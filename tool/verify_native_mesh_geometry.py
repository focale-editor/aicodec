#!/usr/bin/env python3
"""Independently inspect deferred mesh affine/topology outputs against source data.

This checks literal geometry, inks, patch coverage and preserved surrounding data.
It does not render a mesh or establish an Illustrator editing round trip.
"""

import json
import re

from verify_native_meshes import CORPUS, OUTPUT, inks, native_program, tokens


def read_packet(program):
    """Read the fixture's scalar/array fields without importing AiCodec."""
    packet = re.search(rb'/Mesh X!\r?\n?(.*?)/End X!', program, re.S)
    if packet is None:
        raise ValueError('Missing mesh packet')
    body = packet[1].decode('latin1').replace('%_', '')
    fields = list(re.finditer(r'\s*(.*?)\s*/([A-Za-z]+) X#', body, re.S))
    assert ''.join(field[0] for field in fields).strip() == body.strip()
    space, size, active = ['/DeviceGray'], None, None
    patches = {}
    for field in fields:
        values, key = tokens(field[1]), field[2]
        if key == 'CS':
            space = values
        elif key == 'Size':
            size = tuple(map(int, values[1:-1]))
        elif key == 'P':
            active = tuple(map(int, values[1:-1]))
            assert active not in patches
            patches[active] = []
        elif key in {'N', 'A', 'S'}:
            numbers = list(map(float, values[1:-1]))
            geometry = numbers[-8:] if key == 'N' else numbers
            color_space = space[0] if len(space) == 1 else inks(space)
            patches[active].append((key, numbers[:-8] if key == 'N' else [], color_space if key == 'N' else None, geometry))
        elif key == 'R':
            patches[active].append((key, list(map(float, values[1:-1]))))
        elif key == 'E':
            active = None
    assert size is not None and len(patches) == size[0] * size[1]
    assert set(patches) == {(first, second) for first in range(size[0]) for second in range(size[1])}
    return packet, size, patches


def without_bounds(program):
    """Exclude explicitly updated DSC ink envelopes from byte comparison."""
    return re.sub(rb'(^|(?<=\r))%%(?:HiResBoundingBox|BoundingBox|PageBoundingBox):[^\r\n]*', b'', program, flags=re.M)


def main():
    """Check both variants against the pinned source, preserving every paint value."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    manifest = json.loads((CORPUS / 'mesh_manifest.json').read_text())
    report = []
    for entry in manifest['files']:
        name = entry['file']
        source = native_program(CORPUS / 'files' / name)
        original_packet, size, original = read_packet(source)
        for variant in ('transformed', 'cropped'):
            changed = (OUTPUT / f'{name}.{variant}.ps').read_bytes()
            packet, dimensions, patches = read_packet(changed)
            assert without_bounds(source[:original_packet.start()]) == without_bounds(changed[:packet.start()])
            assert without_bounds(source[original_packet.end():]) == without_bounds(changed[packet.end():])
            assert dimensions == (size if variant == 'transformed' else (size[0] - 1, size[1]))
            for key, patch in patches.items():
                expected = original[key]
                assert len(patch) == len(expected)
                for before, after in zip(expected, patch):
                    if variant == 'cropped' or before[0] == 'R':
                        assert before == after
                        continue
                    assert before[:3] == after[:3]
                    old, new = before[3], after[3]
                    second = 5 if before[0] == 'N' else 4
                    coordinate_indices = {0, 1, 2, 3, second, second + 1}
                    for offset in (0, 2, second):
                        x, y = old[offset:offset + 2]
                        mapped = (1.1 * x + .2 * y + 5, .15 * x + .9 * y - 7)
                        assert all(abs(actual - wanted) < 1e-9 for actual, wanted in zip(new[offset:offset + 2], mapped))
                    assert [value for index, value in enumerate(old) if index not in coordinate_indices] == [value for index, value in enumerate(new) if index not in coordinate_indices]
            report.append({'file': name, 'variant': variant, 'patches': len(patches), 'status': 'passed'})
    (OUTPUT / 'geometry-oracle-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
