#!/usr/bin/env python3
"""Verify isolated native paint, restored state and retained producer text."""

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

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_appearance_edits import GROUP, replace_once, string
from verify_native_appearance_graphs import patch
from verify_native_appearances import parts, verify
from verify_native_artboard_text import text_state
from verify_native_printing import render
from verify_native_structure import parsed

SYNTHETIC = {
    'live': '4ea757f61664812ec5c86e5e7752744a9356202aee8e2aa6d586869c15265e2a',
    'ordinary': 'f6a19df5bb9a28706ef3bf37091959f245061998b82b7c4d16ff2b2a3cc3e665',
}
PRODUCERS = ('simple_cc_legacy.ai', 'simple_v2020.ai')
WHITE = b'0 0 0 0 1 1 1 Xa'
CYAN = b'1.0 0.0 0.0 0.0 0.0 1.0 1.0 Xa'


def expected(data, row, producer):
    """Prescribe the entire byte delta, including a separate private state replay."""
    style = row['styles'][6 if producer else 0]
    assert style['uses'] == ([21] if producer else [0, 1])
    assert bytes(style['name']) == (b'Anon PcbI2auHRLE=' if producer else b'Shared')
    start, end = style['record']
    declaration, = parsed(data[start:end])
    paints = []
    for part, _, _ in parts(declaration.Def.Execution):
        assert part.Visible == 1
        fill = (getattr(part, 'Dict', None) or {}).get('FillStyle')
        if fill is not None:
            commands = [item for item in fill.Def if item.command in ('g', 'k', 'Xa')]
            assert len(commands) == 1
            paints.extend(commands)
    assert len(paints) == 1
    color = WHITE if producer else b'0.1 0.2 0.3 Xa'
    replacement = CYAN if producer else b'0.7 0.6 0.5 Xa'
    command, = parsed(color)
    assert paints[0].command == command.command and paints[0].tokens == command.tokens
    copied = replace_once(data[start:end], color, replacement)
    copied = replace_once(copied, b'(' + bytes(style['name']) + b') /Name', string(b'Selected state') + b' /Name')
    use = row['uses'][21 if producer else 1]
    first, last = use['span']
    assert data[first:last] == b'1 (' + bytes(style['name']) + b') XW'
    edits = [(end, end, b'\n' + copied + b'\n'), (first, last, b'1 ' + string(b'Selected state') + b' XW'), (last, last, b'\n%_' + color + b'\n')]
    if producer:
        assert style['parts'][4]['kind'] == 'fill'
        body = data.index(b'%%EndSetup') + len(b'%%EndSetup')
        foreground = data[body:first]
        assert foreground.count(WHITE) == 1
        position = body + foreground.index(WHITE)
        edits.append((position, position + len(WHITE), CYAN))
    else:
        groups = list(re.finditer(rb'(?ms)^u\n.*?\nU$', data))
        assert len(groups) == 2
        edits.append((*groups[1].span(), GROUP))
    result = patch(data, edits)
    if producer:
        return replace_once(result, b'%%HiResBoundingBox: 595.375 -789 1443.8515625 -219.45556640625', b'%%HiResBoundingBox: 595.375 -789.0 1443.8515625 -219.45556640625')
    return replace_once(result, b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def restored(document, producer):
    """Bind the native-only assignment directly to its unchanged following owner."""
    body = list(walk_body(document.trailer))
    uses = [index for index, item in enumerate(body) if getattr(item, 'command', None) == 'XW' and item.tokens == [b'1', b'Selected state']]
    index, = uses
    replay = body[index + 1]
    assert replay.command == 'Xa' and replay.is_pseudo_comment
    assert list(map(float, replay.tokens)) == ([0, 0, 0, 0, 1, 1, 1] if producer else [0.1, 0.2, 0.3])
    if producer:
        assert type(body[index + 2]).__name__ == 'AI11Text'
    # The synthetic opaque owner is deliberately outside this reader's grammar;
    # its complete bytes are retained by the independent full-source oracle.


def reference(original, output):
    """Recolor the original printing rectangle with a separately composed SVG."""
    tree = etree.parse(output / f'{original.name}.svg')
    path, = tree.xpath('//*[local-name()="path" and @d="M 680.5 788.5 L 680.5 419.5 L 1378.5 419.5 L 1378.5 788.5 L 680.5 788.5 Z"]')
    assert 'fill:#ffffff' in path.get('style')
    path.set('style', path.get('style').replace('fill:#ffffff', 'fill:#00ffff'))
    svg = output / f'{original.name}.reference.svg'
    png = svg.with_suffix('.png')
    svg.write_bytes(etree.tostring(tree))
    subprocess.run(['inkscape', str(svg), '--export-type=png', '--export-width=1200', f'--export-filename={png}'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with Image.open(png) as image:
        return image.convert('RGBA')


def main():
    """Require complete source, text, native state and supplied printing evidence."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/appearance-state'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    text_parser = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    inventory = {row['source']: row for row in rows}
    assert len(rows) == 8 and set(inventory) == {f'{name}.{phase}' for name in (*SYNTHETIC, *PRODUCERS) for phase in ('before', 'after')}
    results = []
    for name in (*SYNTHETIC, *PRODUCERS):
        original, changed = [args.output / f'{name}.{phase}.ps' for phase in ('before', 'after')]
        data, after = original.read_bytes(), changed.read_bytes()
        producer = name in PRODUCERS
        if producer:
            entry = manifest[name]
            fixture = Path('test/corpus/files', name)
            raw = fixture.read_bytes()
            assert len(raw) == entry['size'] and hashlib.sha256(raw).hexdigest() == entry['sha256']
            assert entry['revision'] == REVISION and entry['license']
            assert native_programs(fixture) == [data]
        else:
            assert hashlib.sha256(data).hexdigest() == SYNTHETIC[name]
        verify(inkai, args.output, inventory[f'{name}.before'], expected=(13, 119, 22) if producer else (1, 2, 2))
        verify(inkai, args.output, inventory[f'{name}.after'], expected=(14, 125, 22) if producer else (2, 4, 2))
        assert after == expected(data, inventory[f'{name}.before'], producer), name
        before_doc, after_doc = inkai.parse(str(original)), inkai.parse(str(changed))
        restored(after_doc, producer)
        row = dict(source=name, byteDelta='exact', nativeState='restored')
        if producer:
            text = text_state(before_doc, text_parser, stream)
            assert text == text_state(after_doc, text_parser, stream)
            assert text['counts'] == [1, 1, 1]
            before_image, after_image = render(inkai, original, args.output), render(inkai, changed, args.output)
            assert after_image.tobytes() == reference(original, args.output).tobytes()
            assert before_image.getchannel('A').tobytes() == after_image.getchannel('A').tobytes()
            difference = ImageChops.difference(before_image, after_image)
            count = sum(pixel != (0, 0, 0, 0) for pixel in difference.getdata())
            assert count > 0
            row.update(textCounts=text['counts'], changedPixels=count, referencePixels='exact')
        results.append(row)
        print(name, row, flush=True)
    (args.output / 'verification.json').write_text(json.dumps(dict(oracleRevision=REVISION, outcomes=results), indent=2) + '\n')


if __name__ == '__main__':
    main()
