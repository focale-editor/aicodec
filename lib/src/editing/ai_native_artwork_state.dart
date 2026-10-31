part of 'package:aikit/src/model/ai_native_records.dart';

/// Declarative attributes whose values can be replayed without rendering.
const Set<String> _nativeArtworkStateKeys = {'fill', 'stroke', 'A', 'Xw', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'w', 'M', 'd'};

/// Validates a source assignment and identifies its overwritten state component.
String? _nativeArtworkStateKey(AiNativeInstruction item) {
  final String operator = item.operator;
  final List<double>? numbers = item.numbers;

  /// Checks exact numeric arity, retaining no assumed default state.
  bool arity(int length) => numbers != null && numbers.length == length;

  /// Distinguishes malformed known operands from unqualified state operators.
  void require(bool valid) {
    if (!valid || item.operands.any((operand) => operand.number != null && operand.number!.abs() > 9007199254740991)) {
      throw FormatException('Invalid native artwork state operands for $operator.');
    }
  }

  switch (operator) {
    case 'g' || 'G' || 'k' || 'K' || 'Xa' || 'XA':
      require(
        (operator == 'g' || operator == 'G'
                ? arity(1)
                : operator == 'k' || operator == 'K'
                ? arity(4)
                : arity(3) || arity(7)) &&
            numbers!.every(_gradientUnit),
      );
      return const {'g', 'k', 'Xa'}.contains(operator) ? 'fill' : 'stroke';
    case 'A' || 'Xw' || 'O' || 'R' || 'XR' || 'D' || 'Ap':
      require(arity(1) && const {0, 1}.contains(numbers!.single));
    case 'J' || 'j':
      require(arity(1) && const {0, 1, 2}.contains(numbers!.single));
    case 'w' || 'M':
      require(arity(1) && numbers!.single >= (operator == 'w' ? 0 : 1));
    case 'd':
      final List<AiToken> operands = item.operands;
      require(operands.length >= 3 && operands.first.kind == .arrayStart && operands[operands.length - 2].kind == .arrayEnd && operands.last.number != null);
      final List<AiToken> dashes = operands.sublist(1, operands.length - 2);
      require(dashes.every((dash) => dash.number != null && dash.number! >= 0) && (dashes.isEmpty || dashes.any((dash) => dash.number! > 0)));
    default:
      return null;
  }
  return operator;
}

/// Compares declarative values without equating unrelated color representations.
bool _sameNativeArtworkState(AiNativeInstruction? first, AiNativeInstruction? second) =>
    identical(first, second) ||
    first != null &&
        second != null &&
        first.operator == second.operator &&
        first.operands.length == second.operands.length &&
        first.operands.indexed.every((entry) => entry.$2.number != null ? entry.$2.number == second.operands[entry.$1].number : entry.$2.lexeme == second.operands[entry.$1].lexeme);

/// Qualifies intervening ordinary artwork and declarative state assignments.
void _ordinaryArtworkInterval(AiNativeDrawing drawing, int start, int end, {required bool groups}) {
  final List<AiNativePath> paths = _pathInterval(drawing.paths, start, end, (path) => path.start).toList();
  final Map<AiNativePath, AiNativeInstruction?> counts = paths.isEmpty ? {} : _ordinaryPathCounts(drawing, paths);
  final Set<AiNativeInstruction> geometry = {
    for (final AiNativePath path in paths) ...[...path.geometry, path.paint],
    ...counts.values.whereType<AiNativeInstruction>(),
  };
  for (final AiNativeInstruction item in _groupInterval(drawing, start, end, nested: groups)) {
    if ((_nativeGeometry.contains(item.operator) || _nativePaint.contains(item.operator) || item.operator == 'As') && !geometry.contains(item)) {
      throw UnsupportedError('Moving paths requires owned geometry and point counts throughout the interval.');
    }
  }
}

/// Known persistent assignments and the last boundary invalidating unknown values.
final class _NativeArtworkState {
  /// Last explicit source assignment for each qualified state component.
  final Map<String, AiNativeInstruction> values;

