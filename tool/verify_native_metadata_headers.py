#!/usr/bin/env python3
"""Verify cached headers, exact native edits and retained PDF graphs independently."""

import argparse
import hashlib
import json
from pathlib import Path
import re

from pypdf import PdfReader

from corpus_support import native_programs
from verify_native_capabilities import owners
from verify_native_saves import metadata, value

SYNTHETIC_SHA256 = '0f13e2851889d5aec3f56bd5f108e6ffc66ac37bc8e0cf5e3cade095896ed02b'
UNQUALIFIED = {
    'inkscape_minimized_ai9.ai', 'inkscape_minimized_ai10.ai',
    'inkscape_minimized_ai_cs.ai', 'inkscape_minimized_ai_cs2.ai',
    'inkscape_minimized_ai_cs3.ai', 'empty_cs.ai', 'empty_cs2.ai',
    'simple_cs.ai', 'simple_cs2.ai', 'simple_cs3.ai',
}


def header(program):
    """Extract the initial header independently using its physical DSC terminator."""
    ending = re.search(rb'(?:^|(?<=[\r\n]))%%EndComments(?:\r\n|\r|\n|$)', program)
    assert ending and program.startswith(b'%!PS-Adobe-')
    return program[:ending.end()]


def without_fonts(data):
    """Remove complete font declaration comments, retaining other continuations."""
    return re.sub(
        rb'(?:^|(?<=[\r\n]))%%Document(?:Needed)?Fonts:[^\r\n]*(?:\r\n|\r|\n)'
        rb'(?:%%\+[^\r\n]*(?:\r\n|\r|\n))*', b'', data,
    )


def changed_creator(program):
    """Require one exact nonvisual edit and preserve the entire native body."""
    original = header(program)
    changed, count = re.subn(rb'(?:^|(?<=[\r\n]))%%Creator:[^\r\n]*', b'%%Creator: AiKit cache validation', original)
    assert count == 1
    return changed + program[len(original):]


def private(owner):
    """Resolve the private dictionary without guessing page-to-artboard mappings."""
    pieces = owner.get('/PieceInfo')
    illustrator = pieces.get_object().get('/Illustrator') if pieces else None
    result = illustrator.get_object().get('/Private') if illustrator else None
    return result.get_object() if result is not None else None


def verify(original, saved, row, output):
    """Check all cache owners, programs, content, resources and unrelated metadata."""
    before = PdfReader(original)
    old_owners = owners(original)
    old_programs = dict(zip(old_owners, native_programs(original)))
    assert sorted(map(str, old_owners)) == sorted(str(owner) for group in row['owners'] for owner in group)
    new_programs = {}
    for index, group in enumerate(row['owners']):
        source = (output / f'{row["file"]}.{index}.before.ps').read_bytes()
        target = (output / f'{row["file"]}.{index}.after.ps').read_bytes()
        selected = not row['firstOnly'] or index == 0
        assert target == (changed_creator(source) if selected else source)
        for owner in group:
            assert old_programs[owner] == source
            new_programs[owner] = target
    if row['rejected']:
        # Independently establish a real divergent source cache, not just an exception.
        assert any(
            owner.get('/PieceInfo') and private(owner) and '/AIMetaData' in private(owner)
            and private(owner)['/AIMetaData'].get_data() not in (header(old_programs[index]), without_fonts(header(old_programs[index])))
            for index, owner in [(None, before.trailer['/Root']), *enumerate(before.pages)]
            if index in old_programs
        )
        return 0
    after = PdfReader(saved)
    assert old_owners == owners(saved)
    assert dict(zip(owners(saved), native_programs(saved))) == new_programs
    assert len(before.pages) == len(after.pages)
    updated = 0
    for index, first, second in zip([None, *range(len(before.pages))], [before.trailer['/Root'], *before.pages], [after.trailer['/Root'], *after.pages]):
        old_metadata, new_metadata = metadata(first), metadata(second)
        first_private, second_private = private(first), private(second)
        if first_private and '/AIMetaData' in first_private:
            cache = first_private['/AIMetaData'].get_data()
            next_cache = second_private['/AIMetaData'].get_data()
            old_header, new_header = header(old_programs[index]), header(new_programs[index])
            if old_header == new_header:
                assert cache == next_cache
            elif cache == old_header:
                assert next_cache == new_header
                updated += 1
            else:
                assert cache == without_fonts(old_header) and next_cache == without_fonts(new_header)
                updated += 1
            old_cache = old_metadata['/Illustrator']['/Private'].pop('/AIMetaData')
            new_cache = new_metadata['/Illustrator']['/Private'].pop('/AIMetaData')
            assert old_cache[1] == new_cache[1], 'Changed unrelated cache stream attributes'
        assert old_metadata == new_metadata
        if index is not None:
            assert first.get_contents().get_data() == second.get_contents().get_data()
            assert value(first['/Resources']) == value(second['/Resources'])
            excluded = {'/Parent', '/Contents', '/Resources', '/PieceInfo'}
        else:
            excluded = {'/Pages', '/PieceInfo'}
        assert {key: value(child) for key, child in first.items() if key not in excluded} == {key: value(child) for key, child in second.items() if key not in excluded}
    if row['file'] == 'reuters-preview-dev.ai':
        assert len(before.pages) == 5 and row['owners'] == [[0, 1, 2, 3, 4]]
        references = [private(page).raw_get('/AIMetaData').idnum for page in after.pages]
        assert len(set(references)) == 1
    return updated


def main():
    """Require every pinned success, explicit old-profile refusal and synthetic save."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=Path('test/corpus/output/metadata-headers'), type=Path)
    args = parser.parse_args()
    entries = json.loads(Path('test/corpus/manifest.json').read_text())['files']
    entries += [entry for entry in json.loads(Path('test/corpus/artboard_manifest.json').read_text())['files'] if entry['file'] == 'reuters-preview-dev.ai']
    manifest = {entry['file']: entry for entry in entries if Path('test/corpus/files', entry['file']).read_bytes().startswith(b'%PDF-')}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(manifest) == 32 and len(rows) == 34
    assert {row['file'] for row in rows} == manifest.keys() | {'synthetic-batch', 'synthetic-selected'}
    updated = 0
    for row in rows:
        name = row['file']
        assert row['synthetic'] == name.startswith('synthetic-')
        assert row['firstOnly'] == (name == 'synthetic-selected')
        assert row['rejected'] == (name in UNQUALIFIED) and bool(row['issue']) == row['rejected']
        original = args.output / f'{name}.original.ai' if row['synthetic'] else Path('test/corpus/files', name)
        data = original.read_bytes()
        if row['synthetic']:
            assert hashlib.sha256(data).hexdigest() == SYNTHETIC_SHA256
        else:
            assert len(data) == manifest[name]['size'] and hashlib.sha256(data).hexdigest() == manifest[name]['sha256']
        updated += verify(original, args.output / f'{name}.saved.ai', row, args.output)
        print(name, 'passed', flush=True)
    assert updated == 31
    (args.output / 'independent-report.json').write_text(json.dumps(dict(pinnedPdfs=32, updatedRealFiles=22, unqualifiedProfiles=10, syntheticSaves=2, updatedOwnerCaches=updated), indent=2) + '\n')


if __name__ == '__main__':
    main()
