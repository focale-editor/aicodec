#!/usr/bin/env python3
"""Independently verify ordinary path lifecycle and exact unselected native bytes."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_structure import parsed

PAINT = {'n', 'N', 'f', 'F', 's', 'S', 'b', 'B'}
BOUNDS = rb'%%(?:HiResBoundingBox|BoundingBox|PageBoundingBox):([^\r\n]*)'


def inventory(document, expected):
    """Decode every path and its preceding control stream through pinned inkai."""
    paths, geometry, controls, state_controls, owners, count = [], [], [], [], [], None
    identity = 0
    for item in walk_body(document.trailer):
        command = getattr(item, 'command', None)
        if command in GEOMETRY:
            geometry.append(dict(operator=command, numbers=list(map(float, item.tokens))))
        elif command in PAINT and geometry:
            paths.append(dict(geometry=geometry, paint=command, controls=tuple(state_controls), owners=tuple(owners), count=count, private=item.is_pseudo_comment))
            geometry, count = [], None
        elif command == 'As':
            assert count is None
            count = int(item.tokens[0])
        elif command is not None:
            controls.append((command, tuple(item.tokens), item.is_pseudo_comment))
            if command in ('u', '*u', 'q', 'Lb'):
                identity += 1
                owners.append(identity)
            elif command in ('U', '*U', 'Q', 'LB'):
                owners.pop()
            else:
                state_controls.append(controls[-1])
    assert not geometry and count is None and len(paths) == len(expected)
    for path, reported in zip(paths, expected):
        assert path['geometry'] == reported['geometry'] and path['paint'] == reported['paint']
        assert (path['count'] is None) == (reported['count'] is None)
    return paths, controls


def patch(data, edits):
    """Apply independently checked source intervals in their original order."""
    pieces, position = [], 0
    for start, end, replacement in sorted(edits):
        assert position <= start <= end <= len(data)
        pieces.extend([data[position:start], replacement])
        position = end
    pieces.append(data[position:])
    return b''.join(pieces)


def checked_count(data, span, expected):
    """Decode the exact optional count operand independently of report values."""
    if span is None:
        assert expected is None
        return b''
    fragment = data[span[0]:span[1]]
    command, = parsed(fragment)
    assert command.command == 'As' and int(command.tokens[0]) == expected
    return fragment + b'\n'


def verify(inkai, output, row):
    """Check new/retained geometry, inherited controls, counts and byte preservation."""
    before_file, after_file = output / row['original'], output / row['result']
    before, after = before_file.read_bytes(), after_file.read_bytes()
    original, controls = inventory(inkai.parse(str(before_file)), row['before'])
    changed, changed_controls = inventory(inkai.parse(str(after_file)), row['after'])
    assert controls == changed_controls
    if row['operation'] in ('reorder', 'move'):
        return verify_movement(before, after, row, original, changed)
    assert row['selected'] == ([0, 1] if row['source'] == 'synthetic-counted' else [18])
    edits, cursor, new_count = [], 0, 0
    for index, (path, source) in enumerate(zip(original, row['before'])):
        if index not in row['selected']:
            assert path == changed[cursor]
            cursor += 1
            continue
        assert not path['private']
        count = checked_count(before, source['count'], path['count'])
        if row['operation'] == 'remove':
            edits.append((source['start'], source['end'], b' '))
            if source['count'] is not None:
                edits.append((*source['count'], b' '))
            continue
        assert path == changed[cursor]
        added, added_source = changed[cursor + 1], row['after'][cursor + 1]
        cursor += 2
        new_count += 1
        if row['operation'] == 'duplicate':
            assert path == added
            fragment = count + before[source['start']:source['end']]
        else:
            assert row['operation'] == 'insert'
            geometry = list(row['insertions'][row['selected'].index(index)])
            closed = path['paint'].islower()
            if path['count'] is not None and closed and geometry[-1]['numbers'][-2:] != geometry[0]['numbers']:
                geometry.append(dict(operator='L', numbers=geometry[0]['numbers']))
            assert added['geometry'] == geometry and added['paint'] == path['paint']
            assert added['controls'] == path['controls'] and not added['private']
            expected_count = None if path['count'] is None else len(geometry) - int(closed)
            assert added['count'] == expected_count
            count = checked_count(after, added_source['count'], expected_count)
            fragment = count + after[added_source['start']:added_source['end']]
        edits.append((source['end'], source['end'], b'\n' + fragment + b'\n'))
    assert cursor == len(changed)
    expected = patch(before, edits)
    if row['operation'] == 'insert':
        old_bounds = list(re.finditer(BOUNDS, before))
        new_bounds = list(re.finditer(BOUNDS, after))
        assert len(old_bounds) == len(new_bounds) > 0
        for first, second in zip(old_bounds, new_bounds):
            values = list(map(float, first[1].split()))
            assert list(map(float, second[1].split())) == [min(values[0], -1000), min(values[1], -2000), max(values[2], 3000), max(values[3], 1500)]
        expected = re.sub(BOUNDS, b'%%Bounds: supplied', expected)
        after = re.sub(BOUNDS, b'%%Bounds: supplied', after)
    assert expected == after, row['result']
    return dict(pathsBefore=len(original), pathsAfter=len(changed), inserted=new_count, removed=len(row['selected']) if row['operation'] == 'remove' else 0)


def verify_movement(before, after, row, original, changed):
    """Check moved identities, inherited controls and exact source-slot edits."""
    expected_paths, edits = list(original), []
    if row['operation'] == 'reorder':
        assert row['selected'] == ([0, 1] if row['source'] == 'synthetic-counted' else [18, 19])
        for slot, source in zip(row['selected'], reversed(row['selected'])):
            expected_paths[slot] = original[source]
            old, new = row['before'][slot], row['before'][source]
            count = checked_count(before, new['count'], original[source]['count'])
            fragment = before[new['start']:new['end']]
            edits.append((old['start'], old['end'], (count if old['count'] is None else b'') + fragment))
            if old['count'] is not None:
                edits.append((*old['count'], count[:-1] if count else b' '))
    else:
        assert row['source'] == 'synthetic-groups' and row['selected'] == [0] and row['anchor'] == 1
        source, anchor = row['before'][0], row['before'][1]
        expected_paths = [original[1], dict(original[0], owners=original[1]['owners'])]
        count = checked_count(before, source['count'], original[0]['count'])
        edits.extend([(source['start'], source['end'], b' '), (anchor['end'], anchor['end'], b'\n' + count + before[source['start']:source['end']] + b'\n')])
        if source['count'] is not None:
            edits.append((*source['count'], b' '))
    assert expected_paths == changed
    assert patch(before, edits) == after
    return dict(pathsBefore=len(original), pathsAfter=len(changed), moved=len(row['selected']))


def main():
    """Require all variants, pinned upstream code and exact native extraction."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/path-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 13 and {(row['source'], row['operation']) for row in rows} == {
        (source, operation) for source in ('simple_shapes.ai', 'simple_shapes_cc.ai', 'synthetic-counted') for operation in ('duplicate', 'remove', 'insert', 'reorder')
    } | {('synthetic-groups', 'move')}
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    results = []
    for row in rows:
        if row['operation'] == 'reorder':
            assert row['original'] in {result['file'] for result in results}
        elif not row['source'].startswith('synthetic-'):
            entry = next(entry for entry in manifest if entry['file'] == row['source'])
            path = Path('test/corpus/files', row['source'])
            data = path.read_bytes()
            assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            assert (args.output / row['original']).read_bytes() in (native_programs(path) if data.startswith(b'%PDF-') else [inkai.extract(str(path))])
        results.append(dict(file=row['result'], **verify(inkai, args.output, row)))
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=results), indent=2) + '\n')


if __name__ == '__main__':
    main()
