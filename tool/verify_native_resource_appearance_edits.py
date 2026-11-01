#!/usr/bin/env python3
"""Verify complete resource edits, transitive expansions and unselected bytes."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
from types import SimpleNamespace

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_appearance_edits import GROUP, string
from verify_native_appearance_graphs import patch
from verify_native_appearances import verify
from verify_native_artboard_text import normalized
from verify_native_group_lifecycle import command, inventory
from verify_native_structure import parsed

SYNTHETIC = {
    'pattern': 'f3d460f14d2901e388a76f361ec93d5ac1c462671dfee13d430e424f51a8848f',
    'chain': 'd887f9bd51b5941a6dad60f2a7030d10bc6453a04fe4109ada0b96674947cc5f',
}
PRODUCERS = ('simple_shapes.ai', 'simple_shapes_cc.ai', 'stroke_styles.ai', 'fill_stroke_test_cc.ai', 'opacity.ai')
COUNTS = {
    'pattern': (2, 8, 3),
    'chain': (3, 8, 4),
    'simple_shapes.ai': (17, 143, 26),
    'simple_shapes_cc.ai': (18, 149, 26),
    'stroke_styles.ai': (22, 173, 31),
    'fill_stroke_test_cc.ai': (18, 149, 27),
    'opacity.ai': (13, 119, 22),
}
NUMBER = rb'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'


def owners(data, report, document):
    """Bind complete sibling printing/private objects to actual source references."""
    for owner in report:
        start, end = owner['span']
        first, last = owner['printing']
        native_first, native_last = owner['authoring']
        assert start <= first < last < native_first < native_last < end
        pair = parsed(data[start:end])
        roots, _, _ = inventory(SimpleNamespace(trailer=pair))
        assert len(roots) == 2 and roots[0]['kind'] == 'u' and not roots[0]['private'] and roots[1]['kind'] == 'path' and roots[1]['private']
        assert roots[0]['commands'] == [command(item) for item in walk_body(parsed(data[first:last]))]
        native, = inventory(SimpleNamespace(trailer=parsed(b'%_' + data[native_first:native_last])))[0]
        assert native['geometry'] == roots[1]['geometry'] and native['paint'] == roots[1]['paint']
        boundary = [command(item) for item in walk_body(parsed(data[last:native_first])) if getattr(item, 'command', None) == 'XW']
        assert boundary == [('XW', (b'6', b''), False)]
        assert command(list(walk_body(pair))[-1])[0] == 'XW'
        if owner['resource'] is None:
            assert start > data.index(b'%%EndSetup') and owner['resourceSpan'] is None
        else:
            wrapper = b'%AI14_BeginSymbol' if bytes(owner['resourceName']) == b'Add Favorite' else b'%AI3_BeginPattern:'
            matching = [section for section in document.setup.all_subsections_of_type_recursive(wrapper) if section.children[0].tokens[0] == bytes(owner['resourceName'])]
            section, = matching
            wrapped, = parsed(data[slice(*owner['resourceSpan'])])
            assert normalized(wrapped) == normalized(section)
            assert owner['resourceSpan'][0] < start < end < owner['resourceSpan'][1] < data.index(b'%%EndSetup')


def expected(data, row):
    """Prescribe the entire transaction without trusting the writer's edited data."""
    style = row['before']['styles'][row['style']]
    assert style['uses'] == [row['ownersBefore'][0]['use']]
    start, end = style['record']
    first, last = row['paint']
    assert start < first < last < end
    paints = [paint for part in style['parts'] for paint in part['paints']]
    assert any(assignment['parameter'] == 'fillColor' and paint['instructions'][assignment['instruction']]['span'] == row['paint'] for paint in paints for assignment in paint['assignments'])
    original = data[first:last]
    decoded, = parsed(original)
    values = (0.7, 0.6, 0.5) if row['file'] in SYNTHETIC else (0., 1., 0., 0., 1., 0., 1.)
    assert decoded.command == 'Xa' and len(decoded.tokens) == len(values)
    matches = list(re.finditer(NUMBER, original))
    assert len(matches) == len(values)
    changed = patch(original, [(match.start(), match.end(), str(value).encode()) for match, value in zip(matches, values, strict=True)])
    style_changes = [(first - start, last - start, changed)]
    name = b'Selected tile' if row['file'] in SYNTHETIC else b'Edited resource'
    if not row['shared']:
        a, b = row['name']
        assert start < a < b < end
        style_changes.append((a - start, b - start, string(name)))
    replacement = patch(data[start:end], style_changes)
    edits = [(start, end, replacement)] if row['shared'] else [(end, end, b'\n' + replacement + b'\n')]
    if not row['shared']:
        use = row['before']['uses'][style['uses'][0]]
        edits.append((*use['span'], b'1 ' + string(name) + b' XW'))
    for owner in row['ownersBefore']:
        a, b = owner['printing']
        supplied = GROUP
        if row['file'] in PRODUCERS:
            group = data[a:b]
            color, = [item for item in parsed(group) if getattr(item, 'command', None) == 'Xa']
            assert list(map(float, color.tokens)) == list(map(float, decoded.tokens))
            old = b' '.join(color.tokens) + b' Xa'
            assert group.count(old) == 1 and group.endswith(b'U')
            supplied = group.replace(old, b'0 1 0 0 1 0 1 Xa')[:-1] + old + b'\nU'
        edits.append((a, b, supplied))
    result = patch(data, edits)
    if row['file'] in SYNTHETIC:
        assert result.count(b'%%BoundingBox: 0 0 100 100') == 1
        result = result.replace(b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')
    return result


def main():
    """Require four used-pattern and ten complete-producer resource transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/resource-appearance-edits'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 14 and {(row['file'], row['shared']) for row in rows} == {(name, shared) for name in (*SYNTHETIC, *PRODUCERS) for shared in (False, True)}
    pairs = 0
    for row in rows:
        name = row['file']
        before, after = [(args.output / (row[key]['source'] + '.ps')).read_bytes() for key in ('before', 'after')]
        if name in SYNTHETIC:
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC[name]
            assert [owner['use'] for owner in row['ownersBefore']] == list(range(4 if name == 'chain' else 3))
            assert [owner['resource'] for owner in row['ownersBefore']] == ([0, 1, None, None] if name == 'chain' else [0, None, None])
        else:
            entry, fixture = manifest[name], Path('test/corpus/files', name)
            raw = fixture.read_bytes()
            assert entry['license'] and entry['revision'] == REVISION and len(raw) == entry['size'] and hashlib.sha256(raw).hexdigest() == entry['sha256']
            assert ([raw] if raw.startswith(b'%!PS-Adobe-') else native_programs(fixture)) == [before]
            assert len(row['ownersBefore']) == 1 and bytes(row['ownersBefore'][0]['resourceName']) == b'Add Favorite'
        for key in ('before', 'after'):
            counts = COUNTS[name]
            if key == 'after' and not row['shared']:
                counts = (counts[0] + 1, counts[1] + (8 if name in SYNTHETIC else 10), counts[2])
            verify(inkai, args.output, row[key], expected=counts)
            document = inkai.parse(str(args.output / (row[key]['source'] + '.ps')))
            owners(before if key == 'before' else after, row['ownersBefore' if key == 'before' else 'ownersAfter'], document)
        assert after == expected(before, row), (name, row['shared'], 'complete byte delta')
        assert len(row['ownersBefore']) == len(row['ownersAfter'])
        for old, new in zip(row['ownersBefore'], row['ownersAfter'], strict=True):
            assert old['use'] == new['use'] and old['resource'] == new['resource']
            assert before[slice(*old['authoring'])] == after[slice(*new['authoring'])]
            pairs += 1
        print(name, 'shared' if row['shared'] else 'selected', 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=len(rows), synchronizedOwners=pairs), indent=2) + '\n')


if __name__ == '__main__':
    main()
