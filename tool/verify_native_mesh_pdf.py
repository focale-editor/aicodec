#!/usr/bin/env python3
"""Compare native mesh excerpts with independent Adobe-geometry references."""

import copy
import hashlib
import json
import subprocess

import numpy as np
from PIL import Image
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ArrayObject, BooleanObject, DecodedStreamObject, DictionaryObject, FloatObject, NameObject, NumberObject

from verify_native_meshes import CORPUS, OUTPUT, native_program
from verify_native_mesh_paint import mesh_records
from verify_native_mesh_inks import pdf_patches
from verify_native_mesh_interpolation import ORDER, corners, field, restrict, sample_color


DESTINATION = CORPUS / 'output/mesh-pdf'


def verify_edits(original, variant):
    """Require every geometry token, unselected color and surrounding byte intact."""
    packet, fields, colors = mesh_records(original)
    changed = (DESTINATION / f'{variant}.ps').read_bytes()
    after_packet, after_fields, after_colors = mesh_records(changed)
    assert original[:packet.start()] == changed[:after_packet.start()]
    assert original[packet.end():] == changed[after_packet.end():]
    assert fields == after_fields and len(colors) == len(after_colors) == 720
    updated = 0
    for before, after in zip(colors, after_colors):
        expected = dict(before)
        if variant == 'opacity':
            expected['opacity'] = 0.5
            updated += 1
        elif before['vertex'] == (5, 5):
            expected.update(space='/DeviceCMYK', color=[0.9, 0.1, 0.1, 0], inks=[])
            updated += 1
        assert after == expected
    assert updated == (720 if variant == 'opacity' else 4)


def reference(reader, variant, mesh, mapping, patches):
    """Keep Adobe geometry; recolor a dense independent subdivision after editing."""
    writer = PdfWriter()
    page = writer.add_blank_page(822, 519)
    original = reader.pages[0]['/Resources']['/Shading']['/Sh0']
    shade = original.clone(writer)
    placement = b'1 0 0 -1 0 0 cm'
    if variant == 'painted':
        edited = copy.deepcopy(mesh)
        for patch in edited['patches']:
            for key, node in zip(corners(patch['position']), [node for node in patch['nodes'] if node['kind'] == 'corner']):
                if key == (5, 5):
                    node.update(deviceName='DeviceCMYK', color=[0.9, 0.1, 0.1, 0], inks=[], inkTints=[])
        colors = field(edited)
        # Eight fixed subdivisions of each original Adobe PDF patch give a
        # reference independent of AiKit's adaptive refinement and controls.
        count = 8
        reductions = np.array([restrict(index / count, (index + 1) / count) for index in range(count)])
        all_points = np.array([patch['points'] for patch in patches])
        origin = all_points.min(axis=(0, 1))
        span = all_points.max(axis=(0, 1)) - origin
        data = bytearray()
        parameters = np.array([(first / count, second / count) for first in range(count + 1) for second in range(count + 1)])
        for patch, match in zip(patches, mapping):
            grid = np.zeros((4, 4, 2))
            for indices, point in zip(ORDER, patch['points']):
                grid[indices] = point
            geometry = np.einsum('sai,ijc,tbj->stabc', reductions, grid, reductions)
            native = np.array(match['parameters'])
            positions = native[0] + parameters[:, :1] * (native[1] - native[0]) + parameters[:, 1:] * (native[3] - native[0])
            samples = sample_color(colors, match['nativeCell'], positions[:, :1], positions[:, 1:]).reshape(count + 1, count + 1, 4)
            for second in range(count):
                for first in range(count):
                    controls = np.array([geometry[first, second][key] for key in ORDER])
                    components = samples[first:first + 2, second:second + 2][[0, 1, 1, 0], [0, 0, 1, 1]]
                    data.extend(b'\0')
                    data.extend(np.rint((controls - origin) / span * 4294967295).astype('>u4').tobytes())
                    data.extend(np.rint(components * 65535).astype('>u2').tobytes())
        shade = DecodedStreamObject()
        shade.set_data(bytes(data))
        shade.update({NameObject('/ShadingType'): NumberObject(7), NameObject('/ColorSpace'): original['/ColorSpace'].clone(writer),
                      NameObject('/BitsPerCoordinate'): NumberObject(32), NameObject('/BitsPerComponent'): NumberObject(16),
                      NameObject('/BitsPerFlag'): NumberObject(8),
                      NameObject('/Decode'): ArrayObject([FloatObject(value) for value in [origin[0], origin[0] + span[0], origin[1], origin[1] + span[1], *([0, 1] * 4)]])})
        shade = shade.flate_encode()
        placement = b'1 0 0 1 0 519 cm'
    resources = DictionaryObject({NameObject('/Shading'): DictionaryObject({NameObject('/Mesh'): writer._add_object(shade)})})
    content = DecodedStreamObject()
    if variant == 'opacity':
        form = DecodedStreamObject()
        form.set_data(b'q ' + placement + b' /Mesh sh Q')
        form.update({NameObject('/Type'): NameObject('/XObject'), NameObject('/Subtype'): NameObject('/Form'),
                     NameObject('/BBox'): ArrayObject([NumberObject(value) for value in [0, 0, 822, 519]]),
                     NameObject('/Resources'): resources,
                     NameObject('/Group'): DictionaryObject({NameObject('/S'): NameObject('/Transparency'), NameObject('/I'): BooleanObject(True)})})
        page[NameObject('/Resources')] = DictionaryObject({
            NameObject('/XObject'): DictionaryObject({NameObject('/Opaque'): writer._add_object(form)}),
            NameObject('/ExtGState'): DictionaryObject({NameObject('/Alpha'): DictionaryObject({NameObject('/ca'): FloatObject(0.5)})}),
        })
        content.set_data(b'q /Alpha gs /Opaque Do Q')
    else:
        page[NameObject('/Resources')] = resources
        content.set_data(b'q ' + placement + b' /Mesh sh Q')
    page[NameObject('/Contents')] = writer._add_object(content)
    with (DESTINATION / f'{variant}.reference.pdf').open('wb') as output:
        writer.write(output)


