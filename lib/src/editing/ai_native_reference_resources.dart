part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies counted gradient declarations without treating resource names as art IDs.
List<({int start, int end})> _referenceGradientRanges(AiNativeLayers model, {List<_NativeFontEncoding>? fontDeclarations}) {
  final AiNativeRecords records = model.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: records);
  final List<({int start, int end})> ranges = [];
  for (final _NativeGradientBank bank in _nativeGradientBanks(resources, fontDeclarations: fontDeclarations)) {
    final AiToken operator = tokens.skip(_pathOffset(tokens, bank.count.end, (token) => token.start)).firstWhere((token) => token.kind != .comment);
    if (operator.kind != .executableName || operator.lexeme != 'Bn' || model.structure.versions.memberships(start: bank.count.start, end: operator.end).isNotEmpty) {
      throw UnsupportedError('Reference qualification requires unconditional counted gradient banks.');
    }
    // Keep intervening metadata outside the qualified numeric/command tokens.
    ranges.addAll([(start: bank.count.start, end: bank.count.end), (start: operator.start, end: operator.end)]);
  }
  int index = 0;
  for (final AiNativeGradientDefinition definition in resources.definitions) {
    AiToken? opening;
    while (index < tokens.length && tokens[index].start < definition.start) {
      final AiToken token = tokens[index++];
      if (token.kind == .comment && token.lexeme.startsWith('%AI5_BeginGradient:')) {
        opening = token;
      }
    }
    while (index < tokens.length && (tokens[index].start < definition.end || tokens[index].kind != .comment || tokens[index].lexeme != '%AI5_EndGradient')) {
      index++;
    }
    if (opening == null || index == tokens.length) {
      throw const FormatException('A qualified gradient requires both source wrappers.');
    }
    final int start = opening.start;
    final AiToken closing = tokens[index++];
    if (definition.opening.isPrivate || definition.closing.isPrivate || model.structure.versions.blocks.any((block) => block.start < closing.end && block.end > start)) {
      throw UnsupportedError('Reference qualification requires unconditional ordinary gradient boundaries.');
    }
    ranges.add((start: start, end: closing.end));
  }
  return ranges;
}

/// Admits private scalar replay while requiring ordinary ownership everywhere else.
void _referenceArtworkInterval(AiNativeLayers model, int start, int end, Map<int, AiNativeLayer> headers, {List<AiNativeAppearanceArtwork> appearanceArtwork = const []}) {
  int position = start;
  for (final AiNativeInstruction item in _pathInterval(model.drawing.items, start, end, (item) => item.start).whereType<AiNativeInstruction>().where((item) => item.isPrivate)) {
    if (model.drawing.meshArtwork.any((owner) => item.start >= owner.start && item.end <= owner.end)) {
      continue;
    }
    if (_nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('Private artwork outside a complete pair has unresolved reference ownership.');
    }
    _layerInterval(model, position, item.start, headers, appearanceArtwork: appearanceArtwork, retainImages: true);
    position = item.end;
  }
  _layerInterval(model, position, end, headers, appearanceArtwork: appearanceArtwork, retainImages: true);
}
