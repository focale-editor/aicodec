part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// A version-selection boundary retained beside native drawing records.
final class AiNativeVersionComment extends AiNativeItem {
  /// Original comment, including the Illustrator version condition.
  final AiToken token;

  /// Retains the source boundary without evaluating arbitrary conditional code.
  AiNativeVersionComment._({required this.token}) : super(start: token.start, end: token.end);
}

/// A native drawing command in either the printable or private representation.
final class AiNativeInstruction extends AiNativeItem {
  /// Source-backed executable operator token.
  final AiToken token;

  /// Exact operands, including array delimiters and opaque values.
  final List<AiToken> operands;

  /// Whether this is a private `%_` drawing command rather than style data.
  final bool isPrivate;

  /// Creates a command without executing its PostScript semantics.
  AiNativeInstruction._({required this.token, required List<AiToken> operands, required this.isPrivate})
    : operands = List.unmodifiable(operands),
      super(start: operands.isEmpty ? token.start : operands.first.start, end: token.end);

  /// Case-sensitive operator name.
  String get operator => token.lexeme;

  /// Numeric operands when the complete operand list consists of finite numbers.
  List<double>? get numbers => operands.every((operand) => operand.number != null) ? List.unmodifiable(operands.map((operand) => operand.number!.toDouble())) : null;
}

/// A path in the native body, including authoritative comment-prefixed geometry.
final class AiNativePath extends AiNativeItem {
  /// Source geometry retaining smooth/corner distinctions and curve shorthand.
  final List<AiNativeInstruction> geometry;

  /// Path consumption, including an unpainted authoritative outline.
  final AiNativeInstruction paint;

  /// Whether this path is private authoring geometry.
  final bool isPrivate;

  /// Creates a complete path after validating coordinate arities.
  AiNativePath._({required List<AiNativeInstruction> geometry, required this.paint, required this.isPrivate})
    : geometry = List.unmodifiable(geometry),
      super(start: geometry.first.start, end: paint.end);

  /// Geometry independently of the painted compatibility representation.
  List<AiPathSegment> get segments => List.unmodifiable(geometry.map((command) => AiPathSegment(operator: command.operator, coordinates: command.numbers!)));

  /// Whether the native paint operator explicitly closes the path.
  bool get closed => const {'n', 'f', 's', 'b'}.contains(paint.operator);
}

/// New ordinary geometry inheriting an existing path's paint and object flags.
///
/// Insertion immediately follows [after], before subsequent state changes. The
/// host supplies ink bounds; the kit does not compose strokes or render artwork.
final class AiNativePathInsertion {
  /// Owned ordinary source path establishing insertion order and inherited state.
  final AiNativePath after;

  /// New geometry, with exactly one initial moveto and no nested subpaths.
  final List<AiPathSegment> segments;

  /// Host-supplied ink bounds used to expand the existing drawing extent.
  final AiBoundingBox bounds;

  /// Freezes the geometry before planning the complete source transaction.
  AiNativePathInsertion({required this.after, required List<AiPathSegment> segments, required this.bounds}) : segments = List.unmodifiable(segments) {
    if (segments.isEmpty || segments.first.operator != 'm' || segments.skip(1).any((segment) => segment.operator == 'm')) {
      throw ArgumentError('Inserted native paths require exactly one initial moveto.');
    }
    if (segments.any((segment) => segment.coordinates.any((value) => value.abs() > 9007199254740991))) {
      throw ArgumentError('Inserted native coordinates exceed portable numeric limits.');
    }
  }
}

/// A grouped or compound collection of native paths in one representation.
final class AiNativeGroup extends AiNativeItem {
  /// Opening group, compound-path or graphics-state operator.
  final AiNativeInstruction opening;

  /// Matching closing operator.
  final AiNativeInstruction closing;

  /// Direct path/group children in drawing order.
  final List<AiNativeItem> children;

  /// Creates an immutable group without flattening its native topology.
  AiNativeGroup._({required this.opening, required this.closing, required List<AiNativeItem> children}) : children = List.unmodifiable(children), super(start: opening.start, end: closing.end);

  /// Whether this group represents a compound path.
  bool get compound => opening.operator == '*u';

  /// Recursively enumerates paths belonging to this exact group.
  Iterable<AiNativePath> get paths sync* {
    for (final AiNativeItem child in children) {
      if (child is AiNativePath) {
        yield child;
      } else if (child is AiNativeGroup) {
        yield* child.paths;
      }
    }
  }
}

/// A CC live shape linked to its authoring path and compatibility appearance.
final class AiLiveShape {
  /// Authoritative art dictionary, excluding redundant NotRecorded definitions.
  final AiNativeContainer dictionary;

  /// Native live-shape dictionary containing handler and parameters.
  final AiNativeContainer definition;

  /// Complete native parameter dictionary; unrecognized fields are retained.
  final AiNativeContainer parameters;

  /// Handler identifier, such as ai::Rectangle, ai::Ellipse or ai::Star.
  final String handler;

  /// Editable centerline/outline, which may be private comment-prefixed data.
  final AiNativePath? path;

  /// Printable paths associated with this exact shape, including stroke outlines.
  final List<AiNativePath> appearancePaths;

  /// Redundant metadata associated with the printable compatibility appearance.
  final AiNativeContainer? appearanceDictionary;

  /// Older-version metadata alternatives sharing the same authoritative path.
  final List<AiNativeContainer> alternativeDictionaries;

  /// Full compatibility group, when a separate grouped appearance exists.
  final AiNativeGroup? appearanceGroup;

  /// Reference to a named appearance style, when stored separately.
  final String? styleName;

  /// Resolved known-style resource; null when absent or unresolved.
  final AiNativeContainer? style;

  /// Byte position of the first command belonging to the compatibility object.
  final int start;

  /// Exclusive end of the authoritative record or its style reference.
  final int end;

  /// Explains incomplete structural association without inventing ownership.
  final String? bindingIssue;

  /// Creates a source-backed live shape with independently identified views.
  AiLiveShape._({
    required this.dictionary,
    required this.definition,
    required this.parameters,
    required this.handler,
    required this.path,
    required List<AiNativePath> appearancePaths,
    required this.appearanceDictionary,
    required List<AiNativeContainer> alternativeDictionaries,
    required this.appearanceGroup,
    required this.styleName,
    required this.style,
    required this.start,
    required this.end,
    required this.bindingIssue,
  }) : appearancePaths = List.unmodifiable(appearancePaths),
       alternativeDictionaries = List.unmodifiable(alternativeDictionaries);

