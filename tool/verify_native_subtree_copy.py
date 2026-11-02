#!/usr/bin/env python3
"""Verify mixed-parent copies, fresh identities and state with pinned native readers."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from lxml import etree

from corpus_support import REVISION, printable_svg
from verify_live_shapes import GEOMETRY
from verify_native_direct_shapes import normalized
from verify_native_layers import verified_inventory
from verify_native_path_lifecycle import patch
from verify_native_reference_resources import BASE, FILES, pinned_program
from verify_native_shape_lifecycle import artwork, body, inventory, signature, source_flags
from verify_native_shape_removal import COLORS, SCALARS, hierarchy, restored_style, scalar_value
from verify_native_structure import parsed
from verify_native_subtree_removal import children, provenance, selected_ranges

SYNTHETIC = {
    'synthetic': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-inner': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-all': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-nested': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-child': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-following': '3447ebbb42c50978fd7708d2f2799a9ed1a430964b0bf9dbacfcb1a25d8b7fd0',
    'synthetic-state': '17e29f6162834c508ddfb4d026d9b05e098120afaa0233666a15f302de0c2a18',
    'synthetic-unknown-state': 'c305a9111dccadca7afa751b7b9052782fd99751ed9e6d61ddf3edff853ebcaa',
    'synthetic-alias': '1033ccaa89eacbc94faf39c760d9404f40aea1f031cc10eaefb383a133b4c825',
    'synthetic-unknown': '48ed366a5e861c9283a301f854a37c9dbc0a2d0e9e83580258100e9c3820f1ae',
    'synthetic-style': '92388a344f164fe023d1e6460b41b28661c4b689ef41be8af121eebc4bf5b00d',
    'synthetic-hidden-style': 'f22241043d9ea0faa1de54dc4ad9d81785fc4eac3905091684a75af6315f0d90',
}


def requests():
    """Pin source selections, inherited-state refusals and identity-alias failures."""
    result = {(f'group-{name}', 'group'): ([0], name == 'opacity.ai') for name in (*FILES, 'opacity.ai')}
    result.update({(f'layer-{name}', 'layer'): ([1], False) for name in FILES})
    result.update({
        ('synthetic', 'group'): ([0], False), ('synthetic-inner', 'group'): ([1], False),
        ('synthetic-all', 'group'): ([2, 0], False), ('synthetic', 'layer'): ([0], False),
        ('synthetic-nested', 'layer'): ([1], False), ('synthetic-child', 'layer'): ([2], False),
        ('synthetic-all', 'layer'): ([1, 0], False), ('synthetic-following', 'group'): ([0], False),
        ('synthetic-state', 'group'): ([0], False), ('synthetic-unknown-state', 'group'): ([0], True),
        ('synthetic-alias', 'group'): ([0], True), ('synthetic-unknown', 'group'): ([0], True),
        ('synthetic-style', 'group'): ([0], False), ('synthetic-hidden-style', 'group'): ([0], True),
    })
    return result


def replacements(data, row):
    """Bind every new name to the original literal token and require fresh XML IDs."""
    expected = set()
    for start, end in row['spans']:
        # These pinned owners use literal XML names without embedded parentheses.
        for match in re.finditer(rb'/XMLUID\s*:\s*(\([^)]*\))\s*;', data[start:end]):
            expected.add((start + match.start(1), start + match.end(1), 'identity'))
    if row['operation'] == 'layer':
        expected.update((*layer['nameSpan'], 'name') for layer in row['before']['layers']['layers'] if layer['nameSpan'] and any(start <= layer['start'] and layer['end'] <= end for start, end in row['spans']))
    actual = {(value['start'], value['end'], value['kind']) for value in row['replacements']}
    assert len(actual) == len(row['replacements']) and actual == expected
    original = {parsed(match[1] + b' Ln')[0].tokens[0] for match in re.finditer(rb'/XMLUID\s*:\s*(\([^)]*\))\s*;', data)}
    fresh, edits = set(), []
    for value in row['replacements']:
        old = parsed(data[value['start']:value['end']] + b' Ln')
        assert len(old) == 1 and old[0].command == 'Ln'
        new = bytes(value['value'])
        assert new == (b'copy_' if value['kind'] == 'identity' else b'Copy of ') + old[0].tokens[0]
        if value['kind'] == 'identity':
            assert new not in original and new not in fresh
            fresh.add(new)
        encoded = b'(' + b''.join(f'\\{byte:03o}'.encode() for byte in new) + b')'
        assert parsed(encoded + b' Ln')[0].tokens[0] == new
        edits.append((value['start'], value['end'], encoded))
    return edits


def copied(data, start, end, edits):
    """Allow only validated string edits inside an otherwise exact copied owner."""
    return patch(data[start:end], [(first - start, last - start, value) for first, last, value in edits if start <= first and last <= end])


def key(command):
    """Unify equivalent state components without conflating their color encodings."""
    return 'fill' if command in ('g', 'k', 'Xa') else 'stroke' if command in ('G', 'K', 'XA') else command


def input_state(document, items, boundary, private):
    """Recover definite scalar inputs without executing a native appearance graph."""
    state = {}
    for item in items[:boundary]:
        command = getattr(item, 'command', None)
        if command in SCALARS | COLORS and (private or not item.is_pseudo_comment):
            state[key(command)] = scalar_value(item)
        elif private and command == 'XW' and int(item.tokens[0]) == 1:
            name = item.tokens[1].decode('latin1')
            style = next(value for value in hierarchy(document.setup) if type(value).__name__ == 'KnownStyle' and value.Name == name)
            for value in hierarchy(style):
                if type(value).__name__ in ('FillStyle', 'StrokeStyle'):
                    state.pop('fill' if type(value).__name__ == 'FillStyle' else 'stroke', None)
            state.update(restored_style(document, name))
    return state


def exact_bytes(before, after, document, items, ranges, row, identity_edits):
    """Require exact insertions, unchanged originals and source-backed input replay."""
    edits = [(end, end, ('copy', index)) for index, (_, end) in enumerate(row['spans'])]
    if row['operation'] == 'layer':
        layers = row['before']['layers']
        edits.extend((*span, ('view', None)) for span in layers['viewSpans'])
        if layers['rootCountSpan']:
            edits.append((*layers['rootCountSpan'], ('count', None)))
    parts, position = [], 0
    for first, last, (kind, index) in sorted(edits):
        assert first >= position
        parts.append(re.escape(before[position:first]))
        if kind == 'copy':
            start, end = row['spans'][index]
            parts.append(rb'(\n(?:[^\r\n]+\n)*)' + re.escape(copied(before, start, end, identity_edits)) + b'\n')
        else:
            parts.append(rb'([^\r\n]*)')
        position = last
    parts.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(parts), after)
    assert match is not None, (row['result'], 'Unexpected source or copy edit')
    for (_, _, (kind, index)), fragment in zip(sorted(edits), match.groups()):
        if kind == 'view':
            assert not fragment
        elif kind == 'count':
            layers = row['before']['layers']
            count = layers['rootCount'] + sum(layers['layers'][index]['parent'] is None for index in row['selected'])
            assert fragment == before[slice(*layers['rootCountSpan'])].split(b':')[0] + b': ' + str(count).encode()
        else:
            for command in parsed(fragment):
                assert command.command in SCALARS | COLORS
                state = input_state(document, items, ranges[index][0], command.is_pseudo_comment)
                assert state.get(key(command.command)) == scalar_value(command), (row['result'], 'Copy input differs from source', command.command)


def views(inkai, source, target, row):
    """Duplicate exactly the requested SVG owners, retaining shared resources."""
    for mode in (('printing',) if row['source'].startswith('synthetic') else ('native', 'printing')):
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        if row['source'].startswith('group-'):
            selected = [artwork(before)[row['provenance']['firstPair']]]
        elif row['source'].startswith('layer-'):
            selected = [children(before)[1]]
        else:
            routes = [(0, 0), (0, 0, 0), (1, 0, 0)] if row['operation'] == 'group' else [(0,), (1,), (1, 0)]
            selected = []
            for index in row['selected']:
                node = before
                for step in routes[index]:
                    node = children(node)[step]
                selected.append(node)
        for node in selected:
            clone = deepcopy(node)
            if row['operation'] == 'layer':
                for layer in clone.iter():
                    if any(etree.QName(name).localname == 'groupmode' and value == 'layer' for name, value in layer.attrib.items()):
                        label = next(name for name in layer.attrib if etree.QName(name).localname == 'label')
                        layer.set(label, 'Copy of ' + layer.get(label))
            node.addnext(clone)
        assert [signature(node, before) for node in children(before)] == [signature(node, after) for node in children(after)], (row['result'], mode, 'Copied or retained geometry, style or ownership changed')


def translated_copy(target, translated, row):
    """Verify all copied contour/metadata alternatives after the follow-up edit."""
    before, after = target.read_bytes(), translated.read_bytes()
    normalized_after = after.replace(b'%%BoundingBox: 0 0 102 103', b'%%BoundingBox: 0 0 100 100', 1)
    span = row['after']['pairs'][1]
    start, end = span['start'], span['end']
    assert before[:start] == normalized_after[:start] and normalized_after.endswith(before[end:])
    changed_end = len(normalized_after) - len(before[end:])
    delimiters = rb'^%AI17_(?:Begin_Content_if_version_gt|Alternate_Content|End_Versioned_Content)[^\r\n]*'
    old = list(body(parsed(re.sub(delimiters, b'', before[start:end], flags=re.MULTILINE))))
    new = list(body(parsed(re.sub(delimiters, b'', normalized_after[start:changed_end], flags=re.MULTILINE))))
    assert len(old) == len(new)

    def fields(first, second):
        """Translate only the native canvas center, including the older branch."""
        if isinstance(first, dict):
            assert isinstance(second, dict) and first.keys() == second.keys()
            count = 0
            for name, value in first.items():
                if name.endswith('::CenterX') or name.endswith('::CenterY'):
                    assert second[name] == value + (2 if name.endswith('::CenterX') else -3)
                    count += 1
                else:
                    count += fields(value, second[name])
            return count
        assert first == second
        return 0

    centers, moves = 0, 0
    for first, second in zip(old, new):
        operator = getattr(first, 'command', None)
        assert operator == getattr(second, 'command', None)
        if operator in GEOMETRY:
            assert first.is_pseudo_comment == second.is_pseudo_comment and len(first.tokens) == len(second.tokens)
            assert [float(value) for value in second.tokens] == [float(value) + (2 if index % 2 == 0 else 3) for index, value in enumerate(first.tokens)]
            moves += operator == 'm'
        elif operator is None:
            centers += fields(first, second)
        else:
            assert normalized([first]) == normalized([second])
    assert centers == 4 and moves == 4


def verify(inkai, source, target, row):
    """Check exact source edits, fresh names, both saved branches and native flags."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    items, ranges = selected_ranges(before, original, row)
    edits = replacements(before, row)
    exact_bytes(before, after, original, items, ranges, row, edits)
    expected, position = [], 0
    pairs = row['before']['pairs']
    for start, end in sorted(row['spans']):
        while position < len(pairs) and pairs[position]['end'] <= end:
            expected.append((pairs[position], False))
            position += 1
        expected.extend((pair, True) for pair in pairs if start <= pair['start'] and pair['end'] <= end)
    expected.extend((pair, False) for pair in pairs[position:])
    assert len(expected) == len(row['after']['pairs'])
    for (old, copy), new in zip(expected, row['after']['pairs']):
        assert after[new['start']:new['end']] == copied(before, old['start'], old['end'], edits if copy else [])
    for private in (False, True):
        flags = iter(source_flags(original, private=private))
        moves = {index: next(flags) for index, item in enumerate(items) if getattr(item, 'command', None) == 'm' and (private or not item.is_pseudo_comment)}
        assert next(flags, None) is None
        expected_flags = []
        endings = {last: first for first, last in ranges}
        for index in range(len(items)):
            if index in moves:
                expected_flags.append(moves[index])
            if index + 1 in endings:
                expected_flags.extend(value for position, value in moves.items() if endings[index + 1] <= position <= index)
        assert expected_flags == source_flags(changed, private=private), (row['result'], 'Copied or retained native flags changed')
    views(inkai, source, target, row)


