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

/// Original mesh color-space operands without implicit conversion of inks.
final class AiNativeMeshColorSpace {
  /// Explicit source declaration; null denotes the initial DeviceGray space.
  final AiNativeMeshField? field;

  /// Recognized device-space name, or null for named and other color spaces.
  final String? deviceName;

  /// Known component count; null when the declaration needs further semantics.
  final int? componentCount;

  /// Retains named ink alternatives and order in [field], without flattening.
  const AiNativeMeshColorSpace._({required this.field, required this.deviceName, required this.componentCount});
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

/// Bounded native mesh inventory independent of the PDF compatibility view.
///
/// Version-two Cartesian geometry is inspected, including additional anchors,
/// changing color spaces, opacity and opaque extensions. Named inks retain
/// their full declarations and source tints. Reading does not render, edit,
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
}
