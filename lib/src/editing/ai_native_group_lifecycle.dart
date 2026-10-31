part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies complete state/geometry intervals without evaluating opaque records.
List<AiNativeInstruction> _groupInterval(AiNativeDrawing drawing, int start, int end, {bool nested = true}) {
  final List<AiNativeInstruction> commands = [];
  for (final AiNativeItem item in _pathInterval(drawing.items, start, end, (item) => item.start)) {
    if (_ordinaryObjectMetadata(drawing, item) && item.end <= end) {
      continue;
    }
    if (item is! AiNativeInstruction || item.isPrivate || item.end > end) {
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
  if (_pathInterval(drawing.records._projection.tokens, start, end, (token) => token.start).any(
    (token) => token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')),
  )) {
    throw UnsupportedError('Ordinary group edits cannot reinterpret native metadata or opaque data.');
  }
  return commands;
}

/// Refuses consumed expansion flags and unresolved prefixes before a group.
void _ordinaryGroupPrefix(AiNativeDrawing drawing, AiNativeGroup group, List<AiLiveShape> bound, Map<int, AiNativeLayer> layerHeaders) {
  final List<AiNativeItem> items = drawing.items;
  final int preceding = _pathOffset(bound, group.start + 1, (shape) => shape.end);
  final int resolved = preceding == 0 ? drawing.records.program.bodyStart : bound[preceding - 1].end;
  int boundary = resolved;
  for (int index = _pathOffset(items, group.start, (item) => item.start) - 1; index >= 0 && items[index].end > resolved; index--) {
    final AiNativeItem item = items[index];
    if (_ordinaryObjectMetadata(drawing, item)) {
      boundary = item.end;
      break;
    }
    if (layerHeaders[item.start] case final AiNativeLayer owner when owner.bindingIssue == null && item.start != owner.source.begin.start && item.start != owner.source.end.start) {
      continue;
    }
    if (item is! AiNativeInstruction || item.isPrivate) {
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
  _ordinaryGroupMetadata(drawing, boundary, group.start);
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
  int end = drawing.records.program.bodyEnd;
  for (int index = _pathOffset(drawing.items, start, (item) => item.start); index < drawing.items.length; index++) {
    final AiNativeItem item = drawing.items[index];
    if (item is AiNativeInstruction && const {'m', 'u', 'U', 'Lb', 'LB'}.contains(item.operator)) {
      end = item.start;
      break;
    }
  }
  _ordinaryGroupMetadata(drawing, start, end);
}

/// Validates disjoint ordinary owners, attached records and every contained path.
AiNativeStructure _ordinaryGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups) {
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
  final List<AiLiveShape> shapes = [...drawing.liveShapes]..sort((a, b) => a.start.compareTo(b.start));
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
  final List<AiNativePath> paths = [for (final AiNativeGroup group in groups) ...group.paths];
  final Map<AiNativePath, AiNativeInstruction?> counts = paths.isEmpty ? {} : _ordinaryPathCounts(drawing, paths, ownership: ownership);
  final Set<AiNativeInstruction> pathCommands = {
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
          _ordinaryGroupPrefix(drawing, owner, bound, layerHeaders);
          _ordinaryGroupPostfix(drawing, owner);
        } else {
          _ordinaryPathFollowing(drawing.items, node.end);
        }
      }
      node = ownership.parentOf(node);
    }
    for (final AiNativeInstruction command in _groupInterval(drawing, group.start, group.end)) {
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
  [(start: group.start, end: _ordinaryObject(drawing, group).end)],
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
AiNativeDrawing _groupLifecycleResult(AiNativeDrawing drawing, List<AiSourceEdit> edits, {required int paths, required int groups}) {
  final AiNativeDrawing result = _pathLifecycleResult(drawing, edits, paths);
  if (result.groups.length != groups || result.records.program.layers.length != drawing.records.program.layers.length) {
    throw const FormatException('Group lifecycle edits changed unrelated native topology.');
  }
  return result;
}

/// Adds only boundaries around consecutive siblings and their consumed counts.
AiNativeDrawing _groupNativePaths(AiNativeDrawing drawing, List<AiNativePath> paths) {
  final AiNativeStructure ownership = AiNativeStructure.decode(drawing: drawing);
  final Map<AiNativePath, AiNativeInstruction?> counts = _ordinaryPathCounts(drawing, paths, ownership: ownership);
  final List<AiNativePath> ordered = [...paths]..sort((a, b) => a.start.compareTo(b.start));
  final int? parent = ownership.nodeFor(ordered.first).parentIndex;
  if (ordered.any((path) => ownership.nodeFor(path).parentIndex != parent) ||
      drawing.paths.where((path) => path.start >= ordered.first.start && path.end <= ordered.last.end).length != ordered.length) {
    throw ArgumentError('Grouping requires consecutive paths with one immediate native owner.');
  }
  final int start = counts[ordered.first]?.start ?? ordered.first.start;
  final int end = _ordinaryObject(drawing, ordered.last).end;
  _groupInterval(drawing, start, end, nested: false);
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: start, end: start, bytes: latin1.encode('\nu\n')),
      AiSourceEdit(start: end, end: end, bytes: latin1.encode('\nU\n')),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length + 1,
  );
  _ordinaryGroups(result, [result.groups.singleWhere((group) => group.start == start + 1)]);
  return result;
}

/// Dissolves disjoint ordinary boundaries without removing their artwork.
AiNativeDrawing _ungroupNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups) {
  _ordinaryGroups(drawing, groups);
  if (groups.any((group) => _ordinaryObject(drawing, group).dictionary?.entries.isNotEmpty ?? false)) {
    throw UnsupportedError('Dissolving a group cannot discard its native object metadata.');
  }
  return _groupLifecycleResult(
    drawing,
    [
      for (final AiNativeGroup group in groups) ...[
        AiSourceEdit(start: group.opening.start, end: group.opening.end, bytes: [32]),
        AiSourceEdit(start: group.closing.start, end: _ordinaryObject(drawing, group).end, bytes: [32]),
      ],
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length - groups.length,
  );
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
  _ordinaryGroups(drawing, groups);
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
  );
}

