part of '../model/ai_xmp_metadata.dart';

/// Namespace identifying XMP's RDF serialization vocabulary.
const String _rdfNamespace = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

/// Namespace identifying document-management properties.
const String _managementNamespace = 'http://ns.adobe.com/xap/1.0/mm/';

/// Namespace identifying fields of a referenced asset.
const String _referenceNamespace = 'http://ns.adobe.com/xap/1.0/sType/ResourceRef#';

/// Namespace identifying Illustrator manifest fields.
const String _manifestNamespace = 'http://ns.adobe.com/xap/1.0/sType/ManifestItem#';

/// Recognizes elements by expanded name, independent of producer prefixes.
bool _xmpName(XmlElement element, String namespace, String name) => element.namespaceUri == namespace && element.name.local == name;

/// Distinguishes namespace declarations from ordinary namespaced attributes.
bool _xmpNamespaceDeclaration(XmlAttribute attribute) => attribute.name.prefix == 'xmlns' || attribute.name.qualified == 'xmlns';

/// Checks XML scalar validity before UTF-8 encoding can replace bad surrogates.
void _validateXmpText(String value) {
  for (final int rune in value.runes) {
    if (!(rune == 9 || rune == 10 || rune == 13 || (rune >= 32 && rune <= 0xD7FF) || (rune >= 0xE000 && rune <= 0xFFFD) || (rune >= 0x10000 && rune <= 0x10FFFF))) {
      throw const FormatException('XMP contains an invalid XML character.');
    }
  }
}

