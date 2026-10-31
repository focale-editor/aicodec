#!/usr/bin/env python3
"""Qualify named-ink component order against the fixture's original PDF shading."""

import hashlib
import json
import math
import struct

from pypdf import PdfReader

from verify_native_meshes import CORPUS, OUTPUT


def pdf_patches(path):
    """Read this pinned Illustrator type-seven stream, without a native parser."""
    page = PdfReader(path).pages[0]
    assert list(page.mediabox) == [0, 0, 822, 519]
    shading = page['/Resources']['/Shading']['/Sh0']
    assert [shading[key] for key in ['/ShadingType', '/BitsPerCoordinate', '/BitsPerComponent', '/BitsPerFlag']] == [7, 32, 8, 8]
    assert shading['/ColorSpace'][0] == '/ICCBased'
    assert shading['/ColorSpace'][1].get_object()['/N'] == 4
    # The page paints Sh0 through a y reflection; the native drawing origin is
    # one page-height below the PDF origin. Check that source placement too.
    operations = page.get_contents().operations
    calls = [index for index, (values, operator) in enumerate(operations) if operator == b'sh' and values == ['/Sh0']]
    assert len(calls) == 1
    assert operations[calls[0] - 2] == ([1, 0, 0, -1, 0, 0], b'cm')
    assert operations[calls[0] - 1] == ([], b'BX')
    decode = list(map(float, shading['/Decode']))
    assert len(decode) == 12 and decode[4:] == [0, 1] * 4
    data = shading.get_data()
    assert len(data) == 1747 * 145
    patches = []
    for offset in range(0, len(data), 145):
        assert data[offset] == 0  # The fixture stores complete patches only.
        coordinates = struct.unpack_from('>32I', data, offset + 1)
        points = [(decode[0] + coordinates[index] / 0xffffffff * (decode[1] - decode[0]),
                   -decode[2] - coordinates[index + 1] / 0xffffffff * (decode[3] - decode[2]) - 519)
                  for index in range(0, 32, 2)]
        components = data[offset + 129:offset + 145]
        colors = [[value / 255 for value in components[index * 4:index * 4 + 4]] for index in range(4)]
        patches.append({'points': points, 'colors': colors})
    return patches


def pdf_corners(path):
    """Expose all corner samples without inferring any native patch mapping."""
    return [(patch['points'][index * 3], patch['colors'][index])
            for patch in pdf_patches(path) for index in range(4)]


def main():
    """Require all 46 named-ink corners to agree with Adobe's stored CMYK view."""
    rows = json.loads((OUTPUT / 'report.json').read_text())
    manifest = json.loads((CORPUS / 'mesh_manifest.json').read_text())
    assert [row['file'] for row in rows] == [entry['file'] for entry in manifest['files']]
    report = []
    process = {b'Cyan': [1, 0, 0, 0], b'Magenta': [0, 1, 0, 0], b'Yellow': [0, 0, 1, 0], b'Black': [0, 0, 0, 1]}
    for row, entry in zip(rows, manifest['files']):
        path = CORPUS / 'files' / row['file']
        raw = path.read_bytes()
        assert len(raw) == entry['size'] and hashlib.sha256(raw).hexdigest() == entry['sha256']
        samples = pdf_corners(path)
        count, position_error, color_error = 0, 0, 0
        for mesh in row['meshes']:
            for patch in mesh['patches']:
                for node in patch['nodes']:
                    if not node['inks']:
                        assert not node['inkTints']
                        continue
                    expected = [0, 0, 0, 0]
                    for component, ink in zip(node['inkTints'], reversed(node['inks']), strict=True):
                        name = bytes(component['name'])
                        assert name == bytes(ink['name'])
                        assert ink['deviceName'] == 'DeviceCMYK' and ink['components'] == process[name]
                        expected = [value + component['tint'] * weight for value, weight in zip(expected, process[name])]
                    distance, (_, actual) = min((math.dist(node['position'], point), (point, color)) for point, color in samples)
                    error = max(abs(first - second) for first, second in zip(expected, actual))
                    # Source coordinates and components have 32-bit and 8-bit
                    # PDF quantization respectively, not native float precision.
                    assert distance < 0.001 and error <= 0.5 / 255 + 1e-7, (patch['position'], distance, error)
                    position_error, color_error = max(position_error, distance), max(color_error, error)
                    count += 1
        assert count == 46
        report.append({'file': row['file'], 'namedInkCorners': count, 'maximumPositionError': position_error,
                       'maximumComponentError': color_error, 'status': 'passed'})
    (OUTPUT / 'ink-order-oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
