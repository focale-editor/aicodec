part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Requires exact owned scalar schemas and delegates explicitly known structures.
void _referenceFields(
  AiNativeContainer record,
  Map<String, Set<String>> fields, {
  bool notRecorded = false,
  Map<String, void Function(AiNativeEntry)> nested = const {},
}) {
  final Set<String?> seen = {};
  for (final AiNativeEntry entry in record.entries) {
    if (!seen.add(entry.key)) {
      throw UnsupportedError('Reference qualification requires unique fields in ${record.type}.');
    }
    if (entry.isQualifier && notRecorded && entry.key == 'NotRecorded') {
      continue;
    }
    if (!entry.isQualifier) {
      if (nested[entry.key] case final void Function(AiNativeEntry) inspect) {
        inspect(entry);
        continue;
      }
    }
    final String? type = entry.type == 'UnicodeString' ? 'String' : entry.type;
    if (entry.isQualifier || !(fields[type]?.contains(entry.key) ?? false)) {
      throw UnsupportedError('Reference qualification does not cover ${record.type}/${entry.key} (${entry.type}).');
    }
  }
}

/// Requires a single nested record rather than ignoring additional entry values.
AiNativeContainer _referenceRecord(AiNativeEntry entry, String type) {
  final AiNativeContainer? record = entry.container;
  if (entry.type != null || record == null || record.type != type) {
    throw UnsupportedError('Reference qualification requires a $type for ${entry.key}.');
  }
  return record;
}

/// Qualifies only an empty reference-bearing owner, never its unknown contents.
void _referenceEmpty(AiNativeEntry entry, String type) {
  if (_referenceRecord(entry, type).entries.isNotEmpty) {
    throw UnsupportedError('Deleting artwork cannot leave unresolved ${entry.key} references.');
  }
}

/// Allows artboard metadata without conflating its page identity with artwork IDs.
void _referenceArtboards(AiNativeEntry entry) {
  for (final AiNativeEntry board in _referenceRecord(entry, 'Array').entries) {
    if (board.key != null || board.isQualifier) {
      throw UnsupportedError('Artboard reference qualification requires ordinary array entries.');
    }
    _referenceFields(_referenceRecord(board, 'Dictionary'), {
      'String': {'Name', 'ArtboardUUID'},
      'Real': {'PAR'},
      'RealPoint': {'RulerOrigin'},
      'RealPointRelToROrigin': {'PositionPoint1', 'PositionPoint2'},
      'Bool': {'IsArtboardDefaultName', 'IsArtboardSelected'},
      'Int': {'DisplayMark'},
    });
  }
}

/// Describes provenance and empty variable, data-set and slice document owners.
const Map<String, ({int kind, Set<String> children, Map<String, String> attributes})> _referenceXmlNodes = {
  '#document': (kind: 9, children: {'metadata'}, attributes: {}),
  'metadata': (kind: 1, children: {'rdf:RDF', 'variableSets', 'sfw'}, attributes: {'id': 'String'}),
  'rdf:RDF': (kind: 1, children: {'cc:Work', 'cc:License'}, attributes: {}),
  'cc:Work': (kind: 1, children: {'dc:format', 'dc:type', 'dc:creator', 'dc:rights', 'dc:publisher', 'dc:identifier', 'dc:date', 'cc:license', 'dc:title'}, attributes: {'rdf:about': 'String'}),
  'cc:License': (kind: 1, children: {'cc:permits', 'cc:requires'}, attributes: {'rdf:about': 'String'}),
  'cc:Agent': (kind: 1, children: {'dc:title'}, attributes: {}),
  'dc:creator': (kind: 1, children: {'cc:Agent'}, attributes: {}),
  'dc:rights': (kind: 1, children: {'cc:Agent'}, attributes: {}),
  'dc:publisher': (kind: 1, children: {'cc:Agent'}, attributes: {}),
  'dc:format': (kind: 1, children: {'#text'}, attributes: {}),
  'dc:identifier': (kind: 1, children: {'#text'}, attributes: {}),
  'dc:date': (kind: 1, children: {'#text'}, attributes: {}),
  'dc:title': (kind: 1, children: {'#text'}, attributes: {}),
  'dc:type': (kind: 1, children: {}, attributes: {'rdf:resource': 'String'}),
  'cc:license': (kind: 1, children: {}, attributes: {'rdf:resource': 'String'}),
  'cc:permits': (kind: 1, children: {}, attributes: {'rdf:resource': 'String'}),
  'cc:requires': (kind: 1, children: {}, attributes: {'rdf:resource': 'String'}),
  '#text': (kind: 3, children: {}, attributes: {}),
  'variableSets': (kind: 1, children: {'variableSet'}, attributes: {'xmlns': 'String'}),
  'variableSet': (kind: 1, children: {'variables', 'v:sampleDataSets'}, attributes: {'locked': 'String', 'varSetName': 'String'}),
  'variables': (kind: 1, children: {}, attributes: {}),
  'v:sampleDataSets': (kind: 1, children: {}, attributes: {'xmlns': 'String', 'xmlns:v': 'String'}),
  'sfw': (kind: 1, children: {'slices', 'sliceSourceBounds'}, attributes: {'xmlns': 'String'}),
  'slices': (kind: 1, children: {}, attributes: {}),
  'sliceSourceBounds': (kind: 1, children: {}, attributes: {'x': 'Real', 'y': 'Real', 'width': 'Real', 'height': 'Real', 'bottomLeftOrigin': 'Bool'}),
};

