import 'dart:math' as math;

import 'package:aikit/src/model/ai_native_records.dart';

part '../codec/ai_mesh_geometry.dart';
part '../codec/ai_mesh_color.dart';

/// Explicitly resolves one source corner into the mesh's common process space.
///
/// Called once per corner occurrence, including duplicates at shared vertices.
/// Returning null rejects interpolation. All results must use the same space;
/// shared vertices must resolve to exactly equal components. The package never
/// mixes named inks or converts between device spaces implicitly.
typedef AiNativeMeshColorResolver = AiNativeMeshProcessColor? Function(AiNativeMeshNode corner);

/// Immutable source-derived geometry and color interpolation for a native mesh.
///
/// Supports version-two Cartesian grids with at least two cells on each axis,
/// unit weights, nondegenerate boundary pieces and constant corner opacity.
/// Outer grid color boundaries require nonzero inward tangents; collapsed
/// tangents at interior vertices give zero directional color derivatives.
/// Additional boundary knots may occur on one pair of opposite sides per cell.
/// Unknown fields, inconsistent shared edges/colors and unqualified layouts
/// reject construction. Derived storage is bounded by the source node count.
/// This evaluates the mesh; it does not synchronize PDF artwork or previews.
final class AiNativeMeshInterpolation {
  /// Source snapshot from which every surface and color was derived.
  final AiNativeMesh mesh;

  /// Common process model selected explicitly or retained from source colors.
  final AiNativeMeshProcessSpace space;

  /// Constant native corner opacity, separate from enclosing object opacity.
  final double opacity;

  /// Tensor surfaces in source cell order, retaining compound edge partitions.
  final List<AiNativeMeshSurface> surfaces;

  /// Precomputed directional color derivatives for each owned source cell.
  final Map<AiNativeMeshPatch, _MeshColorPatch> _colors;

  /// Derives a bounded immutable interpolant without consulting PDF artwork.
  ///
  /// Without [resolveColor], all corners must already use one device space.
  /// Named inks and mixed spaces require explicit resolution by the caller.
  factory AiNativeMeshInterpolation({
    required AiNativeMesh mesh,
    AiNativeMeshColorResolver? resolveColor,
  }) {
    if (mesh.size.first < 2 || mesh.size.second < 2) {
      throw UnsupportedError('Mesh interpolation requires at least two cells on each axis.');
    }
    if (mesh.fields.any((field) => !const {'Version', 'Type', 'Size', 'Data', 'P', 'R', 'CS', 'N', 'A', 'S', 'E'}.contains(field.key))) {
      throw UnsupportedError('Mesh interpolation cannot interpret unknown native fields.');
    }
    final Map<(_MeshKey, _MeshKey), _MeshEdge> edges = _meshEdges(mesh);
    final _MeshColorField colors = _MeshColorField(mesh: mesh, edges: edges, resolveColor: resolveColor);
    return AiNativeMeshInterpolation._(
      mesh: mesh,
      space: colors.space,
      opacity: colors.opacity,
      surfaces: [for (final AiNativeMeshPatch patch in mesh.patches) ..._meshSurfaces(patch, edges)],
      colors: {for (final AiNativeMeshPatch patch in mesh.patches) patch: colors.patch(patch)},
    );
  }

  /// Freezes the fully validated derived data.
  AiNativeMeshInterpolation._({
    required this.mesh,
    required this.space,
    required this.opacity,
    required List<AiNativeMeshSurface> surfaces,
    required Map<AiNativeMeshPatch, _MeshColorPatch> colors,
  }) : surfaces = List.unmodifiable(surfaces),
       _colors = Map.unmodifiable(colors);

  /// Evaluates process color at normalized coordinates of an owned source cell.
  ///
  /// Parameters address the original cell, including across compound surface
  /// partitions. Values outside the finite unit interval reject access.
  AiNativeMeshProcessColor colorAt({required AiNativeMeshPatch patch, required double first, required double second}) {
    _meshParameters(first, second);
    final _MeshColorPatch? field = _colors[patch];
    if (field == null) {
      throw ArgumentError('The cell belongs to another native mesh snapshot.');
    }
    return AiNativeMeshProcessColor(space: space, components: field.sample(first, second));
  }

  /// Returns bicubic process coefficients indexed by `first * 4 + second`.
  ///
  /// Each immutable vector has [space]'s component count. Coefficients may lie
  /// outside zero to one; evaluating the polynomial and then clamping gives
  /// [colorAt]. Renderers can restrict these tensors to bound approximation
  /// error throughout a surface, rather than testing isolated color samples.
  List<List<double>> colorControlPoints({required AiNativeMeshPatch patch}) {
    final _MeshColorPatch? field = _colors[patch];
    if (field == null) {
      throw ArgumentError('The cell belongs to another native mesh snapshot.');
    }
    return field.controlPoints;
  }
}

/// One bicubic tensor surface occupying a rectangle of a source mesh cell.
final class AiNativeMeshSurface {
  /// Original cell owning this surface and its color interpolation coordinates.
  final AiNativeMeshPatch patch;

  /// Parameter rectangle in the original cell, with endpoints in zero to one.
  final ({double firstStart, double firstEnd, double secondStart, double secondEnd}) bounds;

  /// Sixteen native-coordinate controls, indexed by `first * 4 + second`.
  ///
  /// This is a tensor grid, not PDF's cyclic boundary serialization order.
  final List<({double x, double y})> controlPoints;

  /// Retains a checked tensor with no mutable storage exposed to the caller.
  AiNativeMeshSurface._({
    required this.patch,
    required this.bounds,
    required List<_MeshPoint> controlPoints,
  }) : controlPoints = List.unmodifiable(controlPoints) {
    for (final _MeshPoint point in controlPoints) {
      _meshFinite(point.x);
      _meshFinite(point.y);
    }
  }

  /// Evaluates native geometry at local surface coordinates in zero to one.
  ///
  /// Map these local parameters through [bounds] before calling
  /// [AiNativeMeshInterpolation.colorAt]. Folded geometry is retained.
  ({double x, double y}) positionAt({required double first, required double second}) {
    _meshParameters(first, second);
    final List<double> firstBasis = _meshBasis(first);
    final List<double> secondBasis = _meshBasis(second);
    return _meshWeighted(controlPoints, [
      for (int row = 0; row < 4; row++)
        for (int column = 0; column < 4; column++) firstBasis[row] * secondBasis[column],
    ]);
  }
}

/// Rejects invalid public coordinates before evaluating any polynomial.
void _meshParameters(double first, double second) {
  if (!first.isFinite || !second.isFinite || first < 0 || first > 1 || second < 0 || second > 1) {
    throw ArgumentError('Mesh parameters must be finite values between zero and one.');
  }
}

/// Rejects arithmetic overflow instead of retaining invalid derived geometry.
double _meshFinite(double value) {
  if (!value.isFinite) {
    throw const FormatException('Mesh interpolation exceeds finite numeric range.');
  }
  return value;
}