def compare(variant):
    """Render with Poppler and measure the complete page and painted pixels."""
    for suffix in ['', '.reference']:
        name = variant + suffix
        subprocess.run(['pdftoppm', '-r', '144', '-singlefile', '-png', str(DESTINATION / f'{name}.pdf'), str(DESTINATION / name)], check=True, capture_output=True)
    actual = np.array(Image.open(DESTINATION / f'{variant}.png'), dtype=float)
    expected = np.array(Image.open(DESTINATION / f'{variant}.reference.png'), dtype=float)
    assert actual.shape == expected.shape == (1038, 1644, 3)
    difference = abs(actual - expected)
    ink = np.any(expected < 250, axis=2)
    assert ink.sum() > 190000 and np.all(np.isfinite(difference))
    result = {'variant': variant, 'pageMean': float(difference.mean()), 'paintedMean': float(difference[ink].mean()),
              'maximum': float(difference.max()), 'paintedPixels': int(ink.sum()),
              'percentile99': float(np.quantile(difference[ink].max(axis=1), 0.99)), 'status': 'passed'}
    assert result['pageMean'] < 0.075 and result['paintedMean'] < 0.6 and result['percentile99'] <= 6, result
    return result


def main():
    """Require the pinned source, exact native edits and three rendered probes."""
    manifest = json.loads((CORPUS / 'mesh_manifest.json').read_text())['files']
    assert len(manifest) == 1
    entry = manifest[0]
    source = CORPUS / 'files' / entry['file']
    data = source.read_bytes()
    assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
    original = native_program(source)
    for variant in ['painted', 'opacity']:
        verify_edits(original, variant)
    row = json.loads((OUTPUT / 'report.json').read_text())[0]
    oracle = json.loads((OUTPUT / 'interpolation-oracle-report.json').read_text())[0]
    assert row['file'] == oracle['file'] == entry['file'] and len(row['meshes']) == 1
    mapping = oracle['matches']
    assert [match['pdfPatch'] for match in mapping] == list(range(1747))
    patches = pdf_patches(source)
    reader = PdfReader(source)
    results = []
    for variant in ['mesh', 'painted', 'opacity']:
        reference(reader, variant, row['meshes'][0], mapping, patches)
        result = compare(variant)
        results.append(result)
        print(json.dumps(result), flush=True)
    (DESTINATION / 'render-oracle-report.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
