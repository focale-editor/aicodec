part of 'package:aikit/src/model/ai_native_records.dart';

/// Transforms selected authoritative contours while retaining native paint state.
AiNativeDrawing _transformNativePaths(AiNativeDrawing drawing, List<AiNativePath> paths, AiNativeAffineTransform transform, AiBoundingBox bounds, Map<AiNativePath, double> frameAngles) {
  _nativeTopologyBounds(bounds);
  if (paths.isEmpty || paths.toSet().length != paths.length || frameAngles.keys.any((path) => !paths.contains(path))) {
    throw ArgumentError('Affine contour transforms require a distinct owned selection.');
  }
  final List<AiNativePathTopology> topology = _nativePathTopologies(drawing, paths);
  final _NativeAffinePoints points = _NativeAffinePoints(transform: transform);
  final List<AiSourceEdit> edits = [];
  for (final AiNativePathTopology owner in topology) {
    final AiNativeContainer? dictionary = drawing._objects.forSource(owner.path).dictionary;
    final double? angle = frameAngles[owner.path];
    if (angle != null && (!angle.isFinite || angle.abs() > 2 * pi)) {
      throw ArgumentError('Native frame angles must lie in -2π..2π.');
    }
    if (!transform.isIdentity || angle != null) {
      edits.addAll(_nativeFrameRotationEdits(drawing.records, dictionary, owner.path.end, angle));
    }
  }
  if (!transform.isIdentity) {
    edits.addAll(_nativePathEdits(drawing, [for (final AiNativePath path in paths) AiNativePathEdit(path: path, segments: points.segments(path.segments))]));
    edits.addAll(AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds));
  }
  if (edits.isEmpty) {
    return drawing;
  }
  return _groupLifecycleResult(drawing, edits, paths: drawing.paths.length, groups: drawing.groups.length, liveShapes: drawing.liveShapes.length);
}

