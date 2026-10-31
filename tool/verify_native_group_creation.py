#!/usr/bin/env python3
"""Verify empty group creation, exact source preservation and independent ownership."""

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
from verify_native_direct_shapes import normalized
from verify_native_layers import verified_inventory
from verify_native_reference_resources import pinned_program
from verify_native_shape_lifecycle import body, inventory
from verify_native_shape_reordering import flags
from verify_native_structure import parsed
from verify_native_subtree_movement import topology, tree

SYNTHETIC = {
    'synthetic-empty': '9615df6f204d31138c573e004d2cab65c4431dedbdeebc761db83235d737ab04',
    'synthetic-flags': 'd5bfae0466b90c1892cb5cbb24997a89b5eb59a4aa858d8dae417e32dace25f4',
    'synthetic-groups': 'cdafd002a504a6b195dc3a5533719d45bd45cd7bd52d8e105ad487295ed8873b',
    'synthetic-mixed': '669f1e8413a92063f60302b9f572017172352a86c47c72444aba05d0cfe23eee',
}


def requests():
    """Pin parent kinds, identities and explicit inheritance independently of output."""
    result = {}
    for name in ('simple_shapes.ai', 'simple_shapes_cc.ai', 'layers_and_sublayers.ai'):
        result[name, 'root'] = 'root', None, True, False
        result[name, 'layer'] = 'layer', None, True, False
    result['layers_and_sublayers.ai', 'group'] = 'group', None, True, False
    result['synthetic-empty', 'root'] = 'root', None, False, False
    result['synthetic-groups', 'parent'] = 'group', 'Parent', False, False
    result['synthetic-groups', 'empty'] = 'group', 'Empty', False, False
    result['synthetic-mixed', 'parent'] = 'group', 'outer_0', True, False
    result['synthetic-flags', 'inherited'] = 'root', None, True, False
    result['synthetic-flags', 'rejected'] = 'root', None, False, True
    return result


def destination(before, items, nodes, row):
    """Bind the requested complete ordinary group, first layer or root boundary."""
    if row['target'] == 'root':
        assert row['layer'] is None and row['groupSpan'] is None
        boundary = re.search(rb'^%%(?:PageTrailer|Trailer)\r?$', before, re.MULTILINE)
        assert boundary is not None and row['position'] == boundary.start()
        return 0
    if row['target'] == 'layer':
        assert row['layer'] == 0 and row['groupSpan'] is None
        header = row['before']['layers']['layers'][0]
        assert row['position'] == header['closing'][0]
        return next(index for index, node in enumerate(nodes) if node['kind'] == 'Lb')
    assert row['layer'] is None
    span = row['groupSpan']
    fragment = list(body(parsed(before[slice(*span)])))
    matches = [index for index in range(len(items) - len(fragment) + 1) if normalized(items[index:index + len(fragment)]) == normalized(fragment)]
    assert len(matches) == 1
    first, last = matches[0], matches[0] + len(fragment) - 1
    assert fragment[0].command == 'u' and fragment[-1].command == 'U'
    assert before[row['position']:span[1]] == b'U'
    matches = [index for index, node in enumerate(nodes) if node['kind'] == 'u' and node['first'] == first and node['last'] == last]
    assert len(matches) == 1
    if row['anchor'] is not None:
        assert items[last + 1]['AI10_ArtUID'] == row['anchor']
    else:
        assert sum(node['kind'] == 'u' for node in nodes) == 1
    return matches[0]


def verify(inkai, source, target, row):
    """Require one empty owner insertion, exact old bytes and unchanged contour state."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    items, nodes = tree(original, list(range(len(row['before']['pairs']))))
    parent = destination(before, items, nodes, row)
    position, size = row['position'], len(after) - len(before)
    assert size > 0 and after[:position] + after[position + size:] == before
    inserted = parsed(after[position:position + size])
    assert len(inserted) == 3 and inserted[0].command == 'u' and inserted[1].command == 'U'
    assert not inserted[0].tokens and not inserted[1].tokens and not inserted[0].is_pseudo_comment and not inserted[1].is_pseudo_comment
    assert inserted[2] == {'_type': 'ArtDictionary', 'AI10_ArtUID': 'AiKit_group', 'AIArtName': 'AiKit (group)'}
    assert all(not isinstance(item, dict) or item.get('AI10_ArtUID') != 'AiKit_group' for item in items)
    expected = deepcopy(nodes)
    expected[parent]['children'].append(('node', len(expected)))
    expected.append(dict(kind='u', parent=parent, label=None, children=[]))
    changed_items, actual = tree(changed, list(range(len(row['after']['pairs']))))
    assert topology(actual) == topology(expected)
    added = [node for node in actual if node['kind'] == 'u' and node['last'] + 1 < len(changed_items) and isinstance(changed_items[node['last'] + 1], dict) and changed_items[node['last'] + 1].get('AI10_ArtUID') == 'AiKit_group']
    assert len(added) == 1 and not added[0]['children']
    assert len(row['before']['pairs']) == len(row['after']['pairs'])
    for old, new in zip(row['before']['pairs'], row['after']['pairs']):
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    for private in (False, True):
        assert flags(original, private=private, opacity=row['source'].startswith('synthetic'))[1] == flags(changed, private=private, opacity=row['source'].startswith('synthetic'))[1]


def main():
    """Verify all fixed requests against pinned programs and unmodified reader code."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/group-creation'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    expected, checked = requests(), []
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name, _ in expected if not name.startswith('synthetic')}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 13 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    for row in rows:
        name, variant = row['source'], row['variant']
        assert tuple(row[key] for key in ('target', 'anchor', 'inheritParentFlags', 'rejected')) == expected[name, variant]
        assert row['original'] == f'{name}.original.ps' and row['result'] == f'{name}.{variant}.ps'
        source, target = args.output / row['original'], args.output / row['result']
        if name.startswith('synthetic'):
            assert hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[name]
        else:
            assert source.read_bytes() == programs[name]
        if row['rejected']:
            assert 'explicit inheritParentFlags' in row['issue'] and source.read_bytes() == target.read_bytes() and row['before'] == row['after']
        else:
            assert row['issue'] is None
            verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, realCreations=7, syntheticCreations=5, refusals=1), indent=2) + '\n')


if __name__ == '__main__':
    main()
