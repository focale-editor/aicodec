#!/usr/bin/env python3
"""Verify native text paint edits with unchanged independent ATE decoding."""

import argparse
import base64
import copy
import hashlib
import importlib
import io
import itertools
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid

from corpus_support import REVISION, native_programs
from verify_native_text import field, identifiers

PRODUCERS = {
    'flowtext.ai': 1, 'text_transforms.ai': 10, 'simple_v2020.ai': 1,
    'simple_cc_legacy.ai': 1, 'simple_v2020_no_pdf_data.ai': 1,
    **{f'simple_{version}.ai': 1 for version in ('cs', 'cs2', 'cs3', 'cs4', 'cs5', 'cs6')},
}
SYNTHETIC = {
    'compact': 'fa09b595316b414e1edc3dac4b98376c9a50bdab721074db85f48b0ea0116d00',
    'named': '72b586fa0dfeb34aec4517aa16767b93035dda2538ae01efa58263fa876b9cd0',
}
SCALARS = [
    ('56', 'FillFlag', False), ('57', 'StrokeFlag', True), ('58', 'FillFirst', False),
    ('59', 'FillOverPrint', True), ('60', 'StrokeOverPrint', True),
    ('61', 'LineCap', 1), ('62', 'LineJoin', 2), ('63', 'LineWidth', 3),
    ('64', 'MiterLimit', 8), ('65', 'LineDashOffset', -2), ('66', 'LineDashArray', [3, 0, 1]),
    ('77', 'FillVisibleFlag', False), ('78', 'StrokeVisibleFlag', True), ('80', 'FillBackgroundFlag', True),
]
COLORS = [('53', 'FillColor', 2, [0.1, 0.2, 0.3, 0.4]), ('54', 'StrokeColor', 1, [0.7, 0.6, 0.5]), ('79', 'FillBackgroundColor', 0, [0.9])]


def key(record, compact, name, named):
    """Keep actual source aliases instead of normalizing retained dictionaries."""
    field(record, compact, name)
    return '/' + (compact if '/' + compact in record else name if '/' + name in record or named else compact)


def paint(original, color_type, components, named):
    """Prescribe the native SimplePaint tuple independently of the Dart model."""
    original = original or {}
    color = field(original, '0', 'Color') or {}
    return {
        key(original, '99', 'StreamTag', named): '/SimplePaint',
        key(original, '0', 'Color', named): {
            key(color, '0', 'Type', named): color_type,
            key(color, '1', 'Values', named): [1, *components],
        },
    }


def expected_tree(before, after, row):
    """Change only the selected UTF-16 runs, their identities and layout caches."""
    expected = copy.deepcopy(before)
    story = field(field(expected, '1', 'DocumentObjects'), '1', 'TextObjects')[row['story']]
    model = field(story, '0', 'Model')
    named = '/Text' in model
    length = len(field(model, '0', 'Text').encode('utf-16-le')) // 2
    table = field(model, '6', 'StyleRun')
    if table is None:
        table = {key({}, '0', 'RunArray', named): [{
            key({}, '0', 'RunData', named): {key({}, '0', 'StyleSheet', named): {}},
            key({}, '1', 'Length', named): length,
        }]}
        model[key(model, '6', 'StyleRun', named)] = table
    runs = field(table, '0', 'RunArray')
    owners = [index for index, run in enumerate(runs) for _ in range(field(run, '1', 'Length'))]
    assert len(owners) == length
    actual_story = field(field(after, '1', 'DocumentObjects'), '1', 'TextObjects')[row['story']]
    actual_runs = field(field(field(actual_story, '0', 'Model'), '6', 'StyleRun'), '0', 'RunArray')
    reserved = set(identifiers(before))
    assigned = set()
    labels = [(owner, row['start'] <= position < row['end']) for position, owner in enumerate(owners)]
    rewritten = []
    for index, ((owner, selected), positions) in enumerate(itertools.groupby(labels)):
        run = copy.deepcopy(runs[owner])
        run[key(run, '1', 'Length', named)] = len(list(positions))
        if selected:
            data = field(run, '0', 'RunData')
            style = field(data, '0', 'StyleSheet')
            if not isinstance(style, dict):
                style = {key({}, '5', 'Parent', named): style}
                data[key(data, '0', 'StyleSheet', named)] = style
            features = field(style, '6', 'Features')
            if features is None:
                features = {}
                style[key(style, '6', 'Features', named)] = features
            if row['operation'] == 'inherit':
                for compact, name in [('53', 'FillColor'), ('54', 'StrokeColor'), ('79', 'FillBackgroundColor'), ('66', 'LineDashArray'), ('63', 'LineWidth')]:
                    features.pop(key(features, compact, name, named), None)
            else:
                for compact, name, value in SCALARS if row['operation'] == 'edit' else []:
                    features[key(features, compact, name, named)] = value
                for compact, name, color_type, components in COLORS if row['operation'] == 'edit' else [('53', 'FillColor', 3, [50, -128, 127])]:
                    destination = key(features, compact, name, named)
                    features[destination] = paint(features.get(destination), color_type, components, named)
            if field(style, '97', 'UUID') is not None:
                actual_style = field(field(actual_runs[index], '0', 'RunData'), '0', 'StyleSheet')
                identifier = field(actual_style, '97', 'UUID')
                assert uuid.UUID(identifier).version == 4 and identifier not in reserved and identifier not in assigned
                assigned.add(identifier)
                style[key(style, '97', 'UUID', named)] = identifier
        rewritten.append(run)
    table[key(table, '0', 'RunArray', named)] = rewritten
    view = field(story, '1', 'View')
    for cache in ('/1', '/RenderedData', '/2', '/Strikes'):
        view.pop(cache, None)
    assert after == expected, (row['after'], 'unexpected ATE mutation')


