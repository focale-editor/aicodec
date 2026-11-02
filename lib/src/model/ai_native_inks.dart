part of 'package:aikit/src/model/ai_native_records.dart';

/// One byte-named ink shared by literal paints, gradients and mesh declarations.
final class AiNativeInk {
  /// Exact native ink identity, independent of palette display labels.
  final Uint8List nameBytes;

  /// Literal fill/stroke applications, including styles and palette cells.
  final List<AiNativeInstruction> paints;

  /// Every gradient definition whose authoritative or compatibility stops use it.
  final List<AiNativeGradientDefinition> gradients;

  /// Mesh packets declaring this ink in a Separation or NChannel color space.
  final List<AiNativeMesh> meshes;

  /// Retains immutable references from one owning source snapshot.
  AiNativeInk._({required List<int> nameBytes, required List<AiNativeInstruction> paints, required List<AiNativeGradientDefinition> gradients, required List<AiNativeMesh> meshes})
    : nameBytes = Uint8List.fromList(nameBytes).asUnmodifiableView(),
      paints = List.unmodifiable(paints),
      gradients = List.unmodifiable(gradients),
      meshes = List.unmodifiable(meshes);
}

/// Global named-ink alternatives with explicit representation synchronization.
final class AiNativeInks {
  /// Source appearance graph, also owning supplied printing replacement handles.
  final AiNativeAppearances appearances;

  /// Exact native snapshot shared by every returned reference.
  AiNativeRecords get records => appearances.structure.drawing.records;

  /// Inks found in qualified literal paint, gradient and mesh representations.
  final List<AiNativeInk> inks;

  /// Complete printing owners required by a global redefinition.
  ///
  /// The global operation takes a complete printing revision so resource-driven
  /// expansions cannot retain stale pixels. Independent owners may explicitly
  /// retain their printing bytes. Nested applications share their outer owner.
  late final List<AiNativeAppearanceArtwork> printingOwners = List.unmodifiable(_nativeInkPrintingOwners(appearances));

  /// Inspects named references without converting alternatives or native tints.
  factory AiNativeInks.decode({required AiNativeRecords records}) => _readNativeInks(records);

  /// Keeps graph handles and references in one immutable namespace.
  AiNativeInks._({required this.appearances, required List<AiNativeInk> inks}) : inks = List.unmodifiable(inks);

  /// Identifies printing owners that may consume this ink directly or indirectly.
  ///
  /// Includes style/pattern/gradient dependencies and inherited paint consumed by
  /// either source interpretation. Unresolved input cannot prove independence.
  /// Returned handles belong to [printingOwners] in this immutable snapshot.
  /// Unsupported global reference scopes throw before returning a partial result.
  List<AiNativeAppearanceArtwork> affectedPrintingOwners({required AiNativeInk ink}) => _nativeInkAffectedPrintingOwners(this, ink);

  /// Redefines all qualified uses of one ink while retaining names and tints.
  ///
  /// Supply each device alternative used by the source; none is converted or
  /// inferred. Gradient ramps are keyed by one current definition per affected
  /// gradient name, covering all its printing/nonprinting banks. Artwork uses
  /// handles from [printingOwners]. The host supplies matching complete printing
  /// and PDF content; AiKit does not render or establish visual equivalence.
  /// [retainedArtwork] may cover unaffected owners instead of replacements; their
  /// complete source printing remains untouched. Affected owners cannot be retained.
  ///
  /// Unknown references, text-engine dependencies, color-book payloads,
  /// conditional ownership and unsupported mesh attachments reject atomically.
  /// Reacquire handles from the returned immutable snapshot before another edit.
  AiNativeInks redefine({
    required AiNativeInk ink,
    AiColor? cmyk,
    AiColor? rgb,
    AiColor? gray,
    Map<AiNativeGradientDefinition, List<AiNativeGradientRamp>> ramps = const {},
    List<AiNativeAppearanceReplacement> artwork = const [],
    List<AiNativeAppearanceArtwork> retainedArtwork = const [],
  }) => _redefineNativeInk(this, ink, cmyk, rgb, gray, ramps, artwork, retainedArtwork);
}
