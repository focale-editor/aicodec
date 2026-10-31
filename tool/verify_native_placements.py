#!/usr/bin/env python3
"""Verify CC previews, placement geometry and host-resolved embedding independently."""

import argparse
import hashlib
import importlib
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

from verify_native_pdf import REVISION, compare, native_programs, render_pdf
from verify_native_rasters import images, samples

SOURCE_REVISION = '41bac2967b0f2bd80bc14fce9c8c0dea01283536'


def preview_data(document):
    """Find the independently parsed preview without interpreting its pixels."""
    from inkai.parser.consts import ImageData, Section
    from inkai.parser.hierarchy_objects import HierarchyObject
    from inkai.parser.operators import Operator

    def walk(value):
        if isinstance(value, ImageData):
            yield value
        elif isinstance(value, Operator):
            return
        elif isinstance(value, Section):
            yield from walk(value.children)
        elif isinstance(value, HierarchyObject):
            yield from walk(vars(value))
        elif isinstance(value, dict):
            for child in value.values():
                yield from walk(child)
        elif isinstance(value, (list, tuple)):
            for child in value:
                yield from walk(child)
    found = list(walk([document.prolog, document.setup, document.trailer]))
    assert len(found) == 1
    return found[0]


def reference_pdf(source, width, height, components, pixels, path):
    """Have Ghostscript execute original placement operands with standard image operators."""
    header = re.search(rb'%AI5_BeginPlace\s+%%FileType: 1\s+(\[[^\]]+\][^`]+)`', source)
    assert header
    # Only the pinned producer's literal array, scalar operands and filename are
    # evaluated. Its drawing program and external filename are never executed.
    code = b'''%!PS-Adobe-3.0
<< /PageSize [612 792] >> setpagedevice
0 792 translate
''' + header[1] + b'''
pop pop pop pop
/upper exch def /right exch def /lower exch def /left exch def
concat
left lower translate
right left sub upper lower sub scale
0 0 1 1 rectclip
''' + f'{width} {height} 8 [{width} 0 0 {height} 0 0] currentfile /ASCIIHexDecode filter false {components} colorimage\n'.encode() + pixels.hex().encode() + b'>\nshowpage\n'
    program = path.with_suffix('.ps')
    program.write_bytes(code)
    subprocess.run(['gs', '-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=pdfwrite', '-dAutoFilterColorImages=false', '-dColorImageFilter=/FlateEncode', '-dDownsampleColorImages=false', f'-sOutputFile={path}', str(program)], check=True, capture_output=True)


