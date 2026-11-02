part of 'package:aikit/src/model/ai_native_records.dart';

/// Known scalar assignments at a complete appearance boundary in both views.
///
/// Keys are `fill`, `stroke`, or the native scalar operator (`Xy`, `A`, `Xw`,
/// `O`, `R`, `XR`, `D`, `Ap`, `J`, `j`, `w`, `M`, `d`). Missing assignments
/// have no inferred defaults. Unknown sets distinguish values invalidated by
/// unresolved source state from values never assigned in the inspected source.
final class AiNativeAppearanceState {
  /// Definite authoritative native assignments, including qualified named styles.
  final Map<String, AiNativeInstruction> native;

  /// Definite printable assignments, excluding private authoring changes.
  final Map<String, AiNativeInstruction> printing;

  /// Native values invalidated by an unresolved operation or conditional effect.
  final Set<String> unknownNative;

  /// Printable values invalidated by an unresolved public operation.
  final Set<String> unknownPrinting;

  /// Freezes source-owned values without composing artwork or executing filters.
  AiNativeAppearanceState._(_NativeShapeInputs state)
    : native = Map.unmodifiable(state.native),
      printing = Map.unmodifiable(state.printing),
      unknownNative = Set.unmodifiable(state.nativeOrigins.keys.where((key) => !state.native.containsKey(key) && state.nativeOrigins[key]! >= 0)),
      unknownPrinting = Set.unmodifiable(state.printingOrigins.keys.where((key) => !state.printing.containsKey(key) && state.printingOrigins[key]! >= 0));
}

/// Qualified native artwork and its separate host-composed appearance.
///
/// Obtain this handle through `AiNativeAppearances.artworkFor`. It binds source
/// ownership without composing the style or guaranteeing that every edit is safe.
/// Ordinary enclosing clipping groups remain outside this pair; their masks and
/// metadata stay unchanged when the host supplies a replacement printing group.
final class AiNativeAppearanceArtwork {
  /// Immutable appearance snapshot that issued this handle.
  final AiNativeAppearances _owner;

  /// Exact named-style application at the end of the authoring pair.
  final AiNativeResourceUse use;

  /// Enclosing setup declaration, or null for document-body artwork.
  ///
  /// Resource coordinates and printing ownership stay local to this declaration.
  /// Binding alone does not establish instance dependencies or qualify edits.
  final AiNativeArtworkResource? resource;

  /// Authoritative private path or group, separate from its printing expansion.
  final AiNativeItem authoring;

  /// Single authoritative contour, or null for a grouped appearance.
  AiNativePath? get path => switch (authoring) {
    final AiNativePath path => path,
    _ => null,
  };

  /// Authoritative group tree, or null for a single-contour appearance.
  AiNativeGroup? get group => switch (authoring) {
    final AiNativeGroup group => group,
    _ => null,
  };

  /// Complete ordinary group supplied by the application for compatibility.
  final AiNativeGroup printingGroup;

  /// Complete host-composed process images belonging only to the printing view.
  ///
  /// Native paths and groups remain authoritative. Samples have no native object
  /// identities or cache metadata, and the package does not compose their pixels.
  late final List<AiNativeRaster> printingRasters = List.unmodifiable(_printingRasters(resource?._structure.drawing ?? _owner.structure.drawing, printingGroup));

  /// Optional authoring metadata retained with the native path or outer group.
  final AiNativeContainer? dictionary;

  /// Optional metadata attached to the derived group.
  final AiNativeContainer? printingDictionary;

  /// Retained outer and nested object dictionaries, in source order.
  final List<AiNativeContainer> metadata;

  /// Qualified named applications retained inside the authoritative group.
  ///
  /// Select them explicitly through `AiNativeAppearanceReplacement.uses` when
  /// editing a child style. They share this owner's complete printing group.
  final List<AiNativeResourceUse> nestedUses;

  /// Authoritative group contours with local compound and clipping ownership.
  ///
  /// Empty for single-path and live-shape owners. These snapshots expose masks
  /// for host composition; ordinary path-edit APIs still reject private paths.
  final List<AiNativePathTopology> groupContours;

  /// Exact private child paths or groups bound to the retained named uses.
  final Map<AiNativeResourceUse, AiNativeItem> _nestedOwners;

  /// Live-shape parameters when present; ordinary artwork does not invent a handler.
  final AiLiveShape? liveShape;

  /// First owned source byte, including an optional outer panel flag.
  final int start;

  /// Qualified commands whose unchanged assignments delimit state dependencies.
  final List<AiNativeInstruction> _commands;

  /// State each outer or nested application may inherit at its source endpoint.
  final Map<int, Set<String>> _styleReads;

  /// Freezes a validated source association without copying native geometry.
  AiNativeAppearanceArtwork._({
    required this._owner,
    required this.use,
    required this.resource,
    required this.authoring,
    required this.printingGroup,
    required this.dictionary,
    required this.printingDictionary,
    required this.liveShape,
    required this.start,
    List<AiNativeContainer> metadata = const [],
    Map<AiNativeResourceUse, AiNativeItem> nestedOwners = const {},
    List<AiNativePathTopology> groupContours = const [],
    required List<AiNativeInstruction> commands,
    required Map<int, Set<String>> styleReads,
  }) : metadata = List.unmodifiable({?dictionary, ?printingDictionary, ...metadata}.toList()..sort((first, second) => first.start.compareTo(second.start))),
       nestedUses = List.unmodifiable(nestedOwners.keys),
       groupContours = List.unmodifiable(groupContours),
       _nestedOwners = Map.unmodifiable(nestedOwners),
       _commands = List.unmodifiable(commands),
       _styleReads = Map.unmodifiable(styleReads.map((position, reads) => MapEntry(position, Set<String>.unmodifiable(reads))));

