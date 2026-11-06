part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Retains font encodings in their own namespace during artboard-only changes.
List<({int start, int end})> _artboardFontSetupRanges(AiNativeLayers layers, List<_NativeFontEncoding> fonts) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final List<({int start, int end})> ranges = [];
  for (final _NativeFontEncoding font in fonts) {
    int start = font.start;
    int end = font.end;
    if (font.names.isNotEmpty) {
      final int first = _pathOffset(tokens, start, (token) => token.start);
      final int next = _pathOffset(tokens, end, (token) => token.start);
      final AiToken? opening = first > 0 ? tokens[first - 1] : null;
      final AiToken? closing = next < tokens.length ? tokens[next] : null;
      if (opening == null ||
          closing == null ||
          opening.kind != .comment ||
          closing.kind != .comment ||
          !opening.lexeme.startsWith('%AI3_BeginEncoding:') ||
          opening.lexeme.substring('%AI3_BeginEncoding:'.length).trim().split(RegExp(r'\s+')).join(' ') != font.names.join(' ') ||
          !const {'%AI3_EndEncoding AdobeType', '%AI3_EndEncoding TrueType'}.contains(closing.lexeme)) {
        throw UnsupportedError('Retained font declarations require matching names and complete encoding wrappers.');
      }
      start = opening.start;
      end = closing.end;
    }
    if (layers.structure.versions.blocks.any((block) => block.start < end && block.end > start)) {
      throw UnsupportedError('Artboard font encodings require unconditional setup ownership.');
    }
    ranges.add((start: start, end: end));
  }
  bool initial = true;
  bool setup = false;
  for (final AiToken token in tokens) {
    if (token.start >= records.program.bodyStart) {
      break;
    }
    if (token.kind != .comment) {
      continue;
    }
    if (const {'%%EndComments', '%%BeginProlog', '%%BeginSetup'}.contains(token.lexeme)) {
      initial = false;
    }
    if (token.lexeme == '%%BeginSetup') {
      setup = true;
    } else if (token.lexeme == '%%EndSetup') {
      setup = false;
    }
    if (initial && (token.lexeme.startsWith('%%DocumentFonts:') || token.lexeme.startsWith('%%DocumentNeededFonts:'))) {
      final List<AiToken> names = AiPostScript.tokenize(
        latin1.encode(token.lexeme.substring(token.lexeme.indexOf(':') + 1)),
        maxBytes: records.program.limits.maxDecodedBytes,
        maxTokens: records.program.limits.maxTokens,
        maxDepth: records.program.limits.maxDepth,
      );
      final bool none = names.length == 1 && names.single.kind == .string && latin1.decode(aiStringBytes(names.single)) == 'none';
      if (!none && (names.isEmpty || names.any((name) => name.kind != .executableName))) {
        throw UnsupportedError('Retained font headers require literal font-name inventories.');
      }
    } else if (!setup || token.lexeme != '%AI55J_Tsume: None') {
      continue;
    }
    if (layers.structure.versions.memberships(start: token.start, end: token.end).isNotEmpty) {
      throw UnsupportedError('Artboard font metadata requires unconditional ownership.');
    }
    ranges.add((start: token.start, end: token.end));
  }
  return ranges;
}
