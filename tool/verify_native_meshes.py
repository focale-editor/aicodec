#!/usr/bin/env python3
"""Compare the mesh inventory with independently extracted, pinned CC records."""

import hashlib
import json
import re
import zlib
from collections import Counter
from pathlib import Path

from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / 'test/corpus'
OUTPUT = CORPUS / 'output/meshes'


def native_program(path):
    """Read this fixture's thumbnail followed by its numbered zlib program."""
    document = PdfReader(path)
    owners = [owner for owner in [document.trailer['/Root'], *document.pages]
              if '/PieceInfo' in owner and '/Illustrator' in owner['/PieceInfo']]
    assert len(owners) == 1
    private = owners[0]['/PieceInfo']['/Illustrator']['/Private']
    count = int(private['/NumBlock'])
    blocks = [private[f'/AIPrivateData{index}'].get_object().get_data()
              for index in range(1, count + 1)]
    assert blocks[0].startswith(b'%%BoundingBox:')
    assert blocks[1].startswith(b'%AI12_CompressedData')
    decoder = zlib.decompressobj()
    data = decoder.decompress(b''.join(blocks[1:])[20:], 128 * 1024 * 1024)
    assert decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
    assert data.startswith(b'%!PS-Adobe-')
    assert any(shading.get_object()['/ShadingType'] == 7
               for shading in document.pages[0]['/Resources']['/Shading'].values())
    return data


def tokens(value):
    """Tokenize the fixture's restricted mesh values, including ink names."""
    expression = re.compile(r'\s*(\[[ ]*|\]|\([^()\\]*\)|/[^\s\[\]()]+|[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)')
    output = []
    position = 0
    while value[position:].strip():
        match = expression.match(value, position)
        assert match is not None, value[position:position + 40]
        output.append(match[1].strip())
        position = match.end()
    return output


def main():
    """Require every field, node, color and source span to match independently."""
    manifest = json.loads((CORPUS / 'mesh_manifest.json').read_text())
    rows = json.loads((OUTPUT / 'report.json').read_text())
    assert [row['file'] for row in rows] == [entry['file'] for entry in manifest['files']]
    report = []
    for entry, row in zip(manifest['files'], rows):
        source = CORPUS / 'files' / entry['file']
        raw = source.read_bytes()
        assert len(raw) == entry['size'] and hashlib.sha256(raw).hexdigest() == entry['sha256']
        program = native_program(source)
        assert program == (OUTPUT / (entry['file'] + '.ps')).read_bytes()
        packets = list(re.finditer(rb'/Mesh X!\r(.*?)/End X!', program, re.S))
        assert len(packets) == len(row['meshes']) == 1
        counts = Counter()
        spaces = Counter()
        for packet, mesh in zip(packets, row['meshes']):
            assert [packet.start(), packet.end()] == [mesh['start'], mesh['end']]
            assert mesh['version'] == 2 and not mesh['private']
            # This strict fixture grammar is independent of AiKit's token and
            # hierarchical readers. It also checks every projected source span.
            text = packet[1].decode('latin1').replace('%_', '')
            matches = list(re.finditer(r'\s*(.*?)\s*/([A-Za-z]+) X#', text, re.S))
            assert ''.join(match[0] for match in matches).strip() == text.strip()
            assert len(matches) == len(mesh['fields'])
            patch = None
            native_patches = []
            space, device = None, 'DeviceGray'
            for match, field in zip(matches, mesh['fields']):
                values, key = tokens(match[1]), match[2]
                assert values == field['values'] and key == field['key']
                original = program[field['start']:field['end']].decode('latin1').replace('%_', '')
                assert tokens(original[:-2].strip()) == values + ['/' + key]
                if key == 'Size':
                    assert mesh['size'] == list(map(int, values[1:-1])) == [15, 12]
                elif key == 'P':
                    assert patch is None
                    patch = {'position': list(map(int, values[1:-1])), 'nodes': []}
                elif key == 'CS':
                    space = values
                    device = values[0][1:] if len(values) == 1 and values[0] in ['/DeviceGray', '/DeviceRGB', '/DeviceCMYK'] else None
                elif key in {'N', 'A', 'S'}:
                    assert patch is not None
                    numbers = list(map(float, values[1:-1]))
                    corner = key == 'N'
                    color = numbers[:-9] if corner else []
                    geometry = numbers[-8:] if corner else numbers
                    node = {
                        'kind': {'N': 'corner', 'A': 'anchor', 'S': 'subdivision'}[key],
                        'position': geometry[:2],
                        'firstHandle': geometry[2:4],
                        'secondHandle': geometry[5:7] if corner else geometry[4:6],
                        'weights': [geometry[4], geometry[7]] if corner else geometry[6:],
                        'color': color,
                        'opacity': numbers[-9] if corner else None,
                        'space': space if corner else None,
                        'deviceName': device if corner else None,
                    }
                    if corner:
                        if device:
                            assert len(color) == {'DeviceGray': 1, 'DeviceRGB': 3, 'DeviceCMYK': 4}[device]
                        else:
                            # Adobe's observed NChannel declares its ink count
                            # before the trailing name. Keep each alternative.
                            assert space[-2:] == ['/NChannel', ']']
                            assert int(space[-3]) == len(color) == space.count('/Separation')
                        spaces[device or 'NChannel'] += 1
                    patch['nodes'].append(node)
                    counts[key] += 1
                elif key == 'E':
                    assert patch is not None and sum(node['kind'] == 'corner' for node in patch['nodes']) == 4
                    native_patches.append(patch)
                    patch = None
            assert patch is None and native_patches == mesh['patches']
            assert len(native_patches) == 180
            assert {tuple(patch['position']) for patch in native_patches} == {(first, second) for first in range(15) for second in range(12)}
        assert counts == {'N': 720, 'A': 8, 'S': 11}
        report.append({'file': row['file'], 'patches': 180, 'nodes': dict(counts), 'spaces': dict(spaces), 'sourceBytes': len(program), 'status': 'passed'})
    (OUTPUT / 'oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
