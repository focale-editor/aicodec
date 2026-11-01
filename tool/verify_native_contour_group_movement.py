#!/usr/bin/env python3
"""Verify complete contour-group moves, retained byte owners and consumed state."""

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
from verify_native_contour_movement import interpreter_state, reads, states
from verify_native_group_lifecycle import ATTRIBUTES, command, checked_spans, inventory as group_inventory, parent
from verify_native_objects import inventory as object_inventory
from verify_native_path_lifecycle import BOUNDS
from verify_native_path_topology import bind, inventory
from verify_native_structure import parsed

SOURCES = {
    'synthetic': '2022bbdc4f24e6f58c5c273c4099b811ba8aa0baba41bd1e848392500066b524',
    'scope-saved': 'ac5d913779fe0a0b44d323b3bcc2c0fba1e1c34bd00867918d9c153097287058',
    'scope-enclosing': '4376430871212183e6d004214d5b23540d823efb140c46395d4fd01397da7a08',
}
PRODUCERS = ('inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai')


def attribute(value):
    """Normalize only PostScript dash whitespace that the reader leaves lexical."""
    operator, operands = value
    if operator == 'd':
        match = re.fullmatch(rb'\[\s*([^\[\]]*)\s*\]\s*([\d.eE+\-]+)', b' '.join(operands))
        assert match is not None
        operands = tuple(map(float, match[1].split())), float(match[2])
    return operator, operands


def scalar(values):
    """Compare literal assignments independently of dash-array token spacing."""
    return {key: attribute(value) for key, value in values.items()}


def requests():
    """Prescribe selected trees, parent/anchor ownership and predecessor snapshots."""
    result = {
        ('synthetic', 'compound'): ('original', [0], 4, None),
        ('synthetic', 'clip'): ('original', [2], 4, None),
        ('synthetic', 'batch'): ('original', [4, 2], 5, None),
        ('synthetic', 'anchor'): ('original', [0], 2, 1),
        ('synthetic', 'root'): ('original', [0], None, None),
        ('synthetic', 'mask-root'): ('original', [3], None, None),
        ('scope-saved', 'move'): ('original', [2], 0, None),
        ('scope-enclosing', 'move'): ('original', [2], 0, None),
    }
    for name in PRODUCERS:
        result[name, 'view'] = 'original', [2], 0, None
        result[name, 'restore'] = 'view', [1], 'layer', 2
    return result


def groups(tree):
    """List independently parsed groups in their closing-boundary order."""
    result = []
    for node in tree:
        result.extend(groups(node.get('children', [])))
        if node['kind'] in ('group', 'compound', 'clip'):
            result.append(node)
    return result


def structural(tree):
    """Retain full geometry, hierarchy, metadata and layer/header properties."""
    return [{key: structural(value) if key == 'children' else value for key, value in node.items() if key not in ('commands', 'state', 'flags')} for node in tree]


def bound(data, document, report):
    """Bind every reported path, group and complete metadata owner independently."""
    paths = inventory(document)
    assert len(paths) == len(report['paths'])
    for path, span in zip(paths, report['paths'], strict=True):
        bind(data, span, path)
    _, decoded, children = group_inventory(document)
    checked_spans(data, report['groups'], decoded, children)
    tree = object_inventory(document)
    for node, span in zip(groups(tree), report['groups'], strict=True):
        start, end = span['owner']
        prefix = [command(item) for item in parsed(data[start:span['start']])]
        assert prefix == ([] if node['expanded'] is None else [('Ae', (b'1' if node['expanded'] else b'0',), False)])
        tail = parsed(data[span['end']:end])
        if node['metadata'] is not None:
            assert tail.pop(0) == node['metadata']
        assert [command(item) for item in tail] == ([] if node['style'] is None else [node['style']])
    return tree, paths


def moved_order(spans, selected, position, boundaries):
    """Derive object order from selected original ranges, without trusting the writer."""
    copied = [index for owner in selected for index, boundary in enumerate(boundaries) if spans[owner]['owner'][0] <= boundary < spans[owner]['owner'][1]]
    assert len(copied) == len(set(copied))
    return [index for index, boundary in enumerate(boundaries) if boundary < position and index not in copied] + copied + [index for index, boundary in enumerate(boundaries) if boundary >= position and index not in copied]


