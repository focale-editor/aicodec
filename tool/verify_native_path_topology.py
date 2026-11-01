#!/usr/bin/env python3
"""Independently check ordinary contour geometry, masks and exact retained source."""

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
from verify_native_path_lifecycle import PAINT, patch
from verify_native_structure import parsed

SYNTHETIC = {
    'synthetic-nested': '2c47e2aa44b093675d477266ef2fb64be0ade3d83b01aaf1a78e6845bd5c284f',
    'synthetic-open-mask': '860a4af7b4f49159cdfae784c7b4cfd5e1525db6ee4c90df77712357a7c27de2',
    'synthetic-cc-pairs': '3b7bb81d78afc9c6dbd3e651523322fea8c09eccedeac25c62aa9fccc7ab58ce',
}
REFUSED = ('simple_shapes_cc.ai', 'inkscape_minimized_ai_cc.ai', 'inkscape_minimized_ai_cc_current.ai')
GEOMETRY_INPUT = [('m', [5., 5.]), ('C', [8., 2., 16., 2., 18., 6.]), ('L', [15., 15.])]


def requests():
    """Prescribe selections and predecessor snapshots independently of the writer."""
    result = {}
    for name in SYNTHETIC:
        selected = 9 if name == 'synthetic-cc-pairs' else 0
        result[name, 'geometry'] = 'original', [selected], [], None
        if name != 'synthetic-open-mask':
            result[name, 'inner'] = 'original', [selected + 1], [], None
        if name != 'synthetic-cc-pairs':
            masks = [0, 1] if name == 'synthetic-nested' else [0]
            result[name, 'closed'] = 'original', [], masks, 'closed'
            result[name, 'open'] = 'closed', [], masks, 'open'
            result[name, 'clear'] = 'open', [], masks, 'none'
    result['synthetic-nested', 'combined'] = 'original', [0], [0, 1], 'closed'
    for name in REFUSED:
        result[name, 'rejected'] = 'original', [], [], None
    return result


def inventory(document):
    """Decode both native representations while retaining exact nested owners."""
    paths, geometry, controls, stack = [], [], [], []
    count, group = None, 0
    for item in walk_body(document.trailer):
        operator = getattr(item, 'command', None)
        if operator in ('u', '*u', 'q', 'Lb'):
            assert not geometry
            stack.append((operator, group))
            group += 1
        elif operator in ('U', '*U', 'Q', 'LB'):
            assert not geometry and stack
            assert stack.pop()[0].upper() == operator
        elif operator == 'As':
            assert count is None
            count = int(item.tokens[0])
        elif operator in GEOMETRY:
            geometry.append((operator, list(map(float, item.tokens))))
        elif operator in ('h', 'H', 'W'):
            assert geometry and not item.tokens
            controls.append(operator)
        elif operator in PAINT and geometry:
            assert controls in ([], ['h', 'W'], ['H', 'W'])
            paths.append(dict(geometry=geometry, controls=controls, paint=operator, owners=list(stack), count=count, private=item.is_pseudo_comment))
            geometry, controls, count = [], [], None
    assert not geometry and not controls and not stack and count is None
    return paths


def bind(data, spans, path):
    """Bind writer-reported ranges to independently parsed exact commands."""
    geometry = []
    for span in spans['geometry']:
        command, = parsed(data[slice(*span)])
        geometry.append((command.command, list(map(float, command.tokens))))
        assert command.is_pseudo_comment is False  # The fragment starts after its source prefix.
    assert geometry == path['geometry']
    controls = []
    for span in spans['controls']:
        control, = parsed(data[slice(*span)])
        assert not control.tokens
        controls.append(control.command)
    assert controls == path['controls']
    paint, = parsed(data[slice(*spans['paint'])])
    assert paint.command == path['paint'] and not paint.tokens
    if spans['count'] is None:
        assert spans['countOperand'] is None and path['count'] is None
    else:
        count, = parsed(data[slice(*spans['count'])])
        assert count.command == 'As' and len(count.tokens) == 1
        assert int(count.tokens[0]) == int(data[slice(*spans['countOperand'])]) == path['count']


