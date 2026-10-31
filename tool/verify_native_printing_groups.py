#!/usr/bin/env python3
"""Verify complete supplied groups, source preservation and independent appearance."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from PIL import ImageChops, ImageStat

from corpus_support import REVISION, native_programs
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_printing import FIXTURES, equivalent_geometry, outside, paths, point_counts, render


def paint_commands(body):
    """Associate independently parsed path consumers with their geometry."""
    result, active = [], False
    for item in body:
        command = getattr(item, 'command', None)
        if command in GEOMETRY:
            active = True
        elif active and command in ('n', 'N', 'f', 'F', 's', 'S', 'b', 'B'):
            result.append(item)
            active = False
    assert not active
    return result


def verify(inkai, original, changed, row, output):
    """Check all payloads exactly and independently inspect introduced topology."""
    first_bytes, second_bytes = original.read_bytes(), changed.read_bytes()
    assert outside(first_bytes, [group['before'] for group in row['groups']]) == outside(second_bytes, [group['after'] for group in row['groups']])
    for group in row['groups']:
        assert second_bytes[slice(*group['after'])] == (output / group['payload']).read_bytes()
    before = list(walk_body(inkai.parse(str(original)).trailer))
    after = list(walk_body(inkai.parse(str(changed)).trailer))
    old_paths, new_paths = paths(before), paths(after)
    old_paints, new_paints = paint_commands(before), paint_commands(after)
    added = set(row['addedPaths'])
    assert len(added) == row['shapes']
    assert len(old_paths) == row['paths'] and len(new_paths) == row['paths'] + len(added)
    mapping = [index for index in range(len(new_paths)) if index not in added]
    for index in added:
        assert len(new_paths[index]) == 1 and new_paths[index][0].command == 'm'
        assert list(map(float, new_paths[index][0].tokens)) == [0, 0]
        assert new_paints[index].command == 'F' and not new_paints[index].is_pseudo_comment
    old_counts, new_counts = point_counts(before), point_counts(after)
    for index, (count, closed) in new_counts.items():
        assert int(count.tokens[0]) == len(new_paths[index]) - int(closed)
    for index, target in enumerate(mapping):
        first, second = old_paths[index], new_paths[target]
        assert old_paints[index].command == new_paints[target].command
        assert (index in old_counts) == (target in new_counts)
        if index in old_counts:
            count, closed = old_counts[index]
            assert int(count.tokens[0]) == len(first) - int(closed)
            assert closed == new_counts[target][1]
        if index in row['selectedPaths']:
            equivalent_geometry(first, second)
        else:
            assert [(item.command, item.tokens, item.is_pseudo_comment) for item in first] == [(item.command, item.tokens, item.is_pseudo_comment) for item in second]
            if index in old_counts:
                assert old_counts[index][0].tokens == new_counts[target][0].tokens
    added_paints = {id(new_paints[index]) for index in added}
    omitted = (*GEOMETRY, 'As', 'u', 'U')
    old_controls = [item for item in before if getattr(item, 'command', None) not in omitted]
    new_controls = [item for item in after if getattr(item, 'command', None) not in omitted and id(item) not in added_paints]
    assert len(old_controls) == len(new_controls)
    for first, second in zip(old_controls, new_controls):
        if hasattr(first, 'command'):
            assert (first.command, first.tokens, first.is_pseudo_comment) == (second.command, second.tokens, second.is_pseudo_comment)
        else:
            assert first == second
    for operator in ('u', 'U'):
        assert sum(getattr(item, 'command', None) == operator for item in after) == sum(getattr(item, 'command', None) == operator for item in before) + len(added)


def main():
    """Require every pinned fixture and both partial and complete selections."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/native-printing-groups'), type=Path)
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
        path = Path('test/corpus/files', name)
        data = path.read_bytes()
        assert len(data) == manifest[name]['size'] and hashlib.sha256(data).hexdigest() == manifest[name]['sha256']
        assert row['shapes'] == (FIXTURES[name] if row['variant'] == 'all' else 1)
        original = args.output / f'{name}.original.ps'
        changed = args.output / f'{name}.{row["variant"]}.ps'
        assert original.read_bytes() in (native_programs(path) if data.startswith(b'%PDF-') else [data])
        verify(inkai, original, changed, row, args.output)
        if name not in references:
            references[name] = render(inkai, original, args.output)
        first, second = references[name], render(inkai, changed, args.output)
        assert first.size == second.size
        difference = ImageChops.difference(first, second)
        mean = max(ImageStat.Stat(difference).mean)
        assert mean < 0.05, f'Independent appearance differs by {mean}: {changed.name}'
        difference.save(args.output / f'{changed.name}.difference.png')
        results.append({'file': name, 'variant': row['variant'], 'groups': row['shapes'], 'additionalPaths': len(row['addedPaths']), 'meanChannelDifference': mean})
        print(name, row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps({'oracleRevision': REVISION, 'variants': results}, indent=2) + '\n')


if __name__ == '__main__':
    main()
