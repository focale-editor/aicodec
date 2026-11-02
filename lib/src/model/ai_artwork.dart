import 'package:aicodec/src/model/ai_program.dart';

/// Device color channels used by editable Illustrator path artwork.
enum AiColorSpace {
  /// A single gray channel, from black to white.
  gray,

  /// Red, green and blue light components.
  rgb,

  /// Cyan, magenta, yellow and black ink components.
  cmyk,
}

/// Immutable process color retaining its authored color space.
final class AiColor {
  /// The meaning and number of the stored channels.
  final AiColorSpace space;

  /// Finite normalized channel values.
  final List<double> channels;

  /// Creates a checked process color.
  AiColor({required this.space, required List<double> channels}) : channels = List.unmodifiable(channels) {
    final int expected = switch (space) {
      AiColorSpace.gray => 1,
      AiColorSpace.rgb => 3,
      AiColorSpace.cmyk => 4,
    };
    if (channels.length != expected || channels.any((value) => !value.isFinite || value < 0 || value > 1)) {
      throw ArgumentError('Invalid Illustrator process color.');
    }
  }
}

/// An authored open or closed path with independent fill and stroke colors.
final class AiArtworkPath {
  /// Geometry retaining smooth and corner point distinctions.
  final List<AiPathSegment> segments;

  /// Fill color, or null for an unfilled path.
  final AiColor? fill;

  /// Stroke color, or null for an unstroked path.
  final AiColor? stroke;

  /// Whether to close the editable path before painting.
  final bool closed;

  /// Whether fills use the even-odd winding rule.
  final bool evenOdd;

  /// Stroke width in points; zero requests a device hairline.
  final double strokeWidth;

  /// Line cap: zero for butt, one for round, two for square.
  final int lineCap;

  /// Line join: zero for miter, one for round, two for bevel.
  final int lineJoin;

  /// Maximum miter length divided by stroke width.
  final double miterLimit;

  /// Alternating painted and unpainted stroke lengths.
  final List<double> dash;

  /// Offset into the dash sequence.
  final double dashPhase;

  /// Whether the path is locked in Illustrator's editor.
  final bool locked;

  /// Creates checked artwork without silently substituting unsupported paints.
  AiArtworkPath({
    required List<AiPathSegment> segments,
    this.fill,
    this.stroke,
    this.closed = false,
    this.evenOdd = false,
    this.strokeWidth = 1,
    this.lineCap = 0,
    this.lineJoin = 0,
    this.miterLimit = 4,
    List<double> dash = const [],
    this.dashPhase = 0,
    this.locked = false,
  }) : segments = List.unmodifiable(segments),
       dash = List.unmodifiable(dash) {
    if (segments.isEmpty || segments.first.operator != 'm' || segments.skip(1).any((segment) => segment.operator == 'm')) {
      throw ArgumentError('Each Illustrator path must contain exactly one initial moveto.');
    }
    if (!strokeWidth.isFinite ||
        strokeWidth < 0 ||
        !miterLimit.isFinite ||
        miterLimit < 1 ||
        !dashPhase.isFinite ||
        lineCap < 0 ||
        lineCap > 2 ||
        lineJoin < 0 ||
        lineJoin > 2 ||
        dash.any((value) => !value.isFinite || value < 0) ||
        dash.isNotEmpty && dash.every((value) => value == 0)) {
      throw ArgumentError('Invalid Illustrator stroke attributes.');
    }
  }

  /// Replaces geometry and simple appearance without mutating the source node.
  ///
  /// Set [clearFill] or [clearStroke] to remove the corresponding paint.
  AiArtworkPath copyWith({
    List<AiPathSegment>? segments,
    AiColor? fill,
    AiColor? stroke,
    bool clearFill = false,
    bool clearStroke = false,
    bool? closed,
    bool? evenOdd,
    double? strokeWidth,
    int? lineCap,
    int? lineJoin,
    double? miterLimit,
    List<double>? dash,
    double? dashPhase,
    bool? locked,
  }) => AiArtworkPath(
    segments: segments ?? this.segments,
    fill: clearFill ? null : fill ?? this.fill,
    stroke: clearStroke ? null : stroke ?? this.stroke,
    closed: closed ?? this.closed,
    evenOdd: evenOdd ?? this.evenOdd,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    lineCap: lineCap ?? this.lineCap,
    lineJoin: lineJoin ?? this.lineJoin,
    miterLimit: miterLimit ?? this.miterLimit,
    dash: dash ?? this.dash,
    dashPhase: dashPhase ?? this.dashPhase,
    locked: locked ?? this.locked,
  );
}
