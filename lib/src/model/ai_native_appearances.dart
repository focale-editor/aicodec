part of 'package:aikit/src/model/ai_native_records.dart';

/// The native role of a source appearance part, without executing its filter.
enum AiNativeAppearancePartKind {
  /// An ordered stack of appearance parts.
  stack,

  /// An ordered filter chain; its hierarchy must not be flattened into a stack.
  chain,

  /// A built-in fill part.
  fill,

  /// A built-in stroke part whose parameters remain independently qualified.
  stroke,

  /// A qualified native inside/outside stroke descriptor.
  strokeOffset,

  /// A local blend part whose original paint commands remain available.
  blend,

  /// The source artwork passing through the appearance graph.
  conduit,

  /// A plug-in descriptor retained without executing or qualifying its effect.
  effect,

  /// An unknown record or descriptor whose complete source remains available.
  opaque,
}

/// Alignment explicitly established by a qualified native stroke descriptor.
enum AiNativeStrokeAlignment {
  /// A built-in stroke centered on its source contour.
  center,

  /// A native offset stroke aligned inside its contour.
  inside,

  /// A native offset stroke aligned outside its contour.
  outside,
}

/// One literal filter descriptor, preserving both flags without version guesses.
final class AiNativeAppearanceFilter {
  /// Original field, including the exact name and flag tokens.
  final AiNativeEntry field;

  /// Native integer flags in their original order.
  final List<int> flags;

  /// Exact filter-name bytes independent of application text encoding.
  final Uint8List _nameBytes;

  /// Freezes a decoded descriptor without treating its name as a resource link.
  AiNativeAppearanceFilter._({required this.field, required List<int> flags, required List<int> nameBytes}) : flags = List.unmodifiable(flags), _nameBytes = Uint8List.fromList(nameBytes);

  /// Immutable filter-name bytes.
  Uint8List get nameBytes => _nameBytes.asUnmodifiableView();
}

/// A direct paint payload with its exact parameter-field ownership.
final class AiNativeAppearancePaint {
  /// Field in the part's parameter dictionary, including effect-local paints.
  final AiNativeEntry field;

  /// Native commands and gradient instances in the selected paint payload.
  final AiNativePaintStyle style;

  /// Keeps a paint separate from other fills or strokes of the same type.
  const AiNativeAppearancePaint._({required this.field, required this.style});
}

/// One immutable part of an appearance tree, including hidden and unknown parts.
final class AiNativeAppearancePart {
  /// Position in the owning appearance's preorder inventory.
  final int index;

  /// Immediate parent index, or null for the execution root.
  final int? parentIndex;

  /// Direct children in native Part-field order.
  final List<int> childIndices;

  /// Exact source record; extensions and unsupported parameters remain available.
  final AiNativeContainer record;

  /// Structural role without an effect execution or editing guarantee.
  final AiNativeAppearancePartKind kind;

  /// Literal descriptor, or null for an opaque record without one.
  final AiNativeAppearanceFilter? filter;

  /// Explicit local visibility, or null when absent; ancestors remain separate.
  final bool? visible;

  /// Explicit native fill/stroke selector, independent of host UI selection.
  final int? fillOrStroke;

  /// Parameter owner with all unknown fields retained, or null when absent.
  final AiNativeContainer? parameters;

  /// Direct paint payloads in source order, without collapsing repeated fields.
  final List<AiNativeAppearancePaint> paints;

  /// Explicit winding setting of a fill part, or null when absent/unqualified.
  final bool? evenOdd;

  /// Qualified stroke alignment, or null for unknown or incomplete descriptors.
  final AiNativeStrokeAlignment? strokeAlignment;

  /// Freezes owned graph indices and paint payloads after bounded inspection.
  AiNativeAppearancePart._({
    required this.index,
    required this.parentIndex,
    required List<int> childIndices,
    required this.record,
    required this.kind,
    required this.filter,
    required this.visible,
    required this.fillOrStroke,
    required this.parameters,
    required List<AiNativeAppearancePaint> paints,
    required this.evenOdd,
    required this.strokeAlignment,
  }) : childIndices = List.unmodifiable(childIndices),
       paints = List.unmodifiable(paints);
}

/// A source-owned named appearance, with shared uses kept separate from its parts.
final class AiNativeAppearance {
  /// Named declaration and its retained version memberships.
  final AiNativeStructureResource resource;

  /// Original definition, including unknown future style types.
  final AiNativeContainer definition;

  /// Complete preorder tree for an active appearance; empty for a simple style.
  final List<AiNativeAppearancePart> parts;

  /// Plain Paint commands for a SimpleStyle, or null for other definitions.
  final AiNativePaintStyle? simplePaint;

  /// Potential uses, including ambiguous or conditional links to this resource.
  ///
  /// Inspect each resolution before treating the use as uniquely bound. A style
  /// used twice remains one definition; selecting a part does not isolate a user.
  final List<AiNativeResourceUse> uses;

  /// Freezes a definition and its own ordered parts without flattening effects.
  AiNativeAppearance._({required this.resource, required this.definition, required List<AiNativeAppearancePart> parts, required this.simplePaint, required List<AiNativeResourceUse> uses})
    : parts = List.unmodifiable(parts),
      uses = List.unmodifiable(uses);

  /// Resolves an exact part handle from this immutable appearance snapshot.
  AiNativeAppearancePart forSource({required AiNativeContainer record}) =>
      parts.where((part) => identical(part.record, record)).singleOrNull ?? (throw ArgumentError('The part is not owned by this native appearance.'));
}

/// Immutable named appearance graphs and their independent resource references.
///
/// These are native data views. They do not compose paints, execute effects or
/// synchronize printing expansions. Unknown parts retain their original records.
final class AiNativeAppearances {
  /// Source structure owning declarations, uses and version alternatives.
  final AiNativeStructure structure;

  /// Named appearances in declaration order, including duplicate names.
  final List<AiNativeAppearance> styles;

  /// Named style uses with explicit missing/ambiguous/conditional resolution.
  final List<AiNativeResourceUse> uses;

  /// Reads bounded source graphs without converting unknown filters to paint.
  factory AiNativeAppearances.decode({required AiNativeStructure structure}) => _nativeAppearances(structure);

  /// Freezes the complete source inventory.
  AiNativeAppearances._({required this.structure, required List<AiNativeAppearance> styles, required List<AiNativeResourceUse> uses})
    : styles = List.unmodifiable(styles),
      uses = List.unmodifiable(uses);

  /// Returns the uniquely resolved declaration, or null for unresolved uses.
  AiNativeAppearance? resolve({required AiNativeResourceUse use}) {
    if (!uses.contains(use)) {
      throw ArgumentError('The style use is not owned by this appearance snapshot.');
    }
    return use.resolution == .resolved ? styles.singleWhere((style) => identical(style.resource, use.candidates.single)) : null;
  }
}
