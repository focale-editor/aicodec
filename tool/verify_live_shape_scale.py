#!/usr/bin/env python3
"""Verify native uniform scaling, isolated stroke styles and external SVG geometry."""

import argparse
import hashlib
import importlib
import json
import subprocess
import sys
from pathlib import Path

from verify_live_shapes import FIXTURES, GEOMETRY, walk_body
from verify_live_shape_rotation import close, matrix, verify_svg
from corpus_support import REVISION


LENGTHS = {'Width', 'Height', 'Radius', 'Radius1', 'Radius2', 'Length',
           'CornerRadius', 'Corner1Radius', 'Corner2Radius'}


def scaled(point, pivot, factor):
    """Scale around the independently decoded canvas or drawing pivot."""
    return tuple(p + factor * (float(value) - p) for value, p in zip(point, pivot))


def records(before, after, pivot, factor):
    """Check dimensional fields while retaining angles, enums and sentinels."""
    if isinstance(before, dict):
        assert isinstance(after, dict)
        assert set(before) <= set(after)
        assert set(after) - set(before) <= {'Adobe_AI9_ArtStyle_Dictionary'}
        for key, value in before.items():
            if key.endswith('::CenterX'):
                y_key = key[:-1] + 'Y'
                close((after[key], after[y_key]), scaled((value, before[y_key]), pivot, factor))
            elif key.endswith('::CenterY'):
                continue
            elif key.startswith('ai::') and (key.split('::')[-1] in LENGTHS or '::CornerRadius::' in key):
                sentinel = key == 'ai::Polygon::Radius' and value == -11 and before.get('ai::Polygon::IsRegular') is False
                close((after[key],), (value if sentinel else float(value) * factor,))
            elif key == 'CAIGradientTformMatrix':
                close(after[key], matrix(value, pivot, 0, factor))
            else:
                records(value, after[key], pivot, factor)
        if 'Adobe_AI9_ArtStyle_Dictionary' in after and 'Adobe_AI9_ArtStyle_Dictionary' not in before:
            cached = after['Adobe_AI9_ArtStyle_Dictionary']
            assert set(cached) == {'_type', 'Recorded', 'CAIGradientTformMatrix'}
            assert cached['_type'] == 'Dictionary' and cached['Recorded'] is False
            close(cached['CAIGradientTformMatrix'], matrix((1, 0, 0, 1, 0, 0), pivot, 0, factor))
    elif isinstance(before, list):
        assert isinstance(after, list) and len(before) == len(after)
        for first, second in zip(before, after):
            records(first, second, pivot, factor)
    else:
        assert before == after, (before, after)


def styles(before, after, factor):
    """Compare independently parsed style trees, scaling only stroke distances."""
    if hasattr(before, 'command'):
        assert before.command == after.command
        if before.command == 'd':
            close((*after.dashes, after.phase), tuple(value * factor for value in (*before.dashes, before.phase)))
        elif before.command == 'w':
            close(after.tokens, tuple(float(value) * factor for value in before.tokens))
        else:
            assert before.tokens == after.tokens
    elif hasattr(before, 'asdict'):
        styles(before.asdict(), after.asdict(), factor)
    elif isinstance(before, dict):
        assert before.keys() == after.keys()
        for key, value in before.items():
            styles(value, after[key], factor)
    elif isinstance(before, (list, tuple)):
        assert len(before) == len(after)
        for a, b in zip(before, after):
            styles(a, b, factor)
    else:
        assert before == after, (before, after)


def stroke_states(items):
    """Capture effective widths/dashes at each path's paint in both views."""
    printing = (1.0, (), 0.0)
    authoring = printing
    states = []
    for item in items:
        command = getattr(item, 'command', None)
        if command in {'w', 'd'}:
            def update(state):
                if command == 'w':
                    return (float(item.tokens[0]), state[1], state[2])
                return (state[0], tuple(item.dashes), item.phase)
            authoring = update(authoring)
            if not item.is_pseudo_comment:
                printing = update(printing)
        elif command in {'n', 'N', 'f', 'F', 's', 'S', 'b', 'B'}:
            state = authoring if item.is_pseudo_comment else printing
            states.append((state[0], *state[1], state[2]))
    return states


def verify_native(inkai, original, changed, row):
    """Check source-backed paths, copies, gradients and shared style isolation."""
    source, target = inkai.parse(str(original)), inkai.parse(str(changed))
    assert source.canvas_ruler_origin == target.canvas_ruler_origin
    origin = source.canvas_ruler_origin
    pivot, factor = row['pivot'], row['factor']
    canvas = (origin.x + pivot[0], origin.y - pivot[1])
    before, after = list(walk_body(source.trailer)), list(walk_body(target.trailer))
    first_states, second_states = stroke_states(before), stroke_states(after)
    assert len(first_states) == len(second_states) == row['paths']
    for index, (first, second) in enumerate(zip(first_states, second_states)):
        scaling = 1 if row['paths'] == 19 and index == 18 else factor
        close(second, tuple(value * scaling for value in first))
    before = [item for item in before if getattr(item, 'command', None) not in {'w', 'd'}]
    after = [item for item in after if getattr(item, 'command', None) not in {'w', 'd'}]
    assert len(before) == len(after)
    source_styles, target_styles = source.setup.art_styles, target.setup.art_styles
    assert set(source_styles) <= set(target_styles)
    for name, style in source_styles.items():
        styles(style, target_styles[name], 1)
    used_copies = set()
    path_index = -1
    for first, second in zip(before, after):
        command = getattr(first, 'command', None)
        assert command == getattr(second, 'command', None)
        if command is None:
            records(first, second, canvas, factor)
            continue
        assert first.is_pseudo_comment == second.is_pseudo_comment
        if command == 'm':
            path_index += 1
        if command in GEOMETRY:
            coordinates = list(map(float, first.tokens))
            moving = not (row['paths'] == 19 and path_index == 18)
            expected = [value for index in range(0, len(coordinates), 2)
                        for value in (scaled(coordinates[index:index + 2], pivot, factor) if moving else coordinates[index:index + 2])]
            close(second.tokens, expected)
        elif command in {'Xm', 'Bm', 'Bc'}:
            close(second.tokens, matrix(first.tokens, pivot, 0, factor))
        elif command == 'Bh':
            close(second.tokens[:2], tuple(float(value) * factor for value in first.tokens[:2]))
            assert first.tokens[2:] == second.tokens[2:]
        elif command == 'Bg':
            assert first.tokens[:-7] == second.tokens[:-7] and first.tokens[-1] == second.tokens[-1]
            close(second.tokens[-7:-1], matrix(first.tokens[-7:-1], canvas, 0, factor))
        elif command == 'XW' and first.integer == 1:
            assert second.integer == 1
            styles(source_styles[first.stylename].Def, target_styles[second.stylename].Def, factor)
            if first.stylename != second.stylename:
                used_copies.add(second.stylename)
        else:
            assert first.tokens == second.tokens, command
    assert path_index + 1 == row['paths']
    assert set(target_styles) - set(source_styles) == used_copies


def main():
    """Require pinned inputs, native edits and visible independent SVGs."""
    if not __debug__:
        raise RuntimeError('Run without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/live-shape-scale'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for name in ['manifest.json', 'rotation_manifest.json']
                for entry in json.loads(Path('test/corpus', name).read_text())['files']}
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
        results.append({'file': name, 'variant': row['variant'], 'svgMeanChannelDifference': svg_mean})
        print(name, row['variant'], 'passed', flush=True)
    (args.output / 'oracle-report.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