  /// Parallelogram geometry for a qualified four-sided irregular native polygon.
  ///
  /// Returns null for other shapes, curved corners or non-parallelogram quads.
  AiNativeParallelogram? get parallelogram {
    if (handler != 'ai::Polygon' || parameters['ai::Polygon::NumSides']?.number != 4 || parameters['ai::Polygon::IsRegular']?.boolean != false || path == null) {
      return null;
    }
    try {
      return _parallelogramFromSegments(path!.segments);
    } on UnsupportedError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Whether both native geometry and any separate appearance have known owners.
  bool get isBound => bindingIssue == null;
}

/// Source-backed native drawing structure, retaining both authoring and preview.
final class AiNativeDrawing {
  /// Native records and source snapshot owning all returned handles.
  final AiNativeRecords records;

  /// Drawing commands and hierarchical records in source order.
  final List<AiNativeItem> items;

  /// All body paths, including private editable outlines and printable expansions.
  final List<AiNativePath> paths;

  /// Native group/compound-path ranges, including nested groups.
  final List<AiNativeGroup> groups;

  /// Gradient instances in printable or private body commands.
  final List<AiNativeGradient> gradients;

  /// Live shapes with explicit associations or an explanation of missing links.
  final List<AiLiveShape> liveShapes;

  /// Lazily shares immutable object metadata across bounded lifecycle operations.
  /// Cached family inventories for bounded private and mask wrapper inspection.
  late final List<AiNativeRaster> _appearanceRasters = _readNativeRasters(records, false);

  /// Cached complete mesh packets for the same source revision.
  late final List<AiNativeMesh> _appearanceMeshes = _readNativeMeshes(records, false);

  /// Qualified payloads, including negative ordinary-group results.
  final Map<AiNativeGroup, AiNativeAppearanceLeaf?> _appearanceLeaves = {};

  /// Source-owned identity and metadata associations.
  late final AiNativeObjects _objects = _nativeObjects(this);

  /// Shares qualified image framing across immutable state and lifecycle queries.
  late final List<_NativeSubtreeSpan> _neutralImageSpans = List.unmodifiable(_readImageCreationNeutralSpans(this));

  /// Shares complete ordinary image owners across reference and hierarchy checks.
  late final List<_NativeImageOwner> _imageOwners = List.unmodifiable(_readNativeImageOwners(this));

  /// Shares complete isolated text owners without treating opaque text as editable.
  late final List<_NativeTextArtwork> _textArtwork = List.unmodifiable(_readNativeTextArtwork(this));

  /// Complete direct gradient contours qualified for native lifecycle edits.
  late final List<AiNativeGradientArtwork> gradientArtwork = List.unmodifiable(_readNativeGradientArtwork(this));

  /// Complete Cartesian mesh packets qualified for native lifecycle edits.
  late final List<AiNativeMeshArtwork> meshArtwork = List.unmodifiable(_readNativeMeshArtwork(this));

  /// Shares retained-body qualification across contour inspections and batches.
  late final ({AiNativeLayers layers, Set<AiNativePath> derived, Set<AiNativeContainer> dictionaries, Set<AiNativeContainer> retainedMetadata}) _pathTopologyScope = _nativePathTopologyScope(this);

  /// Builds a bounded structural view without evaluating arbitrary PostScript.
  factory AiNativeDrawing.decode({required AiNativeRecords records}) => _NativeDrawingReader(records: records).read();

  /// Creates an immutable completed drawing view.
  AiNativeDrawing._({
    required this.records,
    required List<AiNativeItem> items,
    required List<AiNativePath> paths,
    required List<AiNativeGroup> groups,
    required List<AiNativeGradient> gradients,
    required List<AiLiveShape> liveShapes,
  }) : items = List.unmodifiable(items),
       paths = List.unmodifiable(paths),
       groups = List.unmodifiable(groups),
       gradients = List.unmodifiable(gradients),
       liveShapes = List.unmodifiable(liveShapes);

  /// Creates one explicit native mesh in a qualified root, layer or group.
  ///
  /// The host supplies all native node data, ink bounds and the synchronized PDF.
  /// Both outgoing scalar state views are restored after the new object.
  AiNativeDrawing createMeshArtwork({required AiNativeMeshArtworkDefinition definition, AiNativeGroup? parent, AiLayer? layer}) => _createNativeMeshArtwork(this, definition, parent, layer);

  /// Replaces a complete mesh and its flags while retaining source metadata.
  ///
  /// The definition must omit its name and identity. Unknown owners reject;
  /// neighboring native and printing state is restored after the replacement.
  /// Existing frame-angle metadata requires explicit [rotationRadians].
  AiNativeDrawing replaceMeshArtwork({required AiNativeMeshArtwork artwork, required AiNativeMeshArtworkDefinition definition, double? rotationRadians}) =>
      _replaceNativeMeshArtwork(this, artwork, definition, rotationRadians);

  /// Copies complete mesh packets with fresh values for all existing identities.
  ///
  /// Shared inks remain literal native data. The copied geometry and attributes
  /// retain their source values; no tessellation or interpolation is performed.
  AiNativeDrawing duplicateMeshArtwork({required List<AiNativeMeshArtwork> artwork, Map<AiNativeItem, List<int>> identifiers = const {}}) => _duplicateNativeMeshArtwork(this, artwork, identifiers);

  /// Inspects an ordinary contour's compound, clip and point-count ownership.
  ///
  /// Private authoring, printable CC expansions and unresolved body dependencies
  /// reject instead of becoming independently editable paths.
  AiNativePathTopology pathTopology({required AiNativePath path}) => _nativePathTopologies(this, [path]).single;

  /// Replaces ordinary contour geometry and clipping relationships atomically.
  ///
  /// Counts follow effective closure, including `h W` masks. Compound masks must
  /// change all affected contours together; enabling clipping requires an existing
  /// effective `q`/`Q` owner outside the compound. Mask role changes synchronize
  /// compound leaf group kinds; paint, metadata, identities, ordering and
  /// unselected source remain unchanged. [bounds] supplies the host-computed ink
  /// extent, including exposed artwork, independently of artboard rectangles.
  AiNativeDrawing editPaths({required List<AiNativePathEdit> edits, required AiBoundingBox bounds}) => _editNativePaths(this, edits, bounds);

