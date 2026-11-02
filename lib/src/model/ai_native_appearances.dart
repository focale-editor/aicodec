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

  /// A native calligraphic nib and its independently qualified stroke paint.
  calligraphic,

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

/// Explicit advanced stroke data without computed dash lengths or defaults.
final class AiNativeStrokeSettings {
  /// Exact native dictionary, including unqualified future fields.
  final AiNativeContainer record;

  /// Saved schema version, or null when the producer omitted it.
  final int? version;

  /// Saved `BSDashAdj` flag, or null when no adjustment was specified.
  ///
  /// The application composes adjusted dashes; the kit retains the literal flag.
  final bool? adjustDashes;

  /// Captures source values without qualifying every future schema for editing.
  const AiNativeStrokeSettings._({required this.record, required this.version, required this.adjustDashes});
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

  /// Advanced options of a stroke part, independent of its literal dash array.
  final AiNativeStrokeSettings? strokeSettings;

  /// Fixed calligraphic parameters, rejecting device-dependent nib settings.
  AiNativeCalligraphicPaint? get calligraphic => kind == .calligraphic ? AiNativeCalligraphicPaint._decode(record) : null;

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
    required this.strokeSettings,
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
/// Inspection does not compose paints or execute effects. Qualified edits attach
/// expansions supplied by the host. Unknown parts retain their original records.
final class AiNativeAppearances {
  /// Inspects several complete body endpoints with one bounded source traversal.
  ///
  /// Owners must be distinct current complete pairs. Results retain the supplied
  /// handles as keys and distinguish known assignments from unresolved values.
  Map<AiNativeAppearanceArtwork, AiNativeAppearanceState> statesAfterArtwork({required List<AiNativeAppearanceArtwork> artwork}) {
    final List<AiNativeAppearanceArtwork> selected = _selectedBodyAppearanceArtwork(this, artwork);
    final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(structure.drawing, selected.map((owner) => owner.end), clipping: true, appearanceArtwork: _nativeBodyAppearanceArtwork(this));
    return Map.unmodifiable({for (final AiNativeAppearanceArtwork owner in selected) owner: AiNativeAppearanceState._(states[owner.end]!)});
  }

  /// Inspects resolved source state after a body pair or before its printing image.
  ///
  /// Handles must belong to this snapshot. With `beforeRaster`, the selected
  /// raster must be one of the complete owner's printing images. Named-style
  /// effects are qualified without rendering; unqualified roles reject instead
  /// of inventing outgoing values. Missing values remain explicitly absent.
  AiNativeAppearanceState stateAtArtwork({required AiNativeAppearanceArtwork artwork, AiNativeRaster? beforeRaster}) {
    _selectedBodyAppearanceArtwork(this, [artwork]);
    if (beforeRaster != null && !artwork.printingRasters.contains(beforeRaster)) {
      throw ArgumentError('Appearance state requires a current owned printing raster.');
    }
    final int position = beforeRaster?.instruction.start ?? artwork.end;
    return AiNativeAppearanceState._(_shapeCopyInputs(structure.drawing, [position], clipping: true, appearanceArtwork: _nativeBodyAppearanceArtwork(this))[position]!);
  }

  /// Source structure owning declarations, uses and version alternatives.
  final AiNativeStructure structure;

  /// Named appearances in declaration order, including duplicate names.
  final List<AiNativeAppearance> styles;

  /// Named style uses with explicit missing/ambiguous/conditional resolution.
  final List<AiNativeResourceUse> uses;

  /// Reads bounded source graphs without converting unknown filters to paint.
  factory AiNativeAppearances.decode({required AiNativeStructure structure}) => _nativeAppearances(structure);

  /// Setup patterns, symbols and brush artwork containing known style applications.
  ///
  /// Resource edits require complete printing owners, dependent representations
  /// and qualified whole-source references in addition to this local inventory.
  late final AiNativeArtworkResources artworkResources = AiNativeArtworkResources.decode(structure: structure);

  /// Unique unconditional pattern names, indexed once when a paint needs them.
  late final Set<String> _patternNames = _nativeAppearancePatternNames(this);

  /// Qualified mask handles cached by exact immutable source record.
  final Map<AiNativeContainer, AiNativeOpacityMask> _opacityMasks = {};

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

