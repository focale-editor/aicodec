part of 'package:aicodec/src/model/ai_native_records.dart';

/// Rejects unrepresentable gradient coordinates before serialization.
List<double> _placementFinite(List<double> values) {
  if (values.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
    throw const FormatException('Gradient placement exceeds bounded native coordinates.');
  }
  return values;
}

/// Applies six affine coefficients to a point in the selected native frame.
List<double> _placementPoint(List<double> matrix, double x, double y) => _placementFinite([
  matrix[0] * x + matrix[2] * y + matrix[4],
  matrix[1] * x + matrix[3] * y + matrix[5],
]);

/// Composes native affine frames, retaining both column vectors and the origin.
List<double> _placementProduct(List<double> first, List<double> second) => _placementFinite([
  first[0] * second[0] + first[2] * second[1],
  first[1] * second[0] + first[3] * second[1],
  first[0] * second[2] + first[2] * second[3],
  first[1] * second[2] + first[3] * second[3],
  ..._placementPoint(first, second[4], second[5]),
]);

/// Inverts a nonsingular native frame without rounding collapsed coordinates.
List<double> _placementInverse(List<double> matrix) {
  _placementFinite(matrix);
  final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
  if (!determinant.isFinite || determinant == 0) {
    throw const FormatException('Gradient placement requires nonsingular coordinate frames.');
  }
  return _placementFinite([
    matrix[3] / determinant,
    -matrix[1] / determinant,
    -matrix[2] / determinant,
    matrix[0] / determinant,
    (matrix[2] * matrix[5] - matrix[3] * matrix[4]) / determinant,
    (matrix[1] * matrix[4] - matrix[0] * matrix[5]) / determinant,
  ]);
}

/// Returns tight cubic extrema using normalized derivative coefficients.
Iterable<double> _placementCubicExtrema(List<double> values) sync* {
  final double first = values[1] - values[0];
  final double second = values[2] - values[0];
  final double last = values[3] - values[0];
  final double quadratic = 3 * first - 3 * second + last;
  final double linear = 2 * (second - 2 * first);
  final double scale = max(quadratic.abs(), max(linear.abs(), first.abs()));
  if (scale == 0) {
    return;
  }
  final double a = quadratic / scale;
  final double b = linear / scale;
  final double c = first / scale;
  final List<double> roots = [];
  if (a == 0) {
    if (b != 0) {
      roots.add(-c / b);
    }
  } else {
    final double discriminant = b * b - 4 * a * c;
    if (discriminant == 0) {
      roots.add(-b / (2 * a));
    } else if (discriminant > 0) {
      final double q = -0.5 * (b + (b >= 0 ? 1 : -1) * sqrt(discriminant));
      roots.addAll([q / a, c / q]);
    }
  }
  for (final double t in roots.where((value) => value > 0 && value < 1)) {
    final double inverse = 1 - t;
    final double first = inverse * values[0] + t * values[1];
    final double second = inverse * values[1] + t * values[2];
    final double third = inverse * values[2] + t * values[3];
    yield inverse * (inverse * first + t * second) + t * (inverse * second + t * third);
  }
}

/// Measures actual native curves after removing accumulated shape transforms.
AiBoundingBox _placementBounds(List<AiNativePath> paths, List<double> matrix) {
  double left = double.infinity;
  double bottom = double.infinity;
  double right = double.negativeInfinity;
  double top = double.negativeInfinity;
  for (final AiNativePath path in paths) {
    List<double>? current;
    for (final AiPathSegment segment in path.segments) {
      final List<double> values = segment.coordinates;
      final List<List<double>> points = [for (int index = 0; index < values.length; index += 2) _placementPoint(matrix, values[index], values[index + 1])];
      final List<List<double>> controls = switch (segment.operator) {
        'm' || 'l' || 'L' => [],
        'v' || 'V' => [current!, current, ...points],
        'y' || 'Y' => [current!, ...points, points.last],
        _ => [current!, ...points],
      };
      final List<double> horizontal = [points.last[0], if (current != null) current[0], ..._placementCubicExtremaIfPresent(controls, 0)];
      final List<double> vertical = [points.last[1], if (current != null) current[1], ..._placementCubicExtremaIfPresent(controls, 1)];
      left = min(left, horizontal.reduce(min));
      right = max(right, horizontal.reduce(max));
      bottom = min(bottom, vertical.reduce(min));
      top = max(top, vertical.reduce(max));
      current = points.last;
    }
  }
  _placementFinite([left, bottom, right, top]);
  return AiBoundingBox(left: left, bottom: bottom, right: right, top: top);
}

/// Measures a cubic axis only when a curve command supplied control points.
Iterable<double> _placementCubicExtremaIfPresent(List<List<double>> points, int axis) => points.isEmpty ? [] : _placementCubicExtrema(points.map((point) => point[axis]).toList());

/// Computes a CC relative gradient's canonical frame from its printable curves.
List<double> _placementFrame(AiNativeGradient gradient, bool radial, List<double> placement) {
  final List<double> retained = gradient.geometry.matrix;
  final List<double> accumulated = [retained[0], -retained[1], -retained[2], retained[3], 0, 0];
  final double angle = placement[2] * pi / 180;
  final List<double> rotation = [cos(angle), sin(angle), -sin(angle), cos(angle), 0, 0];
  final List<double> axes = _placementProduct(accumulated, rotation);
  final AiBoundingBox box = _placementBounds(gradient.paths, _placementInverse(radial ? accumulated : axes));
  final double width = box.right - box.left;
  final double height = box.top - box.bottom;
  final List<double> center = radial
      ? _placementPoint(accumulated, (box.left + box.right) / 2 + placement[0] * width, (box.bottom + box.top) / 2 - placement[1] * height)
      : _placementPoint(axes, box.left + placement[0] * width, (box.bottom + box.top) / 2);
  final double radius = radial ? sqrt(pow(width * (placement[0] - 0.5), 2) + pow(height * (placement[1] - 0.5), 2)) * sqrt(0.5) : width;
  final double length = radius * placement[3];
  final double cross = radial ? length * placement[4] : 1;
  final List<double> frame = _placementFinite([axes[0] * length, axes[1] * length, -axes[2] * cross, -axes[3] * cross, ...center]);
  _placementInverse(frame);
  return frame;
}
