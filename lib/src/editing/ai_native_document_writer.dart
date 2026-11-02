part of 'package:aikit/src/model/ai_native_records.dart';

/// Explicit initial paint state for newly authored ordinary artwork.
const String _newDocumentState = '0 A 0 Xw 0 Ap 0 D 0 XR 0 O 0 R 0 g 0 G 0 J 0 j 1 w 10 M [] 0 d 0 1 0 0 0 Xy\n';

/// A bounded byte accumulator shared by initial native document sections.
final class _NativeDocumentBytes {
  /// Maximum serialized bytes for this section or complete program.
  final int maximum;

  /// Owned bytes accumulated without repeated whole-program copying.
  final BytesBuilder _output = BytesBuilder(copy: false);

  /// Creates one bounded writer under the caller's native policy.
  _NativeDocumentBytes({required this.maximum});

  /// Appends a complete fragment after checking aggregate growth.
  void add(List<int> bytes) {
    if (_output.length + bytes.length > maximum) {
      throw const AiLimitException(message: 'New native document exceeds the output byte limit.');
    }
    _output.add(bytes);
  }

  /// Appends fixed grammar and already escaped string/numeric data.
  void text(String value) {
    if (_output.length + value.length > maximum) {
      throw const AiLimitException(message: 'New native document exceeds the output byte limit.');
    }
    add(latin1.encode(value));
  }

  /// Transfers the completed section to its immutable parser or container.
  Uint8List takeBytes() => _output.takeBytes();
}

/// Joins host-computed extents without deriving paint or geometry bounds.
AiBoundingBox _newDocumentBounds(AiBoundingBox first, AiBoundingBox second) => AiBoundingBox(
  left: min(first.left, second.left),
  bottom: min(first.bottom, second.bottom),
  right: max(first.right, second.right),
  top: max(first.top, second.top),
);

/// Validates deterministic timestamps before creating native or PDF metadata.
DateTime _newDocumentDate(DateTime value) {
  final DateTime utc = value.toUtc();
  if (utc.year < 1 || utc.year > 9999) {
    throw ArgumentError('New AI metadata requires a UTC year between 1 and 9999.');
  }
  return utc;
}

