#!/usr/bin/env python3
"""Check newly created images with pinned inkai, pypdf and Poppler.

This checks native pixels, link previews, placement and matching host PDF saves;
it does not establish Adobe Illustrator editing or rendering acceptance.
"""

import argparse
import importlib
import io
from pathlib import Path
import re
import subprocess
import sys

from PIL import Image
from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_documents import renders
from verify_native_placements import preview_data
from verify_native_rasters import images, samples


def main():
    """Require exact samples and resources across creation and later embedding."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/image-creation'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    expected_samples = (bytes([255, 0, 0, 0, 255, 0]), bytes([255, 128]))
    host_path = args.output / 'host.pdf'
    host = PdfReader(host_path, strict=True)
    expected_pixels = renders(host_path)
    pixels = Image.open(io.BytesIO(expected_pixels[0]))
    for x, color in ((15, (255, 0, 0)), (25, (127, 255, 127)), (45, (255, 0, 0)), (55, (127, 255, 127))):
        assert pixels.getpixel((x, 30)) == color
    assert pixels.getpixel((5, 30)) == (255, 255, 255)
    for name in ('created', 'embedded'):
        native = (args.output / f'{name}.ps').read_bytes()
        parsed = inkai.parse(str(args.output / f'{name}.ps'))
        rasters = images(parsed)
        assert len(rasters) == (1 if name == 'created' else 2)
        for index, image in enumerate(rasters):
            assert image.matrix == [10, 0, 0, 20, index * 30, 60]
            assert (image.h, image.w, image.image_type, image.alpha_channel_count) == (2, 1, 3, 1)
            assert samples(image) == expected_samples
        if name == 'created':
            preview = preview_data(parsed)
            assert (preview.width, preview.height, preview.bits_per_pixel) == (2, 1, 32)
            assert preview.raw == bytes([255, 255, 0, 0, 128, 0, 255, 0])
            assert b'%%DocumentFiles:Links/picture (1).png\n' in native
            assert b'%%IncludeFile:Links/picture (1).png\n' in native
            header, = re.findall(rb'^\[ ([^\n]+) \] 0.0 0.0 2.0 1.0 4 4 0 (\((?:\\[0-7]{3})+\))`$', native, re.M)
            assert list(map(float, header[0].split())) == [10, 0, 0, -20, 30, 60]
            assert bytes(int(value, 8) for value in re.findall(rb'\\([0-7]{3})', header[1])) == b'Links/picture (1).png'
        else:
            assert b'%%DocumentFiles:' not in native and b'%AI5_BeginPlace' not in native
        path = args.output / f'{name}.ai'
        assert native_programs(path) == [native]
        pdf = PdfReader(path, strict=True)
        assert len(pdf.pages) == 1
        page = pdf.pages[0]
        assert page.get_contents().get_data() == host.pages[0].get_contents().get_data()
        image, = page['/Resources']['/XObject'].values()
        image = image.get_object()
        assert image.get_data() == expected_samples[0]
        assert image['/SMask'].get_data() == expected_samples[1]
        assert page['/PieceInfo']['/Illustrator']['/Private']['/AIMetaData'].get_data() == native[:native.index(b'%%EndComments\n') + len(b'%%EndComments\n')]
        assert renders(path) == expected_pixels
    print('Verified two complete saves: new embedded/link owners, exact RGB/alpha and preview pixels, affine placement, dependency removal, header caches and matching Poppler pixels.')


if __name__ == '__main__':
    main()
