part of 'package:aikit/src/model/ai_native_records.dart';

/// Validates one batch before any source offset or object identity changes.
Map<AiNativePath, AiNativeInstruction?> _ordinaryPathCounts(AiNativeDrawing drawing, List<AiNativePath> paths, {AiNativeStructure? ownership}) {
  final Set<AiNativePath> owned = drawing.paths.toSet();
  if (paths.isEmpty || paths.toSet().length != paths.length || paths.any((path) => !owned.contains(path))) {
    throw ArgumentError('Path lifecycle operations require distinct owned source paths.');
  }
  final AiNativeStructure structure = ownership ?? AiNativeStructure.decode(drawing: drawing);
  final Map<AiNativePath, AiNativeInstruction?> result = {};
  final List<AiNativeItem> items = drawing.items;
  final List<AiToken> tokens = drawing.records._projection.tokens;
  final Map<int, AiPath> plainPaths = {for (final AiPath path in drawing.records.program.paths) path.geometry.first.start: path};
  final Set<AiNativePath> dependent = {for (final AiNativeGradient gradient in drawing.gradients) ...gradient.paths};
  final List<AiLiveShape> shapes = [...drawing.liveShapes]..sort((a, b) => a.start.compareTo(b.start));
  final List<AiLiveShape> bound = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((a, b) => a.end.compareTo(b.end));
  final Map<AiNativePath, int> previousEnds = {};
  final Set<AiNativeStructureNode> checkedParents = {};
  int previousEnd = drawing.records.program.bodyStart;
  int shapeIndex = 0;
  int shapeEnd = 0;
  for (final AiNativePath path in drawing.paths) {
    previousEnds[path] = previousEnd;
    previousEnd = path.end;
    while (shapeIndex < shapes.length && shapes[shapeIndex].start < path.end) {
      shapeEnd = max(shapeEnd, shapes[shapeIndex++].end);
    }
    if (shapeEnd > path.start) {
      dependent.add(path);
    }
  }
  for (final AiNativePath path in paths) {
    if (path.isPrivate || dependent.contains(path)) {
      throw UnsupportedError('Path lifecycle operations require independent authoring geometry.');
    }
    final AiNativeStructureNode node = structure.nodeFor(path);
    if (node.versions.isNotEmpty) {
      throw UnsupportedError('A version-dependent path requires synchronized alternative objects.');
    }
    AiNativeStructureNode? parent = structure.parentOf(node);
    while (parent != null) {
      if (parent.kind != .layer && parent.kind != .group) {
        throw UnsupportedError('The path belongs to a compound, clip or unresolved native owner.');
      }
      if (!checkedParents.add(parent)) {
        parent = structure.parentOf(parent);
        continue;
      }
      if (parent.source case final AiNativeGroup group) {
        if (group.opening.isPrivate) {
          throw UnsupportedError('A private group cannot supply independent authoring paths.');
        }
        _ordinaryPathFollowing(items, group.end);
      } else if (parent.source case final AiLayer layer) {
        _ordinaryPathFollowing(items, layer.end.end);
      }
      parent = structure.parentOf(parent);
    }
    _ordinaryPathFollowing(items, path.end);
    final Set<AiNativeInstruction> geometry = {...path.geometry, path.paint};
    if (_pathInterval(items, path.start, path.end, (item) => item.start).any((item) => !geometry.contains(item))) {
      throw UnsupportedError('The selected path contains dependent or interleaved native state.');
    }
    if (_pathInterval(tokens, path.start, path.end, (token) => token.start).any(
      (token) => token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%%') || token.lexeme.startsWith('%AI')),
    )) {
      throw UnsupportedError('The selected path contains unresolved metadata or opaque data.');
    }
    final AiPath? plain = plainPaths[path.start];
    if (plain == null || plain.paint.end != path.end) {
      throw UnsupportedError('The selected path has unresolved appearance dependencies.');
    }
    if (plain.hasDependentAppearance) {
      final int index = _pathOffset(bound, path.start + 1, (shape) => shape.end);
      final AiLiveShape? preceding = index == 0 ? null : bound[index - 1];
      if (preceding == null || _pathInterval(items, preceding.end, path.start, (item) => item.start).any((item) => item is! AiNativeInstruction || !_ordinaryPathSuccessors.contains(item.operator))) {
        throw UnsupportedError('The selected path has unresolved appearance dependencies.');
      }
      // Mode-one XW ends the preceding bound shape. Its resolved postfix style
      // does not turn a later ordinary path into a private printing expansion.
    }
    final int boundary = previousEnds[path]!;
    if (_pathInterval(tokens, boundary, path.start, (token) => token.start).any((token) => token.kind == .comment && token.lexeme.startsWith('%AI3_Note:'))) {
      throw UnsupportedError('A noted path requires explicit ownership of its native annotation.');
    }
    AiNativeInstruction? count;
    for (final AiNativeItem item in _pathInterval(items, boundary, path.end, (item) => item.start)) {
      if (item is! AiNativeInstruction) {
        if (count != null) {
          throw UnsupportedError('A native point count crosses an unresolved record.');
        }
        continue;
      }
      if (item.operator == 'As') {
        if (count != null || item.start >= path.start) {
          throw UnsupportedError('A native point count must precede exactly one selected path.');
        }
        count = item;
      } else if (count != null && const {'u', 'U', '*u', '*U', 'q', 'Q', 'Lb', 'LB'}.contains(item.operator)) {
        throw UnsupportedError('A native point count crosses an object boundary.');
      }
    }
    if (count != null) {
      final List<double> first = path.geometry.first.numbers!;
      final List<double> last = path.geometry.last.numbers!;
      if (count.isPrivate ||
          count.numbers?.length != 1 ||
          count.numbers!.single != path.geometry.length - (path.closed ? 1 : 0) ||
          path.geometry.skip(1).any((command) => command.operator == 'm') ||
          path.closed && (path.geometry.length == 1 || first[0] != last[last.length - 2] || first[1] != last.last)) {
        throw UnsupportedError('The selected path has an inconsistent native point count.');
      }
    }
    result[path] = count;
  }
  return result;
}

