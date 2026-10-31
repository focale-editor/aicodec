part of 'package:aikit/src/model/ai_native_mesh_interpolation.dart';

/// Source colors and directional derivatives shared by neighboring cells.
final class _MeshColorField {
  /// Common explicitly selected process space.
  final AiNativeMeshProcessSpace space;

  /// Uniform source opacity, never inferred from resolved process colors.
  final double opacity;

  /// Process components at each logical vertex.
  final Map<_MeshKey, List<double>> values;

  /// Spatial color derivatives for each vertex and grid direction.
  final Map<(_MeshKey, int), List<double>> derivatives;

  /// Shared geometry supplying complete-edge handle normalization.
  final Map<(_MeshKey, _MeshKey), _MeshEdge> edges;

  /// Checks shared colors and derives bounded slopes without PDF samples.
  factory _MeshColorField({
    required AiNativeMesh mesh,
    required Map<(_MeshKey, _MeshKey), _MeshEdge> edges,
    AiNativeMeshColorResolver? resolveColor,
  }) {
    final Map<_MeshKey, List<double>> values = {};
    AiNativeMeshProcessSpace? space;
    double? opacity;
    for (final AiNativeMeshVertex vertex in mesh.vertices) {
      final _MeshKey key = (first: vertex.firstIndex, second: vertex.secondIndex);
      for (final AiNativeMeshNode corner in vertex.corners) {
        final AiNativeMeshProcessColor? color = resolveColor == null ? _meshDeviceColor(corner) : resolveColor(corner);
        if (color == null || space != null && color.space != space) {
          throw UnsupportedError('Mesh interpolation requires explicitly resolved colors in one process space.');
        }
        space ??= color.space;
        opacity ??= corner.opacity;
        if (corner.opacity != opacity) {
          throw UnsupportedError('Varying mesh corner opacity needs further qualification.');
        }
        final List<double>? previous = values[key];
        if (previous != null && previous.indexed.any((component) => component.$2 != color.components[component.$1])) {
          throw const FormatException('Neighboring mesh cells have inconsistent shared colors.');
        }
        values[key] = color.components;
      }
    }
    final Map<(_MeshKey, int), List<double>> derivatives = {};
    for (int axis = 0; axis < 2; axis++) {
      final int extent = axis == 0 ? mesh.size.first : mesh.size.second;
      for (final _MeshKey vertex in values.keys) {
        final int coordinate = axis == 0 ? vertex.first : vertex.second;
        if (coordinate == 0 || coordinate == extent) {
          continue;
        }
        final _MeshKey before = _meshNeighbor(vertex, axis, -1);
        final _MeshKey after = _meshNeighbor(vertex, axis, 1);
        final _MeshEdge previous = edges[(vertex, before)]!;
        final _MeshEdge next = edges[(vertex, after)]!;
        derivatives[(vertex, axis)] = [
          for (int component = 0; component < space!.componentCount; component++)
            _meshInteriorSlope(values[vertex]![component] - values[before]![component], values[after]![component] - values[vertex]![component], previous, next),
        ];
      }
      for (final _MeshKey vertex in values.keys) {
        final int coordinate = axis == 0 ? vertex.first : vertex.second;
        if (coordinate != 0 && coordinate != extent) {
          continue;
        }
        final int direction = coordinate == 0 ? 1 : -1;
        final _MeshKey inside = _meshNeighbor(vertex, axis, direction);
        final double ownHandle = edges[(vertex, inside)]!.handle;
        final double innerHandle = edges[(inside, vertex)]!.handle;
        derivatives[(vertex, axis)] = [
          for (int component = 0; component < space!.componentCount; component++)
            _meshBoundarySlope((values[inside]![component] - values[vertex]![component]) * direction, derivatives[(inside, axis)]![component], ownHandle, innerHandle),
        ];
      }
    }
    return _MeshColorField._(space: space!, opacity: opacity!, values: values, derivatives: derivatives, edges: edges);
  }

  /// Retains private derived data used to construct immutable cell coefficients.
  const _MeshColorField._({
    required this.space,
    required this.opacity,
    required this.values,
    required this.derivatives,
    required this.edges,
  });

  /// Scales directional derivatives into one original cell's parameter space.
  _MeshColorPatch patch(AiNativeMeshPatch patch) {
    final List<_MeshKey> cyclic = _meshCorners(patch);
    final List<_MeshKey> keys = [cyclic[0], cyclic[1], cyclic[3], cyclic[2]];
    return _MeshColorPatch(
      values: [for (final _MeshKey key in keys) values[key]!],
      first: [
        for (int index = 0; index < 4; index++)
          [for (final double value in derivatives[(keys[index], 0)]!) _meshFinite(value * 3 * edges[(keys[index], keys[index ~/ 2 * 2 + 1 - index % 2])]!.handle)],
      ],
      second: [
        for (int index = 0; index < 4; index++)
          [for (final double value in derivatives[(keys[index], 1)]!) _meshFinite(value * 3 * edges[(keys[index], keys[index % 2 + (index < 2 ? 2 : 0)])]!.handle)],
      ],
    );
  }
}

