#!/usr/bin/env python3
"""Verify relinked native paths, previews and unchanged resources."""

import argparse
import hashlib
import importlib
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageOps

from corpus_support import REVISION
from verify_native_placements import SOURCE_REVISION, preview_data
from verify_native_rasters import images, samples


def literal_path(program):
    """Decode the checked placement operand using Ghostscript's string reader."""
    match = re.search(rb'%AI5_BeginPlace\s+%%FileType: 1\s+(\[[^\]]+\][^`]+)`', program)
    assert match
    result = subprocess.run(['gs', '-q', '-dSAFER', '-dNODISPLAY', '-dBATCH', '-c', match[1].decode('ascii') + ' print clear quit'], check=True, capture_output=True)
    return result.stdout


def main():
    """Require independent byte, resource, filename and preview agreement."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/native-relinks'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    original = (args.output / 'original.ps').read_bytes()
    assert hashlib.sha256(original).hexdigest() == 'a67054a916e7791641826237b55ab04919443bdb282126dbc2a27e07dd768d02'
    assert original == subprocess.check_output(['git', '-C', str(args.inkai_source), 'show', SOURCE_REVISION + ':tests/data/ai/image_linked.ai'])
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    parsed = inkai.parse(str(args.output / 'original.ps'))
    before = preview_data(parsed)
    expected = ImageOps.invert(Image.frombytes('RGBA', (before.width, before.height), before.raw, 'raw', 'ARGB').convert('RGB'))
    destination = args.output / 'assets' / 'relinked-apple.png'
    destination.parent.mkdir(parents=True, exist_ok=True)
    expected.save(destination)
    # The generated resource is the actual file named by both native outputs.
    report = json.loads((args.output / 'report.json').read_text())
    assert bytes(report['pathBytes']) == str(destination.resolve()).encode('utf8')
    assert bytes(report['relativeDirectoryBytes']) == b'assets'
    assert (report['width'], report['height']) == expected.size
    assert report['variants'] == ['with-preview', 'without-preview']
    before_images = images(parsed)
    assert len(before_images) == 5
    expected_path = bytes(report['pathBytes'])
    original_path = literal_path(original)
    assert original_path != expected_path
    for variant in report['variants']:
        program = (args.output / f'{variant}.native.ps').read_bytes()
        decoded = inkai.parse(str(args.output / f'{variant}.native.ps'))
        assert literal_path(program) == expected_path
        assert original_path not in program
        assert re.findall(rb'^%%DocumentFiles:([^\r\n]+)', program, re.M) == [expected_path]
        assert re.findall(rb'^%%IncludeFile:([^\r\n]+)', program, re.M) == [expected_path]
        relative = re.search(rb'%AI28_BeginPlacedRelativePath\s+(\([^\n]+\))\s+%AI28_EndPlacedRelativePath', program)
        assert relative
        decoded_relative = subprocess.run(['gs', '-q', '-dSAFER', '-dNODISPLAY', '-dBATCH', '-c', relative[1].decode('ascii') + ' print quit'], check=True, capture_output=True).stdout
        assert decoded_relative == b'assets'
        # The complete source around the edit is untouched, including numeric
        # spelling, ruler-origin geometry, setup resources and object metadata.
        placement = rb'(%AI5_BeginPlace\s+%%FileType: 1\s+\[[^\]]+\] [^\(]+)\('
        assert re.search(placement, program)[1] == re.search(placement, original)[1]
        assert program[program.index(b'%AI5_EndPlace'):] == original[original.index(b'%AI5_EndPlace'):]
        after_images = images(decoded)
        assert len(after_images) == 5
        for first, second in zip(before_images, after_images):
            assert samples(first) == samples(second) and first.matrix == second.matrix
        if variant == 'with-preview':
            preview = preview_data(decoded)
            assert (preview.width, preview.height, preview.bits_per_pixel) == (expected.width, expected.height, 32)
            rgba = Image.frombytes('RGBA', expected.size, preview.raw, 'raw', 'ARGB')
            assert rgba.getchannel('A').getextrema() == (255, 255)
            assert rgba.convert('RGB').tobytes() == expected.tobytes()
        else:
            assert b'%AI26_BeginPlacedObjectPreview' not in program
    (args.output / 'independent-report.json').write_text(json.dumps({'sourceRevision': SOURCE_REVISION, 'readerRevision': REVISION, 'unchangedSetupImages': 5, 'nativePrograms': 2}, indent=2) + '\n')
    print('CC relinking: exact paths, refreshed/removed preview, five unchanged images, two native programs passed')


if __name__ == '__main__':
    main()
