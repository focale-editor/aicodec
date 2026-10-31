part of 'package:aikit/src/model/ai_native_records.dart';

/// Reorders complete owners with retained identities and both boundary states.
List<AiSourceEdit> _reorderedNativeSubtrees(
  AiNativeLayers model,
  List<_NativeSubtreeSpan> sources,
  List<_NativeShapeBundle> pairs, {
  bool groups = false,
}) {
  final AiNativeDrawing drawing = model.drawing;
  final List<_NativeSubtreeSpan> slots = [...sources]..sort((first, second) => first.start.compareTo(second.start));
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, [
    ...sources.expand((span) => [span.start, span.end]),
    ...pairs.map((pair) => pair.shape.end),
  ]);
  final List<AiSourceEdit> edits = [];
  final Map<_NativeSubtreeSpan, _NativeSourceReplacement> replacements = {};
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final (int, _NativeSubtreeSpan) entry in slots.indexed) {
    final _NativeSubtreeSpan slot = entry.$2;
    final _NativeSubtreeSpan source = sources[entry.$1];
    if (slot == source) {
      continue;
    }
    final List<_NativeShapeBundle> selected = pairs.where((pair) => pair.start >= source.start && pair.shape.end <= source.end).toList();
    final List<AiNativeInstruction> ordinary = _subtreeOrdinaryCommands(model, source.start, source.end, selected, groups: groups);
    final List<AiNativeInstruction> commands = [...ordinary, for (final _NativeShapeBundle pair in selected) ...pair.commands]..sort((first, second) => first.start.compareTo(second.start));
    final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
      drawing,
      source,
      commands,
      {for (final _NativeShapeBundle pair in selected) pair.shape.end: pair},
      _subtreeCopyAccess(drawing, ordinary, selected, states),
      states[source.start]!,
      states[source.end]!,
      states[slot.start]!,
      states[slot.end]!,
      maxBytes: remaining,
    );
    edits.add(AiSourceEdit(start: slot.start, end: slot.end, bytes: placed.bytes));
    replacements[slot] = placed.replacement;
    remaining -= placed.bytes.length;
  }
  _sourceFollowingDependencies(drawing, replacements);
  return edits;
}
