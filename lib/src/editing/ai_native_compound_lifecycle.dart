part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies complete compound elements without interpreting their appearance.
List<AiNativePathTopology> _nativeCompoundElements(AiNativeDrawing drawing, List<AiNativeItem> elements, {AiNativeGroup? compound, bool retainContourData = false}) {
  final List<AiNativeItem> pending = [...elements];
  final List<AiNativeGroup> groups = [];
  final List<AiNativePath> paths = [];
  while (pending.isNotEmpty) {
    final AiNativeItem item = pending.removeLast();
    if (retainContourData) {
      _nativeContourOwner(drawing, item);
    } else {
      _ordinaryObject(drawing, item);
    }
    if (item is AiNativePath) {
      paths.add(item);
    } else if (item is AiNativeGroup && const {'u', 'q'}.contains(item.opening.operator) && item.children.isNotEmpty) {
      groups.add(item);
      pending.addAll(item.children);
    } else {
      throw UnsupportedError('Compound elements require ordinary contours or populated ordinary subgroups.');
    }
  }
  final List<AiNativePathTopology> topology = _nativePathTopologies(drawing, paths);
  final Set<AiNativeInstruction> commands = {
    for (final AiNativePathTopology owner in topology) ...[...owner.path.geometry, owner.path.paint, ...owner.maskControls, ?owner.pointCount],
    for (final AiNativeGroup group in groups) ...[group.opening, group.closing],
    if (compound != null) ...[compound.opening, compound.closing],
  };
  for (final AiNativeGroup group in compound == null ? elements.whereType<AiNativeGroup>() : [compound]) {
    for (final AiNativeItem item in _pathInterval(drawing.items, group.start, group.end, (item) => item.start)) {
      if (!commands.contains(item) &&
          !_ordinaryObjectAttachment(drawing, item) &&
          !(retainContourData && drawing._pathTopologyScope.retainedMetadata.contains(drawing._objects._attachments[item.start]?.dictionary)) &&
          (item is! AiNativeInstruction || (retainContourData ? _nativeContourStateKey(item) : _nativeArtworkStateKey(item)) == null)) {
        throw UnsupportedError('Compound subgroups cannot contain non-contour artwork or unresolved style applications.');
      }
    }
  }
  final Set<bool> masks = topology.map((owner) => owner.mask != .none).toSet();
  if (masks.length != 1) {
    throw UnsupportedError('Compound elements must be either all mask contours or all ordinary contours.');
  }
  for (final AiNativeGroup group in groups) {
    final bool clipping = group.opening.operator == 'q';
    if ((!masks.single && clipping) || masks.single && group.children.any((child) => clipping ? child is! AiNativePath : child is! AiNativeGroup)) {
      throw UnsupportedError('Compound mask subgroups require path-only clipping leaves and group-only ordinary branches.');
    }
  }
  return topology;
}

/// Rejects nesting a complete compound inside an existing compound contour tree.
void _nativeCompoundParents(AiNativeDrawing drawing, AiNativeItem source) {
  final AiNativeStructure structure = drawing._objects.structure;
  if (_artworkParents(structure, structure.parentOf(structure.nodeFor(source))).any((parent) => parent.kind == .compound)) {
    throw UnsupportedError('Compound lifecycle requires a complete outer compound owner.');
  }
}

