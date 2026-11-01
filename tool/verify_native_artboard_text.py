#!/usr/bin/env python3
"""Verify retained producer text independently inside explicit artboard carriers."""

import argparse
import hashlib
import importlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_live_shapes import walk_body
from verify_native_page_saves import native_edit
from verify_native_text import field, resources
from verify_native_group_lifecycle import command

CARRIERS = {
    'simple_cc_legacy.ai': 'a1da186a162f0bad52d83c5f976c091098ac49ba9be523544b7fc27dcdf83b8a',
    'simple_v2020.ai': '3e3b7ae49aee7d1ba8fe7634e277361f8518494869e5f85120949aebd2730257',
    'text_transforms.ai': '9fe7b42d1a85c373187dae3f847c0d5b7f4602c73dedc3c160f4755aaa24432a',
    'flowtext.ai': '2f8fe8eb26ef471aa15e4ceed829dcdff2e3aa146626895212e1245c0bf7e4a3',
    'synthetic-main': '7e6a9ec87819bcd12fefd6d8e6bdddd4e626a4f9ba78a85c195720f5970f932c',
    'synthetic-undo': '1f810674463a07a2172a13f8ca24281db4c7bfff1cb49075e5564505b989d8df',
    'synthetic-pattern': 'af9961c1fd6a372e330654c3693bab3f80eb39c921a17d6f59c55ffc69c2b669',
}


def resource_state(document):
    """Check complete pattern commands/metadata, gradient banks and palette links."""
    patterns = list(document.setup.all_subsections_of_type_recursive(b'%AI3_BeginPattern:'))
    gradients = list(document.setup.all_subsections_of_type_recursive(b'%AI5_BeginGradient:'))
    palette = document.setup.first_subsection_of_type(b'%AI5_BeginPalette')
    gradient_names = {gradient.arguments[0] for gradient in gradients}
    pattern_names = {pattern.arguments[0] for pattern in patterns}
    assert len(gradient_names) == len(gradients) and len(pattern_names) == len(patterns)
    uses = list(walk_body(palette.children)) if palette is not None else []
    for pattern in patterns:
        uses.extend(walk_body(pattern.children))
    for use in uses:
        if getattr(use, 'command', None) == 'Bg':
            assert use.tokens[1] in gradient_names
        elif getattr(use, 'command', None) in ('p', 'P'):
            assert use.tokens[0] in pattern_names
    return dict(
        patterns=[normalized(pattern) for pattern in patterns],
        gradients=[(gradient.arguments, [(command(child), tuple(child.token_is_string)) for child in gradient.children]) for gradient in gradients],
        palette=normalized(palette),
        paths=sum(getattr(child, 'command', None) == 'm' for pattern in patterns for child in walk_body(pattern.children)),
    )


def normalized(value):
    """Retain every independently decoded field, including confinement operators."""
    if isinstance(value, (str, bytes, int, float, bool, type(None))):
        return value
    if isinstance(value, (list, tuple)):
        return [normalized(child) for child in value]
    if isinstance(value, dict):
        return {key: normalized(child) for key, child in value.items()}
    return type(value).__name__, normalized(vars(value))