/// Finds a source boundary without rescanning the complete program per object.
int _pathOffset<T>(List<T> values, int offset, int Function(T) position) {
  int low = 0;
  int high = values.length;
  while (low < high) {
    final int middle = (low + high) ~/ 2;
    if (position(values[middle]) < offset) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// Visits a disjoint native source interval under the owning parser's budget.
Iterable<T> _pathInterval<T>(List<T> values, int start, int end, int Function(T) position) sync* {
  for (int index = _pathOffset(values, start, position); index < values.length && position(values[index]) < end; index++) {
    yield values[index];
  }
}

/// Refuses postfix object metadata and unqualified parent-appearance bindings.
void _ordinaryPathFollowing(List<AiNativeItem> items, int end) {
  for (int index = _pathOffset(items, end, (item) => item.start); index < items.length; index++) {
    final AiNativeItem next = items[index];
    if (next is! AiNativeInstruction || !_ordinaryPathSuccessors.contains(next.operator)) {
      throw UnsupportedError('The selected object has unresolved trailing metadata or references.');
    }
    if (const {'m', 'u', 'U', 'Lb', 'LB'}.contains(next.operator)) {
      return;
    }
  }
}

/// State assignments and structural boundaries allowed before following art.
const Set<String> _ordinaryPathSuccessors = {
  'm',
  'u',
  'U',
  'Lb',
  'LB',
  'Ln',
  'A',
  'Xw',
  'AE',
  'Ae',
  'Ap',
  'As',
  'g',
  'G',
  'k',
  'K',
  'Xa',
  'XA',
  'x',
  'X',
  'Xx',
  'XX',
  'Xy',
  'O',
  'R',
  'D',
  'J',
  'j',
  'w',
  'M',
  'd',
  'XR',
};

/// Reopens a complete atomic edit and checks the expected body-path count.
AiNativeDrawing _pathLifecycleResult(AiNativeDrawing drawing, List<AiSourceEdit> edits, int count) {
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: drawing.records.program, edits: edits),
    ),
  );
  if (result.paths.length != count || result.liveShapes.length != drawing.liveShapes.length || result.liveShapes.indexed.any((entry) => entry.$2.isBound != drawing.liveShapes[entry.$1].isBound)) {
    throw const FormatException('Path lifecycle edits changed unrelated native ownership.');
  }
  return result;
}

