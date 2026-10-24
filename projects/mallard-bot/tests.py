import asyncio
import hashlib
import json
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import AsyncMock, Mock, call
import shutil
import subprocess
import threading

import cv2
import numpy as np
import pytest
from PIL import Image, ImageFont
from telegram import Bot, MessageOriginHiddenUser, Update
from telegram.request import BaseRequest

import app
import stickers
from exceptions import ProcessingException
from mallard import Mallard
from responses import ResponseType

PROJECT = Path(__file__).resolve().parent


@pytest.fixture(autouse=True)
def project_directory(monkeypatch):
    monkeypatch.chdir(PROJECT)


def message(**kwargs):
    fields = dict(text=None, caption=None, reply_to_message=None, sticker=None,
                  video_note=None, document=None, video=None, photo=(), voice=None,
                  forward_origin=None, from_user=None, message_id=42,
                  chat=NS(type='private'), reply_document=AsyncMock(), reply_sticker=AsyncMock())
    fields.update(kwargs)
    return NS(**fields)


def update(msg):
    return NS(message=msg, effective_message=msg, effective_chat=NS(id=123))


@pytest.fixture
def context():
    bot = NS(name='@mallard_test', get_file=AsyncMock(), send_message=AsyncMock(),
             send_sticker=AsyncMock(), send_voice=AsyncMock(), add_sticker_to_set=AsyncMock(),
             get_sticker_set=AsyncMock(), delete_sticker_from_set=AsyncMock())
    return NS(bot=bot)


def test_random_answers(monkeypatch):
    mallard = Mallard(random_answer_rate=100)
    monkeypatch.setattr('random.randrange', lambda rate: rate - 1)
    assert mallard.process('aboba') == (None, None)
    monkeypatch.setattr('random.randrange', lambda rate: 0)
    monkeypatch.setattr('random.choice', lambda choices: choices[0])
    reply, kind = mallard.process('aboba')
    assert reply is not None and kind in ResponseType
    assert mallard.process('') == (None, None)


@pytest.mark.parametrize('text,handler,kwargs', [
    ('/snap', 'quote', {}), ('/snapanything', 'quote', {}),
    ('/qva s1', 'video_quote', {}), ('/qwa', 'video_quote', {}),
    ('/help', 'help', {}), ('/help@mallard_test', 'help', {}),
    ('/id', 'get_sticker_id', {}), ('/voice name', 'download_voice', {'name': 'name'}),
    ('/emoji', 'sticker2emoji_echo', {}),
])
def test_command_routing(monkeypatch, context, text, handler, kwargs):
    callback = AsyncMock()
    monkeypatch.setattr(app, handler, callback)
    event = update(message(text=text))
    asyncio.run(app.command(event, context))
    callback.assert_awaited_once_with(event, context, **kwargs)


def test_group_help_and_unknown_commands(monkeypatch, context):
    callback = AsyncMock()
    monkeypatch.setattr(app, 'help', callback)
    for text in ['/help', '/unknown']:
        asyncio.run(app.command(update(message(text=text, chat=NS(type='group'))), context))
    callback.assert_not_awaited()
    asyncio.run(app.command(update(message(text='/help@mallard_test', chat=NS(type='group'))), context))
    callback.assert_awaited_once()


@pytest.mark.parametrize('kind', list(ResponseType))
def test_echo_replies(monkeypatch, tmp_path, context, kind):
    (tmp_path / 'voices').mkdir()
    (tmp_path / 'voices' / 'reply.ogg').write_bytes(b'voice')
    monkeypatch.chdir(tmp_path)
    process = Mock(return_value=('reply', kind))
    monkeypatch.setattr(app.mallard, 'process', process)
    asyncio.run(app.echo(update(message(caption='caption')), context))
    process.assert_called_once_with('caption')
    args = dict(chat_id=123, reply_to_message_id=42)
    if kind == ResponseType.TEXT:
        context.bot.send_message.assert_awaited_once_with(text='reply', **args)
    elif kind == ResponseType.STICKER:
        context.bot.send_sticker.assert_awaited_once_with(sticker='reply', **args)
    else:
        context.bot.send_voice.assert_awaited_once_with(voice=b'voice', **args)


