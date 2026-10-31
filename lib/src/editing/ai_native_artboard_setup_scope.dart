part of 'package:aikit/src/model/ai_native_records.dart';

/// Retains declarative setup inventories separately from instantiated artwork.
List<({int start, int end})> _artboardSetupRanges(AiNativeLayers layers) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final List<AiNativeContainer> styles = records.roots.where((record) => record.type == 'KnownStyle' && record.end <= records.program.bodyStart).toList();
  final Set<String> styleNames = {
    for (final AiNativeContainer style in styles)
      if (style['Name']?.stringBytes != null) latin1.decode(style['Name']!.stringBytes!),
  };
  const Map<String, String> sections = {
    '%AI9_BeginArtStyles': '%AI9_EndArtStyles',
    '%AI9_BeginArtStyleList': '%AI9_EndArtStyleList',
    '%AI10_BeginSymbolList': '%AI10_EndSymbolList',
    '%AI24_BeginSymbolList': '%AI24_EndSymbolList',
    '%AI5_BeginPalette': '%AI5_EndPalette',
  };
  final List<({int start, int end})> ranges = [];
  bool setup = false;
  int styleIndex = 0;
  for (int index = 0; index < tokens.length && tokens[index].start < records.program.bodyStart; index++) {
    final AiToken token = tokens[index];
    if (token.kind == .comment && token.lexeme == '%%BeginSetup') {
      setup = true;
    }
    if (!setup) {
      continue;
    }
    if (token.kind == .executableName && token.lexeme == 'Np' && index > 0 && tokens[index - 1].lexeme == '%AI5_Begin_NonPrinting') {
      ranges.add((start: token.start, end: token.end));
      continue;
    }
    if (token.kind != .comment) {
      continue;
    }
    if (token.lexeme == '%AI8_PluginGroupInfo') {
      final List<AiToken> fields = tokens.skip(index + 1).take(3).toList();
      if (fields.length != 3 || fields.any((field) => !const {AiTokenKind.string, AiTokenKind.hexString}.contains(field.kind))) {
        throw UnsupportedError('Retained plug-in inventories require exactly three literal names.');
      }
      if (layers.structure.versions.memberships(start: token.start, end: fields.last.end).isNotEmpty) {
        throw UnsupportedError('Artboard setup inventories require unconditional ownership.');
      }
      ranges.add((start: token.start, end: fields.last.end));
      index += 3;
      continue;
    }
    final String? closing = sections[token.lexeme];
    if (closing == null) {
      continue;
    }
    final int first = index + 1;
    while (++index < tokens.length && tokens[index].start < records.program.bodyStart && !(tokens[index].kind == .comment && tokens[index].lexeme == closing)) {}
    if (index == tokens.length || tokens[index].start >= records.program.bodyStart) {
      throw const FormatException('Unterminated artboard setup inventory.');
    }
    final AiToken end = tokens[index];
    if (layers.structure.versions.blocks.any((block) => block.start < end.end && block.end > token.start)) {
      throw UnsupportedError('Artboard setup inventories require unconditional ownership.');
    }
    final List<AiToken> contents = tokens.sublist(first, index);
    if (token.lexeme == '%AI9_BeginArtStyles') {
      for (final AiToken value in contents) {
        while (styleIndex < styles.length && styles[styleIndex].end <= value.start) {
          styleIndex++;
        }
        if (styleIndex < styles.length &&
            styles[styleIndex].start >= token.end &&
            value.start >= styles[styleIndex].start &&
            value.end <= styles[styleIndex].end &&
            styles[styleIndex].end <= end.start) {
          continue;
        }
        if (value.kind != .comment || value.lexeme.startsWith('%AI') || value.lexeme.startsWith('%%')) {
          throw UnsupportedError('Retained style inventories require complete qualified style records.');
        }
      }
    } else {
      if (contents.any((value) => value.kind == .comment && (value.lexeme.startsWith('%AI') || value.lexeme.startsWith('%%')))) {
        throw UnsupportedError('Artboard setup inventories cannot hide opaque annotations.');
      }
      final List<AiToken> values = contents.where((value) => value.kind != .comment).toList();
      if (token.lexeme == '%AI5_BeginPalette') {
        _artboardProcessPalette(values, records.program.limits);
      } else if (token.lexeme == '%AI9_BeginArtStyleList') {
        if (values.any((value) => !const {AiTokenKind.string, AiTokenKind.hexString}.contains(value.kind) || !styleNames.contains(latin1.decode(aiStringBytes(value))))) {
          throw UnsupportedError('Retained style lists require existing literal style names.');
        }
      } else if (values.isNotEmpty) {
        throw UnsupportedError('Artboard isolation of nonempty symbol inventories requires a separate dependency contract.');
      }
    }
    ranges.add((start: token.start, end: end.end));
  }
  return ranges;
}

/// Checks process-color palette cells and the standard registration swatch.
void _artboardProcessPalette(List<AiToken> tokens, AiNativeLimits limits) {
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: limits.maxDepth);
  bool opened = false;
  bool closed = false;
  bool paint = false;
  for (final AiToken token in tokens) {
    final AiNativeInstruction? command = reader.add(token, isPrivate: false);
    if (command == null) {
      continue;
    }
    if (!opened) {
      if (command.operator != 'Pb' || command.numbers?.length != 2 || command.numbers!.any((value) => value != 0)) {
        throw UnsupportedError('Artboard isolation requires an ordinary process palette.');
      }
      opened = true;
    } else if (closed) {
      throw const FormatException('Unexpected data after a native palette.');
    } else if (command.operator == 'PB') {
      if (command.operands.isNotEmpty || paint) {
        throw const FormatException('Native palette has an unfinished color cell.');
      }
      closed = true;
    } else if (command.operator == 'Pc') {
      if (!paint || command.operands.length != 1 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(command.operands.single.kind)) {
        throw const FormatException('Native palette cells require a color and a literal name.');
      }
      paint = false;
    } else {
      if (paint) {
        throw const FormatException('Native palette has multiple paints for one cell.');
      }
      final List<AiToken> operands = command.operands;
      if (command.operator == 'Xz' || command.operator == 'Xs') {
        final int components = command.operator == 'Xz' ? 7 : 4;
        if (operands.length != (command.operator == 'Xz' ? 10 : 6) ||
            operands.take(components).any((operand) => operand.number == null || !_gradientUnit(operand.number!.toDouble())) ||
            !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands[components].kind) ||
            latin1.decode(aiStringBytes(operands[components])) != '[Registration]' ||
            operands[components + 1].number != 0 ||
            command.operator == 'Xz' && operands[9].number != 1) {
          throw UnsupportedError('Artboard palette isolation requires a standard registration color.');
        }
      } else if (!const {'fill', 'stroke'}.contains(_nativeArtworkStateKey(command))) {
        throw UnsupportedError('Artboard palette isolation does not cover ${command.operator}.');
      }
      paint = true;
    }
  }
  reader.finish();
  if (!opened || !closed) {
    throw const FormatException('Native process palette requires both boundaries.');
  }
}
