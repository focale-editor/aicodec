part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Derives representable native parameters without generating printing outlines.
AiNativeDrawing _transformLiveShapes(AiNativeDrawing drawing, List<AiLiveShape> shapes, AiNativeAffineTransform transform, AiBoundingBox bounds, Map<AiLiveShape, List<int>> printing) {
  if (shapes.isEmpty || shapes.toSet().length != shapes.length || shapes.any((shape) => !drawing.liveShapes.contains(shape)) || printing.keys.any((shape) => !shapes.contains(shape))) {
    throw ArgumentError('Affine shape transforms require distinct owned handles and matching printing replacements.');
  }
  _nativeTopologyBounds(bounds);
  final _LiveShapeSimilarity basis = _LiveShapeSimilarity(drawing: drawing, pivotX: 0, pivotY: 0)..validate();
  final _NativeAffinePoints points = _NativeAffinePoints(transform: transform);
  final List<AiNativeLiveShapeReplacement> replacements = [];
  for (final AiLiveShape shape in shapes) {
    if (shape.path == null || !shape.isBound) {
      throw UnsupportedError(shape.bindingIssue ?? 'Affine shapes require an authoritative contour.');
    }
    final List<AiPathSegment> geometry = points.segments(shape.path!.segments);
    final AiNativeShapeParameters parameters = _affineShapeParameters(shape, transform, basis.origin, geometry);
    final List<double> angles = [
      for (final AiNativeContainer dictionary in [shape.dictionary, ?shape.appearanceDictionary, ...shape.alternativeDictionaries])
        if (_nativeFrameRotation(dictionary) case final double angle) angle,
    ];
    if (angles.any((angle) => (sin(angle - angles.first)).abs() > 1e-6 || cos(angle - angles.first) < 0)) {
      throw UnsupportedError('Native shape frame angles disagree across saved representations.');
    }
    final double? frameAngle = angles.isEmpty ? null : _affineDirection(transform, angles.first).$3;
    replacements.add(AiNativeLiveShapeReplacement(shape: shape, parameters: parameters, segments: geometry, printing: printing[shape], rotationRadians: frameAngle, bounds: bounds));
  }
  return _replaceNativeLiveShapes(drawing, replacements);
}

/// Returns transformed local axes and their first-axis angle in drawing space.
(double, double, double) _affineDirection(AiNativeAffineTransform transform, double angle) {
  final double x = transform.a * cos(angle) + transform.c * sin(angle);
  final double y = transform.b * cos(angle) + transform.d * sin(angle);
  final double length = sqrt(x * x + y * y);
  if (!length.isFinite || length == 0) {
    throw ArgumentError('Affine transformation collapses a native shape axis.');
  }
  return (x, y, atan2(y, x));
}

/// Preserves the native family where possible; sharp sheared rectangles become polygons.
AiNativeShapeParameters _affineShapeParameters(AiLiveShape shape, AiNativeAffineTransform transform, List<double> origin, List<AiPathSegment> geometry) {
  final AiNativeShapeParameters source = AiNativeShapeParameters.fromShape(shape: shape);
  final String angleKey = shape.handler == 'ai::Rectangle' ? 'Angle' : 'RotationAngle';
  final double angle = source.numbers[angleKey]!;
  final (double, double, double) first = _affineDirection(transform, angle);
  final (double, double, double) second = _affineDirection(transform, angle + pi / 2);
  final double scaleX = sqrt(first.$1 * first.$1 + first.$2 * first.$2);
  final double scaleY = sqrt(second.$1 * second.$1 + second.$2 * second.$2);
  final bool perpendicular = (first.$1 * second.$1 + first.$2 * second.$2).abs() <= 1e-12 * scaleX * scaleY;
  final bool uniform = perpendicular && (scaleX - scaleY).abs() <= 1e-12 * max(scaleX, scaleY);
  final bool reflected = transform.determinant < 0;
  final bool rounded = source.numbers.entries.any((entry) => entry.key.contains('Corner') && entry.key.contains('Radius') && entry.value != 0);
  if (rounded && (!uniform || reflected)) {
    throw UnsupportedError('Affine rounded shapes require host-regenerated corner geometry and parameters.');
  }
  final List<double> center = transform.point(x: source.numbers['CenterX']! - origin[0], y: origin[1] - source.numbers['CenterY']!);
  final Map<String, double> numbers = {'CenterX': origin[0] + center[0], 'CenterY': origin[1] - center[1], angleKey: first.$3};
  final Map<String, bool> flags = {};
  if (reflected) {
    if (shape.handler != 'ai::Line' && !source.flags.containsKey('Clockwise')) {
      throw UnsupportedError('Reflection requires an explicit native winding flag.');
    }
    if (source.flags['Clockwise'] case final bool clockwise) {
      flags['Clockwise'] = !clockwise;
    }
  }
  switch (shape.handler) {
    case 'ai::Rectangle':
      if (!perpendicular) {
        final AiNativeParallelogram parallelogram = _parallelogramFromSegments(geometry);
        if (!_sameNativeMatrix([parallelogram.centerX, parallelogram.centerY], center)) {
          throw UnsupportedError('Rectangle geometry disagrees with its native canvas center.');
        }
        return parallelogram.parameters(rulerOriginX: origin[0], rulerOriginY: origin[1]);
      }
      numbers['Width'] = _scaleNativeLength(source.numbers['Width']!, scaleX);
      numbers['Height'] = _scaleNativeLength(source.numbers['Height']!, scaleY);
    case 'ai::Ellipse':
      if (!perpendicular || source.numbers.containsKey('PieStartAngle') || source.numbers.containsKey('PieEndAngle')) {
        throw UnsupportedError('Sheared or pie ellipses require host parameter and contour regeneration.');
      }
      numbers['Width'] = _scaleNativeLength(source.numbers['Width']!, scaleX);
      numbers['Height'] = _scaleNativeLength(source.numbers['Height']!, scaleY);
    case 'ai::Polygon':
      if (!uniform) {
        if (rounded || geometry.skip(1).any((segment) => !{'l', 'L'}.contains(segment.operator))) {
          throw UnsupportedError('Nonuniform polygons require sharp straight-sided geometry.');
        }
        numbers['Radius'] = -11;
        flags['IsRegular'] = false;
      } else if (source.numbers['Radius'] != -11) {
        numbers['Radius'] = _scaleNativeLength(source.numbers['Radius']!, scaleX);
      }
    case 'ai::Star':
      if (!uniform) {
        throw UnsupportedError('Nonuniform stars require host-regenerated native parameters.');
      }
      numbers['Radius1'] = _scaleNativeLength(source.numbers['Radius1']!, scaleX);
      numbers['Radius2'] = _scaleNativeLength(source.numbers['Radius2']!, scaleX);
    case 'ai::Line':
      numbers['Length'] = _scaleNativeLength(source.numbers['Length']!, scaleX);
  }
  if (rounded) {
    for (final MapEntry<String, double> entry in source.numbers.entries.where((entry) => entry.key.contains('Corner') && entry.key.contains('Radius'))) {
      numbers[entry.key] = _scaleNativeLength(entry.value, scaleX);
    }
  }
  return source.copyWith(numbers: numbers, flags: flags);
}
