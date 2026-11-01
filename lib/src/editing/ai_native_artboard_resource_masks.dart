part of 'package:aikit/src/model/ai_native_records.dart';

/// Shares source-backed raster inspection across retained resource masks.
final class _ArtboardResourceInspection {
  /// Original document structure and parsing policy.
  final AiNativeLayers layers;

  /// Resource and mask drawings awaiting common geometry/reference checks.
  final List<AiNativeDrawing> drawings = [];

  /// Lazily decoded source images, independent of the host's rendering state.
  List<AiNativeRaster>? _rasters;

  /// Creates one inspection context for an immutable native program.
  _ArtboardResourceInspection({required this.layers});

  /// Decodes each binary image once, retaining the original byte boundaries.
  List<AiNativeRaster> get rasters => _rasters ??= _readNativeRasters(layers.drawing.records, false);
}

/// Checks flags and owned mask artwork without changing its linked coordinates.
void _artboardOpacityMask(_ArtboardResourceInspection scope, AiNativeContainer source) {
  final AiNativeRecords records = scope.layers.drawing.records;
  if (source.hasBinary ||
      source.end > records.program.bodyStart ||
      scope.layers.structure.nodeFor(source).versions.isNotEmpty ||
      source.entries.any((entry) => entry.key != null || entry.type != null || entry.isQualifier || entry.items.isEmpty)) {
    throw UnsupportedError('Retained opacity masks require unconditional literal setup fields.');
  }
  // Mask uses dictionary suffixes, but generic inspection preserves its raw entries.
  final AiNativeContainer mask = AiNativeContainer._(
    start: source.start,
    end: source.end,
    type: source.type,
    entries: source.entries.map((entry) => _NativeRecordReader._entry(type: 'Dictionary', items: entry.items)).toList(),
  );
  _referenceFields(
    mask,
    {
      'Bool': {'Linked', 'Disabled', 'Clipping', 'Inverted'},
    },
    nested: {
      'Art': (entry) {
        if (entry.type != null || entry.items.isEmpty) {
          throw const FormatException('A retained opacity mask requires a complete artwork field.');
        }
      },
    },
  );
  if (mask.entries.length != 5 || mask['Art'] == null) {
    throw UnsupportedError('Retained opacity masks require explicit artwork and all four flags.');
  }
  final AiNativeEntry art = mask['Art']!;
  final List<AiNativeRaster> rasters = _pathInterval(scope.rasters, source.start, source.end, (image) => image.start).toList();
  final Map<AiNativeContainer, AiNativeRaster> metadata = {};
  for (final AiNativeRaster image in rasters) {
    if (image.start < art.items.first.start || image.end > art.items.last.end) {
      throw const FormatException('A retained mask raster crosses its artwork field.');
    }
    _artboardMaskRaster(records, image);
    if (image.dictionary != null) {
      metadata[image.dictionary!] = image;
    }
  }
  final List<AiNativeItem> items = [];
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
  int rasterIndex = 0;
  AiNativeRaster? active;
  for (final AiNativeItem item in art.items) {
    while (rasterIndex < rasters.length && rasters[rasterIndex].end <= item.start) {
      rasterIndex++;
    }
    if (rasterIndex < rasters.length && item.start >= rasters[rasterIndex].start) {
      final AiNativeRaster image = rasters[rasterIndex];
      if (item.end > image.end) {
        throw const FormatException('Retained raster commands cross their owned section.');
      }
      if (!identical(active, image)) {
        reader.finish();
        items.add(image);
        active = image;
      }
      continue;
    }
    if (item is AiNativeContainer) {
      reader.finish();
      _artboardSymbolMetadata(scope, item, raster: metadata[item]);
      items.add(item);
    } else if (item is AiNativeToken) {
      final AiNativeInstruction? instruction = reader.add(item.token, isPrivate: records._projection.isPrivate(item.start));
      if (instruction != null) {
        if (instruction.operator == 'N' && instruction.operands.isNotEmpty) {
          throw const FormatException('A retained raster terminator cannot consume operands.');
        }
        items.add(instruction);
      }
    } else {
      throw const FormatException('Unexpected retained opacity mask artwork.');
    }
  }
  reader.finish();
  if (items.length < 2 ||
      items.first is! AiNativeInstruction ||
      items.last is! AiNativeInstruction ||
      (items.first as AiNativeInstruction).operator != 'X=' ||
      (items.last as AiNativeInstruction).operator != 'X+' ||
      (items.first as AiNativeInstruction).operands.isNotEmpty ||
      (items.last as AiNativeInstruction).operands.isNotEmpty ||
      (items.first as AiNativeInstruction).isPrivate != (items.last as AiNativeInstruction).isPrivate) {
    throw const FormatException('Retained opacity masks require matching empty artwork boundaries.');
  }
  _artboardMaskAnnotations(scope, source, rasters);
  scope.drawings.add(_NativeDrawingReader(records: records).readItems(items.sublist(1, items.length - 1)));
}