def verify(inkai, output, row, request):
    """Allow only prescribed coordinates, count operands, mask tokens and bounds."""
    _, geometry_indices, mask_indices, mask = request
    source, target = output / row['original'], output / row['result']
    before, after = source.read_bytes(), target.read_bytes()
    original, actual = inventory(inkai.parse(str(source))), inventory(inkai.parse(str(target)))
    assert len(original) == len(actual) == len(row['before']) == len(row['after'])
    edits = []
    for index, path in enumerate(original):
        old, new = row['before'][index], row['after'][index]
        bind(before, old, path)
        bind(after, new, actual[index])
        expected = deepcopy(path)
        if index in geometry_indices:
            expected['geometry'] = deepcopy(GEOMETRY_INPUT)
        if index in mask_indices:
            assert any(kind == 'q' for kind, _ in path['owners'])
            expected['controls'] = [] if mask == 'none' else ['h' if mask == 'closed' else 'H', 'W']
        selected = index in geometry_indices or index in mask_indices
        if selected:
            assert not path['private']
            closed = path['paint'].islower() or expected['controls'] == ['h', 'W']
            geometry = expected['geometry']
            if path['count'] is not None:
                if closed and (len(geometry) == 1 or geometry[-1][1][-2:] != geometry[0][1]):
                    geometry.append(('L', list(geometry[0][1])))
                expected['count'] = len(geometry) - int(closed)
            if index in geometry_indices or len(geometry) != len(path['geometry']):
                first, last = new['geometry'][0][0], new['geometry'][-1][1]
                assert after[last:last + 1] == b'\n'
                edits.append((*old['geometry'][0], after[first:last + 1]))
                edits.extend((*span, b'') for span in old['geometry'][1:])
            if expected['count'] != path['count']:
                edits.append((*old['countOperand'], str(expected['count']).encode()))
            if expected['controls'] != path['controls']:
                if not path['controls']:
                    edits.append((old['paint'][0], old['paint'][0], (' '.join(expected['controls']) + ' ').encode()))
                elif not expected['controls']:
                    edits.extend((*span, b' ') for span in old['controls'])
                else:
                    edits.append((*old['controls'][0], expected['controls'][0].encode()))
        assert actual[index] == expected, (row['source'], row['variant'], index)
    pattern = rb'%%(?:HiResBoundingBox|BoundingBox|PageBoundingBox):[^\r\n]*'
    for old, new in zip(re.finditer(pattern, before), re.finditer(pattern, after), strict=True):
        bounds = list(map(float, old[0].split(b':', 1)[1].split()))
        required = [min(bounds[0], 0), min(bounds[1], 0), max(bounds[2], 20), max(bounds[3], 20)]
        assert list(map(float, new[0].split(b':', 1)[1].split())) == required
        edits.append((old.start(), old.end(), new[0]))
    assert patch(before, edits) == after, 'Unexpected native metadata, state, identity or unselected source change'


def main():
    """Require all twelve edits and three unchanged real-source refusals."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/path-topology'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    expected = requests()
    assert len(rows) == len(expected) == 15 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    for name, checksum in SYNTHETIC.items():
        assert hashlib.sha256((args.output / f'{name}.original.ps').read_bytes()).hexdigest() == checksum
    checked = []
    for row in rows:
        name, variant = row['source'], row['variant']
        request = expected[name, variant]
        assert row['original'] == f'{name}.{request[0]}.ps'
        assert row['rejected'] == (name in REFUSED)
        assert row['result'] == (row['original'] if row['rejected'] else f'{name}.{variant}.ps')
        if row['rejected']:
            entry, fixture = manifest[name], Path('test/corpus/files', name)
            assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
            assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
            programs = native_programs(fixture) if fixture.read_bytes().startswith(b'%PDF-') else [inkai.extract(str(fixture))]
            assert programs == [(args.output / row['result']).read_bytes()] and row['issue']
        else:
            verify(inkai, args.output, row, request)
        checked.append(f'{name}/{variant}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, syntheticEdits=12, producerRefusals=3), indent=2) + '\n')


if __name__ == '__main__':
    main()
