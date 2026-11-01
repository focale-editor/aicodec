part of 'package:aikit/src/model/ai_native_records.dart';

/// One retained, copied or newly authored child of an appearance stack or chain.
final class AiNativeAppearanceChild {
  /// Current source handle for retention or an unchanged snapshot copy.
  final AiNativeAppearancePart? part;

  /// Whether to copy original source bytes without applying changes to that copy.
  final bool copied;

  /// Authored data for a new child, absent for source-backed children.
  final AiNativeAppearancePartDefinition? definition;

  /// Retains or moves one original subtree, including edits to its current handles.
  const AiNativeAppearanceChild.retain({required AiNativeAppearancePart this.part}) : copied = false, definition = null;

  /// Duplicates an original subtree independently of edits to retained source data.
  const AiNativeAppearanceChild.copy({required AiNativeAppearancePart this.part}) : copied = true, definition = null;

  /// Creates a new native part from explicit data without generating its rendering.
  const AiNativeAppearanceChild.create({required AiNativeAppearancePartDefinition this.definition}) : part = null, copied = false;
}

/// Explicit process paints and structural parts for native appearance creation.
///
/// New values are serialized literally. Supplied CMYK/RGB alternatives are never
/// converted, and the host supplies the matching printing and PDF representations.
final class AiNativeAppearancePartDefinition {
  /// Qualified part type to serialize.
  final AiNativeAppearancePartKind kind;

  /// Explicit visibility of the new part.
  final bool visible;

  /// One process color or authored CMYK followed by RGB alternatives.
  final List<AiColor> colors;

  /// Explicit overprint flag for a new fill or stroke.
  final bool overprint;

  /// Normal-blend paint opacity, between zero and one.
  final double opacity;

  /// Explicit winding rule for a fill or stroke paint.
  final bool evenOdd;

  /// Width in points, including zero for a hairline.
  final double strokeWidth;

  /// Butt, round or square cap encoded as zero, one or two.
  final int lineCap;

  /// Miter, round or bevel join encoded as zero, one or two.
  final int lineJoin;

  /// Maximum miter length divided by stroke width.
  final double miterLimit;

  /// Ordered alternating painted and unpainted lengths.
  final List<double> dash;

  /// Offset into the supplied dash sequence.
  final double dashPhase;

  /// Centered stroke or an explicit native inside/outside offset descriptor.
  final AiNativeStrokeAlignment strokeAlignment;

  /// Host-supplied display label required for an inside/outside stroke descriptor.
  final List<int>? alignmentLabelBytes;

  /// Ordered children for a new stack or chain; empty for basic parts.
  final List<AiNativeAppearanceChild> children;

  /// Creates supported parts with explicit defaults and immutable payloads.
  AiNativeAppearancePartDefinition({
    required this.kind,
    this.visible = true,
    List<AiColor> colors = const [],
    this.overprint = false,
    this.opacity = 1,
    this.evenOdd = false,
    this.strokeWidth = 1,
    this.lineCap = 0,
    this.lineJoin = 0,
    this.miterLimit = 4,
    List<double> dash = const [],
    this.dashPhase = 0,
    this.strokeAlignment = .center,
    List<int>? alignmentLabelBytes,
    List<AiNativeAppearanceChild> children = const [],
  }) : colors = List.unmodifiable(colors),
       dash = List.unmodifiable(dash),
       alignmentLabelBytes = alignmentLabelBytes == null ? null : List.unmodifiable(alignmentLabelBytes),
       children = List.unmodifiable(children) {
    final bool paint = kind == .fill || kind == .stroke;
    final bool compound = kind == .stack || kind == .chain;
    if (!paint && !compound && kind != .conduit ||
        !compound && children.isNotEmpty ||
        paint && !(colors.length == 1 || colors.length == 2 && colors[0].space == .cmyk && colors[1].space == .rgb) ||
        !paint && colors.isNotEmpty) {
      throw ArgumentError('New appearances require a supported part with its own paint or child payload.');
    }
    if (![opacity, strokeWidth, miterLimit, dashPhase, ...dash].every((value) => value.isFinite && value.abs() <= 9007199254740991) ||
        opacity < 0 ||
        opacity > 1 ||
        strokeWidth < 0 ||
        miterLimit < 1 ||
        lineCap < 0 ||
        lineCap > 2 ||
        lineJoin < 0 ||
        lineJoin > 2 ||
        dash.any((value) => value < 0) ||
        dash.isNotEmpty && dash.every((value) => value == 0)) {
      throw ArgumentError('New appearance paint attributes must be finite, portable and valid.');
    }
    if ((kind == .stroke && strokeAlignment != .center) != (alignmentLabelBytes != null) ||
        alignmentLabelBytes?.any((byte) => byte < 0 || byte > 255) == true ||
        kind != .stroke && (strokeAlignment != .center || strokeWidth != 1 || lineCap != 0 || lineJoin != 0 || miterLimit != 4 || dash.isNotEmpty || dashPhase != 0) ||
        !paint && (overprint || opacity != 1 || evenOdd)) {
      throw ArgumentError('Appearance settings must belong to their selected part; offset strokes require host label bytes.');
    }
  }
}
