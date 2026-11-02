part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies destination ancestors without requiring ordinary-only child artwork.
void _sourceMovementParents(AiNativeDrawing drawing, List<AiNativeStructureNode> parents) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  final List<AiLiveShape> bound = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((first, second) => first.end.compareTo(second.end));
  for (final AiNativeStructureNode parent in parents) {
    if (parent.versions.isNotEmpty || !const {AiNativeStructureKind.layer, AiNativeStructureKind.group}.contains(parent.kind)) {
      throw UnsupportedError('Native movement requires unconditional ordinary ancestors.');
    }
    if (parent.source case final AiNativeGroup group) {
      if (group.opening.isPrivate ||
          group.opening.operator != 'u' ||
          group.opening.operands.isNotEmpty ||
          group.closing.isPrivate ||
          group.closing.operator != 'U' ||
          group.closing.operands.isNotEmpty ||
          bound.any((shape) => group.start >= shape.start && group.end <= shape.end)) {
        throw UnsupportedError('A printing expansion or private group cannot receive native artwork.');
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
Map<int, _NativeShapeInputs> _sourceMovementStates(
  AiNativeDrawing drawing,
  AiNativeStructureNode owner,
  _NativeSubtreeSpan span,
  int position,
  AiNativeStructureNode? parent,
  bool inheritParentFlags, {
  Iterable<int> boundaries = const [],
  List<AiNativeAppearanceArtwork> appearanceArtwork = const [],
}) {
  final AiNativeStructure structure = drawing._objects.structure;
  // Layer and object inventories can own separate structure snapshots over the
  // same immutable source handles. Resolve both through this inventory first.
  final List<AiNativeStructureNode> sourceParents = _artworkParents(structure, structure.parentOf(structure.nodeFor(owner.source)));
  final List<AiNativeStructureNode> targetParents = _artworkParents(structure, parent == null ? null : structure.nodeFor(parent.source));
  _sourceMovementParents(drawing, {...sourceParents, ...targetParents}.toList());
  final AiNativeStructureNode? sourceLayer = sourceParents.where((node) => node.kind == .layer).firstOrNull;
  final AiNativeStructureNode? targetLayer = targetParents.where((node) => node.kind == .layer).firstOrNull;
  if (!identical(sourceLayer, targetLayer) && !inheritParentFlags) {
    throw UnsupportedError('Moving artwork across layers requires explicit inheritParentFlags.');
  }
  final List<AiNativeStructureNode> sourceGroups = sourceParents.takeWhile((node) => node.kind == .group).toList();
  final List<AiNativeStructureNode> targetGroups = targetParents.takeWhile((node) => node.kind == .group).toList();
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      span.start,
      span.end,
      ...boundaries,
      position,
      ...sourceGroups.map((node) => node.start),
      ...targetGroups.map((node) => node.start),
    ],
    appearanceArtwork: appearanceArtwork,
    clipping: appearanceArtwork.isNotEmpty,
  );
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
