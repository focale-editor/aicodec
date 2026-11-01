#!/usr/bin/env python3
"""Verify child style edits, complete printing owners and local native state."""

import argparse
import hashlib
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys

from corpus_support import REVISION
from verify_live_shapes import walk_body
from verify_native_appearance_edits import GROUP, replace_once, string
from verify_native_appearance_graphs import NEW_FILL, patch
from verify_native_appearance_groups import fragment, owners
from verify_native_appearance_nested_styles import SOURCES as RETAINED
from verify_native_appearances import verify
from verify_native_artboard_text import normalized
from verify_native_group_lifecycle import command

SOURCES = {
    **{variant: RETAINED['selected'] for variant in ('path', 'group', 'both', 'shared')},
    **{variant: RETAINED[variant] for variant in ('simple-selected', 'simple-shared', 'compound-selected', 'compound-shared')},
    **{variant: 'fadfaab5dda28d6aea09524c1d010b585ac83324e4925ca391c76495eb7a62ad' for variant in ('restored-selected', 'restored-shared')},
    'outer-shared': 'b69a3fde1a54c2974469d9c17f40cd80b9577dce3ba4e2f07165b50126bddfc5',
    'create': '254a352f379214b6b7f20c302de80db8aa042be4be24e11c5f2d42a9b9250452',
}


def created_style(data, style):
    """Prescribe a cyan fill before the complete original stack children."""
    stack = style['parts'][1]
    assert stack['kind'] == 'stack' and stack['children'] == [2, 3, 4, 5]
    fill = NEW_FILL.replace(b'1.0 0.0 0.0 0.0 0.0 1.0 1.0 Xa', b'0.0 1.0 1.0 Xa')
    children = [style['parts'][index]['record'] for index in stack['children']]
    first, last = style['record']
    insertion = children[0][0] - first
    edits = [(insertion, insertion, b''.join(value + b' /Part ,\n' for value in [fill, *(data[start:end] for start, end in children)]))]
    for start, end in children:
        edits.append((start - first, end - first, b''))
        field = re.match(rb'\s*(/Part)\s*(,)', data[end:last])
        assert field
        for index in (1, 2):
            left, right = field.span(index)
            edits.append((end + left - first, end + right - first, b''))
    return patch(data[first:last], edits)


def selection(variant):
    """Specify intended use indices independently of the reported changes."""
    if variant == 'outer-shared':
        return [0, 2, 3, 5]
    if variant.endswith('shared'):
        return [0, 1, 3, 4]
    return [1] if variant == 'group' else [0, 1] if variant == 'both' else [0]


def expected(data, row, variant):
    """Prescribe every output byte without accepting an implementation edit mask."""
    shared = variant.endswith('shared')
    style = row['styles'][0 if variant == 'outer-shared' else 1]
    first, last = style['record']
    name = b'Child with added fill' if variant == 'create' else b'Selected child'
    if variant == 'create':
        changed = created_style(data, style)
    else:
        old = b'0 g' if variant.startswith('simple') else b'0.1 0.2 0.3 Xa' if variant.startswith('restored') else b'0.2 0.3 0.4 Xa'
        changed = replace_once(data[first:last], old, b'0.8 g' if variant.startswith('simple') else b'0.7 0.6 0.5 Xa')
    edits = [(first, last, changed)] if shared else [
        (last, last, b'\n' + replace_once(changed, b'(Child) /Name', string(name) + b' /Name') + b'\n')]
    groups = list(re.finditer(rb'(?ms)^u\n\n0 0 0 1 k\n.*?\nU(?=\n\n0 J)', data))
    applications = list(re.finditer(rb'(?m)^(%_)?([01]) \((Child|Shared)\) XW$', data))
    assert len(groups) == 2 and len(applications) == 6
    for index in ([0, 1] if shared else [0]):
        edits.append((*groups[index].span(), GROUP))
    for index in selection(variant):
        use = applications[index]
        if not shared:
            assert use[1] == b'%_' and use[3] == b'Child'
            edits.append((*use.span(), b'%_' + use[2] + b' ' + string(name) + b' XW'))
        if variant.startswith('restored'):
            edits.append((use.end(), use.end(), b'\n%_0.1 0.2 0.3 Xa\n'))
    return replace_once(patch(data, edits), b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def child_owners(document, data, row, variant, after):
    """Resolve native child ownership backwards from each independent application."""
    body = list(walk_body(document.trailer))
    applications = [index for index, item in enumerate(body) if command(item)[0] == 'XW' and item.tokens[0] in (b'0', b'1')]
    assert len(applications) == 6
    nested = [(index, position) for index, position in enumerate(applications) if command(body[position])[2]]
    assert [index for index, _ in nested] == [0, 1, 3, 4]
    result = []
    for (index, position), report in zip(nested, row['nestedOwners'], strict=True):
        assert report['use'] == index
        end = position
        if isinstance(body[end - 1], dict):
            end -= 1
        operator, _, private = command(body[end - 1])
        assert private
        start = end - 1
        if operator in ('U', '*U'):
            stack = [operator]
            while stack:
                start -= 1
                value, _, private = command(body[start])
                if value in ('U', '*U'):
                    assert private
                    stack.append(value)
                elif value in ('u', '*u'):
                    assert private and stack.pop() == value.upper()
        else:
            assert operator in ('n', 'N', 'f', 'F', 's', 'S', 'b', 'B')
            while command(body[start])[0] != 'm':
                start -= 1
                assert start >= 0 and command(body[start])[2]
        subtree = normalized(body[start:end])
        assert normalized(fragment(data, report['span'], True)) == subtree
        result.append(subtree)
        if after and variant.startswith('restored') and index in selection(variant):
            replay = body[position + 1]
            assert command(replay)[0] == 'Xa' and command(replay)[2]
            assert list(map(float, replay.tokens)) == [0.1, 0.2, 0.3]
    return result


def main():
    """Verify complete definitions, references, geometry, metadata and byte deltas."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/appearance-nested-editing'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == len(SOURCES) * 2 and {row['source'] for row in rows} == {f'{variant}.{phase}' for variant in SOURCES for phase in ('before', 'after')}
    inventory = {row['source']: row for row in rows}
    for variant, checksum in SOURCES.items():
        before, after = [(args.output / f'{variant}.{phase}.ps').read_bytes() for phase in ('before', 'after')]
        assert hashlib.sha256(before).hexdigest() == checksum
        original, changed = [inventory[f'{variant}.{phase}'] for phase in ('before', 'after')]
        child_parts = 0 if variant.startswith('simple') else 2 if variant.startswith('restored') else 8
        shared = variant.endswith('shared')
        verify(inkai, args.output, original, expected=(2, 8 + child_parts, 6))
        verify(inkai, args.output, changed, expected=(2 if shared else 3, 8 + child_parts * (1 if shared else 2) + int(variant == 'create'), 6))
        assert after == expected(before, original, variant), variant
        original_owners = owners(inkai, args.output, before, original, variant)
        changed_owners = owners(inkai, args.output, after, changed, variant)
        assert [value[1] for value in original_owners] == [value[1] for value in changed_owners]
        children = []
        for data, row, phase in ((before, original, 'before'), (after, changed, 'after')):
            assert [artwork['nestedUses'] for artwork in row['artwork']] == [[0, 1], [3, 4]]
            document = inkai.parse(str(args.output / f'{row["source"]}.ps'))
            children.append(child_owners(document, data, row, variant, phase == 'after'))
        assert children[0] == children[1]
        print(variant, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=list(SOURCES)), indent=2) + '\n')


if __name__ == '__main__':
    main()
