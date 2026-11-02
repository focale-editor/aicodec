part of 'package:aikit/src/model/ai_native_records.dart';

/// One source-backed `value /key X#` mesh record, including unknown fields.
final class AiNativeMeshField extends AiNativeItem {
  /// Complete instruction, retaining private prefixes through source offsets.
  final AiNativeInstruction instruction;

  /// Name of the field without its leading slash.
  final String key;

  /// Exact value tokens, excluding the field name and executable operator.
  final List<AiToken> values;

  /// Retains a checked field without interpreting unknown operands.
  AiNativeMeshField._({required this.instruction})
    : key = instruction.operands.last.lexeme.substring(1),
      values = List.unmodifiable(instruction.operands.take(instruction.operands.length - 1)),
      super(start: instruction.start, end: instruction.end);
}

/// One named mesh ink and its explicit device-color alternative.
final class AiNativeMeshInk {
  /// Exact name bytes without an assumed character encoding.
  final Uint8List nameBytes;

  /// DeviceGray, DeviceRGB or DeviceCMYK alternative space.
  final String deviceName;

  /// Source alternative components, without tinting or color conversion.
  final List<double> components;

  /// Retains one checked ink declaration.
  AiNativeMeshInk._({required List<int> nameBytes, required this.deviceName, required List<double> components})
    : nameBytes = Uint8List.fromList(nameBytes).asUnmodifiableView(),
      components = List.unmodifiable(components);
}

/// Original mesh color-space operands without implicit conversion of inks.
final class AiNativeMeshColorSpace {
  /// Explicit source declaration; null denotes the initial DeviceGray space.
  final AiNativeMeshField? field;

  /// Recognized device-space name, or null for named and other color spaces.
  final String? deviceName;

  /// Known component count; null when the declaration needs further semantics.
  final int? componentCount;

  /// Separation or NChannel declarations in lexical order; empty otherwise.
  ///
  /// NChannel builds its component list from the operand stack, reversing this
  /// order. Use [AiNativeMeshNode.inkTints] to associate inks with components.
  final List<AiNativeMeshInk> inks;

  /// Retains named ink alternatives and order in [field], without flattening.
  const AiNativeMeshColorSpace._({required this.field, required this.deviceName, required this.componentCount, this.inks = const []});
}

/// The three node records retained in a native mesh's cyclic boundary order.
enum AiNativeMeshNodeKind {
  /// A colored corner joining two edges of a patch.
  corner,

  /// An original path anchor between colored corners.
  anchor,

  /// A subdivision point between colored corners.
  subdivision,
}

/// A mesh boundary node with source coordinates and unconverted color values.
final class AiNativeMeshNode {
  /// Original record and exact numeric token spans.
  final AiNativeMeshField field;

  /// Corner, original anchor or subdivision point.
  final AiNativeMeshNodeKind kind;

  /// Position in native drawing coordinates, with y increasing upwards.
  final ({double x, double y}) position;

  /// First control point in the native record's order.
  final ({double x, double y}) firstHandle;

  /// Second control point in the native record's order.
  final ({double x, double y}) secondHandle;

  /// Source weights in order: two for corners, one for other nodes.
  ///
  /// Non-unit weights survive inspection; this reader does not evaluate them.
  final List<double> weights;

  /// Source-space components or named-ink tints; empty for non-corner nodes.
  final List<double> color;

  /// Explicit version-two corner opacity; null for non-corner nodes.
  final double? opacity;

  /// Space in force at this corner; null for non-corner nodes.
  final AiNativeMeshColorSpace? colorSpace;

  /// Named inks paired with their tints in the corner's component order.
  ///
  /// NChannel declarations are consumed in reverse lexical order. Separation
  /// has one component. Other spaces and uncolored nodes return an empty list;
  /// no spot ink is converted to its device-color alternative.
  List<({AiNativeMeshInk ink, double tint})> get inkTints {
    final List<AiNativeMeshInk> inks = colorSpace?.inks ?? const [];
    return List.unmodifiable(inks.reversed.indexed.map((item) => (ink: item.$2, tint: color[item.$1])));
  }

  /// Creates an immutable view after checking the version-specific layout.
  AiNativeMeshNode._({
    required this.field,
    required this.kind,
    required this.position,
    required this.firstHandle,
    required this.secondHandle,
    required List<double> weights,
    required List<double> color,
    required this.opacity,
    required this.colorSpace,
  }) : weights = List.unmodifiable(weights),
       color = List.unmodifiable(color);
}

/// One mesh patch, retaining intermediate nodes and all its source fields.
final class AiNativeMeshPatch extends AiNativeItem {
  /// First native grid index, without imposing a canvas row/column direction.
  final int firstIndex;

  /// Second native grid index.
  final int secondIndex;

  /// Cyclic source order, including anchors before the first colored corner.
  final List<AiNativeMeshNode> nodes;

