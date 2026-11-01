part of 'package:aikit/src/model/ai_native_records.dart';

/// Retains declarative setup inventories separately from instantiated artwork.
List<({int start, int end})> _artboardSetupRanges(AiNativeLayers layers, {required Set<String> patternNames, required Set<String> symbolNames}) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final List<AiNativeContainer> styles = records.roots.where((record) => record.type == 'KnownStyle' && record.end <= records.program.bodyStart).toList();
  final Set<String> styleNames = {
    for (final AiNativeContainer style in styles)
      if (style['Name']?.stringBytes != null) latin1.decode(style['Name']!.stringBytes!),
  };
  final Map<int, AiNativeResourceUse> gradientUses = {for (final AiNativeResourceUse use in layers.structure.resourceUses.where((use) => use.kind == .gradient)) use.instruction.start: use};
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
    final String section = token.lexeme == '%AI10_BeginSymbolList\u0000' ? '%AI10_BeginSymbolList' : token.lexeme;
    final String? closing = sections[section];
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
        if (values.any((value) => records._projection.isPrivate(value.start))) {
          throw UnsupportedError('Retained palettes require ordinary operands and commands.');
        }
        _artboardPalette(values, records.program.limits, gradientUses, patternNames);
      } else if (token.lexeme == '%AI9_BeginArtStyleList') {
        if (values.any((value) => !const {AiTokenKind.string, AiTokenKind.hexString}.contains(value.kind) || !styleNames.contains(latin1.decode(aiStringBytes(value))))) {
          throw UnsupportedError('Retained style lists require existing literal style names.');
        }
      } else {
        final Set<String> names = {};
        if (records._projection.isPrivate(token.start) ||
            records._projection.isPrivate(end.start) ||
            values.any(
              (value) =>
                  records._projection.isPrivate(value.start) ||
                  !_artboardPaletteName(value) ||
                  !symbolNames.contains(latin1.decode(aiStringBytes(value))) ||
                  !names.add(latin1.decode(aiStringBytes(value))),
            )) {
          throw UnsupportedError('Retained symbol inventories require distinct ordinary names with qualified definitions.');
        }
      }
    }
    ranges.add((start: token.start, end: end.end));
  }
  return ranges;
}