def native_payload(data):
    """Independently decode the sole changed binary owner and its exact framing."""
    matches = list(re.finditer(rb'/AI11TextDocument\s*:\s*/ASCII85Decode\s*,\s*(.*?)~>', data, re.S))
    assert len(matches) == 1
    match, = matches
    lines = [line.strip() for line in match[1].splitlines() if line.strip()]
    assert all(line.startswith(b'%') for line in lines)
    encoded = b''.join(line[1:] for line in lines)
    return base64.a85decode(encoded + b'~>', adobe=True), data[:match.start(1)], data[match.end():]


def main():
    """Require all twenty producer stories plus both independently authored schemas."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/text-paints'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    text_parser = importlib.import_module('inkai.parser.text').TextDocumentParser
    stream = importlib.import_module('inkai.parser.streamreader').StreamWrapper
    manifest = {entry['file']: entry for entry in json.loads(Path('test/corpus/manifest.json').read_text())['files']}
    rows = json.loads((args.output / 'report.json').read_text())
    required = {(name, index, operation) for name, count in PRODUCERS.items() for index in range(count) for operation in ('edit', 'inherit')}
    required |= {(name, 0, operation) for name in SYNTHETIC for operation in ('edit', 'inherit', 'lab')}
    assert len(rows) == 46 and {(row['file'], row['story'], row['operation']) for row in rows} == required
    for name in (*PRODUCERS, *SYNTHETIC):
        native = (args.output / f'{name}.original.ps').read_bytes()
        if name in SYNTHETIC:
            assert hashlib.sha256(native).hexdigest() == SYNTHETIC[name]
        else:
            fixture, entry = Path('test/corpus/files', name), manifest[name]
            raw = fixture.read_bytes()
            assert entry['license'] and entry['revision'] == REVISION and len(raw) == entry['size'] and hashlib.sha256(raw).hexdigest() == entry['sha256']
            assert ([raw] if raw.startswith(b'%!PS-Adobe-') else native_programs(fixture)) == [native]
        decoded, _, _ = native_payload(native)
        assert decoded == (args.output / f'{name}.original.ate').read_bytes()
    for row in rows:
        before, after = [(args.output / f'{row[key]}.ate').read_bytes() for key in ('before', 'after')]
        native_before, native_after = [native_payload((args.output / f'{row[key]}.ps').read_bytes()) for key in ('before', 'after')]
        assert native_before[0] == before and native_after[0] == after and native_before[1:] == native_after[1:]
        trees = [text_parser.read_object(stream(io.BytesIO(payload))) for payload in (before, after)]
        expected_tree(*trees, row)
        print(row['after'], 'passed', flush=True)
    report = dict(oracleRevision=REVISION, producerFiles=len(PRODUCERS), producerStories=sum(PRODUCERS.values()), producerTransactions=40, syntheticTransactions=6)
    (args.output / 'independent-report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