/// Retains a known device color without converting or flattening source inks.
AiNativeMeshProcessColor? _meshDeviceColor(AiNativeMeshNode corner) {
  final AiNativeMeshProcessSpace? space = switch (corner.colorSpace?.deviceName) {
    'DeviceGray' => .gray,
    'DeviceRGB' => .rgb,
    'DeviceCMYK' => .cmyk,
    _ => null,
  };
  return space == null ? null : AiNativeMeshProcessColor(space: space, components: corner.color);
}

/// Offsets one grid coordinate to its adjacent vertex.
_MeshKey _meshNeighbor(_MeshKey vertex, int axis, int direction) => (first: vertex.first + (axis == 0 ? direction : 0), second: vertex.second + (axis == 1 ? direction : 0));

/// Limits an interior slope component using its projected boundary travel.
double _meshInteriorSlope(double left, double right, _MeshEdge previous, _MeshEdge next) {
  if (left == 0 || right == 0 || left.sign != right.sign || previous.travel == 0 || next.travel == 0) {
    return 0;
  }
  final double slope = _meshFinite((left / previous.travel + right / next.travel) / 2);
  final double limit = math.min(left.abs() / previous.handle, right.abs() / next.handle);
  return _meshFinite(slope.sign * math.min(slope.abs(), limit));
}

/// Extrapolates a boundary slope with a secant-based monotonicity constraint.
double _meshBoundarySlope(double delta, double inside, double ownHandle, double innerHandle) {
  if (ownHandle == 0) {
    throw UnsupportedError('Mesh boundary color interpolation requires nonzero endpoint tangents.');
  }
  final double secant = _meshFinite(delta / (3 * ownHandle));
  final double slope = _meshFinite(2 * secant - inside * innerHandle / ownHandle);
  return slope.sign == secant.sign ? _meshFinite(secant.sign * math.min(slope.abs(), 3 * secant.abs())) : 0;
}

/// One bicubic process field with zero mixed derivatives at its four corners.
final class _MeshColorPatch {
  /// Corner components in rectangular order: 00, 10, 01, 11.
  final List<List<double>> values;

  /// First-axis parameter derivatives in the same corner order.
  final List<List<double>> first;

  /// Second-axis parameter derivatives in the same corner order.
  final List<List<double>> second;

  /// Retains private precomputed coefficients without source mutation.
  const _MeshColorPatch({
    required this.values,
    required this.first,
    required this.second,
  });

  /// Converts corner Hermite data to a tensor with zero mixed derivatives.
  List<List<double>> get controlPoints {
    final List<List<double>> grid = List.generate(16, (_) => List.filled(values.first.length, 0.0));
    for (int corner = 0; corner < 4; corner++) {
      final int horizontal = corner.isEven ? 0 : 3;
      final int vertical = corner ~/ 2 == 0 ? 0 : 3;
      final int inwardHorizontal = horizontal == 0 ? 1 : 2;
      final int inwardVertical = vertical == 0 ? 1 : 2;
      for (int component = 0; component < values.first.length; component++) {
        final double value = values[corner][component];
        final double alongFirst = first[corner][component] * (horizontal == 0 ? 1 : -1) / 3;
        final double alongSecond = second[corner][component] * (vertical == 0 ? 1 : -1) / 3;
        grid[horizontal * 4 + vertical][component] = value;
        grid[inwardHorizontal * 4 + vertical][component] = _meshFinite(value + alongFirst);
        grid[horizontal * 4 + inwardVertical][component] = _meshFinite(value + alongSecond);
        grid[inwardHorizontal * 4 + inwardVertical][component] = _meshFinite(value + alongFirst + alongSecond);
      }
    }
    return List.unmodifiable(grid.map(List<double>.unmodifiable));
  }

  /// Evaluates the field and clamps components to the process-space range.
  List<double> sample(double horizontal, double vertical) {
    final List<double> a = _meshHermite(horizontal);
    final List<double> b = _meshHermite(vertical);
    final List<double> result = List.filled(values.first.length, 0);
    for (int corner = 0; corner < 4; corner++) {
      final int row = corner % 2;
      final int column = corner ~/ 2;
      for (int component = 0; component < result.length; component++) {
        result[component] += values[corner][component] * a[row] * b[column] + first[corner][component] * a[row + 2] * b[column] + second[corner][component] * a[row] * b[column + 2];
      }
    }
    return [for (final double value in result) _meshFinite(value).clamp(0.0, 1.0)];
  }
}

/// Returns cubic Hermite value and derivative basis coefficients.
List<double> _meshHermite(double value) {
  final double square = value * value;
  final double cube = square * value;
  return [2 * cube - 3 * square + 1, -2 * cube + 3 * square, cube - 2 * square + value, cube - square];
}