  /// Applies a nonuniform scale, reflection, shear or general affine contour map.
  ///
  /// Stroke widths, dashes and paint state remain unchanged. [bounds] is the
  /// host-computed ink extent; this does not affine-expand strokes. Supply an
  /// explicit resulting angle for every existing path frame-angle field through
  /// [frameAngles]. Group/compound/clip topology is retained; transforming selected
  /// masks changes their relationship to unselected artwork intentionally.
  /// Live shapes and positional paints require their separate editing contracts.
  AiNativeDrawing transformPaths({required List<AiNativePath> paths, required AiNativeAffineTransform transform, required AiBoundingBox bounds, Map<AiNativePath, double> frameAngles = const {}}) =>
      _transformNativePaths(this, paths, transform, bounds, frameAngles);

  /// Transforms representable live shapes with fixed stroke widths and dashes.
  ///
  /// Sharp rectangles become native irregular four-sided polygons when sheared;
  /// [AiLiveShape.parallelogram] exposes their editable half-edge geometry.
  /// Sharp polygons can become irregular; lines admit arbitrary invertible maps.
  /// Ellipses require orthogonal transformed axes and no pie parameters. Rounded
  /// nonuniform/reflected shapes and nonuniform stars require [replaceLiveShapes]
  /// with host-regenerated geometry instead. Every separate CC expansion requires
  /// a matching complete [printing] group, composed by the host with fixed stroke
  /// widths. Gradients and unknown positional dependencies reject. The explicit
  /// [bounds] must include all resulting ink. PDF and previews are supplied by
  /// the host after this atomic native edit.
  AiNativeDrawing transformLiveShapes({
    required List<AiLiveShape> shapes,
    required AiNativeAffineTransform transform,
    required AiBoundingBox bounds,
    Map<AiLiveShape, List<int>> printing = const {},
  }) => _transformLiveShapes(this, shapes, transform, bounds, printing);

  /// Saves native shape parameters and host-regenerated contours atomically.
  ///
  /// Every separate CC expansion requires a complete supplied printing group.
  /// Shared process styles, identities and unselected artwork remain unchanged.
  /// Source geometry is not regenerated from parameters by this package. The host
  /// supplies matching outlines, ink bounds, PDF and previews. Unknown effects,
  /// positional gradients and inconsistent redundant parameter copies reject.
  AiNativeDrawing replaceLiveShapes({required List<AiNativeLiveShapeReplacement> replacements}) => _replaceNativeLiveShapes(this, replacements);

  /// Creates a direct live shape from explicit host parameters and painted geometry.
  ///
  /// The host supplies the canvas-relative parameters, complete contour and ink
  /// bounds. No shape geometry or printing appearance is generated by the kit.
  /// The direct contour is its printable representation; supply the matching PDF
  /// when saving. Native names, identities and outgoing scalar state are retained.
  AiNativeDrawing createLiveShape({required AiNativePathDefinition definition, required AiNativeShapeParameters parameters, double? rotationRadians, AiNativeGroup? parent, AiLayer? layer}) =>
      _createNativeLiveShape(this, definition, parameters, rotationRadians, parent, layer);

  /// Attaches explicit live parameters to one qualified ordinary source contour.
  ///
  /// Metadata and identity are preserved. The caller certifies that the existing
  /// contour and synchronized representations match these complete parameters.
  AiNativeDrawing setPathLiveShape({required AiNativePath path, required AiNativeShapeParameters parameters, double? rotationRadians}) =>
      _setNativePathLiveShape(this, path, parameters, rotationRadians);

  /// Replaces a direct shape's parameters, geometry and ordinary process paints.
  ///
  /// Separate CC printing groups require [replaceLiveShapes]. The supplied
  /// definition must omit name and identity, which remain source-owned.
  AiNativeDrawing replaceDirectLiveShape({required AiLiveShape shape, required AiNativePathDefinition definition, required AiNativeShapeParameters parameters, double? rotationRadians}) =>
      _replaceNativeDirectLiveShape(this, shape, definition, parameters, rotationRadians);

  /// Renames qualified direct paths, shapes and groups without changing artwork.
  ///
  /// Keys are current native handles; values are literal display-name bytes.
  /// Existing name aliases retain their scalar types and receive the same value.
  /// Absent names acquire an `AIArtName` field. XML identities, geometry, paint
  /// and unrelated metadata remain unchanged; no new rendered PDF is needed.
  AiNativeDrawing renameObjects({required Map<AiNativeItem, List<int>> names}) => _renameNativeObjects(this, names);

  /// Changes an ordinary group's own visibility and lock without rewriting children.
  ///
  /// Null arguments retain the original flags. Known native and printing state is
  /// restored immediately after the opening group command, so child assignments
  /// and following artwork remain unchanged. The host composes matching PDF
  /// visibility. Group opacity, blending and masks require an appearance owner;
  /// clipping, compound, private and conditional groups retain separate contracts.
  AiNativeDrawing updateGroupAttributes({required AiNativeGroup group, bool? hidden, bool? locked}) => _updateNativeGroupAttributes(this, group, hidden, locked);

  /// Replaces one ordinary path's geometry and complete literal appearance.
  ///
  /// Retains its attached name, XML identity and qualified metadata. Explicit
  /// flags apply only to the selected object; separate native and printing state
  /// is restored for following artwork. Supply matching host ink bounds and PDF
  /// artwork when saving. Private shapes, gradients, compounds and unresolved
  /// metadata require their own contracts. All supplied attributes are complete,
  /// rather than patches over inherited values.
  /// Named channels replace the corresponding absent process channels; names,
  /// alternatives and native tint operands are serialized without conversion.
  AiNativeDrawing replacePathArtwork({
    required AiNativePath path,
    required AiArtworkPath artwork,
    required AiBoundingBox bounds,
    AiNativeNamedColor? namedFill,
    AiNativeNamedColor? namedStroke,
    double opacity = 1,
    AiNativeTransparency? transparency,
    bool hidden = false,
    bool fillOverprint = false,
    bool strokeOverprint = false,
  }) => _replaceNativePathArtwork(this, path, artwork, bounds, opacity, hidden, fillOverprint, strokeOverprint, transparency: transparency, namedFill: namedFill, namedStroke: namedStroke);