  /// Opaque boundary identity; absent values across different barriers differ.
  final int barrier;

  /// Freezes a source state without guessing defaults after unknown instructions.
  _NativeArtworkState({required Map<String, AiNativeInstruction> values, required this.barrier}) : values = Map.unmodifiable(values);

  /// Requires matching known values or the same unchanged unknown provenance.
  bool matches(_NativeArtworkState other, String key) => values[key] == null && other.values[key] == null ? barrier == other.barrier : _sameNativeArtworkState(values[key], other.values[key]);
}

/// Captures state while retaining the provenance of unknown inherited values.
Map<int, _NativeArtworkState> _nativeArtworkStates(AiNativeDrawing drawing, Iterable<int> boundaries, {Set<int> structural = const {}}) {
  final List<int> positions = boundaries.toSet().toList()..sort();
  final Map<int, _NativeArtworkState> result = {};
  final Map<String, AiNativeInstruction> state = {};
  int index = 0;
  int barrier = -1;
  for (final int position in positions) {
    while (index < drawing.items.length && drawing.items[index].end <= position) {
      final AiNativeItem item = drawing.items[index++];
      if (structural.contains(item.start)) {
        continue;
      }
      if (item is AiNativeInstruction && !item.isPrivate) {
        try {
          final String? key = _nativeArtworkStateKey(item);
          if (key != null) {
            state[key] = item;
            continue;
          }
          if (_nativeGeometry.contains(item.operator) || _nativePaint.contains(item.operator) || const {'u', 'U', 'As'}.contains(item.operator)) {
            continue;
          }
        } on FormatException {
          // Malformed unrelated state grants no inherited value to a later edit.
        }
      }
      state.clear();
      barrier = item.start;
    }
    result[position] = _NativeArtworkState(values: state, barrier: barrier);
  }
  return result;
}

/// Lists qualified ancestors without conflating layer flags and group state.
List<AiNativeStructureNode> _artworkParents(AiNativeStructure ownership, AiNativeStructureNode? parent) {
  final List<AiNativeStructureNode> result = [];
  AiNativeStructureNode? current = parent;
  while (current != null) {
    result.add(current);
    current = ownership.parentOf(current);
  }
  return result;
}

/// Qualifies a move and captures its source, destination and ancestor states.
Map<int, _NativeArtworkState> _artworkMovementStates(
  AiNativeDrawing drawing,
  AiNativeStructure ownership,
  AiNativeItem source, {
  required int position,
  required AiNativeStructureNode? parent,
  required bool inheritParentFlags,
}) {
  final List<AiNativeStructureNode> sourceParents = _artworkParents(ownership, ownership.parentOf(ownership.nodeFor(source)));
  final List<AiNativeStructureNode> targetParents = _artworkParents(ownership, parent);
  final AiNativeStructureNode? sourceLayer = sourceParents.where((parent) => parent.kind == .layer).firstOrNull;
  final AiNativeStructureNode? targetLayer = targetParents.where((parent) => parent.kind == .layer).firstOrNull;
  final bool crossLayer = !identical(sourceLayer, targetLayer);
  if (crossLayer && !inheritParentFlags) {
    throw UnsupportedError('Moving artwork across layers requires explicit inheritParentFlags.');
  }
  final List<AiNativeStructureNode> sourceGroups = sourceParents.takeWhile((parent) => parent.kind == .group).toList();
  final List<AiNativeStructureNode> targetGroups = targetParents.takeWhile((parent) => parent.kind == .group).toList();
  final List<int> positions = [source.start, position, ...sourceGroups.map((group) => group.start), ...targetGroups.map((group) => group.start)];
  final int start = min(source.start, position);
  final int end = max(source.end, position);
  final Map<int, _NativeArtworkState> states;
  if (crossLayer) {
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
    final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
    for (final AiNativeStructureNode node in [?sourceLayer, ?targetLayer]) {
      _qualifiedLayerHeader(layers, layers.layerFor(node.source as AiLayer));
    }
    _layerInterval(layers, start, end, headers);
    states = _layerStates(layers, positions, headers);
  } else {
    _ordinaryArtworkInterval(drawing, start, end, groups: true);
    states = _nativeArtworkStates(drawing, positions);
  }
  if (!inheritParentFlags &&
      (sourceGroups.length != targetGroups.length ||
          sourceGroups.indexed.any((entry) => const {'A', 'Xw'}.any((key) => !states[entry.$2.start]!.matches(states[targetGroups[entry.$1].start]!, key))))) {
    throw UnsupportedError('Changing ancestor-group flags or depth requires explicit inheritParentFlags.');
  }
  return states;
}