/// Authors a complete native profile without importing any producer template.
AiNativeRecords _createNativeDocument(
  List<AiNativeArtboardDefinition> artboards,
  List<AiNativeDocumentLayer> layers,
  List<int> titleBytes,
  AiNativeDocumentColorMode colorMode,
  DateTime createdAt,
  int activeArtboard,
  int lastArtboardId,
  AiBoundingBox? inkBounds,
  AiNativeRulerUnit rulerUnit,
  List<double> pageOrigin,
  double canvasSize,
  AiNativeLimits limits,
) {
  limits.validate();
  final DateTime date = _newDocumentDate(createdAt);
  if (artboards.isEmpty ||
      layers.isEmpty ||
      activeArtboard < 0 ||
      activeArtboard >= artboards.length ||
      lastArtboardId < artboards.length ||
      lastArtboardId > 9007199254740991 ||
      pageOrigin.length != 2 ||
      canvasSize <= 0) {
    throw ArgumentError('New documents require boards, layers, valid active/counter values and explicit canvas coordinates.');
  }
  if (artboards.length + layers.length > limits.maxTokens) {
    throw const AiLimitException(message: 'New document owners exceed native limits.');
  }
  _nativeArtboardCoordinates([
    canvasSize,
    ...pageOrigin,
    if (inkBounds != null) ...[inkBounds.left, inkBounds.bottom, inkBounds.right, inkBounds.top],
  ]);
  final String title = latin1.decode(_nativeLiteralString(titleBytes, limits.maxDecodedBytes));
  final Set<String> boardIdentities = {};
  AiBoundingBox bounds = inkBounds ?? artboards.first.bounds;
  final _NativeDocumentBytes setup = _NativeDocumentBytes(maximum: limits.maxDecodedBytes);
  setup.text('%%BeginSetup\n%_/Document : /Dictionary : /Array :\n%_');
  for (final AiNativeArtboardDefinition board in artboards) {
    if (!boardIdentities.add(latin1.decode(board.identifierBytes).toLowerCase())) {
      throw ArgumentError('New documents require distinct artboard UUIDs.');
    }
    if (inkBounds == null) {
      bounds = _newDocumentBounds(bounds, board.bounds);
    }
    setup.add(_nativeArtboardDefinitionBytes(board, limits.maxDecodedBytes, '\n'));
  }
  setup.text(
    '; (ArtboardArray) ,\n%_$activeArtboard /Int (CropAreaActive) ,\n%_; /Recorded ,\n'
    '%_/Dictionary : /NotRecorded ,\n%_$lastArtboardId /Int (LastArtboardID) ,\n%_; /NotRecorded , ;\n%%EndSetup\n',
  );
  final Uint8List setupBytes = setup.takeBytes();
  final AiBoundingBox crop = artboards[activeArtboard].bounds;
  final int unit = switch (rulerUnit) {
    .inches => 0,
    .millimeters => 1,
    .points => 2,
    .picas => 3,
    .centimeters => 4,
    .pixels => 6,
    .feetAndInches => 7,
    .meters => 8,
    .yards => 9,
    .feet => 10,
  };

  /// Writes the final extent and root count without inventing fonts or profiles.
  String header(int roots) =>
      '%!PS-Adobe-3.0\n%%Creator: AiKit\n%%AI8_CreatorVersion: 24.0.0\n'
      '%%Title: $title\n%%CreationDate: ${date.toIso8601String()}\n%%Canvassize: $canvasSize\n'
      '%%BoundingBox: ${bounds.left.floor()} ${bounds.bottom.floor()} ${bounds.right.ceil()} ${bounds.top.ceil()}\n'
      '%%HiResBoundingBox: ${bounds.left} ${bounds.bottom} ${bounds.right} ${bounds.top}\n'
      '%%DocumentProcessColors: Cyan Magenta Yellow Black\n%%DocumentFonts: (none)\n%%DocumentNeededFonts: (none)\n'
      '%AI5_FileFormat 14.0\n%AI3_ColorUsage: Color\n%AI3_DocumentPreview: None\n'
      '%AI3_Cropmarks: ${crop.left} ${crop.bottom} ${crop.right} ${crop.top}\n'
      '%AI5_RulerUnits: ${unit < 7 ? unit : 2}\n${unit < 7 ? '' : '%AI24_RulerUnitsLarge: $unit\n'}'
      '%AI24_LargeCanvasScale: 1\n%AI9_ColorModel: ${colorMode.index}\n%AI5_NumLayers: $roots\n'
      '%%PageOrigin: ${pageOrigin.join(' ')}\n%%EndComments\n%%BeginProlog\n%%EndProlog\n';

  /// Produces complete source boundaries under the same aggregate byte budget.
  Uint8List program(int roots, List<int> body) {
    final _NativeDocumentBytes output = _NativeDocumentBytes(maximum: limits.maxDecodedBytes);
    output.text(header(roots));
    output.add(setupBytes);
    output.text(_newDocumentState);
    output.add(body);
    output.text('%%PageTrailer\n%%Trailer\n%%EOF\n');
    return output.takeBytes();
  }

  // Existing path writers use the empty snapshot only to validate fresh metadata.
  final AiNativeDrawing empty = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(bytes: program(0, const []), limits: limits),
    ),
  );
  final _NativeDocumentBytes body = _NativeDocumentBytes(maximum: limits.maxDecodedBytes);
  final Set<String> identities = {};
  int owners = artboards.length;

  /// Serializes a layer tree once, retaining explicit path and layer order.
  void layer(AiNativeDocumentLayer node, int depth) {
    if (++owners > limits.maxTokens || depth >= limits.maxDepth) {
      throw const AiLimitException(message: 'New document layer tree exceeds native limits.');
    }
    final AiNativeLayerDefinition definition = node.definition;
    final String name = latin1.decode(_nativeLiteralString(definition.nameBytes, limits.maxDecodedBytes));
    body.text('%AI5_BeginLayer\n${definition.attributes.map((value) => value.toInt()).join(' ')} Lb\n$name Ln\n${definition.expanded ? 1 : 0} AE\n');
    if (definition.identifierBytes case final List<int> identifier) {
      final String encoded = latin1.decode(_newNativeIdentity(identifier, identities, limits.maxDecodedBytes));
      body.text('%_/ArtDictionary :\n%_/XMLUID : $encoded ; (AI10_ArtUID) ,\n%_;\n');
    }
    for (final AiNativePathDefinition path in node.paths) {
      if (++owners > limits.maxTokens) {
        throw const AiLimitException(message: 'New document paths exceed native limits.');
      }
      if (path.identifierBytes case final List<int> identifier) {
        _newNativeIdentity(identifier, identities, limits.maxDecodedBytes);
      }
      body.add(_createdNativePathBytes(empty, path));
      bounds = _newDocumentBounds(bounds, path.bounds);
    }
    for (final AiNativeDocumentLayer child in node.children) {
      layer(child, depth + 1);
    }
    body.text('LB\n%AI5_EndLayer--\n');
  }

  for (final AiNativeDocumentLayer node in layers) {
    layer(node, 0);
  }
  final AiNativeRecords result = AiNativeRecords.decode(
    program: AiProgram.decode(bytes: program(layers.length, body.takeBytes()), limits: limits),
  );
  final AiNativeLayers inventory = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: result));
  if (!inventory.rootCountMatches || inventory.layers.any((layer) => layer.bindingIssue != null)) {
    throw const FormatException('Created document disrupted layer ownership.');
  }
  AiNativeArtboards.decode(records: result);
  return result;
}
