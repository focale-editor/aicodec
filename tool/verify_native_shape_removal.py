#!/usr/bin/env python3
"""Verify complete pair deletion, source-derived state and unchanged native owners."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from lxml import etree

from corpus_support import REVISION, native_programs, printable_svg
from verify_native_capabilities import body_operators
from verify_native_shape_lifecycle import artwork, assignment, body, bundles, inventory, signature, source_flags
from verify_native_structure import parsed

SYNTHETIC = {
    'synthetic-alias': '1ec6b3aa13277b70e1194973a896d29215412d7ebb32d56a2485f797d9b0b83c',
    'synthetic-following': '418222b4b50904a1e68dc76db094a777a4bd19f1c844353014e6778801551088',
    'synthetic-identified': '49cf56659fd5aaa38292907d5c810c3f331cf6b783e44d9fe0aad41febd7034f',
    'synthetic-reference': '92befbddb50d79682e5a596770370b85a9dd2b605ad3b54417f6da9110adc11d',
    'synthetic-state': '399005c1c8f84ed6e4fcb45970738b9025d45f3a3b59f91ccd7f399e138b5698',
    'synthetic-width': '9e14f459371477f1b874812936e663803db749e363325827565d69437677b101',
    'synthetic': '6f368c1aa74ad5a4efe5526cea465cb57418dc3ddc7302eb78f5894399fdbc05',
}
SCALARS = {'A', 'Xw', 'Ap', 'D', 'XR', 'O', 'R', 'Xy', 'J', 'j', 'w', 'M', 'd'}
COLORS = {'g', 'G', 'k', 'K', 'Xa', 'XA'}


def requests():
    """Pin exact source selections and expected refusals before reading reports."""
    result = {}
    for name, count in [('simple_shapes.ai', 5), ('simple_shapes_cc.ai', 5), ('gradient_linear.ai', 15), ('gradient_radial.ai', 9)]:
        for variant, selected in [('first', [0]), ('last', [count - 1]), ('alternating', list(range(0, count, 2))), ('all', list(range(count)))]:
            result[name, variant] = selected, False
    result['opacity.ai', 'first'] = [0], False
    for variant, selected in [('first', [0]), ('last', [1]), ('all', [0, 1])]:
        result['synthetic', variant] = selected, False
    for variant, selected in [('first', [0]), ('all', [0, 1])]:
        result['synthetic-identified', variant] = selected, False
    for name in ('synthetic-state', 'synthetic-width'):
        result[name, 'first'] = [0], False
    result['synthetic-following', 'last'] = [1], True
    for name in ('synthetic-reference', 'synthetic-alias'):
        result[name, 'first'] = [0], True
    return result


def hierarchy(value):
    """Visit independently parsed styles without requiring a setup-section wrapper."""
    from inkai.parser.consts import Section
    from inkai.parser.hierarchy_objects import HierarchyObject

    if isinstance(value, HierarchyObject):
        yield value
        yield from hierarchy(vars(value))
    elif isinstance(value, Section):
        yield from hierarchy(value.children)
    elif isinstance(value, dict):
        for item in value.values():
            yield from hierarchy(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from hierarchy(item)


def scalar_value(command):
    """Compare numeric literals and dash operands without decimal spelling changes."""
    if command.command == 'd':
        return assignment(command)
    return command.command, tuple(float(token) for token in command.tokens)


def restored_style(document, name):
    """Require unconditional, unanimous scalar assignments in the named paint graph."""
    styles = [record for record in hierarchy(document.setup) if type(record).__name__ == 'KnownStyle' and record.Name == name]
    assert len(styles) == 1
    records = list(hierarchy(styles[0]))
    assert all(getattr(record, 'Visible', None) in (None, 1) for record in records)
    assignments = {}
    for record in records:
        if type(record).__name__ in ('FillStyle', 'StrokeStyle', 'BlendStyle'):
            for command in body_operators(record):
                if command.command in SCALARS:
                    assignments.setdefault(command.command, []).append(command)
    return {key: scalar_value(values[0]) for key, values in assignments.items() if all(scalar_value(value) == scalar_value(values[0]) for value in values)}


def exact_deletions(before, after, document, row):
    """Require exact unselected bytes and only source-backed scalar replay in each gap."""
    original = bundles(document)
    expected, pieces, position = [], [], 0
    for index in row['selected']:
        span, bundle = row['before'][index], original[index]
        commands = [item for item in bundle['items'] if getattr(item, 'command', None) in SCALARS | COLORS]
        restored = restored_style(document, bundle['style'])
        pieces.append(re.escape(before[position:span['start']]))
        count = len(commands) + len(restored)
        # Every replacement has one leading newline and exactly this many
        # single-line scalar instructions. All intervening source is literal.
        pieces.append(rb'(\n(?:[^\r\n]+\n){' + str(count).encode() + rb'})')
        expected.append((commands, restored))
        position = span['end']
    pieces.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(pieces), after)
    assert match is not None, (row['result'], 'Changed bytes outside complete pair deletions')
    for replacement, (commands, restored) in zip(match.groups(), expected):
        actual = parsed(replacement)
        assert len(actual) == len(commands) + len(restored)
        assert [(item.is_pseudo_comment, scalar_value(item)) for item in actual[:len(commands)]] == [(item.is_pseudo_comment, scalar_value(item)) for item in commands]
        tail = actual[len(commands):]
        assert all(item.is_pseudo_comment and item.command in SCALARS for item in tail)
        assert len({item.command for item in tail}) == len(tail)
        assert {item.command: scalar_value(item) for item in tail} == restored


def retained_flags(original, changed, selected):
    """Check all retained native/printing owner flags, including ordinary neighbors."""
    removed = {id(item) for index, bundle in enumerate(bundles(original)) if index in selected for item in bundle['items']}
    for private in (False, True):
        moves = [item for item in body(original.trailer) if getattr(item, 'command', None) == 'm' and (private or not item.is_pseudo_comment)]
        flags = source_flags(original, private=private)
        assert len(moves) == len(flags)
        assert [value for item, value in zip(moves, flags) if id(item) not in removed] == source_flags(changed, private=private)


def views(inkai, source, target, row):
    """Compare real native/printing SVG and synthetic printing SVG after deletion."""
    # The pinned SVG dispatcher ignores the synthetic version-branch lists.
    for mode in (('printing',) if row['source'] in SYNTHETIC else ('native', 'printing')):
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        old = [signature(item, before) for item in artwork(before)]
        new = [signature(item, after) for item in artwork(after)]
        offset = int(row['source'] == 'opacity.ai')
        extra = offset or int(row['source'].startswith('simple_shapes'))
        assert len(old) == len(row['before']) + extra
        assert [value for index, value in enumerate(old) if index - offset not in row['selected']] == new, (row['result'], mode, 'Retained geometry/style/resources changed')


def verify(inkai, source, target, row):
    """Bind whole pairs, metadata alternatives, shared styles and original bytes."""
    original = inventory(inkai, source, row['before'])
    changed = inventory(inkai, target, row['after'])
    before, after = source.read_bytes(), target.read_bytes()
    retained = [span for index, span in enumerate(row['before']) if index not in row['selected']]
    assert len(retained) == len(row['after'])
    for old, new in zip(retained, row['after']):
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    exact_deletions(before, after, original, row)
    retained_flags(original, changed, row['selected'])
    views(inkai, source, target, row)


def main():
    """Require pinned original programs, fixed requests and unchanged independent tools."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/shape-removal'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    expected = requests()
    assert len(rows) == len(expected) == 27 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    checked = []
    for row in rows:
        assert (row['selected'], row['rejected']) == expected[row['source'], row['variant']]
        assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['variant'] + '.ps'
        source, target = args.output / row['original'], args.output / row['result']
        before = source.read_bytes()
        if row['source'] in SYNTHETIC:
            assert hashlib.sha256(before).hexdigest() == SYNTHETIC[row['source']]
        else:
            entry = manifest[row['source']]
            path = Path('test/corpus/files', row['source'])
            assert path.stat().st_size == entry['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
            assert before in (native_programs(path) if path.read_bytes().startswith(b'%PDF-') else [path.read_bytes()])
        if row['rejected']:
            assert before == target.read_bytes() and row['before'] == row['after']
            issue = {'synthetic-following': 'unresolved native style state: fill', 'synthetic-reference': 'opaque reference owners', 'synthetic-alias': 'unambiguous native identity'}[row['source']]
            assert issue in row['issue']
        else:
            assert row['issue'] is None
            verify(inkai, source, target, row)
        checked.append(row['result'])
        print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, nativeAndPrintingRemovals=17, printingAndMetadataRemovals=7, refusals=3), indent=2) + '\n')


if __name__ == '__main__':
    main()