  /// Complete patch fields, including `P`, `R`, color changes and closing `E`.
  ///
  /// The `R` value and unknown extensions remain source-backed and uninterpreted.
  final List<AiNativeMeshField> fields;

  /// Retains a complete patch after checking its four colored corners.
  AiNativeMeshPatch._({required this.firstIndex, required this.secondIndex, required List<AiNativeMeshNode> nodes, required List<AiNativeMeshField> fields})
    : nodes = List.unmodifiable(nodes),
      fields = List.unmodifiable(fields),
      super(start: fields.first.start, end: fields.last.end);
}

/// A version-two Cartesian mesh with its original patch topology and colors.
final class AiNativeMesh extends AiNativeItem {
  /// Native mesh schema version, independently of the Illustrator application.
  final int version;

  /// First and second native grid extents, each counting patches.
  final ({int first, int second}) size;

  /// Complete source fields, including declarations outside patches.
  final List<AiNativeMeshField> fields;

  /// Patches in source order, without merging duplicated neighboring corners.
  final List<AiNativeMeshPatch> patches;

  /// Whether the opening `/Mesh X!` belongs to private authoring data.
  final bool isPrivate;

  /// Checked logical vertices, retaining every neighboring cell's corner copy.
  ///
  /// Adjacent corner coordinates must agree exactly; inconsistent grids throw
  /// [FormatException] instead of welding distinct positions by proximity.
  late final List<AiNativeMeshVertex> vertices = _meshVertices(this);

  /// Creates a complete source-backed mesh without rebuilding its appearance.
  AiNativeMesh._({
    required super.start,
    required super.end,
    required this.version,
    required this.size,
    required this.isPrivate,
    required List<AiNativeMeshField> fields,
    required List<AiNativeMeshPatch> patches,
  }) : fields = List.unmodifiable(fields),
       patches = List.unmodifiable(patches);
}

/// One logical Cartesian grid vertex and all its source corner occurrences.
final class AiNativeMeshVertex {
  /// First grid coordinate, from zero through the mesh's first patch extent.
  final int firstIndex;

  /// Second grid coordinate, from zero through the second patch extent.
  final int secondIndex;

  /// Source corner copies, including their distinct incoming/outgoing handles.
  final List<AiNativeMeshNode> corners;

  /// Creates a vertex after checking agreement of duplicate positions.
  AiNativeMeshVertex._({required this.firstIndex, required this.secondIndex, required List<AiNativeMeshNode> corners}) : corners = List.unmodifiable(corners);

  /// Shared native position, without merging control points or source colors.
  ({double x, double y}) get position => corners.first.position;
}

/// Device color model for an explicitly supplied mesh vertex color.
enum AiNativeMeshProcessSpace {
  /// One gray component, with zero black and one white.
  gray,

  /// Red, green and blue components.
  rgb,

  /// Cyan, magenta, yellow and black ink components.
  cmyk;

  /// Native color-space name used by mesh declarations.
  String get nativeName => switch (this) {
    .gray => 'DeviceGray',
    .rgb => 'DeviceRGB',
    .cmyk => 'DeviceCMYK',
  };

  /// Number of normalized color components.
  int get componentCount => switch (this) {
    .gray => 1,
    .rgb => 3,
    .cmyk => 4,
  };
}

/// Explicit process color for a mesh corner, independent of its opacity.
final class AiNativeMeshProcessColor {
  /// Selected device model; no automatic source-to-target conversion occurs.
  final AiNativeMeshProcessSpace space;

  /// Finite normalized components in the device model's native order.
  final List<double> components;

  /// Creates a checked immutable replacement color.
  AiNativeMeshProcessColor({required this.space, required List<double> components}) : components = List.unmodifiable(components) {
    if (components.length != space.componentCount || components.any((value) => !_gradientUnit(value))) {
      throw ArgumentError('Invalid native mesh process color.');
    }
  }
}

/// A selected logical vertex's new color, opacity, or both.
final class AiNativeMeshVertexPaint {
  /// Vertex owned by the mesh being edited, from its current snapshot.
  final AiNativeMeshVertex vertex;

  /// Explicit new device color; null retains every source color declaration.
  final AiNativeMeshProcessColor? color;

  /// Replacement named-ink tints in [AiNativeMeshNode.inkTints] order.
  ///
  /// Mutually exclusive with [color]. Every source corner must have the same
  /// ordered ink names and alternatives. Declarations remain byte-for-byte
  /// intact; this never converts named inks to process colors.
  final List<double>? tints;

  /// New normalized opacity; null retains each occurrence's source opacity.
  final double? opacity;

