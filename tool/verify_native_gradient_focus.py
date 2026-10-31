#!/usr/bin/env python3
"""Verify global native focus edits and saved PDF appearances independently."""

import argparse
import hashlib
import importlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, FloatObject, NameObject

from verify_native_gradients import gradient_instances
from verify_native_pdf import REVISION, compare, native_programs, render_pdf


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


def reference_pdf(source, target, angle, length):
    """Change only the three shared focal coordinates in Adobe's original PDF."""
    writer = PdfWriter()
    writer.clone_document_from_reader(PdfReader(source))
    seen = set()
    count = 0

    def visit(value):
        nonlocal count
        value = value.get_object()
        if id(value) in seen:
            return
        seen.add(id(value))
        if isinstance(value, dict):
            if '/ShadingType' in value:
                assert value['/ShadingType'] == 3
                assert list(value['/Coords'][2:]) == [0, 0, 0, 1]
                value[NameObject('/Coords')] = ArrayObject([FloatObject(component) for component in (
                    length * math.cos(math.radians(angle)), -length * math.sin(math.radians(angle)), 0, 0, 0, 1,
                )])
                count += 1
            for key, child in value.items():
                if key not in {'/Parent', '/Metadata', '/PieceInfo'}:
                    visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(writer.pages[0])
    assert count == 3
    writer.write(target)


def main():
    """Require pinned source checksums and the independent reader before renders."""
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
    comparisons = []
    # Use the existing radial-fixture tolerance: native rectangle coordinates
    # have more precision than Adobe's PDF outlines. Measure this before editing
    # as well; the shared comparator still requires equal flat pixels and no
    # more than one channel level of difference within smooth gradient fields.
    baseline = compare(render_pdf(args.output / 'baseline.reference.pdf', 1200, 675),
                       render_pdf(args.output / 'baseline.pdf', 1200, 675),
                       args.output / 'baseline.difference.png', 0.1, gradient=True)
    for label, angle, length in [('angled', 37, 0.375), ('centered', 0, 0), ('boundary', -72, 1)]:
        saved = args.output / f'{label}.ai'
        assert native_programs(saved) == [(args.output / f'{label}.ps').read_bytes()]
        reference = args.output / f'{label}.reference.pdf'
        reference_pdf(Path('test/corpus/files/gradient_radial.ai'), reference, angle, length)
        expected = render_pdf(reference, 1200, 675)
        for target in [args.output / f'{label}.pdf', saved]:
            actual = render_pdf(target, 1200, 675)
            difference = compare(expected, actual, target.with_suffix(f'.{target.suffix[1:]}.difference.png'), 0.1, gradient=True)
            comparisons.append({'file': target.name, 'meanChannelDifference': difference})
    result = {'files': len(report), 'printingInstances': total_printing, 'authoringNotes': total_notes, 'baselineMeanChannelDifference': baseline, 'comparisons': comparisons}
    (args.output / 'oracle-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