/// Checks native XML node ownership without interpreting arbitrary XML extensions.
void _referenceXml(AiNativeEntry entry, String name, {String? attributeType}) {
  final AiNativeContainer node = _referenceRecord(entry, 'XMLNode');
  final ({int kind, Set<String> children, Map<String, String> attributes}) schema = attributeType == null ? _referenceXmlNodes[name]! : (kind: 2, children: {}, attributes: {});
  _referenceFields(
    node,
    {
      'Int': {'xmlnode-nodetype', if (attributeType == 'Int') 'xmlnode-nodevalue'},
      'String': {'xmlnode-nodename', if (attributeType == null || attributeType == 'String') 'xmlnode-nodevalue'},
      if (attributeType != null && attributeType != 'String' && attributeType != 'Int') attributeType: {'xmlnode-nodevalue'},
    },
    nested: {
      'xmlnode-children': (field) {
        final Set<String> seen = {};
        for (final AiNativeEntry child in _referenceRecord(field, 'Array').entries) {
          final AiNativeContainer record = _referenceRecord(child, 'XMLNode');
          final String? childName = record['xmlnode-nodename']?.text();
          if (child.key != null || childName == null || !schema.children.contains(childName) || !seen.add(childName) && name != 'cc:License') {
            throw UnsupportedError('Document XML $name has unqualified children or artwork bindings.');
          }
          _referenceXml(child, childName);
        }
      },
      'xmlnode-attributes': (field) {
        final Map<String, void Function(AiNativeEntry)> attributes = {
          for (final MapEntry<String, String> attribute in schema.attributes.entries) attribute.key: (field) => _referenceXml(field, attribute.key, attributeType: attribute.value),
        };
        _referenceFields(_referenceRecord(field, 'Dictionary'), const {}, nested: attributes);
      },
    },
  );
  if (node['xmlnode-nodetype']?.number != schema.kind ||
      node['xmlnode-nodename']?.text() != name ||
      node['xmlnode-nodevalue'] == null ||
      attributeType == null && schema.kind != 3 && node['xmlnode-nodevalue']!.stringBytes?.isEmpty != true) {
    throw UnsupportedError('Document XML $name has an unqualified value or node kind.');
  }
  if (attributeType != null && const {'rdf:about', 'rdf:resource'}.contains(name)) {
    final Uri? resource = Uri.tryParse(node['xmlnode-nodevalue']!.text()!);
    final bool vocabulary = resource?.host == 'creativecommons.org' && resource?.path == '/ns' && resource?.hasQuery == false;
    if (resource == null ||
        name == 'rdf:about' && resource.hasFragment ||
        name == 'rdf:resource' && (!const {'http', 'https'}.contains(resource.scheme) || resource.host.isEmpty || resource.hasFragment && !vocabulary)) {
      throw UnsupportedError('Retained document provenance cannot refer to local artwork fragments.');
    }
  }
}

