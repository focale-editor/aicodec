#!/usr/bin/env python3
"""Verify explicit native/PDF page mappings, supplied artwork and preserved owners."""

import argparse
from copy import deepcopy
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from pypdf import PdfReader

from corpus_support import REVISION, native_programs
from verify_native_artboards import inventory
from verify_native_artboard_lifecycle import new_board
from verify_native_capabilities import owners
from verify_native_metadata_headers import header, without_fonts
from verify_native_path_lifecycle import patch
from verify_native_reference_scope import values
from verify_native_saves import metadata, value
from verify_native_structure import parsed

SYNTHETIC = {
    'boards': 'ef4416bd2d09a0d61b49af50c1eeda95127d0d3f0ffb095294d176b1cdbebef3',
    'programs': '73ea1b539112eb9ddab409288d2bc60a8f51e5e27e23ae3cfd6037f55d4128c7',
}
REAL = ['simple_cc_legacy.ai', 'simple_v2020_no_pdf_data.ai', 'reuters-preview-dev.ai']


def native_document(data, reported):
    """Bind the independently decoded Document to its unique private setup opener."""
    setup_end = data.index(b'%%EndSetup')
    declarations = list(re.finditer(rb'(?:^|(?<=[\r\n]))%_(/Document\s*:)', data[:setup_end]))
    assert len(declarations) == 1 and declarations[0].start(1) == reported['document'][0]
    decoded = parsed(data[slice(*reported['document'])])
    assert len(decoded) == 1
    result = values(decoded[0])
    inventory(data, result, reported)
    return result


def native_edit(before, after, row):
    """Require the prescribed native edit and exact unselected source bytes."""
    if 'before' not in row:
        assert before == after
        return
    original = native_document(before, row['before'])
    changed = native_document(after, row['after'])
    expected = deepcopy(original)
    boards = expected['Recorded']['ArtboardArray']
    action = row['operation']
    if action == 'none':
        assert before == after and row['before'] == row['after']
        return
    if action == 'create':
        boards.insert(1, new_board(False))
        expected['Recorded']['CropAreaActive'] = 3
        expected['NotRecorded']['LastArtboardID'] = 68
    elif action == 'remove':
        boards.pop(2)
        expected['Recorded']['CropAreaActive'] = 1
    elif action == 'reorder':
        expected['Recorded']['ArtboardArray'] = [boards[2], boards[0], boards[1]]
        expected['Recorded']['CropAreaActive'] = 0
    elif action == 'resize':
        boards[0]['PositionPoint1'] = [-10, 800]
        boards[0]['PositionPoint2'] = [500, -20]
    else:
        raise AssertionError(action)
    assert changed == expected
    edits = []
    if action == 'resize':
        for field in ('PositionPoint1', 'PositionPoint2'):
            for old, new in zip(row['before']['boards'][0]['coordinates'][field], row['after']['boards'][0]['coordinates'][field]):
                edits.append((*old, after[slice(*new)]))
    else:
        edits.append((*row['before']['array'], after[slice(*row['after']['array'])]))
        for field in ('active', 'lastId'):
            if row['before'][field] != row['after'][field]:
                edits.append((*row['before'][field + 'Span'], after[slice(*row['after'][field + 'Span'])]))
    if action == 'create':
        assert row['after']['crop'] == [-10, -20, 30, 40]
        edits.append((*row['before']['cropSpan'], after[slice(*row['after']['cropSpan'])]))
    assert patch(before, edits) == after


def stripped_metadata(owner, native_header=None):
    """Compare all private data except rewritten blocks and qualified cache bytes."""
    result = metadata(owner)
    if result and '/Illustrator' in result and '/Private' in result['/Illustrator']:
        private = result['/Illustrator']['/Private']
        if '/AIMetaData' in private:
            cache, attributes = private['/AIMetaData']
            if native_header is not None:
                assert cache in (native_header, without_fonts(native_header))
            private['/AIMetaData'] = attributes
    return result


