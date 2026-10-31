#!/usr/bin/env python3
"""Check CC authoring placement and independently re-place Adobe PDF shadings."""

import argparse
import hashlib
import importlib
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ContentStream, FloatObject, NameObject

from verify_live_shapes import walk_body
from verify_live_shape_rotation import close
from verify_native_pdf import REVISION, compare, native_programs, render_pdf


def style_tree(before, after, parameters=None):
    """Require intact original styles and only geometry changes in new copies."""
    if hasattr(before, 'command'):
        assert before.command == after.command
        if before.command == 'Bg' and parameters is not None:
            close(after.tokens[2:6] + after.tokens[-1:], parameters)
            assert before.tokens[:2] == after.tokens[:2]
            assert before.tokens[6:-1] == after.tokens[6:-1]
        else:
            assert before.tokens == after.tokens
    elif hasattr(before, 'asdict'):
        style_tree(before.asdict(), after.asdict(), parameters)
    elif isinstance(before, dict):
        assert before.keys() == after.keys()
        for key in before:
            style_tree(before[key], after[key], parameters)
    elif isinstance(before, (list, tuple)):
        assert len(before) == len(after)
        for first, second in zip(before, after):
            style_tree(first, second, parameters)
    else:
        assert before == after


def verify_native(inkai, first, second, row):
    """Inspect every object, every old style and every printing strip/cap."""
    from inkex import Transform
    before, after = inkai.parse(str(first)), inkai.parse(str(second))
    assert repr(before.setup.gradients) == repr(after.setup.gradients)
    old_styles, new_styles = before.setup.art_styles, after.setup.art_styles
    for name in old_styles:
        style_tree(old_styles[name], new_styles[name])
    original, changed = list(walk_body(before.trailer)), list(walk_body(after.trailer))
    assert len(original) == len(changed)
    owner = 0
    copies = set()
    new_matrices, printed_points = [], []
    for index, (old, new) in enumerate(zip(original, changed)):
        command = getattr(old, 'command', None)
        assert command == getattr(new, 'command', None)
        selected = owner in row['selected']
        if command is None:
            assert old == new
        elif command == 'Bg' and selected:
            close(new.tokens[2:6] + new.tokens[-1:], row['parameters'])
            assert old.tokens[:2] == new.tokens[:2] and old.tokens[6:-1] == new.tokens[6:-1]
        elif command in {'Xm', 'Bm', 'Bc'} and selected:
            new_matrices.append(new)
        elif command == 'Bh' and selected:
            assert old.tokens[2:] == new.tokens[2:]
            following = next(item for item in changed[index + 1:] if getattr(item, 'command', None) == 'Bm')
            a, b, c, d, _, _ = map(float, following.tokens)
            angle, length = map(float, new.tokens[2:])
            x, y = length * math.cos(math.radians(angle)), -length * math.sin(math.radians(angle))
            close(new.tokens[:2], (a * x + c * y, b * x + d * y))
        elif command == 'XW' and old.integer == 1:
            if selected:
                assert old.stylename != new.stylename
                style_tree(old_styles[old.stylename].Def, new_styles[new.stylename].Def, row['parameters'])
                copies.add(new.stylename)
                if row['file'] == 'gradient_linear.ai':
                    assert [item.command for item in new_matrices] == ['Xm', 'Bc', 'Bm', 'Bc']
                    matrices = [Transform(tuple(map(float, item.tokens))) for item in new_matrices]
                    close(matrices[0].to_hexad(), matrices[2].to_hexad())
                    before_cap, after_cap = -matrices[0] @ matrices[1], -matrices[0] @ matrices[3]
                    close((before_cap.b, before_cap.c, before_cap.d, before_cap.f, before_cap.a + before_cap.e), (0, 0, 1, 0, 0))
                    close((after_cap.b, after_cap.c, after_cap.d, after_cap.e, after_cap.f), (0, 0, 1, 1, 0))
                    assert before_cap.a > 0 and after_cap.a > 0
                    assert printed_points
                    for point in printed_points:
                        point = (-matrices[0]).apply_to_point(point)
                        assert before_cap.e - 1e-8 <= point.x <= after_cap.e + after_cap.a + 1e-8
                        assert -1e-8 <= point.y <= 1 + 1e-8
                new_matrices = []
            else:
                assert old.tokens == new.tokens
            owner += 1
            printed_points = []
        else:
            assert old.tokens == new.tokens, (owner, command)
            if selected and command in {'m', 'l', 'L'} and not old.is_pseudo_comment:
                printed_points.append(tuple(map(float, old.tokens)))
    assert owner == row['shapes'] and set(new_styles) - set(old_styles) == copies
    return before