/// Header numeric settings whose values cannot name or reference artwork owners.
const Map<String, Set<int>> _referenceHeaderNumbers = {
  'Canvassize': {1, 2},
  'AI12_BuildNumber': {1},
  'AI7_ImageSettings': {1},
  'AI3_Cropmarks': {4},
  'AI3_TemplateBox': {4},
  'AI3_TileBox': {4},
  'AI5_ArtSize': {2},
  'AI5_RulerUnits': {1},
  'AI24_RulerUnitsLarge': {1},
  'AI24_LargeCanvasScale': {1},
  'AI9_ColorModel': {1},
  'AI5_ArtFlags': {9},
  'AI5_TargetResolution': {1},
  'PageOrigin': {2},
  'AI7_GridSettings': {12},
  'AI9_Flatten': {1},
  'AI9_OpenToView': {20},
  'AI10_OpenToVie': {23},
};

/// Recognizes explicit header declarations without treating arbitrary comments as safe.
bool _referenceHeaderComment(String comment, AiNativeLimits limits) {
  final RegExpMatch? field = RegExp(r'^%{1,2}([^: ]+):\s*(.*?)\s*$').firstMatch(comment);
  if (field != null) {
    final String key = field[1]!;
    final String value = field[2]!;
    if (_referenceHeaderNumbers[key] case final Set<int> lengths) {
      final List<double?> numbers = value.split(RegExp(r'\s+')).map(double.tryParse).toList();
      if (!lengths.contains(numbers.length) || numbers.any((value) => value == null || !value.isFinite || value.abs() > 9007199254740991)) {
        throw FormatException('Invalid reference-independent header $key.');
      }
      return true;
    }
    if (key == 'AI8_CreatorVersion') {
      return RegExp(r'^\d+(?:\.\d+){1,3}$').hasMatch(value);
    }
    if (key == 'AI3_ColorUsage') {
      return const {'Color', 'Black&White'}.contains(value);
    }
    if (key == 'AI3_DocumentPreview') {
      return value == 'None';
    }
    if (key == 'AI12_CMSettings') {
      return RegExp(r'^[0-9]{2}\.[A-Z]{2}$').hasMatch(value);
    }
    if (key == 'DocumentProcessColors') {
      return value.split(RegExp(r'\s+')).every(const {'Cyan', 'Magenta', 'Yellow', 'Black'}.contains);
    }
    if (key == 'RGBProcessColor' || key == 'CMYKProcessColor') {
      final List<AiToken> tokens = AiPostScript.tokenize(latin1.encode(value), maxBytes: limits.maxDecodedBytes, maxTokens: limits.maxTokens, maxDepth: limits.maxDepth);
      final int components = key == 'RGBProcessColor' ? 3 : 4;
      return tokens.length == components + 1 &&
          tokens.take(components).every((token) => token.number != null && token.number! >= 0 && token.number! <= 1) &&
          const {AiTokenKind.string, AiTokenKind.hexString}.contains(tokens.last.kind);
    }
  }
  return RegExp(r'^%AI5_FileFormat\s+\d+\.\d+\s*$').hasMatch(comment);
}

