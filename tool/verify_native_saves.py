#!/usr/bin/env python3
"""Verify saved native programs, selected edits and retained PDF data independently."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from pypdf import PdfReader
from pypdf.generic import ArrayObject, DictionaryObject, IndirectObject, StreamObject

from corpus_support import REVISION, native_programs
from verify_native_capabilities import owners


def stream_data(item):
    """Honor explicit empty streams despite pypdf 3.x's zero-length fallback."""
    data = item.get_data()
    if not item and data.strip() == b'':
        reference = item.indirect_reference
        reader = reference.pdf
        offset = reader.xref[reference.generation][reference.idnum]
        position = reader.stream.tell()
        try:
            reader.stream.seek(offset)
            header = reader.stream.read(256)
        finally:
            reader.stream.seek(position)
        # That reader treats Length 0 as unknown and includes the separator EOL.
        # Correct only this explicit empty dictionary; retain real whitespace data.
        if re.match(rb'\d+\s+\d+\s+obj\s*<<\s*/Length\s+0\s*>>\s*stream[\r\n]', header):
            return b''
    return data


def value(item, depth=0):
    """Compare resolved immutable metadata rather than arbitrary PDF object IDs."""
    assert depth < 128
    if isinstance(item, IndirectObject):
        return value(item.get_object(), depth + 1)
    if isinstance(item, StreamObject):
        return (stream_data(item), {key: value(child, depth + 1) for key, child in item.items() if key not in ('/Length', '/Filter', '/DecodeParms')})
    if isinstance(item, DictionaryObject):
        return {key: value(child, depth + 1) for key, child in item.items()}
    if isinstance(item, ArrayObject):
        return [value(child, depth + 1) for child in item]
    return item


def metadata(owner):
    """Exclude replaced native streams and their count, retaining opaque fields."""
    pieces = owner.get('/PieceInfo')
    if pieces is None:
        return None
    result = {}
    for name, producer in pieces.get_object().items():
        if name != '/Illustrator':
            result[name] = value(producer)
            continue
        result[name] = {}
        for key, field in producer.get_object().items():
            if key != '/Private':
                result[name][key] = value(field)
            else:
                result[name][key] = {
                    child: value(data) for child, data in field.get_object().items()
                    if child != '/NumBlock' and not re.fullmatch(r'/(?:AIPrivateData|AIPDFPrivateData)\d+', child)
                }
    return result


def main():
    """Require all pinned PDF inputs plus two synthetic multi-program saves."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/native-saves'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    native_parser = importlib.import_module('inkai.parser.fileparser')
    manifest = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    expected = set()
    for entry in manifest:
        original = (Path('test/corpus/files') / entry['file']).read_bytes()
        assert len(original) == entry['size'] and hashlib.sha256(original).hexdigest() == entry['sha256']
        if original.startswith(b'%PDF-'):
            expected.add(entry['file'])
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(expected) + 2
    assert {row['file'] for row in rows} == expected | {'synthetic-batch', 'synthetic-selected'}
    checked = 0
    for row in rows:
        name = row['file']
        original = args.output / f'{name}.original.ai' if row['synthetic'] else Path('test/corpus/files') / name
        saved = args.output / f'{name}.saved.ai'
        before = PdfReader(original)
        after = PdfReader(saved)
        assert len(before.pages) == len(after.pages)
        for first, second in zip([before.trailer['/Root'], *before.pages], [after.trailer['/Root'], *after.pages]):
            assert metadata(first) == metadata(second), name
        for index, (first, second) in enumerate(zip(before.pages, after.pages)):
            assert first.get_contents().get_data() == second.get_contents().get_data(), name
            old_resources = value(first['/Resources'])
            new_resources = value(second['/Resources'])
            if index == 0:
                added = new_resources['/XObject'].pop('/' + row['resource'])
                assert added[0] == b'q Q' and added[1]['/Subtype'] == '/Form'
                if '/XObject' not in old_resources and not new_resources['/XObject']:
                    new_resources.pop('/XObject')
            assert old_resources == new_resources, name
        original_owners = owners(original)
        saved_owners = owners(saved)
        assert original_owners == saved_owners
        old_programs = dict(zip(original_owners, native_programs(original)))
        new_programs = dict(zip(saved_owners, native_programs(saved)))
        assert sorted(str(owner) for item in row['programs'] for owner in item['owners']) == sorted(str(owner) for owner in original_owners)
        for item in row['programs']:
            first = (args.output / f'{item["prefix"]}.before.ps').read_bytes()
            second = (args.output / f'{item["prefix"]}.after.ps').read_bytes()
            for owner in item['owners']:
                assert old_programs[owner] == first and new_programs[owner] == second, (name, owner)
            if item['renamed']:
                assert first[:item['oldNameStart']] == second[:item['newNameStart']]
                assert first[item['oldNameEnd']:] == second[item['newNameEnd']:]
                parsed = native_parser.parse_bytes(second[item['newNameStart']:item['newNameEnd']] + b'\n', native_parser.FileParser.read_many_objects)
                assert len(parsed) == 1 and parsed[0].command == 'Ln' and parsed[0].tokens == [b'Saved layer']
            else:
                assert first == second
            checked += 1
    result = {'oracleRevision': REVISION, 'pinnedPdfFiles': len(expected), 'syntheticSaves': 2, 'programs': checked}
    (args.output / 'independent-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Native saves: {len(expected)} pinned PDFs, two multi-program saves and {checked} exact native programs passed')


if __name__ == '__main__':
    main()