def verify(inkai, output, row, request, prefix):
    """Compare prescribed tree relocation, both state projections and exact bytes."""
    predecessor, selected, target, anchor = request
    name, variant = row['source'], row['variant']
    original_file, result_file = output / f'{name}.{predecessor}.ps', output / f'{name}.{variant}.ps'
    before, after = original_file.read_bytes(), result_file.read_bytes()
    original_doc, actual_doc = inkai.parse(str(original_file)), inkai.parse(str(result_file))
    old_tree, old_paths = bound(before, original_doc, row['before'])
    actual_tree, new_paths = bound(after, actual_doc, row['after'])
    expected_tree = deepcopy(old_tree)
    original_groups = groups(expected_tree)
    destination = expected_tree if target is None else next(node for node in expected_tree if node['kind'] == 'layer')['children'] if target == 'layer' else original_groups[target]['children']
    moved = [original_groups[index] for index in selected]
    for node in moved:
        siblings, index = parent(expected_tree, node)
        assert siblings[index] is node
        siblings.pop(index)
    insertion = len(destination) if anchor is None else next(index + 1 for index, node in enumerate(destination) if node is original_groups[anchor])
    destination[insertion:insertion] = moved
    assert structural(actual_tree) == structural(expected_tree), (name, variant, 'complete tree')
    spans = row['before']['groups']
    position = spans[anchor]['owner'][1] if anchor is not None else re.search(br'^%%(?:PageTrailer|Trailer|EOF)\b', before, re.MULTILINE).start() if target is None else spans[target]['closing'][0]
    path_order = moved_order(spans, selected, position, [path['geometry'][0][0] for path in row['before']['paths']])
    group_order = moved_order(spans, selected, position, [group['closing'][0] for group in spans])
    original_states, original_group_states, original_final = states(original_doc)
    actual_states, actual_group_states, actual_final = states(actual_doc)
    assert list(map(scalar, original_final)) == list(map(scalar, actual_final)), (name, variant, 'final scalar state')
    for result_index, source_index in enumerate(path_order):
        assert {key: value for key, value in old_paths[source_index].items() if key != 'owners'} == {key: value for key, value in new_paths[result_index].items() if key != 'owners'}
        for old, new in zip(original_states[source_index]['effective'], actual_states[result_index]['effective'], strict=True):
            old, new = scalar(old), scalar(new)
            assert {key: old.get(key) for key in reads(old_paths[source_index]['paint'])} == {key: new.get(key) for key in reads(new_paths[result_index]['paint'])}, (name, variant, source_index, 'consumed scalar state')
    for result_index, source_index in enumerate(group_order):
        assert original_group_states[source_index]['flags'] == actual_group_states[result_index]['flags'], (name, variant, source_index, 'group flags')
    edits = [(*spans[index]['owner'], ('state', index)) for index in selected]
    for old, new in zip(re.finditer(BOUNDS, before), re.finditer(BOUNDS, after), strict=True):
        values = list(map(float, old[1].split()))
        assert list(map(float, new[1].split())) == [min(values[0], 0), min(values[1], 0), max(values[2], 20), max(values[3], 20)]
        edits.append((old.start(), old.end(), ('exact', new[0])))
    edits.append((position, position, ('insert', None)))
    fragments = []
    for label, fragment in state_regions(before, after, edits):
        if label[0] == 'insert':
            copied = [before[slice(*spans[index]['owner'])] for index in selected]
            match = re.fullmatch(b'(.*?)' + b'(.*?)'.join(re.escape(value) for value in copied) + b'(.*?)', fragment, re.DOTALL)
            assert match is not None, 'Copied complete owner bytes changed'
            fragments.extend(match.groups())
        else:
            fragments.append(fragment)
    available = {attribute(command(item)[:2]) for item in walk_body(original_doc.trailer) if command(item)[0] in ATTRIBUTES}
    assert all(command(item)[0] in ATTRIBUTES and attribute(command(item)[:2]) in available for fragment in fragments for item in parsed(fragment)), 'State replay invents an assignment'
    for native in [False, True]:
        old_values, _, old_final = interpreter_state(original_doc, prefix, native)
        new_values, _, new_final = interpreter_state(actual_doc, prefix, native)
        assert old_final == new_final, 'Adobe-prolog final contour attributes changed'
        for result_index, source_index in enumerate(path_order):
            if old_paths[source_index]['paint'].upper() in ('S', 'B'):
                assert old_values[source_index] == new_values[result_index], (name, variant, source_index, native, 'Adobe-prolog consumed contour attributes')


def main():
    """Require every pinned synthetic and complete-producer transaction to pass."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/contour-group-movement'))
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
        assert fixture.stat().st_size == entry['size'] and hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256'] and entry['revision'] == REVISION
        assert native_programs(fixture) == [(args.output / f'{name}.original.ps').read_bytes()]
    rows = json.loads((args.output / 'report.json').read_text())
    expected = requests()
    assert len(rows) == len(expected) == 12 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    for row in rows:
        verify(inkai, args.output, row, expected[row['source'], row['variant']], prefix)
        print(row['source'], row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=[f'{row["source"]}/{row["variant"]}' for row in rows], producerTransactions=4, adobeProlog='inkscape_minimized_ai7.ai', ghostscript=subprocess.check_output(['gs', '--version'], text=True).strip(), stateProjections=24), indent=2) + '\n')


if __name__ == '__main__':
    main()
