part of '../model/ai_xmp_metadata.dart';

/// Rewrites selected references while retaining every surrounding character.
AiXmpMetadata _relinkXmp(AiXmpMetadata metadata, Iterable<AiXmpResource> resources, String path, String? documentId, String? instanceId) {
  for (final String value in [path, ?documentId, ?instanceId]) {
    if (value.isEmpty || value.length > metadata.limits.maxBytes) {
      throw ArgumentError('Replacement XMP paths and identifiers must be nonempty and bounded.');
    }
    _validateXmpText(value);
  }
  final Set<AiXmpResource> selected = {};
  for (final AiXmpResource resource in resources) {
    if (resource.index >= metadata.resources.length || !identical(metadata.resources[resource.index], resource) || !selected.add(resource)) {
      throw ArgumentError('XMP references must be distinct members of the current packet.');
    }
  }
  final List<({int start, int end, String text})> edits = [];
  int size = utf8.encode(metadata.source).length;
  for (final AiXmpResource resource in selected) {
    final XmlElement fields = _xmpStructure(resource._element);
    const Set<String> allowed = {'filePath', 'documentID', 'instanceID', 'alternatePaths'};
    for (final XmlAttribute attribute in fields.attributes) {
      if (!_xmpNamespaceDeclaration(attribute) &&
          !(attribute.namespaceUri == _rdfNamespace && attribute.name.local == 'parseType') &&
          !(attribute.namespaceUri == _referenceNamespace && allowed.contains(attribute.name.local) && attribute.name.local != 'alternatePaths')) {
        throw UnsupportedError('Relinking managed, qualified or extended XMP references requires an explicit policy.');
      }
    }
    for (final XmlElement child in fields.childElements) {
      if (child.namespaceUri != _referenceNamespace || !allowed.contains(child.name.local)) {
        throw UnsupportedError('Relinking extended XMP reference fields requires an explicit policy.');
      }
    }
    final List<XmlElement> alternate = fields.childElements.where((child) => _xmpName(child, _referenceNamespace, 'alternatePaths')).toList();
    if (alternate.length > 1) {
      throw const FormatException('Duplicate XMP fallback paths.');
    }
    if (alternate.isNotEmpty) {
      final XmlElement property = alternate.single;
      _xmpWhitespace(property);
      if (property.attributes.any((attribute) => !_xmpNamespaceDeclaration(attribute)) || property.childElements.length != 1 || !_xmpName(property.childElements.single, _rdfNamespace, 'Seq')) {
        throw UnsupportedError('Only an ordered list of plain XMP fallback paths can be cleared.');
      }
      final XmlElement paths = property.childElements.single;
      _xmpWhitespace(paths);
      if (paths.attributes.any((attribute) => !_xmpNamespaceDeclaration(attribute)) ||
          paths.childElements.any((item) => !_xmpName(item, _rdfNamespace, 'li') || item.childElements.isNotEmpty || item.attributes.any((attribute) => !_xmpNamespaceDeclaration(attribute)))) {
        throw UnsupportedError('Qualified XMP fallback paths require an explicit policy.');
      }
    }
    if (alternate.isEmpty && resource.filePath == path && resource.documentId == documentId && resource.instanceId == instanceId) {
      continue;
    }
    final XmlElement replacement = XmlElement(resource._element.name, resource._element.attributes.where(_xmpNamespaceDeclaration).map((attribute) => attribute.copy()), [
      XmlElement(
        const XmlName.parts('Description', prefix: 'rdf'),
        [
          XmlAttribute(const XmlName.parts('rdf', prefix: 'xmlns'), _rdfNamespace),
          XmlAttribute(const XmlName.parts('stRef', prefix: 'xmlns'), _referenceNamespace),
        ],
        [
          for (final MapEntry<String, String> entry in {'filePath': path, 'documentID': ?documentId, 'instanceID': ?instanceId}.entries)
            XmlElement(XmlName.parts(entry.key, prefix: 'stRef'), [], [XmlText(entry.value)]),
        ],
      ),
    ]);
    final String text = replacement.toXmlString(entityMapping: const _XmpEntityMapping());
    size += utf8.encode(text).length - utf8.encode(metadata.source.substring(resource._span.start, resource._span.end)).length;
    if (size > metadata.limits.maxBytes) {
      throw const FormatException('Rewritten XMP exceeds the byte limit.');
    }
    edits.add((start: resource._span.start, end: resource._span.end, text: text));
  }
  if (edits.isEmpty) {
    return metadata;
  }
  edits.sort((a, b) => a.start.compareTo(b.start));
  final StringBuffer result = StringBuffer();
  int previous = 0;
  for (final ({int start, int end, String text}) edit in edits) {
    result.write(metadata.source.substring(previous, edit.start));
    result.write(edit.text);
    previous = edit.end;
  }
  result.write(metadata.source.substring(previous));
  return AiXmpMetadata.parse(source: result.toString(), limits: metadata.limits);
}

/// Attaches new metadata without mutating objects shared with pages or images.
AiPdfDocument _writeXmp(AiXmpMetadata metadata, AiPdfDocument document) {
  final PdfDocument pdf = document.pdf;
  final Uint8List bytes = utf8.encode(metadata.source);
  pdf.limits.validate();
  if (bytes.length > pdf.limits.maxStreamBytes) {
    throw const FormatException('XMP exceeds the PDF stream limit.');
  }
  final PdfEditor editor = PdfEditor(document: pdf);
  final PdfReference stream = editor.addObject(
    value: PdfStream(
      dictionary: PdfDictionary(
        values: {
          'Type': PdfName(value: 'Metadata'),
          'Subtype': PdfName(value: 'XML'),
        },
      ),
      data: bytes,
    ),
  );
  final PdfReference catalog = editor.addObject(value: pdf.catalog.copyWith(values: {'Metadata': stream}));
  return AiPdfDocument(
    pdf: editor.document.copyWith(trailer: pdf.trailer.copyWith(values: {'Root': catalog})),
  );
}
