#!/usr/bin/env python3
"""Verify mixed-owner deletion, exact shared resources and declared fixture assembly."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from lxml import etree

from corpus_support import REVISION, native_programs, printable_svg
from verify_native_direct_shapes import normalized
from verify_native_layers import verified_inventory
from verify_native_path_lifecycle import patch
from verify_native_reference_scope import values
from verify_native_shape_lifecycle import body, bundles, inventory, signature, source_flags
from verify_native_shape_removal import COLORS, SCALARS, exact_deletions, hierarchy, retained_flags, scalar_value
from verify_native_structure import parsed

FILES = ('simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai')
BASE = 'units-20x40mm_origin_topleft_CC.ai'
BRIDGE = b'0 A 0 Xw 0.1 g 0 G 2 w [] 0 d 0 O 0 R 0 XR 0 D 0 Ap 0 J 0 j 10 M 0 1 0 0 0 Xy\n'
SYNTHETIC = {
    'synthetic': '5539223ba8e5e3480a2c95688da0f9a54b3f7ac4dbc03bae94259dfc15c42d69',
    'synthetic-replay': '92e9b099911ac521814370566ee0c21d8d5473130bc93ef0b18a578bc8987126',
    'synthetic-unused': 'd5236e60c65dbf4cf30a37db2f6b297d24ebca2d0bd0a37f09a006a24126289a',
    'synthetic-style-reference': '3dcfe45a1a18fe3ca2fd053b57ee5c18b427ca5a37e49037d100e0cfadbb292f',
    'synthetic-bank-comment': '9aafa0bc0574f6d5288f2d5854920c043727245f1fe78088e2674dea28cf00cb',
    'synthetic-identity-alias': '4fa0bc8c0d2d33e3959a8daa9b439aa1a638270f81261c252669937e4cede437',
    'synthetic-private': 'cfdf50fa3551b0cb4a4f880b99bccf87d915416b0d59c95f2e96cfe50cafff68',
}


def requests():
    """Pin mixed derived fixtures, full-source refusals and synthetic operations."""
    result = {(f'mixed-{name}', 'layer'): False for name in FILES}
    result.update({(name, 'layer'): True for name in FILES})
    result.update({('synthetic', operation): False for operation in ('path', 'group', 'layer', 'pair')})
    result.update({(name, 'path'): name not in ('synthetic-replay', 'synthetic-unused') for name in SYNTHETIC if name != 'synthetic'})
    return result


def pinned_program(name, manifest):
    """Extract a manifest-pinned native program independently of the Dart producer."""
    path = Path('test/corpus/files', name)
    entry = manifest[name]
    assert path.stat().st_size == entry['size'] and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
    programs = native_programs(path) if path.read_bytes().startswith(b'%PDF-') else [path.read_bytes()]
    assert len(programs) == 1
    return programs[0]


def styles(document):
    """Read each declared native style without discarding its hierarchical fields."""
    return {item.Name: item for item in hierarchy(document.setup) if type(item).__name__ == 'KnownStyle'}


def provenance(inkai, source, row, programs, directory):
    """Reconstruct the declared assembly and bind every donor fragment independently."""
    from inkai.parser.streamreader import dec

    recipe = row['provenance']
    assert recipe['base'] == BASE and recipe['donor'] in FILES and row['source'] == 'mixed-' + recipe['donor']
    assert recipe['bridge'].encode() == BRIDGE
    base, donor = programs[BASE], programs[recipe['donor']]
    setup, end = recipe['baseSetupPosition'], recipe['baseBodyPosition']
    assert setup == base.index(b'%%EndSetup') and base[end:].lstrip().startswith(b'%%PageTrailer')
    pair = donor[slice(*recipe['donorPair'])]
    style = donor[slice(*recipe['donorStyle'])]
    gradients = [donor[slice(*span)] for span in recipe['donorGradients']]
    inserted = str(len(gradients)).encode() + b' Bn\n' + b'\n'.join(gradients) + b'\n' + style + b'\n'
    assert source.read_bytes() == base[:setup] + inserted + base[setup:end] + b'\n' + BRIDGE + pair + b'\n' + base[end:]
    path = directory / recipe['donor']
    path.write_bytes(donor)
    original = inkai.parse(str(path))
    mixed = inkai.parse(str(source))
    selected = bundles(original)[1]
    assert normalized(body(parsed(pair))) == normalized(selected['items'])
    decoded = parsed(style)
    assert len(decoded) == 1 and decoded[0].Name == selected['style']
    assert repr(values(decoded[0])) == repr(values(styles(original)[selected['style']])) == repr(values(styles(mixed)[selected['style']]))
    names = []
    for fragment in gradients:
        opening, rest = fragment.splitlines()[0], fragment.splitlines()[-1]
        assert opening.startswith(b'%AI5_BeginGradient: ') and rest == b'%AI5_EndGradient'
        name = dec(parsed(opening.split(b': ', 1)[1] + b' Ln')[0].tokens[0])
        names.append(name)
        first, second = original.setup.gradients[name], mixed.setup.gradients[name]
        assert repr(first.definition) == repr(second.definition)
        assert repr(first.children) == repr(second.children)
    assert list(mixed.setup.gradients) == names and len(set(names)) == len(names)


def ordinary_span(data, row):
    """Locate and independently qualify the selected ordinary owner and identity."""
    operation = row['operation']
    if operation == 'layer':
        layer = row['before']['layers']['layers'][0]
        assert layer['identifier'] == list(('Layer_1' if row['source'].startswith('mixed-') else 'Target').encode())
        return layer['start'], layer['end']
    selected = next(item for item in row['before']['objects'] if item['kind'] == operation)
    assert not selected['private'] and selected['identifier'] == list((operation + '_target').encode())
    metadata = parsed(data[slice(*selected['dictionary'])])
    assert len(metadata) == 1 and metadata[0]['AI10_ArtUID'] == operation + '_target'
    if operation == 'path':
        commands = [item for item in parsed(data[selected['start']:selected['artworkEnd']]) if hasattr(item, 'command')]
        assert [item.command for item in commands] == ['m', 'L', 'S']
        assert tuple(map(float, commands[0].tokens)) == (70.0, 0.0)
    return selected['start'], selected['end']


def ordinary_bytes(before, after, original, row):
    """Require literal unselected bytes, exact count/view edits and retained scalars."""
    operation = row['operation']
    start, end = ordinary_span(before, row)
    events = []
    if operation == 'path':
        span = next(item for item in row['before']['objects'] if item['kind'] == 'path')
        events.append((start, end, b' '))
        assert span['count'] is not None
        count = parsed(before[slice(*span['count'])])
        assert len(count) == 1 and count[0].command == 'As' and count[0].tokens == [b'2']
        events.append((*span['count'], b' '))
        assert patch(before, events) == after
        return
    # One complete ordinary owner is removed; its source scalar assignments remain.
    scalar = rb'[+\-.\deE \t\r\[\]]+ (?:' + b'|'.join(key.encode() for key in sorted(SCALARS | COLORS)) + rb')\n'
    events.append((start, end, rb'(\n(?:' + scalar + rb')*)'))
    if operation == 'layer':
        layers = row['before']['layers']
        for first, last in layers['viewSpans']:
            events.append((first, last, b''))
        if layers['rootCountSpan']:
            first, last = layers['rootCountSpan']
            assert before[first:last].endswith(b': 1')
            events.append((first, last, re.escape(before[first:last].split(b':', 1)[0] + b': 0')))
    pieces, position = [], 0
    for first, last, replacement in sorted(events):
        assert first >= position
        pieces.extend([re.escape(before[position:first]), replacement])
        position = last
    pieces.append(re.escape(before[position:]))
    match = re.fullmatch(b''.join(pieces), after)
    assert match is not None, (row['result'], 'Unexpected source edit')
    source = [item for item in body(parsed(before[start:end])) if getattr(item, 'command', None) in SCALARS | COLORS]
    retained = parsed(match.group(1))
    assert [(item.is_pseudo_comment, scalar_value(item)) for item in retained] == [(item.is_pseudo_comment, scalar_value(item)) for item in source]


def view(inkai, source, target, row):
    """Delete exactly the selected original SVG subtree and compare both real views."""
    modes = ('printing',) if row['source'] in SYNTHETIC else ('native', 'printing')
    for mode in modes:
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        children = [item for item in before if etree.QName(item).namespace == 'http://www.w3.org/2000/svg' and etree.QName(item).localname != 'defs']
        operation = row['operation']
        selected = children[1] if operation == 'pair' else children[0]
        if operation == 'group':
            selected = selected[0]
        elif operation == 'path':
            selected = selected[0][0]
        selected.getparent().remove(selected)
        assert signature(before, before) == signature(after, after), (row['result'], mode, 'Geometry, resources, paint or enclosing state changed')


def verify(inkai, source, target, row):
    """Check exact retained native owners, resource bytes, identities and both views."""
    original = inventory(inkai, source, row['before']['pairs'])
    changed = inventory(inkai, target, row['after']['pairs'])
    verified_inventory(inkai, source, row['before']['layers'])
    verified_inventory(inkai, target, row['after']['layers'])
    before, after = source.read_bytes(), target.read_bytes()
    if row['operation'] == 'pair':
        exact_deletions(before, after, original, {**row, 'selected': [0], 'before': row['before']['pairs']})
        retained_flags(original, changed, [0])
        retained = row['before']['pairs'][1:]
    else:
        ordinary_bytes(before, after, original, row)
        retained = row['before']['pairs']
        # Each ordinary fixture owner has exactly one public contour before its pairs.
        for private in (False, True):
            assert source_flags(original, private=private)[1:] == source_flags(changed, private=private)
    assert len(retained) == len(row['after']['pairs'])
    for old, new in zip(retained, row['after']['pairs']):
        assert before[old['start']:old['end']] == after[new['start']:new['end']]
    assert {name: repr(values(style)) for name, style in styles(original).items()} == {name: repr(values(style)) for name, style in styles(changed).items()}
    assert {name: repr(gradient.children) for name, gradient in original.setup.gradients.items()} == {name: repr(gradient.children) for name, gradient in changed.setup.gradients.items()}
    view(inkai, source, target, row)


def main():
    """Require fixed transactions, pinned provenance and an unchanged native oracle."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/reference-resources'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for name in ('manifest.json', 'document_manifest.json') for entry in json.loads(Path('test/corpus', name).read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in (*FILES, BASE)}
    expected = requests()
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 18 and {(row['source'], row['operation']) for row in rows} == expected.keys()
    checked = []
    with tempfile.TemporaryDirectory(prefix='aikit-reference-resources-') as temporary:
        for row in rows:
            assert row['rejected'] == expected[row['source'], row['operation']]
            assert row['original'] == row['source'] + '.original.ps' and row['result'] == row['source'] + '.' + row['operation'] + '.ps'
            source, target = args.output / row['original'], args.output / row['result']
            if row['source'] in SYNTHETIC:
                assert row['provenance'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[row['source']]
            elif row['source'] in FILES:
                assert row['provenance'] is None and source.read_bytes() == programs[row['source']]
            else:
                provenance(inkai, source, row, programs, Path(temporary))
            if row['rejected']:
                assert row['issue'] and source.read_bytes() == target.read_bytes() and row['before'] == row['after']
                if row['source'] in FILES:
                    assert 'opaque reference owners' in row['issue']
            else:
                assert row['issue'] is None
                verify(inkai, source, target, row)
            checked.append(row['result'])
            print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, derivedRealRemovals=4, syntheticRemovals=6, fullSourceRefusals=4, syntheticRefusals=4), indent=2) + '\n')


if __name__ == '__main__':
    main()
