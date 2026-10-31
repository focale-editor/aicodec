#!/usr/bin/env python3
"""Check host-supplied printing curves, private data and independent SVG output."""

import argparse
import hashlib
import importlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys

from lxml import etree
from PIL import Image, ImageChops, ImageStat

from corpus_support import REVISION, native_programs, printable_svg
from verify_live_shapes import GEOMETRY, walk_body

FIXTURES = {'simple_shapes.ai': 5, 'simple_shapes_cc.ai': 5, 'opacity.ai': 1, 'gradient_linear.ai': 15, 'gradient_radial.ai': 9}


def paths(body):
    """Collect independent geometry separately from retained painting commands."""
    result, current = [], []
    for item in body:
        command = getattr(item, 'command', None)
        if command in GEOMETRY:
            current.append(item)
        elif command in ('n', 'N', 'f', 'F', 's', 'S', 'b', 'B') and current:
            result.append(current)
            current = []
    assert not current
    return result


def curve(current, item):
    """Expand shorthand control points without subdividing the curve."""
    coordinates = list(map(float, item.tokens))
    points = [tuple(coordinates[index:index + 2]) for index in range(0, len(coordinates), 2)]
    if item.command in ('l', 'L'):
        return [current, points[0]]
    if item.command in ('v', 'V'):
        return [current, current, *points]
    if item.command in ('y', 'Y'):
        return [current, *points, points[-1]]
    assert item.command in ('c', 'C')
    return [current, *points]


def evaluate(points, t):
    """Evaluate Bernstein polynomials independently of the fixture's subdivision."""
    degree = len(points) - 1
    return tuple(sum(math.comb(degree, index) * (1 - t) ** (degree - index) * t ** index * point[axis] for index, point in enumerate(points)) for axis in (0, 1))


def close(first, second):
    """Allow arithmetic rounding, not altered curve coordinates."""
    assert len(first) == len(second) and all(math.isclose(float(a), float(b), abs_tol=1e-9, rel_tol=0) for a, b in zip(first, second)), (first, second)


def outside(data, spans):
    """Retain every unselected byte except explicitly expanded DSC bounds."""
    pieces, position = [], 0
    for start, end in sorted(spans):
        assert position <= start < end <= len(data)
        pieces.extend([data[position:start], b'<supplied-printing-group>'])
        position = end
    pieces.append(data[position:])
    return re.sub(rb'%%(?:HiResBoundingBox|BoundingBox|PageBoundingBox):[^\r\n]*', b'%%Bounds: supplied', b''.join(pieces))


def native(inkai, original, changed, row):
    """Verify curves and preserve every private record, paint and resource binding."""
    before = list(walk_body(inkai.parse(str(original)).trailer))
    after = list(walk_body(inkai.parse(str(changed)).trailer))
    controls_before = [item for item in before if getattr(item, 'command', None) not in GEOMETRY]
    controls_after = [item for item in after if getattr(item, 'command', None) not in GEOMETRY]
    assert len(controls_before) == len(controls_after)
    for first, second in zip(controls_before, controls_after):
        if hasattr(first, 'command'):
            assert first.command == second.command and first.tokens == second.tokens and first.is_pseudo_comment == second.is_pseudo_comment
        else:
            assert first == second
    old_paths, new_paths = paths(before), paths(after)
    assert len(old_paths) == len(new_paths) == row['paths']
    for index, (first, second) in enumerate(zip(old_paths, new_paths)):
        if index not in row['selectedPaths']:
            assert [(item.command, item.tokens) for item in first] == [(item.command, item.tokens) for item in second]
            continue
        assert not any(item.is_pseudo_comment for item in first + second)
        assert len(second) == 1 + 2 * (len(first) - 1)
        assert first[0].command == second[0].command == 'm'
        close(first[0].tokens, second[0].tokens)
        current = tuple(map(float, first[0].tokens))
        for segment, item in enumerate(first[1:]):
            expected = curve(current, item)
            left = curve(current, second[1 + segment * 2])
            right = curve(left[-1], second[2 + segment * 2])
            for t in (0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1):
                close(evaluate(expected, t), evaluate(left, t * 2) if t <= 0.5 else evaluate(right, t * 2 - 1))
            current = expected[-1]
    assert outside(original.read_bytes(), [group['before'] for group in row['groups']]) == outside(changed.read_bytes(), [group['after'] for group in row['groups']])


def render(inkai, path, output):
    """Render independently parsed printing art, without reconstructing live shapes."""
    svg = output / f'{path.name}.svg'
    png = svg.with_suffix('.png')
    svg.write_bytes(etree.tostring(printable_svg(inkai, path)))
    subprocess.run(['inkscape', str(svg), '--export-type=png', '--export-width=1200', f'--export-filename={png}'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with Image.open(png) as image:
        rgba = image.convert('RGBA')
    assert rgba.getchannel('A').getbbox() is not None, f'Empty independent render: {path.name}'
    return rgba


def main():
    """Require all qualified fixtures, both selections and nonempty comparisons."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/native-printing'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 10 and {(row['file'], row['variant']) for row in rows} == {(name, variant) for name in FIXTURES for variant in ('first', 'all')}
    references, results = {}, []
    for row in rows:
        name = row['file']
        input_path = Path('test/corpus/files', name)
        input_bytes = input_path.read_bytes()
        assert hashlib.sha256(input_bytes).hexdigest() == manifest[name]['sha256']
        assert row['shapes'] == (FIXTURES[name] if row['variant'] == 'all' else 1)
        original = args.output / f'{name}.original.ps'
        changed = args.output / f'{name}.{row["variant"]}.ps'
        extracted = native_programs(input_path) if input_bytes.startswith(b'%PDF-') else [input_bytes]
        assert original.read_bytes() in extracted
        native(inkai, original, changed, row)
        if name not in references:
            references[name] = render(inkai, original, args.output)
        first, second = references[name], render(inkai, changed, args.output)
        assert first.size == second.size
        difference = ImageChops.difference(first, second)
        mean = max(ImageStat.Stat(difference).mean)
        assert mean < 0.05, f'Independent printing differs by {mean}: {changed.name}'
        difference.save(args.output / f'{changed.name}.difference.png')
        results.append({'file': name, 'variant': row['variant'], 'shapes': row['shapes'], 'paths': len(row['selectedPaths']), 'meanChannelDifference': mean})
        print(name, row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps({'oracleRevision': REVISION, 'variants': results}, indent=2) + '\n')


if __name__ == '__main__':
    main()
