#!/usr/bin/env python3
"""Verify complete brush artwork and both image planes after artboard edits."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_artboard_styles import appearance_state, panel, styles
from verify_native_artboard_symbols import symbols
from verify_native_artboard_text import normalized, text_state
from verify_native_page_saves import native_edit

CARRIERS = {
    'simple_cc_legacy.ai': '3c475746f0d37bd21afd6eb0dcbcce017fbb54ace8c03cbe4800889e464582f2',
    'simple_v2020.ai': 'c4c5e868d4acb29cb3e5a23982b67e218e3d17104ec67f252c721b6b555f9875',
    'text_transforms.ai': '56f545f791be597479d0a3b34939bfac20b0aa7697f82e132e761cb2959a20f9',
    'flowtext.ai': '4342faf1ce919cb16b0a08ca11facedd224a3944588ccc3f991e57fc7c0da8b9',
    'synthetic-brush': '0b207b30d3223f2366032047fb8e925dcb7b2ca51000bbfe02b21f3bc1e6b1ab',
}


def brush_sections(document):
    """Bind complete independent brush definitions to their literal names."""
    result = {}
    for section in document.setup.all_subsections_of_type_recursive(b'%AI8_BeginBrushPattern'):
        first = section.children[0]
        assert first.command == 'A' and first.token_is_string == [True, False]
        name = first.tokens[0]
        assert name not in result
        result[name] = section
    return result


def image_planes(section, images):
    """Read full sample planes by geometry, complementing the oracle's whitespace loss."""
    result, cursor = [], 0
    for image in images:
        opening = section.index(b'%AI5_BeginRaster', cursor)
        header = re.search(rb'%%BeginData: (\d+)\r?\n(XI\r?\n)', section[opening:])
        assert header is not None
        start = opening + header.end()
        assert image.bits == 8 and image.is_binary == 1 and image.alpha_channel_count == 1
        assert image.h > 0 and image.w > 0 and image.image_type in (3, 4)
        assert image.reserved == (17 if image.image_type == 3 else 18)
        color_size, alpha_size = image.h * image.w * image.image_type, image.h * image.w
        end = start + color_size + alpha_size
        assert end <= len(section)
        closing = re.match(rb'(?:\r\n?|\n)?%%EndData(?:\r\n?|\n)XH(?:\r\n?|\n)%AI5_EndRaster', section[end:])
        assert closing is not None
        declared, prefix = int(header[1]), len(header[2])
        assert declared == image.data.length
        assert declared in {prefix + color_size, prefix + color_size + 1, prefix + color_size + alpha_size, prefix + color_size + alpha_size + 1}
        colors, alpha = section[start:start + color_size], section[start + color_size:end]
        decoded = image.data.raw + image.data.additional
        # The pinned reader discards the leading ASCII-space byte of flowtext's RGB data.
        assert decoded == colors + alpha or colors[0] == 32 and decoded == colors[1:] + alpha
        result.append((image.h, image.w, image.image_type, colors, alpha))
        cursor = end + closing.end()
    assert b'%AI5_BeginRaster' not in section[cursor:]
    return result


def brush_state(document, data):
    """Preserve all geometry, placement, metadata and independently bounded samples."""
    sections = brush_sections(document)
    # These complete byte sections come only from checksum-pinned corpus programs.
    spans = re.findall(rb'%AI8_BeginBrushPattern[\s\S]*?%AI8_EndBrushPattern', data)
    assert len(spans) == len(sections)
    planes = []
    for section, span in zip(sections.values(), spans):
        images = [item for item in walk_body(section.children) if getattr(item, 'command', None) == 'XI']
        planes.extend(image_planes(span, images))
    return dict(definitions={name: normalized(section) for name, section in sections.items()}, planes=planes)


def main():
    """Require pinned producers and all twenty complete native edit transactions."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-brushes'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    text_parser = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    expected = {(name, operation) for name in CARRIERS for operation in ('create', 'resize', 'reorder', 'remove')}
    assert len(rows) == len(expected) == 20 and {(row['source'], row['operation']) for row in rows} == expected
    originals, states, texts, appearances = {}, {}, {}, {}
    for name, checksum in CARRIERS.items():
        original = args.output / f'{name}.original.ps'
        originals[name] = original.read_bytes()
        assert hashlib.sha256(originals[name]).hexdigest() == checksum
        document = inkai.parse(str(original))
        states[name] = brush_state(document, originals[name])
        assert len(states[name]['definitions']) == (1 if name == 'synthetic-brush' else 5 if name == 'flowtext.ai' else 4)
        image_sizes = [(width, height, components, len(colors), len(alpha)) for width, height, components, colors, alpha in states[name]['planes']]
        assert image_sizes == ([(2, 1, 4, 8, 2)] if name == 'synthetic-brush' else [(201, 106, 3, 63918, 21306)] * 5 if name == 'flowtext.ai' else [(168, 62, 4, 41664, 10416)] * 5)
        if name == 'synthetic-brush':
            continue
        entry, fixture = manifest[name], Path('test/corpus/files', name)
        assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
        assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
        producer = args.output / f'{name}.producer.ps'
        assert native_programs(fixture) == [producer.read_bytes()]
        source = inkai.parse(str(producer))
        assert brush_state(source, producer.read_bytes()) == states[name]
        copied = re.findall(rb'%AI8_BeginBrushPattern[\s\S]*?%AI8_EndBrushPattern', originals[name])
        assert all(section in producer.read_bytes() for section in copied)
        texts[name] = text_state(source, text_parser, stream)
        assert text_state(document, text_parser, stream) == texts[name]
        appearances[name] = appearance_state(document)
        assert {key: normalized(value) for key, value in styles(source).items() if key != b'Chrome Highlight'} == appearances[name]['styles']
        assert {key: normalized(value) for key, value in symbols(source).items() if key != b'Band'} == appearances[name]['symbols']
        if name != 'flowtext.ai':
            assert normalized(panel(source)) == appearances[name]['inventory']
    checked = []
    for row in rows:
        name, operation = row['source'], row['operation']
        target = args.output / f'{name}.{operation}.ps'
        data = target.read_bytes()
        native_edit(originals[name], data, dict(row, fixture=None))
        document = inkai.parse(str(target))
        assert brush_state(document, data) == states[name]
        if name in texts:
            assert text_state(document, text_parser, stream) == texts[name]
            assert appearance_state(document) == appearances[name]
        checked.append(f'{name}/{operation}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, producerBrushDefinitions=17, producerBrushRasters=20), indent=2) + '\n')


if __name__ == '__main__':
    main()