def test_video_arguments():
    args = app.parse_video_arguments('/qva s5 e7 x2.5 r b2 j')
    assert vars(args) == dict(starting_point=5, end_point=7, speed=2.5, final_length=None,
                              reverse=True, speech_bubble=1, is_emoji=True)
    assert vars(app.parse_photo_arguments('/snap b1 j')) == dict(speech_bubble=0, is_emoji=True)


@pytest.mark.parametrize('text,fragment', [
    ('/qva s1 s2', "'s*'"), ('/qva s0 e1 e2', "'e*'"),
    ('/qva x1 x2', "'x*'"), ('/qva r r', "'r*'"), ('/qva j j', "'j*'"),
    ('/qva b1 b2', "'b*'"), ('/qva b0', 'меньше 1'),
    ('/qva b999', 'Количество пузырьков'), ('/qva e2 s1', 'только вместе'),
    ('/qva nope', 'не подходит'),
])
def test_video_argument_errors(text, fragment):
    with pytest.raises(ProcessingException, match=fragment.replace('*', r'\*')) as error:
        app.parse_video_arguments(text)
    assert str(error.value).startswith('Не ква!\n')


@pytest.mark.parametrize('text', ['/snap b1 b2', '/snap b0', '/snap b999', '/snap j j', '/snap nope'])
def test_photo_argument_errors(text):
    with pytest.raises(ProcessingException):
        app.parse_photo_arguments(text)


@pytest.mark.parametrize('video', [False, True])
def test_sticker_upload_and_cleanup(monkeypatch, context, video):
    converter = AsyncMock(return_value=BytesIO(b'media'))
    monkeypatch.setattr(app, 'convert_file', converter)
    monkeypatch.setattr(app.random, 'randint', lambda low, high: 0)
    original = message(video=NS(file_id='source', file_size=100, thumbnail=None)) if video else message(photo=[NS(file_id='source')])
    event = update(message(text='/qva' if video else '/snap', reply_to_message=original))
    context.bot.get_sticker_set.return_value = NS(stickers=[NS(file_id=x) for x in ['keep', 'old', 'new']])
    waiting = NS(delete=AsyncMock(), edit_text=AsyncMock())
    context.bot.send_message.return_value = waiting
    timeline = Mock()
    timeline.attach_mock(context.bot.add_sticker_to_set, 'add')
    timeline.attach_mock(context.bot.get_sticker_set, 'get')
    timeline.attach_mock(event.message.reply_sticker, 'reply')
    timeline.attach_mock(context.bot.delete_sticker_from_set, 'delete')
    timeline.attach_mock(waiting.delete, 'wait_delete')
    asyncio.run((app.video_quote if video else app.quote)(event, context))
    upload = context.bot.add_sticker_to_set.await_args.kwargs
    assert upload['name'] == ('animated' if video else 'image') + '_stickerpack_by_mallard_test'
    assert upload['sticker'].format == ('video' if video else 'static')
    assert upload['sticker'].emoji_list == (app.EMOJI_LIST[0],)
    event.message.reply_sticker.assert_awaited_once_with(reply_to_message_id=42, sticker='new')
    assert [c[0] for c in timeline.mock_calls] == ['add', 'get', 'reply', 'delete', 'delete'] + (['wait_delete'] if video else [])
    assert context.bot.delete_sticker_from_set.await_args_list == [call('old'), call('new')]


@pytest.mark.parametrize('video', [False, True])
def test_emoji_bypasses_sticker_pack(monkeypatch, context, video):
    monkeypatch.setattr(app, 'convert_file', AsyncMock(return_value=BytesIO(b'media')))
    original = message(video=NS(file_id='source', file_size=100, thumbnail=None)) if video else message(photo=[NS(file_id='source')])
    event = update(message(text='/qva j' if video else '/snap j', reply_to_message=original))
    context.bot.send_message.return_value = NS(delete=AsyncMock())
    asyncio.run((app.video_quote if video else app.quote)(event, context))
    event.message.reply_document.assert_awaited_once()
    context.bot.add_sticker_to_set.assert_not_awaited()


