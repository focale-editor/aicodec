part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies complete state/geometry intervals without evaluating opaque records.
List<AiNativeInstruction> _groupInterval(AiNativeDrawing drawing, int start, int end, {bool nested = true, bool privateState = false, bool retainImages = false}) {
  final List<AiNativeInstruction> commands = [];
  final List<AiNativeGradientArtwork> gradients = drawing.gradientArtwork;
  final List<AiNativeMeshArtwork> meshes = drawing.meshArtwork;
  int meshIndex = 0;
  int gradientIndex = 0;
  final List<_NativeImageOwner> images = retainImages ? _nativeImageOwners(drawing) : [];
  int imageIndex = 0;
  for (final AiNativeItem item in _pathInterval(drawing.items, start, end, (item) => item.start)) {
    while (meshIndex < meshes.length && meshes[meshIndex].end <= item.start) {
      meshIndex++;
    }
    if (meshIndex < meshes.length && meshes[meshIndex].start <= item.start) {
      final AiNativeMeshArtwork owner = meshes[meshIndex];
      if (owner.start < start || owner.end > end || item.end > owner.end) {
        throw UnsupportedError('Artwork cannot split a complete mesh owner.');
      }
      if (item.start == owner.start) {
        commands.add(owner._access);
      }
      continue;
    }
    while (gradientIndex < gradients.length && gradients[gradientIndex].end <= item.start) {
      gradientIndex++;
    }
    if (gradientIndex < gradients.length && gradients[gradientIndex].start <= item.start) {
      final AiNativeGradientArtwork owner = gradients[gradientIndex];
      if (owner.start < start || owner.end > end || item.end > owner.end) {
        throw UnsupportedError('Group artwork cannot split a complete gradient owner.');
      }
      if (item.start == owner.path.start) {
        commands.add(owner.path.geometry.first);
      }
      continue;
    }
    while (imageIndex < images.length && images[imageIndex].span.end <= item.start) {
      imageIndex++;
    }
    if (imageIndex < images.length && images[imageIndex].span.start <= item.start) {
      final _NativeImageOwner owner = images[imageIndex];
      if (owner.span.start < start || owner.span.end > end || item.end > owner.span.end) {
        throw UnsupportedError('Group artwork cannot split a retained image owner.');
      }
      if (item.start == owner.instruction.start) {
        commands.add(owner.instruction);
      }
      continue;
    }
    if (_ordinaryObjectAttachment(drawing, item) && item.end <= end) {
      continue;
    }
    if (item is! AiNativeInstruction || item.isPrivate && !(privateState && _nativeArtworkStateKey(item) != null) || item.end > end) {
      throw UnsupportedError('Ordinary group edits require isolated non-private instructions.');
    }
    if (const {'u', 'U'}.contains(item.operator)) {
      if (!nested || item.operands.isNotEmpty) {
        throw UnsupportedError('The selected interval has an unqualified group boundary.');
      }
    } else if (!_nativeGeometry.contains(item.operator) && !_nativePaint.contains(item.operator) && item.operator != 'As' && _nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('Ordinary group edits have no state contract for ${item.operator}.');
    }
    commands.add(item);
  }
  imageIndex = 0;
  gradientIndex = 0;
  meshIndex = 0;
  if (_pathInterval(drawing.records._projection.tokens, start, end, (token) => token.start).any((token) {
    while (meshIndex < meshes.length && meshes[meshIndex].end <= token.start) {
      meshIndex++;
    }
    if (meshIndex < meshes.length && meshes[meshIndex].start <= token.start && token.end <= meshes[meshIndex].end) {
      return false;
    }
    while (gradientIndex < gradients.length && gradients[gradientIndex].end <= token.start) {
      gradientIndex++;
    }
    if (gradientIndex < gradients.length && gradients[gradientIndex].start <= token.start && token.end <= gradients[gradientIndex].end) {
      return false;
    }
    while (imageIndex < images.length && images[imageIndex].span.end <= token.start) {
      imageIndex++;
    }
    if (imageIndex < images.length && images[imageIndex].span.start <= token.start && token.end <= images[imageIndex].span.end) {
      return false;
    }
    return token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'));
  })) {
    throw UnsupportedError('Ordinary group edits cannot reinterpret native metadata or opaque data.');
  }
  return commands;
}

