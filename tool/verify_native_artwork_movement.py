#!/usr/bin/env python3
"""Verify cross-layer artwork with pinned inkai, topology and exact source bytes."""

import argparse
import copy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import GEOMETRY
from verify_native_group_lifecycle import ATTRIBUTES, PAINT, attributes, parent
from verify_native_layer_lifecycle import inventory
from verify_native_layers import commands, verified_inventory, verify_insertion
from verify_native_path_lifecycle import checked_count, patch
from verify_native_structure import parsed

SYNTHETIC_SHA256 = '17f814778bd5935db66662f5f957bcb3e2b196ef3d901479afa44b78a48ba347'


def objects(tree):
    """Collect path order and postorder group identities from the external tree."""
    groups, paths = [], []
    for node in tree:
        if node['kind'] == 'path':
            paths.append(node)
        else:
            nested, contained = objects(node['children'])
            groups.extend(nested)
            paths.extend(contained)
            if node['kind'] != 'Lb':
                groups.append(node)
    return groups, paths


def source_commands(data, span, private):
    """Restore an enclosing private-line marker omitted by an operand byte span."""
    fragment = data[span['start']:span['end']]
    if private:
        line = data[data.rfind(b'\n', 0, span['start']) + 1:span['start']]
        assert line.startswith(b'%_')
        fragment = b'%_' + fragment
    return commands(parsed(fragment))


def checked_spans(data, document, report, tree):
    """Bind every reported object/count span to independently parsed commands."""
    trace = commands(document.trailer)
    group_traces, path_traces, stack, geometry = [], [], [], []
    for index, value in enumerate(trace):
        operator = value[0]
        if operator in ('u', '*u', 'q'):
            stack.append(index)
        elif operator in ('U', '*U', 'Q'):
            first = stack.pop()
            assert trace[first][0].upper() == operator
            group_traces.append(trace[first:index + 1])
        elif operator in GEOMETRY:
            geometry.append(value)
        elif operator in PAINT and geometry:
            path_traces.append(geometry + [value])
            geometry = []
    assert not stack and not geometry
    groups, paths = objects(tree)
    assert len(groups) == len(group_traces) == len(report['groups'])
    assert len(paths) == len(path_traces) == len(report['paths'])
    for span, values, node in zip(report['paths'], path_traces, paths):
        assert source_commands(data, span, values[0][2]) == values
        checked_count(data, span['count'], node['count'])
    for span, values, node in zip(report['groups'], group_traces, groups):
        assert source_commands(data, span, values[0][2]) == values
        contained = objects(node['children'])[1]
        assert span['paths'] == [next(index for index, path in enumerate(paths) if path is child) for child in contained]
    return groups, paths


def expected_tree(tree, owners, groups, paths, row):
    """Apply the requested ownership change without changing object attributes."""
    tree, owners, groups, paths = copy.deepcopy((tree, owners, groups, paths))
    operation, selected = row['operation'], row['selected']
    if operation == 'group':
        path = paths[selected]
        siblings, index = parent(tree, path)
        siblings[index] = dict(kind='u', flags={key: path['state'][key] for key in ('A', 'Xw') if key in path['state']}, private=False, children=[path])
    else:
        assert row['inheritParentFlags'] is True
        nodes = paths if operation.startswith('path-') else groups
        moved = nodes[selected]
        siblings, index = parent(tree, moved)
        siblings.pop(index)
        if operation.endswith('-layer'):
            owners[row['layer']]['children'].append(moved)
        else:
            assert operation.endswith('-after')
            siblings, index = parent(tree, nodes[row['anchor']])
            siblings.insert(index + 1, moved)
    return tree


