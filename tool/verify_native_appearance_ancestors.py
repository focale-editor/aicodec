#!/usr/bin/env python3
"""Check enclosing masks, complete appearance deltas and scoped contour state."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_native_appearance_clipping import contour_probe
from verify_native_appearance_edits import replace_once, string
from verify_native_appearance_graphs import patch
from verify_native_appearance_groups import fragment
from verify_native_appearances import verify
from verify_native_clipping_lifecycle import prolog, trace
from verify_native_group_lifecycle import command, descendant_paths, inventory as group_inventory
from verify_native_path_topology import bind, inventory

SOURCES = {
    'ordinary': '33a4197bc750303d92687a3e05055dc29a46eac94ac39271c261cd4c36329600',
    'live': '55d0d3da89d958ec61d1b8741f81c7db0565e4e234d78811b2b0d2305576ee0d',
    'private': '9521b41f57f37b14cfdead7f191e7ac18644012448bbf51f20abaf27d97b56f5',
    'nested': 'a971fa3631aac109a91e6fd33818145e00d66c0113eb6ea364a296431802f862',
    'compound': '08f1f3d8bcd1864bd9565c64b655adee310e7f8b263ce6efc092f3e189ae2ab7',
}
PRINTING = b'u\n0.7 0.6 0.5 Xa\n0 0 m 10 0 L 10 10 L f\n0 0 0 1 k\nU'


def expected(data, row, shared):
    """Prescribe the sole stroke field, explicit users, supplied groups and bounds."""
    first, last = row['styles'][0]['record']
    changed = replace_once(data[first:last], b'2 w', b'8.0 w')
    name = string(b'Selected ancestor')
    edits = [(first, last, changed)] if shared else [(last, last, b'\n' + replace_once(changed, b'(Shared) /Name', name + b' /Name') + b'\n')]
    for index in ([0, 1] if shared else [0]):
        edits.append((*row['artwork'][index]['printing'], PRINTING))
    if not shared:
        applications = list(re.finditer(rb'(?m)^1 \(Shared\) XW$', data))
        assert len(applications) == 2
        edits.append((*applications[0].span(), b'1 ' + name + b' XW'))
    return replace_once(patch(data, edits), b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def ownership(document, data, row):
    """Bind every reported path and group to the unchanged independent reader."""
    paths = inventory(document)
    roots, groups, group_paths = group_inventory(document)
    assert len(paths) == len(row['paths']) and len(groups) == len(row['groups'])
    for report, path in zip(row['paths'], paths, strict=True):
        bind(data, report, path)
    for report, group in zip(row['groups'], groups, strict=True):
        assert report['private'] == group['private']
        assert [command(item) for item in fragment(data, report['span'], report['private'])] == group['commands']
        assert report['paths'] == [next(index for index, candidate in enumerate(group_paths) if candidate is path) for path in descendant_paths(group)]
    assert len(roots) == 4 and [root['kind'] for root in roots] == ['q', 'path', 'q', 'path']
    # Group ordinals change when supplied expansions contain fewer local groups.
    retained = [{**path, 'owners': [kind for kind, _ in path['owners']]} for path in paths if path['private'] or path['controls']]
    parents = []
    for art in row['artwork']:
        candidates = [group for group in row['groups'] if not group['private'] and group['span'][0] < art['printing'][0] < art['authoring'][1] < group['span'][1]]
        assert candidates and all(data[slice(*group['span'])].startswith(b'q\n') for group in candidates)
        parents.append(min(candidates, key=lambda group: group['span'][0])['span'])
    return retained, parents


def main():
    """Require exact native data and independent printing/modeled-state probes."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/appearance-ancestors'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    prefix = prolog()
    rows = json.loads((args.output / 'report.json').read_text())
    variants = [f'{kind}-{mode}' for kind in SOURCES for mode in ('selected', 'shared')]
    assert len(rows) == 2 * len(variants) and {row['source'] for row in rows} == {f'{variant}.{phase}' for variant in variants for phase in ('before', 'after')}
    reports = {row['source']: row for row in rows}
    printing_checks, modeled_checks = 0, 0
    for variant in variants:
        shared = variant.endswith('shared')
        before, after = [(args.output / f'{variant}.{phase}.ps').read_bytes() for phase in ('before', 'after')]
        original, changed = [reports[f'{variant}.{phase}'] for phase in ('before', 'after')]
        assert hashlib.sha256(before).hexdigest() == SOURCES[variant.split('-')[0]]
        verify(inkai, args.output, original, expected=(1, 8, 2))
        verify(inkai, args.output, changed, expected=(1, 8, 2) if shared else (2, 16, 2))
        assert after == expected(before, original, shared), variant
        inventories = [ownership(inkai.parse(str(args.output / f'{variant}.{phase}.ps')), data, row) for phase, data, row in [('before', before, original), ('after', after, changed)]]
        assert inventories[0][0] == inventories[1][0]
        for index in ([0, 1] if shared else [0]):
            regions = [data[slice(*info[1][index])] for data, info in zip((before, after), inventories, strict=True)]
            for state in (b'0 J 0 j 1 w 10 M [] 0 d', b'1 J 1 j 4 w 8 M [3 1] 2 d'):
                initial = trace(contour_probe(b''), prefix + b'\n' + state, False)[-1]
                assert all(trace(contour_probe(region), prefix + b'\n' + state, False)[-1] == initial for region in regions)
                printing_checks += 1
                # Model alternative style writes explicitly; native KnownStyle
                # execution is not available in this older printing prolog.
                for old_width in (2, 3):
                    for phase, region in enumerate(regions):
                        modeled, count = re.subn(rb'(?m)^1 .* XW$', f'{old_width if phase == 0 else 8} w'.encode(), region)
                        assert count == 1
                        assert trace(contour_probe(modeled), prefix + b'\n' + state, True)[-1] == initial
                    modeled_checks += 1
        print(variant, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=variants, printingStateChecks=printing_checks, modeledStyleStateChecks=modeled_checks), indent=2) + '\n')


if __name__ == '__main__':
    main()