/// Refuses consumed expansion flags and unresolved prefixes before a group.
///
/// Private scalar prefixes require a caller that validates native state separately.
void _ordinaryGroupPrefix(AiNativeDrawing drawing, AiNativeGroup group, List<AiLiveShape> bound, Map<int, AiNativeLayer> layerHeaders, {bool privateState = false}) {
  final int start = _ordinaryObject(drawing, group).start;
  _ordinaryArtworkPrefix(
    drawing,
    start,
    bound,
    layerHeaders,
    privateState: privateState,
    resolvedBoundary: _nativeCreationBoundary(drawing, start, _nativeCreationAppearances(drawing)),
  );
}

/// Qualifies an artwork boundary without capturing unknown prefixes or metadata.
void _ordinaryArtworkPrefix(AiNativeDrawing drawing, int start, List<AiLiveShape> bound, Map<int, AiNativeLayer> layerHeaders, {bool privateState = false, int? resolvedBoundary}) {
  final List<AiNativeItem> items = drawing.items;
  final int preceding = _pathOffset(bound, start + 1, (shape) => shape.end);
  final int resolved = max(resolvedBoundary ?? drawing.records.program.bodyStart, preceding == 0 ? drawing.records.program.bodyStart : bound[preceding - 1].end);
  int boundary = resolved;
  for (int index = _pathOffset(items, start, (item) => item.start) - 1; index >= 0 && items[index].end > resolved; index--) {
    final AiNativeItem item = items[index];
    if (_ordinaryObjectAttachment(drawing, item)) {
      boundary = item.end;
      break;
    }
    if (layerHeaders[item.start] case final AiNativeLayer owner when owner.bindingIssue == null && item.start == owner.source.end.start) {
      boundary = owner.end;
      break;
    }
    if (layerHeaders[item.start] case final AiNativeLayer owner when owner.bindingIssue == null && item.start != owner.source.begin.start && item.start != owner.source.end.start) {
      continue;
    }
    if (item is! AiNativeInstruction || item.isPrivate && !(privateState && _nativeArtworkStateKey(item) != null)) {
      throw UnsupportedError('The selected group has an unresolved native prefix.');
    }
    if (_nativePaint.contains(item.operator) || const {'u', 'U', 'Lb', 'LB'}.contains(item.operator)) {
      boundary = item.end;
      break;
    }
    if (_nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('The selected group has an unqualified prefix ${item.operator}.');
    }
  }
  _ordinaryGroupMetadata(drawing, boundary, start);
}

/// Rejects metadata comments that can attach an identity or property to an owner.
void _ordinaryGroupMetadata(AiNativeDrawing drawing, int start, int end) {
  if (_pathInterval(drawing.records._projection.tokens, start, end, (token) => token.start).any(
    (token) => token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')),
  )) {
    throw UnsupportedError('The selected group has unresolved attached metadata.');
  }
}

