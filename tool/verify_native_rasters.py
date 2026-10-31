#!/usr/bin/env python3
"""Verify native image samples, placement edits and PDF rendering independently."""

import argparse
import importlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image
from pypdf import PdfReader, PdfWriter, Transformation

from verify_native_pdf import REVISION, compare, native_programs, render_pdf


def images(document):
    """Walk image operators in setup resources, private records and drawing order."""
    from inkai.parser.consts import Section
    from inkai.parser.hierarchy_objects import HierarchyObject
    from inkai.parser.operators import ImageOperator, Operator

    def walk(value):
        if isinstance(value, ImageOperator):
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

    return list(walk([document.prolog, document.setup, document.trailer]))


def samples(image):
    """Recover original bytes through the pinned reader, including its alpha tail."""
    assert image.bits == 8 and image.is_binary == 1
    color_length = image.h * image.w * image.image_type
    total = color_length + image.h * image.w * image.alpha_channel_count
    raw = image.data.decoded + image.data.additional_decoded
    assert len(raw) >= total and raw[total:] in (b'', b'\n', b'%_'), (len(raw), total, raw[total:][:30])
    return raw[:color_length], raw[color_length:total]


def reference_pdf(image, bounds, path):
    """Render native CMYK samples using standard PostScript colorimage operators."""
    assert image.image_type == 4 and image.alpha_channel_count == 0
    assert [image.llx, image.lly, image.urx, image.ury] == [0, 0, image.h, image.w]
    colors, _ = samples(image)
    left, bottom, right, top = bounds
    source = path.with_suffix('.reference.ps')
    source.write_text(
        '%!PS-Adobe-3.0\n'
        f'<< /PageSize [{right-left} {top-bottom}] >> setpagedevice\n'
        f'{-left} {-bottom} translate\n'
        f'[{" ".join(map(str, image.matrix))}] concat\n'
        f'{image.h} {image.w} 8 [1 0 0 -1 0 0] currentfile /ASCIIHexDecode filter false 4 colorimage\n'
        + colors.hex() + '>\nshowpage\n', encoding='ascii')
    subprocess.run(['gs', '-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=pdfwrite', '-dAutoFilterColorImages=false', '-dColorImageFilter=/FlateEncode', '-dDownsampleColorImages=false', f'-sOutputFile={path}', str(source)], check=True, capture_output=True)


def main():
    """Require exact decoded samples, unchanged private resources and real rendering."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/native-rasters'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    report = json.loads((args.output / 'report.json').read_text())
    rejections = json.loads((args.output / 'rejections.json').read_text())
    assert {row['file'] for row in rejections} == {'transparent_image.ai', 'image_linked.ai'}
    assert all('raster data boundary' in row['error'] for row in rejections)
    assert {row['file']: len(row['images']) for row in report} == {'raster_ai8.ai': 1, 'raster_v2020.ai': 6, 'empty_cs.ai': 5, 'empty_cs2.ai': 5, 'simple_shapes_cc.ai': 7}
    count, alpha_count, private_count, owners = 0, 0, 0, 0
    renders = []
    for row in report:
        name = row['file']
        before = images(inkai.parse(str(args.output / f'{name}.native.ps')))
        assert len(before) == len(row['images'])
        for expected, actual in zip(row['images'], before):
            assert [actual.h, actual.w, actual.bits, actual.image_type] == [expected['width'], expected['height'], expected['bits'], expected['components']]
            assert actual.matrix == expected['matrix']
            assert [actual.llx, actual.lly, actual.urx, actual.ury] == expected['bounds']
            colors, alpha = samples(actual)
            assert colors == (args.output / f'{expected["prefix"]}.colors.bin').read_bytes()
            assert bool(alpha) == expected['alpha']
            if alpha:
                assert alpha == (args.output / f'{expected["prefix"]}.alpha.bin').read_bytes()
                alpha_count += 1
            private_count += expected['private']
            count += 1
        if row['bounds'] is None:
            continue
        after = images(inkai.parse(str(args.output / f'{name}.translated.ps')))
        assert len(before) == len(after)
        for info, first, second in zip(row['images'], before, after):
            expected = list(first.matrix)
            if info['printable']:
                expected[4] += 37
                expected[5] -= 19
            assert all(abs(a-b) < 1e-10 for a, b in zip(second.matrix, expected))
            assert samples(first) == samples(second)
        original = args.output / f'{name}.reference.pdf'
        if row['pdfBacked']:
            original.write_bytes((args.inkai_source / 'tests/data/ai' / name).read_bytes())
        else:
            reference_pdf(next(image for info, image in zip(row['images'], before) if info['printable']), row['bounds'], original)
        writer = PdfWriter()
        writer.clone_document_from_reader(PdfReader(original))
        writer.pages[0].add_transformation(Transformation().translate(37, -19))
        translated = args.output / f'{name}.expected-translated.pdf'
        writer.write(translated)
        width, height = (1920, 1080) if row['pdfBacked'] else (612, 792)
        for variant, reference in [('rebuilt', original), ('translated', translated)]:
            if row['pdfBacked']:
                programs = native_programs(args.output / f'{name}.{variant}.ai')
                assert programs == [(args.output / f'{name}.{"native" if variant == "rebuilt" else "translated"}.ps').read_bytes()]
                owners += len(programs)
            expected = render_pdf(reference, width, height)
            actual = render_pdf(args.output / f'{name}.{variant}.pdf', width, height)
            difference = compare(expected, actual, args.output / f'{name}.{variant}.difference.png', 0.02)
            renders.append({'file': name, 'variant': variant, 'meanChannelDifference': difference})
            print(f'{name} {variant}: mean channel difference {difference}')
    assert count == 24 and alpha_count == 20 and private_count == 2 and owners == 2
    probe = render_pdf(args.output / 'alpha-probes.pdf', 600, 600)
    probes = [(30, 70, (128, 0, 127)), (70, 70, (0, 64, 191)), (30, 30, (0, 0, 255)), (70, 30, (128, 128, 255)), (5, 50, (0, 0, 255))]
    with Image.open(probe) as image:
        for x, y, expected in probes:
            actual = image.getpixel((x * 6, (100-y) * 6))
            assert max(abs(a-b) for a, b in zip(expected, actual)) <= 1, (x, y, expected, actual)
    # Adobe's retained XIImageMask prolog uses false imagemask polarity: zero
    # samples paint, one samples leave the existing page unchanged.
    prolog = (args.inkai_source / 'tests/data/ai/image_linked_ai8.ai').read_bytes()
    assert b'/XIImageMask {\n\tXIImageWidth XIImageHeight false' in prolog.replace(b'\r\n', b'\n')
    stencil = render_pdf(args.output / 'stencil-probes.pdf', 600, 600)
    with Image.open(stencil) as image:
        assert image.getpixel((30 * 6, 50 * 6)) == (255, 0, 0)
        assert image.getpixel((70 * 6, 50 * 6)) == (0, 0, 255)
    result = {'oracleRevision': REVISION, 'images': count, 'alphaPlanes': alpha_count, 'privateImages': private_count, 'nativeOwners': owners, 'pixelProbes': len(probes) + 2, 'rejectedFiles': [row['file'] for row in rejections], 'renders': renders}
    (args.output / 'independent-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('Native rasters: 24 images, 20 alpha planes, 4 renders and 7 pixel probes passed')


if __name__ == '__main__':
    main()