@pytest.mark.parametrize('video', [False, True])
def test_oversized_media_error(context, video):
    original = message(video=NS(file_id='source', file_size=10485761, thumbnail=None))
    waiting = NS(edit_text=AsyncMock())
    context.bot.send_message.return_value = waiting
    event = update(message(text='/qva' if video else '/snap', reply_to_message=original))
    asyncio.run((app.video_quote if video else app.quote)(event, context))
    if video:
        waiting.edit_text.assert_awaited_once_with(text='Не ква!\nФайл слишком большой :(')
    else:
        assert context.bot.send_message.await_args.kwargs['text'] == 'Не ква!\nФайл слишком большой :('
    context.bot.get_file.assert_not_awaited()


@pytest.mark.parametrize('hidden,expected', [(True, 'Hidden sender'), (False, 'Forwarder')])
def test_quote_author(monkeypatch, context, hidden, expected):
    render = Mock(return_value=BytesIO(b'image'))
    monkeypatch.setattr(app, 'quote2sticker', render)
    origin = MessageOriginHiddenUser(datetime.now(timezone.utc), 'Hidden sender') if hidden else None
    original = message(text='quote', forward_origin=origin, from_user=NS(full_name='Forwarder'))
    asyncio.run(app.quote(update(message(text='/snap j', reply_to_message=original)), context))
    render.assert_called_once_with('quote', expected)


@pytest.mark.parametrize('source,preprocess', [
    ('video_note', stickers.FilePreprocessType.circle),
    ('video', stickers.FilePreprocessType.default),
    ('document', stickers.FilePreprocessType.default),
])
def test_snap_thumbnail(monkeypatch, context, source, preprocess):
    convert = AsyncMock(return_value=BytesIO(b'image'))
    monkeypatch.setattr(app, 'convert_file', convert)
    original = message(**{source: NS(thumbnail=NS(file_id='thumb'))})
    asyncio.run(app.quote(update(message(text='/snap j', reply_to_message=original)), context))
    assert convert.await_args.args == ('thumb', context, app.file2sticker)
    assert convert.await_args.kwargs.get('preprocess_type', stickers.FilePreprocessType.default) == preprocess


def test_video_sticker_emoji_still_sends_both_formats(monkeypatch, context):
    converter = AsyncMock(return_value=BytesIO(b'emoji'))
    monkeypatch.setattr(app, 'convert_file', converter)
    original = message(sticker=NS(is_animated=False, is_video=True, file_id='video', thumbnail=NS(file_id='thumb')))
    event = update(message(text='/emoji', reply_to_message=original))
    asyncio.run(app.sticker2emoji_echo(event, context))
    assert [c.args[0] for c in converter.await_args_list] == ['video', 'thumb']
    assert event.message.reply_document.await_count == 2
    assert event.message.reply_document.await_args_list[0].kwargs['filename'].endswith('.webm')


@pytest.mark.parametrize('handler', ['download_voice', 'sticker2emoji_echo'])
def test_private_chat_restrictions(context, handler):
    event = update(message(text='/emoji', chat=NS(type='group'), reply_to_message=message(
        voice=NS(file_id='voice'), sticker=NS(is_animated=False))))
    asyncio.run(getattr(app, handler)(event, context))
    context.bot.get_file.assert_not_awaited()


def test_voice_download(monkeypatch, tmp_path, context):
    monkeypatch.chdir(tmp_path)
    (tmp_path / 'voices').mkdir()
    download = AsyncMock(return_value=bytearray(b'voice'))
    context.bot.get_file.return_value = NS(download_as_bytearray=download)
    event = update(message(reply_to_message=message(voice=NS(file_id='voice-id'))))
    asyncio.run(app.download_voice(event, context, name='saved'))
    context.bot.get_file.assert_awaited_once_with('voice-id')
    download.assert_awaited_once_with()
    assert (tmp_path / 'voices/saved.ogg').read_bytes() == b'voice'


