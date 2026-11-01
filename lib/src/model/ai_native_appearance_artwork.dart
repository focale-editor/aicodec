part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualified native artwork and its separate host-composed appearance.
///
/// Obtain this handle through `AiNativeAppearances.artworkFor`. It binds source
/// ownership without composing the style or guaranteeing that every edit is safe.
final class AiNativeAppearanceArtwork {
  /// Immutable appearance snapshot that issued this handle.
  final AiNativeAppearances _owner;

  /// Exact named-style application at the end of the authoring pair.
  final AiNativeResourceUse use;

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
    required this.authoring,
    required this.printingGroup,
    required this.dictionary,
    required this.printingDictionary,
    required this.liveShape,
    required this.start,
    List<AiNativeContainer> metadata = const [],
    Map<AiNativeResourceUse, AiNativeItem> nestedOwners = const {},
    required List<AiNativeInstruction> commands,
    required Map<int, Set<String>> styleReads,
  }) : metadata = List.unmodifiable({?dictionary, ?printingDictionary, ...metadata}.toList()..sort((first, second) => first.start.compareTo(second.start))),
       nestedUses = List.unmodifiable(nestedOwners.keys),
       _nestedOwners = Map.unmodifiable(nestedOwners),
       _commands = List.unmodifiable(commands),
       _styleReads = Map.unmodifiable(styleReads.map((position, reads) => MapEntry(position, Set<String>.unmodifiable(reads))));

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
  /// Current source association obtained from the appearance snapshot to edit.
  final AiNativeAppearanceArtwork artwork;

  /// Explicit outer or nested uses edited through this complete printing owner.
  ///
  /// Defaults to the outer [AiNativeAppearanceArtwork.use]. Supply every selected
  /// child use here instead of repeating the same printing group in a batch.
  final List<AiNativeResourceUse> uses;

  /// Owned group bytes without document boundaries or private metadata.
  final Uint8List _bytes;

  /// Complete ink bounds in y-up native document coordinates.
  final AiBoundingBox bounds;

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

  /// Immutable supplied printing bytes.
  Uint8List get bytes => _bytes.asUnmodifiableView();
}