def reference_pdf(source, target, native, row):
    """Place fields from Adobe's own clip curves using independent Inkex bounds."""
    from inkex import Transform, Path as VectorPath
    from inkex.paths import Move, Line, Curve, ZoneClose
    writer = PdfWriter()
    writer.clone_document_from_reader(PdfReader(source))
    page = writer.pages[0]
    if row['variant'] == 'transformed':
        pivot = (960, 540)
        transform = Transform(translate=pivot) @ Transform(rotate=180 / 7) @ Transform(scale=0.8) @ Transform(translate=(-pivot[0], -pivot[1]))
        page.add_transformation(tuple(transform.to_hexad()))
    stream = ContentStream(page['/Contents'], writer)
    gradients = [item for item in walk_body(native.trailer) if getattr(item, 'command', None) == 'Bg' and not item.is_pseudo_comment]
    assert len(gradients) == row['shapes']
    current, clip = Transform(), None
    stack, path, operations = [], VectorPath(), []
    count = 0
    edge_mask = Image.new('L', (1200, 675))
    outline = ImageDraw.Draw(edge_mask)
    for operands, operator in stream.operations:
        values = list(map(float, operands)) if operator in {b'cm', b'm', b'l', b'c', b're'} else []
        if operator == b'q':
            stack.append((Transform(current), clip))
        elif operator == b'Q':
            current, clip = stack.pop()
        elif operator == b'cm':
            current = current @ Transform(tuple(values))
        elif operator in {b'm', b'l', b'c'}:
            points = [component for index in range(0, len(values), 2) for component in current.apply_to_point(values[index:index + 2])]
            path.append({b'm': Move, b'l': Line, b'c': Curve}[operator](*points))
        elif operator == b're':
            x, y, width, height = values
            rectangle = VectorPath([Move(x, y), Line(x + width, y), Line(x + width, y + height), Line(x, y + height), ZoneClose()])
            path.extend(rectangle.transform(current))
        elif operator == b'h':
            path.append(ZoneClose())
        elif operator in {b'W', b'W*'}:
            clip = VectorPath(path)
        elif operator in {b'n', b'f', b'f*', b'F', b'S', b's', b'B', b'B*', b'b', b'b*'}:
            path = VectorPath()
        elif operator == b'sh':
            assert clip is not None
            # Color contrast alone misses a white gradient's boundary against
            # the white page. Derive those edges from Adobe's clip geometry.
            points = []
            for segment in clip:
                assert segment.letter in {'M', 'L', 'Z'}
                if segment.letter == 'Z':
                    points.append(points[0])
                else:
                    points.append((float(segment.args[0]) * 1200 / 1920, (1080 - float(segment.args[1])) * 675 / 1080))
            if points[-1] != points[0]:
                points.append(points[0])
            outline.line(points, fill=255, width=3)
            if count in row['selected']:
                gradient = gradients[count]
                a, b, c, d, _, _ = map(float, gradient.tokens[-7:-1])
                accumulated = Transform((a, -b, -c, d, 0, 0))
                x, y, angle, length, aspect = row['parameters']
                rotation = Transform(rotate=angle)
                radial = row['file'] == 'gradient_radial.ai'
                axes = accumulated @ rotation
                bounds = clip.transform(-(accumulated if radial else axes)).bounding_box()
                if radial:
                    radius = math.hypot(bounds.width * (x - 0.5), bounds.height * (y - 0.5)) * math.sqrt(0.5) * length
                    center = accumulated.apply_to_point((bounds.center.x + x * bounds.width, bounds.center.y - y * bounds.height))
                    desired = Transform(translate=center) @ axes @ Transform(scale=(radius, -radius * aspect))
                else:
                    origin = axes.apply_to_point((bounds.left + x * bounds.width, bounds.center.y))
                    desired = Transform(translate=origin) @ axes @ Transform(scale=(bounds.width * length, -1))
                adjustment = -current @ desired
                operations.extend([([], b'q'), ([FloatObject(value) for value in adjustment.to_hexad()], b'cm'), (operands, operator), ([], b'Q')])
            else:
                operations.append((operands, operator))
            count += 1
            continue
        operations.append((operands, operator))
    assert count == row['shapes'] and not stack
    stream.operations = operations
    page[NameObject('/Contents')] = writer._add_object(stream)
    writer.write(target)
    edge_mask.save(target.with_suffix('.edges.png'))
    return edge_mask


