part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Explicit editable content in a newly authored private appearance tree.
sealed class AiNativeAppearanceElementDefinition {
  /// Prevents mutable external implementations of the authoring grammar.
  const AiNativeAppearanceElementDefinition();
}

/// An independently painted editable contour inside an appearance group.
final class AiNativeAppearancePathDefinition extends AiNativeAppearanceElementDefinition {
  /// Complete geometry, flags, fresh metadata and optional direct process paint.
  final AiNativePathDefinition definition;

  /// Existing named style owning the paints of an unpainted private contour.
  final List<int>? styleNameBytes;

  /// Retains the immutable path definition without composing its printing view.
  const AiNativeAppearancePathDefinition({required this.definition}) : styleNameBytes = null;

  /// Authors an unpainted child with an existing independently editable style.
  AiNativeAppearancePathDefinition.styled({required this.definition, required List<int> styleNameBytes}) : styleNameBytes = List.unmodifiable(styleNameBytes) {
    if (definition.filled || definition.stroked || styleNameBytes.isEmpty || styleNameBytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Styled appearance children require unpainted geometry and a nonempty literal style name.');
    }
  }
}

/// An unpainted prefix contour defining one private group's clipping region.
final class AiNativeAppearanceClipDefinition {
  /// Complete native geometry, with exactly one initial moveto.
  final List<AiPathSegment> segments;

  /// Explicit clipping closure, independent of the unpainted `N` operator.
  final AiNativePathMask mask;

  /// Whether the clip uses even-odd winding instead of nonzero winding.
  final bool evenOdd;

  /// Whether to emit the native point-count convention before the contour.
  final bool counted;

  /// Optional source label for the editable mask contour.
  final List<int>? nameBytes;

  /// Optional fresh native identity, independent of the group's identity.
  final List<int>? identifierBytes;

  /// Owns portable contour data without painting or composing the clipped result.
  AiNativeAppearanceClipDefinition({
    required List<AiPathSegment> segments,
    this.mask = .closed,
    this.evenOdd = false,
    this.counted = true,
    List<int>? nameBytes,
    List<int>? identifierBytes,
  }) : segments = List.unmodifiable(segments),
       nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
       identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (mask == .none ||
        segments.isEmpty ||
        segments.first.operator != 'm' ||
        segments.skip(1).any((segment) => segment.operator == 'm') ||
        segments.any((segment) => segment.coordinates.any((value) => value.abs() > 9007199254740991)) ||
        [...?nameBytes, ...?identifierBytes].any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Appearance clips require one portable contour, an explicit clipping role and byte metadata.');
    }
  }
}

/// An ordinary or clipped editable group with optional existing named appearance.
final class AiNativeAppearanceGroupDefinition extends AiNativeAppearanceElementDefinition {
  /// Ordered native children, retained separately from the printing expansion.
  final List<AiNativeAppearanceElementDefinition> children;

  /// One complete image, mesh or live shape instead of vector child definitions.
  ///
  /// The ordinary wrapper retains independent identity, appearance and masks.
  final AiNativeAppearanceLeafDefinition? leaf;

  /// Optional unpainted prefix mask, separate from the ordered content children.
  final AiNativeAppearanceClipDefinition? clip;

  /// Existing style name; required for the root of a complete appearance pair.
  final List<int>? styleNameBytes;

  /// Optional native String label, independent of the style's resource name.
  final List<int>? nameBytes;

  /// Optional fresh portable object identity.
  final List<int>? identifierBytes;

  /// Explicit object visibility, independent of child visibility.
  final bool hidden;

  /// Explicit object locking, independent of child flags.
  final bool locked;

  /// Freezes children and source strings before any document offsets change.
  AiNativeAppearanceGroupDefinition({
    required List<AiNativeAppearanceElementDefinition> children,
    this.clip,
    this.leaf,
    List<int>? styleNameBytes,
    List<int>? nameBytes,
    List<int>? identifierBytes,
    this.hidden = false,
    this.locked = false,
  }) : children = List.unmodifiable(children),
       styleNameBytes = styleNameBytes == null ? null : List.unmodifiable(styleNameBytes),
       nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
       identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (leaf != null && (children.isNotEmpty || clip != null)) {
      throw ArgumentError('An appearance leaf requires an unclipped wrapper without other children.');
    }
    if ([styleNameBytes, nameBytes, identifierBytes].whereType<List<int>>().any((bytes) => bytes.any((byte) => byte < 0 || byte > 255)) || styleNameBytes?.isEmpty == true) {
      throw ArgumentError('Appearance trees require literal byte names and nonempty style names.');
    }
  }
}

/// One retained or newly authored child in a complete appearance tree revision.
final class AiNativeAppearanceTreeChild {
  /// Current path or group retained with its exact metadata and style uses.
  final AiNativeItem? source;

  /// New typed subtree with fresh identities and already declared styles.
  final AiNativeAppearanceElementDefinition? definition;

  /// Planned children of a retained or newly created group, excluding its clip.
  ///
  /// Null keeps the entire subtree. Omitted children are removed, and retained
  /// children may move between groups among the complete owners selected in the transaction.
  final List<AiNativeAppearanceTreeChild>? children;

  /// Replaces a complete non-text payload while retaining its wrapper metadata.
  final AiNativeAppearanceLeafDefinition? leaf;

  /// Retains source data and optionally changes the children of a retained group.
  AiNativeAppearanceTreeChild.retain({required AiNativeItem source, List<AiNativeAppearanceTreeChild>? children, this.leaf})
    : source = source,
      definition = null,
      children = children == null ? null : List.unmodifiable(children) {
    if (leaf != null && (source is! AiNativeGroup || children != null)) {
      throw ArgumentError('Leaf replacement requires a group without a child plan.');
    }
    if (source is! AiNativePath && source is! AiNativeGroup || children != null && source is! AiNativeGroup) {
      throw ArgumentError('Retained appearance children require paths or groups; only groups have replacement children.');
    }
  }

  /// Inserts independently authored data instead of borrowing an existing identity.
  const AiNativeAppearanceTreeChild.create({required AiNativeAppearanceElementDefinition this.definition}) : source = null, children = null, leaf = null;

  /// Creates a fresh group around retained or new children from the selected owners.
  ///
  /// The group definition supplies metadata, clipping and its optional style;
  /// its typed children must be empty because this plan supplies their ownership.
  AiNativeAppearanceTreeChild.group({required AiNativeAppearanceGroupDefinition definition, required List<AiNativeAppearanceTreeChild> children})
    : definition = definition,
      leaf = null,
      source = null,
      children = List.unmodifiable(children) {
    if (definition.children.isNotEmpty) {
      throw ArgumentError('A new group child plan supplies its children separately from its metadata definition.');
    }
  }
}

/// One complete printing owner and its final ordered private child hierarchy.
final class AiNativeAppearanceTreeChange {
  /// Current complete group with host-supplied printing and final ink bounds.
  final AiNativeAppearanceReplacement artwork;

  /// Retained or fresh children, excluding the root's attached clipping contour.
  final List<AiNativeAppearanceTreeChild> children;

  /// Replacement payload when the complete root itself represents one leaf.
  final AiNativeAppearanceLeafDefinition? leaf;

  /// Freezes a child plan for an atomic multi-owner topology transaction.
  AiNativeAppearanceTreeChange({required this.artwork, required List<AiNativeAppearanceTreeChild> children, this.leaf}) : children = List.unmodifiable(children);
}
