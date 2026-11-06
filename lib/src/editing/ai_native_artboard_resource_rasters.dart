part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Shares source-backed raster inspection across retained resource artwork.
final class _ArtboardResourceInspection {
  /// Original document structure and parsing policy.
  final AiNativeLayers layers;

  /// Whether this inspection is restricted to original setup resources.
  final bool setupOnly;

  /// Resource and mask drawings awaiting common geometry/reference checks.
  final List<AiNativeDrawing> drawings = [];

  /// Lazily decoded source images, independent of the host's rendering state.
  List<AiNativeRaster>? _rasters;

  /// Creates one inspection context for an immutable native program.
  _ArtboardResourceInspection({required this.layers, this.setupOnly = true});

  /// Decodes each binary image once, retaining the original byte boundaries.
  List<AiNativeRaster> get rasters => _rasters ??= _readNativeRasters(layers.drawing.records, false);
}

/// Qualifies process raster metadata and its complete binary framing.
void _artboardResourceRaster(AiNativeRecords records, AiNativeRaster image) {
  image.validateProcessLayout();
  const List<String> commands = ['XG', 'XN', 'Xh', 'XI', 'XH'];
  if (image.commands.length != commands.length ||
      image.commands.indexed.any((entry) => entry.$2.operator != commands[entry.$1] || entry.$2.isPrivate != image.instruction.isPrivate) ||
      image.commands.any((command) => command.operands.any((operand) => operand.number != null && (!operand.number!.isFinite || operand.number!.abs() > 9007199254740991)))) {
    throw UnsupportedError('Retained resource rasters require complete literal process-image commands.');
  }
  final List<AiToken> tokens = _pathInterval(records._projection.tokens, image.start, image.end, (token) => token.start).toList();
  int endings = 0;
  for (final AiToken token in tokens) {
    if (token.kind == .data) {
      if (!identical(token, image.data)) {
        throw const FormatException('A retained resource raster has unrelated binary data.');
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
      throw UnsupportedError('Retained resource rasters cannot hide opaque or conditional annotations.');
    }
  }
  if (endings != 1) {
    throw const FormatException('A retained resource raster requires one binary closing boundary.');
  }
}

/// Allows only checked raster spans and their immediate empty file annotations.
void _artboardResourceAnnotations(_ArtboardResourceInspection scope, int start, int end, List<AiNativeRaster> rasters, {List<AiNativeContainer> metadata = const []}) {
  final List<AiToken> tokens = scope.layers.drawing.records._projection.tokens;
  final Map<int, AiNativeRaster> openings = {for (final AiNativeRaster image in rasters) image.start: image};
  int imageIndex = 0;
  int owner = 0;
  for (int index = _pathOffset(tokens, start, (token) => token.start); index < tokens.length && tokens[index].start < end; index++) {
    final AiToken token = tokens[index];
    while (owner < metadata.length && metadata[owner].end <= token.start) {
      owner++;
    }
    if (owner < metadata.length && token.start >= metadata[owner].start && token.end <= metadata[owner].end) {
      continue;
    }
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
      throw UnsupportedError('Retained resources cannot hide unrelated data or annotations.');
    }
  }
}
