part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualified plug-in/name identities and complete retained declaration spans.
typedef _ArtboardBrushScope = ({Set<(String, String)> names, Set<String> artwork, List<({int start, int end})> ranges});

/// Retains known brush descriptors and resolves their independent artwork owners.
_ArtboardBrushScope _artboardBrushScope(AiNativeLayers layers, Set<String> artwork) {
  final AiNativeRecords records = layers.drawing.records;
  final List<AiToken> tokens = records._projection.tokens;
  final Set<(String, String)> names = {};
  final Set<String> references = {};
  final List<({int start, int end})> ranges = [];
  List<(String, String)>? inventory;
  bool setup = false;
  for (int index = 0; index < tokens.length && tokens[index].start < records.program.bodyStart; index++) {
    final AiToken opening = tokens[index];
    if (opening.kind == .comment && opening.lexeme == '%%BeginSetup') {
      setup = true;
    }
    if (!setup || opening.kind != .comment || opening.lexeme != '%AI8_BeginPluginObject') {
      continue;
    }
    final List<AiToken> values = [];
    while (++index < tokens.length && tokens[index].start < records.program.bodyStart && tokens[index].lexeme != '%AI8_EndPluginObject') {
      final AiToken token = tokens[index];
      if (token.kind == .comment && !token.lexeme.startsWith('%AI') && !token.lexeme.startsWith('%%')) {
        continue;
      }
      values.add(token);
    }
    if (index >= tokens.length || tokens[index].start >= records.program.bodyStart) {
      throw const FormatException('Unterminated retained brush descriptor.');
    }
    final AiToken closing = tokens[index];
    if (records._projection.isPrivate(opening.start) ||
        records._projection.isPrivate(closing.start) ||
        values.any((token) => records._projection.isPrivate(token.start)) ||
        layers.structure.versions.blocks.any((block) => block.start < closing.end && block.end > opening.start)) {
      throw UnsupportedError('Retained brush descriptors require ordinary unconditional ownership.');
    }
    if (values.length < 4 || values.length.isOdd || !_artboardPaletteName(values[0]) || !_artboardPaletteName(values[1])) {
      throw UnsupportedError('Retained brush descriptors require literal plug-in and resource names.');
    }
    final String plugin = latin1.decode(aiStringBytes(values[0]));
    final String name = latin1.decode(aiStringBytes(values[1]));
    final StringBuffer payload = StringBuffer();
    for (int part = 2; part < values.length; part += 2) {
      if (!const {AiTokenKind.string, AiTokenKind.hexString}.contains(values[part].kind) ||
          values[part + 1].kind != .executableName ||
          values[part + 1].lexeme != (part + 2 == values.length ? '.' : '-')) {
        throw UnsupportedError('Retained brush payloads require literal continuation fragments.');
      }
      payload.write(latin1.decode(aiStringBytes(values[part])));
    }
    final String data = payload.toString();
    if (plugin == 'Adobe Brush Manager Order') {
      if (name != plugin || inventory != null) {
        throw UnsupportedError('Retained brush panels require a unique matching manager identity.');
      }
      if (RegExp('/').allMatches(data).take(records.program.limits.maxTokens + 1).length > records.program.limits.maxTokens) {
        throw const AiLimitException(message: 'Retained brush inventory exceeds the token limit.');
      }
      final List<String> parts = data.split('/').map((part) => part.trim()).toList();
      if (parts.length.isEven || parts.last.isNotEmpty) {
        throw UnsupportedError('Retained brush panels require complete plug-in/name pairs.');
      }
      inventory = [for (int part = 0; part < parts.length - 1; part += 2) (parts[part], parts[part + 1])];
    } else {
      if (!names.add((plugin, name))) {
        throw UnsupportedError('Retained brush descriptors require unique plug-in/name pairs.');
      }
      references.addAll(_artboardBrushPayload(plugin, data, artwork));
    }
    ranges.add((start: opening.start, end: closing.end));
  }
  if (inventory != null && (inventory.toSet().length != inventory.length || inventory.any((name) => !names.contains(name)))) {
    throw UnsupportedError('Retained brush panel entries require distinct qualified definitions.');
  }
  return (names: Set.unmodifiable(names), artwork: Set.unmodifiable(references), ranges: List.unmodifiable(ranges));
}

