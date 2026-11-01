#!/usr/bin/env python3
"""Verify complete appearance child lifecycle against an independent source tree."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_appearance_edits import GROUP, replace_once, string
from verify_native_appearances import verify

PARTS = {'create': 9, 'remove': 4, 'copy': 9, 'move': 8, 'shared': 9, 'private': 9, 'typed': 15, 'typed-strokes': 15}
SOURCE = 'ca35d60c8e6bdf5e8453516c8c6d3e6f0127b1c119d60b254cda7f27986635cf'
NEW_FILL = b'/BasicFilter : (Fill Style Filter) 0 0 /Filter , 1 /Visible , /Dictionary : /NotRecorded , 0 /Bool (UseEvenOdd) , /FillStyle : 0 O 1.0 0.0 0.0 0.0 0.0 1.0 1.0 Xa 0 1.0 0 0 0 Xy 0 XR 0 1 Xd /Def ; (FillStyle) , ; /Dict , ;'


def typed_parts(advanced=False):
    """Specify authored native descriptors independently of the Dart model/writer."""
    strokes = []
    for color, alignment in ((b'0.25 G', None), (b'0.2 0.4 0.6 XA', b'inside'), (b'0.1 0.2 0.3 0.4 K', b'outside')):
        header = b'(Adobe Stroke Offset) 1 0' if alignment else b'(Stroke Style Filter) 0 0'
        plugin = b'(StrokeOffset.aip) /PluginFileName , ' if alignment else b''
        parameters = string(alignment) + b' /String (DisplayString) , ' + (b'1' if alignment == b'inside' else b'0') + b' /Bool (StrokeOffsetInside) , ' if alignment else b''
        if advanced:
            parameters += b'/Dictionary : /NotRecorded , 1 /Int (BSAdvStrokeDictionaryVersion) , ' + (b'0' if alignment == b'outside' else b'1') + b' /Bool (BSDashAdj) , ; (kAIBeautifulStrokesParamsDictKey) , '
        strokes.append(b'/BasicFilter : ' + header + b' /Filter , 1 /Visible , ' + plugin + b'2 /FillOrStroke , /Dictionary : /NotRecorded , ' + parameters + b'/StrokeStyle : 1 R ' + color + b' 0 0.5 0 0 0 Xy 1 XR 1 J 2 j 3.5 w 8.0 M [2.5 1.5] -1.5 d 1 0 Xd /Def ; (StrokeStyle) , ; /Dict , ;')
    stack = b'/CompoundFilter : (Stack Style Filter) 0 0 /Filter , 1 /Visible , ' + b''.join(part + b' /Part ,\n' for part in (NEW_FILL, *strokes)) + b';'
    conduit = b'/BasicFilter : (Conduit Filter) 0 0 /Filter , 1 /Visible , ;'
    return b'/CompoundFilter : (Chain Style Filter) 0 0 /Filter , 1 /Visible , ' + stack + b' /Part ,\n' + conduit + b' /Part ,\n;'


def patch(data, edits):
    """Apply prescribed nonoverlapping changes against original source offsets."""
    for start, end, value in sorted(edits, reverse=True):
        data = data[:start] + value + data[end:]
    return data


def graph_style(data, style, variant):
    """Specify retained ownership, original copies and one newly authored paint."""
    parts = style['parts']
    assert parts[0]['children'] == [1, 6, 7] and parts[1]['children'] == [2, 3, 4, 5]
    children = {0: [2, 6, 7] if variant == 'remove' else [1, 7] if variant == 'move' else [1, 6, 7, 'copy' if variant == 'copy' else 'new']}
    if variant == 'move':
        children[1] = [6, 2, 3, 4, 5]
    prefix = b'%_' if variant == 'private' else b''

    def subtree(index):
        part = parts[index]
        start, end = part['record']
        edits = []
        if index in children:
            values = []
            for child in children[index]:
                values.append((typed_parts(advanced=variant == 'typed-strokes') if variant.startswith('typed') else NEW_FILL) if child == 'new' else data[slice(*parts[2]['record'])] if child == 'copy' else subtree(child))
            insertion = parts[part['children'][0]]['record'][0]
            edits.append((insertion - start, insertion - start, b''.join(value + b' /Part ,\n' + prefix for value in values)))
            for child in part['children']:
                first, last = parts[child]['record']
                edits.append((first - start, last - start, b''))
                field = re.match(rb'(?:\s|%_)*(/Part)(?:\s|%_)*(,?)', data[last:end])
                assert field
                for group in (1, 2):
                    first, final = field.span(group)
                    if final > first:
                        edits.append((last + first - start, last + final - start, b''))
        else:
            order = list(reversed(part['children'])) if variant == 'shared' and index == 1 else part['children']
            edits.extend((parts[slot]['record'][0] - start, parts[slot]['record'][1] - start, subtree(child)) for slot, child in zip(part['children'], order, strict=True))
        result = patch(data[start:end], edits)
        if variant == 'copy' and index == 2:
            result = replace_once(result, b'0.2 0.3 0.4 Xa', b'0.7 0.6 0.5 Xa')
        if variant == 'shared' and index == 2:
            result = replace_once(result, b'0 /Visible', b'1 /Visible')
        return result

    first, last = style['record']
    start, end = parts[0]['record']
    return data[first:start] + subtree(0) + data[end:last]


def expected(data, row, variant):
    """Require preservation outside explicit graph, style use, group and bounds edits."""
    style = row['styles'][0]
    changed = graph_style(data, style, variant)
    start, end = style['record']
    if variant == 'shared':
        edits = [(start, end, changed)]
    else:
        changed = replace_once(changed, b'(Shared) /Name', string(b'Graph') + b' /Name')
        edits = [(end, end, b'\n' + (b'%_' if variant == 'private' else b'') + changed + b'\n')]
    groups = list(re.finditer(rb'(?m)^u\n\n0 0 0 1 k\n.*?\nU(?=\n%_/ArtDictionary)', data, re.DOTALL))
    uses = list(re.finditer(rb'(?m)^1 \(Shared\) XW$', data))
    assert len(groups) == len(uses) == 2
    for index in ([0, 1] if variant == 'shared' else [1]):
        edits.append((groups[index].start(), groups[index].end(), GROUP))
        if variant != 'shared':
            edits.append((uses[index].start(), uses[index].end(), b'1 ' + string(b'Graph') + b' XW'))
    return replace_once(patch(data, edits), b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def main():
    """Check all complete before/after trees and exact intended source deltas."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/appearance-graphs'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    inventory = {row['source']: row for row in rows}
    assert len(rows) == 2 * len(PARTS) and set(inventory) == {f'{variant}.{phase}' for variant in PARTS for phase in ('before', 'after')}
    ordinary = (args.output / 'create.before.ps').read_bytes()
    assert hashlib.sha256(ordinary).hexdigest() == SOURCE
    for variant, count in PARTS.items():
        before = (args.output / f'{variant}.before.ps').read_bytes()
        after = (args.output / f'{variant}.after.ps').read_bytes()
        row = inventory[f'{variant}.before']
        verify(inkai, args.output, row, expected=(1, 8, 2))
        if variant == 'private':
            first, last = inventory['create.before']['styles'][0]['record']
            assert before == ordinary[:first] + b'%_' + ordinary[first:last].replace(b'\n', b'\n%_') + ordinary[last:]
        else:
            assert before == ordinary
        verify(inkai, args.output, inventory[f'{variant}.after'], expected=(1, count, 2) if variant == 'shared' else (2, count + 8, 2))
        assert after == expected(before, row, variant), variant
        print(variant, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=list(PARTS)), indent=2) + '\n')


if __name__ == '__main__':
    main()
