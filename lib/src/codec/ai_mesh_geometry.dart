part of 'package:aikit/src/model/ai_native_mesh_interpolation.dart';

/// Native drawing point with immutable coordinates.
typedef _MeshPoint = ({double x, double y});

/// Logical grid vertex independent of its artwork position.
typedef _MeshKey = ({int first, int second});

/// Short vector operations used by bounded tensor construction.
extension _MeshPointMath on _MeshPoint {
  /// Adds a displacement.
  _MeshPoint plus(_MeshPoint other) => (x: x + other.x, y: y + other.y);

  /// Subtracts a point or displacement.
  _MeshPoint minus(_MeshPoint other) => (x: x - other.x, y: y - other.y);

  /// Scales both coordinates.
  _MeshPoint scaled(double factor) => (x: x * factor, y: y * factor);

  /// Computes a checked Euclidean magnitude.
  double get magnitude => _meshFinite(math.sqrt(x * x + y * y));

  /// Projects this vector onto another vector.
  double dot(_MeshPoint other) => _meshFinite(x * other.x + y * other.y);
}

/// Returns a cell's cyclic logical vertices, starting at its declared index.
List<_MeshKey> _meshCorners(AiNativeMeshPatch patch) => [
  (first: patch.firstIndex, second: patch.secondIndex),
  (first: patch.firstIndex + 1, second: patch.secondIndex),
  (first: patch.firstIndex + 1, second: patch.secondIndex + 1),
  (first: patch.firstIndex, second: patch.secondIndex + 1),
];

/// Cubic boundary pieces with their normalized control-polygon partitions.
final class _MeshEdge {
  /// Four controls for each consecutive boundary piece.
  final List<List<_MeshPoint>> pieces;

  /// Strictly increasing piece endpoints, including zero and one.
  final List<double> breaks;

  /// Starting handle length normalized to the complete logical edge.
  final double handle;

  /// Absolute control-polygon travel projected on the starting tangent.
  final double travel;

  /// Measures a directed boundary once for all color evaluations.
  factory _MeshEdge({
    required List<List<_MeshPoint>> pieces,
  }) {
    final List<double> lengths = [for (final List<_MeshPoint> piece in pieces) (piece[1].minus(piece[0])).magnitude + (piece[2].minus(piece[1])).magnitude + (piece[3].minus(piece[2])).magnitude];
    final double total = _meshFinite(lengths.fold(0.0, (sum, value) => sum + value));
    final List<double> breaks = [0];
    double accumulated = 0;
    for (final double length in lengths) {
      accumulated += length;
      final double next = breaks.length == lengths.length ? 1 : accumulated / total;
      if (length <= 0 || !next.isFinite || next <= breaks.last) {
        throw UnsupportedError('Mesh interpolation requires nondegenerate boundary pieces.');
      }
      breaks.add(next);
    }
    final _MeshPoint tangent = pieces.first[1].minus(pieces.first[0]);
    final double magnitude = tangent.magnitude;
    if (magnitude == 0) {
      return _MeshEdge._(pieces: pieces, breaks: breaks, handle: 0, travel: 0);
    }
    final _MeshPoint direction = tangent.scaled(1 / magnitude);
    final double travel = _meshFinite(
      pieces.fold(0.0, (sum, piece) => sum + (piece[1].minus(piece[0])).dot(direction).abs() + (piece[2].minus(piece[1])).dot(direction).abs() + (piece[3].minus(piece[2])).dot(direction).abs()),
    );
    return _MeshEdge._(pieces: pieces, breaks: breaks, handle: _meshFinite(magnitude / breaks[1]), travel: travel);
  }

  /// Retains private derived lists after validating parameter spacing.
  const _MeshEdge._({
    required this.pieces,
    required this.breaks,
    required this.handle,
    required this.travel,
  });

