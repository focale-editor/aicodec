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
from verify_native_group_lifecycle import ATTRIBUTES, attributes
from verify_native_layers import commands
from verify_native_structure import parsed

PAINT = {'n', 'N', 'f', 'F', 's', 'S', 'b', 'B'}
BOUNDS = rb'%%(?:HiResBoundingBox|BoundingBox|PageBoundingBox):([^\r\n]*)'
SYNTHETIC_SHA256 = {
    'synthetic-counted': '5d1b58916dbef5903fa3dc9725d6cff973e5df70429bec6dc166b689635cf0b3',
    'synthetic-groups': 'f3cdff9f27a0606ef2e0eecfbb505d033839ada4d17ac6f152209891afc7d1ea',
    'synthetic-state': '77c6118b5a7a7440f36fa22f04301ebc9d247467cb4a285b5315fb591e9ae59a',
    'synthetic-state-siblings': 'e55b38554215f90fef61722558406f8170249559623ad0454b97bc03961819d9',
}


def inventory(document, expected):
    """Decode path/owner state without equating it with assignment history."""
    paths, geometry, controls, state, owners, flags, count = [], [], [], {}, [], {}, None
    identity = 0
    for item in walk_body(document.trailer):
        command = getattr(item, 'command', None)
        if command in GEOMETRY:
            geometry.append(dict(operator=command, numbers=list(map(float, item.tokens))))
        elif command in PAINT and geometry:
            paths.append(dict(geometry=geometry, paint=command, state=dict(state), owners=tuple(owners), count=count, private=item.is_pseudo_comment))
            geometry, count = [], None
        elif command == 'As':
            assert count is None
            count = int(item.tokens[0])
        elif command is not None:
            controls.append((command, tuple(item.tokens), item.is_pseudo_comment))
            if command in ('u', '*u', 'q', 'Lb'):
                identity += 1
                owners.append(identity)
                flags[identity] = {key: state[key] for key in ('A', 'Xw') if key in state}
            elif command in ('U', '*U', 'Q', 'LB'):
                owners.pop()
            elif command in ATTRIBUTES:
                key = 'fill' if command in ('g', 'k', 'Xa') else 'stroke' if command in ('G', 'K', 'XA') else command
                state[key] = (command, tuple(item.tokens))
            elif command not in ('Ln', 'AE'):
                state.clear()
    assert not geometry and count is None and len(paths) == len(expected)
    for path, reported in zip(paths, expected):
        assert path['geometry'] == reported['geometry'] and path['paint'] == reported['paint']
        assert (path['count'] is None) == (reported['count'] is None)
    return paths, controls, flags


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
    original, controls, flags = inventory(inkai.parse(str(before_file)), row['before'])
    changed, changed_controls, changed_flags = inventory(inkai.parse(str(after_file)), row['after'])
    assert flags == changed_flags
    if row['operation'] in ('reorder', 'move'):
        assert [value for value in controls if value[0] not in ATTRIBUTES] == [value for value in changed_controls if value[0] not in ATTRIBUTES]
        if row['operation'] == 'move':
            source_flags = [flags[owner] for owner in original[row['selected'][0]]['owners']]
            target_flags = [flags[owner] for owner in original[row['anchor']]['owners']]
            assert source_flags == target_flags or row.get('inheritParentFlags') is True
        return verify_movement(before, after, row, original, changed)
    assert controls == changed_controls
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
            assert added['state'] == path['state'] and not added['private']
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
    """Check effective attributes and constrain every copied source/count span."""
    expected_paths, edits = list(original), []
    if row['operation'] == 'reorder':
        assert row['selected'] == ([0, 1] if row['source'].startswith('synthetic-') else [18, 19])
        for slot, source in zip(row['selected'], reversed(row['selected'])):
            expected_paths[slot] = original[source]
            old, new = row['before'][slot], row['before'][source]
            count = checked_count(before, new['count'], original[source]['count'])
            fragment = before[new['start']:new['end']]
            edits.append((old['start'], old['end'], 'copy', (count if old['count'] is None else b'') + fragment))
            if old['count'] is not None:
                edits.append((*old['count'], 'exact', count if count else b' '))
    else:
        selected, = row['selected']
        target = row['anchor']
        source, anchor = row['before'][selected], row['before'][target]
        expected_paths.pop(selected)
        position = target - int(selected < target) + 1
        expected_paths.insert(position, dict(original[selected], owners=original[target]['owners']))
        count = checked_count(before, source['count'], original[selected]['count'])
        edits.extend([(source['start'], source['end'], 'exact', b' '), (anchor['end'], anchor['end'], 'copy', count + before[source['start']:source['end']])])
        if source['count'] is not None:
            edits.append((*source['count'], 'exact', b' '))
    assert expected_paths == changed
    original_assignments = {value for value in commands(parsed(before)) if value[0] in ATTRIBUTES}
    assignment = rb'[ \t\r\n0-9.eE+\-\[\]A-Za-z]*'
    position, pattern = 0, b''
    for start, end, kind, source in sorted(edits):
        assert position <= start <= end <= len(before)
        replacement = re.escape(source)
        if kind == 'copy':
            replacement = assignment + replacement + assignment
        pattern += re.escape(before[position:start]) + b'(' + replacement + b')'
        position = end
    match = re.fullmatch(pattern + re.escape(before[position:]), after)
    assert match is not None, 'Unselected source bytes changed'
    for (_, _, kind, source), fragment in zip(sorted(edits), match.groups()):
        if kind == 'copy':
            assert fragment.count(source) == 1
            prefix, suffix = fragment.split(source)
            assert all(value in original_assignments for value in attributes(prefix) + attributes(suffix))
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
    assert len(rows) == 16 and {row['result'] for row in rows} == {
        source + '.' + operation + '.ps' for source in ('simple_shapes.ai', 'simple_shapes_cc.ai', 'synthetic-counted') for operation in ('duplicate', 'remove', 'insert', 'reorder')
    } | {'synthetic-groups.move.ps', 'synthetic-state.forward.ps', 'synthetic-state.backward.ps', 'synthetic-state-siblings.reorder.ps'}
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    results = []
    for row in rows:
        if row['operation'] == 'reorder' and row['source'] != 'synthetic-state-siblings':
            assert row['original'] in {result['file'] for result in results}
        elif row['source'] in SYNTHETIC_SHA256:
            assert hashlib.sha256((args.output / row['original']).read_bytes()).hexdigest() == SYNTHETIC_SHA256[row['source']]
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