/// Checks trailing metadata before the following object or enclosing boundary.
void _ordinaryGroupPostfix(AiNativeDrawing drawing, AiNativeGroup group) {
  final int start = _ordinaryObject(drawing, group).end;
  int end = _nativeNeutralArtwork(drawing).where((owner) => owner.start >= start).firstOrNull?.start ?? drawing.records.program.bodyEnd;
  for (int index = _pathOffset(drawing.items, start, (item) => item.start); index < drawing.items.length; index++) {
    final AiNativeItem item = drawing.items[index];
    if (item.start >= end) {
      break;
    }
    if (item is AiNativeInstruction && const {'m', 'u', 'U', 'Lb', 'LB'}.contains(item.operator)) {
      end = item.start;
      break;
    }
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  for (final AiNativeLayer layer in layers.layers) {
    if (layer.bindingIssue == null && layer.start >= start && layer.start < end) {
      end = layer.start;
    }
  }
  _ordinaryGroupMetadata(drawing, start, end);
}

/// Validates disjoint ordinary owners, attached records and every contained path.
AiNativeStructure _ordinaryGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups, {List<_NativeShapeBundle> pairs = const []}) {
  final Set<AiNativeGroup> owned = drawing.groups.toSet();
  if (groups.isEmpty || groups.toSet().length != groups.length || groups.any((group) => !owned.contains(group))) {
    throw ArgumentError('Group lifecycle operations require distinct owned source groups.');
  }
  final List<AiNativeGroup> ordered = [...groups]..sort((a, b) => a.start.compareTo(b.start));
  if (ordered.indexed.any((entry) => entry.$1 > 0 && ordered[entry.$1 - 1].end > entry.$2.start)) {
    throw ArgumentError('Selected groups cannot contain each other.');
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final AiNativeStructure ownership = layers.structure;
  final Set<AiLiveShape> paired = pairs.map((pair) => pair.shape).toSet();
  final List<AiLiveShape> shapes = drawing.liveShapes.where((shape) => !paired.contains(shape) && _directNativeShapeIssue(shape) != null).toList()..sort((a, b) => a.start.compareTo(b.start));
  final List<AiLiveShape> bound = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((a, b) => a.end.compareTo(b.end));
  final Map<int, AiNativeLayer> layerHeaders = _layerHeaderItems(layers);
  int shapeIndex = 0;
  int shapeEnd = 0;
  for (final AiNativeGroup group in ordered) {
    while (shapeIndex < shapes.length && shapes[shapeIndex].start < group.end) {
      shapeEnd = max(shapeEnd, shapes[shapeIndex++].end);
    }
    if (group.opening.operator != 'u' || group.opening.isPrivate || shapeEnd > group.start) {
      throw UnsupportedError('Group lifecycle operations require independent ordinary authoring groups.');
    }
  }
  final Set<AiNativePath> pairedPaths = {
    for (final _NativeShapeBundle pair in pairs) ...[pair.shape.path!, ...pair.shape.appearancePaths],
    ...drawing.gradientArtwork.map((owner) => owner.path),
  };
  final List<AiNativePath> paths = [for (final AiNativeGroup group in groups) ...group.paths.where((path) => !pairedPaths.contains(path))];
  final Map<AiNativePath, AiNativeInstruction?> counts = paths.isEmpty ? {} : _ordinaryPathCounts(drawing, paths, ownership: ownership);
  final Set<AiNativeInstruction> pathCommands = {
    for (final AiNativeGradientArtwork owner in drawing.gradientArtwork) owner.path.geometry.first,
    for (final AiNativePath path in paths) ...[...path.geometry, path.paint],
    ...counts.values.whereType<AiNativeInstruction>(),
  };
  final Set<AiNativeStructureNode> checked = {};
  for (final AiNativeGroup group in groups) {
    AiNativeStructureNode? node = ownership.nodeFor(group);
    while (node != null) {
      if (node.versions.isNotEmpty || node.kind != .group && node.kind != .layer || node.source is AiNativeGroup && (node.source as AiNativeGroup).opening.isPrivate) {
        throw UnsupportedError('The selected group has unresolved, private or conditional ownership.');
      }
      if (checked.add(node)) {
        if (node.source case final AiNativeGroup owner) {
          _ordinaryObjectFollowing(drawing, owner);
          _ordinaryGroupPrefix(drawing, owner, bound, layerHeaders, privateState: (pairs.isNotEmpty || drawing.gradientArtwork.isNotEmpty || drawing.meshArtwork.isNotEmpty));
          _ordinaryGroupPostfix(drawing, owner);
        } else {
          _ordinaryPathFollowing(drawing.items, node.end);
        }
      }
      node = ownership.parentOf(node);
    }
    final List<AiNativeInstruction> commands = (pairs.isEmpty && drawing.gradientArtwork.isEmpty && drawing.meshArtwork.isEmpty)
        ? _groupInterval(drawing, group.start, group.end)
        : _subtreeOrdinaryCommands(layers, group.start, group.end, pairs, groups: true);
    for (final AiNativeInstruction command in commands) {
      if ((_nativeGeometry.contains(command.operator) || _nativePaint.contains(command.operator) || command.operator == 'As') && !pathCommands.contains(command)) {
        throw UnsupportedError('The selected group contains unowned geometry or point counts.');
      }
    }
    final int preceding = _pathOffset(drawing.paths, group.start + 1, (path) => path.end);
    final int previous = preceding == 0 ? drawing.records.program.bodyStart : drawing.paths[preceding - 1].end;
    if (_pathInterval(drawing.records._projection.tokens, previous, group.start, (token) => token.start).any((token) => token.kind == .comment && token.lexeme.startsWith('%AI3_Note:'))) {
      throw UnsupportedError('A noted group requires explicit native annotation ownership.');
    }
  }
  return ownership;
}

/// Captures known assignments without merging unknown values across opaque owners.
Map<int, _NativeArtworkState> _groupStates(AiNativeDrawing drawing, Iterable<int> boundaries) => _nativeArtworkStates(drawing, boundaries);

/// Replays source values around a group while retaining both boundary states.
List<int> _placedGroup(
  AiNativeDrawing drawing,
  AiNativeGroup group,
  _NativeArtworkState source,
  _NativeArtworkState incoming,
  _NativeArtworkState outgoing, {
  required int maxBytes,
  List<AiSourceEdit> sourceEdits = const [],
}) => _placedNativeArtwork(
  drawing.records.program,
  [(start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)],
  _groupInterval(drawing, group.start, group.end),
  source,
  incoming,
  outgoing,
  maxBytes: maxBytes,
  sourceEdits: sourceEdits,
);

/// Keeps the outgoing effects of a removed group without its objects or counts.
List<int> _removedGroupState(AiNativeDrawing drawing, AiNativeGroup group) => [
  10,
  for (final AiNativeInstruction item in _groupInterval(drawing, group.start, group.end))
    if (_nativeArtworkStateKey(item) != null) ...[...drawing.records.program.bytes.sublist(item.start, item.end), 10],
];

/// Checks topology after the source editor enforces the original byte/token limits.
AiNativeDrawing _groupLifecycleResult(AiNativeDrawing drawing, List<AiSourceEdit> edits, {required int paths, required int groups, int? liveShapes, bool appearanceLeaves = false}) {
  final AiNativeDrawing result = _pathLifecycleResult(drawing, edits, paths, liveShapes: liveShapes, appearanceLeaves: appearanceLeaves);
  if (result.groups.length != groups || result.records.program.layers.length != drawing.records.program.layers.length) {
    throw const FormatException('Group lifecycle edits changed unrelated native topology.');
  }
  return result;
}

/// Counts selected topology without rescanning unrelated groups for each owner.
int _selectedGroupCount(List<AiNativeGroup> groups) {
  final List<AiNativeGroup> pending = [...groups];
  int count = 0;
  while (pending.isNotEmpty) {
    final AiNativeGroup group = pending.removeLast();
    count++;
    pending.addAll(group.children.whereType<AiNativeGroup>());
  }
  return count;
}

/// Duplicates disjoint groups with restored inputs and unchanged outgoing state.
AiNativeDrawing _duplicateNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups, Map<AiNativeItem, List<int>> identifiers) {
  final List<_NativeSubtreeSpan> spans = [for (final AiNativeGroup group in groups) (start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)];
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, spans);
  _ordinaryGroups(drawing, groups, pairs: pairs);
  if (pairs.isNotEmpty || drawing.gradientArtwork.isNotEmpty || drawing.meshArtwork.isNotEmpty) {
    final List<AiSourceEdit> replacements = _subtreeCopyEdits(drawing, groups, spans, pairs, identifiers);
    return _groupLifecycleResult(
      drawing,
      _copiedNativeSubtrees(AiNativeLayers.decode(drawing: drawing), spans, pairs, replacements, groups: true),
      paths: drawing.paths.length + groups.fold(0, (count, group) => count + group.paths.length),
      groups: drawing.groups.length + _selectedGroupCount(groups),
      liveShapes: drawing.liveShapes.length + _subtreeLiveShapeCount(drawing, spans),
    );
  }
  final List<AiSourceEdit> replacements = _objectCopyEdits(drawing, groups, identifiers);
  final Map<int, _NativeArtworkState> states = _groupStates(drawing, groups.expand((group) => [group.start, _ordinaryObject(drawing, group).end]));
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeGroup group in groups) {
    final List<int> bytes = [
      10,
      ..._placedGroup(
        drawing,
        group,
        states[group.start]!,
        states[_ordinaryObject(drawing, group).end]!,
        states[_ordinaryObject(drawing, group).end]!,
        maxBytes: remaining - 1,
        sourceEdits: replacements,
      ),
    ];
    edits.add(AiSourceEdit(start: _ordinaryObject(drawing, group).end, end: _ordinaryObject(drawing, group).end, bytes: bytes));
    remaining -= bytes.length;
  }
  return _groupLifecycleResult(
    drawing,
    edits,
    paths: drawing.paths.length + groups.fold(0, (count, group) => count + group.paths.length),
    groups: drawing.groups.length + _selectedGroupCount(groups),
    liveShapes: drawing.liveShapes.length + _selectedLiveShapeCount(drawing, groups),
  );
}