  /// Binds a named use to its native artwork and separate printing group.
  ///
  /// Live shapes, private paths and private groups share this ownership contract.
  /// Access private child uses through the enclosing owner's `nestedUses`; they
  /// share its printing group rather than accepting an independent binding here.
  /// Setup artwork exposes its enclosing `resource`, with local geometry and
  /// original global style handles. Binding alone does not qualify mutations or
  /// dependent instances. Unknown metadata and conditional owners reject.
  AiNativeAppearanceArtwork artworkFor({required AiNativeResourceUse use}) => _nativeAppearanceArtwork(this, use);

  /// Creates an unused named style from explicit newly authored appearance parts.
  ///
  /// Names must be fresh across declarations and references. Children use
  /// `AiNativeAppearanceChild.create`; retaining or copying source parts requires
  /// their separate ownership contract. Creation preserves body artwork and
  /// needs no printing replacement until a style is applied to an object.
  AiNativeAppearances createStyle({required List<int> nameBytes, required AiNativeAppearancePartDefinition execution}) => _createNativeAppearanceStyle(this, nameBytes, execution);

  /// Deletes unused uniquely declared styles after qualifying all references.
  ///
  /// Supply current distinct handles. Any selected name still referenced by
  /// body artwork, retained resources or a conditional use rejects atomically.
  /// Opaque dependency scopes reject rather than being treated as unused.
  AiNativeAppearances removeStyles({required List<AiNativeAppearance> styles}) => _removeNativeAppearanceStyles(this, styles);

  /// Applies an existing style to selected body appearance applications.
  ///
  /// Each supplied replacement owns one complete printing group; its `uses`
  /// select outer or private child applications. Native geometry, masks and
  /// identities remain attached. Unselected users keep their original style.
  /// The host supplies printing/PDF composition for the new style. Resource-local
  /// applications need dependent-instance propagation and reject here.
  AiNativeAppearances applyStyle({required AiNativeAppearance appearance, required List<AiNativeAppearanceReplacement> artwork}) => _applyNativeAppearanceStyle(this, appearance, artwork);

  /// Gives independent private contours their first named style application.
  ///
  /// Supply current child paths and exactly their complete body printing owners.
  /// Direct contour paints become unpainted geometry; the existing named style
  /// supplies the appearance. Metadata, masks, identities, geometry and sibling
  /// order remain attached. Native scalar outputs are restored for following
  /// children and outer artwork, with unresolved dependencies rejected atomically.
  /// Already styled paths use `applyStyle`; compound and clipping contours retain
  /// their separate contracts. Save with the matching host-composed PDF.
  AiNativeAppearances applyStyleToPaths({required AiNativeAppearance appearance, required List<AiNativePath> paths, required List<AiNativeAppearanceReplacement> artwork}) =>
      _applyNativeAppearanceChildStyle(this, appearance, paths, artwork);

  /// Replaces private group children while retaining selected source subtrees.
  ///
  /// Supply the complete owner's printing replacement and an ordered child plan.
  /// Retained handles occur once and belong to this owner; nested group plans may
  /// reparent them. Clipping contours remain attached to their original groups.
  /// Omitted children and their masks leave together after reference validation.
  /// Fresh typed subtrees require fresh identities and declared named styles.
  /// Source metadata, known inherited inputs and outgoing scalar state remain
  /// preserved. The host supplies matching PDF content on save.
  AiNativeAppearances replaceArtworkChildren({required AiNativeAppearanceReplacement artwork, required List<AiNativeAppearanceTreeChild> children}) => replaceArtworkTrees(
    changes: [AiNativeAppearanceTreeChange(artwork: artwork, children: children)],
  );

  /// Revises complete group trees together, allowing retained children to move.
  ///
  /// Each source and destination owner must have one complete printing replacement.
  /// Retained children occur once across all plans; source metadata, styles, masks
  /// and identities travel with them. Omitted children are deleted only after
  /// document-wide reference checks. Complete roots and clipping contours retain
  /// their ownership. All changes either succeed together or leave this snapshot
  /// unchanged. Supply a matching host-composed compatibility PDF when saving.
  AiNativeAppearances replaceArtworkTrees({required List<AiNativeAppearanceTreeChange> changes}) => _replaceNativeAppearanceTrees(this, changes);

  /// Inserts a complete host-authored native/printing appearance pair.
  ///
  /// Bytes contain optional explicit scalar state, one printing group, its
  /// `6 () XW` boundary, private authoring artwork/metadata and one final public
  /// named-style application. Styles must already resolve in this snapshot.
  /// Object identities must be fresh. Native geometry and printing are supplied
  /// by the host; the kit validates ownership without rendering either one.
  /// The returned snapshot exposes the new pair through `artworkFor`.
  AiNativeAppearances createArtwork({required List<int> bytes, required AiBoundingBox bounds, AiNativeGroup? parent, AiLayer? layer}) =>
      _createNativeAppearanceArtwork(this, bytes, bounds, parent, layer);

