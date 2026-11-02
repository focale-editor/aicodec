import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// RDF namespace used with deliberately nonstandard prefixes.
const String _rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

/// Wraps properties while retaining intentional comments, quotes and padding.
String _packet(String properties) =>
    '''<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x='adobe:ns:meta/'>
<r:RDF xmlns:r='$_rdf' xmlns:m='http://ns.adobe.com/xap/1.0/mm/'
 xmlns:f='http://ns.adobe.com/xap/1.0/sType/ManifestItem#'
 xmlns:a='http://ns.adobe.com/xap/1.0/sType/ResourceRef#' xmlns:custom='urn:keep'>
<r:Description r:about=''>
<!-- keep  exact -->
$properties
<m:DerivedFrom r:parseType='Resource'><a:filePath>old.png</a:filePath></m:DerivedFrom>
<custom:value custom:flag='yes'>&#x41; &amp; 😀</custom:value>
</r:Description></r:RDF></x:xmpmeta>
   \n<?xpacket end='w'?>''';

/// One manifest reference with an explicit stable link form.
String _manifest(String reference, {String array = 'Seq'}) => '<m:Manifest><r:$array><r:li r:parseType="Resource"><f:linkForm>EmbedByReference</f:linkForm>$reference</r:li></r:$array></m:Manifest>';

/// Creates a simple element-form resource with optional identity fields.
String _reference({String path = 'old.png', String extras = ''}) => '<f:reference r:parseType="Resource"><a:filePath>$path</a:filePath>$extras</f:reference>';

/// Relinks a selected inventory with explicit null identity policy.
AiXmpMetadata _relink(AiXmpMetadata metadata, {Iterable<AiXmpResource>? resources, String path = 'new.png', String? documentId, String? instanceId}) =>
    metadata.relink(resources: resources ?? metadata.resources, filePath: path, documentId: documentId, instanceId: instanceId);

/// Builds a PDF with a shared catalog/page XML stream, optionally filtered.
AiPdfDocument _pdf(String source, {bool compress = false, PdfLimits limits = const PdfLimits()}) {
  final PdfDocument pdf = PdfDocument.fromPages(pages: [PdfPageSource(width: 100, height: 100, content: [])]);
  const PdfReference metadata = PdfReference(objectNumber: 80);
  const PdfReference block = PdfReference(objectNumber: 81);
  final PdfStream encoded = PdfStreams.encode(bytes: utf8.encode(source), compress: compress);
  final PdfDictionary catalog = pdf.catalog.copyWith(
    values: {
      'Metadata': metadata,
      'PieceInfo': PdfDictionary(
        values: {
          'Illustrator': PdfDictionary(
            values: {
              'Private': PdfDictionary(values: {'AIPrivateData1': block}),
            },
          ),
        },
      ),
    },
  );
  return AiPdfDocument(
    pdf: PdfDocument(
      objects: {
        ...pdf.objects,
        pdf.trailer['Root']! as PdfReference: catalog,
        pdf.pages.single.reference!: pdf.pages.single.dictionary.copyWith(values: {'Metadata': metadata}),
        metadata: PdfStream(
          dictionary: encoded.dictionary.copyWith(
            values: {
              'Type': PdfName(value: 'Metadata'),
              'Subtype': PdfName(value: 'XML'),
            },
          ),
          data: encoded.data,
        ),
        block: PdfStream(dictionary: PdfDictionary(), data: latin1.encode('%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%%EndSetup\n0 g 10 10 m 20 10 L 20 20 L f\n%%EOF\n')),
      },
      trailer: pdf.trailer,
      limits: limits,
    ),
  );
}

