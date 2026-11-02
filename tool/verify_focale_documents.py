#!/usr/bin/env python3
"""Check Focale-authored CC saves with independent native and PDF readers.

Generate inputs with Focale's new-document, appearance, image and lifecycle tests and
FOCALE_AI_NEW_OUTPUT.
This verifies the qualified ordinary integration, not Adobe Illustrator acceptance.
"""

import argparse
import importlib
import math
import re
from pathlib import Path
import subprocess
import sys

from pypdf import PdfReader
from pypdf.generic import ContentStream

from corpus_support import REVISION, native_programs
from verify_native_colors import operators
from verify_native_documents import renders
from verify_native_rasters import images, samples
from verify_native_placements import preview_data
from verify_native_mesh_geometry import read_packet
from verify_native_group_lifecycle import inventory as group_inventory
from verify_native_structure import native_values


def verify_appearance_lifecycle(inkai, output):
    """Check fresh complete owners, exact mask carriers and two saved revisions."""
    from inkai.parser.hierarchy_objects import Mask

    count = 0
    for kind in ('path', 'group'):
        for destination in ('layer', 'group', 'root'):
            first_identities = None
            for revision in (1, 2):
                stem = f'appearance-{kind}-{destination}-{revision}'
                path = output / f'{stem}.ai'
                native = (output / f'{stem}.ps').read_bytes()
                document = inkai.parse(str(output / f'{stem}.ps'))
                values = list(native_values(document.trailer))
                owners = [value for value in values if isinstance(value, dict) and 'AI10_ArtUID' in value]
                identifiers = [value['AI10_ArtUID'] for value in owners]
                assert len(set(identifiers)) == len(identifiers), stem
                assert identifiers.count('focale_object_1') == identifiers.count('focale_object_2') == 1, stem
                if revision == 1:
                    first_identities = identifiers
                else:
                    assert identifiers == first_identities, stem
                masked = [value for value in owners if 'AI9_Mask' in value]
                assert len(masked) == (1 if kind == 'path' else 3), stem
                assert len([value for value in values if isinstance(value, Mask)]) == len(masked), stem
                for owner in masked:
                    name, mask = owner['AIArtName'], owner['AI9_Mask']
                    assert isinstance(mask, Mask), (stem, name)
                    if name == 'Added':
                        expected = (kind == 'path', revision == 2, kind == 'group', kind == 'path')
                    elif name == 'Added-inner':
                        expected = (True, True, True, False)
                    else:
                        assert name.endswith('Added-path'), (stem, name)
                        expected = (True, False, False, True)
                    assert (mask.Linked, mask.Disabled, mask.Clipping, mask.Inverted) == expected, (stem, name)
                    assert mask.Art[0].command == 'X=' and mask.Art[-1].command == 'X+', stem
                    starts = [list(map(float, op.tokens)) for op in operators(mask.Art) if op.command == 'm']
                    assert starts == [[45, -10]], (stem, name, starts)
                raster, = images(document)
                color, alpha = samples(raster)
                assert len(color) == raster.w * raster.h * 3 and len(alpha) == raster.w * raster.h, stem
                state = None
                selected = []
                for op in operators(document.trailer):
                    if op.command == 'Xy':
                        state = list(map(float, op.tokens))
                    if op is raster:
                        selected.append(state)
                assert selected == [[int(kind == 'group'), .7 if revision == 1 else .4, 1, 0, 0]], (stem, selected)
                assert native_programs(path) == [native], stem
                pdf = PdfReader(path, strict=True)
                assert len(pdf.pages) == 1, stem
                private = pdf.pages[0]['/PieceInfo']['/Illustrator']['/Private']
                assert private['/AIMetaData'].get_data() == native[:native.index(b'%%EndComments\n') + len(b'%%EndComments\n')], stem
                assert renders(path) == renders(output / f'{stem}-reference.pdf'), stem
                count += 1
    return count


