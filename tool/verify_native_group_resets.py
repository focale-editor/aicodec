#!/usr/bin/env python3
"""Verify neutral group-reset dissolution with native ownership and independent ink."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from lxml import etree
from PIL import Image, ImageChops

from corpus_support import REVISION, printable_svg
from verify_native_direct_shapes import normalized
from verify_native_reference_resources import FILES, pinned_program
from verify_native_shape_lifecycle import body, bundles, signature
from verify_native_structure import parsed
from verify_native_subtree_grouping import verify
from verify_native_subtree_removal import children

SYNTHETIC = {
    'outer': '8a4356f4a4f4effc48451973c59781f37cb791fe661245ddfe9efb3573f51ef2',
    'inner': '8a4356f4a4f4effc48451973c59781f37cb791fe661245ddfe9efb3573f51ef2',
    'disjoint': '8a4356f4a4f4effc48451973c59781f37cb791fe661245ddfe9efb3573f51ef2',
    'empty': '70be3e36a6815524b12e9c8c5825e513b82acdf4a4aac8902bc427385a8b589e',
    'mixed': 'aae8a39fb6df2f244026ac8f1ded1832bec5407f297084c00a18db1be567e5a2',
    'reject-0': 'c9128b410fe88b413eaa91740625f89011bdfde14f74df0af43221d72c31973a',
    'reject-1': 'be83dd932f9545db3437149699fb534c2629a945170a91adffdec60fb3e01f9c',
    'reject-2': '4c334c022fcecae769c17653663b5b78f33df62ae03f01e719e42462fb171678',
    'reject-3': '4a0154c23acb993d8c769b79da1eef00287c89df91aaceceecfd30246759973e',
    'reject-4': '9a6d78e11081a2c99a2155a247860cf4a1db8a18c78f12b5247e76052a4b9090',
    'reject-5': '498fe2b0b4005f6154cbcc2b4c7a8485bfc13f68981cd19fe86c40dd15c8262b',
    'reject-6': 'c4bff96979d9e3395785d306afa29059004334ccd9ab09d42e491c912633e0f6',
    'reject-7': '415b63e492465972ac07361a5f2dcded27bc3905d7907aef1343fd8d306544ac',
}


def requests():
    """Pin source-order selections, parent identities and refusal variants."""
    result = {(name, 'wrapped'): ([0], ['']) for name in FILES}
    result['layers_and_sublayers.ai', 'original'] = [0], ['']
    for variant, indices in [('outer', [0]), ('inner', [1]), ('disjoint', [0, 2]), ('empty', [1])]:
        result['synthetic', variant] = indices, [''] * len(indices)
    result['synthetic', 'mixed'] = [0, 4, 8], ['outer_0', 'outer_1', 'outer_2']
    result.update({('synthetic', f'reject-{index}'): ([0], ['']) for index in range(8)})
    return result


def neutral_groups(root):
    """Remove only anonymous SVG containers with no visual attributes beyond opacity one."""
    for node in reversed(list(root.iter())):
        if etree.QName(node).localname != 'g' or node is root:
            continue
        attributes = {key: value for key, value in node.attrib.items() if key != 'id'}
        if attributes and attributes != {'style': 'opacity:1.0'} and attributes != {'style': 'opacity:1'}:
            continue
        parent = node.getparent()
        position = parent.index(node)
        parent.remove(node)
        for child in list(node):
            parent.insert(position, child)
            position += 1


def views(inkai, source, target, row, directory):
    """Require unchanged complete artwork, resources and exact 1024-wide RGBA pixels."""
    modes = ('printing',) if row['source'] == 'synthetic' else ('native', 'printing')
    for mode in modes:
        before = etree.fromstring(inkai.to_svg(str(source)) if mode == 'native' else etree.tostring(printable_svg(inkai, source)))
        after = etree.fromstring(inkai.to_svg(str(target)) if mode == 'native' else etree.tostring(printable_svg(inkai, target)))
        assert before.attrib == after.attrib
        images = []
        for label, root in [('original', before), ('changed', after)]:
            path = directory / f'{row["source"]}.{row["variant"]}.{mode}.{label}.svg'
            path.write_bytes(etree.tostring(root))
            subprocess.run(['rsvg-convert', '-w', '1024', '-o', str(path.with_suffix('.png')), str(path)], check=True, capture_output=True)
            with Image.open(path.with_suffix('.png')) as image:
                images.append(image.convert('RGBA'))
        assert images[0].size == images[1].size
        assert all(channel.getbbox() is None for channel in ImageChops.difference(*images).split()), (row['result'], mode, 'Changed independent pixels')
        neutral_groups(before)
        neutral_groups(after)
        assert [signature(node, before) for node in children(before)] == [signature(node, after) for node in children(after)], (row['result'], mode, 'Changed artwork or resources')


def main():
    """Bind pinned original programs, exact recipes and every requested transaction."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/group-resets'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    programs = {name: pinned_program(name, manifest) for name in (*FILES, 'layers_and_sublayers.ai')}
    rows = json.loads((args.output / 'report.json').read_text())
    expected, checked = requests(), []
    assert len(rows) == len(expected) == 18 and {(row['source'], row['variant']) for row in rows} == expected.keys()
    with tempfile.TemporaryDirectory(prefix='aikit-group-resets-') as temporary:
        directory = Path(temporary)
        for row in rows:
            name, variant = row['source'], row['variant']
            indices, names = expected[name, variant]
            assert row['operation'] == 'dissolve' and row['inheritParentFlags'] is True and row['discardMetadata'] == (variant == 'mixed')
            assert [owner['index'] for owner in row['selected']] == indices and [owner['name'] for owner in row['selected']] == names
            assert all(owner['kind'] == 'group' and owner['reset'] is True for owner in row['selected'])
            assert row['original'] == f'{name}.{variant}.original.ps' and row['result'] == f'{name}.{variant}.ps'
            source, target = args.output / row['original'], args.output / row['result']
            if name == 'synthetic':
                assert row['recipe'] is None and hashlib.sha256(source.read_bytes()).hexdigest() == SYNTHETIC[variant]
            elif variant == 'original':
                assert row['recipe'] is None and source.read_bytes() == programs[name]
            else:
                recipe = row['recipe']
                first, last = recipe['start'], recipe['end']
                opening, closing = b'0 Ae\nu\n', b'\nU\n9 () XW\n'
                assert recipe == dict(start=first, end=last, opening=opening.decode(), closing=closing.decode())
                original = programs[name]
                assert source.read_bytes() == original[:first] + opening + original[first:last] + closing + original[last:]
                path = directory / name
                path.write_bytes(original)
                pairs = bundles(inkai.parse(str(path)))
                selected = list(body(parsed(original[first:last])))
                assert normalized(selected[:len(pairs[0]['items'])]) == normalized(pairs[0]['items'])
                assert normalized(selected[-len(pairs[1]['items']):]) == normalized(pairs[1]['items'])
                assert row['selected'][0]['start'] == first and row['selected'][0]['end'] == last + len(opening) + len(closing) - 1
            if variant.startswith('reject-'):
                assert row['issue'] and source.read_bytes() == target.read_bytes()
            else:
                assert row['issue'] is None
                verify(inkai, source, target, row)
                views(inkai, source, target, row, directory)
            checked.append(row['result'])
            print(row['result'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, originalReal=1, derivedReal=4, synthetic=5, refusals=8, pixelComparisons=15), indent=2) + '\n')


if __name__ == '__main__':
    main()