/// Qualifies source sections outside artwork and checked reference-free records.
void _referenceProgram(AiNativeLayers model, List<({int start, int end})> independent) {
  final AiProgram program = model.drawing.records.program;
  final Set<int> fileDeclarations = _nativeFileDeclarationComments(model.drawing.records);
  final Set<int> declarations = {if (model.rootCountHeader != null) model.rootCountHeader!.token.start, ...model.viewComments.map((token) => token.start)};
  final Set<int> versionMarkers = {
    for (final AiNativeVersionBlock block in model.structure.versions.blocks)
      if (block.end < program.bodyStart) ...[block.opening.start, if (block.alternate != null) block.alternate!.start, block.closing.start],
  };
  const Set<String> markers = {'%%EndComments', '%%BeginProlog', '%%EndProlog', '%%BeginSetup', '%%EndSetup', '%%PageTrailer', '%%Trailer', '%%EOF', '%AI9_BeginDocumentData', '%AI9_EndDocumentData'};
  const Set<String> fields = {'%%Creator', '%%Title', '%%For', '%%CreationDate', '%%BoundingBox', '%%HiResBoundingBox', '%%Pages', '%%Orientation', '%%PageOrder', '%%DocumentData', '%%LanguageLevel'};
  final Set<int> inkDeclarations = _nativeInkHeaders(model.drawing.records).map((row) => row.source.start).toSet();
  final List<String> trailer = [];
  int index = 0;
  bool initial = true;
  bool setup = false;
  bool nonPrinting = false;
  for (final AiToken token in model.drawing.records._projection.tokens) {
    while (index < independent.length && independent[index].end <= token.start) {
      index++;
    }
    if (index < independent.length && independent[index].start <= token.start && token.end <= independent[index].end || token.start >= program.bodyStart && token.end <= program.bodyEnd) {
      continue;
    }
    if (token.kind != .comment) {
      if (token.start >= program.bodyEnd && token.kind == .executableName && trailer.length < 4) {
        trailer.add(token.lexeme);
        continue;
      }
      throw UnsupportedError('Deleting identified artwork requires declarative sections outside its ordinary body: ${token.lexeme} at ${token.start}.');
    }
    if (const {'%%EndComments', '%%BeginProlog', '%%BeginSetup'}.contains(token.lexeme)) {
      initial = false;
    }
    if (token.lexeme == '%%BeginSetup') {
      setup = true;
    } else if (token.lexeme == '%%EndSetup') {
      if (nonPrinting) {
        throw const FormatException('Unterminated nonprinting setup reference scope.');
      }
      setup = false;
    } else if (const {'%AI5_Begin_NonPrinting', '%AI5_End_NonPrinting--'}.contains(token.lexeme)) {
      final bool opening = token.lexeme == '%AI5_Begin_NonPrinting';
      if (!setup || opening == nonPrinting) {
        throw const FormatException('Unbalanced nonprinting setup reference scope.');
      }
      nonPrinting = opening;
      continue;
    }
    if (inkDeclarations.contains(token.start) ||
        declarations.contains(token.start) ||
        fileDeclarations.contains(token.start) ||
        initial && versionMarkers.contains(token.start) ||
        markers.contains(token.lexeme) ||
        fields.contains(token.lexeme.split(':').first)) {
      continue;
    }
    if (RegExp(r'^%{1,2}AI').hasMatch(token.lexeme) || token.lexeme.startsWith('%%')) {
      if (!initial || !_referenceHeaderComment(token.lexeme, program.limits)) {
        throw UnsupportedError('Deleting identified artwork has unqualified metadata outside its ordinary body: ${token.lexeme.split(':').first}.');
      }
    }
  }
  if (nonPrinting) {
    throw const FormatException('Unterminated nonprinting setup reference scope.');
  }
  if (trailer.isNotEmpty && trailer.join(' ') != 'gsave annotatepage grestore showpage') {
    throw UnsupportedError('Deleting identified artwork has an unqualified executable trailer.');
  }
}

/// Qualifies saved SVG canvas coordinates without accepting textual references.
void _referenceSvgCoordinates(AiNativeEntry entry, {required int count}) {
  final List<String>? values = entry.type == 'String' ? entry.text()?.trim().split(RegExp(r'\s+')) : null;
  if (values == null ||
      values.length != count ||
      values.any((value) => double.tryParse(value)?.isFinite != true || double.parse(value).abs() > 9007199254740991 || count == 1 && double.parse(value) <= 0)) {
    throw UnsupportedError('Imported SVG document geometry requires literal portable coordinates and positive dimensions.');
  }
}

