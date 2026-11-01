part of 'package:aikit/src/model/ai_native_records.dart';

/// Proves uniform explicit scalar assignments unchanged by pure permutations.
Set<String> _nativeAppearanceOrderState(AiNativeAppearance appearance, List<AiNativeAppearancePartChange> changes, Set<String> reads) {
  if (changes.any((change) => change.childOrder == null || change.visible != null || change.evenOdd != null || change.strokeAlignment != null || change.adjustDashes != null)) {
    return {};
  }
  return _nativeAppearanceScalarState(appearance, reads).keys.toSet();
}

/// Returns uniform explicit noncolor outputs of an entirely visible appearance.
Map<String, AiNativeInstruction> _nativeAppearanceScalarState(AiNativeAppearance appearance, Set<String> reads) {
  if (appearance.parts.any((part) => part.visible != true)) {
    return {};
  }
  final Map<String, List<AiNativeInstruction>> assignments = {};
  for (final AiNativeAppearancePart part in appearance.parts) {
    for (final AiNativeAppearancePaint paint in part.paints) {
      for (final AiNativeInstruction command in paint.style.instructions) {
        final String? key = _nativeArtworkStateKey(command);
        if (key != null && key != 'fill' && key != 'stroke' && !reads.contains(key)) {
          (assignments[key] ??= []).add(command);
        }
      }
    }
  }
  return {
    for (final MapEntry<String, List<AiNativeInstruction>> entry in assignments.entries)
      if (entry.value.every((command) => _sameNativeArtworkState(command, entry.value.first)) &&
          (entry.key != 'XR' || appearance.parts.where((part) => part.kind == .fill).every((part) => part.evenOdd == (entry.value.first.numbers!.single == 1))))
        entry.key: entry.value.first,
  };
}

/// Applies nested child permutations from the inside out with descendant edits.
List<AiSourceEdit> _nativeAppearanceOrderEdits(
  AiNativeAppearances model,
  AiNativeAppearance appearance,
  List<AiNativeAppearancePartChange> parts,
  List<AiSourceEdit> edits,
) {
  final AiNativeRecords records = model.structure.drawing.records;
  final List<AiNativeAppearancePartChange> orders = parts.where((change) => change.childOrder != null).toList()..sort((first, second) => second.part.record.start.compareTo(first.part.record.start));
  for (final AiNativeAppearancePartChange change in orders) {
    final AiNativeAppearancePart parent = change.part;
    if (!const {AiNativeAppearancePartKind.stack, AiNativeAppearancePartKind.chain}.contains(parent.kind)) {
      throw UnsupportedError('Appearance child ordering requires a qualified stack or chain.');
    }
    final List<AiNativeAppearancePart> children = parent.childIndices.map((index) => appearance.parts[index]).toList();
    final List<AiNativeAppearancePart> order = change.childOrder!;
    if (order.length != children.length || order.toSet().length != order.length || order.any((child) => !children.contains(child))) {
      throw ArgumentError('Appearance child order requires every current direct child exactly once.');
    }
    final List<AiSourceEdit> replacements = [];
    final Set<AiSourceEdit> consumed = {};
    for (final (int, AiNativeAppearancePart) entry in children.indexed) {
      final AiNativeContainer slot = entry.$2.record;
      final AiNativeContainer child = order[entry.$1].record;
      if (records._projection.isPrivate(slot.start) != records._projection.isPrivate(child.start) || records._projection.isPrivate(slot.end - 1) != records._projection.isPrivate(child.end - 1)) {
        throw UnsupportedError('Appearance child order must retain ordinary and private source boundaries.');
      }
      final List<AiSourceEdit> nested = edits.where((edit) => edit.start >= child.start && edit.end <= child.end).toList();
      replacements.add(
        AiSourceEdit(
          start: slot.start,
          end: slot.end,
          bytes: AiNativeEditor.copyRange(program: records.program, start: child.start, end: child.end, edits: nested),
        ),
      );
      consumed.addAll(nested);
    }
    edits.removeWhere(consumed.contains);
    edits.addAll(replacements);
  }
  return edits;
}
