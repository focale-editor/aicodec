#!/usr/bin/env python3
"""Bind resource appearance pairs against complete independent CC parses."""

import argparse
from collections import Counter
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_artwork_resources import PRODUCERS, WRAPPERS, metadata, resource
from verify_native_group_lifecycle import command, inventory
from verify_native_structure import native_values, parsed

SYNTHETIC = {
    'paths': 'b5bb11bf11ec34d6ee1fe9f3b108d73defedd5ca076f3be4b98674c427ac3e50',
    'groups': 'ebce35a1fd6e0c3f3091b94984720b15041c0950bd660af0b48543a0f181d961',
    'clips': 'c0d2caa6db4d28e9a7956d7351d526bbb969f7076da20d54206a72bf0f0a5c5a',
    'live': 'cb7aed64fc20b1e690853643dcfa51ecab6aeec24206c76237c9b347b9183e41',
    'patterns': 'e0c09a118324bf8dd526b6e193f7585b92ae925dc165a2fb80d2800d7548102c',
    'brushes': '58a727867fd4a3d26b60b8ee1b6e6a7cb7fb44b5deef205a315a810a967dc3ec',
}


def appearance(data, owner, pair):
    """Check two sibling objects, their separator and every direct named child."""
    start, end = pair['span']
    first, last = pair['printing']
    native_first, native_last = pair['authoring']
    use = owner['uses'][pair['use']]
    assert owner['body'][0] <= start <= first < last < native_first < native_last <= use['span'][0] < end <= owner['body'][1]
    assert end == use['span'][1] and use['kind'] == 'knownStyle' and use['resolution'] == 'resolved'
    assert pair['printing'] in [item['span'] for item in owner['groups'] if not item['private']]
    fragment = parsed(data[start:end])
    roots, _, _ = inventory(SimpleNamespace(trailer=fragment))
    assert len(roots) == 2 and roots[0]['kind'] == 'u' and not roots[0]['private'] and roots[1]['private']
    assert [command(item) for item in walk_body(parsed(data[first:last]))] == roots[0]['commands']
    authoring = parsed(b'%_' + data[native_first:native_last])
    native_roots, _, _ = inventory(SimpleNamespace(trailer=authoring))
    assert len(native_roots) == 1
    if pair['kind'] == 'group':
        assert pair['authoring'] in [item['span'] for item in owner['groups'] if item['private']]
        assert native_roots[0]['commands'] == roots[1]['commands']
    else:
        assert pair['kind'] in ('path', 'liveShape') and roots[1]['kind'] == 'path'
        for key in ('geometry', 'paint', 'private'):
            assert native_roots[0][key] == roots[1][key]
        assert pair['authoring'] in [[item['geometry'][0][0], item['paint'][1]] for item in owner['paths']]
    commands = list(walk_body(fragment))
    assert command(commands[-1]) == ('XW', (b'1', bytes(use['name'])), False)
    separators = [item for item in walk_body(parsed(data[last:native_first])) if getattr(item, 'command', None) == 'XW']
    assert len(separators) == 1 and command(separators[0]) == ('XW', (b'6', b''), False)
    metadata(data, pair['metadata'], fragment, start, end)
    children = [item for item in walk_body(authoring) if getattr(item, 'command', None) == 'XW']
    assert len(children) == len(pair['nestedUses']) == len(pair['nestedOwners'])
    for child, index, span in zip(children, pair['nestedUses'], pair['nestedOwners'], strict=True):
        nested = owner['uses'][index]
        assert command(child) in [('XW', (str(mode).encode(), bytes(nested['name'])), True) for mode in (0, 1)]
        assert native_first <= span[0] < span[1] <= nested['span'][0] < nested['span'][1] <= native_last
        after = [item for item in walk_body(parsed(data[span[1]:nested['span'][1]])) if hasattr(item, 'command')]
        assert [command(item) for item in after] == [command(child)]
        assert span in [item['span'] for item in owner['groups']] + [[item['geometry'][0][0], item['paint'][1]] for item in owner['paths']]


def main():
    """Require original producers and exact source ownership for all reported pairs."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/resource-appearances'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for name in ('manifest.json', 'direct_shape_manifest.json') for entry in json.loads(Path('test/corpus', name).read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(SYNTHETIC) + len(PRODUCERS) and {row['source'] for row in rows} == {*SYNTHETIC, *PRODUCERS}
    totals = Counter()
    for row in rows:
        name = row['source']
        path = args.output / f'{name}.ps'
        data = path.read_bytes()
        if name in SYNTHETIC:
            assert hashlib.sha256(data).hexdigest() == SYNTHETIC[name]
        else:
            entry, fixture = manifest[name], Path('test/corpus/files', name)
            raw = fixture.read_bytes()
            assert entry['license'] and entry['revision'] == REVISION and len(raw) == entry['size']
            assert hashlib.sha256(raw).hexdigest() == entry['sha256']
            assert ([raw] if raw.startswith(b'%!PS-Adobe-') else native_programs(fixture)) == [data]
        document = inkai.parse(str(path))
        declarations = {
            'knownStyle': [value.Name.encode('latin1') for value in native_values(document.setup) if type(value).__name__ == 'KnownStyle'],
            'gradient': [section.arguments[0] for section in document.setup.all_subsections_of_type_recursive(b'%AI5_BeginGradient:')],
        }
        count = 0
        for kind, wrapper in WRAPPERS.items():
            sections = list(document.setup.all_subsections_of_type_recursive(wrapper))
            reports = [item for item in row['resources'] if item['kind'] == kind]
            assert len(sections) == len(reports)
            for report, section in zip(reports, sections, strict=True):
                resource(data, report, section, declarations)
                assert sorted(report['rejectedUses'] + [pair['use'] for pair in report['appearances']]) == [index for index, use in enumerate(report['uses']) if use['kind'] == 'knownStyle']
                if name in PRODUCERS:
                    assert len(report['appearances']) == (2 if bytes(report['name']) == b'Add Favorite' else 0)
                for pair in report['appearances']:
                    appearance(data, report, pair)
                    count += 1
                    totals['pairs'] += 1
                    totals['nestedUses'] += len(pair['nestedUses'])
                    totals['metadata'] += len(pair['metadata'])
        assert len(row['resources']) == (1 if name in SYNTHETIC else 21) and count == 2
        print(name, count, 'resource pairs passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, sources=[row['source'] for row in rows], **totals), indent=2) + '\n')


if __name__ == '__main__':
    main()
