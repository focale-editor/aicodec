#!/usr/bin/env python3
"""Verify promoted ordinary contours with independent native/PDF readers."""

from pypdf import PdfReader

from corpus_support import native_programs
from verify_native_documents import renders
from verify_native_structure import native_values


def verify_conversions(inkai, output):
    """Check identity retention, private ownership and both same-revision views."""
    for kind in ('pattern', 'brush', 'mask'):
        for reopened in (False, True):
            stem = f'conversion-{kind}' + ('-reopened' if reopened else '')
            path = output / f'{stem}.ai'
            native = (output / f'{stem}.ps').read_bytes()
            assert native_programs(path) == [native], stem
            document = inkai.parse(str(output / f'{stem}.ps'))
            owners = [value for value in native_values(document.trailer)
                      if isinstance(value, dict) and 'AI10_ArtUID' in value]
            assert [value['AI10_ArtUID'] for value in owners] == ['focale_root', 'focale_object_0', 'focale_object_1'], stem
            assert owners[1]['AIArtName'] == f'Converted {kind}', stem
            assert ('AI9_Mask' in owners[1]) == (kind == 'mask'), stem
            saved = PdfReader(path, strict=True)
            reference = output / f'{stem}-reference.pdf'
            expected = PdfReader(reference, strict=True)
            assert len(saved.pages) == len(expected.pages) == 1, stem
            assert saved.pages[0].mediabox == expected.pages[0].mediabox, stem
            assert renders(path) == renders(reference), stem
            print(stem, 'passed', flush=True)
    print('Verified six ordinary-path conversion comparisons with retained identities and original/reopened host PDF views.')
