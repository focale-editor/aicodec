#!/usr/bin/env python3
"""Verify complete named appearance trees and literal paint settings independently."""

import argparse
from collections import Counter
import hashlib
import importlib
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION, native_programs
from verify_native_artboard_text import normalized
from verify_native_group_lifecycle import command
from verify_native_structure import native_values, parsed

PRODUCERS = {
    'simple_cc_legacy.ai': (13, 119, 22),
    'simple_v2020.ai': (13, 119, 22),
    'text_transforms.ai': (12, 113, 21),
    'flowtext.ai': (11, 105, 2),
    'gradient_linear.ai': (27, 203, 36),
    'gradient_radial.ai': (21, 167, 30),
}
PARAMETERS = {
    'g': 'fillColor', 'k': 'fillColor', 'Xa': 'fillColor',
    'G': 'strokeColor', 'K': 'strokeColor', 'XA': 'strokeColor',
    'O': 'fillOverprint', 'R': 'strokeOverprint', 'w': 'strokeWidth',
    'J': 'lineCap', 'j': 'lineJoin', 'M': 'miterLimit', 'd': 'dash',
    'XR': 'evenOdd', 'Xd': 'fillStrokeFlags',
}


def check_paint(data, paint, row):
    """Bind each native instruction and compare independent decoded scalar values."""
    assert row['type'] == type(paint).__name__
    fragment, = parsed(data[slice(*row['record'])])
    assert normalized(fragment) == normalized(paint)
    instructions = paint.Paint if row['type'] == 'SimpleStyle' else paint.Def
    assert len(instructions) == len(row['instructions'])
    for item, reported in zip(instructions, row['instructions'], strict=True):
        decoded, = parsed(data[slice(*reported['span'])])
        assert command(decoded)[:2] == command(item)[:2]
        assert row['record'][0] < reported['span'][0] < reported['span'][1] < row['record'][1]
        assert reported['operator'] == item.command
    expected = []
    for index, item in enumerate(instructions):
        if item.command not in PARAMETERS:
            continue
        values = None if item.command == 'd' else list(map(float, item.tokens))
        colors = []
        if PARAMETERS[item.command] in ('fillColor', 'strokeColor'):
            colors = [dict(space='cmyk', channels=values[:4]), dict(space='rgb', channels=values[4:])] if len(values) == 7 else [dict(space={1: 'gray', 3: 'rgb', 4: 'cmyk'}[len(values)], channels=values)]
        expected.append(dict(instruction=index, parameter=PARAMETERS[item.command], numbers=values, colors=colors, dash=dict(lengths=item.dashes, phase=item.phase) if item.command == 'd' else None))
    assert row['assignments'] == expected


def parts(root):
    """Recover the complete source tree from the reader's ordered Part properties."""
    result = []

    def visit(node, parent):
        index = len(result)
        children = []
        result.append((node, parent, children))
        for child in getattr(node, 'Part', []):
            children.append(visit(child, index))
        return index

    visit(root, None)
    return result


def check_part(data, node, parent, children, row):
    """Check hierarchy, hidden nodes, selectors, alignment and effect-local paints."""
    fragment, = parsed(data[slice(*row['record'])])
    assert normalized(fragment) == normalized(node)
    assert (row['parent'], row['children']) == (parent, children)
    name, *flags = node.Filter
    assert row['filter'] == dict(name=list(name.encode('latin1')), flags=flags)
    kind = {
        'Stack Style Filter': 'stack', 'Chain Style Filter': 'chain',
        'Fill Style Filter': 'fill', 'Stroke Style Filter': 'stroke',
        'Blend Style Filter': 'blend', 'Conduit Filter': 'conduit',
        'Adobe Stroke Offset': 'strokeOffset',
    }.get(name, 'effect' if flags == [1, 0] else 'opaque')
    assert row['kind'] == kind
    assert row['visible'] == (None if node.Visible is None else bool(node.Visible))
    assert row['fillOrStroke'] == getattr(node, 'FillOrStroke', None)
    parameters = getattr(node, 'Dict', None) or {}
    assert row['evenOdd'] == (parameters.get('UseEvenOdd') if kind == 'fill' else None)
    inside = parameters.get('StrokeOffsetInside')
    alignment = 'center' if kind == 'stroke' else ('inside' if inside else 'outside') if kind == 'strokeOffset' and inside is not None else None
    assert row['strokeAlignment'] == alignment
    paints = [(key, value) for key, value in parameters.items() if type(value).__name__ in ('FillStyle', 'StrokeStyle', 'BlendStyle')]
    assert [key for key, _ in paints] == [paint['field'] for paint in row['paints']]
    for (_, paint), reported in zip(paints, row['paints'], strict=True):
        check_paint(data, paint, reported)