def verify_named_inks(inkai, output):
    """Check inverse native/PDF tints, exact spot alternatives and page pixels."""
    for family, count in (('cmyk', 4), ('rgb', 3)):
        for revision in (1, 2):
            stem = f'ink-{family}-{revision}'
            native = (output / f'{stem}.ps').read_bytes()
            document = inkai.parse(str(output / f'{stem}.ps'))
            paints = [op for op in operators(document.trailer) if op.command in ('x', 'X', 'Xx', 'XX')]
            expected = [.1 * revision, .3, .5] + ([.7] if count == 4 else [])
            assert len(paints) == 2, stem
            assert [float(op.tokens[count + 1]) for op in paints] == [.75, 0], stem
            assert all(op.tokens[count] == b'Spot' for op in paints), stem
            assert all(list(map(float, op.tokens[:count])) == expected for op in paints), stem
            path = output / f'{stem}.ai'
            assert native_programs(path) == [native], stem
            pdf = PdfReader(path, strict=True)
            assert len(pdf.pages) == 1, stem
            tints = []

            def inspect(stream, resources, depth=0):
                """Follow painted forms, excluding unused inherited resources."""
                assert depth < 16
                spaces = {}
                for operands, operator in ContentStream(stream, pdf).operations:
                    if operator in (b'cs', b'CS'):
                        spaces[operator == b'CS'] = resources['/ColorSpace'][operands[0]].get_object()
                    elif operator in (b'scn', b'SCN'):
                        space = spaces[operator == b'SCN']
                        assert space[:3] == ['/Separation', '/Spot', '/DeviceCMYK' if count == 4 else '/DeviceRGB'], stem
                        transform = space[3].get_object()
                        assert transform['/FunctionType'] == 2 and transform['/N'] == 1, stem
                        assert list(transform['/C0']) == [0 if count == 4 else 1] * count, stem
                        assert list(transform['/C1']) == expected, stem
                        tints.extend(map(float, operands))
                    elif operator == b'Do':
                        form = resources['/XObject'][operands[0]].get_object()
                        if form.get('/Subtype') == '/Form':
                            inspect(form, form.get('/Resources', resources), depth + 1)

            inspect(pdf.pages[0].get_contents(), pdf.pages[0]['/Resources'])
            assert sorted(tints) == [.25, 1], (stem, tints)
            assert renders(path) == renders(output / f'{stem}-reference.pdf'), stem
    print('Verified four named-ink saves: shared CMYK/RGB alternatives, native/PDF tint inversion, spot plates and exact repeated-save PDF pixels.')