/// Removes selected subtrees while replaying their persistent assignments.
AiNativeDrawing _removeNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups) {
  final List<_NativeSubtreeSpan> spans = [for (final AiNativeGroup group in groups) (start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)];
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, spans);
  _ordinaryGroups(drawing, groups, pairs: pairs);
  final List<AiSourceEdit> edits;
  if (pairs.isEmpty && drawing.gradientArtwork.isEmpty && drawing.meshArtwork.isEmpty) {
    _ordinaryObjectRemoval(drawing, groups);
    edits = [for (final AiNativeGroup group in groups) AiSourceEdit(start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end, bytes: _removedGroupState(drawing, group))];
  } else {
    edits = _removedNativeSubtrees(AiNativeLayers.decode(drawing: drawing), spans, pairs, groups: true);
  }
  return _groupLifecycleResult(
    drawing,
    edits,
    paths: drawing.paths.length - groups.fold(0, (count, group) => count + group.paths.length),
    groups: drawing.groups.length - _selectedGroupCount(groups),
    liveShapes: drawing.liveShapes.length - _subtreeLiveShapeCount(drawing, spans),
  );
}

/// Moves group subtrees between sibling slots with per-slot state restoration.
AiNativeDrawing _reorderNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups) {
  final List<_NativeSubtreeSpan> spans = [for (final AiNativeGroup group in groups) (start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)];
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, spans);
  final AiNativeStructure ownership = _ordinaryGroups(drawing, groups, pairs: pairs);
  final List<AiNativeGroup> slots = [...groups]..sort((a, b) => a.start.compareTo(b.start));
  final int? parent = ownership.nodeFor(slots.first).parentIndex;
  if (slots.any((group) => ownership.nodeFor(group).parentIndex != parent)) {
    throw ArgumentError('Reordering requires groups with one immediate native owner.');
  }
  if (slots.indexed.every((entry) => identical(entry.$2, groups[entry.$1]))) {
    return drawing;
  }
  if (pairs.isNotEmpty || drawing.gradientArtwork.isNotEmpty || drawing.meshArtwork.isNotEmpty) {
    return _groupLifecycleResult(
      drawing,
      _reorderedNativeSubtrees(AiNativeLayers.decode(drawing: drawing), spans, pairs, groups: true),
      paths: drawing.paths.length,
      groups: drawing.groups.length,
    );
  }
  _groupInterval(drawing, _ordinaryObject(drawing, slots.first).start, _ordinaryObject(drawing, slots.last).end);
  final Map<int, _NativeArtworkState> states = _groupStates(drawing, groups.expand((group) => [group.start, _ordinaryObject(drawing, group).end]));
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final (int, AiNativeGroup) entry in slots.indexed) {
    final AiNativeGroup source = groups[entry.$1];
    final AiNativeGroup slot = entry.$2;
    if (!identical(slot, source)) {
      final List<int> bytes = _placedGroup(drawing, source, states[source.start]!, states[slot.start]!, states[_ordinaryObject(drawing, slot).end]!, maxBytes: remaining);
      edits.add(AiSourceEdit(start: _ordinaryObject(drawing, slot).start, end: _ordinaryObject(drawing, slot).end, bytes: bytes));
      remaining -= bytes.length;
    }
  }
  return _groupLifecycleResult(
    drawing,
    edits,
    paths: drawing.paths.length,
    groups: drawing.groups.length,
  );
}

