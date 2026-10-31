part of 'package:aikit/src/model/ai_native_records.dart';

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

  /// Duplicates ordinary paths immediately after their original source objects.
  ///
  /// Geometry, paint, comments and optional CC point counts are copied. Existing
  /// paint/lock/visibility state remains in place and is inherited by each copy.
  /// Private authoring paths, derived expansions, compound/clip members and
  /// unresolved attached metadata reject. Copies have no synthesized identifiers.
  AiNativeDrawing duplicatePaths({required List<AiNativePath> paths}) => _duplicateNativePaths(this, paths);

  /// Removes ordinary geometry and owned point counts, retaining surrounding state.
  ///
  /// Unselected bytes and paint/lock/visibility assignments remain unchanged.
  /// Existing drawing bounds remain conservative. Paths with unresolved native
  /// owners, references or attached metadata reject before applying any edits.
  AiNativeDrawing removePaths({required List<AiNativePath> paths}) => _removeNativePaths(this, paths);

  /// Inserts geometry using each anchor's existing paint, flags and count layout.
  ///
  /// Input order is retained when several insertions share an anchor. Counted
  /// closed paths receive an explicit closing line when necessary. The same
  /// ownership restrictions as [duplicatePaths] apply; this does not create a
  /// missing modern document, layer, resource or private live-shape definition.
  /// Saving requires matching host-supplied PDF artwork through the save API.
  AiNativeDrawing insertPaths({required List<AiNativePathInsertion> insertions}) => _insertNativePaths(this, insertions);

  /// Reorders selected sibling paths into their existing source positions.
  ///
  /// [paths] gives the desired order. Source assignments preserve each path's
  /// paint and object flags and restore the following artwork's state. Unknown
  /// required values, metadata and other object kinds reject. Geometry, paint
  /// and point counts move together without changing unrelated source bytes.
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

  /// Groups contiguous ordinary sibling paths without changing their source order.
  ///
  /// Optional point counts and intervening qualified state stay with the paths.
  /// Unselected siblings, private owners and attached metadata reject atomically.
  AiNativeDrawing groupPaths({required List<AiNativePath> paths}) => _groupNativePaths(this, paths);

  /// Removes ordinary group boundaries while retaining their children and state.
  ///
  /// Groups must be anonymous independent owners, with no compound/clip members,
  /// derived artwork, attached metadata or unresolved state instructions.
  AiNativeDrawing ungroup({required List<AiNativeGroup> groups}) => _ungroupNativeGroups(this, groups);

  /// Copies complete ordinary groups with their qualified inherited state.
  ///
  /// Each copy follows its original. Source assignments restore the copy's input
  /// and the following object's state; unknown required values reject the batch.
  AiNativeDrawing duplicateGroups({required List<AiNativeGroup> groups}) => _duplicateNativeGroups(this, groups);

  /// Deletes ordinary groups and children while retaining outgoing state writes.
  ///
  /// Retained paint/lock/visibility assignments preserve following objects.
  /// Drawing bounds stay conservative; referenced or derived groups reject.
  AiNativeDrawing removeGroups({required List<AiNativeGroup> groups}) => _removeNativeGroups(this, groups);

  /// Reorders selected ordinary sibling groups into their existing source slots.
  ///
  /// Known source assignments preserve incoming and outgoing state in each slot.
  /// Unresolved inherited values or dependencies prevent the complete edit.
  AiNativeDrawing reorderGroups({required List<AiNativeGroup> groups}) => _reorderNativeGroups(this, groups);

  /// Moves an ordinary group after another, optionally changing its group parent.
  ///
  /// The groups cannot contain each other. Different layers or ancestor-group
  /// flags/depths require [inheritParentFlags], accepting destination inheritance.
  /// Source assignments retain inherited state and restore following artwork.
  /// The interval cannot cross opaque metadata, private art or unknown state.
  AiNativeDrawing moveGroupAfter({required AiNativeGroup group, required AiNativeGroup after, bool inheritParentFlags = false}) => _moveNativeGroup(this, group, after, inheritParentFlags);

  /// Appends an ordinary group directly to an existing, possibly empty layer.
  ///
  /// [layer] must belong to this drawing's source program. The state and explicit
  /// destination-inheritance contract of [moveGroupAfter] applies. The group
  /// retains its children and own flags; layer headers/panel data remain exact.
  AiNativeDrawing moveGroupToLayer({required AiNativeGroup group, required AiLayer layer, bool inheritParentFlags = false}) => _moveNativeGroupToLayer(this, group, layer, inheritParentFlags);

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
  /// Paths, compound nesting and process/gradient paints may change. The supplied
  /// group must preserve its outgoing paint state and reference existing unique
  /// gradient resources. Private authoring records, styles and unselected bytes
  /// remain unchanged. The host supplies matching authoring/PDF representations
  /// and ink bounds; this operation does not render or prove visual equivalence.
  /// Unknown local state, clipping, embedded data and unsupported paint layouts
  /// reject atomically. Source point-count conventions must remain coherent.
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
