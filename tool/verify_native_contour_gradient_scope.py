#!/usr/bin/env python3
"""Verify isolated ordinary edits beside retained gradient data and state barriers."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import io
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_native_clipping_lifecycle import prolog
from verify_native_contour_group_movement import verify as verify_groups
from verify_native_contour_movement import verify as verify_contours
from verify_native_gradients import gradient_instances
from verify_native_group_lifecycle import command
from verify_native_path_topology import verify as verify_geometry
from verify_native_structure import parsed

SOURCES = {
    'legacy': '1cd859fe22f084c2a7d214c36bfec73364d92b412ce4c09a8634887b89bf11ec',
    'relative': '8ae9675adf750d6d06d338d13d426f11d39ee75cf8d5042c2ccf2c301200d057',
    'preceding': 'ee14f2d981360b97d61fe3f2102c610ad65f7b110f1a00196bde263fec1c1378',
    'shared': '21d471f6032cb34137ede4d2393f69e0a275651002e8ad8a0e1249ea6b194b9c',
    'unknown': '3e105160454e5063a237e7c0f642976e9d8fb7e2b96b3abe27e671464db22a74',
}
PRODUCERS = ('gradient_linear.ai', 'gradient_radial.ai')
GRADIENT_COMMANDS = {'Bb', 'BB', 'Bg', 'Bh', 'Xm', 'Bm', 'Bc'}


def contour_spans(data, report):
    """Separate independently parsed gradient commands from path mask controls."""
    result = deepcopy(report)
    for path in result['paths']:
        controls = []
        for span in path['controls']:
            item, = parsed(data[slice(*span)])
            if getattr(item, 'command', None) not in GRADIENT_COMMANDS:
                controls.append(span)
        path['controls'] = controls
    return result


def verify(inkai, output, row, prefix):
    """Prescribe every operation and verify retained resources and complete source."""
    name, variant = row['source'], row['variant']
    original_file, result_file = output / f'{name}.original.ps', output / f'{name}.{variant}.ps'
    before, after = original_file.read_bytes(), result_file.read_bytes()
    if name in PRODUCERS or name == 'unknown' and variant != 'geometry':
        expected = 'Artboard text isolation requires the qualified compact ATE version.' if name in PRODUCERS else 'Contour movement cannot restore unknown outgoing appearance values.' if variant == 'move' else 'Contour edits cannot restore unknown final attributes.'
        assert row['error'] == expected and before == after and row['before'] == row['after']
        if name in PRODUCERS:
            document = inkai.parse(str(original_file))
            section = document.setup.first_subsection_of_type(b'%AI11_BeginTextDocument')
            binaries = [child for child in section.children if type(child).__name__ in ('AI11TextDocument', 'AI11UndoFreeTextDocument')]
            text_parser = importlib.import_module('inkai.parser.text').TextDocumentParser
            stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
            assert len(binaries) == 2
            for binary in binaries:
                engine = text_parser.read_object(stream(io.BytesIO(binary.Data)))
                assert engine['/98']['/0'] == 11
                assert not engine['/0'].get('/8', {}).get('/0') and not engine['/1'].get('/1')
        return
    assert row['error'] is None
    original_doc, actual_doc = inkai.parse(str(original_file)), inkai.parse(str(result_file))
    original_gradients, actual_gradients = gradient_instances(original_doc), gradient_instances(actual_doc)
    expected_instances = 2 if name == 'shared' else 1
    assert len(original_gradients) == len(actual_gradients) == expected_instances
    assert list(original_doc.setup.gradients) == list(actual_doc.setup.gradients) == ['path_target']
    assert repr(original_doc.setup.gradients['path_target'].children) == repr(actual_doc.setup.gradients['path_target'].children)
    for original, actual in zip(original_gradients, actual_gradients, strict=True):
        assert [command(item) for item in original] == [command(item) for item in actual]
        geometry = next(item for item in original if item.command == 'Bg')
        assert geometry.name == 'path_target'
    previous = contour_spans(before, row['before'])
    current = contour_spans(after, row['after'])
    if variant == 'geometry':
        verify_geometry(inkai, output, dict(source=name, variant=variant, original=original_file.name, result=result_file.name, before=previous['paths'], after=current['paths']), ('original', [0], [], None))
    elif variant == 'move':
        verify_contours(inkai, output, dict(source=name, variant=variant, before=previous['paths'], after=current['paths'], beforeGroups=previous['groups'], afterGroups=current['groups']), ([0], 1, None, None, False), prefix)
    else:
        assert variant == 'group'
        verify_groups(inkai, output, dict(source=name, variant=variant, before=previous, after=current), ('original', [0], 1, None), prefix)


def main():
    """Require thirteen accepted transactions and four exact conservative refusals."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/contour-gradient-scope'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    for name, checksum in SOURCES.items():
        assert hashlib.sha256((args.output / f'{name}.original.ps').read_bytes()).hexdigest() == checksum
    for name in PRODUCERS:
        fixture, entry = Path('test/corpus/files', name), manifest[name]
        assert fixture.stat().st_size == entry['size'] and hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256'] and entry['revision'] == REVISION and entry['license']
        assert native_programs(fixture) == [(args.output / f'{name}.original.ps').read_bytes()]
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {(name, variant) for name in SOURCES for variant in ('geometry', 'move', 'group')} | {(name, 'geometry') for name in PRODUCERS}
    assert len(rows) == len(expected) == 17 and {(row['source'], row['variant']) for row in rows} == expected
    prefix = prolog()
    for row in rows:
        verify(inkai, args.output, row, prefix)
        print(row['source'], row['variant'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=[f'{row["source"]}/{row["variant"]}' for row in rows], accepted=13, refused=4, producerRefusals=2, ordinaryStateProjections=16, ghostscript=subprocess.check_output(['gs', '--version'], text=True).strip()), indent=2) + '\n')


if __name__ == '__main__':
    main()