/// Relocates a group while retaining the state effects at its original position.
AiNativeDrawing _moveNativeGroup(AiNativeDrawing drawing, AiNativeGroup group, AiNativeGroup after, bool inheritParentFlags) {
  final List<_NativeSubtreeSpan> spans = [
    for (final AiNativeGroup owner in [group, after]) (start: _ordinaryObject(drawing, owner).start, end: _ordinaryObject(drawing, owner).end),
  ];
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, spans);
  final AiNativeStructure ownership = _ordinaryGroups(drawing, [group, after], pairs: pairs);
  if (pairs.isNotEmpty || drawing.gradientArtwork.isNotEmpty || drawing.meshArtwork.isNotEmpty) {
    return _moveNativeGroupSubtree(drawing, group, _ordinaryObject(drawing, after).end, ownership.parentOf(ownership.nodeFor(after)), inheritParentFlags);
  }
  final Map<int, _NativeArtworkState> states = _artworkMovementStates(
    drawing,
    ownership,
    group,
    position: _ordinaryObject(drawing, after).end,
    parent: ownership.parentOf(ownership.nodeFor(after)),
    inheritParentFlags: inheritParentFlags,
  );
  return _relocateNativeGroup(drawing, group, states, _ordinaryObject(drawing, after).end);
}