def verify(inkai, output, row):
    """Inspect all definitions and uses from the untouched complete source program."""
    from inkai.parser.hierarchy_objects import KnownStyle

    path = output / f'{row["source"]}.ps'
    data = path.read_bytes()
    document = inkai.parse(str(path))
    values = list(native_values([document.setup, document.trailer]))
    styles = [value for value in values if isinstance(value, KnownStyle)]
    uses = [value for value in values if getattr(value, 'command', None) == 'XW' and value.tokens[0] in (b'0', b'1') and value.tokens[1]]
    assert len(styles) == len(row['styles'])
    assert Counter((int(use.tokens[0]), use.tokens[1]) for use in uses) == Counter((use['mode'], bytes(use['name'])) for use in row['uses'])
    assert len({tuple(use['span']) for use in row['uses']}) == len(uses)
    for use in row['uses']:
        decoded, = parsed(data[slice(*use['span'])])
        assert decoded.command == 'XW' and decoded.tokens == [str(use['mode']).encode(), bytes(use['name'])]
        candidates = [index for index, style in enumerate(styles) if style.Name.encode('latin1') == bytes(use['name'])]
        assert use['candidates'] == candidates
        assert use['resolution'] == ('resolved' if len(candidates) == 1 else 'missing' if not candidates else 'ambiguous')
    for index, (style, reported) in enumerate(zip(styles, row['styles'], strict=True)):
        fragment, = parsed(data[slice(*reported['record'])])
        assert normalized(fragment) == normalized(style)
        assert bytes(reported['name']) == style.Name.encode('latin1')
        assert reported['definitionType'] == type(style.Def).__name__
        assert reported['uses'] == [ordinal for ordinal, use in enumerate(row['uses']) if index in use['candidates']]
        if type(style.Def).__name__ == 'SimpleStyle':
            assert reported['parts'] == []
            check_paint(data, style.Def, reported['simplePaint'])
        else:
            assert type(style.Def).__name__ == 'ActiveStyle' and reported['simplePaint'] is None
            tree = parts(style.Def.Execution)
            assert len(tree) == len(reported['parts'])
            for (node, parent, children), part in zip(tree, reported['parts'], strict=True):
                check_part(data, node, parent, children, part)
    assert (len(styles), sum(len(style['parts']) for style in row['styles']), len(uses)) == PRODUCERS.get(row['source'], (1, 8, 2))


def main():
    """Require complete fixture provenance and every declared appearance inventory."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/appearances'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(PRODUCERS) + 1 and {row['source'] for row in rows} == {'synthetic', *PRODUCERS}
    assert hashlib.sha256((args.output / 'synthetic.ps').read_bytes()).hexdigest() == '5811098d509fb144ee594903e83cf6a042086ce5bad86bd3d2e3806b7236b341'
    for name in PRODUCERS:
        fixture, entry = Path('test/corpus/files', name), manifest[name]
        assert fixture.stat().st_size == entry['size'] and hashlib.sha256(fixture.read_bytes()).hexdigest() == entry['sha256'] and entry['license'] and entry['revision'] == REVISION
        assert native_programs(fixture) == [(args.output / f'{name}.ps').read_bytes()]
    for row in rows:
        verify(inkai, args.output, row)
        print(row['source'], 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, sources=[row['source'] for row in rows], styles=sum(len(row['styles']) for row in rows), parts=sum(len(style['parts']) for row in rows for style in row['styles']), uses=sum(len(row['uses']) for row in rows)), indent=2) + '\n')


if __name__ == '__main__':
    main()
