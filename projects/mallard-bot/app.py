import asyncio
import os
from telegram import Update, Message, MessageOriginHiddenUser, InputSticker, InlineQueryResultArticle, InputTextMessageContent
from telegram.constants import ParseMode
from telegram.ext import Application, CallbackContext, MessageHandler, filters, InlineQueryHandler
from mallard import Mallard
from stickers import file2sticker, file2animated_sticker, quote2sticker, video2emoji, image2emoji, FilePreprocessType
from content.emoji_dict import EMOJI_LIST
import random
import re
from stickers import VideoQuoteArguments, PhotoQuoteArguments
from exceptions import ProcessingException
from content.bubbles.bubbles import BUBBLES_COUNT
from uuid import uuid4
from responses import ResponseType

mallard = Mallard(random_answer_rate=150)

token = os.environ.get('TG_API_KEY')
admin_id = os.environ.get('TG_ADMIN_ID')


async def convert_file(file_id, context, conversion, **kwargs):
    telegram_file = await context.bot.get_file(file_id)
    file_bytes = await telegram_file.download_as_bytearray()
    return await asyncio.to_thread(conversion, file_bytes, **kwargs)


async def sticker2emoji_echo(update: Update, context: CallbackContext):
    if update.message.reply_to_message is None or update.message.reply_to_message.sticker is None \
            or update.message.reply_to_message.sticker.is_animated or update.message.chat.type != 'private':
        return

    sticker = update.message.reply_to_message.sticker
    print(sticker)
    if sticker.is_video:
        arguments = parse_video_arguments(update.message.text)
        emoji = await convert_file(sticker.file_id, context, video2emoji)
        await update.message.reply_document(document=emoji, filename=str(uuid4()) + '.webm')

    fid = sticker.file_id
    if sticker.is_video and sticker.thumbnail is not None and sticker.thumbnail.file_id is not None:
        fid = sticker.thumbnail.file_id
    emoji = await convert_file(fid, context, image2emoji)
    await update.message.reply_document(document=emoji)


async def download_voice(update: Update, context: CallbackContext, name=str(uuid4())):
    print(update.message)
    if update.message.reply_to_message is None or update.message.reply_to_message.voice is None \
            or update.message.chat.type != 'private':
        return
    print('ok')
    original_message = update.message.reply_to_message
    telegram_file = await context.bot.get_file(original_message.voice.file_id)
    file_bytes = await telegram_file.download_as_bytearray()
    with open(f'voices/{name}.ogg', 'wb') as f:
        f.write(file_bytes)


async def echo(update: Update, context: CallbackContext):
    text = update.message.text if update.message.text is not None else update.message.caption
    if text is None:
        return
    reply, reply_type = mallard.process(text)
    if reply is not None and reply_type is not None:
        if reply_type == ResponseType.STICKER:
            await context.bot.send_sticker(chat_id=update.effective_chat.id, sticker=reply,
                                           reply_to_message_id=update.effective_message.message_id)
        elif reply_type == ResponseType.TEXT:
            await context.bot.send_message(chat_id=update.effective_chat.id, text=reply,
                                           reply_to_message_id=update.effective_message.message_id)
        elif reply_type == ResponseType.VOICE:
            with open(f'voices/{reply}.ogg', 'rb') as f:
                await context.bot.send_voice(chat_id=update.effective_chat.id, voice=f.read(),
                                             reply_to_message_id=update.effective_message.message_id)


async def command(update: Update, context: CallbackContext):
    # print(update)
    if update.message.text[:5] == '/snap':  # you are going to my collection
        await quote(update, context)
    elif update.message.text[:4] == '/qwa' or update.message.text[:4] == '/qva':
        await video_quote(update, context)
    elif update.message.text == f'/help{context.bot.name}' \
            or (update.message.text == f'/help' and update.message.chat.type == 'private'):
        await help(update, context)
    elif update.message.text == '/id':
        await get_sticker_id(update, context)
    elif update.message.text.split(' ')[0] == '/voice':
        await download_voice(update, context, name=update.message.text.split(' ')[1])
    elif update.message.text == '/emoji':
        await sticker2emoji_echo(update, context)


