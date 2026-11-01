#!/usr/bin/env python3
"""Verify complete CC compound/clip lifecycle against unmodified producer data."""

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
from verify_native_compound_lifecycle import normalized_paths
from verify_native_contour_group_movement import PRODUCERS, attribute, bound, groups, scalar, structural
from verify_native_contour_movement import interpreter_state, reads, states
from verify_native_group_lifecycle import ATTRIBUTES, command, parent
from verify_native_path_lifecycle import BOUNDS
from verify_native_structure import parsed


def verify(inkai, output, row, prefix):
    """Require prescribed topology, exact surviving owners and both state streams."""
    name, variant = row['source'], row['variant']
    predecessor = {'release': 'original', 'recompound': 'release', 'clip': 'original', 'unclip': 'clip'}[variant]
    assert row['predecessor'] == predecessor
    original_file, result_file = output / f'{name}.{predecessor}.ps', output / f'{name}.{variant}.ps'
    before, after = original_file.read_bytes(), result_file.read_bytes()
    original_doc, actual_doc = inkai.parse(str(original_file)), inkai.parse(str(result_file))
    old_tree, old_paths = bound(before, original_doc, row['before'])
    actual_tree, new_paths = bound(after, actual_doc, row['after'])
    assert len(old_paths) == len(new_paths) == 5
    expected_tree = deepcopy(old_tree)
    owners = groups(expected_tree)
    edits = []
    if variant in ('release', 'unclip'):
        selected = next(node for node in owners if node['kind'] == ('compound' if variant == 'release' else 'clip'))
        index = owners.index(selected)
        siblings, position = parent(expected_tree, selected)
        siblings[position:position + 1] = selected['children']
        span = row['before']['groups'][index]
        edits.extend([(span['owner'][0], span['opening'][1], ('exact', b' ')), (span['closing'][0], span['owner'][1], ('replay', None))])
    else:
        if variant == 'clip':
            selected = next(node for node in owners if node['kind'] == 'compound')
            siblings, position = parent(expected_tree, selected)
            children = [selected]
            span = row['before']['groups'][owners.index(selected)]
            start, end = span['owner']
        else:
            selected = next(node for node in owners if node['kind'] == 'group' and any(child['kind'] == 'path' for child in node['children']))
            siblings, position = selected['children'], 0
            children = list(siblings)
            assert all(child['kind'] == 'path' for child in children) and len(children) == 5
            first = row['before']['paths'][0]
            start, end = (first['count'] or first['geometry'][0])[0], row['before']['paths'][-1]['paint'][1]
        kind, opening, closing = ('clip', b'q', b'Q') if variant == 'clip' else ('compound', b'*u', b'*U')
        siblings[position:position + len(children)] = [dict(kind=kind, private=False, children=children, metadata=None, expanded=None, style=None)]
        edits.extend([(start, start, ('exact', b'\n' + opening + b'\n')), (end, end, ('closing', closing))])
    assert structural(actual_tree) == structural(expected_tree), (name, variant, 'geometry, identities, metadata or owner tree')
    expected_paths = normalized_paths(original_doc)
    for index, path in enumerate(expected_paths):
        if variant == 'release':
            assert path['owners'].pop() == '*u'
        elif variant == 'recompound':
            path['owners'].append('*u')
        elif variant == 'clip':
            path['owners'].insert(len(path['owners']) - 1, 'q')
            path['controls'] = ['h', 'W']
            span = row['before']['paths'][index]
            edits.append((span['paint'][0], span['paint'][0], ('exact', b'h W ')))
        else:
            assert path['owners'].pop(-2) == 'q'
            path['controls'] = []
            edits.extend((*span, ('exact', b' ')) for span in row['before']['paths'][index]['controls'])
    assert normalized_paths(actual_doc) == expected_paths, (name, variant, 'mask/count topology')
    for old, new in zip(re.finditer(BOUNDS, before), re.finditer(BOUNDS, after), strict=True):
        values = list(map(float, old[1].split()))
        assert list(map(float, new[1].split())) == [min(values[0], 0), min(values[1], 0), max(values[2], 20), max(values[3], 20)]
        edits.append((old.start(), old.end(), ('exact', new[0])))
    available = {attribute(command(item)[:2]) for item in walk_body(original_doc.trailer) if command(item)[0] in ATTRIBUTES}
    for label, fragment in state_regions(before, after, edits):
        commands = [command(item) for item in parsed(fragment)]
        if label[0] == 'closing':
            assert commands.pop(0) == (label[1].decode(), (), False)
        assert all(operator in ATTRIBUTES and attribute((operator, operands)) in available for operator, operands, _ in commands), 'Invented replay data'
    old_states, _, old_final = states(original_doc)
    new_states, _, new_final = states(actual_doc)
    assert list(map(scalar, old_final)) == list(map(scalar, new_final))
    for index, (old, new) in enumerate(zip(old_states, new_states, strict=True)):
        for previous, current in zip(old['effective'], new['effective'], strict=True):
            previous, current = scalar(previous), scalar(current)
            consumed = reads(old_paths[index]['paint'])
            assert {key: previous.get(key) for key in consumed} == {key: current.get(key) for key in consumed}, (name, variant, index, 'consumed state')
    for native in (False, True):
        old_values, _, old_final = interpreter_state(original_doc, prefix, native)
        new_values, _, new_final = interpreter_state(actual_doc, prefix, native)
        assert old_final == new_final, (name, variant, 'Adobe-prolog final attributes')
        assert old_values == new_values, (name, variant, 'Adobe-prolog contour attributes')


def main():
    """Require all eight transactions from independently extracted pinned sources."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/imported-contour-lifecycle'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    prefix = prolog()
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    for name in PRODUCERS:
        fixture, entry = Path('test/corpus/files', name), manifest[name]
        assert fixture.stat().st_size == entry['size'] and hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256'] and entry['revision'] == REVISION and entry['license']
        assert native_programs(fixture) == [(args.output / f'{name}.original.ps').read_bytes()]
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 8 and {(row['source'], row['variant']) for row in rows} == {(name, variant) for name in PRODUCERS for variant in ('release', 'recompound', 'clip', 'unclip')}
    for row in rows:
        verify(inkai, args.output, row, prefix)
        print(row['source'], row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=[f'{row["source"]}/{row["variant"]}' for row in rows], producerTransactions=8, adobeProlog='inkscape_minimized_ai7.ai', ghostscript=subprocess.check_output(['gs', '--version'], text=True).strip(), stateProjections=16), indent=2) + '\n')


if __name__ == '__main__':
    main()
