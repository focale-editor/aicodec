part of 'package:aikit/src/model/ai_native_records.dart';

/// Describes declarative state writes, without executing or rendering a group.
///
/// Missing keys represent unknown inherited values, not assumed defaults. A
/// replacement may only leave the same assignments. Complete gradient fills
/// restore their path-rendering procedures at BB and retain external resources.
Map<String, String> _printingState(AiNativeDrawing drawing, AiNativeGroup group, {bool clipping = false}) {
  if (group.opening.operator != 'u' || group.paths.isEmpty) {
    throw UnsupportedError('Printing replacement requires a nonempty ordinary outer group.');
  }
  if (group.paths.any((path) => path.geometry.skip(1).any((item) => item.operator == 'm'))) {
    throw const FormatException('Each native printing path requires exactly one initial moveto.');
  }
  final List<AiNativeInstruction> commands = _printingCommands(drawing, group, clipping: clipping);
  final List<AiNativeGradient> gradients = drawing.gradients.where((gradient) => gradient.start >= group.start && gradient.end <= group.end).toList();
  final Set<AiNativeInstruction> gradientCommands = {};
  for (final AiNativeGradient gradient in gradients) {
    if (gradient.onStroke ||
        gradient.closing.numbers!.single != 0 ||
        gradient.paths.length != 1 ||
        !const {'f', 'F'}.contains(gradient.paths.single.paint.operator) ||
        gradient.paths.single.geometry.last.end > gradient.start ||
        gradient.geometry.flag != 1 ||
        gradient.geometry.length <= 0 ||
        gradient.geometry.relativeToArtwork && gradient.imagingMatrices.isEmpty) {
      throw UnsupportedError('Printing replacement requires a complete ordinary gradient fill.');
    }
    for (final AiNativeInstruction item in commands.where((item) => item.start >= gradient.start && item.end <= gradient.end)) {
      if (!_gradientCommands.contains(item.operator) && !identical(item, gradient.paths.single.paint)) {
        throw UnsupportedError('A gradient fill contains unresolved state changes.');
      }
      gradientCommands.add(item);
    }
  }
  final Set<AiNativeInstruction> pathCommands = {
    for (final AiNativePath path in group.paths) ...[...path.geometry, path.paint],
    if (clipping)
      for (final AiNativePathTopology path in _nativeGroupContours(drawing, group, retainedCommands: gradientCommands)) ...path.maskControls,
  };
  final Map<String, String> state = {};
  final List<Map<String, String>?> clips = [];
  int compoundDepth = 0;
  bool expanded = false;
  for (final AiNativeInstruction item in commands) {
    final String operator = item.operator;
    if (item.operands.any((operand) => operand.number != null && operand.number!.abs() > 9007199254740991)) {
      throw const FormatException('Printing coordinates and state exceed portable numeric limits.');
    }
    if (expanded && !(const {'u', '*u'}.contains(operator) || clipping && operator == 'q')) {
      throw UnsupportedError('A group-expansion flag must immediately precede its owned group.');
    }
    if (const {'u', 'U', '*u', '*U'}.contains(operator) || clipping && const {'q', 'Q'}.contains(operator)) {
      if (item.operands.isNotEmpty) {
        throw const FormatException('Native printing group boundaries cannot have operands.');
      }
      expanded = false;
      if (operator == '*u') {
        compoundDepth++;
      } else if (operator == '*U') {
        compoundDepth--;
      } else if (operator == 'q') {
        clips.add(
          compoundDepth == 0
              ? {
                  for (final String key in _nativeClipStateKeys)
                    if (state[key] case final String value) key: value,
                }
              : null,
        );
      } else if (operator == 'Q') {
        if (clips.removeLast() case final Map<String, String> saved) {
          state
            ..removeWhere((key, _) => _nativeClipStateKeys.contains(key))
            ..addAll(saved);
        }
      }
      continue;
    }
    if (pathCommands.contains(item) || gradientCommands.contains(item) || operator == 'As') {
      continue;
    }
    if (group.paths.any((path) => item.start >= path.start && item.end <= path.end)) {
      throw UnsupportedError('A printing path contains interleaved paint-state changes.');
    }
    final List<double>? numbers = item.numbers;

    /// Requires finite numeric operands before applying an attribute schema.
    bool arity(int count) => numbers != null && numbers.length == count;

    /// Rejects invalid known attributes without accepting executable operands.
    void require(bool valid) {
      if (!valid) {
        throw FormatException('Invalid native printing operands for $operator.');
      }
    }

    String key = operator;
    switch (operator) {
      case 'g' || 'G' || 'k' || 'K' || 'Xa' || 'XA':
        require(
          (operator == 'g' || operator == 'G' ? arity(1) : (operator == 'k' || operator == 'K' ? arity(4) : arity(3) || arity(7))) && numbers!.every(_gradientUnit),
        );
        key = operator == 'g' || operator == 'k' || operator == 'Xa' ? 'fill' : 'stroke';
      case 'O' || 'R' || 'XR' || 'D' || 'Ap' || 'Ae':
        require(arity(1) && const {0, 1}.contains(numbers!.single));
        if (operator == 'Ae') {
          expanded = true;
          continue;
        }
      case 'J' || 'j':
        require(arity(1) && const {0, 1, 2}.contains(numbers!.single));
      case 'w' || 'M':
        require(arity(1) && numbers!.single >= (operator == 'w' ? 0 : 1));
      case 'Xy':
        require(arity(5) && numbers![0] == 0 && _gradientUnit(numbers[1]) && numbers.skip(2).every((value) => value == 0));
      case 'd':
        final List<AiToken> operands = item.operands;
        require(operands.length >= 3 && operands.first.kind == .arrayStart && operands[operands.length - 2].kind == .arrayEnd && operands.last.number != null);
        final List<AiToken> dashes = operands.sublist(1, operands.length - 2);
        require(dashes.every((dash) => dash.number != null && dash.number! >= 0) && (dashes.isEmpty || dashes.any((dash) => dash.number! > 0)));
      default:
        throw UnsupportedError('Printing replacement has no qualified state contract for $operator.');
    }
    state[key] = '$operator ${item.operands.map((operand) => operand.number?.toDouble().toString() ?? operand.lexeme).join(' ')}';
  }
  if (expanded) {
    throw UnsupportedError('A printing expansion flag has no owned group.');
  }
  return state;
}
