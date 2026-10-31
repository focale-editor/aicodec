part of 'ai_postscript.dart';

/// Bounds a binary XI payload by its validated raster geometry, never a search.
///
/// CC writers sometimes count one extra byte or omit the separate alpha plane
/// from BeginData. Only these measured variants are accepted, and only when the
/// computed sample boundary lands exactly on EndData (or its line separator).
({int samples, int end})? _rasterData({required Uint8List bytes, required int start, required int declared, required List<AiToken> tokens, required bool privateData}) {
  if (start + 3 > bytes.length || bytes[start] != 88 || bytes[start + 1] != 73 || bytes[start + 2] != 10 && bytes[start + 2] != 13) {
    return null;
  }
  int samples = start + 3;
  if (bytes[start + 2] == 13 && samples < bytes.length && bytes[samples] == 10) {
    samples++;
  }
  final List<AiToken> header = [];
  for (int index = tokens.length - 2; index >= 0 && header.length < 24; index--) {
    final AiToken token = tokens[index];
    if (token.kind == .comment) {
      if (token.lexeme.startsWith('%_')) {
        final List<AiToken> fields = AiPostScript.tokenize(latin1.encode(token.lexeme.substring(2)), maxTokens: 32);
        header.addAll(fields.reversed);
        if (fields.any((field) => field.kind == .arrayStart)) {
          break;
        }
      }
      continue;
    }
    header.add(token);
    if (token.kind == .arrayStart) {
      break;
    }
  }
  final List<AiToken> operands = header.reversed.toList();
  if (!const {20, 23, 24}.contains(operands.length) ||
      operands.first.kind != .arrayStart ||
      operands[7].kind != .arrayEnd ||
      operands.indexed.any((item) => item.$1 != 0 && item.$1 != 7 && item.$2.number == null)) {
    throw const FormatException('Invalid binary Illustrator raster header.');
  }
  final List<double> values = operands.skip(8).map((token) => token.number!.toDouble()).toList();
  if (values.skip(4).any((value) => value != value.truncateToDouble()) || values[4] <= 0 || values[5] <= 0 || values[4] > bytes.length || values[5] > bytes.length) {
    throw const FormatException('Invalid Illustrator raster dimensions.');
  }
  final int width = values[4].toInt();
  final int height = values[5].toInt();
  final int bits = values[6].toInt();
  final int channels = values[7].toInt();
  final int alpha = values[8].toInt();
  if (!const {1, 2, 4, 8, 16}.contains(bits) || !const {1, 3, 4}.contains(channels) || !const {0, 1}.contains(alpha) || values[10] != 1) {
    throw UnsupportedError('Unsupported binary Illustrator raster sample layout.');
  }
  final int row = (width * channels * bits + 7) ~/ 8;
  final int alphaRow = alpha * ((width * bits + 7) ~/ 8);
  if (row + alphaRow > (bytes.length - samples) ~/ height) {
    throw const FormatException('Truncated Illustrator raster samples.');
  }
  final int colors = row * height;
  final int length = (row + alphaRow) * height;
  final int prefix = samples - start;
  final int end = samples + length;
  int terminator = end;
  if (terminator < bytes.length && bytes[terminator] == 13) {
    terminator++;
  }
  if (terminator < bytes.length && bytes[terminator] == 10) {
    terminator++;
  }
  if (!{prefix + length, prefix + length + 1, prefix + colors, prefix + colors + 1, terminator - start}.contains(declared)) {
    throw const FormatException('Inconsistent Illustrator raster data count.');
  }
  final String marker = privateData ? '%_%%EndData' : '%%EndData';
  if (terminator + marker.length > bytes.length ||
      latin1.decode(Uint8List.sublistView(bytes, terminator, terminator + marker.length)) != marker ||
      terminator + marker.length < bytes.length && !_space(bytes[terminator + marker.length])) {
    throw const FormatException('Invalid Illustrator raster data boundary.');
  }
  return (samples: samples, end: end);
}