/// Copies source geometry while leaving persistent attributes at their positions.
AiNativeDrawing _duplicateNativePaths(AiNativeDrawing drawing, List<AiNativePath> paths) {
  final Map<AiNativePath, AiNativeInstruction?> counts = _ordinaryPathCounts(drawing, paths);
  final AiProgram program = drawing.records.program;
  final List<AiSourceEdit> edits = [];
  for (final AiNativePath path in paths) {
    final AiNativeInstruction? count = counts[path];
    edits.add(
      AiSourceEdit(
        start: path.end,
        end: path.end,
        bytes: [
          10,
          if (count != null) ...[...program.bytes.sublist(count.start, count.end), 10],
          ...program.bytes.sublist(path.start, path.end),
          10,
        ],
      ),
    );
  }
  return _pathLifecycleResult(drawing, edits, drawing.paths.length + paths.length);
}

/// Deletes only geometry/paint and its optional consumed point-count declaration.
AiNativeDrawing _removeNativePaths(AiNativeDrawing drawing, List<AiNativePath> paths) {
  final Map<AiNativePath, AiNativeInstruction?> counts = _ordinaryPathCounts(drawing, paths);
  return _pathLifecycleResult(drawing, [
    for (final AiNativePath path in paths) ...[
      AiSourceEdit(start: path.start, end: path.end, bytes: [32]),
      if (counts[path] case final AiNativeInstruction count) AiSourceEdit(start: count.start, end: count.end, bytes: [32]),
    ],
  ], drawing.paths.length - paths.length);
}

/// Authors geometry in the anchor's unchanged inherited state and count layout.
AiNativeDrawing _insertNativePaths(AiNativeDrawing drawing, List<AiNativePathInsertion> insertions) {
  final Map<AiNativePath, AiNativeInstruction?> counts = _ordinaryPathCounts(drawing, insertions.map((insertion) => insertion.after).toSet().toList());
  final List<AiSourceEdit> edits = [];
  int encoded = 0;
  for (final AiNativePathInsertion insertion in insertions) {
    final AiNativePath anchor = insertion.after;
    final bool counted = counts[anchor] != null;
    final List<AiPathSegment> segments = [...insertion.segments];
    if (counted && anchor.closed) {
      final List<double> first = segments.first.coordinates;
      final List<double> last = segments.last.coordinates;
      if (segments.length == 1 || first[0] != last[last.length - 2] || first[1] != last.last) {
        segments.add(AiPathSegment(operator: 'L', coordinates: first));
      }
    }
    final StringBuffer output = StringBuffer('\n');
    if (counted) {
      output.writeln('${segments.length - (anchor.closed ? 1 : 0)} As');
    }
    for (final AiPathSegment segment in segments) {
      output.writeln('${segment.coordinates.join(' ')} ${segment.operator}');
      if (output.length + encoded > drawing.records.program.limits.maxDecodedBytes) {
        throw const AiLimitException(message: 'Inserted paths exceed native output limits.');
      }
    }
    output.writeln(anchor.paint.operator);
    final List<int> bytes = latin1.encode(output.toString());
    encoded += bytes.length;
    edits.add(AiSourceEdit(start: anchor.end, end: anchor.end, bytes: bytes));
  }
  edits.addAll(
    AiNativeEditor.includeBoundsEdits(
      program: drawing.records.program,
      bounds: AiBoundingBox(
        left: insertions.map((value) => value.bounds.left).reduce(min),
        bottom: insertions.map((value) => value.bounds.bottom).reduce(min),
        right: insertions.map((value) => value.bounds.right).reduce(max),
        top: insertions.map((value) => value.bounds.top).reduce(max),
      ),
    ),
  );
  return _pathLifecycleResult(drawing, edits, drawing.paths.length + insertions.length);
}