/// Removes selected subtrees while replaying their persistent assignments.
AiNativeDrawing _removeNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups) {
  _ordinaryGroups(drawing, groups);
  _ordinaryObjectRemoval(drawing, groups);
  return _groupLifecycleResult(
    drawing,
    [for (final AiNativeGroup group in groups) AiSourceEdit(start: group.start, end: _ordinaryObject(drawing, group).end, bytes: _removedGroupState(drawing, group))],
    paths: drawing.paths.length - groups.fold(0, (count, group) => count + group.paths.length),
    groups: drawing.groups.length - _selectedGroupCount(groups),
  );
}

/// Moves group subtrees between sibling slots with per-slot state restoration.
AiNativeDrawing _reorderNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups) {
  final AiNativeStructure ownership = _ordinaryGroups(drawing, groups);
  final List<AiNativeGroup> slots = [...groups]..sort((a, b) => a.start.compareTo(b.start));
  final int? parent = ownership.nodeFor(slots.first).parentIndex;
  if (slots.any((group) => ownership.nodeFor(group).parentIndex != parent)) {
    throw ArgumentError('Reordering requires groups with one immediate native owner.');
  }
  if (slots.indexed.every((entry) => identical(entry.$2, groups[entry.$1]))) {
    return drawing;
  }
  _groupInterval(drawing, slots.first.start, _ordinaryObject(drawing, slots.last).end);
  final Map<int, _NativeArtworkState> states = _groupStates(drawing, groups.expand((group) => [group.start, _ordinaryObject(drawing, group).end]));
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final (int, AiNativeGroup) entry in slots.indexed) {
    final AiNativeGroup source = groups[entry.$1];
    final AiNativeGroup slot = entry.$2;
    if (!identical(slot, source)) {
      final List<int> bytes = _placedGroup(drawing, source, states[source.start]!, states[slot.start]!, states[_ordinaryObject(drawing, slot).end]!, maxBytes: remaining);
      edits.add(AiSourceEdit(start: slot.start, end: _ordinaryObject(drawing, slot).end, bytes: bytes));
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
  final AiNativeStructure ownership = _ordinaryGroups(drawing, [group, after]);
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
  final AiNativeStructure ownership = _ordinaryGroups(drawing, [group]);
  final int position = layer.end.start;
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

/// Commits a qualified group relocation and retains old persistent assignments.
AiNativeDrawing _relocateNativeGroup(AiNativeDrawing drawing, AiNativeGroup group, Map<int, _NativeArtworkState> states, int position) {
  final List<int> retained = _removedGroupState(drawing, group);
  final List<int> moved = _placedGroup(drawing, group, states[group.start]!, states[position]!, states[position]!, maxBytes: drawing.records.program.limits.maxDecodedBytes - retained.length - 1);
  return _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: group.start, end: _ordinaryObject(drawing, group).end, bytes: retained),
      AiSourceEdit(start: position, end: position, bytes: [10, ...moved]),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length,
  );
}
