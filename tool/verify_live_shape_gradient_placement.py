#!/usr/bin/env python3
"""Check CC authoring placement and retained native printing geometry."""

import argparse
import hashlib
import importlib
import json
import math
import subprocess
import sys
from pathlib import Path


from verify_live_shapes import walk_body
from verify_live_shape_rotation import close
from corpus_support import REVISION, native_programs


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


def main():
    """Require pinned original artwork and independently decoded native edits."""
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
        verify_native(inkai, Path(f'{stem}.before.ps'), Path(f'{stem}.ps'), row)
        report.append(row)
        print(name, variant, 'native records passed', flush=True)
    (args.output / 'oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
