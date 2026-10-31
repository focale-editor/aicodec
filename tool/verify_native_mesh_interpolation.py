#!/usr/bin/env python3
"""Qualify a candidate mesh interpolant against Adobe's pinned PDF samples.

This research oracle does not enable mesh rendering in AiNativePdf. It compares
ordinary four-corner cell geometry and process-color interpolation, including
piecewise neighboring edges. More complex cell surfaces and opacity still need
qualification. No Adobe PDF color is used to construct the candidate field.
"""

import hashlib
import json

import numpy as np

from verify_native_mesh_inks import pdf_patches
from verify_native_meshes import CORPUS, OUTPUT


# Tensor boundary order followed by its four interior control points (PDF 1.7).
ORDER = [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2), (3, 3), (2, 3),
         (1, 3), (0, 3), (0, 2), (0, 1), (1, 1), (2, 1), (2, 2), (1, 2)]


def corners(indices):
    """Map native cyclic corner order to logical grid vertices."""
    first, second = indices
    return [(first, second), (first + 1, second), (first + 1, second + 1), (first, second + 1)]


def edges(mesh):
    """Project directed boundary cubics, keeping all intermediate knots."""
    output = {}
    for patch in mesh['patches']:
        nodes, keys = patch['nodes'], corners(patch['position'])
        assert all(node['weights'] == ([1, 1] if node['kind'] == 'corner' else [1]) for node in nodes)
        corner = -1
        for start, node in enumerate(nodes):
            if node['kind'] != 'corner':
                continue
            corner += 1
            current, parts = start, []
            while True:
                following = (current + 1) % len(nodes)
                first, second = nodes[current], nodes[following]
                # N handles follow the cell. A/S handles follow the grid axes;
                # their order therefore differs on increasing/decreasing sides.
                outgoing = first['firstHandle'] if first['kind'] == 'corner' or corner >= 2 else first['secondHandle']
                incoming = second['secondHandle'] if second['kind'] == 'corner' or corner >= 2 else second['firstHandle']
                parts.append(np.array([first['position'], outgoing, incoming, second['position']]))
                if second['kind'] == 'corner':
                    break
                current = following
            pair = keys[corner], keys[(corner + 1) % 4]
            if pair in output:
                assert np.array_equal(output[pair], parts), pair
            output[pair] = parts
            output[pair[::-1]] = [part[::-1] for part in parts[::-1]]
    return output


def process_color(node):
    """Explicitly map this fixture's process inks, without general spot mixing."""
    if node['deviceName'] == 'DeviceCMYK':
        return np.array(node['color'])
    if node['deviceName'] == 'DeviceGray':
        return np.array([0, 0, 0, 1 - node['color'][0]])
    expected = {b'Cyan': [1, 0, 0, 0], b'Magenta': [0, 1, 0, 0], b'Yellow': [0, 0, 1, 0], b'Black': [0, 0, 0, 1]}
    result = np.zeros(4)
    for component, ink in zip(node['inkTints'], reversed(node['inks']), strict=True):
        name = bytes(component['name'])
        assert name == bytes(ink['name']) and ink['deviceName'] == 'DeviceCMYK'
        assert ink['components'] == expected[name]
        result += np.array(expected[name]) * component['tint']
    assert node['inks']
    return result


def field(mesh):
    """Build source-only directional color derivatives in artwork coordinates."""
    curves, colors = edges(mesh), {}
    for patch in mesh['patches']:
        for key, node in zip(corners(patch['position']), [node for node in patch['nodes'] if node['kind'] == 'corner'], strict=True):
            assert node['weights'] == [1, 1] and node['opacity'] == 1
            value = process_color(node)
            if key in colors:
                assert np.array_equal(colors[key], value)
            colors[key] = value

    def lengths(first, second):
        """Measure the tangent and control-polygon travel projected onto it."""
        pieces = curves[first, second]
        tangent = pieces[0][1] - pieces[0][0]
        magnitude = np.linalg.norm(tangent)
        if magnitude == 0:
            return 0.0, 0.0
        direction = tangent / magnitude
        travel = sum(np.abs((piece[1:] - piece[:-1]) @ direction).sum() for piece in pieces)
        return magnitude, travel

    derivatives = {}
    for axis in [0, 1]:
        extent = mesh['size'][axis]
        for vertex in colors:
            if vertex[axis] in [0, extent]:
                continue
            before = tuple(value - (1 if index == axis else 0) for index, value in enumerate(vertex))
            after = tuple(value + (1 if index == axis else 0) for index, value in enumerate(vertex))
            left, right = colors[vertex] - colors[before], colors[after] - colors[vertex]
            previous_handle, previous_span = lengths(vertex, before)
            next_handle, next_span = lengths(vertex, after)
            if previous_span == 0 or next_span == 0:
                derivatives[vertex, axis] = np.zeros(4)
                continue
            slope = (left / previous_span + right / next_span) / 2
            limit = np.minimum(abs(left) / previous_handle, abs(right) / next_handle)
            derivatives[vertex, axis] = np.where(left * right > 0, np.sign(slope) * np.minimum(abs(slope), limit), 0)
        for vertex in colors:
            if vertex[axis] not in [0, extent]:
                continue
            inside = tuple((1 if vertex[axis] == 0 else extent - 1) if index == axis else value
                           for index, value in enumerate(vertex))
            own_handle, _ = lengths(vertex, inside)
            inner_handle, _ = lengths(inside, vertex)
            assert extent > 1 and own_handle > 0  # Qualified fixture boundary.
            delta = (colors[inside] - colors[vertex]) * (1 if vertex[axis] == 0 else -1)
            secant = delta / (3 * own_handle)
            slope = 2 * secant - derivatives[inside, axis] * inner_handle / own_handle
            derivatives[vertex, axis] = np.where(slope * secant > 0, np.sign(secant) * np.minimum(abs(slope), 3 * abs(secant)), 0)
    return colors, derivatives, lengths