/// Checks observed descriptor layouts without executing a brush or generating art.
Set<String> _artboardBrushPayload(String plugin, String data, Set<String> artwork) {
  switch (plugin) {
    case 'Adobe Calligraphic Brush Tool':
      final List<double> values = _artboardBrushNumbers(data, count: 11);
      if (values.first != 1) {
        throw UnsupportedError('Retained calligraphic brushes require the version-one scalar layout.');
      }
    case 'Adobe ArtOnPath Brush Tool' || 'Adobe PatternOnPath Brush Tool':
      if (RegExp('/').allMatches(data).take(9).length != 8) {
        throw UnsupportedError('Retained art/pattern brushes require complete bounded field groups.');
      }
      final List<String> parts = data.split('/').map((part) => part.trim()).toList();
      if (parts.length != 9 || parts.first != '2' || parts[1].isEmpty || parts.skip(1).take(5).any((name) => name.isNotEmpty && !artwork.contains(name))) {
        throw UnsupportedError('Retained art/pattern brushes require version-two descriptors with qualified artwork tiles.');
      }
      _artboardBrushNumbers(parts[6], count: 2);
      final List<double> color = _artboardBrushNumbers(parts[7]);
      if (!(color.length == 2 && color.first == 0 || color.length == 4 && color.first == 5)) {
        throw UnsupportedError('Retained brush colors require the observed gray or RGB scalar layout.');
      }
      _artboardBrushNumbers(parts[8], count: 15);
      return parts.skip(1).take(5).where((name) => name.isNotEmpty).toSet();
    case 'Adobe dBrush Brush Tool':
      final List<String> parts = RegExp(r'\S+').allMatches(data).take(11).map((part) => part[0]!).toList();
      if (parts.length != 10 || parts[8] != 'AI_BristleBrushLibary_CS5' || !RegExp(r'^\d{2}_(Flat|Round)_[A-Za-z]+$').hasMatch(parts[9])) {
        throw UnsupportedError('Retained bristle brushes require a qualified built-in library identity.');
      }
      if (_artboardBrushNumbers(parts.take(8).join(' '), count: 8).first != 0) {
        throw UnsupportedError('Retained bristle brushes require the version-zero scalar layout.');
      }
    default:
      throw UnsupportedError('Artboard dependency qualification does not cover the $plugin brush descriptor.');
  }
  return {};
}

/// Reads bounded literal numeric fields, excluding executable or reference syntax.
List<double> _artboardBrushNumbers(String data, {int? count}) {
  final List<double?> values = RegExp(r'\S+').allMatches(data).take((count ?? 4) + 1).map((part) => double.tryParse(part[0]!)).toList();
  if (count != null && values.length != count || values.any((value) => value == null || !value.isFinite || value.abs() > 9007199254740991)) {
    throw const FormatException('Retained brush scalar fields require finite portable numbers and their declared layout.');
  }
  return values.cast<double>();
}

/// Resolves a style's brush reference within its plug-in/name namespace.
void _artboardBrushReference(AiNativeEntry entry, String plugin, Set<(String, String)> names) {
  final AiNativeContainer reference = _referenceRecord(entry, 'GObjRef');
  _artboardStyleFields(reference, {'PluginObject'});
  final List<AiNativeItem>? values = reference['PluginObject']?.items;
  if (reference.entries.length != 1 || values == null || values.length != 2 || values.any((item) => item is! AiNativeToken || !_artboardPaletteName(item.token))) {
    throw UnsupportedError('Retained brush references require one literal resource/plug-in pair.');
  }
  final String name = latin1.decode(aiStringBytes((values.first as AiNativeToken).token));
  final String owner = latin1.decode(aiStringBytes((values.last as AiNativeToken).token));
  if (owner != plugin || !names.contains((owner, name))) {
    throw UnsupportedError('Retained brush references must resolve to the matching qualified descriptor.');
  }
}
