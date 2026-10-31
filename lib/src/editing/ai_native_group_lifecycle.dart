part of 'package:aikit/src/model/ai_native_records.dart';

/// Declarative attributes whose values can be replayed without rendering.
const Set<String> _groupStateKeys = {'fill', 'stroke', 'A', 'Xw', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'w', 'M', 'd'};

/// Validates a source assignment and identifies its overwritten state component.
String? _groupStateKey(AiNativeInstruction item) {
  final String operator = item.operator;
  final List<double>? numbers = item.numbers;

  /// Checks exact numeric arity, retaining no assumed default state.
  bool arity(int length) => numbers != null && numbers.length == length;

  /// Distinguishes malformed known operands from unqualified state operators.
  void require(bool valid) {
    if (!valid || item.operands.any((operand) => operand.number != null && operand.number!.abs() > 9007199254740991)) {
      throw FormatException('Invalid ordinary-group state operands for $operator.');
    }
  }

  switch (operator) {
    case 'g' || 'G' || 'k' || 'K' || 'Xa' || 'XA':
      require(
        (operator == 'g' || operator == 'G'
                ? arity(1)
                : operator == 'k' || operator == 'K'
                ? arity(4)
                : arity(3) || arity(7)) &&
            numbers!.every(_gradientUnit),
      );
      return const {'g', 'k', 'Xa'}.contains(operator) ? 'fill' : 'stroke';
    case 'A' || 'Xw' || 'O' || 'R' || 'XR' || 'D' || 'Ap':
      require(arity(1) && const {0, 1}.contains(numbers!.single));
    case 'J' || 'j':
      require(arity(1) && const {0, 1, 2}.contains(numbers!.single));
    case 'w' || 'M':
      require(arity(1) && numbers!.single >= (operator == 'w' ? 0 : 1));
    case 'd':
      final List<AiToken> operands = item.operands;
      require(operands.length >= 3 && operands.first.kind == .arrayStart && operands[operands.length - 2].kind == .arrayEnd && operands.last.number != null);
      final List<AiToken> dashes = operands.sublist(1, operands.length - 2);
      require(dashes.every((dash) => dash.number != null && dash.number! >= 0) && (dashes.isEmpty || dashes.any((dash) => dash.number! > 0)));
    default:
      return null;
  }
  return operator;
}