  /// Locates one interval without assuming uniform boundary segments.
  int interval(double parameter) {
    int lower = 0;
    int upper = pieces.length - 1;
    while (lower < upper) {
      final int middle = (lower + upper) ~/ 2;
      if (parameter > breaks[middle + 1]) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    return lower;
  }

  /// Evaluates the piece containing a complete-edge parameter.
  _MeshPoint point(double parameter) {
    final int index = interval(parameter);
    return _meshWeighted(pieces[index], _meshBasis((parameter - breaks[index]) / (breaks[index + 1] - breaks[index])));
  }

  /// Restricts a single piece to endpoints in complete-edge coordinates.
  List<_MeshPoint> restrict(double start, double end) {
    final int index = interval((start + end) / 2);
    final double span = breaks[index + 1] - breaks[index];
    return [for (final List<double> weights in _meshRestriction((start - breaks[index]) / span, (end - breaks[index]) / span)) _meshWeighted(pieces[index], weights)];
  }
}

/// Builds checked shared edges without welding nearby but different geometry.
Map<(_MeshKey, _MeshKey), _MeshEdge> _meshEdges(AiNativeMesh mesh) {
  final Map<(_MeshKey, _MeshKey), _MeshEdge> result = {};

  /// Requires duplicate edges to agree control for control in both directions.
  void retain(_MeshKey first, _MeshKey second, List<List<_MeshPoint>> pieces) {
    final _MeshEdge? previous = result[(first, second)];
    if (previous == null) {
      result[(first, second)] = _MeshEdge(pieces: pieces);
    } else if (previous.pieces.length != pieces.length || pieces.indexed.any((piece) => piece.$2.indexed.any((point) => point.$2 != previous.pieces[piece.$1][point.$1]))) {
      throw const FormatException('Neighboring mesh cells have inconsistent shared boundaries.');
    }
  }

  for (final AiNativeMeshPatch patch in mesh.patches) {
    final List<AiNativeMeshNode> nodes = patch.nodes;
    if (nodes.any((node) => node.weights.any((weight) => weight != 1))) {
      throw UnsupportedError('Mesh interpolation requires unit node weights.');
    }
    final List<_MeshKey> keys = _meshCorners(patch);
    int corner = -1;
    for (int start = 0; start < nodes.length; start++) {
      if (nodes[start].kind != .corner) {
        continue;
      }
      corner++;
      final List<List<_MeshPoint>> pieces = [];
      int current = start;
      while (true) {
        final int following = (current + 1) % nodes.length;
        final AiNativeMeshNode first = nodes[current];
        final AiNativeMeshNode second = nodes[following];
        // Corner handles follow the cell; intermediate handles follow grid axes.
        final _MeshPoint outgoing = first.kind == .corner || corner >= 2 ? first.firstHandle : first.secondHandle;
        final _MeshPoint incoming = second.kind == .corner || corner >= 2 ? second.secondHandle : second.firstHandle;
        pieces.add([first.position, outgoing, incoming, second.position]);
        if (second.kind == .corner) {
          break;
        }
        current = following;
      }
      retain(keys[corner], keys[(corner + 1) % 4], pieces);
      retain(keys[(corner + 1) % 4], keys[corner], [for (final List<_MeshPoint> piece in pieces.reversed) piece.reversed.toList()]);
    }
  }
  return result;
}

/// Evaluates cubic Bernstein coefficients.
List<double> _meshBasis(double value) {
  final double complement = 1 - value;
  return [complement * complement * complement, 3 * value * complement * complement, 3 * value * value * complement, value * value * value];
}

/// Evaluates derivatives of cubic Bernstein coefficients.
List<double> _meshBasisDerivative(double value) => [-3 * (1 - value) * (1 - value), 3 * (1 - value) * (1 - 3 * value), 3 * value * (2 - 3 * value), 3 * value * value];

/// Computes the exact control transformation for a cubic subinterval.
List<List<double>> _meshRestriction(double start, double end) {
  final List<double> first = _meshBasis(start);
  final List<double> last = _meshBasis(end);
  final List<double> firstDerivative = _meshBasisDerivative(start);
  final List<double> lastDerivative = _meshBasisDerivative(end);
  final double span = (end - start) / 3;
  return [
    first,
    [for (int index = 0; index < 4; index++) first[index] + span * firstDerivative[index]],
    [for (int index = 0; index < 4; index++) last[index] - span * lastDerivative[index]],
    last,
  ];
}

/// Sums weighted native points with checked arithmetic.
_MeshPoint _meshWeighted(List<_MeshPoint> points, List<double> weights) {
  double horizontal = 0;
  double vertical = 0;
  for (int index = 0; index < points.length; index++) {
    horizontal += points[index].x * weights[index];
    vertical += points[index].y * weights[index];
  }
  return (x: _meshFinite(horizontal), y: _meshFinite(vertical));
}

/// Partitions compound boundaries and constructs zero-mixed-derivative tensors.
List<AiNativeMeshSurface> _meshSurfaces(AiNativeMeshPatch patch, Map<(_MeshKey, _MeshKey), _MeshEdge> edges) {
  final List<_MeshKey> keys = _meshCorners(patch);
  final List<_MeshEdge> original = [edges[(keys[0], keys[1])]!, edges[(keys[1], keys[2])]!, edges[(keys[3], keys[2])]!, edges[(keys[0], keys[3])]!];
  final bool swapped = original[1].pieces.length > 1 || original[3].pieces.length > 1;
  final List<_MeshEdge> sides = swapped ? [original[3], original[2], original[1], original[0]] : original;
  if (sides[1].pieces.length != 1 || sides[3].pieces.length != 1) {
    throw UnsupportedError('Compound mesh boundaries on both axes need further qualification.');
  }
  final List<double> partitions = {...sides[0].breaks, ...sides[2].breaks}.toList()..sort();

  /// Blends transverse handles and linearly distributes endpoint displacement.
  List<_MeshPoint> transverse(double parameter) {
    final List<_MeshPoint> line = [for (int index = 0; index < 4; index++) sides[3].pieces.single[index].scaled(1 - parameter).plus(sides[1].pieces.single[index].scaled(parameter))];
    final _MeshPoint bottom = sides[0].point(parameter).minus(line.first);
    final _MeshPoint top = sides[2].point(parameter).minus(line.last);
    return [line[0].plus(bottom), line[1].plus(bottom.scaled(2).plus(top).scaled(1 / 3)), line[2].plus(bottom.plus(top.scaled(2)).scaled(1 / 3)), line[3].plus(top)];
  }

  final List<AiNativeMeshSurface> surfaces = [];
  for (int index = 0; index < partitions.length - 1; index++) {
    final double start = partitions[index];
    final double end = partitions[index + 1];
    final List<_MeshPoint> bottom = sides[0].restrict(start, end);
    final List<_MeshPoint> top = sides[2].restrict(start, end);
    final List<_MeshPoint> left = transverse(start);
    final List<_MeshPoint> right = transverse(end);
    final List<_MeshPoint> grid = List.filled(16, (x: 0.0, y: 0.0));
    for (int control = 0; control < 4; control++) {
      grid[control * 4] = bottom[control];
      grid[control * 4 + 3] = top[control];
      grid[control] = left[control];
      grid[12 + control] = right[control];
    }
    for (final (int, int) corner in const [(0, 0), (3, 0), (3, 3), (0, 3)]) {
      final int first = corner.$1 == 0 ? 1 : 2;
      final int second = corner.$2 == 0 ? 1 : 2;
      grid[first * 4 + second] = grid[first * 4 + corner.$2].plus(grid[corner.$1 * 4 + second]).minus(grid[corner.$1 * 4 + corner.$2]);
    }
    surfaces.add(
      AiNativeMeshSurface._(
        patch: patch,
        bounds: swapped ? (firstStart: 0, firstEnd: 1, secondStart: start, secondEnd: end) : (firstStart: start, firstEnd: end, secondStart: 0, secondEnd: 1),
        controlPoints: swapped
            ? [
                for (int first = 0; first < 4; first++)
                  for (int second = 0; second < 4; second++) grid[second * 4 + first],
              ]
            : grid,
      ),
    );
  }
  return surfaces;
}
