#!/usr/bin/env python3
"""Verify group lifecycle through pinned inkai, effective state and source bytes."""

import argparse
import copy
from decimal import Decimal
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
ATTRIBUTES = {'g', 'G', 'k', 'K', 'Xa', 'XA', 'A', 'Xw', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'w', 'M', 'd', 'Xy'}
SYNTHETIC_SHA256 = 'ef60c43a97cddd691af2ae3473084b293303cb59ffdcc9e00f719976dba751d4'


def command(item):
    """Retain independently parsed operators and exact lexical operands."""
    return (getattr(item, 'command', None), tuple(getattr(item, 'tokens', [])), getattr(item, 'is_pseudo_comment', False))


def inventory(document):
    """Build actual nested objects and observe persistent attributes at each path."""
    roots, groups, paths, stack, state, geometry = [], [], [], [], {}, []
    count = None
    commands = list(walk_body(document.trailer))
    for index, item in enumerate(commands):
        operator, operands, private = command(item)
        owner = roots if not stack else stack[-1]['children']
        if operator in ATTRIBUTES:
            key = 'fill' if operator in ('g', 'k', 'Xa') else 'stroke' if operator in ('G', 'K', 'XA') else operator
            state[key] = (operator, operands)
        elif operator in ('u', '*u', 'q', 'Lb'):
            if operator == 'Lb':
                state.clear()
            node = dict(kind=operator, flags={key: state[key] for key in ('A', 'Xw') if key in state}, children=[], private=private)
            if operator == 'Lb':
                node['header'] = operands
            node['first'] = index
            owner.append(node)
            stack.append(node)
        elif operator in ('U', '*U', 'Q', 'LB'):
            node = stack.pop()
            assert node['kind'].upper() == operator
            node['commands'] = [command(value) for value in commands[node.pop('first'):index + 1]]
            if operator == 'LB':
                node['outgoing'] = dict(state)
                state.clear()
            else:
                groups.append(node)
        elif operator in GEOMETRY:
            geometry.append((operator, operands))
        elif operator == 'As':
            assert count is None and len(operands) == 1
            value = Decimal(operands[0].decode('ascii'))
            assert value.is_finite() and value >= 0 and value == value.to_integral_value()
            count = int(value)
        elif operator in PAINT and geometry:
            node = dict(kind='path', geometry=geometry, paint=operator, count=count, state=dict(state), private=private)
            paths.append(node)
            owner.append(node)
            geometry, count = [], None
        elif operator not in ('Ln', 'AE'):
            # Opaque attributes have no inferred values; the qualified sources
            # reestablish the assignments needed by their selected ordinary art.
            state.clear()
    assert not stack and not geometry and count is None
    return roots, groups, paths


def view(nodes):
    """Compare object semantics while excluding retained lexical trace data."""
    return [{key: view(value) if key == 'children' else value for key, value in node.items() if key != 'commands'} for node in nodes]


def parent(nodes, wanted):
    """Locate an exact independently decoded object without merging equal art."""
    for index, node in enumerate(nodes):
        if node is wanted:
            return nodes, index
        if 'children' in node:
            result = parent(node['children'], wanted)
            if result is not None:
                return result
    return None


def descendant_paths(node):
    """Enumerate paths under one independently decoded group in object order."""
    for child in node['children']:
        if child['kind'] == 'path':
            yield child
        else:
            yield from descendant_paths(child)


def checked_spans(data, reported, groups, paths):
    """Bind reported byte ranges to the independent complete native parse."""
    assert len(reported) == len(groups)
    for span, group in zip(reported, groups):
        assert [command(item) for item in parsed(data[span['start']:span['end']])] == group['commands']
        assert [command(item)[0] for item in parsed(data[slice(*span['opening'])])] == [group['kind']]
        assert [command(item)[0] for item in parsed(data[slice(*span['closing'])])] == [group['kind'].upper()]
        assert span['paths'] == [next(index for index, value in enumerate(paths) if value is path) for path in descendant_paths(group)]


def rewritten_tree(tree, groups, paths, row):
    """Apply the requested object operation to an independently decoded tree."""
    tree, groups, paths = copy.deepcopy((tree, groups, paths))
    selected, operation = row['selected'], row['operation']
    if operation == 'group':
        assert selected == [18]
        path = paths[18]
        siblings, index = parent(tree, path)
        siblings[index] = dict(kind='u', flags={key: path['state'][key] for key in ('A', 'Xw') if key in path['state']}, children=[path], private=False)
    elif operation == 'reorder':
        assert row['source'] == 'synthetic-state' and selected == [2, 1]
        slots = sorted(selected, key=lambda index: row['before'][index]['start'])
        placements = [(parent(tree, groups[slot]), copy.deepcopy(groups[source])) for slot, source in zip(slots, selected)]
        for (siblings, index), replacement in placements:
            siblings[index] = replacement
    elif operation == 'move':
        assert row['source'] == 'synthetic-state' and selected == [0] and row['anchor'] == 2
        siblings, index = parent(tree, groups[0])
        moved = siblings.pop(index)
        siblings, index = parent(tree, groups[2])
        siblings.insert(index + 1, moved)
    else:
        assert len(selected) == 1
        node = groups[selected[0]]
        siblings, index = parent(tree, node)
        if operation == 'duplicate':
            siblings.insert(index + 1, copy.deepcopy(node))
        elif operation == 'remove':
            siblings.pop(index)
        else:
            assert operation == 'ungroup'
            siblings[index:index + 1] = node['children']
    return view(tree)