def verify_field(expected, actual, outline):
    """Require one-level field agreement away from reference clip/color edges."""
    with Image.open(expected) as image:
        first = image.convert('RGB')
    with Image.open(actual) as image:
        second = image.convert('RGB')
    edges = Image.new('L', first.size)
    for offset in [(1, 0), (0, 1)]:
        for channel in ImageChops.difference(first, ImageChops.offset(first, *offset)).split():
            edges = ImageChops.lighter(edges, channel)
    sharp = edges.point(lambda value: 255 if value > 8 else 0).filter(ImageFilter.MaxFilter(3))
    mask = ImageChops.invert(ImageChops.lighter(sharp, outline))
    for channel in ImageChops.difference(first, second).split():
        assert ImageChops.multiply(channel, mask).getextrema()[1] <= 1, f'{actual.name}: gradient field differs away from reference edges'


def main():
    """Require pinned original artwork and recover each saved native program."""
    if not __debug__:
        raise RuntimeError('Run without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/gradient-placement'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {row['file']: row for row in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert [(row['file'], row['variant']) for row in rows] == [(name, variant) for name in ['gradient_linear.ai', 'gradient_radial.ai'] for variant in ['all', 'selected', 'transformed']]
    report = []
    for row in rows:
        name, variant = row['file'], row['variant']
        fixture = Path('test/corpus/files', name)
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == manifest[name]['sha256']
        assert native_programs(fixture) == [(args.output / f'{name}.original.ps').read_bytes()]
        assert row['selected'] == (list(range(row['shapes'])) if variant == 'all' else [0, row['shapes'] // 2, row['shapes'] - 1])
        assert row['parameters'] == [0.15, -0.2 if name == 'gradient_radial.ai' else 0, 37, 0.75, 0.6 if name == 'gradient_radial.ai' else 1]
        stem = args.output / f'{name}.{variant}'
        if variant != 'transformed':
            assert Path(f'{stem}.before.ps').read_bytes() == (args.output / f'{name}.original.ps').read_bytes()
        native = verify_native(inkai, Path(f'{stem}.before.ps'), Path(f'{stem}.ps'), row)
        assert native_programs(Path(f'{stem}.ai')) == [Path(f'{stem}.ps').read_bytes()]
        reference = Path(f'{stem}.reference.pdf')
        outline = reference_pdf(fixture, reference, native, row)
        expected = render_pdf(reference, 1200, 675)
        means = []
        for extension in ['pdf', 'ai']:
            result = Path(f'{stem}.{extension}')
            actual = render_pdf(result, 1200, 675)
            means.append(compare(expected, actual, Path(f'{stem}.{extension}.difference.png'), 0.1))
            verify_field(expected, actual, outline)
        report.append({**row, 'meanChannelDifferences': means})
        print(name, variant, means, flush=True)
    (args.output / 'oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
