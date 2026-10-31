#!/usr/bin/env python3
"""Verify global native focus edits independently."""

import argparse
import hashlib
import importlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path


from verify_native_gradients import gradient_instances
from corpus_support import REVISION


def verify_instances(inkai, original, changed, names, angle, length):
    """Check parsed focus vectors while requiring every other command unchanged."""
    before = gradient_instances(inkai.parse(str(original)))
    after = gradient_instances(inkai.parse(str(changed)))
    assert len(before) == len(after)
    printing = notes = 0
    for first, second in zip(before, after):
        geometry = next(command for command in first if command.command == 'Bg')
        if geometry.name not in names:
            assert repr(first) == repr(second)
            continue
        assert repr([command for command in first if command.command != 'Bh']) == repr([command for command in second if command.command != 'Bh'])
        highlight = [command for command in second if command.command == 'Bh']
        assert len(highlight) == 1
        x, y, actual_angle, actual_length = map(float, highlight[0].tokens)
        assert actual_angle == angle and actual_length == length
        matrices = [command for command in first if command.command == 'Bm']
        if matrices:
            assert len(matrices) == 1
            a, b, c, d, _, _ = map(float, matrices[0].tokens)
            u = length * math.cos(math.radians(angle))
            v = -length * math.sin(math.radians(angle))
            expected = (a * u + c * v, b * u + d * v)
            printing += 1
        else:
            expected = (0, 0)
            notes += 1
        assert all(math.isclose(value, wanted, abs_tol=1e-8, rel_tol=1e-10) for value, wanted in zip((x, y), expected))
    # These pinned programs already contain a Bh for each radial instance.
    # Removing only its four numeric operands leaves the exact source bytes.
    pattern = rb'(?m)(?<=\n)((?:%_)?)[ \t]*[-+0-9.eE]+[ \t]+[-+0-9.eE]+[ \t]+[-+0-9.eE]+[ \t]+[-+0-9.eE]+(?= Bh)'
    assert re.sub(pattern, rb'\1FOCUS', original.read_bytes()) == re.sub(pattern, rb'\1FOCUS', changed.read_bytes())
    return printing, notes


def main():
    """Require pinned source checksums and independent native focus decoding."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/gradient-focus'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    report = json.loads((args.output / 'report.json').read_text())
    assert len(report) == len(manifest) == 37
    total_printing = total_notes = 0
    for entry, fixture in zip(report, manifest):
        name = entry['file']
        assert name == fixture['file']
        assert hashlib.sha256(Path('test/corpus/files', name).read_bytes()).hexdigest() == fixture['sha256']
        printing, notes = verify_instances(inkai, args.output / f'{name}.original.ps', args.output / f'{name}.edited.ps', entry['names'], entry['angle'], entry['length'])
        total_printing += printing
        total_notes += notes
    result = {'files': len(report), 'printingInstances': total_printing, 'authoringNotes': total_notes}
    (args.output / 'oracle-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
