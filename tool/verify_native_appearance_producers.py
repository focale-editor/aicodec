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

from PIL import ImageChops

from corpus_support import REVISION
from verify_native_appearance_edits import replace_once, string
from verify_native_appearances import verify
from verify_native_printing import render

PRODUCERS = {'simple_shapes.ai': (17, 143, 26), 'simple_shapes_cc.ai': (18, 149, 26)}
WHITE = b'0 0 0 0 1 1 1 Xa'
CYAN = b'1.0 0.0 0.0 0.0 0.0 1.0 1.0 Xa'


def expected(data, row):
    """Specify exact changes after independently binding all inventory spans."""
    assert row['selectedShapes'] == [0] and row['style'] == 9 and row['part'] == 4
    style = row['before']['styles'][9]
    assert bytes(style['name']) == b'Anon amY4LCj5JfA=' and style['uses'] == [21]
    start, end = style['record']
    copy = replace_once(data[start:end], b'(Anon amY4LCj5JfA=) /Name', string(b'Selected cyan') + b' /Name')
    copy = replace_once(copy, WHITE, CYAN)
    use = row['before']['uses'][21]
    old = b'1 (Anon amY4LCj5JfA=) XW'
    assert data[slice(*use['span'])] == old
    assert data.count(b'%%EndSetup') == 1
    body = data.index(b'%%EndSetup') + len(b'%%EndSetup')
    foreground = data[body:use['span'][0]]
    assert foreground.count(WHITE) == 1
    color = body + foreground.index(WHITE)
    edits = [(end, end, b'\n' + copy + b'\n'), (color, color + len(WHITE), CYAN), (*use['span'], b'1 ' + string(b'Selected cyan') + b' XW')]
    for start, end, value in sorted(edits, reverse=True):
        data = data[:start] + value + data[end:]
    # The bounds writer retains the same values with its canonical float spelling.
    data, count = re.subn(rb'(?m)^(%%HiResBoundingBox:[^\r\n]*) -149(?=\r?$)', rb'\1 -149.0', data)
    assert count == 1
    return data


def main():
    """Require both pinned producers, full byte preservation and actual cyan ink."""
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
        assert original.read_bytes() == data
        verify(inkai, args.output, row['before'], expected=counts)
        verify(inkai, args.output, row['after'], expected=(counts[0] + 1, counts[1] + 6, counts[2]))
        assert changed.read_bytes() == expected(data, row)
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
        results.append(dict(file=name, changedPixels=changed_pixels, changedBounds=difference.getbbox(), styles=counts[0] + 1, parts=counts[1] + 6, uses=counts[2], sharedRejection=row['sharedRejection']))
        print(name, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, outcomes=results), indent=2) + '\n')


if __name__ == '__main__':
    main()
