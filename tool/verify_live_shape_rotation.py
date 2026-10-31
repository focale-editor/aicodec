#!/usr/bin/env python3
"""Verify rotated native shapes, accumulated gradients and PDF appearances."""

import argparse
import hashlib
import importlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from lxml import etree
from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader, PdfWriter, Transformation

from verify_live_shapes import FIXTURES, GEOMETRY, walk_body
from verify_native_pdf import REVISION, compare, native_programs, printable_svg, render_pdf


def rotate(point, pivot, angle):
    """Apply a rigid transform independently of AiKit's matrix serialization."""
    x, y = point[0] - pivot[0], point[1] - pivot[1]
    return (pivot[0] + math.cos(angle) * x - math.sin(angle) * y,
            pivot[1] + math.sin(angle) * x + math.cos(angle) * y)


def close(actual, expected, tolerance=1e-8):
    """Compare native decimal values with explicit serialization tolerance."""
    assert len(actual) == len(expected)
    assert all(math.isclose(float(a), float(b), abs_tol=tolerance, rel_tol=1e-11) for a, b in zip(actual, expected)), (actual, expected)


def matrix(values, pivot, angle):
    """Rotate both column vectors and the affine origin."""
    a, b, c, d, x, y = map(float, values)
    first = rotate((a, b), (0, 0), angle)
    second = rotate((c, d), (0, 0), angle)
    return (*first, *second, *rotate((x, y), pivot, angle))


def verify_records(before, after, pivot, angle):
    """Check native dictionaries without dropping corners or version alternatives."""
    if isinstance(before, dict):
        assert isinstance(after, dict)
        assert set(before) <= set(after)
        assert set(after) - set(before) <= {'BBAccumRotation', 'Adobe_AI9_ArtStyle_Dictionary'}
        for key, value in before.items():
            if key.endswith('::CenterX'):
                y_key = key[:-1] + 'Y'
                close((after[key], after[y_key]), rotate((value, before[y_key]), pivot, -angle))
            elif key.endswith('::CenterY'):
                continue
            elif key.endswith('::RotationAngle') or key == 'ai::Rectangle::Angle':
                close((after[key],), ((float(value) + angle) % (2 * math.pi),))
            elif key == 'BBAccumRotation':
                expected = math.fmod(float(value) + angle, 2 * math.pi)
                close((after[key],), (expected,), 0.00000051)
            elif key == 'CAIGradientTformMatrix':
                close(after[key], matrix(value, pivot, -angle))
            else:
                verify_records(value, after[key], pivot, angle)
        if 'BBAccumRotation' in after and 'BBAccumRotation' not in before:
            close((after['BBAccumRotation'],), (angle,), 0.00000051)
        if 'Adobe_AI9_ArtStyle_Dictionary' in after and 'Adobe_AI9_ArtStyle_Dictionary' not in before:
            cached = after['Adobe_AI9_ArtStyle_Dictionary']
            assert set(cached) == {'_type', 'Recorded', 'CAIGradientTformMatrix'}
            assert cached['_type'] == 'Dictionary' and cached['Recorded'] is False
            close(cached['CAIGradientTformMatrix'], matrix((1, 0, 0, 1, 0, 0), pivot, -angle))
    elif isinstance(before, list):
        assert isinstance(after, list) and len(before) == len(after)
        for first, second in zip(before, after):
            verify_records(first, second, pivot, angle)
    else:
        assert before == after, (before, after)