  /// Authors an editable private group tree with a supplied complete printing view.
  ///
  /// Root and optional child styles must already exist. Process paths retain
  /// independent flags and paints; fresh identities are checked atomically across
  /// the whole inserted tree. Optional group clips emit unpainted prefix contours
  /// with their own counts, winding and metadata inside native clipping scopes.
  /// The host supplies printing bytes and matching PDF.
  AiNativeAppearances createGroupArtwork({
    required AiNativeAppearanceGroupDefinition definition,
    required List<int> printingBytes,
    required AiBoundingBox bounds,
    AiNativeGroup? parent,
    AiLayer? layer,
  }) => _createNativeAppearanceTree(this, definition, printingBytes, bounds, parent, layer);

  /// Authors one editable private contour with an existing named appearance.
  ///
  /// The definition must be unpainted: its fill and stroke are null. The named
  /// style owns the visible paints; geometry, closure, flags, counts and fresh
  /// metadata belong to the contour. Its bounds describe the complete host ink,
  /// including the style. Printing bytes contain a separate complete group and
  /// the host supplies the matching PDF when saving. No wrapper group is added
  /// to the native authoring tree. Masks can subsequently target `owner.path`.
  AiNativeAppearances createPathArtwork({
    required AiNativePathDefinition definition,
    required List<int> styleNameBytes,
    required List<int> printingBytes,
    AiNativeGroup? parent,
    AiLayer? layer,
  }) => _createNativeAppearancePath(this, definition, styleNameBytes, printingBytes, parent, layer);

  /// Converts an ordinary contour into a complete named native appearance.
  ///
  /// Supply a current independent path, unpainted authoring geometry and a
  /// complete host printing group. The existing metadata, XML identity, point
  /// count convention, parent and stacking slot remain attached. Geometry,
  /// winding, locking and visibility use the supplied values. The named style
  /// must already resolve and owns the paints. Dynamic shapes, gradient owners,
  /// private descendants and unresolved metadata require their own contracts.
  /// Outgoing native and printing state is restored for neighboring artwork;
  /// unresolved dependencies reject atomically. Save with a matching host PDF.
  AiNativeAppearances convertPathArtwork({
    required AiNativePath path,
    required AiArtworkPath artwork,
    required AiBoundingBox bounds,
    required List<int> styleNameBytes,
    required List<int> printingBytes,
    bool hidden = false,
  }) => _convertNativeAppearancePath(this, path, artwork, bounds, styleNameBytes, printingBytes, hidden);

  /// Removes complete native/printing body owners and their child applications.
  ///
  /// Supply distinct current `artworkFor` handles. Shared styles remain declared.
  /// Both representations, owned metadata and qualified masks leave together;
  /// explicit outgoing state is retained for following artwork. Unknown effects
  /// must be overwritten before use. Deleting identities additionally requires
  /// a qualified document reference scope, including identified mask descendants.
  /// Resource-local owners require dependent-instance lifecycle transactions.
  /// Supply a matching compatibility PDF when saving the resulting document.
  AiNativeAppearances removeArtwork({required List<AiNativeAppearanceArtwork> artwork}) => _removeNativeAppearanceArtwork(this, artwork);

  /// Renames private paths and groups without changing their rendering or identity.
  ///
  /// Supply current authoring handles and exactly their complete body owners.
  /// Existing name aliases retain their scalar types; callers supply bytes in
  /// the source encoding. Missing names acquire an `AIArtName` String field.
  /// Printing, style uses, XML identities and mask artwork remain unchanged, so
  /// this nonvisual transaction does not require new printing or PDF content.
  /// Live shapes and resource-local owners retain their separate contracts.
  AiNativeAppearances renameArtworkObjects({required Map<AiNativeItem, List<int>> names, required List<AiNativeAppearanceArtwork> artwork}) => _renameNativeAppearanceObjects(this, names, artwork);

  /// Duplicates complete body owners immediately after their original source.
  ///
  /// Both native and printable geometry, child applications, masks and live-shape
  /// alternatives are copied together. Styles remain shared. Supply one fresh
  /// XML identity per identified metadata container, including mask descendants;
  /// raster sample-cache identities are renewed automatically without changing
  /// samples. Source inputs and following state stay separate in each native and
  /// printing interpretation. The host composes the corresponding PDF on save.
  AiNativeAppearances duplicateArtwork({required List<AiNativeAppearanceArtwork> artwork, Map<AiNativeContainer, List<int>> identifiers = const {}}) =>
      _duplicateNativeAppearanceArtwork(this, artwork, identifiers);

