part of 'package:aikit/src/model/ai_native_records.dart';

/// Checks unchanged tile geometry and local paint without instantiating a motif.
void _artboardPatternArtwork(AiNativeLayers layers, AiNativeDrawing drawing, Map<int, AiNativeResourceUse> references) {
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  final Map<int, AiNativeGroup> groups = {for (final AiNativeGroup group in drawing.groups) group.start: group};
  final Set<AiNativeInstruction> endings = {for (final AiNativeGroup group in drawing.groups) group.closing};
  final Set<AiNativeInstruction> gradients = {};
  for (final AiNativeGradient gradient in drawing.gradients) {
    if (references[gradient.geometry.instruction.start]?.resolution != .resolved) {
      throw UnsupportedError('Retained pattern gradients require one unconditional setup definition.');
    }
    gradients.addAll([gradient.opening, gradient.geometry.instruction, ?gradient.highlight, ...gradient.imagingMatrices, gradient.closing]);
  }
  final Set<AiNativeInstruction> geometry = {
    for (final AiNativePath path in drawing.paths) ...[...path.geometry, path.paint],
  };
  for (final AiNativeGradient gradient in drawing.gradients) {
    if (_pathInterval(drawing.items, gradient.start, gradient.end, (item) => item.start).any((item) => !gradients.contains(item) && !geometry.contains(item))) {
      throw UnsupportedError('Retained pattern gradients cannot cross group, state or metadata boundaries.');
    }
  }
  AiNativeInstruction? count;
  int clipDepth = 0;
  for (int index = 0; index < drawing.items.length; index++) {
    final AiNativeItem item = drawing.items[index];
    if (paths[item.start] case final AiNativePath path) {
      final int first = index;
      while (index + 1 < drawing.items.length && drawing.items[index + 1].start < path.end) {
        index++;
      }
      final List<AiNativeItem> commands = drawing.items.sublist(first, index + 1).where((item) => !gradients.contains(item)).toList();
      _artboardRetainedPath(layers, path, commands, count, clipping: clipDepth > 0);
      if (count != null && count.isPrivate != path.isPrivate) {
        throw UnsupportedError('Pattern point counts must belong to the same representation as their paths.');
      }
      count = null;
      continue;
    }
    if (gradients.contains(item)) {
      continue;
    }
    if (item is AiNativeContainer) {
      if (count != null) {
        throw const FormatException('A pattern point count crosses artwork metadata.');
      }
      continue;
    }
    final AiNativeInstruction command = item as AiNativeInstruction;
    if (command.operands.any((operand) => operand.number != null && (!operand.number!.isFinite || operand.number!.abs() > 9007199254740991))) {
      throw const FormatException('Retained pattern operands must be finite portable numbers.');
    }
    if (groups.containsKey(command.start) || endings.contains(command)) {
      if (count != null || command.operands.isNotEmpty) {
        throw const FormatException('Pattern groups cannot consume operands or pending point counts.');
      }
      if (command.operator == 'q') {
        clipDepth++;
      } else if (command.operator == 'Q') {
        clipDepth--;
      }
    } else if (command.operator == 'As') {
      if (count != null || command.numbers?.length != 1 || command.numbers!.single < 0 || command.numbers!.single % 1 != 0) {
        throw const FormatException('Invalid retained pattern point count.');
      }
      count = command;
    } else if (command.operator == 'XW') {
      if (command.operands.length != 2 ||
          !const {6, 9}.contains(command.operands.first.number) ||
          !const {AiTokenKind.string, AiTokenKind.hexString}.contains(command.operands.last.kind) ||
          aiStringBytes(command.operands.last).isNotEmpty) {
        throw UnsupportedError('Retained pattern artwork requires literal empty style resets.');
      }
    } else if (command.operator == 'Ae') {
      if (command.numbers?.length != 1 || command.numbers!.single != 0) {
        throw UnsupportedError('Retained pattern artwork has an unknown editing flag.');
      }
    } else if (command.operator == 'Xd') {
      if (command.numbers?.length != 2 || command.numbers!.any((value) => value != 0 && value != 1)) {
        throw const FormatException('Pattern fill/stroke flags must be Boolean.');
      }
    } else if (command.operator == 'Xy') {
      if (command.numbers?.length != 5 || !const {0, 1}.contains(command.numbers!.first) || !_gradientUnit(command.numbers![1]) || command.numbers!.skip(2).any((value) => value != 0)) {
        throw UnsupportedError('Retained patterns require qualified local opacity state.');
      }
    } else if (_nativeArtworkStateKey(command) == null) {
      throw UnsupportedError('Artboard pattern isolation does not cover ${command.operator}.');
    }
  }
  if (count != null) {
    throw const FormatException('A retained pattern point count has no path.');
  }
}