def test_inline_query(monkeypatch, context):
    monkeypatch.setattr(app.mallard, 'get_creature', lambda: 'creature')
    query = NS(answer=AsyncMock())
    asyncio.run(app.inline_query(NS(inline_query=query), context))
    args = query.answer.await_args
    assert args.kwargs == {'cache_time': 10800, 'is_personal': True}
    article = args.args[0][0]
    assert article.title == 'Кто ты сегодня?'
    assert article.input_message_content.message_text == '<i>creature</i>'
    assert article.input_message_content.parse_mode == 'HTML'
    assert article.thumbnail_url == 'https://i.ibb.co/6HPDsj7/2023-01-27-01-10-28.jpg'


def test_application_startup_and_filters(monkeypatch, context):
    monkeypatch.setattr(app, 'token', '123456:ABCDEF')
    application = app.build_application()
    assert application.concurrent_updates == 6
    assert application.post_init is app.post_init
    echo, command, inline = application.handlers[0]
    assert (echo.callback, command.callback, inline.callback) == (app.echo, app.command, app.inline_query)
    for text, caption, is_command in [('hello', None, False), (None, 'caption', False), ('/qva', None, True)]:
        event = Update.de_json(dict(update_id=1, message=dict(message_id=42, date=1,
            chat=dict(id=123, type='private'), text=text, caption=caption,
            entities=[dict(type='bot_command', offset=0, length=4)] if is_command else [])), None)
        assert bool(echo.check_update(event)) is not is_command
        assert bool(command.check_update(event)) is is_command
    asyncio.run(app.post_init(NS(bot=context.bot)))
    context.bot.send_message.assert_awaited_once_with(chat_id=app.admin_id, text='Я снова здесь!')
    application_mock = Mock()
    monkeypatch.setattr(app, 'build_application', lambda: application_mock)
    app.main()
    application_mock.run_polling.assert_called_once_with(drop_pending_updates=True, bootstrap_retries=-1)


def test_update_concurrency_bound(monkeypatch):
    monkeypatch.setattr(app, 'token', '123456:ABCDEF')
    application = app.build_application()

    async def scenario():
        active = peak = 0
        saturated, release = asyncio.Event(), asyncio.Event()

        async def work():
            nonlocal active, peak
            active += 1
            peak = max(peak, active)
            if active == 6:
                saturated.set()
            await release.wait()
            active -= 1

        async with application.update_processor as processor:
            tasks = [asyncio.create_task(processor.process_update(None, work())) for _ in range(8)]
            try:
                await asyncio.wait_for(saturated.wait(), 3)
                assert active == peak == 6
            finally:
                release.set()
                await asyncio.gather(*tasks)
            assert peak == 6

    asyncio.run(scenario())


def test_conversion_does_not_block_replies(monkeypatch, context):
    context.bot.get_file.return_value = NS(download_as_bytearray=AsyncMock(return_value=b'data'))
    monkeypatch.setattr(app.mallard, 'process', lambda text: ('reply', ResponseType.TEXT))

    async def scenario():
        loop = asyncio.get_running_loop()
        started, release = asyncio.Event(), threading.Event()

        def slow_conversion(data):
            assert data == b'data'
            loop.call_soon_threadsafe(started.set)
            assert release.wait(3)
            return BytesIO(b'converted')

        task = asyncio.create_task(app.convert_file('file-id', context, slow_conversion))
        try:
            await asyncio.wait_for(started.wait(), 3)
            await app.echo(update(message(text='hello')), context)
            context.bot.send_message.assert_awaited_once()
            assert not task.done()
        finally:
            release.set()
            result = await task
        assert result.getvalue() == b'converted'
        context.bot.get_file.assert_awaited_once_with('file-id')

    asyncio.run(scenario())