/// Reads bounded XML while retaining source offsets for each parsed element.
AiXmpMetadata _parseXmp(String source, AiXmpLimits limits) {
  limits.validate();
  if (source.length > limits.maxBytes) {
    throw const FormatException('XMP exceeds the byte limit.');
  }
  _validateXmpText(source);
  if (utf8.encode(source).length > limits.maxBytes) {
    throw const FormatException('XMP exceeds the byte limit.');
  }
  final List<({int start, int end})> spans = [];
  final List<List<String>> attributeValues = [];
  final List<int> stack = [];
  int nodes = 0;
  for (final XmlEvent event in parseEvents(
    source,
    entityMapping: const _XmpEntityMapping(),
    validateNesting: true,
    validateNamespace: true,
    validateDocument: true,
    withLocation: true,
    withNamespace: true,
  )) {
    nodes += 1 + (event is XmlStartElementEvent ? event.attributes.length : 0);
    if (nodes > limits.maxNodes) {
      throw const FormatException('XMP exceeds the node limit.');
    }
    if (event is XmlDoctypeEvent) {
      throw const FormatException('XMP document type declarations are unsupported.');
    }
    if (event is XmlProcessingEvent && event.target.toLowerCase() == 'xml') {
      throw const FormatException('Reserved XMP XML processing target.');
    }
    if (stack.isEmpty && event is XmlTextEvent) {
      final String outside = event.start == 0 && event.value.startsWith('\uFEFF') ? event.value.substring(1) : event.value;
      if (outside.codeUnits.any((unit) => !_xmpSpace(unit))) {
        throw const FormatException('Unexpected text outside the XMP document root.');
      }
    }
    if (event is XmlCommentEvent && (event.value.contains('--') || event.value.endsWith('-'))) {
      throw const FormatException('Invalid XMP XML comment.');
    }
    if (event is XmlTextEvent && source.substring(event.start!, event.stop).contains(']]>')) {
      throw const FormatException('Invalid XMP character data terminator.');
    }
    if (event is XmlDeclarationEvent) {
      _xmpAttributeValues(source, event.start! + 5, event.stop!, event.attributes, declaration: true);
      final List<String> names = event.attributes.map((attribute) => attribute.name).toList();
      final String shape = names.join(',');
      if (event.start != (source.startsWith('\uFEFF') ? 1 : 0) ||
          !['version', 'version,encoding', 'version,standalone', 'version,encoding,standalone'].contains(shape) ||
          event.attributes.any((attribute) => attribute.name == 'standalone' && !['yes', 'no'].contains(attribute.value))) {
        throw const FormatException('Invalid XMP XML declaration.');
      }
      final String? encoding = event.attributes.where((attribute) => attribute.name == 'encoding').firstOrNull?.value;
      if (encoding != null && encoding.toUpperCase() != 'UTF-8') {
        throw const FormatException('Only UTF-8 XMP packets are supported.');
      }
      if (event.attributes.any((attribute) => attribute.name == 'version' && attribute.value != '1.0')) {
        throw const FormatException('Only XML 1.0 XMP packets are supported.');
      }
    }
    if (event is XmlStartElementEvent) {
      if (stack.length >= limits.maxDepth) {
        throw const FormatException('XMP exceeds the depth limit.');
      }
      final int index = spans.length;
      spans.add((start: event.start!, end: event.stop!));
      attributeValues.add(_xmpAttributeValues(source, event.start! + 1 + event.name.length, event.stop!, event.attributes));
      if (!event.isSelfClosing) {
        stack.add(index);
      }
    } else if (event is XmlEndElementEvent) {
      final int index = stack.removeLast();
      spans[index] = (start: spans[index].start, end: event.stop!);
    }
  }
  // XML line-ending normalization changes values, never retained source spans.
  final XmlDocument tree = XmlDocument.parse(source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'), entityMapping: const _XmpEntityMapping());
  final XmlElement root = tree.rootElement;
  final XmlElement rdf;
  if (_xmpName(root, _rdfNamespace, 'RDF')) {
    rdf = root;
  } else if (_xmpName(root, 'adobe:ns:meta/', 'xmpmeta') && root.childElements.length == 1 && _xmpName(root.childElements.single, _rdfNamespace, 'RDF')) {
    rdf = root.childElements.single;
  } else {
    throw const FormatException('Expected an XMP metadata or RDF root.');
  }
  final Map<XmlElement, ({int start, int end})> locations = {};
  int index = 0;
  for (final XmlElement element in [root, ...root.descendantElements]) {
    for (int attribute = 0; attribute < element.attributes.length; attribute++) {
      element.attributes[attribute].value = attributeValues[index][attribute];
    }
    locations[element] = spans[index++];
  }
  final List<AiXmpResource> resources = [];
  for (final XmlElement description in rdf.childElements) {
    if (!_xmpName(description, _rdfNamespace, 'Description') || (description.getAttribute('about', namespaceUri: _rdfNamespace) ?? '').isNotEmpty) {
      continue;
    }
    if (description.attributes.any((attribute) => attribute.namespaceUri == _managementNamespace && ['Manifest', 'Ingredients'].contains(attribute.name.local))) {
      throw const FormatException('XMP dependencies require array properties.');
    }
    for (final XmlElement property in description.childElements) {
      if (property.namespaceUri != _managementNamespace || !['Manifest', 'Ingredients'].contains(property.name.local)) {
        continue;
      }
      if (description.getAttribute('nodeID', namespaceUri: _rdfNamespace) != null) {
        throw const FormatException('XMP dependency node references are unsupported.');
      }
      final AiXmpResourceKind kind = property.name.local == 'Manifest' ? .manifest : .ingredient;
      _xmpWhitespace(property);
      if (property.attributes.any((attribute) => !_xmpNamespaceDeclaration(attribute)) || property.childElements.length != 1) {
        throw const FormatException('Ambiguous XMP dependency array.');
      }
      final XmlElement array = property.childElements.single;
      if (!(_xmpName(array, _rdfNamespace, 'Bag') || (kind == .manifest && _xmpName(array, _rdfNamespace, 'Seq'))) || array.attributes.any((attribute) => !_xmpNamespaceDeclaration(attribute))) {
        throw const FormatException('Unsupported XMP dependency array type.');
      }
      _xmpWhitespace(array);
      for (final XmlElement item in array.childElements) {
        if (!_xmpName(item, _rdfNamespace, 'li')) {
          throw const FormatException('Invalid XMP dependency array item.');
        }
        final XmlElement structure = _xmpStructure(item);
        final XmlElement reference;
        String? linkForm;
        if (kind == .manifest) {
          final List<XmlElement> references = structure.childElements.where((element) => _xmpName(element, _manifestNamespace, 'reference')).toList();
          if (references.length != 1 || structure.attributes.any((attribute) => attribute.namespaceUri == _manifestNamespace && attribute.name.local == 'reference')) {
            throw const FormatException('A manifest item requires one resource reference.');
          }
          reference = references.single;
          linkForm = _xmpScalar(structure, _manifestNamespace, 'linkForm');
        } else {
          reference = item;
        }
        final XmlElement fields = _xmpStructure(reference);
        resources.add(
          AiXmpResource._(
            kind: kind,
            index: resources.length,
            filePath: _xmpScalar(fields, _referenceNamespace, 'filePath'),
            documentId: _xmpScalar(fields, _referenceNamespace, 'documentID'),
            instanceId: _xmpScalar(fields, _referenceNamespace, 'instanceID'),
            linkForm: linkForm,
            element: reference,
            span: locations[reference]!,
          ),
        );
      }
    }
  }
  return AiXmpMetadata._(source: source, limits: limits, resources: resources);
}

/// Validates quoted XML attributes and normalizes literal attribute whitespace.
///
/// The shared XML parser also accepts HTML-like unquoted attributes. XMP does
/// not. Entity references are decoded after whitespace normalization so an
/// explicitly escaped tab or carriage return retains its value.
List<String> _xmpAttributeValues(String source, int start, int end, List<XmlEventAttribute> attributes, {bool declaration = false}) {
  int position = start;
  final List<String> values = [];
  final Set<String> names = {};
  for (final XmlEventAttribute attribute in attributes) {
    final int before = position;
    while (position < end && _xmpSpace(source.codeUnitAt(position))) {
      position++;
    }
    if (before == position || !source.startsWith(attribute.name, position) || !names.add('${attribute.namespaceUri ?? ''}|${attribute.localName}')) {
      throw const FormatException('Invalid or duplicate XMP XML attribute.');
    }
    position += attribute.name.length;
    while (position < end && _xmpSpace(source.codeUnitAt(position))) {
      position++;
    }
    if (position >= end || source.codeUnitAt(position++) != 61) {
      throw const FormatException('XMP attributes require an assigned value.');
    }
    while (position < end && _xmpSpace(source.codeUnitAt(position))) {
      position++;
    }
    if (position >= end || ![34, 39].contains(source.codeUnitAt(position))) {
      throw const FormatException('XMP attributes require quoted values.');
    }
    final String quote = source[position++];
    final int close = source.indexOf(quote, position);
    if (close < 0 || close >= end) {
      throw const FormatException('Unterminated XMP XML attribute.');
    }
    final String raw = source.substring(position, close);
    if (raw.contains('<')) {
      throw const FormatException('Unescaped markup in an XMP XML attribute.');
    }
    values.add(const _XmpEntityMapping().decode(raw.replaceAll('\r\n', '\n').replaceAll(RegExp(r'[\r\n\t]'), ' ')));
    position = close + 1;
  }
  while (position < end && _xmpSpace(source.codeUnitAt(position))) {
    position++;
  }
  final String close = source.substring(position, end);
  if (declaration ? close != '?>' : close != '>' && close != '/>') {
    throw const FormatException('Invalid XMP XML tag ending.');
  }
  return values;
}

/// Recognizes XML's four structural whitespace characters only.
bool _xmpSpace(int unit) => unit == 32 || unit == 9 || unit == 10 || unit == 13;

/// Rejects significant text between structural XML children.
void _xmpWhitespace(XmlElement element) {
  if (element.children.any((node) => (node is XmlText || node is XmlCDATA) && node.value!.trim().isNotEmpty)) {
    throw const FormatException('Unexpected text in an XMP structure.');
  }
}

/// Resolves the inline RDF structures used for manifest and ingredient records.
XmlElement _xmpStructure(XmlElement element) {
  _xmpWhitespace(element);
  final String? parseType = element.getAttribute('parseType', namespaceUri: _rdfNamespace);
  if (element.attributes.any((attribute) => attribute.namespaceUri == _rdfNamespace && attribute.name.local != 'parseType') || (parseType != null && parseType != 'Resource')) {
    throw const FormatException('Unsupported XMP resource indirection or qualifier.');
  }
  final List<XmlElement> descriptions = element.childElements.where((child) => _xmpName(child, _rdfNamespace, 'Description')).toList();
  if (descriptions.isEmpty) {
    if (parseType == null && element.childElements.isNotEmpty) {
      throw const FormatException('XMP structured fields require an RDF resource wrapper.');
    }
    return element;
  }
  if (parseType != null || element.childElements.length != 1 || element.attributes.any((attribute) => !_xmpNamespaceDeclaration(attribute))) {
    throw const FormatException('Ambiguous XMP resource structure.');
  }
  final XmlElement description = descriptions.single;
  _xmpWhitespace(description);
  if (description.attributes.any((attribute) => attribute.namespaceUri == _rdfNamespace)) {
    throw const FormatException('XMP resource node identifiers are unsupported.');
  }
  return description;
}

/// Rejects undefined or malformed entities instead of retaining literal markup.
final class _XmpEntityMapping extends XmlDefaultEntityMapping {
  /// Uses only XML's five predefined entities and valid character references.
  const _XmpEntityMapping() : super.xml();

  @override
  String decode(String input) {
    int position = input.indexOf('&');
    while (position >= 0) {
      final int end = input.indexOf(';', position + 1);
      if (end < 0) {
        throw const FormatException('Unterminated XMP entity.');
      }
      decodeEntity(input.substring(position + 1, end));
      position = input.indexOf('&', end + 1);
    }
    return super.decode(input);
  }

  @override
  String decodeEntity(String input) {
    if (input.startsWith('#') && !RegExp(r'^#(?:[0-9]+|x[0-9a-fA-F]+)$').hasMatch(input)) {
      throw const FormatException('Invalid XMP character reference.');
    }
    final String? value = super.decodeEntity(input);
    if (value == null) {
      throw const FormatException('Unknown XMP entity.');
    }
    _validateXmpText(value);
    return value;
  }

  @override
  String encodeText(String input) => super.encodeText(input).replaceAll('\r', '&#xD;');
}

/// Reads one simple property in element, attribute or URI form without trimming.
String? _xmpScalar(XmlElement element, String namespace, String name) {
  final List<XmlAttribute> attributes = element.attributes.where((attribute) => attribute.namespaceUri == namespace && attribute.name.local == name).toList();
  final List<XmlElement> children = element.childElements.where((child) => _xmpName(child, namespace, name)).toList();
  if (attributes.length + children.length > 1) {
    throw const FormatException('Duplicate XMP resource property.');
  }
  if (attributes.isNotEmpty) {
    return attributes.single.value;
  }
  if (children.isEmpty) {
    return null;
  }
  final XmlElement child = children.single;
  final List<XmlAttribute> qualifiers = child.attributes.where((attribute) => !_xmpNamespaceDeclaration(attribute)).toList();
  if (child.childElements.isNotEmpty || qualifiers.any((attribute) => attribute.namespaceUri != _rdfNamespace || attribute.name.local != 'resource')) {
    throw const FormatException('Qualified XMP dependency scalar is unsupported.');
  }
  if (qualifiers.isNotEmpty) {
    if (child.innerText.isNotEmpty) {
      throw const FormatException('Ambiguous XMP URI property.');
    }
    return qualifiers.single.value;
  }
  return child.innerText;
}