/// Qualifies process raster metadata and its complete binary framing.
void _artboardMaskRaster(AiNativeRecords records, AiNativeRaster image) {
  image.validateProcessLayout();
  const List<String> commands = ['XG', 'XN', 'Xh', 'XI', 'XH'];
  if (image.commands.length != commands.length ||
      image.commands.indexed.any((entry) => entry.$2.operator != commands[entry.$1] || entry.$2.isPrivate != image.instruction.isPrivate) ||
      image.commands.any((command) => command.operands.any((operand) => operand.number != null && (!operand.number!.isFinite || operand.number!.abs() > 9007199254740991)))) {
    throw UnsupportedError('Retained mask rasters require complete literal process-image commands.');
  }
  final List<AiToken> tokens = _pathInterval(records._projection.tokens, image.start, image.end, (token) => token.start).toList();
  int endings = 0;
  for (final AiToken token in tokens) {
    if (token.kind == .data) {
      if (!identical(token, image.data)) {
        throw const FormatException('A retained mask raster has unrelated binary data.');
      }
      continue;
    }
    if (token.kind != .comment || !token.lexeme.startsWith('%AI') && !token.lexeme.startsWith('%%')) {
      continue;
    }
    if (records._projection.isPrivate(token.start) != image.instruction.isPrivate ||
        !(token.start == image.start && token.lexeme == '%AI5_BeginRaster' ||
            token.end == image.end && token.lexeme == '%AI5_EndRaster' ||
            identical(token, image.declaration) ||
            token.lexeme == '%%EndData' && ++endings == 1)) {
      throw UnsupportedError('Retained mask rasters cannot hide opaque or conditional annotations.');
    }
  }
  if (endings != 1) {
    throw const FormatException('A retained mask raster requires one binary closing boundary.');
  }
}

/// Allows only checked raster spans and their immediate empty file annotations.
void _artboardMaskAnnotations(_ArtboardResourceInspection scope, AiNativeContainer mask, List<AiNativeRaster> rasters) {
  final List<AiToken> tokens = scope.layers.drawing.records._projection.tokens;
  final Map<int, AiNativeRaster> openings = {for (final AiNativeRaster image in rasters) image.start: image};
  int imageIndex = 0;
  for (int index = _pathOffset(tokens, mask.start, (token) => token.start); index < tokens.length && tokens[index].start < mask.end; index++) {
    final AiToken token = tokens[index];
    while (imageIndex < rasters.length && rasters[imageIndex].end <= token.start) {
      imageIndex++;
    }
    if (imageIndex < rasters.length && token.start >= rasters[imageIndex].start && token.end <= rasters[imageIndex].end) {
      continue;
    }
    final AiNativeRaster? image = index + 1 < tokens.length ? openings[tokens[index + 1].start] : null;
    if (token.kind == .comment && token.lexeme == '%AI5_File:' && image != null) {
      if (scope.layers.drawing.records._projection.isPrivate(token.start) == image.instruction.isPrivate) {
        continue;
      }
    }
    if (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'))) {
      throw UnsupportedError('Retained masks cannot hide unrelated data or annotations.');
    }
  }
}
