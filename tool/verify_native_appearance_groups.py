#!/usr/bin/env python3
"""Check group ownership and exact appearance edits with the pinned native reader."""

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
from verify_native_appearances import verify
from verify_native_artboard_text import normalized
from verify_native_group_lifecycle import command
from verify_native_structure import parsed

SOURCES = {
    'selected': '081dd36f599e2166b81478b329784b9be9c8f3f48d67d071bc624b228bffe9b7',
    'shared': '081dd36f599e2166b81478b329784b9be9c8f3f48d67d071bc624b228bffe9b7',
    'compound-selected': 'de1ff80b5ce7e402d6209b38f7a44f484b6c85829995683cd5b273c14d07a6a0',
    'compound-shared': 'de1ff80b5ce7e402d6209b38f7a44f484b6c85829995683cd5b273c14d07a6a0',
    'uncounted': 'd955626a4afe4f2ce6dba48cdcfc4935601e45b98a3cd400cce63a1e1448458f',
    'mixed': 'fe6baccd13709a194b242f0b3eb8262aa4608d4affac10ae5848c09b5017e1ed',
}


def shared(variant):
    """Specify which fixture transaction covers both source users."""
    return variant.endswith('shared') or variant == 'mixed'


def expected(before, original, variant):
    """Prescribe the complete file delta without accepting reported edit masks."""
    start, end = original['styles'][0]['record']
    style = replace_once(before[start:end], b'0.2 0.3 0.4 Xa', b'0.7 0.6 0.5 Xa')
    name = string(b'Selected group')
    edits = [(start, end, style)] if shared(variant) else [
        (end, end, b'\n' + replace_once(style, b'(Shared) /Name', name + b' /Name') + b'\n')]
    groups = list(re.finditer(rb'(?m)^u\n\n0 0 0 1 k\n.*?\nU(?=\n\n0 J)', before, re.DOTALL))
    applications = list(re.finditer(rb'(?m)^1 \(Shared\) XW$', before))
    assert len(groups) == len(applications) == 2
    for index in ([0, 1] if shared(variant) else [0]):
        group, application = groups[index], applications[index]
        assert group.end() < application.start()
        edits.append((group.start(), group.end(), GROUP))
        if not shared(variant):
            edits.append((application.start(), application.end(), b'1 ' + name + b' XW'))
    for start, end, value in sorted(edits, reverse=True):
        before = before[:start] + value + before[end:]
    return replace_once(before, b'%%BoundingBox: 0 0 100 100', b'%%BoundingBox: -20 -30 120 140')


def fragment(data, span, private=False):
    """Restore the lexical private prefix outside a token's reported byte span."""
    start, end = span
    if private:
        assert data[start - 2:start] == b'%_'
        start -= 2
    return parsed(data[start:end])


def subtree(items, private):
    """Find a complete native group or path independently of the Dart spans."""
    start = next(index for index, item in enumerate(items)
                 if command(item)[2] == private and command(item)[0] in ('u', '*u', 'm'))
    opening = command(items[start])[0]
    if opening == 'm':
        end = next(index for index in range(start + 1, len(items)) if command(items[index])[0] in ('n', 'N'))
        return items[start:end + 1]
    stack = []
    for index in range(start, len(items)):
        operator, _, pseudo = command(items[index])
        if operator in ('u', '*u'):
            assert pseudo == private
            stack.append(operator)
        elif operator in ('U', '*U'):
            assert pseudo == private and stack.pop().upper() == operator
            if not stack:
                return items[start:index + 1]
    raise AssertionError('Unfinished independently decoded group')


def owners(inkai, output, data, row, variant):
    """Bind each authoring tree, printing group and dictionary to the full parse."""
    body = list(walk_body(inkai.parse(str(output / f'{row["source"]}.ps')).trailer))
    applications = [index for index, item in enumerate(body) if command(item)[0] == 'XW' and item.tokens[0] == b'1']
    assert len(applications) == len(row['artwork']) == 2
    previous = 0
    result = []
    for index, (end, report) in enumerate(zip(applications, row['artwork'], strict=True)):
        items = body[previous:end]
        previous = end + 1
        authoring, printing = subtree(items, True), subtree(items, False)
        assert normalized(fragment(data, report['authoring'], True)) == normalized(authoring)
        assert normalized(fragment(data, report['printing'])) == normalized(printing)
        grouped = variant != 'mixed' or index == 0
        compound = variant.startswith('compound')
        assert report['group'] == grouped and report['compound'] == (compound if grouped else None)
        assert report['paths'] == sum(command(item)[0] == 'm' for item in authoring) == (2 if grouped else 1)
        boundaries = [command(item)[0] for item in authoring if command(item)[0] in ('u', 'U', '*u', '*U')]
        expected_boundaries = (['*u', '*U'] if compound else ['u', 'u', 'U', 'U']) if grouped else []
        assert boundaries == expected_boundaries
        counts = [item.tokens for item in authoring if command(item)[0] == 'As']
        assert counts == ([[b'3'], [b'3']] if grouped and variant != 'uncounted' else [])
        dictionaries = [item for item in items if isinstance(item, dict) and item.get('_type') == 'ArtDictionary']
        expected_dictionaries = (2 if compound else 3) if grouped else 0
        assert len(dictionaries) == len(report['metadata']) == expected_dictionaries
        assert [span[0] for span in report['metadata']] == sorted(span[0] for span in report['metadata'])
        for dictionary, span in zip(dictionaries, report['metadata'], strict=True):
            decoded, = fragment(data, span, True)
            assert normalized(decoded) == normalized(dictionary)
        result.append((normalized(authoring), normalized(dictionaries)))
    return result


def main():
    """Check every selected/shared group case without claiming host composition."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inkai-source', required=True, type=Path)
    parser.add_argument('--output', default=Path('test/corpus/output/appearance-groups'), type=Path)
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.inkai_source), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.inkai_source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module('inkai')
    rows = json.loads((args.output / 'report.json').read_text())
    assert len(rows) == 2 * len(SOURCES) and {row['source'] for row in rows} == {f'{variant}.{phase}' for variant in SOURCES for phase in ('before', 'after')}
    inventory = {row['source']: row for row in rows}
    for variant, checksum in SOURCES.items():
        before, after = [(args.output / f'{variant}.{phase}.ps').read_bytes() for phase in ('before', 'after')]
        assert hashlib.sha256(before).hexdigest() == checksum
        original, changed = [inventory[f'{variant}.{phase}'] for phase in ('before', 'after')]
        styles = 1 if shared(variant) else 2
        verify(inkai, args.output, original, expected=(1, 8, 2))
        verify(inkai, args.output, changed, expected=(styles, styles * 8, 2))
        assert after == expected(before, original, variant)
        assert owners(inkai, args.output, before, original, variant) == owners(inkai, args.output, after, changed, variant)
        print(variant, 'passed', flush=True)
    (args.output / 'independent-report.json').write_text(json.dumps(dict(oracleRevision=REVISION, variants=list(SOURCES)), indent=2) + '\n')


if __name__ == '__main__':
    main()