/// Appends an ordinary group as the last direct artwork of an owned layer.
AiNativeDrawing _moveNativeGroupToLayer(AiNativeDrawing drawing, AiNativeGroup group, AiLayer layer, bool inheritParentFlags) {
  _artworkLayerDestination(drawing, layer);
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, [(start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)]);
  final AiNativeStructure ownership = _ordinaryGroups(drawing, [group], pairs: pairs);
  final int position = layer.end.start;
  if (pairs.isNotEmpty || drawing.gradientArtwork.isNotEmpty || drawing.meshArtwork.isNotEmpty) {
    return _moveNativeGroupSubtree(drawing, group, position, ownership.nodeFor(layer), inheritParentFlags);
  }
  final Map<int, _NativeArtworkState> states = _artworkMovementStates(
    drawing,
    ownership,
    group,
    position: position,
    parent: ownership.nodeFor(layer),
    inheritParentFlags: inheritParentFlags,
  );
  return _relocateNativeGroup(drawing, group, states, position);
}

/// Appends a whole ordinary parent without separating its complete CC descendants.
AiNativeDrawing _moveNativeGroupToGroup(AiNativeDrawing drawing, AiNativeGroup group, AiNativeGroup parent, bool inheritParentFlags) {
  final AiNativeStructureNode target = drawing._objects.structure.nodeFor(parent);
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, [(start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end)]);
  _ordinaryGroups(drawing, [group], pairs: pairs);
  return _moveNativeGroupSubtree(drawing, group, parent.closing.start, target, inheritParentFlags);
}

/// Retains a complete group at its destination and persistent effects at its origin.
AiNativeDrawing _moveNativeGroupSubtree(AiNativeDrawing drawing, AiNativeGroup group, int position, AiNativeStructureNode? parent, bool inheritParentFlags) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final _NativeSubtreeSpan span = (start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end);
  final List<_NativeShapeBundle> pairs = _subtreeShapeBundles(drawing, [span]);
  return _groupLifecycleResult(
    drawing,
    _relocatedNativeSubtree(layers, layers.structure.nodeFor(group), span, pairs, position, parent, inheritParentFlags, groups: true),
    paths: drawing.paths.length,
    groups: drawing.groups.length,
  );
}

/// Commits a qualified group relocation and retains old persistent assignments.
AiNativeDrawing _relocateNativeGroup(AiNativeDrawing drawing, AiNativeGroup group, Map<int, _NativeArtworkState> states, int position) {
  final List<int> retained = _removedGroupState(drawing, group);
  final List<int> moved = _placedGroup(drawing, group, states[group.start]!, states[position]!, states[position]!, maxBytes: drawing.records.program.limits.maxDecodedBytes - retained.length - 1);
  return _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: _ordinaryObject(drawing, group).start, end: _ordinaryObject(drawing, group).end, bytes: retained),
      AiSourceEdit(start: position, end: position, bytes: [10, ...moved]),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length,
  );
}
