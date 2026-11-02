part of 'package:aikit/src/model/ai_native_records.dart';

/// Namespace of a setup artwork declaration, separate from named styles.
enum AiNativeArtworkResourceKind {
  /// Tile artwork declared by the pattern wrapper and its rectangle.
  pattern,

  /// Reusable artwork declared by a symbol wrapper.
  symbol,

  /// Artwork declared by a brush-pattern wrapper.
  brush,
}

/// Exact setup artwork, without promoting its contents to editable body objects.
///
/// Unknown commands, records, annotations and binary payloads remain in the
/// original source. Inspection does not qualify effects, instances or caches.
final class AiNativeArtworkResource {
  /// Shared source reader and lazily inspected image inventory.
  final _NativeArtworkResourceReader _reader;

  /// Resource namespace established by the complete source wrappers.
  final AiNativeArtworkResourceKind kind;

  /// Opening source wrapper, including a pattern's retained display name.
  final AiToken opening;

  /// Matching closing source wrapper.
  final AiToken closing;

  /// Literal declaration name, independently of its display encoding.
  final AiToken name;

  /// Tile rectangle for a pattern, or null for symbols and brushes.
  final AiBoundingBox? bounds;

  /// First byte after the declaration header, including retained whitespace.
  final int artworkStart;

  /// End of the artwork before the pattern terminator or closing wrapper.
  final int artworkEnd;

  /// Enclosing version branches, without selecting a producer target version.
  final List<AiNativeVersionMembership> versions;

  /// Complete projected source tokens inside the artwork interval.
  final List<AiToken> tokens;

  /// Original direct records, retaining unknown fields and nested mask owners.
  final List<AiNativeContainer> metadata;

  /// Known style and gradient applications anywhere in this definition.
  ///
  /// Nested record uses remain separate from direct geometry. This inventory
  /// does not establish complete dependencies of unknown plug-in descriptors.
  final List<AiNativeResourceUse> uses;

  /// Local topology that must not be passed to body mutation APIs.
  late final AiNativeDrawing _drawing = _reader.drawing(this);

  /// Local lexical ownership with original absolute source positions.
  late final AiNativeStructure _structure = AiNativeStructure.decode(drawing: _drawing);

  /// Images inside this declaration, inspected without decoding their pixels.
  ///
  /// Includes images in nested metadata such as opacity masks; [items] retains
  /// those records as records instead of flattening their artwork into the parent.
  late final List<AiNativeRaster> rasters = List.unmodifiable(
    tokens.any((token) => token.kind == .data) ? _pathInterval<AiNativeRaster>(_reader.rasters, artworkStart, artworkEnd, (image) => image.start) : const [],
  );

  /// Freezes a source declaration without rewriting or resolving its instances.
  AiNativeArtworkResource._({
    required this._reader,
    required this.kind,
    required this.opening,
    required this.closing,
    required this.name,
    required this.bounds,
    required this.artworkStart,
    required this.artworkEnd,
    required List<AiNativeVersionMembership> versions,
    required List<AiToken> tokens,
    required List<AiNativeContainer> metadata,
    required List<AiNativeResourceUse> uses,
  }) : versions = List.unmodifiable(versions),
       tokens = List.unmodifiable(tokens),
       metadata = List.unmodifiable(metadata),
       uses = List.unmodifiable(uses);

  /// First byte of the complete resource wrapper.
  int get start => opening.start;

  /// Exclusive end of the complete resource wrapper.
  int get end => closing.end;

  /// Immutable source name bytes, with duplicate names retained independently.
  Uint8List get nameBytes => aiStringBytes(name).asUnmodifiableView();

  /// Whether the declaration wrappers are carried by private source lines.
  bool get isPrivate => _reader.records._projection.isPrivate(opening.start);

  /// Local commands, records, images and version comments in source order.
  List<AiNativeItem> get items => _drawing.items;

  /// Local paths, retaining separate native and printing representations.
  List<AiNativePath> get paths => _drawing.paths;

  /// Local ordinary, compound and clipping groups in closing order.
  List<AiNativeGroup> get groups => _drawing.groups;

  /// Saved local gradient instances without composed colors or ramps.
  List<AiNativeGradient> get gradients => _drawing.gradients;
}

/// Setup artwork definitions and their known style/gradient applications.
///
/// Names are not deduplicated or conflated across namespaces. Body ownership,
/// resource instances and unknown dependency schemas remain separate contracts.
final class AiNativeArtworkResources {
  /// Original structure owning all reference handles and version branches.
  final AiNativeStructure structure;

  /// Complete declarations in original source order.
  final List<AiNativeArtworkResource> resources;

  /// Reads bounded declaration headers without interpreting their artwork.
  factory AiNativeArtworkResources.decode({required AiNativeStructure structure}) => _nativeArtworkResources(structure);

  /// Retains immutable declaration ownership for one source snapshot.
  AiNativeArtworkResources._({required this.structure, required List<AiNativeArtworkResource> resources}) : resources = List.unmodifiable(resources);

  /// Creates a pattern tile, symbol master or brush artwork declaration.
  ///
  /// Supply native [artworkBytes] with complete local groups, metadata and fresh
  /// object/sample identities. Pattern [bounds] are required; other namespaces
  /// have no tile rectangle. Names are byte-exact and unique within their kind.
  /// Symbol masters join every existing symbol panel, or a new CC panel, unless
  /// [addToSymbolList] is false. Brush artwork does not create a brush descriptor.
  /// Literal dependencies and all source limits are checked atomically; the host
  /// retains responsibility for painting instances and composing their PDF views.
  AiNativeArtworkResources create({
    required AiNativeArtworkResourceKind kind,
    required List<int> nameBytes,
    required List<int> artworkBytes,
    AiBoundingBox? bounds,
    bool addToSymbolList = true,
  }) => _createNativeArtworkResource(this, kind, nameBytes, artworkBytes, bounds, addToSymbolList);

  /// Removes unused declarations and matching symbol-panel entries together.
  ///
  /// Supply distinct current handles. Retained pattern/style/brush dependencies,
  /// uncertain identity references, conditional owners and opaque schemas reject.
  /// No dependent artwork, shared style or brush descriptor is silently removed.
  AiNativeArtworkResources remove({required List<AiNativeArtworkResource> resources}) => _removeNativeArtworkResources(this, resources);

  /// Replaces unused native artwork while retaining its name and panel order.
  ///
  /// Referenced definitions require their dependent printing transaction instead.
  /// Explicit [bounds] are required for patterns and forbidden for other kinds.
  /// Existing local identities may remain; new identities must be globally fresh.
  AiNativeArtworkResources replaceUnused({required AiNativeArtworkResource resource, required List<int> artworkBytes, AiBoundingBox? bounds}) =>
      _replaceUnusedNativeArtworkResource(this, resource, artworkBytes, bounds);

  /// Finds the enclosing declaration for an exact known source application.
  ///
  /// Returns null for body, palette or other uses outside an artwork declaration.
  /// Membership does not imply that the application or its effects are editable.
  AiNativeArtworkResource? forUse({required AiNativeResourceUse use}) {
    if (!structure.resourceUses.contains(use)) {
      throw ArgumentError('The reference belongs to a different native snapshot.');
    }
    final int index = _pathOffset(resources, use.instruction.start + 1, (resource) => resource.start) - 1;
    if (index < 0) {
      return null;
    }
    final AiNativeArtworkResource resource = resources[index];
    return use.instruction.start >= resource.artworkStart && use.instruction.end <= resource.artworkEnd ? resource : null;
  }
}
