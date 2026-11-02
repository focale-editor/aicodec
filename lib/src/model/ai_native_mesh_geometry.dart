part of 'package:aikit/src/model/ai_native_records.dart';

/// Changes explicit native coordinates or weights of one source node occurrence.
///
/// Shared corner positions must be changed in every occurrence in the same
/// transaction. Handles retain their source order; no tangent welding is inferred.
final class AiNativeMeshNodeGeometry {
  /// Node from the selected immutable mesh snapshot.
  final AiNativeMeshNode node;

  /// New position, or null to retain the source coordinates.
  final ({double x, double y})? position;

  /// First native handle, or null to retain it.
  final ({double x, double y})? firstHandle;

  /// Second native handle, or null to retain it.
  final ({double x, double y})? secondHandle;

  /// Explicit source-order weights, or null to retain them exactly.
  final List<double>? weights;

  /// Validates supplied coordinates without normalizing rational weights.
  AiNativeMeshNodeGeometry({required this.node, this.position, this.firstHandle, this.secondHandle, List<double>? weights}) : weights = weights == null ? null : List.unmodifiable(weights) {
    if (position == null && firstHandle == null && secondHandle == null && weights == null || weights != null && weights.length != node.weights.length) {
      throw ArgumentError('Mesh geometry requires a change with the source weight arity.');
    }
    _validateMeshCoordinates([?position, ?firstHandle, ?secondHandle], weights ?? const []);
  }
}

/// Explicit native node data for a newly supplied Cartesian patch topology.
final class AiNativeMeshNodeDefinition {
  /// Corner or intermediate node classification.
  final AiNativeMeshNodeKind kind;

  /// Native drawing coordinates, with y increasing upwards.
  final ({double x, double y}) position;

  /// First control point in native source order.
  final ({double x, double y}) firstHandle;

  /// Second control point in native source order.
  final ({double x, double y}) secondHandle;

  /// Two weights for a corner, one for an anchor or subdivision point.
  final List<double> weights;

  /// Explicit process color of a newly authored corner.
  final AiNativeMeshProcessColor? processColor;

  /// Retained source color space, including exact named ink declarations.
  final AiNativeMeshColorSpace? retainedColorSpace;

  /// Exact retained source components or tints; absent for process definitions.
  final List<double>? retainedComponents;

  /// Corner opacity; null for intermediate nodes.
  final double? opacity;

  /// Creates a process-colored corner with explicit geometry and weights.
  AiNativeMeshNodeDefinition.corner({
    required this.position,
    required this.firstHandle,
    required this.secondHandle,
    required List<double> weights,
    required AiNativeMeshProcessColor color,
    required double opacity,
  }) : kind = .corner,
       weights = List.unmodifiable(weights),
       processColor = color,
       retainedColorSpace = null,
       retainedComponents = null,
       opacity = opacity {
    _validateMeshCoordinates([position, firstHandle, secondHandle], weights);
    if (weights.length != 2 || !_gradientUnit(opacity)) {
      throw ArgumentError('A mesh corner requires two weights and normalized opacity.');
    }
  }

  /// Creates an uncolored anchor or subdivision point in cyclic boundary order.
  AiNativeMeshNodeDefinition.boundary({required this.kind, required this.position, required this.firstHandle, required this.secondHandle, required double weight})
    : weights = List.unmodifiable([weight]),
      processColor = null,
      retainedColorSpace = null,
      retainedComponents = null,
      opacity = null {
    _validateMeshCoordinates([position, firstHandle, secondHandle], [weight]);
    if (kind == .corner) {
      throw ArgumentError('Colored corners require their own definition.');
    }
  }