def verify_native(inkai, original, changed, row):
    """Inspect all body paths, style transforms, polar foci and native copies."""
    source = inkai.parse(str(original))
    target = inkai.parse(str(changed))
    origin = source.canvas_ruler_origin
    pivot = row['pivot']
    canvas_pivot = (origin.x + pivot[0], origin.y - pivot[1])
    first_items, second_items = list(walk_body(source.trailer)), list(walk_body(target.trailer))
    assert len(first_items) == len(second_items)
    path_index = -1
    for first, second in zip(first_items, second_items):
        command = getattr(first, 'command', None)
        assert command == getattr(second, 'command', None)
        if command is None:
            verify_records(first, second, canvas_pivot, row['radians'])
            continue
        assert first.is_pseudo_comment == second.is_pseudo_comment
        if command == 'm':
            path_index += 1
        if command in GEOMETRY:
            moving = not (row['paths'] == 19 and path_index == 18)
            coordinates = list(map(float, first.tokens))
            expected = [component for index in range(0, len(coordinates), 2)
                        for component in (rotate(coordinates[index:index + 2], pivot, row['radians']) if moving else coordinates[index:index + 2])]
            close(second.tokens, expected)
        elif command in {'Xm', 'Bm', 'Bc'}:
            close(second.tokens, matrix(first.tokens, pivot, row['radians']))
        elif command == 'Bh':
            close(second.tokens[:2], rotate(list(map(float, first.tokens[:2])), (0, 0), row['radians']))
            assert first.tokens[2:] == second.tokens[2:]
        elif command == 'Bg':
            assert first.tokens[:-7] == second.tokens[:-7]
            close(second.tokens[-7:-1], matrix(first.tokens[-7:-1], canvas_pivot, -row['radians']))
            assert first.tokens[-1] == second.tokens[-1]
        else:
            assert first.tokens == second.tokens, command
    assert path_index + 1 == row['paths']
    # Shared styles, text payloads and other setup resources stay byte-exact.
    before = original.read_bytes().split(b'%%BeginSetup', 1)[1].split(b'%%EndSetup', 1)[0]
    after = changed.read_bytes().split(b'%%BeginSetup', 1)[1].split(b'%%EndSetup', 1)[0]
    assert before == after


