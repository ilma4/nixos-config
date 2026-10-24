"""Exercise the production image without installing test dependencies."""

import json
import os
from io import BytesIO
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile

assert Path.cwd() == Path('/app')
assert os.getuid() == os.getgid() == 805
sys.path.insert(0, '/app')

import app
import cv2
import numpy as np
from PIL import Image
import stickers

assert app.mallard is not None
assert Path('frame.dat').is_file()
assert Path('mask.dat').is_file()
assert all(Path(name).is_file() for name in stickers.BUBBLE_NAMES)
assert ssl.create_default_context().cert_store_stats()['x509_ca'] > 0
assert subprocess.check_output(['/bin/sh', '-c', 'printf shell-ok']) == b'shell-ok'

with tempfile.NamedTemporaryFile(dir='voices', suffix='.ogg') as voice:
    voice.write(b'voice-write-test')
    voice.flush()
    assert Path(voice.name).read_bytes() == b'voice-write-test'

image = BytesIO()
Image.new('RGB', (160, 120), (30, 60, 90)).save(image, format='PNG')
static = stickers.file2sticker(image.getvalue())
assert Image.open(static).size == (512, 384)
assert cv2.imdecode(np.frombuffer(static.getvalue(), dtype=np.uint8), cv2.IMREAD_UNCHANGED) is not None

with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'source.mp4'
    subprocess.run([
        'ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
        'testsrc2=size=160x120:rate=6:duration=1.5', '-c:v', 'mpeg4', str(source),
    ], check=True)
    output = stickers.file2animated_sticker(source.read_bytes())
    target = Path(directory) / 'sticker.webm'
    target.write_bytes(output.getvalue())
    probe = subprocess.run([
        'ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(target),
    ], capture_output=True, text=True, check=True)
    result = json.loads(probe.stdout)
    stream = result['streams'][0]
    assert stream['codec_name'] == 'vp9'
    assert (stream['width'], stream['height']) == (512, 384)
    assert 0 < float(result['format']['duration']) <= 3

print('Container smoke test passed')