def test_snap_with_real_telegram_objects(monkeypatch, image_bytes):
    """Exercise downloads, multipart uploads, and message replies without network I/O."""
    requests = []

    class OfflineRequest(BaseRequest):
        @property
        def read_timeout(self):
            return 5

        async def initialize(self):
            pass

        async def shutdown(self):
            pass

        async def do_request(self, url, method, request_data=None, **kwargs):
            endpoint = url.rsplit('/', 1)[-1]
            parameters = request_data.parameters if request_data else {}
            requests.append((endpoint, parameters))
            if endpoint == 'source.png':
                return 200, image_bytes
            sticker = dict(file_id='new', file_unique_id='unique-new', width=512, height=256,
                           type='regular', is_animated=False, is_video=False)
            if endpoint == 'getMe':
                result = dict(id=123456, is_bot=True, first_name='Mallard', username='mallard_test')
            elif endpoint == 'getFile':
                result = dict(file_id='source', file_unique_id='unique-source', file_path='source.png')
            elif endpoint == 'getStickerSet':
                result = dict(name='image_stickerpack_by_mallard_test', title='Mallard',
                              sticker_type='regular', stickers=[dict(sticker, file_id='keep'), sticker])
            elif endpoint == 'sendSticker':
                result = dict(message_id=43, date=1, chat=dict(id=123, type='private'), sticker=sticker)
            elif endpoint in ['addStickerToSet', 'deleteStickerFromSet']:
                result = True
            else:
                raise AssertionError(f'Unexpected API call: {endpoint}')
            return 200, json.dumps(dict(ok=True, result=result)).encode()

    monkeypatch.setattr(app, 'admin_id', '123')

    async def scenario():
        async with Bot('123456:ABCDEF', request=OfflineRequest(), get_updates_request=OfflineRequest()) as bot:
            original = dict(message_id=41, date=1, chat=dict(id=123, type='private'),
                            photo=[dict(file_id='source', file_unique_id='unique-source', width=240, height=120)])
            event = Update.de_json(dict(update_id=1, message=dict(
                message_id=42, date=1, chat=dict(id=123, type='private'), text='/snap',
                reply_to_message=original)), bot)
            await app.quote(event, NS(bot=bot))

    asyncio.run(scenario())
    assert [name for name, _ in requests] == [
        'getMe', 'getFile', 'source.png', 'addStickerToSet', 'getStickerSet', 'sendSticker', 'deleteStickerFromSet']
    upload = dict(requests)['addStickerToSet']
    assert upload['user_id'] == '123'
    assert upload['name'] == 'image_stickerpack_by_mallard_test'
    assert upload['sticker']['format'] == 'static'
    assert upload['sticker']['emoji_list'][0] in app.EMOJI_LIST
    reply = dict(requests)['sendSticker']
    assert reply['sticker'] == 'new'
    assert reply['reply_parameters']['message_id'] == 42


@pytest.fixture
def image_bytes():
    image = np.full((120, 240, 3), (30, 60, 90), dtype=np.uint8)
    return cv2.imencode('.png', image)[1].tobytes()


def decode(image):
    return cv2.imdecode(np.frombuffer(image.getvalue(), dtype=np.uint8), cv2.IMREAD_UNCHANGED)


@pytest.mark.parametrize('circle,emoji,bubble', [(False, False, None), (False, True, None),
    (True, False, None), (True, True, None), (False, False, 0), (True, False, 1)])