/// Requires a native interval whose paint and object state cannot change.
void _pathMovementInterval(AiNativeDrawing drawing, int start, int end, {required bool groups}) {
  for (final AiNativeItem item in drawing.items.where((item) => item.start >= start && item.end <= end)) {
    if (item is! AiNativeInstruction ||
        item.isPrivate ||
        !_nativeGeometry.contains(item.operator) && !_nativePaint.contains(item.operator) && item.operator != 'As' && !(groups && const {'u', 'U'}.contains(item.operator))) {
      throw UnsupportedError('Moving paths requires an interval without changing native state or opaque dependencies.');
    }
    if (const {'u', 'U'}.contains(item.operator) && item.operands.isNotEmpty) {
      throw const FormatException('Ordinary native group boundaries cannot have operands.');
    }
  }
  if (drawing.records._projection.tokens.any(
    (token) => token.start < end && token.end > start && (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'))),
  )) {
    throw UnsupportedError('Moving paths requires an interval without unresolved metadata.');
  }
}

/// Applies a permutation to source slots while carrying optional count syntax.
AiNativeDrawing _reorderNativePaths(AiNativeDrawing drawing, List<AiNativePath> paths) {
  final AiNativeStructure ownership = AiNativeStructure.decode(drawing: drawing);
  final Map<AiNativePath, AiNativeInstruction?> counts = _ordinaryPathCounts(drawing, paths, ownership: ownership);
  final List<AiNativePath> slots = [...paths]..sort((a, b) => a.start.compareTo(b.start));
  final int? parent = ownership.nodeFor(slots.first).parentIndex;
  if (slots.any((path) => ownership.nodeFor(path).parentIndex != parent)) {
    throw ArgumentError('Reordering requires paths with one immediate native owner.');
  }
  if (slots.indexed.every((entry) => identical(entry.$2, paths[entry.$1]))) {
    return drawing;
  }
  _pathMovementInterval(drawing, slots.first.start, slots.last.end, groups: false);
  final AiProgram program = drawing.records.program;
  final List<AiSourceEdit> edits = [];
  for (final (int, AiNativePath) entry in slots.indexed) {
    final AiNativePath slot = entry.$2;
    final AiNativePath source = paths[entry.$1];
    if (identical(slot, source)) {
      continue;
    }
    final AiNativeInstruction? oldCount = counts[slot];
    final AiNativeInstruction? newCount = counts[source];
    edits.add(
      AiSourceEdit(
        start: slot.start,
        end: slot.end,
        bytes: [
          if (oldCount == null && newCount != null) ...[...program.bytes.sublist(newCount.start, newCount.end), 10],
          ...program.bytes.sublist(source.start, source.end),
        ],
      ),
    );
    if (oldCount != null) {
      edits.add(AiSourceEdit(start: oldCount.start, end: oldCount.end, bytes: newCount == null ? [32] : program.bytes.sublist(newCount.start, newCount.end)));
    }
  }
  return _pathLifecycleResult(drawing, edits, drawing.paths.length);
}

/// Finds the containing layer by immutable source identity, allowing root art.
AiNativeStructureNode? _pathLayer(AiNativeStructure ownership, AiNativePath path) {
  AiNativeStructureNode? parent = ownership.parentOf(ownership.nodeFor(path));
  while (parent != null && parent.kind != .layer) {
    parent = ownership.parentOf(parent);
  }
  return parent;
}

/// Moves geometry across ordinary group boundaries with an unchanged state stream.
AiNativeDrawing _moveNativePath(AiNativeDrawing drawing, AiNativePath path, AiNativePath after) {
  final AiNativeStructure ownership = AiNativeStructure.decode(drawing: drawing);
  final Map<AiNativePath, AiNativeInstruction?> counts = _ordinaryPathCounts(drawing, [path, after], ownership: ownership);
  if (!identical(_pathLayer(ownership, path), _pathLayer(ownership, after))) {
    throw UnsupportedError('Moving paths across native layers requires an explicit state contract.');
  }
  _pathMovementInterval(drawing, min(path.start, after.start), max(path.end, after.end), groups: true);
  final AiProgram program = drawing.records.program;
  final AiNativeInstruction? count = counts[path];
  return _pathLifecycleResult(drawing, [
    AiSourceEdit(start: path.start, end: path.end, bytes: [32]),
    if (count != null) AiSourceEdit(start: count.start, end: count.end, bytes: [32]),
    AiSourceEdit(
      start: after.end,
      end: after.end,
      bytes: [
        10,
        if (count != null) ...[...program.bytes.sublist(count.start, count.end), 10],
        ...program.bytes.sublist(path.start, path.end),
        10,
      ],
    ),
  ], drawing.paths.length);
}