  /// Requires at least one finite paint change.
  AiNativeMeshVertexPaint({required this.vertex, this.color, List<double>? tints, this.opacity}) : tints = tints == null ? null : _checkedMeshTints(vertex, tints) {
    if (color == null && tints == null && opacity == null || color != null && tints != null || opacity != null && !_gradientUnit(opacity!)) {
      throw ArgumentError('A mesh vertex paint edit needs either process color or ink tints, and/or normalized opacity.');
    }
  }
}

/// Bounds replacement tint storage by the selected source corner's arity.
List<double> _checkedMeshTints(AiNativeMeshVertex vertex, List<double> tints) {
  if (tints.isEmpty || tints.length != vertex.corners.first.color.length || tints.any((value) => !_gradientUnit(value))) {
    throw ArgumentError('Mesh tints must match the source component count and lie between zero and one.');
  }
  return List.unmodifiable(tints);
}

/// Bounded native mesh inventory independent of the PDF compatibility view.
///
/// Version-two Cartesian geometry is inspected, including additional anchors,
/// changing color spaces, opacity and opaque extensions. Named inks retain
/// their full declarations and source tints. Reading does not render,
/// weld neighboring nodes or reconstruct mesh-dependent appearance caches.
final class AiNativeMeshes {
  /// Source snapshot owning every mesh and field span.
  final AiNativeRecords records;

  /// Meshes in source order, including resource artwork unless [bodyOnly].
  final List<AiNativeMesh> meshes;

  /// Whether setup and trailer resources were excluded from this inventory.
  final bool bodyOnly;

  /// Reads explicit mesh packets outside procedures, literals and embedded files.
  ///
  /// Unknown versions or topology types reject access with [UnsupportedError].
  /// Malformed packets, inconsistent extents and truncated nodes throw
  /// [FormatException]. All input bytes remain available in [records].
  factory AiNativeMeshes.decode({required AiNativeRecords records, bool bodyOnly = false}) => AiNativeMeshes._(records: records, bodyOnly: bodyOnly, meshes: _readNativeMeshes(records, bodyOnly));

  /// Retains an immutable inventory and its original resource policy.
  AiNativeMeshes._({required this.records, required this.bodyOnly, required List<AiNativeMesh> meshes}) : meshes = List.unmodifiable(meshes);

  /// Changes selected logical vertices, updating every neighboring corner copy.
  ///
  /// Color-space switches are local to each changed corner: subsequent source
  /// colors keep their declarations, including Separation and NChannel inks.
  /// Named-ink tint edits retain declarations and require matching ordered inks
  /// across every selected vertex's corner copies.
  /// Geometry, weights, intermediate nodes and unrelated source bytes survive.
  /// Only direct printable body meshes without dependent appearance metadata
  /// are qualified. Unknown fields and unresolved parent appearances reject
  /// the transaction. Exact no-ops return this snapshot.
  ///
  /// This updates native authoring data. The host must regenerate PDF artwork
  /// and other previews before saving; [AiNativeMeshes] does not render meshes.
  AiNativeMeshes paintVertices({required AiNativeMesh mesh, required List<AiNativeMeshVertexPaint> changes}) => _paintMeshVertices(this, mesh, changes);

  /// Edits explicit node positions, source-order handles and rational weights.
  ///
  /// Every changed shared position must agree across its corner occurrences in
  /// the same transaction. Color declarations, intermediate nodes, parameters,
  /// metadata and unrelated bytes survive. Supply complete host ink bounds and
  /// regenerate matching PDF/previews before saving. No mesh is tessellated here.
  AiNativeMeshes editGeometry({required AiNativeMesh mesh, required List<AiNativeMeshNodeGeometry> changes, required AiBoundingBox bounds}) => _editMeshGeometry(this, mesh, changes, bounds);

  /// Maps all native positions and handles through one invertible affine basis.
  ///
  /// Paint, source weights, patch indices and parameters remain unchanged.
  /// Distinct source points cannot silently collapse at numeric precision.
  /// An existing frame angle requires explicit [rotationRadians] from the host.
  AiNativeMeshes transform({required AiNativeMesh mesh, required AiNativeAffineTransform transform, required AiBoundingBox bounds, double? rotationRadians}) =>
      _transformNativeMesh(this, mesh, transform, bounds, rotationRadians);

  /// Replaces the complete Cartesian topology using explicit host-supplied data.
  ///
  /// New dimensions, cells, handles, weights, colors, opacity and numeric patch
  /// parameters are supplied together. The source identity, external metadata
  /// and neighboring artwork survive. Unknown fields, reference-valued patch
  /// parameters and dependent/private/resource owners reject. This is native
  /// serialization, not subdivision, interpolation or a conversion of inks.
  /// An existing frame angle requires explicit [rotationRadians] from the host.
  AiNativeMeshes replaceTopology({required AiNativeMesh mesh, required AiNativeMeshDefinition definition, required AiBoundingBox bounds, double? rotationRadians}) =>
      _replaceMeshTopology(this, mesh, definition, bounds, rotationRadians);
}
