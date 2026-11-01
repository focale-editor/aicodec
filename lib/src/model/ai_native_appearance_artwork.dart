part of 'package:aikit/src/model/ai_native_records.dart';

/// One qualified native contour and its separate host-composed appearance.
///
/// Obtain this handle through `AiNativeAppearances.artworkFor`. It binds source
/// ownership without composing the style or guaranteeing that every edit is safe.
final class AiNativeAppearanceArtwork {
  /// Immutable appearance snapshot that issued this handle.
  final AiNativeAppearances _owner;

  /// Exact named-style application at the end of the authoring pair.
  final AiNativeResourceUse use;

  /// Authoritative private contour, independent of its derived printing paths.
  final AiNativePath path;

  /// Complete ordinary group supplied by the application for compatibility.
  final AiNativeGroup printingGroup;

  /// Optional authoring metadata retained with the native contour.
  final AiNativeContainer? dictionary;

  /// Optional metadata attached to the derived group.
  final AiNativeContainer? printingDictionary;

  /// Live-shape parameters when present; ordinary paths do not invent a handler.
  final AiLiveShape? liveShape;

  /// First owned source byte, including an optional outer panel flag.
  final int start;

  /// Qualified commands whose unchanged assignments delimit state dependencies.
  final List<AiNativeInstruction> _commands;

  /// State the saved style may inherit before assigning its own values.
  final Set<String> _styleReads;

  /// Freezes a validated source association without copying native geometry.
  AiNativeAppearanceArtwork._({
    required this._owner,
    required this.use,
    required this.path,
    required this.printingGroup,
    required this.dictionary,
    required this.printingDictionary,
    required this.liveShape,
    required this.start,
    required List<AiNativeInstruction> commands,
    required Set<String> styleReads,
  }) : _commands = List.unmodifiable(commands),
       _styleReads = Set.unmodifiable(styleReads);

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
