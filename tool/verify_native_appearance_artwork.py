#!/usr/bin/env python3
"""Verify ordinary appearance users in complete pinned CC producer files."""

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
from verify_native_appearance_edits import replace_once, string
from verify_native_appearance_graphs import patch
from verify_native_appearances import verify
from verify_native_structure import native_values, parsed
from verify_native_printing import render

PRODUCERS = {
    'stroke_styles.ai': (22, 173, 31),
    'fill_stroke_test_cc.ai': (18, 149, 27),
    'fill_stroke_test.ai': (18, 149, 27),
}
MAGENTA = b'0.0 1.0 0.0 0.0 1.0 0.0 1.0'
STROKE_PREFIXES = ('M 845 1042 L 952 897.775', 'M 1325 1042 L 1432 897.775')
OFFSET_PREFIXES = ('M 1723.48 53.9786 L 1869.83 232', 'M 1723.48 587.979 L 1869.83 766')


def printing_span(data, application):
    """Bind the last complete group before XW6 using this pinned lexical layout."""
    marker = data.rfind(b'6 () XW', 0, application)
    assert marker > data.index(b'%%EndSetup')
    stack, groups = [], []
    # These fixed nonbinary body groups contain only paths and scalar state.
    # The independent parser below additionally checks the selected source group.
    for token in re.finditer(rb'(?<!\S)(\*?u|\*?U)(?!\S)', data[data.index(b'%%EndSetup'):marker]):
        start = data.index(b'%%EndSetup') + token.start()
        end = data.index(b'%%EndSetup') + token.end()
        if token[1] in (b'u', b'*u'):
            stack.append((start, token[1]))
        else:
            first, kind = stack.pop()
            assert kind.upper() == token[1]
            groups.append((first, end))
    assert not stack
    start, end = groups[-1]
    assert data[start:start + 1] == b'u' and data[end - 1:end] == b'U'
    assert b'XW' not in data[end:marker]
    commands = [item for item in native_values(parsed(data[start:end])) if hasattr(item, 'command')]
    assert commands[0].command == 'u' and commands[-1].command == 'U'
    assert all(not item.is_pseudo_comment for item in commands)
    native = data[marker + len(b'6 () XW'):application]
    assert re.search(rb'%_[^\r\n]*\bm(?:\r|\n)', native)
    assert re.search(rb'%_[nN](?:\r|\n)', native)
    assert b'ai::LiveShape' not in native
    return start, end


def expected(data, row):
    """Prescribe every changed byte independently of writer-reported group spans."""
    style = row['before']['styles'][row['style']]
    assert style['uses'] == [row['use']] and row['part'] == 2
    start, end = style['record']
    part = style['parts'][row['part']]
    assert part['kind'] == ('stroke' if row['file'] == 'stroke_styles.ai' else 'strokeOffset')
    paint, = part['paints']
    assignment, = [item for item in paint['assignments'] if item['parameter'] == 'strokeColor']
    first, last = paint['instructions'][assignment['instruction']]['span']
    original_color = data[first:last]
    assert original_color.endswith(b' XA')
    updated_style = replace_once(data[start:end], original_color, MAGENTA + b' XA')
    name = bytes(style['name'])
    updated_style = replace_once(updated_style, b'(' + name + b') /Name', string(b'Magenta stroke') + b' /Name')
    use = row['before']['uses'][row['use']]
    first, last = use['span']
    assert data[first:last] == b'1 (' + name + b') XW'
    group_start, group_end = printing_span(data, first)
    group = data[group_start:group_end]
    printed_color = original_color if part['kind'] == 'stroke' else original_color[:-1] + b'a'
    group = replace_once(group, printed_color, MAGENTA + printed_color[-3:])
    assert group.endswith(b'U')
    group = group[:-1] + printed_color + b'\nU'
    output = patch(data, [(end, end, b'\n' + updated_style + b'\n'), (first, last, b'1 ' + string(b'Magenta stroke') + b' XW'), (group_start, group_end, group)])
    # Existing numeric bounds are unchanged; only integer float spelling differs.
    output, count = re.subn(rb'%%HiResBoundingBox: ([^\r\n]+)', lambda match: b'%%HiResBoundingBox: ' + b' '.join(str(float(value)).encode() for value in match[1].split()), output)
    assert count == 1
    return output


def reference(original, output, name, user):
    """Recolor only the independently identified original SVG stroke geometry."""
    tree = etree.parse(output / f'{original.name}.svg')
    centered = name == 'stroke_styles.ai'
    prefix = (STROKE_PREFIXES if centered else OFFSET_PREFIXES)[user]
    old = 'stroke:#00ffff' if centered else 'fill:#000000'
    new = 'stroke:#ff00ff' if centered else 'fill:#ff00ff'
    path, = [item for item in tree.xpath('//*[local-name()="path"]') if item.get('d', '').startswith(prefix) and old in item.get('style', '')]
    path.set('style', path.get('style').replace(old, new))
    svg = output / f'{name}.{user}.reference.svg'
    png = svg.with_suffix('.png')
    svg.write_bytes(etree.tostring(tree))
    subprocess.run(['inkscape', str(svg), '--export-type=png', '--export-width=1200', f'--export-filename={png}'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with Image.open(png) as image:
        return image.convert('RGBA')


def main():
    """Require six complete transactions, byte oracles and matching supplied ink."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/appearance-artwork'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {item['file']: item for item in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 6 and {(row['file'], row['user']) for row in rows} == {(name, index) for name in PRODUCERS for index in (0, 1)}
    originals, results = {}, []
    for row in rows:
        name, user = row['file'], row['user']
        entry = manifest[name]
        fixture = Path('test/corpus/files', name)
        raw = fixture.read_bytes()
        assert len(raw) == entry['size'] and hashlib.sha256(raw).hexdigest() == entry['sha256']
        if raw.startswith(b'%PDF-'):
            data, = native_programs(fixture)
        else:
            data = raw
        assert entry['revision'] == REVISION and entry['license']
        original = args.output / f'{row["before"]["source"]}.ps'
        changed = args.output / f'{row["selected"]["source"]}.ps'
        assert original.read_bytes() == data
        counts = PRODUCERS[name]
        if name not in originals:
            verify(inkai, args.output, row['before'], expected=counts)
            originals[name] = render(inkai, original, args.output)
        verify(inkai, args.output, row['selected'], expected=(counts[0] + 1, counts[1] + 6, counts[2]))
        assert changed.read_bytes() == expected(data, row), (name, user, 'complete byte delta')
        assert row['shared'] is None
        expected_rejection = 'Native transformation requires a supported appearance style.' if name == 'stroke_styles.ai' else 'Reference qualification does not cover Dictionary/GenAIRecorded (null).'
        assert row['sharedRejection'] == expected_rejection
        before, after = originals[name], render(inkai, changed, args.output)
        oracle = reference(original, args.output, name, user)
        assert after.size == before.size == oracle.size
        assert all(ImageChops.difference(after.getchannel(channel), oracle.getchannel(channel)).getbbox() is None for channel in 'RGBA'), (name, user, 'supplied stroke pixels')
        assert ImageChops.difference(before.getchannel('A'), after.getchannel('A')).getbbox() is None
        changed_pixels = sum(first != second for first, second in zip(before.getdata(), after.getdata(), strict=True))
        assert changed_pixels > 1000, (name, user, 'empty stroke change')
        results.append(dict(file=name, user=user, changedPixels=changed_pixels, byteDelta='exact', referencePixels='exact', shared='explicit rejection'))
        print(name, user, changed_pixels, 'pixels; exact source delta and independent reference', flush=True)
    (args.output / 'verification.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