  /// Copies literal node data without changing source ink names or precision.
  factory AiNativeMeshNodeDefinition.fromSource({required AiNativeMeshNode node}) {
    if (node.kind == .corner && node.colorSpace!.componentCount == null) {
      throw UnsupportedError('Mesh authoring requires a qualified corner color space.');
    }
    _validateMeshCoordinates([node.position, node.firstHandle, node.secondHandle], node.weights);
    return AiNativeMeshNodeDefinition._(
      kind: node.kind,
      position: node.position,
      firstHandle: node.firstHandle,
      secondHandle: node.secondHandle,
      weights: node.weights,
      retainedColorSpace: node.colorSpace,
      retainedComponents: node.kind == .corner ? node.color : null,
      opacity: node.opacity,
    );
  }

  /// Owns already checked values for source preservation and geometry copies.
  AiNativeMeshNodeDefinition._({
    required this.kind,
    required this.position,
    required this.firstHandle,
    required this.secondHandle,
    required List<double> weights,
    this.processColor,
    this.retainedColorSpace,
    List<double>? retainedComponents,
    required this.opacity,
  }) : weights = List.unmodifiable(weights),
       retainedComponents = retainedComponents == null ? null : List.unmodifiable(retainedComponents);

  /// Replaces geometry while preserving the exact process or named-ink paint.
  AiNativeMeshNodeDefinition withGeometry({({double x, double y})? position, ({double x, double y})? firstHandle, ({double x, double y})? secondHandle, List<double>? weights}) {
    _validateMeshCoordinates([?position, ?firstHandle, ?secondHandle], weights ?? const []);
    if (weights != null && weights.length != this.weights.length) {
      throw ArgumentError('Mesh node replacement must retain the weight arity.');
    }
    return AiNativeMeshNodeDefinition._(
      kind: kind,
      position: position ?? this.position,
      firstHandle: firstHandle ?? this.firstHandle,
      secondHandle: secondHandle ?? this.secondHandle,
      weights: weights ?? this.weights,
      processColor: processColor,
      retainedColorSpace: retainedColorSpace,
      retainedComponents: retainedComponents,
      opacity: opacity,
    );
  }
}

/// One complete supplied patch with explicit native indices and boundary nodes.
final class AiNativeMeshPatchDefinition {
  /// First Cartesian patch index.
  final int firstIndex;

  /// Second Cartesian patch index.
  final int secondIndex;

  /// Cyclic nodes; exactly four are colored corners, with optional intermediates.
  final List<AiNativeMeshNodeDefinition> nodes;

  /// Explicit numeric `/R` payload, or null to omit that field.
  ///
  /// This is retained native data, not an inferred rotation or subdivision rule.
  /// The host supplies it with the new topology; AiKit does not interpolate it.
  final List<double>? nativeParameters;

  /// Captures a complete patch without synthesizing any omitted native fields.
  AiNativeMeshPatchDefinition({required this.firstIndex, required this.secondIndex, required List<AiNativeMeshNodeDefinition> nodes, required List<double>? nativeParameters})
    : nodes = List.unmodifiable(nodes),
      nativeParameters = nativeParameters == null ? null : List.unmodifiable(nativeParameters) {
    if (firstIndex < 0 || secondIndex < 0 || firstIndex > 9007199254740991 || secondIndex > 9007199254740991 || nodes.where((node) => node.kind == .corner).length != 4) {
      throw ArgumentError('A mesh patch requires portable indices and four colored corners.');
    }
    _validateMeshCoordinates(const [], nativeParameters ?? const []);
  }

  /// Retains known source node and numeric parameter data for a replacement grid.
  factory AiNativeMeshPatchDefinition.fromSource({required AiNativeMeshPatch patch, int? firstIndex, int? secondIndex}) {
    if (patch.fields.any((field) => !const {'P', 'R', 'CS', 'N', 'A', 'S', 'E'}.contains(field.key)) || patch.fields.where((field) => field.key == 'R').length > 1) {
      throw UnsupportedError('Mesh topology replacement cannot discard unknown or repeated patch fields.');
    }
    final AiNativeMeshField? parameters = patch.fields.where((field) => field.key == 'R').firstOrNull;
    return AiNativeMeshPatchDefinition(
      firstIndex: firstIndex ?? patch.firstIndex,
      secondIndex: secondIndex ?? patch.secondIndex,
      nodes: [for (final AiNativeMeshNode node in patch.nodes) AiNativeMeshNodeDefinition.fromSource(node: node)],
      nativeParameters: parameters == null ? null : _meshNumbers(parameters),
    );
  }
}