async def help(update: Update, context: CallbackContext):
    reply = 'Кряква умеет превращать кружочки, гифки, видео и картинки в стикеры.\n\
Используйте /qva для анимированных стикеров и /snap для обычных.\n\
Используйте /emoji в ответ на стикер, чтобы преобразовать его в формат, подходящий для кастомных эмодзи (реакций).\n\
При использовании /qva вы также можете использовать параметры:\n\
* s<sec> обрежет видео начиная с sec, sec должно быть целым\n\
* e<sec> обрежет видео до sec, sec должно быть целым\n\
* x<speed> изменит скорость видео на speed, speed может иметь вид 123.123\n\
* r — если указан, видео будет инвертировано\n\
* b<id> — добавляет пузырёк, 1 — справа, 2 — сверху\n\
* j — если указан, преобразует видео/фото в формат, подходящий для кастомных эмодзи\n\
* например /qva s5 e7 x2.5 r обрежет видео с 5 по 7 секунды, инвертирует полученный фрагмент и ускорит его в два с половиной раза\n\
кря-кря.'
    await context.bot.send_message(chat_id=update.effective_chat.id, text=reply,
                                   reply_to_message_id=update.effective_message.message_id)


async def edit_exception(wait_message: Message = None, exception: ProcessingException = None):
    if wait_message is not None and exception is not None:
        await wait_message.edit_text(text=str(exception))


async def reply_exception(reply_message: Message = None, exception: ProcessingException = None,
                          context: CallbackContext = None, update: Update = None):
    if reply_message is not None and exception is not None and context is not None and update is not None:
        await context.bot.send_message(chat_id=update.effective_chat.id, text=str(exception),
                                       reply_to_message_id=update.effective_message.message_id)


