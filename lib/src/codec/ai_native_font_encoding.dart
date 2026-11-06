part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// One declarative font mark, separate from array-valued setup operands.
typedef _NativeFontEncoding = ({int start, int end, List<String> names});

/// Recognizes literal TE/TZ operands without executing PostScript mark operators.
({int endIndex, List<String> names})? _readNativeFontEncoding(AiNativeRecords records, int start) {
  final List<AiToken> tokens = records._projection.tokens;
  final List<AiToken> values = [];
  bool weights = false;
  bool closedWeights = false;
  for (int index = start + 1; index < tokens.length && tokens[index].end <= records.program.bodyStart; index++) {
    final AiToken token = tokens[index];
    if (token.kind == .comment) {
      continue;
    }
    if (token.kind == .executableName && const {'TE', 'TZ'}.contains(token.lexeme) && !weights) {
      for (int inspected = start; inspected <= index; inspected++) {
        final AiToken value = tokens[inspected];
        if (records._projection.isPrivate(value.start) || value.kind == .comment && (value.lexeme.startsWith('%AI') || value.lexeme.startsWith('%%'))) {
          throw UnsupportedError('Font encoding marks require ordinary operands without opaque annotations.');
        }
      }
      final List<String> names = token.lexeme == 'TE' ? [] : _nativeFontNames(values);
      _nativeEncodingPairs(values);
      return (endIndex: index, names: names);
    }
    if (token.kind == .arrayStart && !weights && !closedWeights) {
      weights = true;
    } else if (token.kind == .arrayEnd && weights) {
      weights = false;
      closedWeights = true;
    } else if (!const {AiTokenKind.number, AiTokenKind.literalName}.contains(token.kind) || closedWeights) {
      return null;
    }
    values.add(token);
  }
  return null;
}

/// Removes qualified font names, direction/script flags and optional MM weights.
List<String> _nativeFontNames(List<AiToken> values) {
  if (values.isNotEmpty && values.last.kind == .arrayEnd) {
    values.removeLast();
    int count = 0;
    while (values.isNotEmpty && values.last.kind == .number) {
      final num weight = values.removeLast().number!;
      if (!weight.isFinite || weight < 0 || weight > 1) {
        throw const FormatException('Font instance weights must be finite unit values.');
      }
      count++;
    }
    if (count == 0 || values.isEmpty || values.removeLast().kind != .arrayStart) {
      throw const FormatException('Font instance weights require a nonempty numeric array.');
    }
  }
  final List<num> flags = [];
  while (values.isNotEmpty && values.last.kind == .number && flags.length < 4) {
    flags.insert(0, values.removeLast().number!);
  }
  if (flags.length != 2 && flags.length != 3 ||
      flags.any((value) => !value.isFinite || value % 1 != 0) ||
      !const {0, 1}.contains(flags.last) ||
      !const {0, 1, 2, 3, 25}.contains(flags[flags.length - 2]) ||
      flags.length == 3 && !const {0, 1}.contains(flags.first) ||
      values.length < 2) {
    throw const FormatException('Font encoding requires literal names and known direction/script flags.');
  }
  final List<String> names = [];
  for (final AiToken token in values.sublist(values.length - 2)) {
    if (!_nativeFontLiteral(token)) {
      throw const FormatException('Font names must be nonempty literal PostScript names.');
    }
    names.add(token.lexeme.substring(1));
  }
  values.removeRange(values.length - 2, values.length);
  return List.unmodifiable(names);
}

/// Checks bounded glyph runs, including the implicit increment after each name.
void _nativeEncodingPairs(List<AiToken> values) {
  int? code;
  bool needsName = false;
  for (final AiToken token in values) {
    if (token.kind == .number) {
      final num value = token.number!;
      if (needsName || !value.isFinite || value % 1 != 0 || value < 0 || value > 255) {
        throw const FormatException('Font encoding indices must introduce glyphs within 0..255.');
      }
      code = value.toInt();
      needsName = true;
    } else {
      if (code == null || code > 255 || !_nativeFontLiteral(token)) {
        throw const FormatException('Font encoding runs require literal glyph names and bounded indices.');
      }
      code++;
      needsName = false;
    }
  }
  if (needsName) {
    throw const FormatException('A font encoding index has no glyph.');
  }
}

/// Excludes immediate name lookup while retaining literal spelling exactly.
bool _nativeFontLiteral(AiToken token) => token.kind == .literalName && token.lexeme.length > 1 && !token.lexeme.startsWith('//');