/// Proves that a known document record has no artwork-reference-bearing payload.
void _referenceDocument(AiNativeLayers model, AiNativeContainer document) {
  final AiNativeRecords records = model.drawing.records;
  if (document.end > records.program.bodyStart || model.structure.nodeFor(document).versions.isNotEmpty) {
    throw UnsupportedError('Document reference qualification requires unconditional setup ownership.');
  }
  AiNativeContainer? profile;
  _referenceFields(
    document,
    const {},
    nested: {
      'Recorded': (entry) => _referenceFields(
        _referenceRecord(entry, 'Dictionary'),
        _referenceDocumentRecorded,
        nested: {
          'SVG_ViewBoxXY': (entry) => _referenceSvgCoordinates(entry, count: 2),
          'SVG_CropBoxWidth': (entry) => _referenceSvgCoordinates(entry, count: 1),
          'SVG_CropBoxHeight': (entry) => _referenceSvgCoordinates(entry, count: 1),
          'ArtboardArray': _referenceArtboards,
          'Constraint Data': (entry) => _referenceEmpty(entry, 'Array'),
          'GenAIRecorded': (entry) => _referenceFields(
            _referenceRecord(entry, 'Dictionary'),
            const {},
            nested: {
              'MigratedArtList': (entry) => _referenceEmpty(entry, 'Array'),
              'GenAIVariationsDictionary': (entry) => _referenceEmpty(entry, 'Dictionary'),
            },
          ),
          'DocumentDict/ExportableAssetsKey': (entry) => _referenceEmpty(entry, 'Dictionary'),
          'SelHatDocTableDict': (entry) => _referenceFields(
            _referenceRecord(entry, 'Dictionary'),
            const {},
            nested: {
              'SelHatDocLocalNamesArray': (entry) => _referenceEmpty(entry, 'Array'),
              'SelHatDocInterIDsArray': (entry) => _referenceEmpty(entry, 'Array'),
            },
          ),
          'AI Auto Rasterize': (entry) => _referenceFields(_referenceRecord(entry, 'Dictionary'), {
            'Int': {'colr', 'dpi.'},
            'Real': {'padd'},
            'Bool': {'alis', 'mask', 'spot'},
          }),
          '#document': (entry) => _referenceXml(entry, '#document'),
        },
      ),
      'NotRecorded': (entry) {
        final AiNativeContainer settings = _referenceRecord(entry, 'Dictionary');
        _referenceFields(
          settings,
          _referenceDocumentNotRecorded,
          notRecorded: true,
          nested: {
            'AI12 Document Profile Data': (entry) {
              profile = _referenceRecord(entry, 'Binary');
            },
            'PDFPresetCollection': (entry) => _referenceFields(_referenceRecord(entry, 'Dictionary'), _referencePdfPreset, notRecorded: true),
            'AI11 Print JobInfo Dict': (entry) => _referenceFields(_referenceRecord(entry, 'Dictionary'), _referencePrintJob, notRecorded: true),
            'AI11 Print Attribute Dict': (entry) {
              final AiNativeContainer attributes = _referenceRecord(entry, 'Dictionary');
              _referenceFields(attributes, _referencePrintAttributes, notRecorded: true);
              if (attributes['/attributes/rdrs.custom']?.stringBytes?.isNotEmpty ?? false) {
                throw UnsupportedError('Custom PostScript screening requires separate reference qualification.');
              }
            },
            'AI11 Ink List Dict': (entry) {
              final AiNativeContainer inks = _referenceRecord(entry, 'Dictionary');
              _referenceFields(inks, {
                'Int': {'/attributes/inklst.count'},
              }, notRecorded: true);
              if (inks['/attributes/inklst.count']?.number != 0) {
                throw UnsupportedError('Document ink references require a separate qualification.');
              }
            },
          },
        );
        final double? size = settings['AI12 Document Profile Size']?.number;
        if (profile != null || size != null) {
          if (profile == null || !profile!.hasBinary || profile!.entries.isNotEmpty || size == null) {
            throw const FormatException('Document profile data and size must have matching ownership.');
          }
          final Uint8List bytes = profile!.decodeBinary(maxOutputBytes: records.program.limits.maxDecodedBytes);
          if (bytes.length < 128 || bytes.length != size || ByteData.sublistView(bytes).getUint32(0) != bytes.length || latin1.decode(bytes.sublist(36, 40)) != 'acsp') {
            throw const FormatException('Document profile data does not match its ICC header and size.');
          }
        }
      },
    },
  );
  for (final AiToken token in _pathInterval(records._projection.tokens, document.start, document.end, (token) => token.start)) {
    if (profile != null && token.start >= profile!._binaryStart! && token.end <= profile!._binaryEnd!) {
      continue;
    }
    if (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'))) {
      throw UnsupportedError('Document reference metadata has conditional or opaque annotations.');
    }
  }
}