/// Serializes only owned source spans under an aggregate output budget.
List<int> _nativeSourceSpans(AiProgram program, Iterable<({int start, int end})> spans, int maxBytes, {List<AiSourceEdit> edits = const []}) {
  final BytesBuilder result = BytesBuilder(copy: false);
  for (final ({int start, int end}) span in spans) {
    final List<AiSourceEdit> replacements = edits.where((edit) => edit.start >= span.start && edit.end <= span.end).toList();
    final int length = span.end - span.start + replacements.fold(0, (count, edit) => count + edit.bytes.length - (edit.end - edit.start));
    if (result.length + length + 1 > maxBytes) {
      throw const AiLimitException(message: 'Native artwork output exceeds the native byte limit.');
    }
    result.add(replacements.isEmpty ? Uint8List.sublistView(program.bytes, span.start, span.end) : AiNativeEditor.copyRange(program: program, start: span.start, end: span.end, edits: replacements));
    result.addByte(10);
  }
  return result.takeBytes();
}

/// Replays source values around owned artwork, retaining both boundary states.
List<int> _placedNativeArtwork(
  AiProgram program,
  Iterable<({int start, int end})> spans,
  List<AiNativeInstruction> commands,
  _NativeArtworkState source,
  _NativeArtworkState incoming,
  _NativeArtworkState outgoing, {
  required int maxBytes,
  List<AiSourceEdit> sourceEdits = const [],
}) {
  final Set<String> required = {};
  final Map<String, AiNativeInstruction> writes = {};
  for (final AiNativeInstruction command in commands) {
    final String? key = _nativeArtworkStateKey(command);
    if (key != null) {
      writes[key] = command;
    } else if (command.operator == 'u' || command.operator == 'm') {
      required.addAll((command.operator == 'u' ? const {'A', 'Xw'} : _nativeArtworkStateKeys).where((key) => !writes.containsKey(key)));
    }
  }
  final Map<String, AiNativeInstruction> actual = Map.of(incoming.values);
  final List<AiNativeInstruction> prefix = [];
  for (final String key in required) {
    if (!source.matches(incoming, key)) {
      final AiNativeInstruction? value = source.values[key];
      if (value == null) {
        throw UnsupportedError('The placed artwork requires an unknown inherited $key value.');
      }
      prefix.add(value);
      actual[key] = value;
    }
  }
  actual.addAll(writes);
  final List<AiNativeInstruction> suffix = [];
  final _NativeArtworkState resulting = _NativeArtworkState(values: actual, barrier: incoming.barrier);
  for (final String key in _nativeArtworkStateKeys) {
    if (!resulting.matches(outgoing, key)) {
      final AiNativeInstruction? value = outgoing.values[key];
      if (value == null) {
        throw UnsupportedError('The placed artwork cannot restore an unknown outgoing $key value.');
      }
      suffix.add(value);
    }
  }
  return _nativeSourceSpans(
    program,
    [
      for (final AiNativeInstruction item in prefix) (start: item.start, end: item.end),
      ...spans,
      for (final AiNativeInstruction item in suffix) (start: item.start, end: item.end),
    ],
    maxBytes,
    edits: sourceEdits,
  );
}

/// Requires an owned, qualified destination without changing its header or panel.
AiNativeLayers _artworkLayerDestination(AiNativeDrawing drawing, AiLayer layer) {
  final AiNativeLayers model = AiNativeLayers.decode(drawing: drawing);
  _qualifiedLayerHeader(model, model.layerFor(layer));
  return model;
}