  /// Duplicates ordinary paths immediately after their original source objects.
  ///
  /// Geometry, paint, qualified object metadata and CC point counts are copied.
  /// Direct live shapes retain their native parameters with their single path.
  /// [identifiers] supplies a fresh XML name for every identified selected path.
  /// Names must differ from all saved XMLUID wrappers, including opaque owners.
  /// Anonymous copies stay anonymous; existing references retain their targets.
  /// Paint/lock/visibility state remains in place and is inherited by each copy.
  /// Private authoring paths, derived expansions, compound/clip members and
  /// unresolved attached metadata reject.
  AiNativeDrawing duplicatePaths({required List<AiNativePath> paths, Map<AiNativeItem, List<int>> identifiers = const {}}) => _duplicateNativePaths(this, paths, identifiers);

  /// Creates an empty ordinary group without requiring existing child artwork.
  ///
  /// Specify either an owned [parent] group or [layer], or neither to append at
  /// the document root. Optional name bytes and a fresh XML identity create only
  /// the corresponding native metadata. Ancestor and current object flags are
  /// inherited; unknown or non-neutral object flags require [inheritParentFlags].
  /// Optional [hidden] and [locked] override only the new group's own flags,
  /// restoring both source states before its children. Parent inheritance still
  /// requires the same explicit acknowledgement.
  /// Painting state, existing identities, layer headers and saved views stay
  /// unchanged. Private, compound, clipping and unresolved owners reject.
  AiNativeDrawing createGroup({AiNativeGroup? parent, AiLayer? layer, List<int>? nameBytes, List<int>? identifierBytes, bool inheritParentFlags = false, bool? hidden, bool? locked}) =>
      _createNativeGroup(this, parent, layer, nameBytes, identifierBytes, inheritParentFlags, hidden, locked);

  /// Creates an ordinary path without requiring existing geometry or a sibling.
  ///
  /// Appends at the root or inside one owned [parent] group or [layer]. The
  /// definition supplies all consumed object/paint state; ancestor flags remain
  /// inherited. Known native and printing state is restored independently for
  /// following artwork. Unresolved required state or ownership rejects atomically.
  /// Host-computed ink bounds expand drawing extents without changing artboards.
  AiNativeDrawing createPath({required AiNativePathDefinition definition, AiNativeGroup? parent, AiLayer? layer}) => _createNativePath(this, definition, parent, layer);

  /// Creates a direct gradient fill from an existing resource and explicit geometry.
  ///
  /// The host supplies the resource's composed ramps and matching PDF. The path
  /// definition supplies a process fallback and complete ink bounds. Its name and
  /// fresh identity attach after the complete gradient application.
  AiNativeDrawing createGradientArtwork({required AiNativePathDefinition definition, required AiNativeGradientFillDefinition gradient, AiNativeGroup? parent, AiLayer? layer}) =>
      _createNativeGradientArtwork(this, definition, gradient, parent, layer);

  /// Applies a gradient to an ordinary process path while keeping its identity.
  ///
  /// Supply complete geometry, fallback paint and ink bounds with no new metadata.
  AiNativeDrawing setPathGradient({required AiNativePath path, required AiNativePathDefinition definition, required AiNativeGradientFillDefinition gradient}) =>
      _setNativePathGradient(this, path, definition, gradient);

  /// Replaces a gradient owner by ordinary process artwork without changing its ID.
  ///
  /// The shared resource remains until explicitly removed after its final user.
  AiNativeDrawing clearGradientArtwork({required AiNativeGradientArtwork artwork, required AiNativePathDefinition definition}) => _clearNativeGradientArtwork(this, artwork, definition);

  /// Copies complete gradient owners without duplicating their shared resources.
  ///
  /// Supply a fresh identifier keyed by each identified gradient artwork handle.
  /// Anonymous source owners remain anonymous, matching ordinary path copies.
  AiNativeDrawing duplicateGradientArtwork({required List<AiNativeGradientArtwork> artwork, Map<AiNativeItem, List<int>> identifiers = const {}}) =>
      _duplicateNativeGradientArtwork(this, artwork, identifiers);

  /// Replaces a complete gradient contour/application while retaining its identity.
  ///
  /// The supplied definition must omit names/identifiers. Move, reorder and remove
  /// complete handles through `AiNativeLayers` rather than detaching their paths.
  AiNativeDrawing replaceGradientArtwork({required AiNativeGradientArtwork artwork, required AiNativePathDefinition definition, required AiNativeGradientFillDefinition gradient}) =>
      _replaceNativeGradientArtwork(this, artwork, definition, gradient);

  /// Inserts embedded process samples with explicit placement and ordinary state.
  ///
  /// Appends to the selected ordinary group/layer, or to the drawing root.
  /// The host supplies the matching PDF; no file decoding or rendering occurs.
  /// Unknown inherited state and conditional/appearance-owned parents reject.
  AiNativeDrawing createRaster({required AiNativeRasterDefinition definition, AiNativeGroup? parent, AiLayer? layer}) => _createNativeRaster(this, definition, parent, layer);

  /// Inserts a copy of qualified native samples without display-pixel conversion.
  ///
  /// [source] owns [image], including when copying from an earlier snapshot.
  /// Supply a fresh artwork identity in [attributes]. Sample identities are
  /// renewed; original depth, planes, frame metadata and source filename survive.
  /// Filename interpretation belongs to the host when the document base changes.
  /// Explicit attributes and placement replace the source object's effective
  /// attributes; source and destination neighbors retain their original state.
  AiNativeDrawing copyRaster({
    required AiNativeRasters source,
    required AiNativeRaster image,
    required List<double> matrix,
    required AiNativeImageAttributes attributes,
    AiNativeGroup? parent,
    AiLayer? layer,
  }) => _copyNativeRaster(this, source, image, matrix, attributes, parent, layer);

  /// Inserts a raster link, its optional preview and document file dependency.
  ///
  /// Paths retain host-supplied bytes; IllustratorKit never opens the external file.
  /// Placement uses the local downward-y rectangle and native drawing points.
  /// Parent selection and outgoing-state guarantees match [createRaster].
  AiNativeDrawing createPlacement({required AiNativePlacementDefinition definition, AiNativeGroup? parent, AiLayer? layer}) => _createNativePlacement(this, definition, parent, layer);

