#!/usr/bin/env python3
"""Verify clip topology, exact source edits and Adobe-prolog contour state."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_live_shapes import GEOMETRY, walk_body
from verify_native_compound_lifecycle import normalized_paths
from verify_native_group_lifecycle import checked_spans, command, inventory as group_inventory
from verify_native_path_topology import bind, inventory
from verify_native_structure import parsed


SOURCES = {
    'state': 'cfd8750f61c7a8e8283620da5f577e3981b15cff0d7904cd161ae0045fa340fd',
    'nested': '566279dc408fa2bb63a4ae75dd970871a8fdf6c8ee89e39bb5e5eea416db8b48',
    'compound': '1f64f6ce4f9aff238f35ef5e51a19e5d56eee36124afbd86e0bba4684ecf715d',
    'compound-state': 'def28a56b26a8483d98a36b13200701573057622b8ca797dde315d3f1d567057',
    'metadata': 'be26b5d264946ef53e4affa7f3cca8312befc8cf5d1d0f0e7872171040757d52',
    'cc-pairs': 'e5a59c009610e265af2b1b88af187fe783f0c1be386fe5925e3292f58860c913',
    'batch': '694acc814859decacf95a2b5999f3e1e8014e8b5187556e73e042026ee32b0bc',
}
STATE = {'J', 'j', 'w', 'M', 'd'}
OPERATORS = STATE | GEOMETRY | {'n', 'N', 'f', 'F', 's', 'S', 'b', 'B', 'u', 'U', '*u', '*U', 'q', 'Q', 'h', 'H', 'W', 'g', 'G', 'k', 'K', 'Xa', 'XA', 'O', 'R', 'XR', 'A', 'D', 'Ap'}


def prolog():
    """Use the unchanged Adobe prolog already pinned in the licensed corpus."""
    name = 'inkscape_minimized_ai7.ai'
    entry = next(item for item in json.loads(Path('test/corpus/manifest.json').read_text())['files'] if item['file'] == name)
    data = Path('test/corpus/files', name).read_bytes()
    assert entry['revision'] == REVISION and len(data) == entry['size']
    assert hashlib.sha256(data).hexdigest() == entry['sha256']
    assert entry['license'] and b'%%AI8_CreatorVersion: 27.3.1' in data
    return data[:data.index(b'%%EndSetup') + len(b'%%EndSetup')]


def trace(document, prefix, native):
    """Observe all five contour attributes through Ghostscript, without a renderer.

    The native projection exposes saved private scalar assignments to the same
    bounded declarative probe. This does not execute Adobe's native UI reader.
    Opaque records are never executed; CC pairs use exact-data checks separately.
    """
    probe = b'\n[ currentlinecap currentlinejoin currentlinewidth currentmiterlimit currentdash ] ==\n'
    output = bytearray(prefix + b'\n')
    count = 0
    for item in walk_body(document.trailer):
        operator, operands, private = command(item)
        if operator not in OPERATORS or private and not native:
            continue
        if operator == 'm':
            output.extend(probe)
            count += 1
        output.extend((' '.join(value.decode('ascii') if isinstance(value, bytes) else str(value) for value in operands) + ' ' + operator + '\n').encode('ascii'))
    output.extend(probe)
    result = subprocess.run(['gs', '-q', '-dSAFER', '-dNODISPLAY', '-dBATCH', '-dNOPAUSE', '-'], input=output, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout.decode() + result.stderr.decode()
    lines = result.stdout.decode().splitlines()
    assert len(lines) == count + 1
    # Exact interpreter output is stable for unchanged values, including dashes.
    assert all(re.fullmatch(r'[\[\]\d.eE+\- ]+', line) for line in lines)
    return lines


def expectations(name, variant, original):
    """Prescribe changed contours, owners and mask roles independently."""
    create = variant == 'create'
    selected = list(range(9, 11)) if name == 'cc-pairs' else list(range(2)) if name in ('state', 'compound', 'compound-state') else list(range(4)) if name == 'nested' else list(range(200)) if name == 'batch' else [0]
    masks = [] if name == 'compound-state' else [9] if name == 'cc-pairs' else [0] if name in ('state', 'nested', 'metadata') else selected
    expected = deepcopy(original)
    for index in selected:
        owners = expected[index]['owners']
        if name == 'compound-state':
            if create:
                owners.insert(1, '*u')
            else:
                assert owners.pop(1) == '*u'
        elif create:
            owners.insert(0, 'q')
        else:
            assert owners.pop(0) == 'q'
        if name == 'compound' and index == 0:
            assert owners[-1] == ('u' if create else 'q')
            owners[-1] = 'q' if create else 'u'
    for index in masks:
        path = expected[index]
        path['controls'] = (['H', 'W'] if name == 'cc-pairs' else ['h', 'W']) if create else []
        closed = path['paint'].islower() or path['controls'] == ['h', 'W']
        if closed and path['count'] is not None and path['geometry'][-1][1][-2:] != path['geometry'][0][1]:
            path['geometry'].append(('L', list(path['geometry'][0][1])))
        if path['count'] is not None:
            path['count'] = len(path['geometry']) - int(closed)
    return selected, masks, expected


def state_regions(before, after, edits):
    """Match exact patches literally so adjacent geometry cannot absorb captures."""
    position, pattern, labels = 0, b'', []
    for start, end, label in sorted(edits):
        assert position <= start <= end <= len(before)
        pattern += re.escape(before[position:start])
        if label[0] == 'exact':
            pattern += re.escape(label[1])
        else:
            pattern += b'(.*?)'
            labels.append(label)
        position = end
    match = re.fullmatch(pattern + re.escape(before[position:]), after, re.DOTALL)
    assert match is not None, 'Unexpected geometry, identity, metadata or unselected source change'
    return zip(labels, match.groups(), strict=True)


def verify(inkai, output, row, prefix):
    """Bind independent parses, restrict changed bytes and compare real state."""
    name, variant = row['source'], row['variant']
    source = output / f'{name}.{row["predecessor"]}.ps'
    target = output / f'{name}.{variant}.ps'
    before, after = source.read_bytes(), target.read_bytes()
    old_document, new_document = inkai.parse(str(source)), inkai.parse(str(target))
    old_paths, new_paths = inventory(old_document), inventory(new_document)
    assert len(old_paths) == len(new_paths) == len(row['before']) == len(row['after'])
    for data, reported, paths in [(before, row['before'], old_paths), (after, row['after'], new_paths)]:
        for spans, path in zip(reported, paths, strict=True):
            bind(data, spans, path)
    _, old_groups, old_group_paths = group_inventory(old_document)
    _, new_groups, new_group_paths = group_inventory(new_document)
    checked_spans(before, row['beforeGroups'], old_groups, old_group_paths)
    checked_spans(after, row['afterGroups'], new_groups, new_group_paths)
    selected, masks, expected = expectations(name, variant, normalized_paths(old_document))
    assert normalized_paths(new_document) == expected, (name, variant, 'unexpected path or mask ownership')
    edits = []
    for index in masks:
        old, new = row['before'][index], row['after'][index]
        path, wanted = old_paths[index], expected[index]
        if path['geometry'] != wanted['geometry']:
            assert name == 'state' and variant == 'create' and index == 0
            geometry = ''.join(' '.join(str(value) for value in coordinates) + f' {operator}\n' for operator, coordinates in wanted['geometry']).encode()
            edits.append((*old['geometry'][0], ('exact', geometry)))
            edits.extend((*span, ('exact', b'')) for span in old['geometry'][1:])
        if path['count'] != wanted['count']:
            edits.append((*old['countOperand'], ('exact', str(wanted['count']).encode())))
        if not path['controls']:
            edits.append((old['paint'][0], old['paint'][0], ('exact', (' '.join(wanted['controls']) + ' ').encode())))
        else:
            assert not wanted['controls']
            edits.extend((*span, ('exact', b' ')) for span in old['controls'])
    if name == 'compound':
        leaf = row['beforeGroups'][0]
        edits.extend([(*leaf['opening'], ('exact', b'q' if variant == 'create' else b'u')), (*leaf['closing'], ('exact', b'Q' if variant == 'create' else b'U'))])
    if variant == 'create':
        if name == 'state':
            start = row['before'][0]['count'][0]
            end = before.index(b'\n%_;', before.index(b'(Content)')) + len(b'\n%_;')
        elif name == 'cc-pairs':
            start, end = row['before'][9]['count'][0], row['before'][10]['paint'][1]
        else:
            owner = row['beforeGroups'][2 if name == 'compound-state' else -1]
            assert owner['owner'] == [owner['start'], owner['end']]
            start, end = owner['owner']
        edits.extend([(start, start, ('exact', b'\n*u\n' if name == 'compound-state' else b'\nq\n')), (end, end, ('close', b'*U' if name == 'compound-state' else b'Q'))])
    else:
        groups = row['beforeGroups'] if name == 'batch' else [row['beforeGroups'][3 if name == 'compound-state' else -1]]
        for group in groups:
            if name == 'metadata':
                assert group['owner'] == [before.index(b'1 Ae q'), before.index(b'9 () XW') + len(b'9 () XW')]
            else:
                assert group['owner'] == [group['start'], group['end']]
            edits.extend([(group['owner'][0], group['opening'][1], ('exact', b' ')), (group['closing'][0], group['owner'][1], ('release', b'*U' if name == 'compound-state' else b'Q'))])
    if name == 'compound-state':
        for group in row['beforeGroups'][:2]:
            assert group['owner'] == [group['start'], group['end']]
            edits.append((group['end'], group['end'], ('replay', b'')))
    available = {command(item)[:2] for item in walk_body(old_document.trailer) if getattr(item, 'command', None) in STATE}
    for (kind, wanted), fragment in state_regions(before, after, edits):
        if kind == 'close':
            assert fragment.startswith(b'\n' + wanted + b'\n')
            fragment = fragment[len(wanted) + 2:]
        elif kind == 'release':
            assert fragment.startswith(b' ')
            fragment = fragment[1:]
        else:
            assert kind == 'replay'
        for item in parsed(fragment):
            operator, operands, _ = command(item)
            assert operator in STATE and (operator, operands) in available, 'Replay must derive from an existing scalar assignment'
    if name != 'cc-pairs':
        for native in [False, True]:
            assert trace(old_document, prefix, native) == trace(new_document, prefix, native), (name, variant, native, 'outgoing contour state changed')


def main():
    """Require all eleven transactions, pinned sources and the real Adobe prolog."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/clipping-lifecycle'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    prefix = prolog()
    rows = json.loads((args.output / 'report.json').read_text())
    by_request = {(row['source'], row['variant']): row for row in rows}
    requests = {
        (name, variant): 'create' if variant == 'release' and name in ('state', 'compound', 'compound-state', 'cc-pairs') else 'original'
        for name in SOURCES
        for variant in (['create', 'release'] if name in ('state', 'compound', 'compound-state', 'cc-pairs') else ['release'])
    }
    assert len(rows) == len(requests) == 11 and by_request.keys() == requests.keys()
    for name, checksum in SOURCES.items():
        assert hashlib.sha256((args.output / f'{name}.original.ps').read_bytes()).hexdigest() == checksum
    checked = []
    for request, predecessor in requests.items():
        row = by_request[request]
        assert row['predecessor'] == predecessor
        verify(inkai, args.output, row, prefix)
        checked.append('/'.join(request))
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, adobeProlog='inkscape_minimized_ai7.ai', ghostscript=subprocess.check_output(['gs', '--version'], text=True).strip(), stateTransactions=9, stateProjections=18), indent=2) + '\n')


if __name__ == '__main__':
    main()
