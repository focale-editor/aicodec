part of 'package:aicodec/src/model/ai_native_records.dart';

/// Complete host-supplied native mesh and ordinary object attributes.
///
/// Geometry, weights, colors and patch parameters are explicit. The host supplies
/// the ink envelope and matching PDF/previews; no surface is generated here.
final class AiNativeMeshArtworkDefinition {
  /// Explicit Cartesian cells and their node data.
  final AiNativeMeshDefinition mesh;

  /// Complete host-computed ink envelope in native drawing coordinates.
  final AiBoundingBox bounds;

  /// Ordinary object opacity, separate from each corner's opacity.
  final double opacity;

  /// Complete object blending, independent of the individual corner opacities.
  ///
  /// Keep [opacity] at its default when supplying this explicit native tuple.
  final AiNativeTransparency? transparency;

  /// Whether the object is hidden in the native drawing.
  final bool hidden;

  /// Whether native editing locks the object.
  final bool locked;

  /// Explicit object overprint flag.
  final bool overprint;

  /// Optional literal display name, without an inferred encoding.
  final List<int>? nameBytes;

  /// Optional fresh native artwork identity.
  final List<int>? identifierBytes;

  /// Captures portable data without supplying derived appearance defaults.
  AiNativeMeshArtworkDefinition({
    required this.mesh,
    required this.bounds,
    this.opacity = 1,
    this.transparency,
    this.hidden = false,
    this.locked = false,
    this.overprint = false,
    List<int>? nameBytes,
    List<int>? identifierBytes,
  }) : nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
       identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    _nativeTopologyBounds(bounds);
    if (!_gradientUnit(opacity) ||
        transparency != null && opacity != 1 ||
        identifierBytes != null && identifierBytes.isEmpty ||
        [...?nameBytes, ...?identifierBytes].any((value) => value < 0 || value > 255)) {
      throw ArgumentError('Mesh artwork requires unit opacity or explicit transparency without conflicting inputs, and literal metadata bytes.');
    }
  }
}

/// Complete direct mesh owner, including an optional terminator and metadata.
///
/// Ownership qualification does not certify the host's rendering or Illustrator
/// interoperability. Unknown fields and attached appearances stay unqualified.
final class AiNativeMeshArtwork extends AiNativeItem {
  /// Explicit source packet and all of its original node occurrences.
  final AiNativeMesh mesh;

  /// Lexical opening instruction used for source hierarchy lookup.
  final AiNativeInstruction opening;

  /// Exclusively attached ordinary name and identity metadata.
  final AiNativeContainer? dictionary;

  /// Analysis-only state read; never serialized into native source.
  late final AiNativeInstruction _access = AiNativeInstruction._(
    token: AiToken(kind: .executableName, start: start, end: mesh.end, lexeme: 'aikit:mesh'),
    operands: [],
    isPrivate: false,
  );

  /// Retains exact boundaries after validating the packet's complete owner.
  AiNativeMeshArtwork._({required this.mesh, required this.opening, required this.dictionary, required super.end}) : super(start: mesh.start);

  /// Exact native identity bytes when supplied by the source.
  Uint8List? get identifierBytes => dictionary?['AI10_ArtUID']?.container?.entries.single.stringBytes;

  /// Literal display name retaining its original encoding.
  Uint8List? get nameBytes => (dictionary?['AIArtName'] ?? dictionary?['Object name'])?.stringBytes;
}