  /// Copies an owned raster link and preview with a fresh artwork identity.
  ///
  /// External path bytes and relative-directory hints are preserved verbatim.
  /// The host must rebase links before copying between different file locations.
  AiNativeDrawing copyPlacement({
    required AiNativePlacements source,
    required AiNativePlacedObject object,
    required List<double> matrix,
    required AiNativeImageAttributes attributes,
    AiNativeGroup? parent,
    AiLayer? layer,
  }) => _copyNativePlacement(this, source, object, matrix, attributes, parent, layer);

  /// Copies complete bound CC authoring/printing pairs after their originals.
  ///
  /// Private geometry, parameters, printing contours and saved alternatives stay
  /// together. Shared styles/resources retain their identities. Each identified
  /// metadata dictionary requires a fresh XML name in [identifiers]. Unknown
  /// inherited state, resource ownership or local metadata rejects atomically.
  /// Direct single-path shapes use [duplicatePaths] instead.
  AiNativeDrawing duplicateLiveShapes({required List<AiLiveShape> shapes, Map<AiNativeContainer, List<int>> identifiers = const {}}) => _duplicateNativeShapes(this, shapes, identifiers);

  /// Removes complete CC authoring/printing pairs while retaining shared resources.
  ///
  /// Explicit printing and private state assignments remain in the source.
  /// Following artwork must not depend on unresolved outgoing style effects.
  /// Saved identities require a qualified document-wide reference scope.
  AiNativeDrawing removeLiveShapes({required List<AiLiveShape> shapes}) => _removeNativeShapes(this, shapes);

  /// Places complete CC pairs into their original sibling slots in the given order.
  ///
  /// Saved identities, private geometry, printing groups and alternatives travel
  /// together. Other objects retain their source bytes and inherited attributes.
  /// Unknown required state or unresolved following dependencies rejects the batch.
  AiNativeDrawing reorderLiveShapes({required List<AiLiveShape> shapes}) => _reorderNativeShapes(this, shapes);

  /// Moves a complete CC pair after another, preserving its saved identities.
  ///
  /// Source-derived state remains at the old location and restores the destination
  /// after insertion. Different layers or ancestor-group flags/depths require
  /// [inheritParentFlags]. Unknown required state or dependencies reject atomically.
  AiNativeDrawing moveLiveShapeAfter({required AiLiveShape shape, required AiLiveShape after, bool inheritParentFlags = false}) => _moveNativeShapeAfter(this, shape, after, inheritParentFlags);

  /// Appends a complete CC pair to an ordinary group, including an empty group.
  ///
  /// Printing expansions, private/compound/clip groups and unresolved owners
  /// cannot be destinations. The inheritance contract of [moveLiveShapeAfter]
  /// applies; destination metadata and unselected artwork remain exact.
  AiNativeDrawing moveLiveShapeToGroup({required AiLiveShape shape, required AiNativeGroup group, bool inheritParentFlags = false}) => _moveNativeShapeToGroup(this, shape, group, inheritParentFlags);

  /// Appends a complete CC pair directly to an existing, possibly empty layer.
  ///
  /// The inheritance contract of [moveLiveShapeAfter] applies. Layer identities,
  /// headers, root counts and saved panel declarations remain unchanged.
  AiNativeDrawing moveLiveShapeToLayer({required AiLiveShape shape, required AiLayer layer, bool inheritParentFlags = false}) => _moveNativeShapeToLayer(this, shape, layer, inheritParentFlags);

  /// Removes ordinary geometry and owned point counts, retaining surrounding state.
  ///
  /// Unselected bytes and paint/lock/visibility assignments remain unchanged.
  /// Existing drawing bounds remain conservative. Paths with unresolved native
  /// owners or references reject. Identified paths require a fully qualified
  /// declarative reference scope, including all unselected native owners.
  /// Qualified direct live-shape parameters are removed with their path.
  AiNativeDrawing removePaths({required List<AiNativePath> paths}) => _removeNativePaths(this, paths);

  /// Inserts geometry using each anchor's existing paint, flags and count layout.
  ///
  /// Input order is retained when several insertions share an anchor. Counted
  /// closed paths receive an explicit closing line when necessary. The same
  /// ownership restrictions as [duplicatePaths] apply; this does not create a
  /// missing modern document, layer, resource or private live-shape definition.
  /// Inserting after a live shape creates plain geometry without its parameters.
  /// Saving requires matching host-supplied PDF artwork through the save API.
  AiNativeDrawing insertPaths({required List<AiNativePathInsertion> insertions}) => _insertNativePaths(this, insertions);

  /// Reorders selected sibling paths into their existing source positions.
  ///
  /// [paths] gives the desired order. Source assignments preserve each path's
  /// paint and object flags and restore the following artwork's state. Unknown
  /// required values, opaque metadata and other object kinds reject. Geometry,
  /// qualified metadata and point counts move together, retaining identities.
  AiNativeDrawing reorderPaths({required List<AiNativePath> paths}) => _reorderNativePaths(this, paths);

  /// Moves a path after an anchor, optionally into another ordinary group.
  ///
  /// Both paths require a qualified ordinary interval. Source
  /// assignments preserve the moved path's paint/object flags and restore state
  /// at the destination. Unknown required values and opaque dependencies reject.
  /// Moving across layers or different ancestor-group flags/depths requires
  /// [inheritParentFlags], accepting destination inheritance. Layer headers,
  /// identities and panel declarations remain unchanged.
  AiNativeDrawing movePathAfter({required AiNativePath path, required AiNativePath after, bool inheritParentFlags = false}) => _moveNativePath(this, path, after, inheritParentFlags);

  /// Appends a path directly to an existing layer, including an empty layer.
  ///
  /// [layer] must belong to this drawing's source program. The state and explicit
  /// destination-inheritance contract of [movePathAfter] applies. Layer identity,
  /// order, flags and saved panel declarations remain unchanged.
  AiNativeDrawing movePathToLayer({required AiNativePath path, required AiLayer layer, bool inheritParentFlags = false}) => _moveNativePathToLayer(this, path, layer, inheritParentFlags);

  /// Appends a complete ordinary path to a populated or empty ordinary group.
  ///
  /// Geometry, point counts and qualified direct metadata move together. Native
  /// and printing state are preserved separately, including around complete CC
  /// siblings. Unknown required state and unresolved dependencies reject. Changed
  /// ancestor flags, depth or layers require explicit [inheritParentFlags].
  AiNativeDrawing movePathToGroup({required AiNativePath path, required AiNativeGroup group, bool inheritParentFlags = false}) => _moveNativePathToGroup(this, path, group, inheritParentFlags);

