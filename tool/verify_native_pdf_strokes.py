#!/usr/bin/env python3
"""Check stroke geometry, opacity and page placement independently with Poppler."""

import argparse
import json
import subprocess
from pathlib import Path

from PIL import Image, ImageChops
from pypdf import PdfReader

from verify_native_pdf import native_programs, render_pdf


def main():
    """Require visible stroke semantics and exact placement on two shifted pages."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=Path('test/corpus/output/native-pdf-strokes'), type=Path)
    args = parser.parse_args()
    samples = [
        (20, 40, 223), (50, 40, 128), (80, 40, 32),  # Linear field on an open stroke.
        (93, 40, 255),  # Butt cap ends at the path endpoint.
        (115, 40, 239), (125, 40, 255), (135, 40, 175),  # Dashes keep their gaps.
        (294, 40, 0), (298, 40, 255),  # Round cap extends beyond the endpoint.
        (350, 100, 128),  # Cubic centerline, without flattening to a polygon.
        (50, 150, 223),  # Half stop opacity times half object opacity.
        (150, 150, 191),  # Half group opacity, once.
        (250, 170, 128), (240, 170, 255),  # BB closes the stroke without filling it.
        (350, 150, 255), (370, 150, 128), (330, 150, 128), (385, 150, 32),  # Radial field.
    ]
    scale = 6
    standalone = render_pdf(args.output / 'probes.pdf', 400 * scale, 240 * scale)
    with Image.open(standalone) as image:
        expected = image.convert('RGB')
        for x, y, gray in samples:
            actual = expected.getpixel((x * scale, (240 - y) * scale))
            assert max(abs(channel - gray) for channel in actual) <= 1, (x, y, gray, actual)
    multiple = args.output / 'probes.multi.ai'
    assert native_programs(multiple) == [(args.output / 'probes.native.ps').read_bytes()]
    reader = PdfReader(multiple)
    assert [list(page['/MediaBox']) for page in reader.pages] == [[20, -30, 420, 210], [-15, 40, 385, 280]]
    first = render_pdf(multiple, 400 * scale, 240 * scale)
    with Image.open(first) as image:
        assert ImageChops.difference(expected, image.convert('RGB')).getbbox() is None
    destination = args.output / 'probes.page2'
    process = subprocess.run(['pdftoppm', '-f', '2', '-l', '2', '-singlefile', '-png', '-scale-to-x', str(400 * scale), '-scale-to-y', str(240 * scale), str(multiple), str(destination)], check=True, capture_output=True, text=True)
    assert 'Syntax Error' not in process.stderr, process.stderr
    shifted = Image.new('RGB', expected.size, 'white')
    shifted.paste(expected.crop((100 * scale, 0, 400 * scale, 240 * scale)), (0, 0))
    with Image.open(destination.with_suffix('.page2.png')) as image:
        difference = ImageChops.difference(shifted, image.convert('RGB'))
        difference.save(args.output / 'probes.page2.difference.png')
        assert difference.getbbox() is None, 'Pattern and path must move together on the second page'
    result = {
        'poppler': subprocess.run(['pdftoppm', '-v'], check=True, capture_output=True, text=True).stderr.splitlines()[0],
        'pixelProbes': len(samples),
        'exactPageComparisons': 2,
        'nativeOwners': 1,
    }
    (args.output / 'independent-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Gradient strokes: {len(samples)} pixel probes, 2 exact page comparisons and 1 native owner passed')


if __name__ == '__main__':
    main()
