#!/usr/bin/env python3
"""Verify moved contour ownership, shared appearance and exact preserved bytes."""

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
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_clipping_lifecycle import state_regions, prolog, OPERATORS
from verify_native_group_lifecycle import ATTRIBUTES, command, inventory as group_inventory, checked_spans
from verify_native_objects import inventory as object_inventory, objects
from verify_native_path_lifecycle import PAINT, patch, BOUNDS
from verify_native_path_topology import inventory, bind
from verify_native_structure import parsed

SOURCES = {
    'synthetic': 'aa1a2bf84185f384b452ff50d95bc73f395ebb1be8415856ca5e4e38c79c17d6',
    'batch': 'd6498e5b37987b7b97382a5f0f6a590bea3565c34f0be008d92735a66e9e2a68',
}
PRODUCERS = ('inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai')
FLAGS = {'A', 'Xw', 'Ap', 'D'}
SCOPED = {'J', 'j', 'w', 'M', 'd'}


def requests():
    """Prescribe every source handle, target owner, anchor and mask change."""
    result = {
        ('synthetic', 'leave'): ([0], 3, None, None, False),
        ('synthetic', 'enter'): ([0], 2, None, None, True),
        ('synthetic', 'reorder'): ([1, 0], 0, None, None, False),
        ('synthetic', 'anchor'): ([6], 3, 4, None, False),
        ('synthetic', 'mask'): ([0], 4, None, 'closed', False),
        ('synthetic', 'clear'): ([5, 0], 3, None, 'none', False),
        ('batch', 'reverse'): (list(range(199, -1, -1)), 1, None, None, False),
    }
    for name in PRODUCERS:
        result[name, 'reorder'] = list(range(4, -1, -1)), 1, None, None, False
        result[name, 'leave'] = [1], 2, None, None, False
    return result


def states(document):
    """Read native/printing assignments and compound consumption independently."""
    printing, native, stack, groups, paths = {}, {}, [], [], []
    ordinal = 0
    for item in walk_body(document.trailer):
        operator, operands, private = command(item)
        if operator in ATTRIBUTES:
            key = 'fill' if operator in ('g', 'k', 'Xa') else 'stroke' if operator in ('G', 'K', 'XA') else operator
            native[key] = operator, operands
            if not private:
                printing[key] = operator, operands
        elif operator in ('u', '*u', 'q', 'Lb'):
            node = dict(kind=operator, ordinal=ordinal, flags=[{key: values.get(key) for key in ('A', 'Xw')} for values in (printing, native)])
            node['owners'] = [(parent['kind'], parent['ordinal']) for parent in stack] + [(operator, ordinal)]
            node['saved'] = [dict(values) for values in (printing, native)] if operator == 'q' and not any(parent['kind'] == '*u' for parent in stack) else None
            stack.append(node)
            ordinal += 1
        elif operator in ('U', '*U', 'Q', 'LB'):
            node = stack.pop()
            assert node['kind'].upper() == operator
            node['state'] = [dict(values) for values in (printing, native)]
            if node['saved'] is not None:
                for current, saved in zip((printing, native), node['saved'], strict=True):
                    for key in SCOPED:
                        current.pop(key, None)
                        if key in saved:
                            current[key] = saved[key]
            if operator != 'LB':
                groups.append(node)
        elif operator in PAINT:
            paths.append(dict(state=[dict(values) for values in (printing, native)], compound=next((node for node in reversed(stack) if node['kind'] == '*u'), None)))
    assert not stack
    for path in paths:
        path['effective'] = [dict(values) for values in path['state']]
        if path['compound'] is not None:
            path['effective'] = [dict(shared, **{key: local[key] for key in FLAGS if key in local}) for local, shared in zip(path['state'], path['compound']['state'], strict=True)]
            for values, local in zip(path['effective'], path['state'], strict=True):
                for key in FLAGS - local.keys():
                    values.pop(key, None)
    return paths, groups, [printing, native]


def reads(paint):
    """Compare only attributes consumed by this paint, plus local path flags."""
    keys = FLAGS | {'XR'}
    if paint.upper() != 'N':
        keys |= {'Xy'}
    if paint.upper() in ('F', 'B'):
        keys |= {'fill', 'O'}
    if paint.upper() in ('S', 'B'):
        keys |= {'stroke', 'R'} | SCOPED
    return keys


