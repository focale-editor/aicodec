#!/usr/bin/env python3
"""Independently check selected/all-vertex paint edits in the pinned CC mesh."""

import json
import re
from verify_native_meshes import CORPUS, OUTPUT, inks, native_program, tokens


def mesh_records(program):
    """Read the fixture's field grammar and effective paint at each corner."""
    packet = re.search(rb'/Mesh X!\r?\n?(.*?)/End X!', program, re.S)
    assert packet is not None
    body = packet[1].decode('latin1').replace('%_', '')
    fields = list(re.finditer(r'\s*(.*?)\s*/([A-Za-z]+) X#', body, re.S))
    assert ''.join(field[0] for field in fields).strip() == body.strip()
    output, corners = [], []
    space, position, index = ['/DeviceGray'], None, 0
    for field in fields:
        values, key = tokens(field[1]), field[2]
        if key == 'CS':
            space = values
            continue
        if key == 'P':
            position = tuple(map(int, values[1:-1]))
            index = 0
        if key == 'N':
            first, second = position
            logical = [(first, second), (first + 1, second), (first + 1, second + 1), (first, second + 1)][index]
            index += 1
            numbers = list(map(float, values[1:-1]))
            corners.append({'vertex': logical, 'color': numbers[:-9], 'opacity': numbers[-9],
                            'space': space[0] if len(space) == 1 else None, 'inks': inks(space),
                            'geometry': values[-9:-1]})
            output.append((key, values[-9:-1]))
        else:
            output.append((key, values))
    return packet, output, corners


def main():
    """Check every unchanged field and all 720 corner appearances independently."""
    rows = json.loads((OUTPUT / 'report.json').read_text())
    report = []
    changes = {
        (0, 0): ('/DeviceRGB', [0.2, 0.3, 0.4], 0.8),
        (5, 5): ('/DeviceGray', [0.25], None),
        (5, 11): ('/DeviceCMYK', [0.1, 0.2, 0.3, 0.4], 0.6),
        (8, 7): ('/DeviceRGB', [0.6, 0.2, 0.7], None),
        (15, 12): (None, None, 0.3),
    }
    for row in rows:
        original = native_program(CORPUS / 'files' / row['file'])
        packet, fields, corners = mesh_records(original)
        assert len(corners) == 720
        for variant in ['painted', 'translucent']:
            changed = (OUTPUT / f"{row['file']}.{variant}.ps").read_bytes()
            edited_packet, edited_fields, edited_corners = mesh_records(changed)
            assert original[:packet.start()] == changed[:edited_packet.start()]
            assert original[packet.end():] == changed[edited_packet.end():]
            assert fields == edited_fields
            assert len(edited_corners) == len(corners)
            affected = 0
            for before, after in zip(corners, edited_corners):
                expected = dict(before)
                if variant == 'translucent':
                    expected['opacity'] = 0.5
                    affected += 1
                elif before['vertex'] in changes:
                    space, color, opacity = changes[before['vertex']]
                    if color is not None:
                        expected.update(space=space, color=color, inks=[])
                    if opacity is not None:
                        expected['opacity'] = opacity
                    affected += 1
                assert expected == after, (variant, before['vertex'])
            assert affected == (14 if variant == 'painted' else 720)
            report.append({'file': row['file'], 'variant': variant, 'updatedCorners': affected, 'status': 'passed'})
    (OUTPUT / 'paint-oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