  /// Relocates one complete body owner without changing its geometry or identities.
  ///
  /// Supply at most one destination: before/after another complete owner,
  /// beforeObject/afterObject an ordinary artwork handle, or a parent group/layer
  /// whose last child receives the artwork. Ordinary anchors include their point
  /// counts and metadata; private or printing descendants cannot be anchors.
  /// With none, append
  /// to the document body. Public ordinary/clipping parents are qualified;
  /// private, compound, derived and applied-appearance parents reject.
  /// Changing inherited flags, group depth, layers or clipping ancestry requires
  /// `inheritParentAppearance`. The host supplies current ink bounds and the
  /// recomposed PDF, including changed clipping and stacking. Both slots retain
  /// observable native/printing state; unresolved dependencies reject atomically.
  AiNativeAppearances moveArtwork({
    required AiNativeAppearanceArtwork artwork,
    required AiBoundingBox bounds,
    AiNativeAppearanceArtwork? before,
    AiNativeAppearanceArtwork? after,
    AiNativeItem? beforeObject,
    AiNativeItem? afterObject,
    AiNativeGroup? parent,
    AiLayer? layer,
    bool inheritParentAppearance = false,
  }) => _moveNativeAppearanceArtwork(this, artwork, bounds, before, after, beforeObject, afterObject, parent, layer, inheritParentAppearance);

  /// Updates mask flags or qualified native mask artwork with complete printing.
  ///
  /// Each changed mask must belong to one supplied body appearance owner, including
  /// private child objects/groups. Supply that owner's full group exactly once.
  /// Flags retain artwork bytes; replacement artwork retains boundaries and must
  /// have no named-resource or identity dependencies. Authoritative live-shape
  /// masks also qualify; printing-side or alternate mask copies, resource instances,
  /// unknown mask commands and conditional owners reject. The host supplies
  /// matching PDF content on full save; AiKit never composes mask pixels.
  AiNativeAppearances updateOpacityMasks({required List<AiNativeOpacityMaskChange> changes, required List<AiNativeAppearanceReplacement> artwork}) => _editNativeOpacityMasks(this, changes, artwork);

  /// Attaches masks to qualified private paths or groups with complete printing.
  ///
  /// Supply each enclosing body appearance's printing group once. Targets must
  /// have no existing mask; mask artwork cannot introduce named dependencies or
  /// object identities. Existing unrelated metadata remains byte-exact.
  /// Live shapes require one authoritative metadata representation without
  /// version-alternate dictionaries; no mask is added to their printing metadata.
  AiNativeAppearances createOpacityMasks({required List<AiNativeOpacityMaskAttachment> masks, required List<AiNativeAppearanceReplacement> artwork}) =>
      _lifecycleNativeOpacityMasks(this, masks, const [], artwork);

  /// Removes complete mask fields while retaining their owning objects.
  ///
  /// Every selected mask requires its enclosing body's complete printing group.
  /// Masks containing native identities require reference-aware removal and
  /// reject here. Removing a mask differs from retaining it with disabled=true.
  AiNativeAppearances deleteOpacityMasks({required List<AiNativeOpacityMask> masks, required List<AiNativeAppearanceReplacement> artwork}) =>
      _lifecycleNativeOpacityMasks(this, const [], masks, artwork);

  /// Replaces independent private child paints and geometry with complete printing.
  ///
  /// Every changed path belongs to a supplied body group owner. The transaction
  /// retains names, identities, frame metadata and group styles, synchronizes
  /// closure/counts, and restores original scalar state before following artwork.
  /// Unknown original values require proof that no following consumer uses them.
  /// Applied child styles, compound/mask contours, live shapes and resource-local
  /// owners require their separate appearance contracts. Supply matching PDF data
  /// when saving; the kit does not compose the supplied printing groups.
  AiNativeAppearances replaceArtworkPaths({required List<AiNativeAppearancePathChange> changes, required List<AiNativeAppearanceReplacement> artwork}) =>
      _replaceNativeAppearancePaths(this, changes, artwork);

