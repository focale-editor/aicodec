#!/usr/bin/env python3
"""Verify appearance masks, complete source deltas and scoped printing state."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
from types import SimpleNamespace

from corpus_support import REVISION
from verify_native_appearance_edits import replace_once, string
from verify_native_appearance_graphs import patch
from verify_native_appearance_groups import fragment
from verify_native_appearances import verify
from verify_native_clipping_lifecycle import prolog, trace
from verify_native_group_lifecycle import command, descendant_paths, inventory as group_inventory
from verify_native_path_topology import bind, inventory
from verify_native_structure import parsed

SOURCES = {
    'closed': '65a6cf1860d64310f7ab70acf72ed921246f20fe799ac6954fcf89b12f7001ce',
    'open': '9e223d60236066d98e865f2d8c1bb7de1f02489ca6935cc9d9ddf545f7b384f5',
    'compound': 'bfed0812b539904d03e488ddb6ba7d985c7b640a13ce7b84879c02be6743f4a3',
    'leaves': '544493786419e123c50f15b64d0f36f4e0b66b2013cafb5e0c48b0fcd83b1ef1',
    'nested': '6b64a43f54f0127f092e4a4f0ea18a6b5e2fd9228cc85621bcb386cec96bb653',
    'counted': '5799c21a4f65f1549b4aba2f99ce319d2717058b4ab7261c5a79971092558fdd',
    'child': 'edecce09d9d8fc3b9d01d164fc7162a21bb7f881c53cafb2a683675c7fdd419e',
}


def printing(counted):
    """Prescribe the host's complete group independently of its serialization."""
    count = b'3 As\n' if counted else b''
    return (b'u\nq\n' + count + b'0 0 m 10 0 L 10 10 L 0 0 L h W N\n0.7 0.6 0.5 Xa\n'
            + count + b'1 1 m 9 1 L 9 9 L 1 1 L f\n2 J 2 j 9 w 17 M [4 2] 1 d\nQ\n0 0 0 1 k\nU')


def expected(data, row, variant):
    """Allow only the prescribed style, reference, host group and bounds edits."""
    child = variant == 'child'
    shared = variant.endswith('shared')
    style = row['styles'][1 if child else 0]
    first, last = style['record']
    changed = replace_once(data[first:last], b'2 w' if child else b'0.2 0.3 0.4 Xa', b'8.0 w' if child else b'0.7 0.6 0.5 Xa')
    name = string(b'Clipped child' if child else b'Selected clip')
    edits = [(first, last, changed)] if shared else [(last, last, b'\n' + replace_once(changed, b'(' + bytes(style['name']) + b') /Name', name + b' /Name') + b'\n')]
    groups = list(re.finditer(rb'(?ms)^u\n\n0 0 0 1 k\n.*?\nU(?=\n\n0 J)', data))
    assert len(groups) == 2
    for index in ([0, 1] if shared else [0]):
        edits.append((*groups[index].span(), printing(variant.startswith('counted'))))
    if not shared:
        applications = list(re.finditer(rb'(?m)^%_0 \(Child\) XW$' if child else rb'(?m)^1 \(Shared\) XW$', data))
        assert len(applications) == 2
        edits.append((*applications[0].span(), (b'%_0 ' if child else b'1 ') + name + b' XW'))
    return replace_once(patch(data, edits), b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def ownership(document, data, row):
    """Bind every contour, local group, mask and effective graphics-state owner."""
    paths = inventory(document)
    roots, groups, group_paths = group_inventory(document)
    assert len(row['paths']) == len(paths) and len(row['groups']) == len(groups)
    for report, path in zip(row['paths'], paths, strict=True):
        bind(data, report, path)
    for report, group in zip(row['groups'], groups, strict=True):
        assert report['private'] == group['private']
        assert [command(item) for item in fragment(data, report['span'], report['private'])] == group['commands']
        assert report['paths'] == [next(index for index, candidate in enumerate(group_paths) if candidate is path) for path in descendant_paths(group)]
    preorder = []

    def visit(nodes):
        """Assign the independent reader's preorder owner indices to group objects."""
        for node in nodes:
            if node['kind'] != 'path':
                preorder.append(node)
                visit(node['children'])

    visit(roots)
    indices = {index: next(ordinal for ordinal, group in enumerate(groups) if group is value) for index, value in enumerate(preorder)}
    private = [index for index, path in enumerate(paths) if path['private']]
    assert [contour['path'] for contour in row['contours']] == private
    for contour in row['contours']:
        path = paths[contour['path']]
        assert contour['groups'] == [indices[index] for _, index in path['owners']]
        assert contour['count'] == row['paths'][contour['path']]['count']
        expected_mask = 'closed' if path['controls'] == ['h', 'W'] else 'open' if path['controls'] else 'none'
        assert contour['mask'] == expected_mask
        clip, compound = None, None
        for kind, index in path['owners']:
            if kind == '*u':
                compound = indices[index]
            elif kind == 'q' and compound is None:
                clip = indices[index]
        assert contour['clip'] == clip and contour['compound'] == compound
    # Group ordinals can shift when the host supplies additional printing groups.
    return [{**path, 'owners': [kind for kind, _ in path['owners']]} for path in paths if path['private']]


def contour_probe(data):
    """Project contour state without adapting CC color layouts to the AI7 prolog.

    Colors do not affect the five probed contour attributes. Their original
    operands remain covered by the complete byte oracle, not by this probe.
    """
    return SimpleNamespace(trailer=[item for item in parsed(data) if command(item)[0] not in ('g', 'G', 'k', 'K', 'Xa', 'XA')])


def main():
    """Require complete native data and two independent incoming contour states."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/appearance-clipping'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    prefix = prolog()
    rows = json.loads((args.output / 'report.json').read_text())
    variants = [f'{kind}-{mode}' for kind in SOURCES if kind != 'child' for mode in ('selected', 'shared')] + ['child']
    assert len(rows) == len(variants) * 2 and {row['source'] for row in rows} == {f'{variant}.{phase}' for variant in variants for phase in ('before', 'after')}
    reports = {row['source']: row for row in rows}
    state_checks = 0
    for variant in variants:
        child, shared = variant == 'child', variant.endswith('shared')
        before, after = [(args.output / f'{variant}.{phase}.ps').read_bytes() for phase in ('before', 'after')]
        assert hashlib.sha256(before).hexdigest() == SOURCES[variant.split('-')[0]]
        original, changed = [reports[f'{variant}.{phase}'] for phase in ('before', 'after')]
        verify(inkai, args.output, original, expected=(2, 16, 6) if child else (1, 8, 2))
        verify(inkai, args.output, changed, expected=(3, 24, 6) if child else ((1, 8, 2) if shared else (2, 16, 2)))
        assert after == expected(before, original, variant), variant
        documents = [inkai.parse(str(args.output / f'{variant}.{phase}.ps')) for phase in ('before', 'after')]
        assert ownership(documents[0], before, original) == ownership(documents[1], after, changed)
        for index in ([0, 1] if shared else [0]):
            for state in (b'0 J 0 j 1 w 10 M [] 0 d', b'1 J 1 j 4 w 8 M [3 1] 2 d'):
                observed = []
                for data, row in ((before, original), (after, changed)):
                    group = data[slice(*row['artwork'][index]['printing'])]
                    observed.append(trace(contour_probe(group), prefix + b'\n' + state, False)[-1])
                assert observed[0] == observed[1], (variant, index, state, observed)
                state_checks += 1
        print(variant, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=variants, printingStateChecks=state_checks), indent=2) + '\n')


if __name__ == '__main__':
    main()
