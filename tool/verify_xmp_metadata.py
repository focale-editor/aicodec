#!/usr/bin/env python3
"""Independently check source-preserving XMP edits and unchanged PDF artwork."""

import hashlib
import json
import subprocess
from pathlib import Path

from lxml import etree
from pypdf import PdfReader
from pypdf.generic import IndirectObject

from corpus_support import compare, render_pdf


def structure(value):
    """Compare PDF values without following references or retaining reader IDs."""
    if isinstance(value, IndirectObject):
        return ('reference', value.idnum, value.generation)
    if isinstance(value, dict):
        # Rewriting changes stream lengths and invalidates old linearization.
        return {key: structure(item) for key, item in value.items() if key not in {'/Length', '/Linearized'}}
    if isinstance(value, list):
        return [structure(item) for item in value]
    return str(value)


def main():
    """Require pinned sources, exact surrounding XML and unchanged page rendering."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    corpus = Path('test/corpus')
    output = corpus / 'output/xmp'
    manifest = json.loads((corpus / 'xmp_manifest.json').read_text())
    for entry in manifest['files']:
        data = (corpus / 'files' / entry['file']).read_bytes()
        assert len(data) == entry['size']
        assert hashlib.sha256(data).hexdigest() == entry['sha256']
    original = PdfReader(corpus / 'files/xmp/BlueSquare.ai')
    packet = original.trailer['/Root']['/Metadata'].get_data()
    assert packet == (output / 'adobe.xmp').read_bytes()
    source = (corpus / 'files/xmp/XMP3.xmp').read_bytes()
    changed = (output / 'relinked.xmp').read_bytes()
    start = source.index(b'<stMfs:reference ')
    end = source.index(b'</stMfs:reference>', start) + len(b'</stMfs:reference>')
    assert changed.startswith(source[:start]) and changed.endswith(source[end:])
    parser = etree.XMLParser(resolve_entities=False, no_network=True)
    tree = etree.fromstring(changed, parser)
    ns = {'m': 'http://ns.adobe.com/xap/1.0/mm/',
          'r': 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
          'f': 'http://ns.adobe.com/xap/1.0/sType/ManifestItem#',
          'a': 'http://ns.adobe.com/xap/1.0/sType/ResourceRef#'}
    references = tree.xpath('./r:RDF/r:Description/m:Manifest/r:Seq/r:li/f:reference', namespaces=ns)
    assert len(references) == 1
    report = json.loads((output / 'report.json').read_text())
    assert references[0].xpath('string(r:Description/a:filePath)', namespaces=ns) == report['path']
    assert references[0].xpath('string(r:Description/a:documentID)', namespaces=ns) == report['documentId']
    assert not references[0].xpath('r:Description/a:instanceID', namespaces=ns)
    # ExifTool independently understands the authored RDF Description structure.
    exif = json.loads(subprocess.check_output(['exiftool', '-j', '-struct', '-XMP-xmpMM:Manifest', str(output / 'relinked.xmp')]))[0]
    assert exif['Manifest'][0]['Reference']['FilePath'] == report['path']
    assert exif['Manifest'][0]['Reference']['DocumentID'] == report['documentId']
    page = original.pages[0]
    width, height = round(float(page.mediabox.width)), round(float(page.mediabox.height))
    reference = output / 'original.ai'
    reference.write_bytes((corpus / 'files/xmp/BlueSquare.ai').read_bytes())
    rendered = render_pdf(reference, width, height)
    results = []
    for name, expected in [('preserved', packet), ('metadata-carrier', changed)]:
        target = output / f'{name}.ai'
        saved = PdfReader(target)
        assert saved.trailer['/Root']['/Metadata'].get_data() == expected
        # Native streams and original object values survive serialization,
        # except regenerated lengths and the removed stale linearization flag.
        for generation, objects in original.xref.items():
            if generation == 65535:
                continue
            for number in objects:
                if number == 0:
                    continue
                before = original.get_object(IndirectObject(number, generation, original))
                after = saved.get_object(IndirectObject(number, generation, saved))
                assert structure(before) == structure(after), number
                if hasattr(before, 'get_data'):
                    assert before.get_data() == after.get_data(), number
        assert len(saved.pages) == len(original.pages) == 1
        difference = compare(render_pdf(target, width, height), rendered, output / f'{name}.diff.png', 0.000001)
        assert difference == 0
        results.append(difference)
    (output / 'independent-verification.json').write_text(json.dumps({'xmlReferences': 1, 'pdfPackets': 2, 'pageComparisons': results}, indent=2) + '\n')
    print('XMP: lxml and ExifTool agree; exact surrounding XML and original PDF objects; two zero-difference pages.')


if __name__ == '__main__':
    main()