  /// Direct masks on this owner, private children or authoritative live shape.
  ///
  /// Printing metadata is excluded. Each mask retains exact native artwork and
  /// explicit flags; nested masks inside its Art field stay part of that payload.
  late final List<AiNativeOpacityMask> opacityMasks = List.unmodifiable([
    for (final AiNativeContainer record in metadata)
      if (!identical(record, printingDictionary))
        if (record['AI9_Mask']?.container case final AiNativeContainer mask) _qualifiedAppearanceMask(_owner, mask),
  ]);

  /// Returns the exact private path or group carrying one current opacity mask.
  ///
  /// Mask-local descendants stay inside their Art payload. The returned carrier
  /// shares this owner's complete printing replacement and source revision.
  AiNativeItem authoringForMask({required AiNativeOpacityMask mask}) {
    if (!opacityMasks.contains(mask)) {
      throw ArgumentError('The opacity mask does not belong to this appearance owner.');
    }
    final AiNativeContainer record = metadata.singleWhere((record) => identical(record['AI9_Mask']?.container, mask.record));
    if (identical(record, dictionary)) {
      return authoring;
    }
    final AiNativeDrawing drawing = resource?._structure.drawing ?? _owner.structure.drawing;
    final List<AiNativeItem> candidates = [
      ...drawing.paths.where((path) => path.start >= authoring.start && path.end <= authoring.end),
      ...drawing.groups.where((group) => group.start >= authoring.start && group.end <= authoring.end),
    ].where((item) => identical(drawing._objects.forSource(item).dictionary, record)).toList();
    if (candidates.length != 1) {
      throw const FormatException('An appearance opacity mask requires one authoritative carrier.');
    }
    return candidates.single;
  }

  /// Exclusive end of the complete source pair.
  int get end => use.instruction.end;

  /// Returns the exact native path or group targeted by an owned style use.
  ///
  /// Child artwork shares the enclosing [printingGroup]; it does not gain an
  /// independent printing replacement or source-pair boundary.
  AiNativeItem authoringFor({required AiNativeResourceUse use}) =>
      identical(use, this.use) ? authoring : _nestedOwners[use] ?? (throw ArgumentError('The style use does not belong to this appearance owner.'));
}

/// A host-supplied printing group for one qualified appearance user.
///
/// Native geometry and metadata stay authoritative. The group must preserve
/// outgoing printing state and the source's point-count convention. Bounds are
/// computed by the host, including strokes, effects and inherited transforms.
final class AiNativeAppearanceReplacement {
  /// Copies host bytes before validating them against the owning source limits.
  AiNativeAppearanceReplacement({required this.artwork, List<AiNativeResourceUse>? uses, required List<int> bytes, required this.bounds})
    : uses = List.unmodifiable(uses ?? [artwork.use]),
      _bytes = Uint8List.fromList(bytes) {
    if (this.uses.isEmpty || this.uses.toSet().length != this.uses.length || this.uses.any((use) => !identical(use, artwork.use) && !artwork.nestedUses.contains(use))) {
      throw ArgumentError('Appearance replacements require distinct uses belonging to their complete printing owner.');
    }
    if (bytes.any((byte) => byte < 0 || byte > 255) || [bounds.left, bounds.bottom, bounds.right, bounds.top].any((coordinate) => coordinate.abs() > 9007199254740991)) {
      throw ArgumentError('Appearance replacements require byte data and portable ink bounds.');
    }
  }

  /// Wraps composed pixels and explicit blending with proven state restoration.
  ///
  /// This replaces only an ordinary body's complete printing view. The caller
  /// supplies already-composed samples; native authoring and matching PDF changes
  /// belong to the enclosing transaction. Unknown outgoing transparency rejects.
  factory AiNativeAppearanceReplacement.raster({
    required AiNativeAppearanceArtwork artwork,
    required AiNativeRasterSamples samples,
    required List<double> matrix,
    required AiNativeTransparency transparency,
    required AiBoundingBox bounds,
  }) => _nativeRasterAppearanceReplacement(artwork, samples, matrix, transparency, bounds);

  /// Current source association obtained from the appearance snapshot to edit.
  final AiNativeAppearanceArtwork artwork;

  /// Explicit outer or nested uses covered by this complete printing owner.
  ///
  /// Defaults to the outer [AiNativeAppearanceArtwork.use]. Supply every selected
  /// child use here instead of repeating the same printing group in a batch.
  /// In `dependents`, these references retain their original styles and names.
  final List<AiNativeResourceUse> uses;

  /// Owned group bytes without document boundaries or private metadata.
  final Uint8List _bytes;

  /// Complete ink bounds in the owning document or resource coordinate system.
  ///
  /// Resource-local bounds do not enlarge document bounds or change pattern tile
  /// rectangles. Dependent body replacements supply their own document ink bounds.
  final AiBoundingBox bounds;

  /// Immutable supplied printing bytes.
  Uint8List get bytes => _bytes.asUnmodifiableView();
}