def main():
    """Require pinned bytes, opaque ARGB rows and complete-page reference agreement."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/native-placements'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    original = (args.output / 'original.ps').read_bytes()
    assert hashlib.sha256(original).hexdigest() == 'a67054a916e7791641826237b55ab04919443bdb282126dbc2a27e07dd768d02'
    assert original == subprocess.check_output(['git', '-C', str(args.inkai_source), 'show', SOURCE_REVISION + ':tests/data/ai/image_linked.ai'])
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    parsed = inkai.parse(str(args.output / 'original.ps'))
    preview = preview_data(parsed)
    report = json.loads((args.output / 'report.json').read_text())
    assert report['preview'] == {'width': 256, 'height': 271, 'rowBytes': 1024, 'bits': 32, 'format': 17}
    assert [preview.width, preview.height, preview.bits_per_pixel] == [256, 271, 32]
    raw = preview.raw
    assert raw == (args.output / 'preview.argb').read_bytes() and len(raw) == 277504
    rgba = Image.frombytes('RGBA', (256, 271), raw, 'raw', 'ARGB')
    rgba.save(args.output / 'preview-samples.png')
    assert rgba.getchannel('A').getextrema() == (255, 255)
    rgb = rgba.convert('RGB').tobytes()
    before_images = images(parsed)
    assert len(before_images) == 5
    host = images(inkai.parse(str(args.output / 'host-source.ps')))[-1]
    host_colors, host_alpha = samples(host)
    assert (host.h, host.w, host.image_type) == (800, 848, 4) and not host_alpha
    translated = (args.output / 'translated.ps').read_bytes()
    assert preview_data(inkai.parse(str(args.output / 'translated.ps'))).raw == raw
    # The original document's box independently confirms the raster placement's
    # downward local y direction, including its nonzero ruler-origin coordinates.
    placement = re.search(rb'\[([^\]]+)\] (7885 7795 8685 8643) 4 4 0\s+\(', original)
    assert placement
    matrix = list(map(float, placement[1].split()))
    assert matrix == report['matrix'] and report['bounds'] == [7885, 7795, 8685, 8643]
    moved = re.search(rb'\[([^\]]+)\] (7885 7795 8685 8643) 4 4 0\s+\(', translated)
    assert moved
    expected_matrix = [*matrix[:4], matrix[4] + 37, matrix[5] - 19]
    assert list(map(float, moved[1].split())) == expected_matrix
    corners = [(matrix[0]*x + matrix[2]*y + matrix[4], matrix[1]*x + matrix[3]*y + matrix[5]) for x,y in [(7885,7795),(8685,7795),(7885,8643),(8685,8643)]]
    actual_bounds = [min(x for x,y in corners), min(y for x,y in corners), max(x for x,y in corners), max(y for x,y in corners)]
    expected_bounds = list(map(float, re.search(rb'%%HiResBoundingBox: ([^\n]+)', original)[1].split()))
    assert max(abs(a-b) for a,b in zip(actual_bounds, expected_bounds)) < 1e-8
    assert bytes(report['pathBytes']) == b'C:\\Users\\me\\Downloads\\Lobo_(apple)_(cropped).jpg'
    assert report['relativeDirectoryBytes'] == []
    renders = []
    assert {row['variant'] for row in report['variants']} == {'preview', 'resolved', 'translated'} and len(report['variants']) == 3
    for row in report['variants']:
        variant = row['variant']
        program = (args.output / f'{variant}.embedded.ps').read_bytes()
        assert b'%AI5_BeginPlace' not in program and b'%%DocumentFiles:' not in program and b'%%IncludeFile:' not in program
        decoded = images(inkai.parse(str(args.output / f'{variant}.embedded.ps')))
        assert len(decoded) == 6
        for before, after in zip(before_images, decoded[:5]):
            assert samples(before) == samples(after) and before.matrix == after.matrix
        last = decoded[-1]
        expected = (rgb, bytes([255]) * (256*271)) if variant == 'preview' else (host_colors, b'')
        assert samples(last) == expected
        source = translated if variant == 'translated' else original
        reference = args.output / f'{variant}.reference.pdf'
        reference_pdf(source, row['width'], row['height'], row['components'], expected[0], reference)
        difference = compare(render_pdf(reference, 612, 792), render_pdf(args.output / f'{variant}.pdf', 612, 792), args.output / f'{variant}.difference.png', 0.02)
        renders.append({'variant': variant, 'meanChannelDifference': difference})
        print(f'{variant}: mean channel difference {difference}')
    assert native_programs(args.output / 'synchronized.ai') == [(args.output / 'resolved.embedded.ps').read_bytes()]
    synchronized = compare(render_pdf(args.output / 'resolved.pdf', 612, 792), render_pdf(args.output / 'synchronized.ai', 612, 792), args.output / 'synchronized.difference.png', 0.02)
    (args.output / 'independent-report.json').write_text(json.dumps({'sourceRevision': SOURCE_REVISION, 'readerRevision': REVISION, 'previewBytes': len(raw), 'unchangedSetupImages': 5, 'renders': renders, 'synchronizedDifference': synchronized}, indent=2) + '\n')
    print('CC placement: exact preview, three embedded variants, four page comparisons and synchronized native bytes passed')


if __name__ == '__main__':
    main()