def verify_bytes(before, after, report, paths, original_assignments):
    """Allow only relocation spans and copied, independently decoded state values."""
    operation, selected = report['operation'], report['selected']
    if operation == 'group':
        span = report['before']['paths'][selected]
        start = span['count'][0] if span['count'] is not None else span['start']
        assert patch(before, [(start, start, b'\nu\n'), (span['end'], span['end'], b'\nU\n')]) == after
        return
    kind = 'paths' if operation.startswith('path-') else 'groups'
    source = report['before'][kind][selected]
    core = before[source['start']:source['end']]
    if operation.endswith('-layer'):
        position = report['before']['layers']['layers'][report['layer']]['closing'][0]
    else:
        position = report['before'][kind][report['anchor']]['end']
    edits = [(source['start'], source['end'], 'remove')]
    if kind == 'paths':
        core = checked_count(before, source['count'], paths[selected]['count']) + core
        if source['count'] is not None:
            edits.append((*source['count'], 'count'))
        retained = []
    else:
        retained = [value for value in commands(parsed(core)) if value[0] in ATTRIBUTES]
    edits.append((position, position, 'copy'))
    assignment = rb'[ \t\r\n0-9.eE+\-\[\]A-Za-z]*'
    offset, pattern = 0, b''
    for start, end, action in sorted(edits):
        assert offset <= start <= end <= len(before)
        replacement = b' '
        if action == 'copy':
            replacement = assignment + re.escape(core) + assignment
        elif action == 'remove' and kind == 'groups':
            replacement = rb'\s*'
            for operator, operands, private in retained:
                assert not private
                replacement += rb'\s*'.join(re.escape(value) for value in (*operands, operator.encode())) + rb'\b\s*'
        pattern += re.escape(before[offset:start]) + b'(' + replacement + b')'
        offset = end
    match = re.fullmatch(pattern + re.escape(before[offset:]), after)
    assert match is not None, 'Unselected native bytes changed'
    for (_, _, action), fragment in zip(sorted(edits), match.groups()):
        if action == 'copy':
            assert fragment.count(core) == 1
            prefix, suffix = fragment.split(core)
            assert all(value in original_assignments for value in attributes(prefix) + attributes(suffix))
        elif action == 'remove' and kind == 'groups':
            assert attributes(fragment) == retained


def main():
    """Require exact provenance, complete transaction coverage and external parses."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artwork-movement'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {source + '.' + operation + '.ps' for source in ('simple_shapes.ai', 'simple_shapes_cc.ai') for operation in ('insert', 'path', 'group', 'subtree')}
    expected |= {'synthetic-state.' + variant + '.ps' for variant in ('path-forward', 'path-backward', 'group-forward', 'group-backward', 'path-empty', 'group-empty')}
    assert len(rows) == 14 and {row['result'] for row in rows} == expected
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    verified = set()
    for row in rows:
        source, target = args.output / row['original'], args.output / row['result']
        before, after = source.read_bytes(), target.read_bytes()
        if row['source'] == 'synthetic-state':
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC_SHA256
        elif row['operation'] == 'insert':
            entry = next(value for value in manifest if value['file'] == row['source'])
            path = Path('test/corpus/files', row['source'])
            data = path.read_bytes()
            assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if data.startswith(b'%PDF-') else [inkai.extract(str(path))])
        else:
            assert row['original'] in verified
        old_layers = verified_inventory(inkai, source, row['before']['layers'])
        new_layers = verified_inventory(inkai, target, row['after']['layers'])
        if row['operation'] == 'insert':
            variant = dict(selected=0, name=list(b'Destination'), identifier=list(b'AiCodec_destination'), after=row['after']['layers'])
            verify_insertion(before, after, old_layers, new_layers, dict(before=row['before']['layers']), variant)
        else:
            document, changed_document = inkai.parse(str(source)), inkai.parse(str(target))
            tree, owners = inventory(document)
            changed, _ = inventory(changed_document)
            groups, paths = checked_spans(before, document, row['before'], tree)
            checked_spans(after, changed_document, row['after'], changed)
            assert expected_tree(tree, owners, groups, paths, row) == changed, row['result']
            original_assignments = {value for value in commands(document.trailer) if value[0] in ATTRIBUTES}
            verify_bytes(before, after, row, paths, original_assignments)
        verified.add(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=sorted(verified), movements=10, prerequisiteInsertions=2, prerequisiteGroups=2), indent=2) + '\n')


if __name__ == '__main__':
    main()