def verify_svg(inkai, original, changed, row, output):
    """Compare native-authoring rendering with explicitly rotated original SVG."""
    from inkex import Transform
    from inkai.svg.coordinates import SVGTransform

    if row['file'] == 'rectangle-rounded-corners-all-different.ai':
        # The pinned converter emits an empty-d path effect for this authoring
        # shape. Check its exact curves through the independent printing reader;
        # native corner parameters are still checked separately above.
        before = printable_svg(inkai, original)
        after = printable_svg(inkai, changed)
    else:
        before = etree.fromstring(inkai.to_svg(str(original)))
        after = etree.fromstring(inkai.to_svg(str(changed)))
    pivot = SVGTransform(inkai.parse(str(original))).from_drawing(*row['pivot'])
    transform = Transform(f'rotate({-math.degrees(row["radians"])} {pivot[0]} {pivot[1]})')
    tags = {'path', 'rect', 'ellipse', 'circle', 'line', 'polygon'}
    shapes = [node for node in before.iter() if etree.QName(node).localname in tags]
    assert len(shapes) == row['shapes'] + (1 if row['paths'] == 19 else 0)
    for shape in shapes[:row['shapes']]:
        shape.set('transform', str(transform @ Transform(shape.get('transform', ''))))
    images = []
    for label, tree in [('expected', before), ('actual', after)]:
        path = output / f'{changed.stem}.{label}.svg'
        png = path.with_suffix('.png')
        path.write_bytes(etree.tostring(tree))
        subprocess.run(['inkscape', str(path), '--export-type=png', '--export-width=1200', f'--export-filename={png}'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with Image.open(png) as image:
            images.append(image.convert('RGBA'))
    for image in images:
        assert image.getchannel('A').getbbox() is not None, f'Empty SVG render for {changed.name}'
        assert ImageChops.difference(image.convert('RGB'), Image.new('RGB', image.size, 'white')).getbbox() is not None, f'Blank SVG render for {changed.name}'
    assert images[0].size == images[1].size
    difference = ImageChops.difference(*images)
    mean = max(ImageStat.Stat(difference).mean)
    difference.save(output / f'{changed.stem}.svg-difference.png')
    assert mean < 0.05, (changed.name, mean)
    return mean


def reference_pdf(original, target, row):
    """Rotate Adobe's existing PDF around the same pivot in PDF page coordinates."""
    if row['file'] == 'page_moved_to_1000_2000_rect200_300.ai':
        # This pinned native fixture has Adobe's missing-PDF-content notice.
        # Its actual artwork is one black 200x300 rectangle at (1000,-2300).
        # Render that independently with standard PostScript, then transform it.
        assert 'saved without PDF Content' in PdfReader(original).pages[0].extract_text()
        assert row['bounds'] == [1000, -3080, 2920, -2000]
        original = target.with_name(target.stem + '.original-rectangle.pdf')
        postscript = '%!PS-Adobe-3.0\n<< /PageSize [1920 1080] >> setpagedevice\n0 setgray 0 780 200 300 rectfill showpage\n'
        subprocess.run(['gs', '-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=pdfwrite', f'-sOutputFile={original}', '-'], input=postscript.encode(), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    writer = PdfWriter()
    writer.clone_document_from_reader(PdfReader(original))
    left, bottom, _, _ = row['bounds']
    pivot = (row['pivot'][0] - left, row['pivot'][1] - bottom)
    values = matrix((1, 0, 0, 1, 0, 0), pivot, row['radians'])
    writer.pages[0].add_transformation(Transformation(values))
    writer.write(target)


def main():
    """Require pinned artwork and an unchanged independent converter checkout."""
    if not __debug__:
        raise RuntimeError('Run without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/live-shape-rotation'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for filename in ['manifest.json', 'rotation_manifest.json']
                for entry in json.loads(Path('test/corpus', filename).read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    added = {'rectangle_with_rounded_corners.ai', 'rectangle-rounded-corners-all-different.ai', 'page_moved_to_1000_2000_rect200_300.ai'}
    assert len(rows) == 22 and {row['file'] for row in rows} == set(FIXTURES) | added
    results = []
    for row in rows:
        name = row['file']
        assert hashlib.sha256(Path('test/corpus/files', name).read_bytes()).hexdigest() == manifest[name]['sha256']
        original = args.output / f'{name}.original.ps'
        stem = f'{name}.{row["variant"]}'
        changed = args.output / f'{stem}.ps'
        verify_native(inkai, original, changed, row)
        svg_mean = verify_svg(inkai, original, changed, row, args.output)
        comparisons = []
        if row['pdf']:
            saved = args.output / f'{stem}.ai'
            assert native_programs(saved) == [changed.read_bytes()]
            reference = args.output / f'{stem}.reference.pdf'
            reference_pdf(args.output / f'{name}.original.pdf', reference, row)
            left, bottom, right, top = row['bounds']
            width, height = 1200, math.ceil(1200 * (top - bottom) / (right - left))
            expected = render_pdf(reference, width, height)
            for target in [args.output / f'{stem}.pdf', saved]:
                actual = render_pdf(target, width, height)
                # Poppler rasterizes Adobe's transformed rectangle operator and
                # the equivalent explicit native path with different edge coverage.
                # Flat pixels and smooth gradient fields retain the stricter checks.
                mean = compare(expected, actual, target.with_suffix(f'.{target.suffix[1:]}.difference.png'), 0.1, gradient=name.startswith('gradient_'))
                comparisons.append({'file': target.name, 'meanChannelDifference': mean})
        results.append({'file': name, 'variant': row['variant'], 'svgMeanChannelDifference': svg_mean,
                        'svgSource': 'Printing curves; authoring path effect unsupported by oracle' if name == 'rectangle-rounded-corners-all-different.ai' else 'Native authoring',
                        'pdfReference': 'Ghostscript known rectangle' if name == 'page_moved_to_1000_2000_rect200_300.ai' else 'Original Adobe PDF', 'pdf': comparisons})
        print(name, row['variant'], 'passed', flush=True)
    (args.output / 'oracle-report.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
