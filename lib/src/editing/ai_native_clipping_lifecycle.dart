part of 'package:aikit/src/model/ai_native_records.dart';

/// Keeps ordinary and masked compound subgroup kinds consistent with their role.
List<AiSourceEdit> _nativeClippingCompoundGroups(AiNativeDrawing drawing, List<AiNativePathEdit> masks, {required bool masked}) {
  final AiNativeStructure structure = drawing._objects.structure;
  final Set<AiNativeGroup> compounds = {
    for (final AiNativePathEdit mask in masks)
      for (final AiNativeStructureNode parent in _artworkParents(structure, structure.parentOf(structure.nodeFor(mask.path))))
        if (parent.source case final AiNativeGroup group when group.compound) group,
  };
  final Set<AiNativeGroup> changed = {};
  for (final AiNativeGroup compound in compounds) {
    final List<AiNativeGroup> pending = compound.children.whereType<AiNativeGroup>().toList();
    while (pending.isNotEmpty) {
      final AiNativeGroup group = pending.removeLast();
      if (group.compound) {
        throw UnsupportedError('Clipping changes require a complete non-nested compound contour tree.');
      }
      final List<AiNativeGroup> children = group.children.whereType<AiNativeGroup>().toList();
      if (masked && (group.children.isEmpty || children.isNotEmpty && children.length != group.children.length)) {
        throw UnsupportedError('Compound mask branches require explicit regrouping of mixed or empty elements.');
      }
      final bool clipping = masked && children.isEmpty;
      if ((group.opening.operator == 'q') != clipping) {
        changed.add(group);
      }
      pending.addAll(children);
    }
  }
  return [
    for (final AiNativeGroup group in changed) ...[
      AiSourceEdit(start: group.opening.start, end: group.opening.end, bytes: latin1.encode(masked && group.children.every((child) => child is AiNativePath) ? 'q' : 'u')),
      AiSourceEdit(start: group.closing.start, end: group.closing.end, bytes: latin1.encode(masked && group.children.every((child) => child is AiNativePath) ? 'Q' : 'U')),
    ],
  ];
}

/// Qualifies ordinary contour artwork while retaining complete nested groups.
List<AiNativePathTopology> _nativeClippingElements(AiNativeDrawing drawing, List<AiNativeItem> elements) {
  final List<AiNativeItem> pending = [...elements];
  final List<AiNativeGroup> groups = [];
  final List<AiNativePath> paths = [];
  while (pending.isNotEmpty) {
    final AiNativeItem item = pending.removeLast();
    _ordinaryObject(drawing, item);
    if (item is AiNativePath) {
      paths.add(item);
    } else if (item is AiNativeGroup) {
      groups.add(item);
      pending.addAll(item.children);
    }
  }
  final List<AiNativePathTopology> topology = paths.isEmpty ? [] : _nativePathTopologies(drawing, paths);
  final Set<AiNativeInstruction> commands = {
    for (final AiNativePathTopology owner in topology) ...[...owner.path.geometry, owner.path.paint, ...owner.maskControls, ?owner.pointCount],
    for (final AiNativeGroup group in groups) ...[group.opening, group.closing],
  };
  for (final AiNativeGroup group in elements.whereType<AiNativeGroup>()) {
    for (final AiNativeItem item in _pathInterval(drawing.items, group.start, group.end, (item) => item.start)) {
      if (commands.contains(item) || _ordinaryObjectAttachment(drawing, item)) {
        continue;
      }
      if (item is! AiNativeInstruction || item.operator == 'Xy' || _nativeArtworkStateKey(item) == null) {
        throw UnsupportedError('Clipping lifecycle requires ordinary contour state and complete non-derived artwork.');
      }
    }
  }
  return topology;
}

