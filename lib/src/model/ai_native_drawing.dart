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
      _LiveShapeTransform(drawing: this, shapes: shapes, deltaX: deltaX, deltaY: deltaY).apply();

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
  AiNativeDrawing rotateLiveShapes({required List<AiLiveShape> shapes, required double radians, required double pivotX, required double pivotY}) => _LiveShapeTransform(
    drawing: this,
    shapes: shapes,
    rotation: _LiveShapeRotation(drawing: this, radians: radians, pivotX: pivotX, pivotY: pivotY),
  ).apply();
}