/// A complete immutable Cartesian replacement grid without tessellation.
final class AiNativeMeshDefinition {
  /// First patch extent, excluding the extra boundary vertex.
  final int firstSize;

  /// Second patch extent.
  final int secondSize;

  /// Complete source-order patches with unique indices and coherent corners.
  final List<AiNativeMeshPatchDefinition> patches;

  /// Validates coverage before allocating a topology index from caller data.
  AiNativeMeshDefinition({required this.firstSize, required this.secondSize, required List<AiNativeMeshPatchDefinition> patches}) : patches = List.unmodifiable(patches) {
    if (firstSize < 1 || secondSize < 1 || patches.length ~/ secondSize != firstSize || patches.length % secondSize != 0) {
      throw ArgumentError('Mesh replacement dimensions must match explicit patch coverage.');
    }
    final Set<(int, int)> cells = {};
    final Map<(int, int), ({double x, double y})> vertices = {};
    for (final AiNativeMeshPatchDefinition patch in patches) {
      if (patch.firstIndex >= firstSize || patch.secondIndex >= secondSize || !cells.add((patch.firstIndex, patch.secondIndex))) {
        throw ArgumentError('Mesh replacement patches must have distinct in-range indices.');
      }
      final List<(int, int)> positions = [
        (patch.firstIndex, patch.secondIndex),
        (patch.firstIndex + 1, patch.secondIndex),
        (patch.firstIndex + 1, patch.secondIndex + 1),
        (patch.firstIndex, patch.secondIndex + 1),
      ];
      for (final (int index, AiNativeMeshNodeDefinition node) in patch.nodes.where((node) => node.kind == .corner).indexed) {
        final (int, int) key = positions[index];
        if (vertices.containsKey(key) && vertices[key] != node.position) {
          throw ArgumentError('Shared mesh corner occurrences must agree exactly.');
        }
        vertices[key] = node.position;
      }
    }
  }

  /// Copies only qualified literal topology, preserving per-corner source inks.
  factory AiNativeMeshDefinition.fromSource({required AiNativeMesh mesh}) {
    _validateMeshTopologyFields(mesh);
    return AiNativeMeshDefinition(
      firstSize: mesh.size.first,
      secondSize: mesh.size.second,
      patches: [for (final AiNativeMeshPatch patch in mesh.patches) AiNativeMeshPatchDefinition.fromSource(patch: patch)],
    );
  }
}

/// Requires every topology-dependent field to belong to one explicit patch.
void _validateMeshTopologyFields(AiNativeMesh mesh) {
  final Set<AiNativeMeshField> patchFields = {for (final AiNativeMeshPatch patch in mesh.patches) ...patch.fields};
  if (mesh.fields.any(
    (field) =>
        !const {'Version', 'Type', 'Size', 'Data', 'CS', 'P', 'R', 'N', 'A', 'S', 'E'}.contains(field.key) ||
        !patchFields.contains(field) && !const {'Version', 'Type', 'Size', 'Data', 'CS'}.contains(field.key),
  )) {
    throw UnsupportedError('Mesh topology cannot discard unknown or unowned native fields.');
  }
}

/// Keeps coordinates, parameters and weights finite and portable on VM and Web.
void _validateMeshCoordinates(List<({double x, double y})> points, List<double> values) {
  if ([
    for (final ({double x, double y}) point in points) ...[point.x, point.y],
    ...values,
  ].any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
    throw ArgumentError('Mesh geometry requires finite portable coordinates and weights.');
  }
}