/// Exercises packet preservation, bounded parsing and explicit resource updates.
void main() {
  test('reads dependencies by namespace and excludes provenance and other subjects', () {
    final String source = _packet(
      '${_manifest(_reference(extras: '<a:documentID>doc</a:documentID><a:instanceID>instance</a:instanceID>'))}'
      '<m:Ingredients><r:Bag><r:li a:filePath="old.png" a:documentID="doc"/></r:Bag></m:Ingredients>',
    );
    final AiXmpMetadata metadata = AiXmpMetadata.parse(source: source);
    check(metadata.source).equals(source);
    check(metadata.resources.length).equals(2);
    check(metadata.resources.map((resource) => resource.kind).toList()).deepEquals([AiXmpResourceKind.manifest, AiXmpResourceKind.ingredient]);
    check(metadata.resources.first.linkForm).equals('EmbedByReference');
    check(metadata.resources.first.instanceId).equals('instance');
    check(metadata.resources.last.documentId).equals('doc');
    check(metadata.resources.clear).throws<UnsupportedError>();
    check(AiXmpMetadata.parse(source: source.replaceAll("r:about=''", "r:about='urn:another-document'")).resources).isEmpty();
  });

  test('relinks selected resources and preserves all surrounding XML exactly', () {
    final String reference = _reference(extras: '<a:documentID>old-doc</a:documentID><a:instanceID>old-instance</a:instanceID>');
    final String source = _packet(_manifest(reference) + _manifest(reference));
    final AiXmpMetadata metadata = AiXmpMetadata.parse(source: source);
    const String path = 'C:\\Photos\\Été & <soir> "😀".png';
    final AiXmpMetadata changed = _relink(metadata, resources: [metadata.resources.first], path: path, documentId: 'new-doc');
    check(changed.resources.first.filePath).equals(path);
    check(changed.resources.first.documentId).equals('new-doc');
    check(changed.resources.first.instanceId).isNull();
    check(changed.resources.last.filePath).equals('old.png');
    final int start = source.indexOf(reference);
    final int end = start + reference.length;
    check(changed.source.startsWith(source.substring(0, start))).isTrue();
    check(changed.source.endsWith(source.substring(end))).isTrue();
    check(metadata.source).equals(source);
    check(_relink(changed, resources: [changed.resources.first], path: path, documentId: 'new-doc')).identicalTo(changed);
  });

  test('updates manifest and ingredient together without selecting identical unrelated paths', () {
    final AiXmpMetadata metadata = AiXmpMetadata.parse(source: _packet('${_manifest(_reference())}<m:Ingredients><r:Bag><r:li><r:Description a:filePath="old.png"/></r:li></r:Bag></m:Ingredients>'));
    final AiXmpMetadata changed = _relink(metadata, resources: metadata.resources.reversed, instanceId: 'new-instance');
    check(changed.resources.map((resource) => resource.filePath).toList()).deepEquals(['new.png', 'new.png']);
    check(changed.resources.map((resource) => resource.instanceId).toList()).deepEquals(['new-instance', 'new-instance']);
    check(changed.source).contains('<m:DerivedFrom r:parseType=\'Resource\'><a:filePath>old.png</a:filePath>');
  });

  test('supports abbreviated structures, URI values, alternate prefixes and empty inventories', () {
    for (final String reference in [
      '<f:reference a:filePath="old.png"/>',
      '<f:reference><r:Description a:filePath="old.png"/></f:reference>',
      '<f:reference r:parseType="Resource"><a:filePath r:resource="old.png"/></f:reference>',
      '<f:reference r:parseType="Resource"><a:filePath><![CDATA[old.png]]></a:filePath></f:reference>',
    ]) {
      final AiXmpMetadata metadata = AiXmpMetadata.parse(source: _packet(_manifest(reference, array: 'Bag')));
      check(metadata.resources.single.filePath).equals('old.png');
      check(_relink(metadata).resources.single.filePath).equals('new.png');
    }
    final AiXmpMetadata empty = AiXmpMetadata.parse(source: '<RDF xmlns="$_rdf"/>');
    check(empty.resources).isEmpty();
    check(_relink(empty)).identicalTo(empty);
  });

  test('clears old fallback paths and refuses richer reference semantics', () {
    final AiXmpMetadata metadata = AiXmpMetadata.parse(source: _packet(_manifest(_reference(extras: '<a:alternatePaths><r:Seq><r:li>fallback.png</r:li></r:Seq></a:alternatePaths>'))));
    check(_relink(metadata, path: 'old.png').source.contains('alternatePaths')).isFalse();
    for (final String field in ['<a:versionID>5</a:versionID>', '<a:fromPart>/page:2</a:fromPart>', '<custom:secret>keep</custom:secret>']) {
      final AiXmpMetadata rich = AiXmpMetadata.parse(source: _packet(_manifest(_reference(extras: field))));
      check(() => _relink(rich)).throws<UnsupportedError>();
      check(rich.source).contains(field);
    }
  });

  test('keeps local namespace declarations, BOMs and replacement character references', () {
    final AiXmpMetadata metadata = AiXmpMetadata.parse(
      source: '\uFEFF${_packet(_manifest('<local:reference xmlns:local="http://ns.adobe.com/xap/1.0/sType/ManifestItem#" a:filePath="old.png"/>'))}',
    );
    const String path = 'line\r\n&tab\t😀.png';
    final AiXmpMetadata changed = _relink(metadata, path: path);
    check(changed.source.startsWith('\uFEFF')).isTrue();
    check(changed.resources.single.filePath).equals(path);
    check(changed.source).contains('&#xD;');
    check(changed.source).contains('xmlns:local="http://ns.adobe.com/xap/1.0/sType/ManifestItem#"');
  });

  test('rejects qualified or malformed fallback paths before clearing them', () {
    for (final String paths in [
      '<r:Bag><r:li>old.png</r:li></r:Bag>',
      '<r:Seq><r:li custom:keep="value">old.png</r:li></r:Seq>',
      '<r:Seq><r:li><custom:keep/></r:li></r:Seq>',
    ]) {
      final AiXmpMetadata metadata = AiXmpMetadata.parse(source: _packet(_manifest(_reference(extras: '<a:alternatePaths>$paths</a:alternatePaths>'))));
      check(() => _relink(metadata)).throws<UnsupportedError>();
    }
  });

  test('retains default namespaces and rejects xmlns-named extension attributes', () {
    final AiXmpMetadata metadata = AiXmpMetadata.parse(source: _packet(_manifest('<f:reference xmlns="urn:retained" a:filePath="old.png"/>')));
    final AiXmpMetadata changed = _relink(metadata);
    check(changed.resources.single.filePath).equals('new.png');
    check(changed.source).contains('xmlns="urn:retained"');

    final String source = _packet(_manifest('<f:reference custom:xmlns="retained" a:filePath="old.png"/>'));
    final AiXmpMetadata extended = AiXmpMetadata.parse(source: source);
    check(() => _relink(extended)).throws<UnsupportedError>();
    check(extended.source).equals(source);
  });

  test('normalizes XML line endings and literal attribute whitespace without changing source', () {
    final String textSource = _packet(_manifest(_reference(path: 'a\r\nb\rc&#xD;d')));
    check(AiXmpMetadata.parse(source: textSource).resources.single.filePath).equals('a\nb\nc\rd');
    final String attributeSource = _packet(_manifest('<f:reference a:filePath="a\r\nb\tc&#x9;d&#xD;e"/>'));
    final AiXmpMetadata metadata = AiXmpMetadata.parse(source: attributeSource);
    check(metadata.resources.single.filePath).equals('a b c\td\re');
    check(metadata.source).equals(attributeSource);
  });

  test('rejects foreign or duplicated selections and invalid replacement scalars', () {
    final AiXmpMetadata first = AiXmpMetadata.parse(source: _packet(_manifest(_reference())));
    final AiXmpMetadata second = AiXmpMetadata.parse(source: first.source);
    check(() => _relink(first, resources: second.resources)).throws<ArgumentError>();
    check(() => _relink(first, resources: [first.resources.single, first.resources.single])).throws<ArgumentError>();
    check(() => _relink(first, path: '')).throws<ArgumentError>();
    check(() => _relink(first, documentId: '')).throws<ArgumentError>();
    for (final String path in ['bad\u0000path', 'bad\uD800path', 'bad\uFFFFpath']) {
      check(() => _relink(first, path: path)).throws<FormatException>();
    }
  });

  test('rejects duplicate scalar representations and ambiguous dependency structures', () {
    for (final String reference in [
      '<f:reference a:filePath="first"><a:filePath>second</a:filePath></f:reference>',
      '<f:reference r:nodeID="shared"/>',
      '<f:reference r:parseType="Resource"><r:Description a:filePath="old.png"/></f:reference>',
      '<f:reference><a:filePath xml:lang="en">old.png</a:filePath></f:reference>',
      '<f:reference><a:filePath r:resource="old.png">also.png</a:filePath></f:reference>',
      '<f:reference>significant text</f:reference>',
    ]) {
      check(() => AiXmpMetadata.parse(source: _packet(_manifest(reference)))).throws<FormatException>();
    }
    for (final String property in ['<m:Manifest/>', '<m:Manifest><r:Alt/></m:Manifest>', '<m:Ingredients><r:Seq/></m:Ingredients>', _manifest(_reference() + _reference())]) {
      check(() => AiXmpMetadata.parse(source: _packet(property))).throws<FormatException>();
    }
  });

  test('rejects DTDs, undeclared prefixes, invalid XML and non-UTF-8 declarations', () {
    for (final String source in [
      '<!DOCTYPE x SYSTEM "https://example.invalid/evil"><RDF xmlns="$_rdf"/>',
      '<!DOCTYPE x [<!ENTITY many "boom">]><RDF xmlns="$_rdf"/>',
      '<rdf:RDF/>',
      '<wrong/>',
      '<RDF xmlns="$_rdf"><x></RDF>',
      '<?xml version="1.0" encoding="UTF-16"?><RDF xmlns="$_rdf"/>',
      _packet(_manifest(_reference(path: '&missing;'))),
      _packet(_manifest(_reference(path: '&bare'))),
      _packet(_manifest(_reference(path: '&#0;'))),
      _packet(_manifest(_reference(path: '&#xD800;'))),
      _packet(_manifest(_reference(path: '&#X20;'))),
      _packet(_manifest(_reference(path: '&#-1;'))),
      '</unexpected>',
      _packet(_manifest('<f:reference a:filePath=old.png/>')),
      _packet(_manifest('<f:reference a:filePath/>')),
      _packet(_manifest('<f:reference a:filePath="<bad>"/>')),
      _packet(_manifest('<f:reference a:filePath="one" a:filePath="two"/>')),
      _packet('<!-- bad -- comment -->'),
      _packet('<custom:value>bad ]]></custom:value>'),
      'garbage<RDF xmlns="$_rdf"/>',
      '<RDF xmlns="$_rdf"/>garbage',
      '<?XML version="1.0"?><RDF xmlns="$_rdf"/>',
      '<?xml encoding="UTF-8"?><RDF xmlns="$_rdf"/>',
      '<?xml version="1.0" standalone="maybe"?><RDF xmlns="$_rdf"/>',
      '<?xpacket begin=""?><?xml version="1.0"?><RDF xmlns="$_rdf"/>',
    ]) {
      check(() => AiXmpMetadata.parse(source: source)).throws<FormatException>();
    }
  });

  test('checks byte, depth and attribute-inclusive node limits before editing', () {
    final String source = _packet(_manifest(_reference()));
    check(() => AiXmpMetadata.parse(source: source, limits: const AiXmpLimits(maxBytes: 0))).throws<ArgumentError>();
    check(
      () => AiXmpMetadata.parse(
        source: source,
        limits: AiXmpLimits(maxBytes: source.length),
      ),
    ).throws<FormatException>();
    check(() => AiXmpMetadata.parse(source: source, limits: const AiXmpLimits(maxDepth: 4))).throws<FormatException>();
    check(() => AiXmpMetadata.parse(source: source, limits: const AiXmpLimits(maxNodes: 10))).throws<FormatException>();
    final AiXmpMetadata metadata = AiXmpMetadata.parse(
      source: source,
      limits: AiXmpLimits(maxBytes: utf8.encode(source).length),
    );
    check(() => _relink(metadata, path: List.filled(300, '😀').join())).throws<FormatException>();
  });

  test('extracts filtered PDF metadata and preserves its optional UTF-8 BOM', () {
    final String source = '\uFEFF${_packet(_manifest(_reference()))}';
    for (final bool compress in [false, true]) {
      final AiXmpMetadata metadata = AiXmpMetadata.fromPdf(document: _pdf(source, compress: compress))!;
      check(metadata.source).equals(source);
      check(metadata.resources.single.filePath).equals('old.png');
    }
    check(
      AiXmpMetadata.fromPdf(
        document: AiPdfDocument(pdf: PdfDocument.fromPages(pages: [])),
      ),
    ).isNull();
    check(() => AiXmpMetadata.fromPdf(document: _pdf(source, compress: true), limits: const AiXmpLimits(maxBytes: 600))).throws<FormatException>();
  });

  test('writes a separate catalog packet after synchronized native saving', () {
    final AiPdfDocument original = _pdf(_packet(_manifest(_reference())), compress: true);
    final AiNativeSource native = AiNativeData.extract(original).single;
    final AiXmpMetadata changed = _relink(AiXmpMetadata.fromPdf(document: original)!);
    final AiPdfDocument synchronized = AiNativeData.replace(
      source: native,
      program: native.bytes,
      synchronizedPdf: original.pdf,
    );
    final AiPdfDocument saved = changed.writeTo(document: synchronized);
    check(AiXmpMetadata.fromPdf(document: saved)!.resources.single.filePath).equals('new.png');
    check(AiXmpMetadata.fromPdf(document: original)!.resources.single.filePath).equals('old.png');
    check(saved.pdf.catalog['Metadata'] == saved.pdf.pages.single.dictionary['Metadata']).isFalse();
    check(saved.pdf.pages.single.dictionary['Metadata']).equals(original.pdf.pages.single.dictionary['Metadata']);
    check(AiNativeData.extract(saved).single.bytes).deepEquals(native.bytes);
    final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
    check(AiXmpMetadata.fromPdf(document: reopened)!.source).equals(changed.source);
    check(AiNativeData.extract(reopened).single.bytes).deepEquals(native.bytes);
  });

  test('checks PDF object and stream ceilings without changing the source', () {
    final String source = _packet(_manifest(_reference()));
    final AiXmpMetadata metadata = AiXmpMetadata.parse(source: source);
    check(() => metadata.writeTo(document: _pdf(source, limits: const PdfLimits(maxStreamBytes: 100)))).throws<FormatException>();
    check(() => metadata.writeTo(document: _pdf(source, limits: const PdfLimits(maxObjects: 6)))).throws<FormatException>();
  });
}
