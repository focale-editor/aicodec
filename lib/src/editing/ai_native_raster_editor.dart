part of 'package:aikit/src/model/ai_native_records.dart';

/// Rewrites both image placement matrices while preserving all sample bytes.
AiNativeRasters _translateNativeRasters(AiNativeRasters source, List<AiNativeRaster> images, double deltaX, double deltaY) {
  if (!deltaX.isFinite || !deltaY.isFinite || images.toSet().length != images.length || images.any((image) => !source.images.contains(image))) {
    throw ArgumentError('Translation requires finite offsets and images owned by this snapshot.');
  }
  if (images.isEmpty || deltaX == 0 && deltaY == 0) {
    return source;
  }
  final List<AiSourceEdit> edits = [...AiNativeEditor.translationBoundsEdits(program: source.records.program, deltaX: deltaX, deltaY: deltaY)];
  for (final AiNativeRaster image in images) {
    final Set<String> seen = {};
    for (final AiNativeInstruction command in image.commands) {
      if (!const {'XG', 'XN', 'Xh', 'XI', 'XH'}.contains(command.operator) || !seen.add(command.operator)) {
        throw UnsupportedError('Native raster translation requires resolved placement commands.');
      }
      if (command.operator != 'Xh' && command.operator != 'XI') {
        continue;
      }
      if (command.operands.length < 8 ||
          command.operands.first.kind != .arrayStart ||
          command.operands[7].kind != .arrayEnd ||
          command.operands.skip(1).take(6).indexed.any((item) => item.$2.number != image.matrix[item.$1])) {
        throw UnsupportedError('Native raster placement matrices disagree.');
      }
      for (final (int, double) coordinate in [(5, deltaX), (6, deltaY)]) {
        final AiToken token = command.operands[coordinate.$1];
        final double value = token.number!.toDouble() + coordinate.$2;
        if (!value.isFinite || value.abs() > 9007199254740991) {
          throw ArgumentError('Raster translation exceeds finite source-coordinate bounds.');
        }
        edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode(value.toString())));
      }
    }
  }
  return AiNativeRasters.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
  );
}