/// Writes host-regenerated native parameters, contours and expansions together.
AiNativeDrawing _replaceNativeLiveShapes(AiNativeDrawing drawing, List<AiNativeLiveShapeReplacement> replacements) {
  final List<AiLiveShape> shapes = replacements.map((replacement) => replacement.shape).toList();
  if (shapes.isEmpty || shapes.toSet().length != shapes.length || shapes.any((shape) => !drawing.liveShapes.contains(shape))) {
    throw ArgumentError('Shape replacement requires distinct handles from this drawing.');
  }
  final _LiveShapeEditor guard = _LiveShapeEditor(drawing: drawing, shapes: shapes);
  guard._checkDrawing();
  final List<AiSourceEdit> edits = [];
  final List<AiNativePrintingGroupReplacement> printing = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeLiveShapeReplacement replacement in replacements) {
    final AiLiveShape shape = replacement.shape;
    if (!shape.isBound || shape.path == null) {
      throw UnsupportedError(shape.bindingIssue ?? 'A native shape requires an authoritative contour.');
    }
    final AiNativeShapeParameters original = AiNativeShapeParameters.fromShape(shape: shape);
    _shapeFamilyChange(original, replacement.parameters, replacement.segments);
    _shapeWithoutPositionalPaint(drawing, shape);
    AiNativeInstruction? count;
    if (shape.appearanceGroup == null) {
      if (replacement.printing != null) {
        throw ArgumentError('A direct shape has no separate printing attachment.');
      }
      count = _ordinaryPathCounts(drawing, [shape.path!])[shape.path!];
    } else {
      if (replacement.printing == null) {
        throw ArgumentError('A CC shape replacement requires its complete new printing group.');
      }
      final _NativeShapeBundle bundle = _shapeBundle(drawing, shape, drawing._objects.structure);
      count = bundle.commands.where((command) => command.operator == 'As' && command.isPrivate && command.end < shape.path!.start).singleOrNull;
      printing.add(AiNativePrintingGroupReplacement(shape: shape, bytes: replacement.printing!, bounds: replacement.bounds));
    }
    for (final AiNativeContainer dictionary in [shape.dictionary, ?shape.appearanceDictionary, ...shape.alternativeDictionaries]) {
      _shapeCopyDictionary(drawing, shape, dictionary);
      final AiNativeContainer? definition = dictionary['ai::LiveShape']?.container;
      final AiNativeContainer? parameters = definition?['ai::LiveShape::Params']?.container;
      if (parameters != null) {
        _consistentShapeParameters(shape, parameters);
        final AiSourceEdit edit = _replaceShapeParameterDictionary(drawing, parameters, replacement.parameters);
        remaining -= edit.bytes.length;
        if (remaining < 0) {
          throw const AiLimitException(message: 'Shape parameter output exceeds the aggregate byte limit.');
        }
        edits.add(edit);
      }
      if (definition != null && replacement.parameters.handler != shape.handler) {
        final AiNativeEntry handler = definition['ai::LiveShape::HandlerName']!;
        edits.add(AiSourceEdit(start: handler.items.first.start, end: handler.items.first.end, bytes: _nativeString(replacement.parameters.handler)));
        edits.addAll(handler.items.skip(1).map((item) => AiSourceEdit(start: item.start, end: item.end, bytes: [])));
      }
      edits.addAll(_nativeFrameRotationEdits(drawing.records, dictionary, dictionary.end, replacement.rotationRadians));
    }
    final List<AiSourceEdit> geometry = _replaceShapeContour(drawing, shape.path!, count, replacement.segments, remaining);
    remaining -= geometry.fold<int>(0, (total, edit) => total + edit.bytes.length);
    edits.addAll(geometry);
  }
  final AiBoundingBox bounds = AiBoundingBox(
    left: replacements.map((value) => value.bounds.left).reduce(min),
    bottom: replacements.map((value) => value.bounds.bottom).reduce(min),
    right: replacements.map((value) => value.bounds.right).reduce(max),
    top: replacements.map((value) => value.bounds.top).reduce(max),
  );
  if (printing.isNotEmpty) {
    edits.addAll(
      _nativePrintingSourceEdits(drawing, [
        for (final AiNativePrintingGroupReplacement replacement in printing) (group: _printingShapeGroup(drawing, replacement.shape), bytes: replacement.bytes, bounds: replacement.bounds),
      ], documentBounds: false),
    );
  }
  edits.addAll(AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds));
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: drawing.records.program, edits: edits),
    ),
  );
  if (result.liveShapes.length != drawing.liveShapes.length) {
    throw const FormatException('Shape replacement changed unrelated native ownership.');
  }
  for (final AiNativeLiveShapeReplacement replacement in replacements) {
    final AiLiveShape changed = result.liveShapes[drawing.liveShapes.indexOf(replacement.shape)];
    if (!changed.isBound || changed.handler != replacement.parameters.handler) {
      throw const FormatException('Shape replacement lost its native handler or printing ownership.');
    }
  }
  return result;
}

/// Rejects parameter edits that would leave gradients or accumulated caches stale.
void _shapeWithoutPositionalPaint(AiNativeDrawing drawing, AiLiveShape shape) {
  if (drawing.gradients.any((gradient) => gradient.paths.any(({?shape.path, ...shape.appearancePaths}).contains) || gradient.start >= shape.start && gradient.end <= shape.end)) {
    throw UnsupportedError('General shape edits require a separate gradient rebasing contract.');
  }
  final AiNativeContainer? style = shape.style;
  if (style != null) {
    for (final AiNativeContainer record in drawing.records.containers.where(
      (record) => record.start > style.start && record.end < style.end && {'FillStyle', 'StrokeStyle', 'BlendStyle'}.contains(record.type),
    )) {
      if (AiNativePaintStyle.decode(records: drawing.records, record: record).gradients.isNotEmpty) {
        throw UnsupportedError('General shape edits cannot retain positional shared paints.');
      }
    }
  }
}

/// Allows the observed irregular-polygon representation for a sharp rectangle.
void _shapeFamilyChange(AiNativeShapeParameters original, AiNativeShapeParameters changed, List<AiPathSegment> segments) {
  if (original.handler == changed.handler) {
    return;
  }
  if (original.handler != 'ai::Rectangle' ||
      changed.handler != 'ai::Polygon' ||
      changed.numbers['NumSides'] != 4 ||
      changed.numbers['Radius'] != -11 ||
      changed.flags['IsRegular'] != false ||
      original.numbers.entries.any((entry) => entry.key.contains('CornerRadius') && entry.value != 0)) {
    throw UnsupportedError('Only a sharp rectangle can change family to an irregular four-sided polygon.');
  }
  _parallelogramFromSegments(segments);
}

