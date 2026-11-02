part of 'package:aikit/src/model/ai_native_records.dart';

/// Relocates one complete subtree while retaining state at both edited boundaries.
List<AiSourceEdit> _relocatedNativeSubtree(
  AiNativeLayers model,
  AiNativeStructureNode owner,
  _NativeSubtreeSpan span,
  List<_NativeShapeBundle> pairs,
  int position,
  AiNativeStructureNode? parent,
  bool inheritParentFlags, {
  bool groups = false,
  List<AiNativeAppearanceArtwork> appearanceArtwork = const [],
}) {
  if (position > span.start && position < span.end) {
    throw ArgumentError('A native subtree cannot move inside its own source span.');
  }
  final AiNativeDrawing drawing = model.drawing;
  final Map<int, _NativeShapeInputs> states = _sourceMovementStates(
    drawing,
    owner,
    span,
    position,
    parent,
    inheritParentFlags,
    boundaries: pairs.map((pair) => pair.shape.end),
    appearanceArtwork: appearanceArtwork,
  );
  final List<AiNativeInstruction> ordinary = _subtreeOrdinaryCommands(model, span.start, span.end, pairs, groups: groups, appearanceArtwork: appearanceArtwork);
  final List<AiNativeAppearanceArtwork> appearances = _subtreeAppearances(appearanceArtwork, span.start, span.end);
  final _NativeShapeAccess access = _subtreeCopyAccess(drawing, ordinary, pairs, states, appearanceArtwork: appearances);
  final ({List<int> bytes, _NativeSourceReplacement replacement}) retained = appearances.isEmpty
      ? _retainedSubtreeState(ordinary, pairs, states, drawing.records.program.limits.maxDecodedBytes)
      : _removedAppearanceState(access, states[span.start]!, states[span.end]!, drawing.records.program.limits.maxDecodedBytes);
  final List<AiNativeInstruction> commands = _subtreeCommands(ordinary, pairs, appearances);
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    drawing,
    span,
    commands,
    {for (final _NativeShapeBundle pair in pairs) pair.shape.end: pair},
    access,
    states[span.start]!,
    states[span.end]!,
    states[position]!,
    states[position]!,
    maxBytes: drawing.records.program.limits.maxDecodedBytes - retained.bytes.length,
    appearanceStyleReads: {for (final AiNativeAppearanceArtwork owner in appearances) ...owner._styleReads},
  );
  _sourceFollowingDependencies(drawing, {span: retained.replacement}, insertions: {position: placed.replacement}, retainedArtwork: appearanceArtwork, clipping: appearanceArtwork.isNotEmpty);
  return [AiSourceEdit(start: span.start, end: span.end, bytes: retained.bytes), AiSourceEdit(start: position, end: position, bytes: placed.bytes)];
}