def text_state(document, text_parser, stream):
    """Bind both exact binary snapshots and every drawing reference independently."""
    section = document.setup.first_subsection_of_type(b'%AI11_BeginTextDocument')
    binaries = [child for child in section.children if type(child).__name__ in ('AI11TextDocument', 'AI11UndoFreeTextDocument')]
    assert [type(child).__name__ for child in binaries] == ['AI11TextDocument', 'AI11UndoFreeTextDocument']
    snapshots = [text_parser.read_object(stream(io.BytesIO(child.Data))) for child in binaries]
    frames = [resources(root, '8', 'TextFrameSet') for root in snapshots]
    stories = [field(field(root, '1', 'DocumentObjects'), '1', 'TextObjects') or [] for root in snapshots]
    bindings = [
        [[field(reference, '0', 'Resource') for reference in field(field(story, '1', 'View'), '0', 'Frames') or []] for story in model]
        for model in stories
    ]
    for model, indices in zip(frames, bindings):
        assert all(0 <= index < len(model) for story in indices for index in story)
    body = list(walk_body(document.trailer))
    drawing = []
    for index, item in enumerate(body):
        if type(item).__name__ != 'AI11Text':
            continue
        assert item.FreeUndo in (0, 1)
        frame = frames[item.FreeUndo][bindings[item.FreeUndo][item.StoryIndex][item.FrameIndex]]
        kind = field(field(frame, '2', 'Data'), '0', 'Type') or 0
        assert kind in (0, 1, 2) and (kind == 0 or item.ConfiningPath is not None)
        metadata = body[index + 1] if index + 1 < len(body) and type(body[index + 1]).__name__ == 'ArtDictionary' else None
        drawing.append((normalized(item), normalized(metadata)))
    return dict(
        payloads=[child.Data for child in binaries],
        origin=normalized(binaries[0].RulerOrigin),
        snapshots=snapshots,
        drawing=drawing,
        counts=[len(stories[0]), len(frames[0]), len(drawing)],
        fonts=[normalized(child) for child in document.setup.children
               if getattr(child, 'command', None) in ('[', 'TE')
               or type(child).__name__ == 'Encoding'
               or isinstance(child, tuple) and child[0] == 'AI55J_Tsume'],
        resources=resource_state(document),
    )


def main():
    """Require producer provenance, all declared edits and exact retained text."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/artboard-text'), type=Path)
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
    assert len(rows) == len(expected) == 28 and {(row['source'], row['operation']) for row in rows} == expected
    originals, states = {}, {}
    for name, checksum in CARRIERS.items():
        original = args.output / f'{name}.original.ps'
        originals[name] = original.read_bytes()
        assert hashlib.sha256(originals[name]).hexdigest() == checksum
        states[name] = text_state(inkai.parse(str(original)), text_parser, stream)
        assert states[name]['counts'] == ([2, 3, 3] if name.startswith('synthetic-') else [10, 16, 16] if name == 'text_transforms.ai' else [1, 1, 1])
        if not name.startswith('synthetic-'):
            assert len(states[name]['resources']['patterns']) == 2
            assert states[name]['resources']['paths'] == (177 if name == 'flowtext.ai' else 102)
            assert len(states[name]['resources']['gradients']) == (20 if name == 'flowtext.ai' else 16)
            assert states[name]['fonts'] and sum(value[0] == 'Encoding' for value in states[name]['fonts']) >= 1
            entry, fixture = manifest[name], Path('test/corpus/files', name)
            assert entry['revision'] == REVISION and fixture.stat().st_size == entry['size']
            assert hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256']
            producer = args.output / f'{name}.producer.ps'
            assert native_programs(fixture) == [producer.read_bytes()]
            font_setup = producer.read_bytes().split(b'%%BeginSetup', 1)[1].split(b'%AI5_Begin_NonPrinting', 1)[0]
            assert font_setup and font_setup in originals[name]
            for section in re.findall(rb'%AI5_Begin_NonPrinting[\s\S]*?%AI5_End_NonPrinting--', producer.read_bytes()):
                if b'%AI5_BeginGradient:' in section or b'%AI3_BeginPattern:' in section:
                    assert section in originals[name]
            palette = re.search(rb'%AI5_BeginPalette[\s\S]*?%AI5_EndPalette', producer.read_bytes()).group()
            assert palette in originals[name]
            assert text_state(inkai.parse(str(producer)), text_parser, stream) == states[name]
    checked = []
    for row in rows:
        name, operation = row['source'], row['operation']
        target = args.output / f'{name}.{operation}.ps'
        native_edit(originals[name], target.read_bytes(), dict(row, fixture=None))
        assert text_state(inkai.parse(str(target)), text_parser, stream) == states[name]
        checked.append(f'{name}/{operation}')
        print(checked[-1], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, transactions=checked, producerTextCarriers=4, syntheticCarriers=3), indent=2) + '\n')


if __name__ == '__main__':
    main()
