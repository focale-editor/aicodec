#!/usr/bin/env python3
"""Independently check native envelopes emitted by check_native_corpus.dart."""
import json
from pathlib import Path
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]


def main():
    """Require every corpus result, then compare system-decoded source bytes."""
    output = ROOT / 'test/corpus/output/native'
    manifest = json.loads((ROOT / 'test/corpus/manifest.json').read_text())
    report = json.loads((output / 'report.json').read_text())
    expected = {entry['file'] for entry in manifest['files']}
    if len(report) != len(expected) or {row['file'] for row in report} != expected:
        raise RuntimeError('Native report does not cover the required manifest')
    if any(row['status'] != 'passed' for row in report):
        raise RuntimeError('Native corpus check has failures')
    checked = 0
    for row in report:
        if row['container'] == 'postscript':
            continue
        if row['container'] != 'pdf':
            raise RuntimeError(f"Unknown container: {row['container']}")
        for envelope_suffix, source_suffix in [('envelope', 'native.ps'), ('edited.envelope', 'edited.ps')]:
            envelope = (output / f"{row['file']}.{envelope_suffix}").read_bytes()
            if envelope.startswith(b'%AI24_ZStandard_Data'):
                decoded = subprocess.run(['zstd', '-q', '-d', '-c'], input=envelope[20:], stdout=subprocess.PIPE, check=True).stdout
            elif envelope.startswith(b'%AI12_CompressedData'):
                decoded = zlib.decompress(envelope[20:])
            elif envelope.startswith(b'%!PS-Adobe-'):
                decoded = envelope
            else:
                raise RuntimeError(f"Unrecognized envelope: {row['file']}")
            if decoded != (output / f"{row['file']}.{source_suffix}").read_bytes():
                raise RuntimeError(f"Independent decoding mismatch: {row['file']} / {envelope_suffix}")
            checked += 1
    print(f'Independent native byte comparisons: {checked}/{checked}')


if __name__ == '__main__':
    main()