def replacement_regions(before, after, edits):
    """Require every byte outside the authorized source intervals unchanged."""
    position, pattern = 0, b''
    for start, end, _ in sorted(edits):
        assert position <= start <= end <= len(before)
        pattern += re.escape(before[position:start]) + b'(.*?)'
        position = end
    match = re.fullmatch(pattern + re.escape(before[position:]), after, re.DOTALL)
    assert match is not None, 'Unselected source bytes changed'
    return [(edit[2], fragment) for edit, fragment in zip(sorted(edits), match.groups())]


def attributes(fragment):
    """Require only declarative assignments in added boundary state."""
    assert b'%AI' not in fragment and b'%%' not in fragment
    result = [command(item) for item in parsed(fragment)]
    assert all(operator in ATTRIBUTES and not private for operator, _, private in result)
    return result


def check_bytes(before, after, row, groups, paths):
    """Check copied group bytes, source assignment provenance and allowed edits."""
    operation, selected, spans = row['operation'], row['selected'], row['before']
    if operation == 'group':
        start, end = row['pathSpans'][18]
        if paths[18]['count'] is not None:
            count = list(re.finditer(rb'(?m)(?:^|\s)([0-9]+)\s+As\b', before[:start]))[-1]
            assert int(count[1]) == paths[18]['count']
            instructions = [command(item) for item in parsed(before[count.start(1):start])]
            assert instructions[0][0] == 'As' and all(value[0] in ATTRIBUTES for value in instructions[1:])
            start = count.start(1)
        assert before[:start] + b'\nu\n' + before[start:end] + b'\nU\n' + before[end:] == after
        return
    if operation == 'ungroup':
        group = spans[selected[0]]
        edits = [(*group['opening'], 'space'), (*group['closing'], 'space')]
    elif operation == 'duplicate':
        group = spans[selected[0]]
        edits = [(group['end'], group['end'], ('copy', selected[0]))]
    elif operation == 'remove':
        group = spans[selected[0]]
        edits = [(group['start'], group['end'], ('remove', selected[0]))]
    elif operation == 'reorder':
        slots = sorted(selected, key=lambda index: spans[index]['start'])
        edits = [(spans[slot]['start'], spans[slot]['end'], ('copy', source)) for slot, source in zip(slots, selected)]
    else:
        group, anchor = spans[selected[0]], spans[row['anchor']]
        edits = [(group['start'], group['end'], ('remove', selected[0])), (anchor['end'], anchor['end'], ('copy', selected[0]))]
    original_assignments = {command(item) for item in parsed(before) if command(item)[0] in ATTRIBUTES}
    for kind, fragment in replacement_regions(before, after, edits):
        if kind == 'space':
            assert fragment == b' '
            continue
        action, index = kind
        if action == 'remove':
            assert attributes(fragment) == [value for value in groups[index]['commands'] if value[0] in ATTRIBUTES]
        else:
            source = before[spans[index]['start']:spans[index]['end']]
            assert fragment.count(source) == 1
            prefix, suffix = fragment.split(source)
            assert all(value in original_assignments for value in attributes(prefix) + attributes(suffix))


def main():
    """Verify all variants against pinned sources and an unchanged external reader."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/group-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 13 and {(row['source'], row['operation']) for row in rows} == {
        (source, operation) for source in ('simple_shapes.ai', 'simple_shapes_cc.ai') for operation in ('group', 'duplicate', 'remove', 'ungroup')
    } | {('synthetic-state', operation) for operation in ('duplicate', 'remove', 'ungroup', 'reorder', 'move')}
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    results = []
    for row in rows:
        before_file, after_file = args.output / row['original'], args.output / row['result']
        before, after = before_file.read_bytes(), after_file.read_bytes()
        if row['source'] == 'synthetic-state':
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
        elif row['operation'] == 'group':
            path = Path('test/corpus/files', row['source'])
            entry = next(entry for entry in manifest if entry['file'] == row['source'])
            data = path.read_bytes()
            assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if data.startswith(b'%PDF-') else [inkai.extract(str(path))])
        else:
            assert row['original'] in {result['file'] for result in results}
        original, groups, paths = inventory(inkai.parse(str(before_file)))
        changed, new_groups, new_paths = inventory(inkai.parse(str(after_file)))
        checked_spans(before, row['before'], groups, paths)
        checked_spans(after, row['after'], new_groups, new_paths)
        for path, span in zip(paths, row['pathSpans']):
            commands = [command(item) for item in parsed(before[slice(*span)])]
            assert [(name, values) for name, values, _ in commands[:-1]] == path['geometry'] and commands[-1][0] == path['paint']
        assert rewritten_tree(original, groups, paths, row) == view(changed), row['result']
        check_bytes(before, after, row, groups, paths)
        results.append(dict(file=row['result'], groupsBefore=len(groups), groupsAfter=len(new_groups), pathsBefore=len(paths), pathsAfter=len(new_paths)))
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=results), indent=2) + '\n')


if __name__ == '__main__':
    main()
