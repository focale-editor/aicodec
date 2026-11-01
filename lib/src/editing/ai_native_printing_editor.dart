part of 'package:aikit/src/model/ai_native_records.dart';

/// Attaches bounded host geometry while preserving native ownership and state.
AiNativeDrawing _replaceNativePrintingContours(AiNativeDrawing drawing, List<AiNativePrintingReplacement> replacements) {
  if (replacements.isEmpty || replacements.map((replacement) => replacement.shape).toSet().length != replacements.length) {
    throw ArgumentError('Printing replacement requires a nonempty distinct shape selection.');
  }
  final AiProgram program = drawing.records.program;
  final List<AiSourceEdit> edits = [];
  final Set<AiNativePath> selected = {};
  double left = double.infinity;
  double bottom = double.infinity;
  double right = double.negativeInfinity;
  double top = double.negativeInfinity;
  int outputBytes = 0;
  int outputTokens = 0;
  for (final AiNativePrintingReplacement replacement in replacements) {
    final AiLiveShape shape = replacement.shape;
    final AiNativeGroup group = _printingShapeGroup(drawing, shape);
    final Map<AiNativePath, AiNativeInstruction> pointCounts = _printingPointCounts(drawing, group);
    final List<AiNativePath> paths = replacement.paths.map((path) => path.path).toList();
    if (paths.length != shape.appearancePaths.length || paths.toSet().length != paths.length || paths.any((path) => !shape.appearancePaths.contains(path) || !selected.add(path))) {
      throw ArgumentError('Printing replacement must cover every owned path exactly once.');
    }
    for (final AiNativePrintingContours supplied in replacement.paths) {
      final AiNativePath path = supplied.path;
      final List<AiNativeInstruction> controls = drawing.items
          .whereType<AiNativeInstruction>()
          .where((item) => item.start >= path.start && item.end <= path.end && item != path.paint && !path.geometry.contains(item))
          .toList();
      if (path.isPrivate || controls.any((item) => item.start < path.geometry.last.end)) {
        throw UnsupportedError('Printing path geometry contains interleaved state changes.');
      }
      if (supplied.contours.length > 1 && (controls.isNotEmpty || drawing.gradients.any((gradient) => gradient.paths.contains(path)))) {
        throw UnsupportedError('Additional printing contours require a self-contained path paint operation.');
      }
      final StringBuffer geometry = StringBuffer();

      /// Bounds generated text before retaining it in the replacement buffer.
      void append(String value, int tokens) {
        outputBytes += value.length;
        outputTokens += tokens;
        if (outputBytes > program.limits.maxDecodedBytes || outputTokens > program.limits.maxTokens) {
          throw const AiLimitException(message: 'Supplied printing contours exceed native output limits.');
        }
        geometry.write(value);
      }

      for (final (int, List<AiPathSegment>) contour in supplied.contours.indexed) {
        final bool counted = pointCounts.containsKey(path);
        final List<double> first = contour.$2.first.coordinates;
        final List<double> last = contour.$2.last.coordinates;
        final bool close = counted && path.closed && (contour.$2.length == 1 || last[last.length - 2] != first[0] || last.last != first[1]);
        final int points = contour.$2.length + (close ? 1 : 0) - (path.closed ? 1 : 0);
        if (contour.$1 > 0) {
          append('${path.paint.operator}\n', 1);
          if (counted) {
            append('$points As\n', 2);
          }
        } else if (counted) {
          final AiToken count = pointCounts[path]!.operands.single;
          edits.add(AiSourceEdit(start: count.start, end: count.end, bytes: latin1.encode('$points')));
        }
        for (final AiPathSegment segment in contour.$2) {
          if (segment.coordinates.any((coordinate) => coordinate.abs() > 9007199254740991)) {
            throw ArgumentError('Printing contours exceed portable native coordinates.');
          }
          append('${segment.coordinates.map((coordinate) => coordinate.toString()).join(' ')} ${segment.operator}\n', segment.coordinates.length + 1);
        }
        if (close) {
          append('${first[0]} ${first[1]} L\n', 3);
        }
      }
      edits.add(AiSourceEdit(start: path.geometry.first.start, end: path.geometry.first.end, bytes: latin1.encode(geometry.toString())));
      edits.addAll([for (final AiNativeInstruction command in path.geometry.skip(1)) AiSourceEdit(start: command.start, end: command.end, bytes: [])]);
    }
    left = min(left, replacement.bounds.left);
    bottom = min(bottom, replacement.bounds.bottom);
    right = max(right, replacement.bounds.right);
    top = max(top, replacement.bounds.top);
  }
  edits.addAll(
    AiNativeEditor.includeBoundsEdits(
      program: program,
      bounds: AiBoundingBox(left: left, bottom: bottom, right: right, top: top),
    ),
  );
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: program, edits: edits),
    ),
  );
  if (result.liveShapes.length != drawing.liveShapes.length || result.liveShapes.indexed.any((entry) => drawing.liveShapes[entry.$1].isBound && !entry.$2.isBound)) {
    throw const FormatException('Supplied printing contours changed native shape ownership.');
  }
  return result;
}

