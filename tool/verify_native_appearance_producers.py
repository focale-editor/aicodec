#!/usr/bin/env python3
"""Verify isolated paint edits in complete producer programs and printing output."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from lxml import etree
from PIL import Image, ImageChops

from corpus_support import REVISION
from verify_native_appearance_edits import replace_once, string
from verify_native_appearances import verify
from verify_native_printing import render

PRODUCERS = {'simple_shapes.ai': (17, 143, 26), 'simple_shapes_cc.ai': (18, 149, 26)}
WHITE = b'0 0 0 0 1 1 1 Xa'
CYAN = b'1.0 0.0 0.0 0.0 0.0 1.0 1.0 Xa'


def expected(data, row, ordered=False):
    """Specify exact changes after independently binding all inventory spans."""
    assert row['selectedShapes'] == [0] and row['style'] == 9 and row['part'] == 4
    style = row['before']['styles'][9]
    assert bytes(style['name']) == b'Anon amY4LCj5JfA=' and style['uses'] == [21]
    start, end = style['record']
    name = b'Fill above stroke' if ordered else b'Selected cyan'
    copy = data[start:end]
    if ordered:
        parts = style['parts']
        assert parts[1]['children'] == [2, 3, 4]
        assert parts[2]['strokeAlignment'] == 'inside' and parts[4]['visible']
        for slot, child in reversed(list(zip((2, 3, 4), (4, 3, 2), strict=True))):
            first, last = parts[slot]['record']
            copy = copy[:first - start] + data[slice(*parts[child]['record'])] + copy[last - start:]
    else:
        copy = replace_once(copy, WHITE, CYAN)
    copy = replace_once(copy, b'(Anon amY4LCj5JfA=) /Name', string(name) + b' /Name')
    use = row['before']['uses'][21]
    old = b'1 (Anon amY4LCj5JfA=) XW'
    assert data[slice(*use['span'])] == old
    assert data.count(b'%%EndSetup') == 1
    body = data.index(b'%%EndSetup') + len(b'%%EndSetup')
    foreground = data[body:use['span'][0]]
    assert foreground.count(WHITE) == 1
    color = body + foreground.index(WHITE)
    edits = [(end, end, b'\n' + copy + b'\n'), (*use['span'], b'1 ' + string(name) + b' XW')]
    if ordered:
        group_start = body + foreground.index(b'\nu\n') + 1
        group_end = group_start + data[group_start:use['span'][0]].index(b'\nU\n%_/ArtDictionary') + 2
        group = data[group_start:group_end]
        outline, = re.findall(rb'(?ms)^\*u\n.*?^\*U$', group)
        black, = re.findall(rb'(?m)^[0-9. ]+ Xa$', outline)
        geometry = b'719 -399 m\n269 -399 L\n269 -149 L\n719 -149 L\n719 -399 L'
        # Bind the supplied rectangle to its original private authoritative path.
        assert b'%_' + geometry.replace(b'\n', b'\n%_') + b'\n%_n' in data[group_end:use['span'][0]]
        count = b'4 As\n' if b'4 As\n' in group else b''
        replacement = b'u\n0 O\n0 1 0 0 0 Xy\n0 J 0 j 1 w 10 M []0 d\n0 XR\n0 Ae\n' + outline + b'\n' + count + b'0 D\n' + WHITE + b'\n' + geometry + b'\nf\n' + black + b'\n1 D\nU'
        edits.append((group_start, group_end, replacement))
    else:
        edits.append((color, color + len(WHITE), CYAN))
    for start, end, value in sorted(edits, reverse=True):
        data = data[:start] + value + data[end:]
    # The bounds writer retains the same values with its canonical float spelling.
    data, count = re.subn(rb'(?m)^(%%HiResBoundingBox:[^\r\n]*) -149(?=\r?$)', rb'\1 -149.0', data)
    assert count == 1
    return data


def order_reference(original, output):
    """Compose the known opaque rectangle above the original inside-stroke ink."""
    tree = etree.parse(output / f'{original.name}.svg')
    group, = tree.xpath('/*[local-name()="svg"]/*[local-name()="g"]/*[local-name()="g"][1]')
    fill, stroke = list(group)
    assert fill.get('d') == 'M 269.5 398.5 L 269.5 149.5 L 718.5 149.5 L 718.5 398.5 L 269.5 398.5 Z'
    assert 'fill:#ffffff' in fill.get('style') and 'fill:#000000' in stroke.get('style')
    group.remove(fill)
    rectangle = etree.SubElement(group, '{http://www.w3.org/2000/svg}rect', x='269', y='149', width='450', height='250', style=fill.get('style'))
    assert rectangle.getprevious() is stroke
    svg = output / f'{original.name}.order-reference.svg'
    png = svg.with_suffix('.png')
    svg.write_bytes(etree.tostring(tree))
    subprocess.run(['inkscape', str(svg), '--export-type=png', '--export-width=1200', f'--export-filename={png}'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with Image.open(png) as image:
        return image.convert('RGBA')


def main():
    """Require both pinned producers, exact source edits and supplied ink."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/appearance-producers'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 2 and {row['file'] for row in rows} == set(PRODUCERS)
    results = []
    for row in rows:
        name, counts = row['file'], PRODUCERS[row['file']]
        assert row['sharedRejection'] == 'Artboard setup inventories require unconditional ownership.'
        fixture = Path('test/corpus/files', name)
        data, entry = fixture.read_bytes(), manifest[name]
        assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
        assert entry['license'] and entry['revision'] == REVISION
        original = args.output / f'{name}.before.ps'
        changed = args.output / f'{name}.selected.ps'
        ordered = args.output / f'{name}.ordered.ps'
        assert original.read_bytes() == data
        verify(inkai, args.output, row['before'], expected=counts)
        verify(inkai, args.output, row['after'], expected=(counts[0] + 1, counts[1] + 6, counts[2]))
        verify(inkai, args.output, row['ordered'], expected=(counts[0] + 1, counts[1] + 6, counts[2]))
        assert changed.read_bytes() == expected(data, row)
        assert ordered.read_bytes() == expected(data, row, ordered=True)
        before, after = render(inkai, original, args.output), render(inkai, changed, args.output)
        assert before.size == after.size
        # White-to-cyan removes red only. Unchanged alpha and green/blue prove
        # the printing geometry and opacity were not modified by the attachment.
        for channel in ('A', 'G', 'B'):
            assert ImageChops.difference(before.getchannel(channel), after.getchannel(channel)).getbbox() is None, (name, channel)
        assert ImageChops.subtract(after.getchannel('R'), before.getchannel('R')).getbbox() is None
        difference = ImageChops.subtract(before.getchannel('R'), after.getchannel('R'))
        histogram = difference.histogram()
        changed_pixels = sum(histogram[1:])
        assert sum(histogram[200:]) > 1000, 'The selected fill did not change from white to cyan'
        difference.save(args.output / f'{name}.difference.png')
        above = render(inkai, ordered, args.output)
        assert above.size == before.size
        reference = order_reference(original, args.output)
        assert above.size == reference.size and above.tobytes() == reference.tobytes(), 'Ordered printing differs from the independent SVG composition'
        lighter = ImageChops.subtract(above.getchannel('R'), before.getchannel('R'))
        for channel in ('R', 'G', 'B'):
            assert ImageChops.subtract(before.getchannel(channel), above.getchannel(channel)).getbbox() is None
            assert ImageChops.difference(lighter, ImageChops.subtract(above.getchannel(channel), before.getchannel(channel))).getbbox() is None
        order_pixels = sum(lighter.histogram()[1:])
        assert order_pixels > 500, 'The opaque top fill did not cover the original inside stroke'
        lighter.save(args.output / f'{name}.ordered.difference.png')
        results.append(dict(file=name, changedPixels=changed_pixels, changedBounds=difference.getbbox(), orderChangedPixels=order_pixels, orderChangedBounds=lighter.getbbox(), styles=counts[0] + 1, parts=counts[1] + 6, uses=counts[2], sharedRejection=row['sharedRejection']))
        print(name, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, outcomes=results), indent=2) + '\n')


if __name__ == '__main__':
    main()
