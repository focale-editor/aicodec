#!/usr/bin/env python3
"""Compare complete CC compound-gradient saves with original Adobe PDF artwork."""

import argparse
import importlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

from verify_native_gradients import stops, verify_geometry
from verify_native_pdf import REVISION, compare, native_programs, recolor_original, render_pdf


def check_probes(output):
    """Require actual holes, one object-alpha application and restored stroke clips."""
    path = render_pdf(output / 'compound-probes.pdf', 2400, 720)
    samples = [
        (50, 50, (0, 0, 255)),  # Same-winding contours use the even-odd hole.
        (20, 50, (223, 223, 223)),
        (150, 50, (255, 255, 255)),  # Opposite winding keeps the nonzero hole.
        (120, 50, (239, 239, 239)),  # Whole compound opacity, exactly once.
        (250, 50, (255, 255, 255)),
        (220, 50, (247, 247, 247)),  # Stop opacity multiplied by object opacity.
        (207, 50, (128, 128, 255)),  # Solid stroke outside the gradient fill clip.
        (350, 50, (255, 0, 0)),  # A state-only gradient note cannot paint the next path.
    ]
    with Image.open(path) as image:
        for x, y, expected in samples:
            actual = image.getpixel((x * 6, (120 - y) * 6))
            assert max(abs(first - second) for first, second in zip(actual, expected)) <= 1, (x, y, expected, actual)
    return len(samples)


def main():
    """Require all fixtures, retained native owners and independently edited fields."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/native-pdf-compounds'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    gradient = importlib.import_module('inkai.parser.gradient')
    report = json.loads((args.output / 'report.json').read_text())
    assert {row['file']: row['status'] for row in report} == {
        'gradient_linear_random_test.ai': 'accepted',
        'gradient_radial_random_test.ai': 'accepted',
        'styles.ai': 'accepted',
    }
    results = []
    owners = 0
    for row in report:
        name = row['file']
        assert row['compounds'] == 1 and len(row['gradientResources']) == (2 if name == 'styles.ai' else 6)
        assert row['printedGradients'] == {'gradient_linear_random_test.ai': 7, 'gradient_radial_random_test.ai': 8, 'styles.ai': 3}[name]
        assert row['gradientStrokes'] == (1 if name == 'styles.ai' else 0)
        before = inkai.parse(str(args.output / f'{name}.native.ps'))
        after = inkai.parse(str(args.output / f'{name}.colors.ps'))
        first, second = before.setup.gradients, after.setup.gradients
        assert first.keys() == second.keys()
        for key in first:
            if key not in row['gradientResources']:
                assert repr(first[key].children) == repr(second[key].children), (name, key)
                continue
            actual = stops(second[key], gradient.Bs, 'Bs')
            radial = second[key].definition.type == 1
            assert [stop['position'] for stop in actual] == ([0, 40, 100] if radial else [100, 40, 0])
            assert [stop['opacity'] for stop in actual] == [1, 0.4, 1]
            for primary, stop in zip([0, 1, 2] if radial else [2, 1, 0], actual):
                assert stop['style'] == 2 and stop['components'][4:] == [1 if channel == primary else 0 for channel in range(3)]
                assert stop['midpoint'] == 50
            original_stops = stops(first[key], gradient.Bs, 'Bs')
            verify_geometry(before, after, key, radial, sorted(stop['position'] / 100 for stop in original_stops), [0, 0.4, 1], row['gradientResources'])
        recolor_original(args.output / f'{name}.original.pdf', args.output / f'{name}.expected-colors.pdf')
        for label, source in [('rebuilt', 'native'), ('colors', 'colors')]:
            saved = args.output / f'{name}.{label}.ai'
            programs = native_programs(saved)
            assert all(program == (args.output / f'{name}.{source}.ps').read_bytes() for program in programs)
            owners += len(programs)
            expected = render_pdf(args.output / f'{name}.{"original" if label == "rebuilt" else "expected-colors"}.pdf', 1920, 1080)
            actual = render_pdf(saved, 1920, 1080)
            difference = compare(expected, actual, args.output / f'{name}.{label}.difference.png', 0.02, True)
            results.append({'file': name, 'variant': label, 'meanChannelDifference': difference})
            print(f'{name} {label}: mean channel difference {difference}')
    assert owners == 6 and len(results) == 6
    probes = check_probes(args.output)
    poppler = subprocess.run(['pdftoppm', '-v'], check=True, capture_output=True, text=True).stderr.splitlines()[0]
    result = {'oracleRevision': REVISION, 'poppler': poppler, 'nativeOwners': owners, 'compositionProbes': probes, 'renders': results}
    (args.output / 'independent-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('Complete compound/stroke-gradient drawings: 6/6 comparisons, 6/6 native owners and 8 pixel probes passed')


if __name__ == '__main__':
    main()
