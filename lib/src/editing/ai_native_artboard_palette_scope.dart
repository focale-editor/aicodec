part of 'package:aicodec/src/model/ai_native_records.dart';

/// Keeps palette cells and their local paint references separate from artboards.
void _artboardPalette(List<AiToken> tokens, AiNativeLimits limits, Map<int, AiNativeResourceUse> gradientUses, Set<String> patternNames, {Set<int> versionMarkers = const {}}) {
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: limits.maxDepth);
  final List<AiNativeInstruction> gradient = [];
  bool opened = false;
  bool closed = false;
  bool paint = false;
  for (final AiToken token in tokens) {
    if (versionMarkers.contains(token.start)) {
      // Every branch starts and ends between complete cells. Both alternatives
      // can then be checked once without merging operands or choosing a version.
      if (!opened || closed || paint || gradient.isNotEmpty || !reader.isEmpty) {
        throw UnsupportedError('Palette version boundaries require complete cells inside the original palette.');
      }
      continue;
    }
    final AiNativeInstruction? command = reader.add(token, isPrivate: false);
    if (command == null) {
      continue;
    }
    final List<AiToken> operands = command.operands;
    if (operands.any((operand) => operand.number != null && (!operand.number!.isFinite || operand.number!.abs() > 9007199254740991))) {
      throw const FormatException('Native palette operands require finite portable numbers.');
    }
    if (!opened) {
      if (command.operator != 'Pb' || command.numbers?.length != 2 || command.numbers!.any((value) => value < 0 || value % 1 != 0)) {
        throw const FormatException('Native palette indices must be nonnegative integers.');
      }
      opened = true;
    } else if (closed) {
      throw const FormatException('Unexpected data after a native palette.');
    } else if (gradient.isNotEmpty) {
      if (!_gradientCommands.contains(command.operator)) {
        throw UnsupportedError('Palette gradients cannot contain unrelated paint or executable commands.');
      }
      gradient.add(command);
      if (command.operator == 'BB') {
        _artboardPaletteGradient(gradient, gradientUses);
        gradient.clear();
        paint = true;
      }
    } else if (command.operator == 'PB') {
      if (operands.isNotEmpty || paint) {
        throw const FormatException('Native palette has an unfinished color cell.');
      }
      closed = true;
    } else if (command.operator == 'Pc') {
      if (!paint || operands.length > 1 || operands.isNotEmpty && !_artboardPaletteName(operands.single)) {
        throw const FormatException('Native palette cells require a paint and an optional literal name.');
      }
      paint = false;
    } else if (command.operator == 'Pg') {
      if (paint || operands.length != 3 || !const {0, 1}.contains(operands.first.number) || !_artboardPaletteName(operands[1]) || !const {0, 1}.contains(operands.last.number)) {
        throw const FormatException('Native palette groups require a literal name and two Boolean flags between cells.');
      }
    } else {
      if (paint) {
        throw const FormatException('Native palette has multiple paints for one cell.');
      }
      if (command.operator == 'Bb') {
        gradient.add(command);
        continue;
      }
      if (command.operator == 'p' || command.operator == 'P') {
        _artboardPatternUse(command, patternNames);
      } else {
        _artboardPaletteColor(command);
      }
      paint = true;
    }
  }
  reader.finish();
  if (!opened || !closed || gradient.isNotEmpty) {
    throw const FormatException('Native palette requires complete boundaries and cells.');
  }
}

/// Qualifies a local gradient instance with a uniquely resolved setup resource.
void _artboardPaletteGradient(List<AiNativeInstruction> commands, Map<int, AiNativeResourceUse> uses) {
  final AiNativeGradient gradient = _readNativeGradients(instructions: commands, paths: []).single;
  final AiNativeResourceUse? use = uses[gradient.geometry.instruction.start];
  if (gradient.onStroke || gradient.geometry.flag != 2 || gradient.closing.numbers!.single != 0 || use?.resolution != .resolved) {
    throw UnsupportedError('Palette gradients require a fill instance and one unconditional resource.');
  }
}

/// Preserves process colors, named ink alternatives and the explicit none paint.
void _artboardPaletteColor(AiNativeInstruction command) {
  final List<AiToken> operands = command.operands;
  if (command.operator == 'Pn') {
    if (operands.isNotEmpty) {
      throw const FormatException('A none palette cell has no paint operands.');
    }
  } else if (const {'Xz', 'XZ', 'Xs', 'XS'}.contains(command.operator)) {
    final bool rgb = command.operator == 'Xz' || command.operator == 'XZ';
    final int components = rgb ? 7 : 4;
    if (operands.length != (rgb ? 10 : 6) ||
        operands.take(components).any((operand) => operand.number == null || !_gradientUnit(operand.number!.toDouble())) ||
        !_artboardPaletteName(operands[components]) ||
        operands[components + 1].number == null ||
        !_gradientUnit(operands[components + 1].number!.toDouble()) ||
        rgb && operands[9].number != 1) {
      throw const FormatException('Named palette colors require unit components, a literal name and a tint.');
    }
  } else if (!const {'fill', 'stroke'}.contains(_nativeArtworkStateKey(command))) {
    throw UnsupportedError('Artboard palette isolation does not cover ${command.operator}.');
  }
}

/// Retains byte names without interpreting localization or another namespace.
bool _artboardPaletteName(AiToken token) => const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind) && aiStringBytes(token).isNotEmpty;

/// Preserves pattern transforms while resolving their distinct resource names.
void _artboardPatternUse(AiNativeInstruction command, Set<String> names) {
  final List<AiToken> operands = command.operands;
  if (operands.length != 18 ||
      !_artboardPaletteName(operands.first) ||
      operands[10].kind != .arrayStart ||
      operands.last.kind != .arrayEnd ||
      [...operands.sublist(1, 10), ...operands.sublist(11, 17)].any((value) => value.number == null || !value.number!.isFinite || value.number!.abs() > 9007199254740991) ||
      !const {0, 1}.contains(operands[6].number)) {
    throw const FormatException('Retained pattern paints require literal names, transforms and a six-value matrix.');
  }
  if (!names.contains(latin1.decode(aiStringBytes(operands.first)))) {
    throw UnsupportedError('Retained pattern paints require one qualified setup definition.');
  }
}
