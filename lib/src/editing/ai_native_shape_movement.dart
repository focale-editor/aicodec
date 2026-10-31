part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies destination ancestors without requiring ordinary-only child artwork.
void _shapeMovementParents(AiNativeDrawing drawing, List<AiNativeStructureNode> parents) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  final List<AiLiveShape> bound = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((first, second) => first.end.compareTo(second.end));
  for (final AiNativeStructureNode parent in parents) {
    if (parent.versions.isNotEmpty || !const {AiNativeStructureKind.layer, AiNativeStructureKind.group}.contains(parent.kind)) {
      throw UnsupportedError('Shape movement requires unconditional ordinary ancestors.');
    }
    if (parent.source case final AiNativeGroup group) {
      if (group.opening.isPrivate ||
          group.opening.operator != 'u' ||
          group.opening.operands.isNotEmpty ||
          group.closing.isPrivate ||
          group.closing.operator != 'U' ||
          group.closing.operands.isNotEmpty ||
          bound.any((shape) => group.start >= shape.start && group.end <= shape.end)) {
        throw UnsupportedError('A printing expansion or private group cannot receive native shapes.');
      }
      _ordinaryObjectFollowing(drawing, group);
      _ordinaryGroupPrefix(drawing, group, bound, headers, privateState: true);
      _ordinaryGroupPostfix(drawing, group);
    } else if (parent.source case final AiLayer layer) {
      _qualifiedLayerHeader(layers, layers.layerFor(layer));
    }
  }
}

/// Retains separate native/printing states and requires explicit parent inheritance.
Map<int, _NativeShapeInputs> _shapeMovementStates(
  AiNativeDrawing drawing,
  _NativeShapeBundle bundle,
  int position,
  AiNativeStructureNode? parent,
  bool inheritParentFlags,
) {
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeStructureNode> sourceParents = _artworkParents(structure, structure.parentOf(structure.nodeFor(bundle.shape.appearanceGroup!)));
  final List<AiNativeStructureNode> targetParents = _artworkParents(structure, parent);
  _shapeMovementParents(drawing, {...sourceParents, ...targetParents}.toList());
  final AiNativeStructureNode? sourceLayer = sourceParents.where((node) => node.kind == .layer).firstOrNull;
  final AiNativeStructureNode? targetLayer = targetParents.where((node) => node.kind == .layer).firstOrNull;
  if (!identical(sourceLayer, targetLayer) && !inheritParentFlags) {
    throw UnsupportedError('Moving shapes across layers requires explicit inheritParentFlags.');
  }
  final List<AiNativeStructureNode> sourceGroups = sourceParents.takeWhile((node) => node.kind == .group).toList();
  final List<AiNativeStructureNode> targetGroups = targetParents.takeWhile((node) => node.kind == .group).toList();
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, [
    bundle.start,
    bundle.shape.end,
    position,
    ...sourceGroups.map((node) => node.start),
    ...targetGroups.map((node) => node.start),
  ]);
  if (!inheritParentFlags &&
      (sourceGroups.length != targetGroups.length ||
          sourceGroups.indexed.any((entry) {
            final _NativeShapeInputs source = states[entry.$2.start]!;
            final _NativeShapeInputs target = states[targetGroups[entry.$1].start]!;
            return const {'A', 'Xw'}.any(
              (key) =>
                  !_sameShapeAttribute(source.printing, source.printingOrigins, target.printing, target.printingOrigins, key) ||
                  !_sameShapeAttribute(source.native, source.nativeOrigins, target.native, target.nativeOrigins, key),
            );
          }))) {
    throw UnsupportedError('Changing ancestor-group flags or depth requires explicit inheritParentFlags.');
  }
  return states;
}

/// Removes and inserts one complete pair while preserving both boundary states.
AiNativeDrawing _relocateNativeShape(AiNativeDrawing drawing, _NativeShapeBundle bundle, int position, AiNativeStructureNode? parent, bool inheritParentFlags) {
  if (position > bundle.start && position < bundle.shape.end) {
    throw ArgumentError('A native shape cannot be moved inside its own source span.');
  }
  final Map<int, _NativeShapeInputs> states = _shapeMovementStates(drawing, bundle, position, parent, inheritParentFlags);
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
