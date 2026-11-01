part of 'package:aikit/src/model/ai_native_records.dart';

/// Requires explicit inheritance when changing a non-neutral or unknown parent.
void _nativeGroupingFlags(AiNativeDrawing drawing, Iterable<int> boundaries, bool inheritParentFlags, {bool clipping = false}) {
  if (inheritParentFlags) {
    return;
  }
  final Map<int, _NativeShapeInputs> states = clipping ? _nativeContourInputs(drawing, boundaries) : _shapeCopyInputs(drawing, boundaries);
  for (final _NativeShapeInputs state in states.values) {
    if ([state.printing, state.native].any((values) => const {'A', 'Xw'}.any((key) => values[key]?.numbers?.single != 0))) {
      throw UnsupportedError('Changing a non-neutral or unknown group ancestor requires explicit inheritParentFlags.');
    }
  }
}

/// Wraps consecutive complete owners without relocating or rewriting their data.
AiNativeDrawing _groupNativeArtwork(
  AiNativeDrawing drawing,
  List<AiNativePath> paths,
  List<AiNativeGroup> groups,
  List<AiLiveShape> liveShapes,
  bool inheritParentFlags,
) {
  if (liveShapes.toSet().length != liveShapes.length || liveShapes.any((shape) => !drawing.liveShapes.contains(shape))) {
    throw ArgumentError('Grouping requires distinct owned live shapes.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativePath> ordinary = [
    ...paths,
    for (final AiLiveShape shape in liveShapes)
      if (_directNativeShapeIssue(shape) == null) shape.path!,
  ];
  final Map<AiNativePath, AiNativeInstruction?> counts = ordinary.isEmpty ? {} : _ordinaryPathCounts(drawing, ordinary, ownership: structure);
  final List<AiLiveShape> paired = liveShapes.where((shape) => _directNativeShapeIssue(shape) != null).toList();
  final List<_NativeShapeBundle> selected = paired.isEmpty ? [] : _selectedShapeBundles(drawing, paired);
  final List<({AiNativeStructureNode node, _NativeSubtreeSpan span})> owners = [
    for (final AiNativePath path in ordinary) (node: structure.nodeFor(path), span: (start: counts[path]?.start ?? path.start, end: _ordinaryObject(drawing, path).end)),
    for (final AiNativeGroup group in groups) (node: structure.nodeFor(group), span: (start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)),
    for (final _NativeShapeBundle pair in selected) (node: structure.nodeFor(pair.shape.appearanceGroup!), span: (start: pair.start, end: pair.shape.end)),
  ]..sort((first, second) => first.span.start.compareTo(second.span.start));
  if (owners.isEmpty ||
      owners.any((owner) => owner.node.parentIndex != owners.first.node.parentIndex) ||
      owners.indexed.any((entry) => entry.$1 > 0 && owners[entry.$1 - 1].span.end > entry.$2.span.start)) {
    throw ArgumentError('Grouping requires disjoint consecutive artwork with one immediate native owner.');
  }
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, owners.map((owner) => owner.span).toList());
  if (groups.isNotEmpty) {
    _ordinaryGroups(drawing, groups, pairs: pairs);
  }
  _sourceMovementParents(drawing, _artworkParents(structure, structure.parentOf(owners.first.node)));
  for (int index = 1; index < owners.length; index++) {
    final List<AiNativeInstruction> gap = _groupInterval(drawing, owners[index - 1].span.end, owners[index].span.start, nested: false, privateState: true);
    if (gap.any((command) => _nativeArtworkStateKey(command) == null)) {
      throw ArgumentError('Grouping cannot absorb unselected artwork or point counts.');
    }
  }
  final int start = owners.first.span.start;
  final int end = owners.last.span.end;
  _nativeGroupingFlags(drawing, [start], inheritParentFlags);
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: start, end: start, bytes: latin1.encode('\nu\n')),
      AiSourceEdit(start: end, end: end, bytes: latin1.encode('\nU\n')),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length + 1,
    liveShapes: drawing.liveShapes.length,
  );
  final AiNativeGroup group = result.groups.singleWhere((group) => group.start == start + 1);
  _ordinaryGroups(result, [group], pairs: _subtreeShapeBundles(result, [(start: group.start, end: group.end)]));
  return result;
}

/// Removes only qualified parent boundaries, with explicit metadata/flag policies.
AiNativeDrawing _dissolveNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups, bool discardMetadata, bool inheritParentFlags) {
  final List<_NativeSubtreeSpan> spans = [for (final AiNativeGroup group in groups) (start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)];
  _ordinaryGroups(drawing, groups, pairs: _subtreeShapeBundles(drawing, spans));
  final List<AiNativeObject> objects = groups.map((group) => _ordinaryObject(drawing, group)).toList();
  if (!discardMetadata && objects.any((object) => object.dictionary?.entries.isNotEmpty ?? false)) {
    throw UnsupportedError('Dissolving a group requires explicit metadata disposal.');
  }
  // Ordinary ownership admits only the neutral mode-nine group reset. Removing
  // it with its parent preserves child appearance and persistent scalar state;
  // named styles, blend applications and private resets fail qualification.
  for (final AiNativeObject object in objects) {
    final AiNativeInstruction? reset = object.styleApplication;
    if (reset != null && drawing.gradients.any((gradient) => gradient.start < reset.end && gradient.end > reset.start)) {
      throw UnsupportedError('Dissolving a group reset inside a gradient instance requires its complete appearance owner.');
    }
  }
  _nativeGroupingFlags(drawing, groups.map((group) => group.start), inheritParentFlags);
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  _nativeRemovalReferences(layers, [for (final AiNativeObject object in objects) ?object.identifier], _layerHeaderItems(layers));
  return _groupLifecycleResult(
    drawing,
    [
      for (final (int, AiNativeGroup) entry in groups.indexed) ...[
        AiSourceEdit(start: objects[entry.$1].start, end: entry.$2.opening.end, bytes: [32]),
        AiSourceEdit(start: entry.$2.closing.start, end: objects[entry.$1].end, bytes: [32]),
      ],
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length - groups.length,
    liveShapes: drawing.liveShapes.length,
  );
}