def hermite(value):
    """Return endpoint-value and endpoint-derivative cubic basis functions."""
    return [2 * value**3 - 3 * value**2 + 1, -2 * value**3 + 3 * value**2,
            value**3 - 2 * value**2 + value, value**3 - value**2]


def sample_color(color_field, indices, first, second):
    """Evaluate a zero-mixed-derivative color patch from its native neighbors."""
    colors, derivatives, lengths = color_field
    cyclic = corners(indices)
    keys = [cyclic[0], cyclic[1], cyclic[3], cyclic[2]]
    a, b, da, db = hermite(first)
    c, d, dc, dd = hermite(second)
    result = sum(colors[key] * weight for key, weight in zip(keys, [a*c, b*c, a*d, b*d]))
    for index, key in enumerate(keys):
        along_first = keys[index // 2 * 2 + 1 - index % 2]
        along_second = keys[index % 2 + (2 if index < 2 else 0)]
        result += derivatives[key, 0] * 3 * lengths(key, along_first)[0] * [da*c, db*c, da*d, db*d][index]
        result += derivatives[key, 1] * 3 * lengths(key, along_second)[0] * [a*dc, b*dc, a*dd, b*dd][index]
    return np.clip(result, 0, 1)


def basis(value):
    """Return cubic Bernstein basis coefficients."""
    return np.array([(1-value)**3, 3*value*(1-value)**2, 3*value**2*(1-value), value**3])


def derivative(value):
    """Return derivatives of the cubic Bernstein coefficients."""
    return np.array([-3*(1-value)**2, 3*(1-value)*(1-3*value), 3*value*(2-3*value), 3*value**2])


def tensor(patch):
    """Construct a simple cell's geometry with zero corner mixed derivatives."""
    nodes = patch['nodes']
    assert len(nodes) == 4 and all(node['weights'] == [1, 1] for node in nodes)
    grid = np.zeros((4, 4, 2))
    for index, node in enumerate(nodes):
        position, outgoing, incoming = [np.array(node[key]) for key in ['position', 'firstHandle', 'secondHandle']]
        grid[ORDER[index*3]] = position
        grid[ORDER[index*3+1]] = outgoing
        grid[ORDER[(index*3-1) % 12]] = incoming
        grid[ORDER[12+index]] = outgoing + incoming - position
    return grid


def search_grid(grid):
    """Bound the search to observed dyadic subdivision positions, through 1/64."""
    coefficients = np.array([basis(index / 64) for index in range(65)])
    return np.einsum('ai,ijc,bj->abc', coefficients, grid, coefficients)


def restrict(start, end):
    """Form the exact one-dimensional Bernstein subinterval transformation."""
    return np.array([basis(start), basis(start) + (end-start)/3*derivative(start),
                     basis(end) - (end-start)/3*derivative(end), basis(end)])


def match_patch(grid, samples, patch):
    """Require all sixteen PDF control points to match one native subinterval."""
    points = np.array(patch['points'])
    candidates = [np.argwhere(np.linalg.norm(samples - point, axis=2) < 0.0015) for point in points[[0, 3, 9]]]
    matches = []
    for origin in candidates[0]:
        for adjacent in candidates[1]:
            equal = adjacent == origin
            if int(equal.sum()) != 1:
                continue
            swapped = bool(equal[0])
            for opposite in candidates[2]:
                if opposite[1 if swapped else 0] != origin[1 if swapped else 0] or opposite[0 if swapped else 1] == origin[0 if swapped else 1]:
                    continue
                first_start, second_start = origin / 64
                first_end = (opposite if swapped else adjacent)[0] / 64
                second_end = (adjacent if swapped else opposite)[1] / 64
                reduced = np.einsum('ai,ijc,bj->abc', restrict(first_start, first_end), grid, restrict(second_start, second_end))
                if swapped:
                    reduced = reduced.transpose(1, 0, 2)
                expected = np.array([reduced[first, second] for first, second in ORDER])
                error = float(np.linalg.norm(expected - points, axis=1).max())
                if error >= 0.0015:
                    continue
                rectangle = np.array([(first_start, second_start), (first_end, second_start),
                                      (first_end, second_end), (first_start, second_end)])
                if swapped:
                    rectangle = rectangle[[0, 3, 2, 1]]
                matches.append((rectangle, error))
    # Repeated positions on folded cells are insufficient evidence. Require an
    # unambiguous full-control-net match, without consulting any PDF colors.
    assert len(matches) <= 1
    return matches[0] if matches else None


def main():
    """Fail on corpus drift or a candidate exceeding the measured error gates."""
    manifest = json.loads((CORPUS / 'mesh_manifest.json').read_text())
    rows = json.loads((OUTPUT / 'report.json').read_text())
    assert [row['file'] for row in rows] == [entry['file'] for entry in manifest['files']]
    reports = []
    for entry, row in zip(manifest['files'], rows):
        path = CORPUS / 'files' / entry['file']
        data = path.read_bytes()
        assert len(data) == entry['size'] and hashlib.sha256(data).hexdigest() == entry['sha256']
        mesh = row['meshes'][0]
        assert len(row['meshes']) == 1 and len(mesh['patches']) == 180
        native = []
        for patch in mesh['patches']:
            if len(patch['nodes']) == 4:
                grid = tensor(patch)
                native.append((patch, grid, search_grid(grid)))
        color_field = field(mesh)
        matches, unmatched, maximum_geometry, maximum_color, half_step_exceptions = [], [], 0, 0, 0
        for index, patch in enumerate(pdf_patches(path)):
            points = np.array(patch['points'])[[0, 3, 6, 9]]
            candidates = []
            for source, grid, samples in native:
                if np.any(points < grid.min(axis=(0, 1)) - 0.01) or np.any(points > grid.max(axis=(0, 1)) + 0.01):
                    continue
                match = match_patch(grid, samples, patch)
                if match is not None:
                    candidates.append((source, match))
            assert len(candidates) <= 1, index
            if not candidates:
                unmatched.append(index)
                continue
            source, (parameters, geometry_error) = candidates[0]
            errors = [float(abs(sample_color(color_field, source['position'], *position) - color).max())
                      for position, color in zip(parameters, patch['colors'])]
            assert np.all(np.isfinite(errors)) and np.isfinite(geometry_error), index
            maximum_geometry = max(maximum_geometry, geometry_error)
            maximum_color = max(maximum_color, *errors)
            half_step_exceptions += sum(error > 0.5 / 255 + 1e-7 for error in errors)
            matches.append({'pdfPatch': index, 'nativeCell': source['position'], 'parameters': parameters.tolist(),
                            'geometryError': geometry_error, 'componentError': max(errors), 'cornerComponentErrors': errors})
        coverage = {tuple(patch['position']): np.zeros((64, 64), dtype=np.uint16) for patch, _, _ in native}
        for match in matches:
            parameters = np.array(match['parameters'])
            lower = np.round(parameters.min(axis=0) * 64).astype(int)
            upper = np.round(parameters.max(axis=0) * 64).astype(int)
            coverage[tuple(match['nativeCell'])][lower[0]:upper[0], lower[1]:upper[1]] += 1
        # Require every parameter region of every simple source cell exactly
        # once, so a dropped or duplicated PDF patch cannot improve the score.
        assert len(native) == 163 and len(matches) == 1624 and len(unmatched) == 123
        assert all(np.all(values == 1) for values in coverage.values())
        assert maximum_color < 1 / 255, {
            'matched': len(matches), 'maximumComponentError': maximum_color,
            'beyondHalfStep': half_step_exceptions,
            'worst': sorted(matches, key=lambda item: item['componentError'])[-3:],
        }
        result = {'file': row['file'], 'qualifiedNativeCells': len({tuple(match['nativeCell']) for match in matches}),
                  'matchedPdfPatches': len(matches), 'unmatchedPdfPatches': unmatched, 'sampledCorners': 4 * len(matches),
                  'maximumGeometryError': maximum_geometry, 'maximumComponentError': maximum_color,
                  'cornersBeyondHalfComponentStep': half_step_exceptions, 'matches': matches, 'status': 'passed'}
        reports.append(result)
        print(json.dumps({key: value for key, value in result.items() if key not in ['matches', 'unmatchedPdfPatches']}, indent=2))
    (OUTPUT / 'interpolation-oracle-report.json').write_text(json.dumps(reports, indent=2) + '\n')


if __name__ == '__main__':
    main()
