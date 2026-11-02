#!/usr/bin/env python3
"""Check edited native mesh controls, alpha and original/reopened PDF views.

Inputs come from ai_mesh_editing_test.dart with FOCALE_AI_NEW_OUTPUT.
This verifies literal native data and supplied PDF views, not Adobe recomposition.
"""

import argparse
import json
import re
from pathlib import Path

from corpus_support import native_programs
from verify_focale_group_paints import ghostscript_renders
from verify_native_documents import renders
from verify_native_mesh_geometry import read_packet


def verify_mesh_editing(output):
    """Compare every duplicated native corner with the original host revision."""
    cases = sorted(output.glob('mesh-edit-*.json'))
    assert len(cases) == 13, len(cases)
    for path in cases:
        stem = path.stem
        native = path.with_suffix('.ps').read_bytes()
        assert native_programs(path.with_suffix('.ai')) == [native], stem
        packets = re.findall(rb'(?:%_)?/Mesh X!.*?(?:%_)?/End X!', native, re.S)
        expected = json.loads(path.read_text())
        assert len(packets) == len(expected), (stem, len(packets), len(expected))
        for packet, grid in zip(packets, expected):
            _, dimensions, patches = read_packet(packet.replace(b'%_', b''))
            columns = grid['columns']
            assert dimensions == (columns - 1, grid['rows'] - 1), stem
            for (column, row), patch in patches.items():
                if 'parameters' in grid:
                    assert [item[1] for item in patch if item[0] == 'R'] == [[grid['parameters'][row * (columns - 1) + column]]], stem
                first = row * columns + column
                indices = (first, first + 1, first + columns + 1, first + columns)
                directions = (('right', 'down'), ('down', 'left'), ('left', 'up'), ('up', 'right'))
                nodes = [item for item in patch if item[0] != 'R']
                assert len(nodes) == 4, stem
                for item, index, sides in zip(nodes, indices, directions):
                    kind, color, space, geometry = item
                    assert kind == 'N' and space in ('/DeviceRGB', '/DeviceCMYK', '/DeviceGray'), stem
                    assert color == grid['colors'][index], (stem, index, color, grid['colors'][index])
                    controls = [*grid['points'][index], *grid['handles'][index][sides[0]], 1, *grid['handles'][index][sides[1]], 1]
                    assert all(abs(a - b) < 1e-9 for a, b in zip(geometry, controls)), (stem, index, geometry, controls)
        for dpi in (72, 144):
            actual = renders(path.with_suffix('.ai'), dpi)
            assert actual == renders(output / f'{stem}-reference.pdf', dpi), (stem, dpi, 'original')
            assert actual == renders(output / f'{stem}-reopened.pdf', dpi), (stem, dpi, 'reopened')
        assert ghostscript_renders(path.with_suffix('.ai')) == ghostscript_renders(output / f'{stem}-reference.pdf') == ghostscript_renders(output / f'{stem}-reopened.pdf'), (stem, 'Ghostscript')
        print(stem, 'passed', flush=True)
    print(f'Verified {len(cases)} mesh saves with exact native controls/colors/alpha and Poppler/Ghostscript original/reopened comparisons.')


def main():
    """Read bounded local acceptance fixtures without modifying their source."""
    if not __debug__:
        raise RuntimeError('Run without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    verify_mesh_editing(parser.parse_args().output)


if __name__ == '__main__':
    main()