/// Qualifies complete state/geometry intervals without evaluating opaque records.
List<AiNativeInstruction> _groupInterval(AiNativeDrawing drawing, int start, int end, {bool nested = true}) {
  final List<AiNativeInstruction> commands = [];
  for (final AiNativeItem item in _pathInterval(drawing.items, start, end, (item) => item.start)) {
    if (item is! AiNativeInstruction || item.isPrivate || item.end > end) {
      throw UnsupportedError('Ordinary group edits require isolated non-private instructions.');
    }
    if (const {'u', 'U'}.contains(item.operator)) {
      if (!nested || item.operands.isNotEmpty) {
        throw UnsupportedError('The selected interval has an unqualified group boundary.');
      }
    } else if (!_nativeGeometry.contains(item.operator) && !_nativePaint.contains(item.operator) && item.operator != 'As' && _groupStateKey(item) == null) {
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
void _ordinaryGroupPrefix(AiNativeDrawing drawing, AiNativeGroup group, List<AiLiveShape> bound, Set<int> layerHeaders) {
  final List<AiNativeItem> items = drawing.items;
  final int preceding = _pathOffset(bound, group.start + 1, (shape) => shape.end);
  final int resolved = preceding == 0 ? drawing.records.program.bodyStart : bound[preceding - 1].end;
  int boundary = resolved;
  for (int index = _pathOffset(items, group.start, (item) => item.start) - 1; index >= 0 && items[index].end > resolved; index--) {
    final AiNativeItem item = items[index];
    if (item is! AiNativeInstruction || item.isPrivate) {
      throw UnsupportedError('The selected group has an unresolved native prefix.');
    }
    if (_nativePaint.contains(item.operator) || const {'u', 'U', 'Lb', 'LB'}.contains(item.operator)) {
      boundary = item.end;
      break;
    }
    if (_groupStateKey(item) == null && !(const {'Ln', 'AE'}.contains(item.operator) && layerHeaders.contains(item.token.start))) {
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
  int end = drawing.records.program.bodyEnd;
  for (int index = _pathOffset(drawing.items, group.end, (item) => item.start); index < drawing.items.length; index++) {
    final AiNativeItem item = drawing.items[index];
    if (item is AiNativeInstruction && const {'m', 'u', 'U', 'Lb', 'LB'}.contains(item.operator)) {
      end = item.start;
      break;
    }
  }
  _ordinaryGroupMetadata(drawing, group.end, end);
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
  final AiNativeStructure ownership = AiNativeStructure.decode(drawing: drawing);
  final List<AiLiveShape> shapes = [...drawing.liveShapes]..sort((a, b) => a.start.compareTo(b.start));
  final List<AiLiveShape> bound = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((a, b) => a.end.compareTo(b.end));
  final Set<int> layerHeaders = {
    for (final AiLayer layer in drawing.records.program.layers) ...layer.header.map((item) => item.token.start),
    for (final AiLayer layer in drawing.records.program.layers)
      if (layer.naming != null) layer.naming!.token.start,
  };
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
        _ordinaryPathFollowing(drawing.items, node.end);
        if (node.source case final AiNativeGroup owner) {
          _ordinaryGroupPrefix(drawing, owner, bound, layerHeaders);
          _ordinaryGroupPostfix(drawing, owner);
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

/// Captures known source assignments at requested boundaries in one ordered pass.
Map<int, Map<String, AiNativeInstruction>> _groupStates(AiNativeDrawing drawing, Iterable<int> boundaries) {
  final List<int> positions = boundaries.toSet().toList()..sort();
  final Map<int, Map<String, AiNativeInstruction>> result = {};
  final Map<String, AiNativeInstruction> state = {};
  int index = 0;
  for (final int position in positions) {
    while (index < drawing.items.length && drawing.items[index].end <= position) {
      final AiNativeItem item = drawing.items[index++];
      if (item is! AiNativeInstruction || item.isPrivate) {
        state.clear();
        continue;
      }
      final String? key;
      try {
        key = _groupStateKey(item);
      } on FormatException {
        state.clear();
        continue;
      }
      if (key != null) {
        state[key] = item;
      } else if (!_nativeGeometry.contains(item.operator) && !_nativePaint.contains(item.operator) && !const {'u', 'U', 'As'}.contains(item.operator)) {
        // A layer, clip, private appearance or unknown operator invalidates our
        // knowledge; later explicit assignments can reestablish individual keys.
        state.clear();
      }
    }
    result[position] = Map.of(state);
  }
  return result;
}

/// Compares declarative values without equating unrelated color representations.
bool _sameGroupState(AiNativeInstruction? first, AiNativeInstruction? second) =>
    identical(first, second) ||
    first != null &&
        second != null &&
        first.operator == second.operator &&
        first.operands.length == second.operands.length &&
        first.operands.indexed.every((entry) => entry.$2.number != null ? entry.$2.number == second.operands[entry.$1].number : entry.$2.lexeme == second.operands[entry.$1].lexeme);

/// Replays owned assignments around a group, preserving both boundary states.
List<int> _placedGroup(
  AiNativeDrawing drawing,
  AiNativeGroup group,
  Map<String, AiNativeInstruction> source,
  Map<String, AiNativeInstruction> incoming,
  Map<String, AiNativeInstruction> outgoing, {
  required int maxBytes,
}) {
  final List<AiNativeInstruction> commands = _groupInterval(drawing, group.start, group.end);
  final Map<String, AiNativeInstruction> writes = {};
  final Set<String> required = {};
  for (final AiNativeInstruction command in commands) {
    final String? key = _groupStateKey(command);
    if (key != null) {
      writes[key] = command;
    } else if (command.operator == 'u' || command.operator == 'm') {
      required.addAll((command.operator == 'u' ? const {'A', 'Xw'} : _groupStateKeys).where((key) => !writes.containsKey(key)));
    }
  }
  final Map<String, AiNativeInstruction> actual = Map.of(incoming);
  final List<AiNativeInstruction> prefix = [];
  for (final String key in required) {
    if (!_sameGroupState(source[key], incoming[key])) {
      final AiNativeInstruction? value = source[key];
      if (value == null) {
        throw UnsupportedError('The moved group requires an unknown inherited $key value.');
      }
      prefix.add(value);
      actual[key] = value;
    }
  }
  actual.addAll(writes);
  final List<AiNativeInstruction> suffix = [];
  for (final String key in {...actual.keys, ...outgoing.keys}) {
    if (!_sameGroupState(actual[key], outgoing[key])) {
      final AiNativeInstruction? value = outgoing[key];
      if (value == null) {
        throw UnsupportedError('The moved group cannot restore an unknown outgoing $key value.');
      }
      suffix.add(value);
    }
  }
  final Uint8List bytes = drawing.records.program.bytes;
  final BytesBuilder result = BytesBuilder(copy: false);

  /// Bounds replayed source spans before allocating repeated paint operands.
  void append(int start, int end) {
    if (result.length + end - start + 1 > maxBytes) {
      throw const AiLimitException(message: 'Group lifecycle output exceeds the native byte limit.');
    }
    result.add(Uint8List.sublistView(bytes, start, end));
    result.addByte(10);
  }

  for (final AiNativeInstruction value in prefix) {
    append(value.start, value.end);
  }
  append(group.start, group.end);
  for (final AiNativeInstruction value in suffix) {
    append(value.start, value.end);
  }
  return result.takeBytes();
}

/// Keeps the outgoing effects of a removed group without its objects or counts.
List<int> _removedGroupState(AiNativeDrawing drawing, AiNativeGroup group) => [
  10,
  for (final AiNativeInstruction item in _groupInterval(drawing, group.start, group.end))
    if (_groupStateKey(item) != null) ...[...drawing.records.program.bytes.sublist(item.start, item.end), 10],
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
  _groupInterval(drawing, start, ordered.last.end, nested: false);
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: start, end: start, bytes: latin1.encode('\nu\n')),
      AiSourceEdit(start: ordered.last.end, end: ordered.last.end, bytes: latin1.encode('\nU\n')),
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
  return _groupLifecycleResult(
    drawing,
    [
      for (final AiNativeGroup group in groups) ...[
        AiSourceEdit(start: group.opening.start, end: group.opening.end, bytes: [32]),
        AiSourceEdit(start: group.closing.start, end: group.closing.end, bytes: [32]),
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
AiNativeDrawing _duplicateNativeGroups(AiNativeDrawing drawing, List<AiNativeGroup> groups) {
  _ordinaryGroups(drawing, groups);
  final Map<int, Map<String, AiNativeInstruction>> states = _groupStates(drawing, groups.expand((group) => [group.start, group.end]));
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeGroup group in groups) {
    final List<int> bytes = [10, ..._placedGroup(drawing, group, states[group.start]!, states[group.end]!, states[group.end]!, maxBytes: remaining - 1)];
    edits.add(AiSourceEdit(start: group.end, end: group.end, bytes: bytes));
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
  return _groupLifecycleResult(
    drawing,
    [for (final AiNativeGroup group in groups) AiSourceEdit(start: group.start, end: group.end, bytes: _removedGroupState(drawing, group))],
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
  _groupInterval(drawing, slots.first.start, slots.last.end);
  final Map<int, Map<String, AiNativeInstruction>> states = _groupStates(drawing, groups.expand((group) => [group.start, group.end]));
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final (int, AiNativeGroup) entry in slots.indexed) {
    final AiNativeGroup source = groups[entry.$1];
    final AiNativeGroup slot = entry.$2;
    if (!identical(slot, source)) {
      final List<int> bytes = _placedGroup(drawing, source, states[source.start]!, states[slot.start]!, states[slot.end]!, maxBytes: remaining);
      edits.add(AiSourceEdit(start: slot.start, end: slot.end, bytes: bytes));
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

/// Resolves a group's containing layer without assigning cross-snapshot identity.
AiNativeStructureNode? _groupLayer(AiNativeStructure ownership, AiNativeGroup group) {
  AiNativeStructureNode? parent = ownership.parentOf(ownership.nodeFor(group));
  while (parent != null && parent.kind != .layer) {
    parent = ownership.parentOf(parent);
  }
  return parent;
}

/// Relocates a group while retaining the state effects at its original position.
AiNativeDrawing _moveNativeGroup(AiNativeDrawing drawing, AiNativeGroup group, AiNativeGroup after) {
  final AiNativeStructure ownership = _ordinaryGroups(drawing, [group, after]);
  if (!identical(_groupLayer(ownership, group), _groupLayer(ownership, after))) {
    throw UnsupportedError('Moving native groups across layers requires an explicit layer-state contract.');
  }
  _groupInterval(drawing, min(group.start, after.start), max(group.end, after.end));
  final Map<int, Map<String, AiNativeInstruction>> states = _groupStates(drawing, [group.start, after.end]);
  final List<int> retained = _removedGroupState(drawing, group);
  final List<int> moved = _placedGroup(drawing, group, states[group.start]!, states[after.end]!, states[after.end]!, maxBytes: drawing.records.program.limits.maxDecodedBytes - retained.length - 1);
  return _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: group.start, end: group.end, bytes: retained),
      AiSourceEdit(start: after.end, end: after.end, bytes: [10, ...moved]),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length,
  );
}