def main():
    """Verify shared native owners, edited geometry, caches and exact page pixels."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module('inkai')
    cases = [('new', 'reference', 1, [[10, -10]])]
    cases += [(f'multiple-{i}', f'multiple-{i}-reference', 2, [[10 + 5 * i, -10 - 3 * i]]) for i in (1, 2)]
    cases.append(('appearance', 'appearance-reference', 1, [[10, -10], [70, -10]]))
    cases.append(('lifecycle', 'lifecycle-reference', 1,
                  [[10, -10], [35, -50], [50, -10], [90, -10], [130, -10]]))
    cases += [('images-created', 'images-created-reference', 1, [[10, -10], [110, -10]]),
              ('images-replaced', 'images-replaced-reference', 1, []),
              ('images-hidden', 'images-hidden-reference', 1, [[10, -10]]),
              ('images-attributes', 'images-attributes-reference', 1, [[10, -10]])]
    cases.append(('links-created', 'links-created-reference', 1, [[10, -10]]))
    cases.append(('gradient-native', 'gradient-native-reference', 1, [[10, -10], [60, -10]]))
    cases.append(('mesh-native', 'mesh-native-reference', 1, [[10, -10], [160, -10]]))
    cases.append(('image-mesh-transparency', 'image-mesh-transparency-reference', 1, [[10, -10], [160, -60]]))
    cases.append(('groups-native', 'groups-native-reference', 1, [[10, -10], [160, -60]]))
    cases.append(('shapes-native', 'shapes-native-reference', 1, [[10, -10], [82.5, -10], [120, -10], [165, -10], [10, -80]]))
    cases.append(('rounded-native', 'rounded-native-reference', 1, [[75 - 2 * math.cos(.3), -10 + 2 * math.sin(.3)]]))
    cases.append(('transparency-native', 'transparency-native-reference', 1,
                  [[10 + (index % 8) * 22, -10 - (index // 8) * 40] for index in range(16)]))
    rectangles = {
        'boards-resized': [(-20, 10, 100, -60), (50, 0, 150, -80)],
        'boards-inserted': [(50, 0, 150, -80), (220, 0, 300, -60), (0, 0, 100, -80)],
        'boards-removed': [(220, 0, 300, -60), (50, 0, 150, -80)],
        'boards-painted': [(0, 0, 100, -80), (50, 0, 150, -80), (220, -30, 320, -110)],
        'boards-catalog': [(50, 0, 150, -80), (220, 0, 300, -60)],
    }
    cases += [(stem, f'{stem}-reference', len(bounds), [[10, -10], [70, -10]] +
               ([[220, -30], [230, -40]] if stem == 'boards-painted' else []))
              for stem, bounds in rectangles.items()]
    identities = {}
    page_references = {}
    for stem, reference, count, starts in cases:
        path = args.output / f'{stem}.ai'
        native = (args.output / f'{stem}.ps').read_bytes()
        parsed = inkai.parse(str(args.output / f'{stem}.ps'))
        actual_starts = [list(map(float, op.tokens)) for op in operators(parsed.trailer) if op.command == 'm']
        if stem == 'rounded-native':
            assert len(actual_starts) == len(starts) == 1
            assert all(abs(actual - expected) < 1e-9 for actual, expected in zip(actual_starts[0], starts[0]))
            radii = dict((int(index), float(radius)) for radius, index in re.findall(rb'([-+.0-9eE]+) /Real \(ai::Rectangle::CornerRadius::([0-3])\)', native))
            assert radii.keys() == {0, 1, 2, 3}
            assert all(abs(radii[index] - index - 2) < 1e-9 for index in range(4))
            assert b'3 /Int (ai::Rectangle::InitialQuadrant)' in native
            assert b'0 /Bool (ai::Rectangle::Clockwise)' in native
        else:
            assert actual_starts == starts, (stem, actual_starts, starts)
        if stem.startswith('images-'):
            raster, = images(parsed)
            if stem != 'images-replaced':
                expected_samples = (bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]), bytes([255, 128, 64, 255]))
                matrix = [20, 0, 0, 10, 15, -25]
                dimensions = (2, 2)
            else:
                expected_samples = (bytes([0, 0, 255, 255, 0, 0, 0, 255, 0]), b'')
                matrix = [40 / 3, 0, 0, 20, 15, -25]
                dimensions = (3, 1)
            assert (raster.h, raster.w) == dimensions
            assert all(abs(actual - expected) < 1e-10 for actual, expected in zip(raster.matrix, matrix))
            assert samples(raster) == expected_samples
            if stem in ('images-hidden', 'images-attributes'):
                state = {}
                selected = None
                for op in operators(parsed.trailer):
                    if op.command in ('A', 'Xw', 'Xy', 'O'):
                        state[op.command] = [float(token) for token in op.tokens]
                    if op is raster:
                        selected = state.copy()
                    if op.command == 'm':
                        assert state['Xy'] == [0, 1, 1, 0, 0]
                        assert state['O'] == state['A'] == state['Xw'] == [0]
                assert selected is not None
                assert selected['Xy'] == [0, .35, 1, 0, 0]
                assert selected['O'] == [1]
                assert selected['A'] == selected['Xw'] == [int(stem == 'images-hidden')]
        if stem == 'links-created':
            assert not images(parsed)
            preview = preview_data(parsed)
            assert (preview.width, preview.height, preview.bits_per_pixel) == (2, 2, 32)
            assert preview.raw == bytes([255, 255, 0, 0, 128, 0, 255, 0, 64, 0, 0, 255, 255, 255, 255, 0])
            assert b'%%DocumentFiles:/assets/image.png\n' in native
            assert b'%%IncludeFile:/assets/image.png\n' in native
            header, = re.findall(rb'^\[ ([^\n]+) \] 0.0 0.0 2.0 2.0 4 4 0 (\((?:\\[0-7]{3})+\))`$', native, re.M)
            assert list(map(float, header[0].split())) == [20, 0, 0, -10, 15, -25]
            assert bytes(int(value, 8) for value in re.findall(rb'\\([0-7]{3})', header[1])) == b'/assets/image.png'
        if stem == 'gradient-native':
            commands = list(operators(parsed.trailer))
            assert sum(op.command == 'Bb' for op in commands) == 1
            assert sum(op.command == 'Bg' for op in commands) == 1
            assert sum(op.command == 'BB' for op in commands) == 1
            assert len(re.findall(rb'^%_.* Bs$', native, re.M)) == 4
            assert len(re.findall(rb'^4 %_Br$', native, re.M)) == 3
            native_stops = re.findall(rb'^%_([^\n]*) Bs$', native, re.M)
            assert [float(stop.split()[-1]) for stop in native_stops] == [100, 50, 50, 0]
            assert [float(stop.split()[-4]) for stop in native_stops] == [64 / 255, 64 / 255, 1, 1]
        if stem == 'shapes-native':
            handlers = re.findall(rb'\((ai::[A-Za-z]+)\) /UnicodeString \(ai::LiveShape::HandlerName\)', native)
            assert handlers == [b'ai::Rectangle', b'ai::Ellipse', b'ai::Polygon', b'ai::Star', b'ai::Line']
            assert b'/AI11TextDocument' in native
            assert b'(ai::Rectangle::Width)' in native
            assert b'(ai::Star::Radius2)' in native
        if stem == 'transparency-native':
            current = None
            saved = []
            for op in operators(parsed.trailer):
                if op.command == 'Xy':
                    current = [float(token) for token in op.tokens]
                if op.command == 'm':
                    saved.append(current)
            assert saved == [[index, .37, int(index % 2 == 0), 0, 0] for index in range(16)]
        if stem == 'image-mesh-transparency':
            raster, = images(parsed)
            assert samples(raster) == (bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]), bytes([255, 128, 64, 255]))
            assert preview_data(parsed).raw == bytes([255, 255, 0, 0, 128, 0, 255, 0, 64, 0, 0, 255, 255, 255, 255, 0])
            current = None
            selected = []
            for op in operators(parsed.trailer):
                if op.command == 'Xy':
                    current = [float(token) for token in op.tokens]
                if op is raster or op.command == '`' or op.command == 'X!' and list(op.tokens) == [b'/Mesh']:
                    selected.append(current)
            # The pinned reader folds the placement instruction into its
            # FileType comment tuple. Check that carrier directly; raster and
            # mesh boundaries remain independently parsed operators.
            assert selected == [[1, .63, 0, 0, 0]] * 2
            placed, = re.findall(rb'(?m)^([-.0-9 ]+) Xy\n%AI5_BeginPlace\n%%FileType: 1\n(\[ [^\n]+`)$', native)
            assert list(map(float, placed[0].split())) == [1, .63, 0, 0, 0]
            assert list(map(float, placed[1].split(b']')[0][1:].split())) == [20, 0, 0, -10, 15, -25]
            assert b'%%DocumentFiles:/assets/image.png\n' in native
        if stem == 'groups-native':
            roots, groups, _ = group_inventory(parsed)
            assert len(roots) == 1 and len(groups) == 2
            assert groups[1]['children'][1] is groups[0]
            assert roots[0]['children'][0] is groups[1]
            raster, = images(parsed)
            assert samples(raster) == (bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]), bytes([255, 128, 64, 255]))
            assert preview_data(parsed).raw == bytes([255, 255, 0, 0, 128, 0, 255, 0, 64, 0, 0, 255, 255, 255, 255, 0])
        if stem in ('mesh-native', 'image-mesh-transparency', 'groups-native'):
            _, dimensions, patches = read_packet(native)
            assert dimensions == (2, 2)
            assert all(len(patch) == 4 for patch in patches.values())
            first = patches[(0, 0)][0]
            assert first[:3] == ('N', [.123456789, .234567891, .345678912, .123456781, .3712345], '/DeviceCMYK')
            assert first[3][:2] == [40, -15]
            assert all(node[3][4] == node[3][7] == 1 for patch in patches.values() for node in patch)
        if stem in rectangles:
            setup = [value.asdict() if hasattr(value, 'asdict') else value for value in parsed.setup.children]
            document, = [value for value in setup if isinstance(value, dict) and value.get('_type') == 'Document']
            boards = document['Recorded']['ArtboardArray']
            assert [tuple(board['PositionPoint1']) + tuple(board['PositionPoint2']) for board in boards] == rectangles[stem]
            identities[stem] = [board['ArtboardUUID'] for board in boards]
            assert len(set(identities[stem])) == count
            if stem == 'boards-resized':
                assert boards[0]['Name'].encode('latin-1').decode('utf-16-be') == 'Plan été 🌿'
                assert document['Recorded']['CropAreaActive'] == 0
            if stem == 'boards-removed':
                assert document['Recorded']['CropAreaActive'] == 1
                assert document['NotRecorded']['LastArtboardID'] == 3
        if stem == 'appearance':
            state = {}
            snapshots = []
            for op in operators(parsed.trailer):
                if op.command in ('Xa', 'XA', 'Xy', 'w', 'O', 'R', 'XR', 'd'):
                    state[op.command] = [float(token.strip(b'[]')) for token in op.tokens if token.strip(b'[]')]
                if op.command == 'm':
                    snapshots.append(state.copy())
            assert snapshots[0]['Xa'] == [0, 1, 0]
            assert snapshots[0]['XA'] == [0, 0, 1]
            assert snapshots[0]['Xy'] == [0, 0.4, 1, 0, 0]
            assert snapshots[0]['w'] == [3]
            assert snapshots[0]['d'] == [6, 3, 1.5]
            assert snapshots[0]['O'] == snapshots[0]['R'] == snapshots[0]['XR'] == [1]
            assert snapshots[1]['Xa'] == [1, 0, 0]
            assert snapshots[1]['Xy'] == [0, 1, 1, 0, 0]
            assert snapshots[1]['w'] == [1]
            assert snapshots[1]['d'] == [0]
        assert native_programs(path) == [native] * (count + (stem == 'boards-catalog'))
        pdf = PdfReader(path, strict=True)
        host = PdfReader(args.output / f'{reference}.pdf', strict=True)
        assert len(pdf.pages) == len(host.pages) == count
        page_references[stem] = [page.indirect_reference.idnum for page in pdf.pages]
        owners = []
        for page, expected in zip(pdf.pages, host.pages):
            assert page.mediabox == expected.mediabox
            private = page['/PieceInfo']['/Illustrator']['/Private']
            assert private['/AIMetaData'].get_data() == native[:native.index(b'%%EndComments\n') + len(b'%%EndComments\n')]
            owners.append(private.raw_get('/AIPrivateData1'))
        assert all(owner == owners[0] for owner in owners)
        if stem == 'boards-catalog':
            catalog = pdf.trailer['/Root']['/PieceInfo']['/Illustrator']['/Private']
            assert catalog.raw_get('/AIPrivateData1') == owners[0]
            assert catalog['/AIMetaData'].get_data() == native[:native.index(b'%%EndComments\n') + len(b'%%EndComments\n')]
        assert renders(path) == renders(args.output / f'{reference}.pdf'), stem
    assert identities['boards-removed'] == [identities['boards-inserted'][i] for i in (1, 0)]
    assert page_references['boards-removed'] == [page_references['boards-inserted'][i] for i in (1, 0)]
    appearances = verify_appearance_lifecycle(inkai, args.output)
    verify_named_inks(inkai, args.output)
    print(f'Verified {appearances} additional appearance saves: native mask carriers, stable identities, supplied image state, exact PDF pixels and repeated saves.')
    print(f'Verified {len(cases)} Focale AI saves: native contours, image samples, appearances and artboards, retained page identities, shared owners, current headers and exact PDF pixels after repeated edits.')


if __name__ == '__main__':
    main()
