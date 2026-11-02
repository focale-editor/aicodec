#!/usr/bin/env python3
"""Verify complete mixed-subtree deletion against unchanged pinned native readers."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace

from lxml import etree

from corpus_support import REVISION, printable_svg
from verify_native_direct_shapes import normalized
from verify_native_layers import verified_inventory
from verify_native_reference_resources import BASE, FILES, pinned_program, provenance as mixed_provenance
from verify_native_shape_lifecycle import artwork, body, bundles, inventory, signature, source_flags
from verify_native_shape_removal import COLORS, SCALARS, restored_style, scalar_value
from verify_native_structure import parsed

SYNTHETIC = {
    'synthetic': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-inner': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-all': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-nested': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-child': '16ae6377fe0b54a40d27e51cb65debe25e2284999f99b4955bd0c95cb648dbbd',
    'synthetic-reset': '1f4bece782f61beffce149f04d711e748ea02e74b7cafcd8255eeede57834098',
    'synthetic-following': '3447ebbb42c50978fd7708d2f2799a9ed1a430964b0bf9dbacfcb1a25d8b7fd0',
    'synthetic-reference': '0d97d0eb015ecc3f7a3d7ac203848216b13ce014bd11e12c8c5b2dcd0ffc8aec',
    'synthetic-alias': '1033ccaa89eacbc94faf39c760d9404f40aea1f031cc10eaefb383a133b4c825',
    'synthetic-unknown': '48ed366a5e861c9283a301f854a37c9dbc0a2d0e9e83580258100e9c3820f1ae',
}


def requests():
    """Pin exact subtree selections and expected refusal cases independently."""
    result = {(f'group-{name}', 'group'): ([0], False) for name in (*FILES, 'opacity.ai')}
    result.update({(f'layer-{name}', 'layer'): ([1], False) for name in FILES})
    result.update({
        ('synthetic', 'group'): ([0], False), ('synthetic-inner', 'group'): ([1], False),
        ('synthetic-all', 'group'): ([2, 0], False), ('synthetic', 'layer'): ([0], False),
        ('synthetic-nested', 'layer'): ([1], False), ('synthetic-child', 'layer'): ([2], False),
        ('synthetic-all', 'layer'): ([1, 0], False), ('synthetic-reset', 'layer'): ([1], False),
        ('synthetic-following', 'group'): ([2], True), ('synthetic-following', 'layer'): ([1], True),
        ('synthetic-reference', 'layer'): ([0], True), ('synthetic-alias', 'layer'): ([0], True),
        ('synthetic-unknown', 'layer'): ([0], True),
    })
    return result


def provenance(inkai, source, row, programs, directory):
    """Rebuild declared wrappers around exact original pairs and mixed assemblies."""
    recipe = row['provenance']
    name = recipe['donor']
    assert name in (*FILES, 'opacity.ai')
    first, last = recipe['start'], recipe['end']
    opening, closing = recipe['opening'].encode(), recipe['closing'].encode()
    data = source.read_bytes()
    if row['operation'] == 'group':
        original = programs[name]
        assert row['source'] == 'group-' + name and opening == b'u\nu\n' and closing == b'\nU\nU\n'
        assert data == original[:first] + opening + original[first:last] + closing + original[last:]
        donor = directory / name
        donor.write_bytes(original)
        selected = bundles(SimpleNamespace(trailer=parsed(original[first:last])))
        offset = recipe.get('firstPair', 0)
        assert offset in (0, 1)
        expected = bundles(inkai.parse(str(donor)))[offset:offset + 2]
        assert len(selected) == len(expected)
        assert [normalized(bundle['items']) for bundle in selected] == [normalized(bundle['items']) for bundle in expected]
    else:
        assert row['source'] == 'layer-' + name
        expected_opening = (b'%AI5_BeginLayer\n1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb\n(Derived) Ln\n1 AE\n'
                            b'%_/ArtDictionary :\n%_/XMLUID : (Derived) ; (AI10_ArtUID) ,\n%_;\nu\n')
        assert opening == expected_opening and closing == b'\nU\nLB\n%AI5_EndLayer--'
        pair_end = first + len(opening) + last - first
        assert data[first:first + len(opening)] == opening and data[pair_end:pair_end + len(closing)] == closing
        unwrapped = (data[:first] + data[first + len(opening):pair_end] + data[pair_end + len(closing):]).replace(b'%AI5_NumLayers: 2', b'%AI5_NumLayers: 1', 1)
        path = directory / 'mixed.ps'
        path.write_bytes(unwrapped)
        mixed_provenance(inkai, path, {**row, 'source': 'mixed-' + name}, programs, directory)


def groups(items):
    """Select complete ordinary groups enclosing private artwork independently."""
    result, stack = [], []
    for index, item in enumerate(items):
        command = getattr(item, 'command', None)
        if command in ('u', '*u', 'q'):
            stack.append(index)
        elif command in ('U', '*U', 'Q'):
            first = stack.pop()
            if items[first].command != 'u' or not any(getattr(child, 'command', None) == 'm' and child.is_pseudo_comment for child in items[first:index]):
                continue
            last = index + 1
            if first and getattr(items[first - 1], 'command', None) == 'Ae':
                first -= 1
            if last < len(items) and isinstance(items[last], dict) and items[last].get('_type') == 'ArtDictionary':
                last += 1
            result.append((first, last))
    assert not stack
    return sorted(result)


def selected_ranges(data, document, row):
    """Bind each selected byte span to a complete independently decoded owner."""
    items = list(body(document.trailer))
    candidates = groups(items) if row['operation'] == 'group' else None
    selected = []
    for index, span in zip(row['selected'], row['spans']):
        fragment = list(body(parsed(data[slice(*span)])))
        expected = normalized(fragment)
        if candidates is not None:
            first, last = candidates[index]
            assert normalized(items[first:last]) == expected
        else:
            layer = row['before']['layers']['layers'][index]
            assert span == [layer['start'], layer['end']]
            matches = [position for position in range(len(items) - len(fragment) + 1) if normalized(items[position:position + len(fragment)]) == expected]
            assert len(matches) == 1
            first, last = matches[0], matches[0] + len(fragment)
        selected.append((first, last))
    ordered = sorted(selected)
    assert all(previous[1] <= current[0] for previous, current in zip(ordered, ordered[1:]))
    return items, selected


def replay(fragment, replacement, document):
    """Require exact scalar order, privacy and source-backed style effects only."""
    actual = parsed(replacement)
    position = 0
    for item in body(parsed(fragment)):
        command = getattr(item, 'command', None)
        if command in SCALARS | COLORS:
            assert position < len(actual)
            changed = actual[position]
            assert changed.is_pseudo_comment == item.is_pseudo_comment and scalar_value(changed) == scalar_value(item)
            position += 1
        elif command == 'XW' and int(item.tokens[0]) == 1:
            expected = restored_style(document, item.tokens[1].decode('latin1'))
            tail = actual[position:position + len(expected)]
            assert all(value.is_pseudo_comment and value.command in SCALARS for value in tail)
            assert len({value.command for value in tail}) == len(tail) == len(expected)
            assert {value.command: scalar_value(value) for value in tail} == expected
            position += len(expected)
    assert position == len(actual)


def exact_bytes(before, after, document, row):
    """Keep all unselected bytes and allow only declared layer count/view changes."""
    edits = [(*span, ('subtree', index)) for index, span in enumerate(row['spans'])]
    if row['operation'] == 'layer':
        layers = row['before']['layers']
        edits.extend((*span, ('view', None)) for span in layers['viewSpans'])
        if layers['rootCountSpan'] is not None:
            edits.append((*layers['rootCountSpan'], ('count', None)))
    pieces, position = [], 0
    ordered = sorted(edits)
    for first, last, (kind, index) in ordered:
        assert position <= first <= last <= len(before)
        pieces.append(re.escape(before[position:first]))
        if kind == 'subtree':
            count = 0
            for item in body(parsed(before[first:last])):
                command = getattr(item, 'command', None)
                if command in SCALARS | COLORS:
                    count += 1
                elif command == 'XW' and int(item.tokens[0]) == 1:
                    count += len(restored_style(document, item.tokens[1].decode('latin1')))
            # Scalar counts make adjacent newline-separated deletions unambiguous.
            pieces.append(rb'(\n(?:\n*[^\r\n]+\n){' + str(count).encode() + rb'})')
        else:
            pieces.append(rb'([^\r\n]*)')
        position = last
    pieces.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(pieces), after)
    assert match is not None, (row['result'], 'Unselected source or scalar counts changed')
    for (_, _, (kind, index)), value in zip(ordered, match.groups()):
        if kind == 'subtree':
            replay(before[slice(*row['spans'][index])], value, document)
        elif kind == 'view':
            assert not value
        else:
            old = before[slice(*row['before']['layers']['rootCountSpan'])]
            expected = row['before']['layers']['rootCount'] - sum(row['before']['layers']['layers'][index]['parent'] is None for index in row['selected'])
            assert value == old.split(b':')[0] + b': ' + str(expected).encode()


def children(node):
    """Keep visible SVG structure while resource signatures resolve through defs."""
    return [child for child in node if etree.QName(child).namespace == 'http://www.w3.org/2000/svg' and etree.QName(child).localname != 'defs']


def views(inkai, source, target, row):
    """Compare real native/printing and synthetic printing after exact owner deletion."""
    for mode in (('printing',) if row['source'].startswith('synthetic') else ('native', 'printing')):
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        if row['source'].startswith('group-'):
            removed = [artwork(before)[int(row['source'] == 'group-opacity.ai')]]
        elif row['source'].startswith('layer-'):
            removed = [children(before)[1]]
        else:
            routes = [(0, 0), (0, 0, 0), (1, 0, 0)] if row['operation'] == 'group' else [(0,), (1,), (1, 0)]
            removed = []
            for index in row['selected']:
                node = before
                for step in routes[index]:
                    node = children(node)[step]
                removed.append(node)
        for node in removed:
            node.getparent().remove(node)
        assert [signature(node, before) for node in children(before)] == [signature(node, after) for node in children(after)], (row['result'], mode, 'Retained geometry, appearance or ownership changed')


def verify(inkai, source, target, row):
    """Verify source ownership, state, resources, alternatives and retained flags."""
    before, after = source.read_bytes(), target.read_bytes()
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    items, selected = selected_ranges(before, original, row)
    exact_bytes(before, after, original, row)
    retained = [pair for pair in row['before']['pairs'] if not any(first <= pair['start'] and pair['end'] <= last for first, last in row['spans'])]
    assert len(retained) == len(row['after']['pairs'])
    for old, new in zip(retained, row['after']['pairs']):
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    for private in (False, True):
        moves = [index for index, item in enumerate(items) if getattr(item, 'command', None) == 'm' and (private or not item.is_pseudo_comment)]
        flags = source_flags(original, private=private)
        assert len(moves) == len(flags)
        expected = [value for index, value in zip(moves, flags) if not any(first <= index < last for first, last in selected)]
        assert expected == source_flags(changed, private=private)
    views(inkai, source, target, row)


def main():
    """Require exact requests, manifest provenance and an unchanged pinned oracle."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/subtree-removal'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for name in ('manifest.json', 'document_manifest.json') for entry in json.loads(Path('test/corpus', name).read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in (*FILES, 'opacity.ai', BASE)}
    rows = json.loads((args.output / 'report.json').read_text())
    expected = requests()
    assert len(rows) == len(expected) == 22 and {(row['source'], row['operation']) for row in rows} == expected.keys()
    checked = []
    with tempfile.TemporaryDirectory(prefix='aicodec-subtree-removal-') as temporary:
        for row in rows:
            assert (row['selected'], row['rejected']) == expected[row['source'], row['operation']]
            assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['operation'] + '.ps'
            source, target = args.output / row['original'], args.output / row['result']
            if row['source'].startswith('synthetic'):
                assert row['provenance'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[row['source']]
            else:
                provenance(inkai, source, row, programs, Path(temporary))
            if row['rejected']:
                assert row['issue'] and source.read_bytes() == target.read_bytes() and row['before'] == row['after']
            else:
                assert row['issue'] is None
                verify(inkai, source, target, row)
            checked.append(row['result'])
            print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, derivedRealRemovals=9, syntheticRemovals=8, syntheticRefusals=5), indent=2) + '\n')


if __name__ == '__main__':
    main()
