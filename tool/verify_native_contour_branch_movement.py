#!/usr/bin/env python3
"""Verify compound-branch movement, changed clip scopes and literal state replay."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_clipping_lifecycle import prolog, state_regions
from verify_native_contour_group_movement import PRODUCERS, attribute, bound, groups, moved_order, scalar, structural
from verify_native_contour_movement import FLAGS, interpreter_state, reads, states
from verify_native_group_lifecycle import ATTRIBUTES, command, parent
from verify_native_objects import objects
from verify_native_path_lifecycle import BOUNDS
from verify_native_structure import parsed

SOURCES = {
    'ordinary': '7bde4077dad28183501b112128c16fe793c143f83ed59e87cbcc1ea3cf08bbfa',
    'mask': '7d91f11935a89a0a74875eda8e195d19b565f4166696e92720424baa2436215f',
    'mask-tree': 'bf8d95dcb82f298cf679cea4fad94cae7564f1509248dd105c7e36a578b36381',
}


def requested(tree, name, variant):
    """Resolve the prescribed selection independently of writer-supplied indices."""
    owners = groups(tree)
    if name in PRODUCERS:
        branch = next(node for node in owners if node['kind'] == 'group' and len([child for child in objects(node['children']) if child['kind'] == 'path']) == 1)
        target = owners[-1] if variant == 'extract' else next(node for node in owners if node['kind'] == 'compound')
    else:
        named = {(node.get('metadata') or {}).get('AI10_ArtUID'): node for node in owners}
        branch = named['Destination' if variant == 'enter' else 'Tree' if name == 'mask-tree' else 'Branch']
        target = named[{'extract': 'Destination', 'reorder': 'Source', 'restore': 'Source', 'nest': 'Sibling', 'adopt': 'Target', 'enter': 'Target'}[variant]]
    return owners.index(branch), owners.index(target)


def branch_pattern(data, report, selected, paint):
    """Allow only scalar insertions at consumers and the prescribed paint change."""
    span = report['groups'][selected]
    start, end = span['owner']
    boundaries = {start}
    changes = {}
    for group in report['groups']:
        if start <= group['start'] < group['end'] <= end:
            boundaries.update((group['opening'][0], group['closing'][0]))
    for path in report['paths']:
        if start <= path['geometry'][0][0] < path['paint'][1] <= end:
            boundaries.add(path['geometry'][0][0])
            if paint is not None:
                left, right = path['paint']
                original = data[left:right]
                changes[left] = right, paint.lower() if original.islower() else paint.upper()
    result, position = [], start
    for boundary in sorted(boundaries | changes.keys()):
        result.append(re.escape(data[position:boundary]))
        if boundary in boundaries:
            result.append(b'(.*?)')
        position = boundary
        if boundary in changes:
            position, replacement = changes[boundary]
            result.append(re.escape(replacement.encode('ascii')))
    result.append(re.escape(data[position:end]))
    return b''.join(result)


def verify(inkai, output, row, prefix):
    """Compare the complete prescribed tree, exact source patches and consumed state."""
    name, variant = row['source'], row['variant']
    predecessor = 'extract' if variant == 'restore' else 'prepared' if name in PRODUCERS else 'original'
    assert row['predecessor'] == predecessor
    original_file, result_file = output / f'{name}.{predecessor}.ps', output / f'{name}.{variant}.ps'
    before, after = original_file.read_bytes(), result_file.read_bytes()
    original_doc, actual_doc = inkai.parse(str(original_file)), inkai.parse(str(result_file))
    old_tree, old_paths = bound(before, original_doc, row['before'])
    actual_tree, new_paths = bound(after, actual_doc, row['after'])
    expected_tree = deepcopy(old_tree)
    original_groups = groups(expected_tree)
    selected, target = requested(expected_tree, name, variant)
    branch, destination = original_groups[selected], original_groups[target]
    compound = destination if destination['kind'] == 'compound' else None
    if compound is None:
        for node in original_groups:
            if node['kind'] == 'compound' and any(child is destination for child in objects(node['children'])):
                compound = node
    compound_index = None if compound is None else original_groups.index(compound)
    old_states, old_group_states, old_final = states(original_doc)
    new_states, new_group_states, new_final = states(actual_doc)
    target_path = None if compound_index is None else row['before']['groups'][compound_index]['paths'][-1]
    paint = None if target_path is None else old_paths[target_path]['paint'].upper()
    moved_paths = row['before']['groups'][selected]['paths']
    if paint is not None:
        for node in objects(branch['children']):
            if node['kind'] == 'path':
                node['paint'] = paint.lower() if node['paint'].islower() else paint
    siblings, index = parent(expected_tree, branch)
    assert siblings.pop(index) is branch
    destination['children'].append(branch)
    assert structural(actual_tree) == structural(expected_tree), (name, variant, 'complete tree')
    spans = row['before']['groups']
    position = spans[target]['closing'][0]
    path_order = moved_order(spans, [selected], position, [path['geometry'][0][0] for path in row['before']['paths']])
    group_order = moved_order(spans, [selected], position, [group['closing'][0] for group in spans])
    assert list(map(scalar, old_final)) == list(map(scalar, new_final)), (name, variant, 'final state')
    for result_index, source_index in enumerate(path_order):
        expected_path = {key: value for key, value in old_paths[source_index].items() if key != 'owners'}
        if source_index in moved_paths and paint is not None:
            expected_path['paint'] = paint.lower() if expected_path['paint'].islower() else paint
        assert expected_path == {key: value for key, value in new_paths[result_index].items() if key != 'owners'}, (name, variant, 'path topology')
        for projection in (0, 1):
            wanted = scalar(old_states[source_index]['effective'][projection])
            if source_index in moved_paths and compound_index is not None:
                shared = scalar(old_group_states[compound_index]['state'][projection])
                wanted = {**{key: value for key, value in shared.items() if key not in FLAGS}, **{key: value for key, value in wanted.items() if key in FLAGS}}
            actual = scalar(new_states[result_index]['effective'][projection])
            consumed = reads(expected_path['paint'])
            assert {key: wanted.get(key) for key in consumed} == {key: actual.get(key) for key in consumed}, (name, variant, source_index, projection, 'consumed state')
    for result_index, source_index in enumerate(group_order):
        assert old_group_states[source_index]['flags'] == new_group_states[result_index]['flags'], (name, variant, source_index, 'group flags')
    edits = [(*spans[selected]['owner'], ('state', None)), (position, position, ('insert', None))]
    for old, new in zip(re.finditer(BOUNDS, before), re.finditer(BOUNDS, after), strict=True):
        values = list(map(float, old[1].split()))
        assert list(map(float, new[1].split())) == [min(values[0], 0), min(values[1], 0), max(values[2], 20), max(values[3], 20)]
        edits.append((old.start(), old.end(), ('exact', new[0])))
    fragments = []
    for label, fragment in state_regions(before, after, edits):
        if label[0] == 'insert':
            match = re.fullmatch(b'(.*?)' + branch_pattern(before, row['before'], selected, paint) + b'(.*?)', fragment, re.DOTALL)
            assert match is not None, (name, variant, 'branch source bytes')
            fragments.extend(match.groups())
        else:
            fragments.append(fragment)
    available = {attribute(command(item)[:2]) for item in walk_body(original_doc.trailer) if command(item)[0] in ATTRIBUTES}
    assert all(command(item)[0] in ATTRIBUTES and attribute(command(item)[:2]) in available for fragment in fragments for item in parsed(fragment)), (name, variant, 'invented replay')
    for native in (False, True):
        old_values, _, old_final = interpreter_state(original_doc, prefix, native)
        new_values, _, new_final = interpreter_state(actual_doc, prefix, native)
        assert old_final == new_final, (name, variant, native, 'Adobe-prolog final attributes')
        for result_index, source_index in enumerate(path_order):
            if new_paths[result_index]['paint'].upper() in ('S', 'B'):
                expected_index = target_path if source_index in moved_paths and target_path is not None else source_index
                assert old_values[expected_index] == new_values[result_index], (name, variant, source_index, native, 'Adobe-prolog stroke attributes')


def preparation(inkai, output, name):
    """Prove that producer preparation adds exactly two ordinary group delimiters."""
    original_file, prepared_file = output / f'{name}.original.ps', output / f'{name}.prepared.ps'
    before, after = original_file.read_bytes(), prepared_file.read_bytes()
    report = json.loads((output / f'{name}.preparation.json').read_text())
    original_doc, prepared_doc = inkai.parse(str(original_file)), inkai.parse(str(prepared_file))
    tree, paths = bound(before, original_doc, report['before'])
    actual_tree, actual_paths = bound(after, prepared_doc, report['after'])
    first = report['before']['paths'][0]
    start, end = (first['count'] or first['geometry'][0])[0], first['paint'][1]
    assert (report['start'], report['end']) == (start, end)
    assert after == before[:start] + b'\nu\n' + before[start:end] + b'\nU\n' + before[end:]
    branch = next(node for node in objects(tree) if node['kind'] == 'path')
    siblings, index = parent(tree, branch)
    siblings[index:index + 1] = [dict(kind='group', private=False, children=[branch], metadata=None, expanded=None, style=None)]
    assert structural(tree) == structural(actual_tree)
    assert len(paths) == len(actual_paths) == 5
    for original, prepared in zip(states(original_doc)[0], states(prepared_doc)[0], strict=True):
        assert original['effective'] == prepared['effective']


def main():
    """Require all pinned transactions and both exact producer preparations."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/contour-branch-movement'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    prefix = prolog()
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    for name, expected in SOURCES.items():
        assert hashlib.sha256((args.output / f'{name}.original.ps').read_bytes()).hexdigest() == expected
    for name in PRODUCERS:
        fixture, entry = Path('test/corpus/files', name), manifest[name]
        assert fixture.stat().st_size == entry['size'] and hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256'] and entry['revision'] == REVISION and entry['license']
        assert native_programs(fixture) == [(args.output / f'{name}.original.ps').read_bytes()]
        preparation(inkai, args.output, name)
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {(name, variant) for name in ('ordinary', 'mask') for variant in ('extract', 'reorder', 'adopt', 'restore')} | {('ordinary', 'nest'), ('ordinary', 'enter')} | {(name, variant) for name in (*PRODUCERS, 'mask-tree') for variant in ('extract', 'restore')}
    assert len(rows) == len(expected) == 16 and {(row['source'], row['variant']) for row in rows} == expected
    for row in rows:
        verify(inkai, args.output, row, prefix)
        print(row['source'], row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=[f'{row["source"]}/{row["variant"]}' for row in rows], preparedProducerTransactions=4, producerPreparations=2, adobeProlog='inkscape_minimized_ai7.ai', ghostscript=subprocess.check_output(['gs', '--version'], text=True).strip(), stateProjections=32), indent=2) + '\n')


if __name__ == '__main__':
    main()