  /// Moves ordinary contours between group, compound and clipping owners atomically.
  ///
  /// Paths follow the supplied order, after an optional direct child [after] or
  /// at the end of [group]. Counts and identities travel with each contour;
  /// source state assignments and unselected artwork remain in place. [mask]
  /// optionally changes every selected mask role. A retained mask needs an
  /// effective destination clip owner, and compounds cannot mix mask roles.
  ///
  /// Entering a different compound requires [inheritCompoundAppearance], adopting
  /// its paint mode and shared appearance while retaining each contour's closure.
  /// Leaving a compound preserves its shared appearance. Empty compound elements,
  /// unknown required state and derived CC geometry reject. Changed ancestor
  /// flags/depth or layers require [inheritParentFlags]. The host supplies affected
  /// ink [bounds] and updated derived representations when saving. Imported affine
  /// ancestors must remain the same; this operation does not rebase their matrices.
  /// Each affected compound must be non-nested with one paint mode ignoring case.
  AiNativeDrawing moveContours({
    required List<AiNativePath> paths,
    required AiNativeGroup group,
    required AiBoundingBox bounds,
    AiNativePath? after,
    AiNativePathMask? mask,
    bool inheritCompoundAppearance = false,
    bool inheritParentFlags = false,
  }) => _moveNativeContours(this, paths, group, bounds, after, mask, inheritCompoundAppearance, inheritParentFlags);

  /// Moves complete contour groups with their identities and saved mask trees.
  ///
  /// Distinct, disjoint [groups] follow caller order at the end of [parent] or
  /// [layer], or after its unselected direct child [after]. Omitting both parents
  /// places the groups at the document root. Ordinary, compound and clipping
  /// descendants retain their geometry, metadata and identities, with source-derived
  /// state replay at the edited positions. Empty groups and ordinary contours are
  /// supported; private/derived geometry, text and unresolved dependencies reject.
  ///
  /// Ordinary branches can move within, out of or into a compound. Leaving one
  /// materializes its shared paint; entering another requires
  /// [inheritCompoundAppearance] and adopts its paint mode, retaining closure.
  /// Compound elements must remain populated, non-nested and consistent in paint
  /// mode and mask role. Mask branches retain path-only clipping leaves and
  /// group-only ordinary branches. Retained masks require an effective clipping
  /// owner after the move. Imported transform ancestors stay identical. Changed
  /// ancestor flags, depth or layers require [inheritParentFlags]. The host supplies
  /// ink [bounds] and any changed derived representations when saving.
  AiNativeDrawing moveContourGroups({
    required List<AiNativeGroup> groups,
    required AiBoundingBox bounds,
    AiNativeGroup? parent,
    AiLayer? layer,
    AiNativeGroup? after,
    bool inheritCompoundAppearance = false,
    bool inheritParentFlags = false,
  }) => _moveNativeContourGroups(this, groups, parent, layer, bounds, after, inheritCompoundAppearance, inheritParentFlags);

  /// Groups contiguous ordinary sibling paths without changing their source order.
  ///
  /// Optional point counts and intervening qualified state stay with the paths.
  /// Qualified child metadata and identities stay with their paths. Unselected
  /// siblings, private owners and unresolved metadata reject atomically. The parent
  /// inheritance policy of [groupArtwork] applies.
  AiNativeDrawing groupPaths({required List<AiNativePath> paths, bool inheritParentFlags = false}) => groupArtwork(paths: paths, inheritParentFlags: inheritParentFlags);

  /// Groups consecutive sibling paths, groups and complete native live shapes.
  ///
  /// Source order, child identities and complete authoring/printing pairs remain
  /// unchanged. Select a paired shape through [liveShapes], not its private path
  /// or printing group. The new anonymous parent inherits the flags at the first
  /// selected owner. Non-neutral or unknown flags require [inheritParentFlags].
  AiNativeDrawing groupArtwork({List<AiNativePath> paths = const [], List<AiNativeGroup> groups = const [], List<AiLiveShape> liveShapes = const [], bool inheritParentFlags = false}) =>
      _groupNativeArtwork(this, paths, groups, liveShapes, inheritParentFlags);

  /// Combines consecutive ordinary sibling contours into one native compound.
  ///
  /// Complete ordinary subgroups may be selected through [groups]. Geometry,
  /// paint commands, identities and child metadata remain in source order. The
  /// new anonymous `*u`/`*U` owner changes their compound painting relationship;
  /// [bounds] supplies the host-computed affected ink extent. Existing compounds,
  /// live shapes and printing expansions cannot become independent contours.
  /// Mask and non-mask contours cannot share the new compound. Non-neutral or
  /// unknown parent flags require explicit [inheritParentFlags].
  AiNativeDrawing compoundArtwork({required AiBoundingBox bounds, List<AiNativePath> paths = const [], List<AiNativeGroup> groups = const [], bool inheritParentFlags = false}) =>
      _compoundNativeArtwork(this, paths, groups, bounds, inheritParentFlags);

  /// Releases compound boundaries while retaining the complete child artwork.
  ///
  /// Masks become independent masks in saved order; the host must supply [bounds]
  /// including exposed ink and updated derived representations when saving.
  /// Nonempty parent metadata requires [discardMetadata], and removed identities
  /// undergo whole-source reference qualification. Non-neutral or unknown flags
  /// require [inheritParentFlags], as with [ungroup]. Nested ordinary groups,
  /// clipping scopes, child metadata and scalar state remain unchanged.
  /// Qualified imported provenance is retained; a referenced parent or imported
  /// matrix owner cannot be discarded without resolving its separate contract.
  AiNativeDrawing releaseCompounds({required List<AiNativeGroup> groups, required AiBoundingBox bounds, bool discardMetadata = false, bool inheritParentFlags = false}) =>
      _releaseNativeCompounds(this, groups, bounds, discardMetadata, inheritParentFlags);

  /// Wraps consecutive ordinary siblings in a new mask group atomically.
  ///
  /// [masks] supplies owned contour edits with explicit open/closed mask behavior,
  /// optionally replacing their geometry. Select complete compound owners through
  /// [groups] and every contour when making a compound mask. Existing nested mask
  /// groups remain intact; a requested mask must belong to the new outer scope.
  /// The host supplies affected ink [bounds] and derived representations. Saved
  /// contour attributes are replayed after the new `Q` without inventing defaults.
  /// Non-neutral/unknown group flags require explicit [inheritParentFlags].
  AiNativeDrawing clipArtwork({
    required List<AiNativePathEdit> masks,
    required AiBoundingBox bounds,
    List<AiNativePath> paths = const [],
    List<AiNativeGroup> groups = const [],
    bool inheritParentFlags = false,
  }) => _clipNativeArtwork(this, paths, groups, masks, bounds, inheritParentFlags);