def parse_video_arguments(line: str) -> VideoQuoteArguments:
    result = VideoQuoteArguments()
    counts = VideoQuoteArguments(0, 0, 0)
    words = line.split()
    for word in words[1:]:
        if (it := re.search(r's\d+', word)) is not None:
            counts.starting_point += 1
            if counts.starting_point > 1:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 's*', не знаю, что делать :(")
            result.starting_point = int(it.string[1:])
        elif (it := re.search(r'e\d+', word)) is not None:
            counts.end_point += 1
            if counts.end_point > 1:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 'e*', не знаю, что делать :(")
            result.end_point = int(it.string[1:])
        elif (it := re.search(r'x\d+\.?\d*', word)) is not None:
            counts.speed = 1 if counts.speed is None else counts.speed + 1
            if counts.speed > 1:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 'x*', не знаю, что делать :(")
            result.speed = float(it.string[1:])
        elif (it := re.search(r'b\d*', word)) is not None:
            counts.speech_bubble = 1 if counts.speech_bubble is None else counts.speech_bubble + 1
            if counts.speech_bubble > 1:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 'b*', не знаю, что делать :(")
            if len(it.string) > 1:
                bubble_id = int(it.string[1:])
                if bubble_id < 1:
                    raise ProcessingException(
                        exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                        additional_message="Номер не может быть меньше 1.")
                if bubble_id > BUBBLES_COUNT:
                    raise ProcessingException(
                        exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                        additional_message=f"Количество пузырьков в коллекции: {BUBBLES_COUNT}.")

            result.speech_bubble = random.randint(0, BUBBLES_COUNT - 1) if it.string == 'b' else int(it.string[1:]) - 1
        elif word == 'r':
            if counts.reverse is None:
                counts.reverse = True
            else:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 'r*', не знаю, что делать :(")
            result.reverse = True
        elif word == 'j':
            if counts.is_emoji is None:
                counts.is_emoji = True
            else:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 'j*', не знаю, что делать :(")
            result.is_emoji = True
        else:
            raise ProcessingException(
                exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                additional_message=f'"{word}" не подходит как аргумент для команды.')
        if counts.end_point == 1 and counts.starting_point == 0:
            raise ProcessingException(
                exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                additional_message=f'Параметр "e*" должен использоваться только вместе с "s*".')

    return result


def parse_photo_arguments(line: str) -> PhotoQuoteArguments:
    result = PhotoQuoteArguments()
    counts = PhotoQuoteArguments(0)
    words = line.split()
    for word in words[1:]:
        if (it := re.search(r'b\d*', word)) is not None:
            counts.speech_bubble = 1 if counts.speech_bubble is None else counts.speech_bubble + 1
            if counts.speech_bubble > 1:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 'b*', не знаю, что делать :(")
            if len(it.string) > 1:
                bubble_id = int(it.string[1:])
                if bubble_id < 1:
                    raise ProcessingException(
                        exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                        additional_message="Номер не может быть меньше 1.")
                if bubble_id > BUBBLES_COUNT:
                    raise ProcessingException(
                        exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                        additional_message=f"У меня есть только {BUBBLES_COUNT} пузырьков.")

            result.speech_bubble = random.randint(0, BUBBLES_COUNT - 1) if it.string == 'b' else int(it.string[1:]) - 1
        elif word == 'j':
            if counts.is_emoji is None:
                counts.is_emoji = True
            else:
                raise ProcessingException(
                    exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                    additional_message="Несколько вхождений аргумента 'j*', не знаю, что делать :(")
            result.is_emoji = True
        else:
            raise ProcessingException(
                exception_type=ProcessingException.ProcessingExceptionType.arguments_parsing_error,
                additional_message=f'"{word}" не подходит как аргумент для команды.')

    return result


async def video_quote(update: Update, context: CallbackContext):
    waiting_text = "Ваш запрос очень кважен для нас, оставайтесь на линии!"
    message = update.message
    wait_message = await context.bot.send_message(chat_id=update.effective_chat.id, text=waiting_text,
                                                 reply_to_message_id=update.effective_message.message_id)

    sticker = None
    try:
        arguments = None
        if (original_message := message.reply_to_message) is not None:
            arguments = parse_video_arguments(message.text)
            if (video_note := original_message.video_note) is not None:  # circle video
                if (file_id := video_note.file_id) is not None:
                    sticker = await convert_file(
                        file_id, context, file2animated_sticker,
                        preprocess_type=FilePreprocessType.circle, video_arguments=arguments)
            elif (
                    video := original_message.document if original_message.document is not None
                    else original_message.video) is not None:
                if video.file_size > 10485760:  # 10mb
                    raise ProcessingException(exception_type=ProcessingException.ProcessingExceptionType.file_too_large)
                sticker = await convert_file(
                    video.file_id, context, file2animated_sticker,
                    preprocess_type=FilePreprocessType.video_thumb, video_arguments=arguments)
            else:
                raise ProcessingException(exception_type=ProcessingException.ProcessingExceptionType.wrong_source_type)
        if sticker is None:
            await edit_exception(wait_message=wait_message, exception=ProcessingException(
                exception_type=ProcessingException.ProcessingExceptionType.unexpected))
            return

        sticker_set_name = f"animated_stickerpack_by_{context.bot.name[1:]}"
        if arguments is not None and arguments.is_emoji:
            await update.message.reply_document(reply_to_message_id=update.effective_message.message_id,
                                                document=sticker, filename=str(uuid4()) + '.webm')
        else:
            emoji = EMOJI_LIST[random.randint(0, len(EMOJI_LIST) - 1)]
            await context.bot.add_sticker_to_set(
                user_id=admin_id, name=sticker_set_name,
                sticker=InputSticker(sticker=sticker, format="video", emoji_list=[emoji]))
            sticker_set = await context.bot.get_sticker_set(sticker_set_name)
            await update.message.reply_sticker(reply_to_message_id=update.effective_message.message_id,
                                               sticker=sticker_set.stickers[-1].file_id)
            for sticker in sticker_set.stickers[1:]:
                await context.bot.delete_sticker_from_set(sticker.file_id)

        await wait_message.delete()
    except ProcessingException as e:
        await edit_exception(wait_message=wait_message, exception=e)
        return
    except Exception as e:
        print(e)
        await edit_exception(wait_message=wait_message, exception=ProcessingException(
            exception_type=ProcessingException.ProcessingExceptionType.unexpected))
        return


async def quote(update: Update, context: CallbackContext):
    message = update.message
    # print(message)
    sticker = None
    try:
        arguments = None
        if (original_message := message.reply_to_message) is not None:
            arguments = parse_photo_arguments(message.text)
            if (text := original_message.text) is not None:
                author = 'unknown'
                if isinstance(original_message.forward_origin, MessageOriginHiddenUser):
                    author = original_message.forward_origin.sender_user_name
                elif original_message.from_user is not None and original_message.from_user.full_name is not None:
                    author = original_message.from_user.full_name
                sticker = await asyncio.to_thread(quote2sticker, text, author)
            elif (video_note := original_message.video_note) is not None:  # circle video
                if (thumb := video_note.thumbnail) is not None:
                    if (file_id := thumb.file_id) is not None:
                        sticker = await convert_file(
                            file_id, context, file2sticker,
                            preprocess_type=FilePreprocessType.circle, photo_arguments=arguments)
            elif (
                    video := original_message.document if original_message.document is not None else original_message.video) is not None:  # circle video
                if (thumb := video.thumbnail) is not None:
                    if (file_id := thumb.file_id) is not None:
                        sticker = await convert_file(file_id, context, file2sticker, photo_arguments=arguments)
                else:
                    if video.file_size > 10485760:  # 10mb
                        raise ProcessingException(
                            exception_type=ProcessingException.ProcessingExceptionType.file_too_large)
                    sticker = await convert_file(
                        video.file_id, context, file2sticker,
                        preprocess_type=FilePreprocessType.video_thumb, photo_arguments=arguments)
            elif (photo := original_message.photo) is not None and len(photo) > 0:
                if (file_id := photo[-1].file_id) is not None:
                    sticker = await convert_file(file_id, context, file2sticker, photo_arguments=arguments)
            else:
                raise ProcessingException(exception_type=ProcessingException.ProcessingExceptionType.wrong_source_type)
        if sticker is None:
            await reply_exception(reply_message=message, exception=ProcessingException(
                exception_type=ProcessingException.ProcessingExceptionType.unexpected), context=context, update=update)
            return

        sticker_set_name = f"image_stickerpack_by_{context.bot.name[1:]}"
        if arguments is not None and arguments.is_emoji:
            await update.message.reply_document(reply_to_message_id=update.effective_message.message_id,
                                                document=sticker)
        else:
            emoji = EMOJI_LIST[random.randint(0, len(EMOJI_LIST) - 1)]
            await context.bot.add_sticker_to_set(
                user_id=admin_id, name=sticker_set_name,
                sticker=InputSticker(sticker=sticker, format="static", emoji_list=[emoji]))
            sticker_set = await context.bot.get_sticker_set(sticker_set_name)
            await update.message.reply_sticker(reply_to_message_id=update.effective_message.message_id,
                                               sticker=sticker_set.stickers[-1].file_id)
            for sticker in sticker_set.stickers[1:]:
                await context.bot.delete_sticker_from_set(sticker.file_id)
    except ProcessingException as e:
        await reply_exception(reply_message=message, exception=e, update=update, context=context)
        return
    except Exception as e:
        print(e)
        await reply_exception(reply_message=message, exception=ProcessingException(
            exception_type=ProcessingException.ProcessingExceptionType.unexpected), context=context, update=update)
        return


async def get_sticker_id(update: Update, context: CallbackContext):
    if update.message.reply_to_message.sticker is None:
        await context.bot.send_message(chat_id=update.effective_chat.id,
                                       text="Команда должна быть отправлена в ответ на стикер",
                                       reply_to_message_id=update.effective_message.message_id)
    else:
        await context.bot.send_message(chat_id=update.effective_chat.id, text=update.message.reply_to_message.sticker.file_id,
                                       reply_to_message_id=update.effective_message.message_id)


async def inline_query(update: Update, context):
    results = [
        InlineQueryResultArticle(
            id=str(uuid4()),
            title="Кто ты сегодня?",
            thumbnail_url="https://i.ibb.co/6HPDsj7/2023-01-27-01-10-28.jpg",
            input_message_content=InputTextMessageContent(
                f"<i>{mallard.get_creature()}</i>", parse_mode=ParseMode.HTML
            ),
        ),
    ]

    await update.inline_query.answer(results, cache_time=60 * 60 * 3, is_personal=True)


async def post_init(application):
    print('STARTED')
    await application.bot.send_message(chat_id=admin_id, text='Я снова здесь!')


def build_application():
    application = Application.builder().token(token).concurrent_updates(6).post_init(post_init).build()
    application.add_handler(MessageHandler((filters.TEXT | filters.CAPTION) & ~filters.COMMAND, echo))
    application.add_handler(MessageHandler(filters.COMMAND, command))
    application.add_handler(InlineQueryHandler(inline_query))
    return application


def main():
    build_application().run_polling(drop_pending_updates=True, bootstrap_retries=-1)


if __name__ == '__main__':
    main()