/// Resolves an isolated derived group without replacing private authoring data.
AiNativeGroup _printingShapeGroup(AiNativeDrawing drawing, AiLiveShape shape, {bool clipping = false}) {
  if (!drawing.liveShapes.contains(shape)) {
    throw ArgumentError('Printing replacement has a stale or foreign native shape.');
  }
  final AiNativeGroup? group = shape.appearanceGroup;
  if (!shape.isBound || shape.path?.isPrivate != true || group == null || shape.appearanceDictionary == null) {
    throw UnsupportedError(shape.bindingIssue ?? 'Printing replacement requires a separate, bound CC expansion.');
  }
  if (drawing.liveShapes.any((other) => !identical(other, shape) && other.start < group.end && other.end > group.start)) {
    throw UnsupportedError('The printing group overlaps another authoring object.');
  }
  _printingCommands(drawing, group, clipping: clipping);
  return group;
}

/// Rejects hidden payloads and returns the exact local declarative commands.
List<AiNativeInstruction> _printingCommands(AiNativeDrawing drawing, AiNativeGroup group, {bool clipping = false}) {
  if (drawing.records._projection.tokens.any(
    (token) => token.start < group.end && token.end > group.start && (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%%BeginDocument') || token.lexeme.startsWith('%AI'))),
  )) {
    throw UnsupportedError('Printing replacement requires resolved local data and embedded-document dependencies.');
  }
  final List<AiNativeInstruction> result = [];
  for (final AiNativeItem item in drawing.items.where((item) => item.start >= group.start && item.end <= group.end)) {
    if (item is! AiNativeInstruction || item.isPrivate || !(_printingGeometryControls.contains(item.operator) || clipping && const {'h', 'H', 'W'}.contains(item.operator))) {
      throw UnsupportedError('Printing replacement requires resolved local commands and no nested authoring metadata.');
    }
    result.add(item);
  }
  return result;
}

/// Associates observed CC point counts without carrying them across boundaries.
Map<AiNativePath, AiNativeInstruction> _printingPointCounts(AiNativeDrawing drawing, AiNativeGroup group) {
  final Map<int, AiNativePath> starts = {for (final AiNativePath path in group.paths) path.start: path};
  final Map<AiNativePath, AiNativeInstruction> counts = {};
  final int previous = drawing.paths.where((path) => path.end < group.start).fold(drawing.records.program.bodyStart, (end, path) => max(end, path.end));
  AiNativeInstruction? pending;
  AiNativePath? current;
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>().where((item) => item.start >= previous && item.end <= group.end)) {
    if (item.operator == 'As') {
      if (pending != null || current != null) {
        throw UnsupportedError('Printing point counts must precede exactly one path.');
      }
      pending = item;
    } else if (starts[item.start] case final AiNativePath path) {
      current = path;
      if (pending case final AiNativeInstruction count) {
        final List<double>? numbers = count.numbers;
        final List<AiPathSegment> segments = path.segments;
        final List<double> first = segments.first.coordinates;
        final List<double> last = segments.last.coordinates;
        final bool closed =
            path.closed || _pathInterval(drawing.items, path.geometry.last.end, path.paint.start, (item) => item.start).whereType<AiNativeInstruction>().any((item) => item.operator == 'h');
        if (numbers == null ||
            numbers.length != 1 ||
            numbers.single != segments.length - (closed ? 1 : 0) ||
            segments.skip(1).any((segment) => segment.operator == 'm') ||
            closed && (segments.length == 1 || last[last.length - 2] != first[0] || last.last != first[1])) {
          throw UnsupportedError('The native printing point count or closed-path layout is inconsistent.');
        }
        counts[path] = count;
        pending = null;
      }
    } else if (identical(item, current?.paint)) {
      current = null;
    } else if (pending != null && const {'u', 'U', '*u', '*U', 'q', 'Q'}.contains(item.operator)) {
      throw UnsupportedError('A printing point count crosses an object boundary.');
    }
  }
  if (pending != null) {
    throw UnsupportedError('A native printing point count has no owned path.');
  }
  return counts;
}

/// Structural and paint commands retained byte-for-byte around supplied curves.
///
/// This is an edit dependency contract, not a rendering or save whitelist.
/// Unknown commands outside the selected printing group do not participate.
const Set<String> _printingGeometryControls = {
  ..._nativeGeometry,
  ..._nativePaint,
  ..._solidStyleCommands,
  ..._gradientCommands,
  'Ap',
  'As',
  'Ae',
  'D',
  'u',
  'U',
  '*u',
  '*U',
  'q',
  'Q',
};