  /// Releases disjoint mask groups and only the masks they directly own.
  ///
  /// Nested clipping scopes retain their masks. Compound masks lose their controls
  /// together, with point counts synchronized. Parent metadata and flag policies
  /// match [releaseCompounds]. Saved contour attributes restore following artwork;
  /// unknown required values and unresolved appearance dependencies reject.
  /// An unknown restored value is allowed only when a bounded source check proves
  /// it is overwritten before consumption in both interpretations, across every
  /// boundary removed by this transaction. Literal transparency stays intact.
  AiNativeDrawing releaseClippingGroups({required List<AiNativeGroup> groups, required AiBoundingBox bounds, bool discardMetadata = false, bool inheritParentFlags = false}) =>
      _releaseNativeClipping(this, groups, bounds, discardMetadata, inheritParentFlags);

  /// Dissolves ordinary parents while retaining complete children and local state.
  ///
  /// Qualified CC pairs and their alternatives remain together. Nonempty parent
  /// dictionaries require [discardMetadata]; deleted parent identities undergo a
  /// whole-source reference check, while descendant identities remain unchanged.
  /// Neutral default-group resets are removed; applied styles and opaque owners
  /// reject. Non-neutral or unknown flags require [inheritParentFlags]: children
  /// then inherit the remaining ancestors, without receiving the removed parent's
  /// flags as local assignments.
  AiNativeDrawing ungroup({required List<AiNativeGroup> groups, bool discardMetadata = false, bool inheritParentFlags = false}) =>
      _dissolveNativeGroups(this, groups, discardMetadata, inheritParentFlags);

  /// Copies complete ordinary groups with their qualified inherited state.
  ///
  /// Each copy follows its original. Source assignments restore the copy's input
  /// and the following object's state; unknown required values reject the batch.
  /// [identifiers] supplies fresh XML names for every identified copied group
  /// and path, including descendants, using their original source handles.
  /// Complete qualified CC pairs retain both representations and alternatives;
  /// their IDs use the owning [AiNativeContainer] handles in [identifiers].
  /// Qualified direct live-shape children retain their native parameters.
  AiNativeDrawing duplicateGroups({required List<AiNativeGroup> groups, Map<AiNativeItem, List<int>> identifiers = const {}}) => _duplicateNativeGroups(this, groups, identifiers);

  /// Deletes ordinary groups and children while retaining outgoing state writes.
  ///
  /// Retained paint/lock/visibility assignments preserve following objects.
  /// Drawing bounds stay conservative. Identified groups or descendants require
  /// a qualified whole-source reference scope. Complete qualified CC pairs may
  /// be removed with their parent; partial pairs and unresolved owners reject.
  /// Both native and printing state used by retained artwork remain preserved.
  AiNativeDrawing removeGroups({required List<AiNativeGroup> groups}) => _removeNativeGroups(this, groups);

  /// Reorders selected ordinary sibling groups into their existing source slots.
  ///
  /// Known source assignments preserve incoming and outgoing state in each slot.
  /// Qualified complete CC descendants retain both representations, metadata
  /// alternatives and identities, with separate native/printing state replay.
  /// Unresolved inherited values or dependencies prevent the complete edit.
  AiNativeDrawing reorderGroups({required List<AiNativeGroup> groups}) => _reorderNativeGroups(this, groups);

  /// Moves an ordinary group after another, optionally changing its group parent.
  ///
  /// The groups cannot contain each other. Different layers or ancestor-group
  /// flags/depths require [inheritParentFlags], accepting destination inheritance.
  /// Source assignments retain inherited state and restore following artwork.
  /// Complete qualified CC descendants keep both representations and identities;
  /// unresolved source ownership or required boundary state rejects the edit.
  AiNativeDrawing moveGroupAfter({required AiNativeGroup group, required AiNativeGroup after, bool inheritParentFlags = false}) => _moveNativeGroup(this, group, after, inheritParentFlags);

  /// Appends an ordinary group directly to an existing, possibly empty layer.
  ///
  /// [layer] must belong to this drawing's source program. The state and explicit
  /// destination-inheritance contract of [moveGroupAfter] applies. The group
  /// retains its children and own flags; layer headers/panel data remain exact.
  AiNativeDrawing moveGroupToLayer({required AiNativeGroup group, required AiLayer layer, bool inheritParentFlags = false}) => _moveNativeGroupToLayer(this, group, layer, inheritParentFlags);

  /// Appends a complete ordinary group inside another, possibly empty group.
  ///
  /// Qualified CC descendants retain both representations and their identities.
  /// The source cannot contain [parent]. Different layers or ancestor flags and
  /// depths require [inheritParentFlags]; unresolved boundary state rejects.
  AiNativeDrawing moveGroupToGroup({required AiNativeGroup group, required AiNativeGroup parent, bool inheritParentFlags = false}) => _moveNativeGroupToGroup(this, group, parent, inheritParentFlags);

  /// Attaches host-composed contours to separate native printing expansions.
  ///
  /// Every selected shape must have a bound private outline and a separate
  /// printable group. Supply all its printing paths, with one or more contours
  /// per path. Paint operations, compound nesting, resources, private geometry,
  /// parameters and alternate dictionaries remain unchanged. The host must
  /// compose the contours from that same authoring state and supply matching PDF
  /// artwork; this method does not establish visual equivalence.
  ///
  /// Unresolved bindings, nested authoring records and unknown commands inside
  /// the selected expansion reject. Opaque neighboring objects stay untouched.
  /// Gradient and post-geometry paint wrappers retain one contour per source
  /// path; splitting those wrappers requires a separate paint-topology edit.
  /// This does not change paint/resource topology or create missing expansions.
  /// Existing CC point counts follow each supplied contour; counted closed paths
  /// receive an explicit closing line when their last endpoint is not the first.
  AiNativeDrawing withPrintingContours({required List<AiNativePrintingReplacement> replacements}) => _replaceNativePrintingContours(this, replacements);