/// Wraps complete siblings and supplies their masks in one source transaction.
AiNativeDrawing _clipNativeArtwork(
  AiNativeDrawing drawing,
  List<AiNativePath> paths,
  List<AiNativeGroup> groups,
  List<AiNativePathEdit> masks,
  AiBoundingBox bounds,
  bool inheritParentFlags,
) {
  _nativeTopologyBounds(bounds);
  final List<AiNativeItem> selected = [...paths, ...groups];
  if (selected.isEmpty || selected.toSet().length != selected.length || masks.isEmpty || masks.any((edit) => edit.mask == null || edit.mask == .none)) {
    throw ArgumentError('Clipping requires distinct source owners and explicit open or closed mask requests.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeStructureNode> nodes = selected.map(structure.nodeFor).toList();
  if (nodes.any((node) => node.parentIndex != nodes.first.parentIndex)) {
    throw ArgumentError('Clipping requires disjoint consecutive sibling owners.');
  }
  _nativeCompoundParents(drawing, selected.first);
  final List<AiNativePathTopology> topology = _nativeClippingElements(drawing, selected);
  final Map<AiNativePath, AiNativePathTopology> contours = {for (final AiNativePathTopology owner in topology) owner.path: owner};
  final List<_NativeSubtreeSpan> spans = [
    for (final AiNativeItem item in selected)
      (start: item is AiNativePath ? contours[item]!.pointCount?.start ?? item.start : _ordinaryObject(drawing, item).start, end: _ordinaryObject(drawing, item).end),
  ]..sort((first, second) => first.start.compareTo(second.start));
  for (int index = 1; index < spans.length; index++) {
    if (spans[index - 1].end > spans[index].start) {
      throw ArgumentError('Clipping requires disjoint source owners.');
    }
    for (final AiNativeItem item in _pathInterval(drawing.items, spans[index - 1].end, spans[index].start, (item) => item.start)) {
      if (item is! AiNativeInstruction || item.operator == 'Xy' || _nativeArtworkStateKey(item) == null) {
        throw UnsupportedError('Clipping cannot absorb unselected artwork or unresolved appearance state.');
      }
    }
  }
  for (final AiNativePathEdit mask in masks) {
    final AiNativePathTopology? owner = contours[mask.path];
    if (owner == null || owner.clippingGroup != null && owner.clippingGroup!.start >= spans.first.start) {
      throw ArgumentError('Each requested mask must belong to the new clipping scope.');
    }
  }
  _nativeGroupingFlags(drawing, [spans.first.start], inheritParentFlags, clipping: true);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, [spans.first.start, spans.last.end], clipping: true);
  final List<int> replay = _nativeClipStateReplay(drawing, states[spans.first.start]!, states[spans.last.end]!);
  return _nativeCompoundResult(
    drawing,
    [
      AiSourceEdit(start: spans.first.start, end: spans.first.start, bytes: latin1.encode('\nq\n')),
      ..._nativePathEdits(drawing, masks, newClipPaths: contours.keys.toSet()),
      ..._nativeClippingCompoundGroups(drawing, masks, masked: true),
      AiSourceEdit(start: spans.last.end, end: spans.last.end, bytes: [...latin1.encode('\nQ\n'), ...replay]),
    ],
    bounds,
    drawing.groups.length + 1,
  );
}

/// Removes complete scopes while restoring each retained outgoing state.
AiNativeDrawing _releaseNativeClipping(AiNativeDrawing drawing, List<AiNativeGroup> groups, AiBoundingBox bounds, bool discardMetadata, bool inheritParentFlags) {
  _nativeTopologyBounds(bounds);
  if (groups.isEmpty || groups.toSet().length != groups.length) {
    throw ArgumentError('Releasing clipping groups requires distinct current owners.');
  }
  final List<AiNativeObject> owners = groups.map((group) => _ordinaryObject(drawing, group)).toList();
  final List<AiNativeGroup> ordered = [...groups]..sort((first, second) => first.start.compareTo(second.start));
  if (ordered.indexed.any((entry) => entry.$1 > 0 && ordered[entry.$1 - 1].end > entry.$2.start)) {
    throw ArgumentError('Releasing clipping groups requires disjoint selections.');
  }
  final List<AiNativePathEdit> masks = [];
  for (final AiNativeGroup group in groups) {
    if (group.opening.operator != 'q' || group.opening.isPrivate) {
      throw ArgumentError('Releasing clipping requires ordinary q/Q owners.');
    }
    _nativeCompoundParents(drawing, group);
    masks.addAll([
      for (final AiNativePathTopology owner in _nativeClippingElements(drawing, [group]))
        if (owner.mask != .none && identical(owner.clippingGroup, group)) AiNativePathEdit(path: owner.path, mask: .none),
    ]);
  }
  if (!discardMetadata && owners.any((owner) => owner.dictionary?.entries.isNotEmpty ?? false)) {
    throw UnsupportedError('Releasing clipping groups requires explicit parent metadata disposal.');
  }
  _nativeGroupingFlags(drawing, groups.map((group) => group.start), inheritParentFlags, clipping: true);
  final AiNativeLayers layers = drawing._pathTopologyScope.layers;
  _nativeRemovalReferences(layers, [for (final AiNativeObject owner in owners) ?owner.identifier], _layerHeaderItems(layers), bodyDictionaries: drawing._pathTopologyScope.dictionaries);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, [
    for (final AiNativeGroup group in groups) ...[group.closing.start, group.closing.end],
  ], clipping: true);
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  final List<AiSourceEdit> boundaries = [];
  for (final (int, AiNativeGroup) entry in groups.indexed) {
    final List<int> replay = _nativeClipStateReplay(drawing, states[entry.$2.closing.start]!, states[entry.$2.closing.end]!, maxBytes: remaining);
    remaining -= replay.length;
    boundaries.addAll([
      AiSourceEdit(start: owners[entry.$1].start, end: entry.$2.opening.end, bytes: [32]),
      AiSourceEdit(start: entry.$2.closing.start, end: owners[entry.$1].end, bytes: [32, ...replay]),
    ]);
  }
  return _nativeCompoundResult(
    drawing,
    [
      if (masks.isNotEmpty) ..._nativePathEdits(drawing, masks),
      ..._nativeClippingCompoundGroups(drawing, masks, masked: false),
      ...boundaries,
    ],
    bounds,
    drawing.groups.length - groups.length,
  );
}