def interpreter_state(document, prefix, native):
    """Measure contour attributes with the pinned Adobe prolog, without a renderer.

    Private scalars are exposed only for this probe. Opaque metadata and modern
    opacity operators are not executed; their exact data is checked separately.
    Unprojected private paths/groups keep a None slot so native source indices
    never address a different printing contour after a private shape.
    """
    probe = b'\n[ currentlinecap currentlinejoin currentlinewidth currentmiterlimit currentdash ] ==\n'
    output, count, stack, paths, groups = bytearray(prefix + b'\n'), 0, [], [], []
    for item in walk_body(document.trailer):
        operator, operands, private = command(item)
        if operator not in OPERATORS:
            continue
        projected = native or not private
        if operator in ('u', '*u', 'q'):
            stack.append(dict(kind=operator, projected=projected))
        elif operator == 'm':
            paths.append(dict(index=count if projected else None, compound=next((node for node in reversed(stack) if node['kind'] == '*u' and node['projected']), None)))
            if projected:
                output.extend(probe)
                count += 1
        elif operator in ('U', '*U', 'Q'):
            node = stack.pop()
            assert node['kind'].upper() == operator
            assert node['projected'] == projected
            node['index'] = count if projected else None
            if projected:
                output.extend(probe)
                count += 1
            groups.append(node)
        if projected:
            output.extend((' '.join(value.decode('ascii') if isinstance(value, bytes) else str(value) for value in operands) + ' ' + operator + '\n').encode('ascii'))
    assert not stack
    output.extend(probe)
    result = subprocess.run(['gs', '-q', '-dSAFER', '-dNODISPLAY', '-dBATCH', '-dNOPAUSE', '-'], input=output, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout.decode() + result.stderr.decode()
    values = result.stdout.decode().splitlines()
    assert len(values) == count + 1 and all(re.fullmatch(r'[\[\]\d.eE+\- ]+', value) for value in values)
    outlines = inventory(document)
    assert len(paths) == len(outlines)
    assert [path['index'] is None for path in paths] == [path['private'] and not native for path in outlines]
    return [None if path['index'] is None else values[(path['compound'] or path)['index']] for path in paths], [None if group['index'] is None else values[group['index']] for group in groups], values[-1]


def checked_paths(data, spans, paths, metadata):
    """Bind geometry/count spans and complete postfix dictionaries independently."""
    assert len(spans) == len(paths) == len(metadata)
    for span, path, node in zip(spans, paths, metadata, strict=True):
        bind(data, span, path)
        assert span['owner'][0] == span['geometry'][0][0]
        if span['dictionary'] is None:
            assert node['metadata'] is None and span['owner'][1] == span['paint'][1]
        else:
            start, end = span['dictionary']
            assert not parsed(data[span['paint'][1]:start])
            assert parsed(data[start:end]) == [node['metadata']] and end == span['owner'][1]


def copied_path(before, after, old, new, original, expected):
    """Reproduce the allowed count, closure, mask and paint patches exactly."""
    edits = []
    if original['geometry'] != expected['geometry']:
        assert expected['geometry'] == original['geometry'] + [('L', original['geometry'][0][1])]
        geometry = after[new['geometry'][0][0]:new['geometry'][-1][1] + 1]
        assert geometry.endswith(b'\n')
        edits.append((*old['geometry'][0], geometry))
        edits.extend((*span, b'') for span in old['geometry'][1:])
    if original['controls'] != expected['controls']:
        if not original['controls']:
            edits.append((old['paint'][0], old['paint'][0], (' '.join(expected['controls']) + ' ').encode()))
        elif not expected['controls']:
            edits.extend((*span, b' ') for span in old['controls'])
        else:
            edits.append((*old['controls'][0], expected['controls'][0].encode()))
    if original['paint'] != expected['paint']:
        edits.append((*old['paint'], expected['paint'].encode()))
    start, end = old['owner']
    fragment = patch(before[start:end], [(first - start, last - start, value) for first, last, value in edits])
    if old['count'] is not None:
        count = before[slice(*old['count'])]
        if original['count'] != expected['count']:
            first, last = old['countOperand']
            count = patch(count, [(first - old['count'][0], last - old['count'][0], str(expected['count']).encode())])
        fragment = count + b'\n' + fragment
    return fragment


def verify(inkai, output, row, request, prefix):
    """Verify independently prescribed ownership, state and exact unselected bytes."""
    selected, target, anchor, mask, inherit = request
    name, variant = row['source'], row['variant']
    before_file, after_file = output / f'{name}.original.ps', output / f'{name}.{variant}.ps'
    before, after = before_file.read_bytes(), after_file.read_bytes()
    original_doc, actual_doc = inkai.parse(str(before_file)), inkai.parse(str(after_file))
    original, actual = inventory(original_doc), inventory(actual_doc)
    source_states, source_groups, final = states(original_doc)
    result_states, result_groups, result_final = states(actual_doc)
    source_metadata = [node for node in objects(object_inventory(original_doc)) if node['kind'] == 'path']
    result_metadata = [node for node in objects(object_inventory(actual_doc)) if node['kind'] == 'path']
    for data, document, reported, paths, metadata in [(before, original_doc, row['before'], original, source_metadata), (after, actual_doc, row['after'], actual, result_metadata)]:
        checked_paths(data, reported, paths, metadata)
        _, groups, group_paths = group_inventory(document)
        checked_spans(data, row['beforeGroups' if data is before else 'afterGroups'], groups, group_paths)
    assert final == result_final
    assert [(node['kind'], node['flags'], node['state']) for node in source_groups] == [(node['kind'], node['flags'], node['state']) for node in result_groups]
    position = row['before'][anchor]['owner'][1] if anchor is not None else row['beforeGroups'][target]['closing'][0]
    order = [index for index, path in enumerate(row['before']) if path['owner'][0] < position and index not in selected] + selected + [index for index, path in enumerate(row['before']) if path['owner'][0] >= position and index not in selected]
    assert len(original) == len(actual) == len(order) == len(set(order))
    target_node = source_groups[target]
    compound = next((node for node in reversed(source_groups) if node['kind'] == '*u' and ('*u', node['ordinal']) in target_node['owners']), None)
    copied, edits = [], []
    for result_index, source_index in enumerate(order):
        old, new = row['before'][source_index], row['after'][result_index]
        expected = deepcopy(original[source_index])
        expected_states = source_states[source_index]['effective']
        if source_index in selected:
            expected['owners'] = target_node['owners']
            if compound is not None:
                expected_states = [dict(shared, **{key: local[key] for key in FLAGS if key in local}) for shared, local in zip(compound['state'], expected_states, strict=True)]
                if inherit:
                    last = row['beforeGroups'][target]['paths'][-1]
                    paint = original[last]['paint'].upper()
                    expected['paint'] = paint.lower() if original[source_index]['paint'].islower() else paint
            if mask is not None:
                expected['controls'] = [] if mask == 'none' else ['h' if mask == 'closed' else 'H', 'W']
            if expected['count'] is not None:
                closed = expected['paint'].islower() or expected['controls'] == ['h', 'W']
                if closed and expected['geometry'][-1][1][-2:] != expected['geometry'][0][1]:
                    expected['geometry'].append(('L', list(expected['geometry'][0][1])))
                expected['count'] = len(expected['geometry']) - int(closed)
            copied.append(copied_path(before, after, old, new, original[source_index], expected))
            edits.append((*old['owner'], ('exact', b' ')))
            if old['count'] is not None:
                edits.append((*old['count'], ('exact', b' ')))
        assert actual[result_index] == expected, (name, variant, source_index, 'geometry or ownership')
        assert source_metadata[source_index]['metadata'] == result_metadata[result_index]['metadata']
        for wanted, changed in zip(expected_states, result_states[result_index]['effective'], strict=True):
            assert {key: wanted.get(key) for key in reads(expected['paint'])} == {key: changed.get(key) for key in reads(expected['paint'])}, (name, variant, source_index, 'effective appearance')
    for old, new in zip(re.finditer(BOUNDS, before), re.finditer(BOUNDS, after), strict=True):
        values = list(map(float, old[1].split()))
        assert list(map(float, new[1].split())) == [min(values[0], 0), min(values[1], 0), max(values[2], 20), max(values[3], 20)]
        edits.append((old.start(), old.end(), ('exact', new[0])))
    edits.append((position, position, ('insert', b'')))
    inserted, = list(state_regions(before, after, edits))
    assert inserted[0] == ('insert', b'')
    match = re.fullmatch(b'(.*?)' + b'(.*?)'.join(re.escape(fragment) for fragment in copied) + b'(.*?)', inserted[1], re.DOTALL)
    assert match is not None, 'Unexpected copied source bytes'
    available = {command(item)[:2] for item in walk_body(original_doc.trailer) if command(item)[0] in ATTRIBUTES}
    for fragment in match.groups():
        assert all(command(item)[0] in ATTRIBUTES and command(item)[:2] in available for item in parsed(fragment)), 'Replay must use an existing source assignment'
    for native in [False, True]:
        old_paths, old_groups, old_final = interpreter_state(original_doc, prefix, native)
        new_paths, new_groups, new_final = interpreter_state(actual_doc, prefix, native)
        assert old_groups == new_groups and old_final == new_final, 'Adobe-prolog outgoing contour attributes changed'
        for result_index, source_index in enumerate(order):
            if actual[result_index]['paint'].upper() in ('S', 'B'):
                wanted = old_groups[source_groups.index(compound)] if source_index in selected and compound is not None else old_paths[source_index]
                assert new_paths[result_index] == wanted, (name, variant, source_index, native, 'Adobe-prolog shared stroke attributes')


def main():
    """Require all eleven transactions, pinned sources and the unchanged oracle."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/contour-movement'))
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
    assert len(rows) == len(expected) == 11 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    for row in rows:
        verify(inkai, args.output, row, expected[row['source'], row['variant']], prefix)
        print(row['source'], row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=[f'{row["source"]}/{row["variant"]}' for row in rows], producerTransactions=4, adobeProlog='inkscape_minimized_ai7.ai', ghostscript=subprocess.check_output(['gs', '--version'], text=True).strip(), stateProjections=22), indent=2) + '\n')


if __name__ == '__main__':
    main()