/// Wraps one consecutive sibling selection without rewriting its child records.
AiNativeDrawing _compoundNativeArtwork(AiNativeDrawing drawing, List<AiNativePath> paths, List<AiNativeGroup> groups, AiBoundingBox bounds, bool inheritParentFlags) {
  _nativeTopologyBounds(bounds);
  final List<AiNativeItem> selected = [...paths, ...groups];
  if (selected.isEmpty || selected.toSet().length != selected.length) {
    throw ArgumentError('Compounding requires distinct source owners.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeStructureNode> nodes = selected.map(structure.nodeFor).toList();
  if (nodes.any((node) => node.parentIndex != nodes.first.parentIndex)) {
    throw ArgumentError('Compounding requires disjoint sibling artwork.');
  }
  _nativeCompoundParents(drawing, selected.first);
  final List<AiNativePathTopology> topology = _nativeCompoundElements(drawing, selected, retainContourData: true);
  final Map<AiNativePath, AiNativeInstruction?> counts = {for (final AiNativePathTopology owner in topology) owner.path: owner.pointCount};
  final List<_NativeSubtreeSpan> spans = [
    for (final AiNativeItem item in selected) (start: item is AiNativePath ? counts[item]?.start ?? item.start : _nativeContourOwner(drawing, item).start, end: _nativeContourOwner(drawing, item).end),
  ]..sort((first, second) => first.start.compareTo(second.start));
  for (int index = 1; index < spans.length; index++) {
    if (spans[index - 1].end > spans[index].start) {
      throw ArgumentError('Compounding requires nonoverlapping complete owners.');
    }
    for (final AiNativeItem item in _pathInterval(drawing.items, spans[index - 1].end, spans[index].start, (item) => item.start)) {
      if (item is! AiNativeInstruction || _nativeContourStateKey(item) == null) {
        throw ArgumentError('Compounding cannot absorb unselected artwork, counts or metadata.');
      }
    }
  }
  _nativeGroupingFlags(drawing, [spans.first.start], inheritParentFlags, clipping: true);
  if (topology.first.mask != .none && !topology.first.groups.any((group) => group.opening.operator == 'q' && group.start < spans.first.start && group.end > spans.last.end)) {
    throw UnsupportedError('A new compound mask requires a shared clipping owner outside the selected elements.');
  }
  final List<AiNativeGroup> clipping = drawing.groups.where((group) => group.opening.operator == 'q' && group.start >= spans.first.start && group.end <= spans.last.end).toList();
  return _nativeCompoundResult(
    drawing,
    [
      AiSourceEdit(start: spans.first.start, end: spans.first.start, bytes: latin1.encode('\n*u\n')),
      AiSourceEdit(start: spans.last.end, end: spans.last.end, bytes: latin1.encode('\n*U\n')),
      ..._nativeCompoundClipState(drawing, clipping, activate: false),
    ],
    bounds,
    drawing.groups.length + 1,
  );
}

/// Removes only disjoint compound owners, retaining all nested group scopes.
AiNativeDrawing _releaseNativeCompounds(AiNativeDrawing drawing, List<AiNativeGroup> groups, AiBoundingBox bounds, bool discardMetadata, bool inheritParentFlags) {
  _nativeTopologyBounds(bounds);
  if (groups.isEmpty || groups.toSet().length != groups.length) {
    throw ArgumentError('Releasing compounds requires distinct source groups.');
  }
  final List<AiNativeObject> owners = groups.map((group) => _nativeContourOwner(drawing, group)).toList();
  final List<AiNativeGroup> ordered = [...groups]..sort((first, second) => first.start.compareTo(second.start));
  if (ordered.indexed.any((entry) => entry.$1 > 0 && ordered[entry.$1 - 1].end > entry.$2.start)) {
    throw ArgumentError('Releasing compounds requires disjoint owners.');
  }
  for (final AiNativeGroup group in groups) {
    if (!group.compound) {
      throw ArgumentError('Releasing compounds requires native compound groups.');
    }
    _nativeCompoundParents(drawing, group);
    _nativeCompoundElements(drawing, group.children, compound: group, retainContourData: true);
  }
  if (!discardMetadata && owners.any((owner) => owner.dictionary?.entries.isNotEmpty ?? false)) {
    throw UnsupportedError('Releasing a compound requires explicit disposal of its parent metadata.');
  }
  _nativeGroupingFlags(drawing, groups.map((group) => group.start), inheritParentFlags, clipping: true);
  _nativeContourRemovalReferences(drawing, owners);
  final List<AiNativeGroup> clipping = drawing.groups.where((child) => child.opening.operator == 'q' && groups.any((group) => child.start > group.start && child.end < group.end)).toList();
  return _nativeCompoundResult(
    drawing,
    [
      for (final (int, AiNativeGroup) entry in groups.indexed) ...[
        AiSourceEdit(start: owners[entry.$1].start, end: entry.$2.opening.end, bytes: [32]),
        AiSourceEdit(start: entry.$2.closing.start, end: owners[entry.$1].end, bytes: [32]),
      ],
      ..._nativeCompoundClipState(drawing, clipping, activate: true),
    ],
    bounds,
    drawing.groups.length - groups.length,
  );
}

/// Reopens a bounded transaction and qualifies every resulting contour scope.
AiNativeDrawing _nativeCompoundResult(AiNativeDrawing drawing, List<AiSourceEdit> edits, AiBoundingBox bounds, int groups) {
  edits.addAll(AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds));
  edits.removeWhere((edit) => _sameNativeBytes(Uint8List.sublistView(drawing.records.program.bytes, edit.start, edit.end), edit.bytes));
  final AiNativeDrawing result = _groupLifecycleResult(drawing, edits, paths: drawing.paths.length, groups: groups, liveShapes: drawing.liveShapes.length);
  if (result._pathTopologyScope.derived.length != drawing._pathTopologyScope.derived.length) {
    throw const FormatException('Compound edits changed unrelated derived geometry ownership.');
  }
  return result;
}
