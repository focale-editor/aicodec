part of 'package:aikit/src/model/ai_native_records.dart';

/// Removes and inserts one complete pair while preserving both boundary states.
AiNativeDrawing _relocateNativeShape(AiNativeDrawing drawing, _NativeShapeBundle bundle, int position, AiNativeStructureNode? parent, bool inheritParentFlags) {
  if (position > bundle.start && position < bundle.shape.end) {
    throw ArgumentError('A native shape cannot be moved inside its own source span.');
  }
  final Map<int, _NativeShapeInputs> states = _sourceMovementStates(
    drawing,
    drawing._objects.structure.nodeFor(bundle.shape.appearanceGroup!),
    (start: bundle.start, end: bundle.shape.end),
    position,
    parent,
    inheritParentFlags,
  );
  final Map<String, AiNativeInstruction> restored = _restoredShapeStyle(bundle, states[bundle.shape.end]!);
  final List<int> retained = _removedShapeState(bundle, restored, drawing.records.program.limits.maxDecodedBytes);
  final ({List<int> bytes, _NativeShapeReplacement replacement}) placed = _placedNativeShape(
    drawing,
    bundle,
    states[bundle.start]!,
    states[bundle.shape.end]!,
    states[position]!,
    states[position]!,
    maxBytes: drawing.records.program.limits.maxDecodedBytes - retained.length,
  );
  _shapeFollowingDependencies(
    drawing,
    [bundle],
    {
      bundle.shape: _removedShapeReplacement(bundle, restored),
    },
    insertions: {position: placed.replacement},
  );
  return _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: bundle.start, end: bundle.shape.end, bytes: retained),
      AiSourceEdit(start: position, end: position, bytes: placed.bytes),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length,
  );
}

/// Relocates a complete pair after a distinct owned pair, retaining all identities.
AiNativeDrawing _moveNativeShapeAfter(AiNativeDrawing drawing, AiLiveShape shape, AiLiveShape after, bool inheritParentFlags) {
  final List<_NativeShapeBundle> selected = _selectedShapeBundles(drawing, [shape, after]);
  final _NativeShapeBundle bundle = selected.singleWhere((bundle) => identical(bundle.shape, shape));
  final AiNativeStructure structure = drawing._objects.structure;
  return _relocateNativeShape(drawing, bundle, after.end, structure.parentOf(structure.nodeFor(after.appearanceGroup!)), inheritParentFlags);
}

/// Appends a pair before a qualified ordinary group's closing boundary.
AiNativeDrawing _moveNativeShapeToGroup(AiNativeDrawing drawing, AiLiveShape shape, AiNativeGroup group, bool inheritParentFlags) {
  final AiNativeStructureNode parent = drawing._objects.structure.nodeFor(group);
  final _NativeShapeBundle bundle = _selectedShapeBundles(drawing, [shape]).single;
  return _relocateNativeShape(drawing, bundle, group.closing.start, parent, inheritParentFlags);
}

/// Appends a pair directly to an owned layer without rewriting its header.
AiNativeDrawing _moveNativeShapeToLayer(AiNativeDrawing drawing, AiLiveShape shape, AiLayer layer, bool inheritParentFlags) {
  _artworkLayerDestination(drawing, layer);
  final AiNativeStructureNode parent = drawing._objects.structure.nodeFor(layer);
  final _NativeShapeBundle bundle = _selectedShapeBundles(drawing, [shape]).single;
  return _relocateNativeShape(drawing, bundle, layer.end.start, parent, inheritParentFlags);
}
