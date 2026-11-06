part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// A finite invertible affine map in native drawing coordinates (y up).
final class AiNativeAffineTransform {
  /// Horizontal contribution of the input x coordinate.
  final double a;

  /// Vertical contribution of the input x coordinate.
  final double b;

  /// Horizontal contribution of the input y coordinate.
  final double c;

  /// Vertical contribution of the input y coordinate.
  final double d;

  /// Horizontal translation in drawing points.
  final double tx;

  /// Vertical translation in drawing points.
  final double ty;

  /// Validates a portable, nonsingular matrix without decomposing authored axes.
  AiNativeAffineTransform({this.a = 1, this.b = 0, this.c = 0, this.d = 1, this.tx = 0, this.ty = 0}) {
    if ([a, b, c, d, tx, ty].any((value) => !value.isFinite || value.abs() > 9007199254740991) || !determinant.isFinite || determinant == 0) {
      throw ArgumentError('Native affine transforms require finite portable values and a nonzero finite determinant.');
    }
  }

  /// Scales each drawing axis about an explicit pivot; negative values reflect.
  factory AiNativeAffineTransform.scale({required double scaleX, required double scaleY, required double pivotX, required double pivotY}) =>
      AiNativeAffineTransform(a: scaleX, d: scaleY, tx: pivotX * (1 - scaleX), ty: pivotY * (1 - scaleY));

  /// Applies horizontal and vertical shear coefficients about a drawing pivot.
  factory AiNativeAffineTransform.shear({required double horizontal, required double vertical, required double pivotX, required double pivotY}) =>
      AiNativeAffineTransform(c: horizontal, b: vertical, tx: -horizontal * pivotY, ty: -vertical * pivotX);

  /// Reflects across the line through the pivot at [axisRadians] counterclockwise.
  factory AiNativeAffineTransform.reflection({required double axisRadians, required double pivotX, required double pivotY}) {
    if (!axisRadians.isFinite || axisRadians.abs() > 2 * pi) {
      throw ArgumentError('A reflection axis must lie in -2π..2π.');
    }
    final double turns = axisRadians / (pi / 4);
    final int? cardinal = turns == turns.roundToDouble() ? turns.toInt() % 4 : null;
    final double cosine = cardinal == null ? cos(2 * axisRadians) : const [1.0, 0.0, -1.0, 0.0][cardinal];
    final double sine = cardinal == null ? sin(2 * axisRadians) : const [0.0, 1.0, 0.0, -1.0][cardinal];
    return AiNativeAffineTransform(a: cosine, b: sine, c: sine, d: -cosine, tx: pivotX - cosine * pivotX - sine * pivotY, ty: pivotY - sine * pivotX + cosine * pivotY);
  }

  /// Signed area scale, negative when the map reverses winding.
  double get determinant => a * d - b * c;

  /// Whether this matrix leaves every coordinate unchanged.
  bool get isIdentity => a == 1 && b == 0 && c == 0 && d == 1 && tx == 0 && ty == 0;

  /// The inverse map, subject to the same portable numeric limits.
  AiNativeAffineTransform get inverse =>
      AiNativeAffineTransform(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant, tx: (c * ty - d * tx) / determinant, ty: (b * tx - a * ty) / determinant);

  /// Transforms one point without permitting output overflow.
  List<double> point({required double x, required double y}) {
    final List<double> result = [a * x + c * y + tx, b * x + d * y + ty];
    if ([x, y, ...result].any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('Native affine geometry exceeds portable coordinates.');
    }
    return result;
  }
}

/// Editable parallelogram geometry represented natively as an irregular polygon.
///
/// Half-edge vectors are measured from the center in y-up drawing coordinates.
/// No unrecognized Illustrator handler or private host metadata is invented.
final class AiNativeParallelogram {
  /// Horizontal center in drawing points.
  final double centerX;

  /// Vertical center in drawing points.
  final double centerY;

  /// Horizontal component of the first half-edge.
  final double ux;

  /// Vertical component of the first half-edge.
  final double uy;

  /// Horizontal component of the second half-edge.
  final double vx;

  /// Vertical component of the second half-edge.
  final double vy;

  /// Captures two independent half-edges and their common center.
  AiNativeParallelogram({required this.centerX, required this.centerY, required this.ux, required this.uy, required this.vx, required this.vy}) {
    AiNativeAffineTransform(a: ux, b: uy, c: vx, d: vy, tx: centerX, ty: centerY);
    segments;
  }

  /// Four straight sides with an explicit return to the initial point.
  List<AiPathSegment> get segments {
    final AiNativeAffineTransform basis = AiNativeAffineTransform(a: ux, b: uy, c: vx, d: vy, tx: centerX, ty: centerY);
    final _NativeAffinePoints points = _NativeAffinePoints(transform: basis);
    return List.unmodifiable([
      for (final (int index, (double x, double y)) entry in <(double, double)>[(-1, -1), (1, -1), (1, 1), (-1, 1), (-1, -1)].indexed)
        AiPathSegment(
          operator: entry.$1 == 0 ? 'm' : 'L',
          coordinates: points.point(entry.$2.$1, entry.$2.$2),
        ),
    ]);
  }

  /// Native polygon parameters for an explicit document canvas ruler origin.
  AiNativeShapeParameters parameters({required double rulerOriginX, required double rulerOriginY}) => AiNativeShapeParameters(
    handler: 'ai::Polygon',
    numbers: {
      'CenterX': rulerOriginX + centerX,
      'CenterY': rulerOriginY - centerY,
      'RotationAngle': atan2(uy, ux),
      'NumSides': 4,
      'Radius': -11,
      'CornerRadius': 0,
      'CornerType': 0,
      'CornerRoundingType': 0,
    },
    flags: {'IsRegular': false, 'Clockwise': ux * vy - uy * vx < 0},
  );
}

/// Tracks transformed points so distinct source geometry cannot silently collapse.
final class _NativeAffinePoints {
  /// Validated map shared by all selected contours.
  final AiNativeAffineTransform transform;

  /// Source point corresponding to each already transformed coordinate.
  final Map<(double, double), (double, double)> _sources = {};

  /// Captures a transaction-local precision guard.
  _NativeAffinePoints({required this.transform});

  /// Transforms anchors and cubic controls while retaining native operators.
  List<AiPathSegment> segments(List<AiPathSegment> source) => [
    for (final AiPathSegment segment in source)
      AiPathSegment(
        operator: segment.operator,
        coordinates: [for (int index = 0; index < segment.coordinates.length; index += 2) ...point(segment.coordinates[index], segment.coordinates[index + 1])],
      ),
  ];

  /// Rejects floating-point collapse before any source edit is committed.
  List<double> point(double x, double y) {
    final List<double> result = transform.point(x: x, y: y);
    final (double, double) key = (result[0], result[1]);
    final (double, double)? previous = _sources[key];
    if (previous != null && previous != (x, y)) {
      throw ArgumentError('Native affine transformation collapses distinct coordinates.');
    }
    _sources[key] = (x, y);
    return result;
  }
}
