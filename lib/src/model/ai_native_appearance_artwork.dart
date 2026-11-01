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
  /// These uses remain unchanged when editing this outer owner. They do not
  /// receive independent printing ownership from this handle.
  final List<AiNativeResourceUse> nestedUses;

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
    List<AiNativeResourceUse> nestedUses = const [],
    required List<AiNativeInstruction> commands,
    required Map<int, Set<String>> styleReads,
  }) : metadata = List.unmodifiable({?dictionary, ?printingDictionary, ...metadata}.toList()..sort((first, second) => first.start.compareTo(second.start))),
       nestedUses = List.unmodifiable(nestedUses),
       _commands = List.unmodifiable(commands),
       _styleReads = Map.unmodifiable(styleReads.map((position, reads) => MapEntry(position, Set<String>.unmodifiable(reads))));

  /// Exclusive end of the complete source pair.
  int get end => use.instruction.end;
}

/// A host-supplied printing group for one qualified appearance user.
///
/// Native geometry and metadata stay authoritative. The group must preserve
/// outgoing printing state and the source's point-count convention. Bounds are
/// computed by the host, including strokes, effects and inherited transforms.
final class AiNativeAppearanceReplacement {
  /// Current source association obtained from the appearance snapshot to edit.
  final AiNativeAppearanceArtwork artwork;

  /// Owned group bytes without document boundaries or private metadata.
  final Uint8List _bytes;

  /// Complete ink bounds in y-up native document coordinates.
  final AiBoundingBox bounds;

  /// Copies host bytes before validating them against the owning source limits.
  AiNativeAppearanceReplacement({required this.artwork, required List<int> bytes, required this.bounds}) : _bytes = Uint8List.fromList(bytes) {
    if (bytes.any((byte) => byte < 0 || byte > 255) || [bounds.left, bounds.bottom, bounds.right, bounds.top].any((coordinate) => coordinate.abs() > 9007199254740991)) {
      throw ArgumentError('Appearance replacements require byte data and portable ink bounds.');
    }
  }

  /// Immutable supplied printing bytes.
  Uint8List get bytes => _bytes.asUnmodifiableView();
}
