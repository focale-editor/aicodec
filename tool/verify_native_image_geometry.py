#!/usr/bin/env python3
"""Verify native image matrices, retained pixels and affine PDF appearances."""

import argparse
import hashlib
import importlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image
from pypdf import PdfReader, PdfWriter, Transformation

from verify_native_pdf import REVISION, compare, native_programs, render_pdf
from verify_native_placements import preview_data, reference_pdf as linked_reference
from verify_native_raster_edits import identities
from verify_native_rasters import images, reference_pdf as raster_reference, samples


def compose(first, second):
    """Multiply affine matrices using independent homogeneous coordinates."""
    def rows(value):
        a, b, c, d, x, y = value
        return [[a, c, x], [b, d, y], [0, 0, 1]]
    left, right = rows(first), rows(second)
    product = [[sum(left[i][k] * right[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return [product[0][0], product[1][0], product[0][1], product[1][1], product[0][2], product[1][2]]


def transformed_pdf(source, target, transform, bounds):
    """Apply the drawing transform to the independent original PDF appearance."""
    a, b, c, d, x, y = transform
    left, bottom, _, _ = bounds
    page_transform = (a, b, c, d, a * left + c * bottom + x - left, b * left + d * bottom + y - bottom)
    writer = PdfWriter()
    writer.clone_document_from_reader(PdfReader(source))
    writer.pages[0].add_transformation(Transformation(page_transform))
    writer.write(target)


def retained(program):
    """Mask only editable geometry fields in these pinned native fixtures.

    All image samples are checked separately through the independent binary
    reader, so matching bytes inside a sample cannot hide a sample change.
    """
    matrix = rb'(?m)^((?:%_)?)[ \t]*\[[^\]\r\n]+\](?=(?:[^\r\n]* Xh\r?\n|[^\r\n]*\r?\n(?:%_)?%%BeginData:))'
    program = re.sub(matrix, rb'\1[MATRIX]', program)
    program = re.sub(rb'(?m)^((?:%_)?\[[^\]\r\n]+\])(?= 7885 7795 8685 8643 4 4 0)', b'[MATRIX]', program)
    program = re.sub(rb'(?m)^%%(?:HiResBoundingBox|BoundingBox|PageBoundingBox):[^\r\n]+', b'%%BOUNDS', program)
    return re.sub(rb'\([-+0-9.eE]+\)(?= /String \(BBAccumRotation\))', b'(ANGLE)', program)


def check_angles(before, after, transform, last_only=False):
    """Verify explicit frame-axis angles while retaining other source metadata."""
    pattern = rb'\(([-+0-9.eE]+)\) /String \(BBAccumRotation\)'
    old, new = re.findall(pattern, before), re.findall(pattern, after)
    assert len(old) == len(new)
    if last_only:
        # The fixture's final tag belongs to the sole linked object. Earlier
        # tags belong to setup styles and must remain unchanged.
        assert old[:-1] == new[:-1]
        old, new = old[-1:], new[-1:]
    for first, second in zip(old, new):
        angle = float(first)
        x, y = math.cos(angle), math.sin(angle)
        expected = math.atan2(transform[1] * x + transform[3] * y, transform[0] * x + transform[2] * y)
        assert abs(float(second) - expected) <= 0.0000005


def main():
    """Require independently recovered native geometry and complete-page agreement."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/native-image-geometry'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    report = json.loads((args.output / 'report.json').read_text())
    assert {row['file'] for row in report} == {'raster_ai8.ai', 'raster_v2020.ai', 'empty_cs.ai', 'empty_cs2.ai', 'simple_shapes_cc.ai', 'linked'}
    comparisons, count, owners = [], 0, 0
    for row in report:
        name = row['file']
        original_path = args.output / f'{name}.original.ps'
        original = original_path.read_bytes()
        parsed = inkai.parse(str(original_path))
        before = images(parsed)
        assert set(row['transforms']) == {'resize', 'rotate', 'reflect-shear'}
        reference = args.output / f'{name}.reference.pdf'
        linked = name == 'linked'
        if linked:
            assert hashlib.sha256(original).hexdigest() == 'a67054a916e7791641826237b55ab04919443bdb282126dbc2a27e07dd768d02'
            preview = preview_data(parsed)
            rgb = Image.frombytes('RGBA', (preview.width, preview.height), preview.raw, 'raw', 'ARGB').convert('RGB').tobytes()
            linked_reference(original, preview.width, preview.height, 3, rgb, reference)
            pattern = rb'\[([^\]]+)\] 7885 7795 8685 8643 4 4 0'
            original_matrix = list(map(float, re.search(pattern, original)[1].split()))
        else:
            pinned = args.inkai_source / 'tests/data/ai' / name
            if row['pdfBacked']:
                assert inkai.extract(str(pinned)) == original
            else:
                assert pinned.read_bytes() == original
            if row['printable']:
                if row['pdfBacked']:
                    reference.write_bytes(pinned.read_bytes())
                else:
                    raster_reference(before[-1], row['bounds'], reference)
        for variant, transform in row['transforms'].items():
            path = args.output / f'{name}.{variant}.ps'
            raw = path.read_bytes()
            after_parsed = inkai.parse(str(path))
            after = images(after_parsed)
            assert len(before) == len(after)
            assert identities(path) == identities(original_path)
            assert retained(raw) == retained(original), (name, variant, 'unexpected source changes')
            for index, (old, new) in enumerate(zip(before, after)):
                assert samples(old) == samples(new)
                selected = not linked and index in row['selected']
                expected = compose(transform, old.matrix) if selected else old.matrix
                assert max(abs(a - b) for a, b in zip(expected, new.matrix)) < 1e-8
                assert (old.llx, old.lly, old.urx, old.ury, old.h, old.w, old.bits, old.image_type) == (new.llx, new.lly, new.urx, new.ury, new.h, new.w, new.bits, new.image_type)
                count += selected
            headers = re.findall(rb'(?m)^(?:%_)?\[([^\]\r\n]+)\] \d+ \d+ 0 Xh\r?$', raw)
            assert len(headers) == len(after)
            for header, image in zip(headers, after):
                assert list(map(float, header.split())) == image.matrix
            if linked:
                actual = list(map(float, re.search(pattern, raw)[1].split()))
                assert max(abs(a - b) for a, b in zip(compose(transform, original_matrix), actual)) < 1e-8
                assert preview_data(after_parsed).raw == preview.raw
                check_angles(original, raw, transform, last_only=True)
                count += 1
            elif name == 'raster_ai8.ai':
                check_angles(original, raw, transform)
            else:
                pattern = rb'\(([-+0-9.eE]+)\) /String \(BBAccumRotation\)'
                assert re.findall(pattern, raw) == re.findall(pattern, original)
            if not linked and not row['printable']:
                continue
            expected_pdf = args.output / f'{name}.{variant}.reference.pdf'
            transformed_pdf(reference, expected_pdf, transform, row['bounds'])
            width, height = (1920, 1080) if not linked and row['pdfBacked'] else (612, 792)
            expected_png = render_pdf(expected_pdf, width, height)
            targets = [args.output / f'{name}.{variant}.pdf']
            if linked or row['pdfBacked']:
                saved = args.output / f'{name}.{variant}.ai'
                assert native_programs(saved) == [raw]
                owners += 1
                # A different stem avoids replacing the standalone PDF's PNG.
                carrier = args.output / f'{name}.{variant}.saved.pdf'
                carrier.write_bytes(saved.read_bytes())
                if linked:
                    targets.append(carrier)
            for target in targets:
                difference = compare(expected_png, render_pdf(target, width, height), target.with_suffix('.difference.png'), 0.02)
                comparisons.append({'file': target.name, 'meanChannelDifference': difference})
                print(f'{target.name}: mean channel difference {difference}')
    assert count == 69 and owners == 6 and len(comparisons) == 12
    (args.output / 'independent-verification.json').write_text(json.dumps({'geometryEdits': count, 'nativePrograms': owners, 'renders': comparisons}, indent=2) + '\n')
    print('Verified 69 geometry edits, six saved native programs and twelve page comparisons.')


if __name__ == '__main__':
    main()