def main():
    """Require fixed source recipes, pinned fixtures and an unchanged native oracle."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/subtree-copy'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for name in ('manifest.json', 'document_manifest.json') for entry in json.loads(Path('test/corpus', name).read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in (*FILES, 'opacity.ai', BASE)}
    rows = json.loads((args.output / 'report.json').read_text())
    expected = requests()
    assert len(rows) == len(expected) == 23 and {(row['source'], row['operation']) for row in rows} == expected.keys()
    checked = []
    with tempfile.TemporaryDirectory(prefix='aicodec-subtree-copy-') as temporary:
        for row in rows:
            assert (row['selected'], row['rejected']) == expected[row['source'], row['operation']]
            assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['operation'] + '.ps'
            source, target = args.output / row['original'], args.output / row['result']
            if row['source'].startswith('synthetic'):
                assert row['provenance'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[row['source']]
            else:
                if row['operation'] == 'group':
                    assert row['provenance']['firstPair'] == (0 if row['source'] == 'group-opacity.ai' else 1)
                provenance(inkai, source, row, programs, Path(temporary))
            if row['rejected']:
                assert row['issue'] and source.read_bytes() == target.read_bytes() and row['before'] == row['after']
            else:
                assert row['issue'] is None
                verify(inkai, source, target, row)
            expected_translation = 'synthetic.group.translated.ps' if (row['source'], row['operation']) == ('synthetic', 'group') else None
            assert row['translated'] == expected_translation
            if row['translated']:
                translated_copy(target, args.output / row['translated'], row)
            checked.append(row['result'])
            print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, derivedRealCopies=8, syntheticCopies=10, refusals=5, followupTranslations=1), indent=2) + '\n')


if __name__ == '__main__':
    main()