def test_image_conversion(image_bytes, circle, emoji, bubble):
    arguments = stickers.PhotoQuoteArguments(speech_bubble=bubble, is_emoji=emoji)
    result = decode(stickers.file2sticker(image_bytes, photo_arguments=arguments,
        preprocess_type=stickers.FilePreprocessType.circle if circle else stickers.FilePreprocessType.default))
    size = 100 if emoji else 512
    assert result.shape == (size if circle else size // 2, size, 4)
    if bubble is None:
        assert tuple(result[result.shape[0] // 2, size // 2]) == (30, 60, 90, 255)
        assert result[0, 0, 3] == (0 if circle else 255)


def test_image_to_emoji(image_bytes):
    result = decode(stickers.image2emoji(image_bytes))
    assert result.shape == (100, 100, 4)
    assert tuple(result[50, 50]) == (30, 60, 90, 255)


def test_legacy_text_measurement_and_rendering():
    # Pillow's bundled TrueType font keeps this test independent of host fonts.
    font = ImageFont.load_default(size=28)
    assert stickers._textsize('A', font) == (font.getbbox('A')[2], font.getbbox('A')[3])
    text = 'Hello\nworld'
    assert stickers._textsize(text, font) == (
        max(stickers._textsize(line, font)[0] for line in text.split('\n')),
        2 * (font.getbbox('A')[3] + 4) - 4)
    font.path.seek(0)
    result = stickers.quote2sticker('A quote with words ' * 20, 'Author', font_file=font.path)
    assert Image.open(result).size == (512, 384)


def test_quote_pixels_match_pillow_9(monkeypatch):
    # Captured from Pillow 9.2 with the same bundled Aileron font and background.
    font = ImageFont.load_default(size=28)
    font.path.seek(0)
    monkeypatch.setattr(stickers.random, 'randint', lambda low, high: 0)
    result = stickers.quote2sticker('A short quote', 'Author', font_file=font.path)
    assert hashlib.sha256(Image.open(result).tobytes()).hexdigest() == (
        'fcb1fcef971db24364057d27dcaae1c448022eef1169810241fa2e044b875786')


@pytest.fixture(scope='module')
def video_bytes(tmp_path_factory):
    assert shutil.which('ffmpeg'), 'ffmpeg is required for media regression tests'
    directory = tmp_path_factory.mktemp('videos')
    videos = {}
    for size in ['160x120', '128x128']:
        path = directory / (size + '.mp4')
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i',
            f'testsrc2=size={size}:rate=6:duration=1.5', '-c:v', 'mpeg4', str(path)], check=True)
        videos[size] = path.read_bytes()
    return videos


@pytest.mark.parametrize('circle,options', [
    (False, {}), (False, dict(is_emoji=True)),
    (False, dict(starting_point=0, end_point=1, speed=2, reverse=True)),
    (False, dict(speech_bubble=0)), (True, {}), (True, dict(is_emoji=True, speech_bubble=1)),
])
def test_video_conversion(video_bytes, tmp_path, circle, options):
    source = video_bytes['128x128' if circle else '160x120']
    result = stickers.file2animated_sticker(source,
        preprocess_type=stickers.FilePreprocessType.circle if circle else stickers.FilePreprocessType.video_thumb,
        video_arguments=stickers.VideoQuoteArguments(**options))
    path = tmp_path / 'sticker.webm'
    path.write_bytes(result.getvalue())
    probe = subprocess.run(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)],
                           capture_output=True, text=True, check=True)
    import json
    data = json.loads(probe.stdout)
    stream = data['streams'][0]
    size = 100 if options.get('is_emoji') else 512
    assert stream['codec_name'] == 'vp9'
    assert (stream['width'], stream['height']) == (size, size if circle else size * 3 // 4)
    assert 0 < float(data['format']['duration']) <= 3
    if circle:
        assert stream['tags']['alpha_mode'] == '1'


def test_video_thumbnail_and_emoji(video_bytes, tmp_path):
    source = video_bytes['160x120']
    assert decode(stickers.file2sticker(source, preprocess_type=stickers.FilePreprocessType.video_thumb)).shape == (384, 512, 4)
    result = stickers.video2emoji(source)
    path = tmp_path / 'emoji.webm'
    path.write_bytes(result.getvalue())
    cap = cv2.VideoCapture(str(path))
    try:
        assert cap.read()[1].shape[:2] == (100, 100)
    finally:
        cap.release()