  /// Replaces complete host-composed CC groups while retaining native ownership.
  ///
  /// Paths, compound nesting, clipping and process/gradient paints may change. The supplied
  /// group must preserve its outgoing paint state and reference existing unique
  /// gradient resources. Private authoring records, styles and unselected bytes
  /// remain unchanged. The host supplies matching authoring/PDF representations
  /// and ink bounds; this operation does not render or prove visual equivalence.
  /// Clipping retains qualified `q/Q` scopes and `h/H W` contours, including
  /// consistent compound masks. Unknown local state, embedded data and unsupported
  /// paint layouts reject atomically. Source point-count conventions remain coherent.
  AiNativeDrawing withPrintingGroups({required List<AiNativePrintingGroupReplacement> replacements}) => _replaceNativePrintingGroups(this, replacements);

  /// Moves native shapes and their supported painted expansions atomically.
  ///
  /// Offsets use source drawing coordinates, with y increasing upwards. Native
  /// canvas centers use the opposite y direction. Rectangle, ellipse, polygon,
  /// star and line handlers retain their dimensions, corners and live styles.
  /// Solid and linear/radial gradient appearances are synchronized. Patterns,
  /// clipping, transforms and unresolved plug-ins currently
  /// reject the operation; their positional resources need dedicated editors.
  ///
  /// DSC bounds conservatively include both the original and translated extent.
  /// Artboards stay fixed. The host must regenerate the PDF compatibility view
  /// and any cached previews before packaging the edited native program.
  AiNativeDrawing translateLiveShapes({required List<AiLiveShape> shapes, required double deltaX, required double deltaY}) =>
      _LiveShapeEditor(drawing: this, shapes: shapes, deltaX: deltaX, deltaY: deltaY).apply();

  /// Rotates native shapes and their appearances around a drawing-space pivot.
  ///
  /// [radians] is counterclockwise with y upwards, in -2π..2π. The operation
  /// updates canvas centers, native angles, frame angles, private outlines and
  /// printable paths together. CC gradients retain their relative parameters;
  /// printing matrices and per-object accumulated transforms follow the shape.
  /// Shared relative style resources remain shared. Dimensions and stroke widths
  /// remain unchanged. A unique setup `AI11TextDocument.RulerOrigin` is required
  /// to convert drawing coordinates into the native canvas frame.
  ///
  /// The dependency restrictions of [translateLiveShapes] also apply. Unknown
  /// gradient layouts, positional styles and inconsistent accumulated matrices
  /// reject the edit. DSC bounds grow conservatively; artboards stay fixed.
  /// The host must regenerate PDF appearances and other cached previews.
  AiNativeDrawing rotateLiveShapes({required List<AiLiveShape> shapes, required double radians, required double pivotX, required double pivotY}) => _LiveShapeEditor(
    drawing: this,
    shapes: shapes,
    similarity: _LiveShapeSimilarity(drawing: this, radians: radians, pivotX: pivotX, pivotY: pivotY),
  ).apply();

  /// Uniformly scales native shapes, corners and strokes around a drawing pivot.
  ///
  /// [factor] must be finite and positive. All shape dimensions, corner radii,
  /// private/printable curves, stroke widths and dash distances scale together.
  /// CC gradients follow the shape in their respective coordinate systems.
  /// Shared appearance styles are copied for the selection; other artwork and
  /// its inherited paint state remain unchanged. Angles and artboards stay fixed.
  ///
  /// The canvas-origin and dependency restrictions of [rotateLiveShapes] apply.
  /// Nonuniform scaling, reflections and fixed-width/corner resizing require
  /// separate shape or appearance regeneration. The host must regenerate PDF
  /// appearances and other previews before packaging a visual edit.
  AiNativeDrawing scaleLiveShapes({required List<AiLiveShape> shapes, required double factor, required double pivotX, required double pivotY}) => _LiveShapeEditor(
    drawing: this,
    shapes: shapes,
    similarity: _LiveShapeSimilarity(drawing: this, factor: factor, pivotX: pivotX, pivotY: pivotY),
  ).apply();

  /// Gives selected live shapes their own copy of a named gradient resource.
  ///
  /// All appearances of [sourceNameBytes] within each selected object are
  /// rebound to [nameBytes], including private notes and copied known styles.
  /// Other objects, shared styles, swatches and original definitions remain
  /// unchanged. Geometry, colors, ramps and focus initially stay identical.
  /// The new byte name must be unused by both definitions and instances.
  ///
  /// Decode [AiNativeGradientResources] from the returned [records] to edit
  /// the new resource with `replaceStops` or `setRadialFocus`. Each selected
  /// shape must have a matching printable appearance and, when applicable,
  /// a matching known style. Unsupported appearance dependencies or ambiguous
  /// gradient banks reject the transaction. After a visual edit, the host must
  /// synchronize PDF appearances and other cached previews before saving.
  AiNativeDrawing isolateLiveShapeGradient({required List<AiLiveShape> shapes, required List<int> sourceNameBytes, required List<int> nameBytes}) => _LiveShapeEditor(
    drawing: this,
    shapes: shapes,
    gradientEdit: _LiveShapeGradientIsolation(drawing: this, sourceNameBytes: sourceNameBytes, nameBytes: nameBytes),
  ).apply();

  /// Sets relative CC gradient placement inside selected live shapes.
  ///
  /// [originX] and [originY] use the native artwork-relative coordinates;
  /// positive vertical offsets point downwards. [angle] is in degrees within
  /// -360..360. [length] and [aspectRatio] must be positive. Linear gradients
  /// require zero vertical origin and unit aspect ratio.
  ///
  /// All matching appearances within the selection, private notes and copied
  /// known styles change together. Printable matrices and radial focus offsets
  /// are regenerated; paths, shape parameters, resource colors and other users
  /// stay unchanged. Inconsistent native/printing geometry rejects the edit.
  /// Regenerate PDF appearances and previews before saving a visual edit.
  AiNativeDrawing setLiveShapeGradientPlacement({
    required List<AiLiveShape> shapes,
    required List<int> nameBytes,
    required double originX,
    required double originY,
    required double angle,
    required double length,
    double aspectRatio = 1,
  }) => _LiveShapeEditor(
    drawing: this,
    shapes: shapes,
    gradientEdit: _LiveShapeGradientPlacement(drawing: this, nameBytes: nameBytes, placement: [originX, originY, angle, length, aspectRatio]),
  ).apply();
}