def verify(original, target, host_path, row, output):
    """Bind source metadata templates and program aliases to actual final pages."""
    before, after, host = PdfReader(original), PdfReader(target), PdfReader(host_path)
    old_indices = {page.indirect_reference.idnum: index for index, page in enumerate(before.pages)}
    assert len(after.pages) == len(host.pages) == len(row['appearances'])
    assert [(page.indirect_reference.idnum, page.indirect_reference.generation) for page in after.pages] == [(page.indirect_reference.idnum, page.indirect_reference.generation) for page in host.pages]
    old_owners = owners(original)
    old_programs = dict(zip(old_owners, native_programs(original)))
    assert sorted(map(str, old_owners)) == sorted(str(owner) for program in row['programs'] for owner in program['owners'])
    actual_programs = dict(zip(owners(target), native_programs(target)))
    expected_programs, templates = {}, {}
    for index, program in enumerate(row['programs']):
        source = (output / f'{row["name"]}.{index}.before.ps').read_bytes()
        changed = (output / f'{row["name"]}.{index}.after.ps').read_bytes()
        for owner in program['owners']:
            assert old_programs[owner] == source
        native_edit(source, changed, row if index == 0 else {'operation': 'none'})
        if program['selected']:
            if None in program['owners']:
                expected_programs[None], templates[None] = changed, None
            indices = [entry['index'] for entry in program['pages']]
            assert indices == sorted(set(indices))
            if len(row['programs']) == 1:
                assert indices == list(range(len(row['after']['boards'])))
            for entry in program['pages']:
                assert entry['metadataOwner'] in program['owners']
                assert entry['index'] not in expected_programs
                expected_programs[entry['index']], templates[entry['index']] = changed, entry['metadataOwner']
        else:
            assert not program['pages'] and source == changed
            for owner in program['owners']:
                target_index = None if owner is None else next(index for index, page in enumerate(after.pages) if page.indirect_reference.idnum == before.pages[owner].indirect_reference.idnum)
                expected_programs[target_index], templates[target_index] = source, owner
    assert actual_programs == expected_programs
    for owner, source_owner in templates.items():
        source = before.trailer['/Root'] if source_owner is None else before.pages[source_owner]
        destination = after.trailer['/Root'] if owner is None else after.pages[owner]
        supplied = host.trailer['/Root'] if owner is None else host.pages[owner]
        expected = stripped_metadata(source, header(old_programs[source_owner]))['/Illustrator']
        actual = stripped_metadata(destination, header(expected_programs[owner]))
        assert actual.pop('/Illustrator') == expected
        supplied_metadata = metadata(supplied) or {}
        supplied_metadata.pop('/Illustrator', None)
        assert actual == supplied_metadata
    for index, page in enumerate(after.pages):
        supplied = host.pages[index]
        assert {key: value(child) for key, child in page.items() if key not in ('/Parent', '/PieceInfo')} == {key: value(child) for key, child in supplied.items() if key not in ('/Parent', '/PieceInfo')}
        source_index = row['appearances'][index]
        if source_index is not None:
            source = before.pages[source_index]
            assert page.get_contents().get_data() == source.get_contents().get_data()
            assert value(page['/Resources']) == value(source['/Resources'])
            if row['operation'] != 'resize' or index != 0:
                assert list(page.mediabox) == list(source.mediabox)
        else:
            wanted = b'0.5 g 0 0 30 40 re f' if row['operation'] == 'create' else b'q Q'
            assert page.get_contents().get_data() == wanted
            assert list(page.mediabox) == ([0, 0, 504, 804] if row['operation'] == 'create' else [0, 0, 220, 140])
        if row['fixture'] and index == 0 or source_index is None:
            assert page.indirect_reference.idnum not in old_indices
        else:
            assert old_indices[page.indirect_reference.idnum] == source_index
    if row['operation'] == 'resize':
        assert list(after.pages[0].mediabox) == [0, 0, 540, 840]
    assert {key: value(child) for key, child in after.trailer['/Root'].items() if key not in ('/Pages', '/PieceInfo')} == {key: value(child) for key, child in host.trailer['/Root'].items() if key not in ('/Pages', '/PieceInfo')}


def main():
    """Require three pinned real graphs and every declared native lifecycle save."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/page-saves'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    importlib.import_module('inkai')
    entries = json.loads(Path('test/corpus/manifest.json').read_text())['files'] + json.loads(Path('test/corpus/artboard_manifest.json').read_text())['files']
    manifest = {entry['file']: entry for entry in entries}
    expected = {name: ('none', list(range(5 if name.startswith('reuters-') else 1))) for name in REAL}
    expected.update({f'synthetic-{action}': (action, appearances) for action, appearances in [('create', [0, None, 1, 2]), ('remove', [0, 1]), ('reorder', [2, 0, 1]), ('resize', [0, 1, 2])]})
    expected.update({f'synthetic-{mode}': ('none', [0, 1, None]) for mode in ('selected', 'batch')})
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) == 9 and {row['name'] for row in rows} == expected.keys()
    for row in rows:
        name = row['name']
        assert (row['operation'], row['appearances']) == expected[name]
        assert row['fixture'] == (name if name in REAL else None)
        multiple = name in ('synthetic-selected', 'synthetic-batch')
        assert [program['selected'] for program in row['programs']] == ([True, name.endswith('batch')] if multiple else [True])
        if multiple:
            assert row['programs'][0]['pages'] == [{'index': 0, 'metadataOwner': 0}, {'index': 2, 'metadataOwner': None}]
            assert row['programs'][1]['pages'] == ([{'index': 1, 'metadataOwner': 1}] if name.endswith('batch') else [])
        else:
            assert row['programs'][0]['pages'] == [{'index': index, 'metadataOwner': owner} for index, owner in enumerate(row['appearances'])]
        original = Path('test/corpus/files', name) if name in REAL else args.output / f'{name}.original.ai'
        data = original.read_bytes()
        if name in REAL:
            assert len(data) == manifest[name]['size'] and hashlib.sha256(data).hexdigest() == manifest[name]['sha256']
        else:
            assert hashlib.sha256(data).hexdigest() == SYNTHETIC['programs' if multiple else 'boards']
        verify(original, args.output / f'{name}.saved.ai', args.output / f'{name}.host.pdf', row, args.output)
        print(name, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, realPageReplacements=3, nativeLifecycleSaves=4, multipleProgramSaves=2), indent=2) + '\n')


if __name__ == '__main__':
    main()