/// Confirms redundant parameter copies before replacing all their known fields.
void _consistentShapeParameters(AiLiveShape shape, AiNativeContainer parameters) {
  for (final AiNativeEntry field in parameters.entries.where((entry) => !entry.isQualifier)) {
    final AiNativeEntry? original = shape.parameters[field.key!];
    if (original == null || original.type != field.type || (field.number != null ? !_sameNativeMatrix([field.number!], [original.number!]) : field.text() != original.text())) {
      throw UnsupportedError('Redundant live-shape parameters disagree with the authoritative record.');
    }
  }
}

/// Rewrites one complete typed dictionary with its original private spelling.
AiSourceEdit _replaceShapeParameterDictionary(AiNativeDrawing drawing, AiNativeContainer target, AiNativeShapeParameters parameters) {
  final bool private = drawing.records._projection.isPrivate(target.start);
  final String prefix = private ? '%_' : '';
  return AiSourceEdit(
    start: target.start,
    end: target.end,
    bytes: latin1.encode(_nativeShapeParametersSource(parameters, prefix: prefix, notRecorded: target.notRecorded)),
  );
}

/// Replaces an owned authoring curve while retaining closure, paint and comments.
List<AiSourceEdit> _replaceShapeContour(AiNativeDrawing drawing, AiNativePath path, AiNativeInstruction? count, List<AiPathSegment> supplied, int budget, {bool? closed}) {
  final bool closure = closed ?? path.closed;
  int remaining = budget;
  final List<AiPathSegment> segments = [...supplied];
  final List<double> first = segments.first.coordinates;
  final List<double> last = segments.last.coordinates;
  if (count != null && closure && (segments.length == 1 || last[last.length - 2] != first[0] || last.last != first[1])) {
    segments.add(AiPathSegment(operator: 'L', coordinates: first));
  }
  final StringBuffer output = StringBuffer();
  for (final AiPathSegment segment in segments) {
    // Stay on the original line so a following private paint stays private.
    final String command = '${segment.coordinates.join(' ')} ${segment.operator} ';
    remaining -= command.length;
    if (remaining < 0) {
      throw const AiLimitException(message: 'Native shape contours exceed the aggregate byte limit.');
    }
    output.write(command);
  }
  return [
    if (count != null) _numberEdit(AiNativeToken._(token: count.operands.single), (segments.length - (closure ? 1 : 0)).toDouble()),
    AiSourceEdit(start: path.geometry.first.start, end: path.geometry.first.end, bytes: latin1.encode(output.toString())),
    for (final AiNativeInstruction command in path.geometry.skip(1)) AiSourceEdit(start: command.start, end: command.end, bytes: []),
  ];
}

/// Reads four straight corners without replacing an arbitrary polygon by a box.
AiNativeParallelogram _parallelogramFromSegments(List<AiPathSegment> segments) {
  if (segments.length < 4 || segments.length > 5 || segments.skip(1).any((segment) => !{'l', 'L'}.contains(segment.operator))) {
    throw UnsupportedError('A parallelogram requires exactly four straight sides.');
  }
  final List<List<double>> points = segments.take(4).map((segment) => segment.coordinates).toList();
  if (segments.length == 5 && !_sameNativeMatrix(segments.last.coordinates, points.first) ||
      !_sameNativeMatrix([points[0][0] + points[2][0], points[0][1] + points[2][1]], [points[1][0] + points[3][0], points[1][1] + points[3][1]])) {
    throw UnsupportedError('Opposite parallelogram sides must be parallel with consistent closure.');
  }
  return AiNativeParallelogram(
    centerX: (points[0][0] + points[2][0]) / 2,
    centerY: (points[0][1] + points[2][1]) / 2,
    ux: (points[1][0] - points[0][0]) / 2,
    uy: (points[1][1] - points[0][1]) / 2,
    vx: (points[3][0] - points[0][0]) / 2,
    vy: (points[3][1] - points[0][1]) / 2,
  );
}