  /// Changes private contour geometry with its complete host-composed appearance.
  ///
  /// Select private paths through each current `artworkFor` owner. Every selected
  /// body owner requires exactly one printing replacement, including when several
  /// child paths change together. Source paints, closure, clipping roles, styles,
  /// masks and identities remain unchanged; owned point counts are synchronized.
  /// `frameAngles` optionally updates authoring paths' and groups' frame directions.
  /// Omitted frame angles retain their source values independently of geometry.
  /// Live shapes and resource-local owners require their separate contracts.
  /// Supply geometry in native coordinates and a matching PDF when saving.
  AiNativeAppearances editArtworkPaths({
    required List<AiNativePathEdit> edits,
    required List<AiNativeAppearanceReplacement> artwork,
    Map<AiNativeItem, double> frameAngles = const {},
  }) => _editNativeAppearancePaths(this, edits, artwork, frameAngles);

  /// Replaces styled private contour geometry, closure and visibility/locking.
  ///
  /// Each complete body owner requires one current printing replacement, even
  /// when several independently styled child contours change together.
  /// The native contour remains unpainted and keeps its named style, metadata,
  /// mask and identity. Counts follow the new closure; explicit flag restorations
  /// protect following native and printing artwork. Unknown inherited flag state,
  /// live shapes, compound/clipping contours and resource-local owners reject.
  /// Child flags do not change the complete printing group's visibility/locking.
  /// The host supplies complete printing and a matching compatibility PDF.
  AiNativeAppearances replaceArtworkContours({required List<AiNativeAppearanceContourChange> changes, required List<AiNativeAppearanceReplacement> artwork}) =>
      _replaceNativeAppearanceContours(this, changes, artwork);

  /// Changes a shared definition and all qualified dependent printing groups.
  ///
  /// Every named use must have one uniquely bound printing owner covered by
  /// `artwork` or the live-shape `printing` shorthand.
  /// Select nested uses explicitly in `AiNativeAppearanceReplacement.uses`,
  /// supplying each complete enclosing printing group only once.
  /// Unknown dependency owners, effects and unresolved following state reject.
  /// Explicit uniform original state may be restored after each selected use
  /// as private scalar commands; this does not relax shared reference coverage.
  /// An unused qualified style needs no printing replacement. The host supplies
  /// matching expansions and the compatibility PDF when saving the document.
  /// Resource edits also require `dependents` for affected pattern-style users
  /// not already covered by a primary complete owner, including transitive
  /// resource owners. Their native styles remain unchanged. Resource boundaries
  /// must retain their outgoing native state.
  /// Unknown instance links, recursive resources and incomplete coverage reject.
  AiNativeAppearances updateShared({
    required AiNativeAppearance appearance,
    List<AiNativePaintChange> paints = const [],
    List<AiNativeAppearancePartChange> parts = const [],
    List<AiNativePrintingGroupReplacement> printing = const [],
    List<AiNativeAppearanceReplacement> artwork = const [],
    List<AiNativeAppearanceReplacement> dependents = const [],
  }) => _editNativeAppearance(this, appearance, paints, parts, printing, artwork, dependents, null);

  /// Copies a style for selected CC users and attaches their host-composed groups.
  ///
  /// The fresh byte name must not capture an existing declaration or reference.
  /// Only users identified by `artwork` or `printing` are rebound; the source definition and
  /// other users remain unchanged. `AiNativeAppearanceReplacement.uses` can select
  /// several nested applications with one complete enclosing printing group.
  /// Each supplied group must preserve outgoing
  /// printing state. When following artwork needs the original native state,
  /// uniform explicit assignments of an entirely visible original style can
  /// be restored with private scalar commands. Unknown values still reject.
  /// For resource-local edits, `dependents` supplies the complete derived groups
  /// of affected pattern-style users without rebinding their native references.
  /// Include each affected use in its replacement's `uses`, and each complete
  /// printing group only once across both lists. A selected complete owner also
  /// covers dependent child uses inside that same printing group.
  /// Resource selections require qualified whole-source references. All instances
  /// of that resource remain dependent on its edited artwork.
  AiNativeAppearances updateSelected({
    required AiNativeAppearance appearance,
    List<AiNativePaintChange> paints = const [],
    List<AiNativeAppearancePartChange> parts = const [],
    List<AiNativePrintingGroupReplacement> printing = const [],
    List<AiNativeAppearanceReplacement> artwork = const [],
    List<AiNativeAppearanceReplacement> dependents = const [],
    required List<int> nameBytes,
  }) => _editNativeAppearance(this, appearance, paints, parts, printing, artwork, dependents, nameBytes);
}
