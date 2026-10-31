import 'dart:convert';

import 'package:aikit/src/codec/ai_codec.dart';
import 'package:aikit/src/model/ai_document.dart';
import 'package:aikit/src/model/ai_program.dart';

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

/// An immutable editable node in newly authored Illustrator artwork.
sealed class AiArtworkNode {
  /// Allows typed paths, groups and layers in drawing order.
  const AiArtworkNode();
}

/// An authored open or closed path with independent fill and stroke colors.
final class AiArtworkPath extends AiArtworkNode {
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

/// A native group whose children keep their drawing order and editability.
final class AiArtworkGroup extends AiArtworkNode {
  /// Ordered child objects.
  final List<AiArtworkNode> children;

  /// Copies group membership into an immutable snapshot.
  AiArtworkGroup({required List<AiArtworkNode> children}) : children = List.unmodifiable(children);
}

/// A native layer, including sublayers that remain separate authoring objects.
final class AiArtworkLayer extends AiArtworkNode {
  /// Latin-1 display name, escaped as a PostScript byte string during writing.
  final String name;

  /// Ordered child artwork and nested layers.
  final List<AiArtworkNode> children;

  /// Whether the layer is shown.
  final bool visible;

  /// Whether the layer can be edited.
  final bool locked;

  /// Whether the layer participates in printing.
  final bool printing;

  /// Creates a native layer without flattening hidden children.
  AiArtworkLayer({required this.name, required List<AiArtworkNode> children, this.visible = true, this.locked = false, this.printing = true}) : children = List.unmodifiable(children) {
    latin1.encode(name);
  }

  /// Creates a detached copy with selected layer properties changed.
  AiArtworkLayer copyWith({String? name, List<AiArtworkNode>? children, bool? visible, bool? locked, bool? printing}) => AiArtworkLayer(
    name: name ?? this.name,
    children: children ?? this.children,
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    printing: printing ?? this.printing,
  );
}

/// Creates editable AI7 artwork from typed nodes, with a self-contained prolog.
///
/// This is an explicit legacy authoring target. It does not claim to manufacture
/// Illustrator CC plug-in, live-effect or ATE records. Recent native programs
/// should instead use the source-preserving editor for supported edits.
final class AiArtwork {
  /// Page bounds in PostScript points, including a nonzero origin.
  final AiBoundingBox bounds;

  /// Ordered top-level artwork.
  final List<AiArtworkNode> children;

  /// Creates immutable, typed authoring data.
  AiArtwork({required this.bounds, required List<AiArtworkNode> children}) : children = List.unmodifiable(children);

  /// Serializes native layers, groups, geometry and simple paint as AI7.
  ///
  /// No generic PDF is relabeled as native Illustrator data. The emitted program
  /// includes the drawing operator definitions needed by a PostScript renderer.
  AiPostScriptDocument toPostScript({AiLimits limits = const AiLimits()}) {
    limits.pdf.validate();
    final StringBuffer output = StringBuffer();
    int nodes = 0;

    /// Appends bounded ASCII lines, enforcing the output limit during writing.
    void line(String value) {
      if (output.length + value.length + 1 > limits.pdf.maxFileBytes) {
        throw const FormatException('Authored Illustrator output exceeds the byte limit.');
      }
      output.writeln(value);
    }

    /// Writes finite decimal coordinates in the native numeric grammar.
    String number(double value) => value.toString();

    /// Writes a process color without converting its authored channel space.
    void color(AiColor value, bool stroke) {
      final String operator = switch (value.space) {
        AiColorSpace.gray => stroke ? 'G' : 'g',
        AiColorSpace.rgb => stroke ? 'XA' : 'Xa',
        AiColorSpace.cmyk => stroke ? 'K' : 'k',
      };
      line('${value.channels.map(number).join(' ')} $operator');
    }

    /// Serializes native tree structure with a bounded recursion depth.
    void write(AiArtworkNode node, int depth) {
      if (depth > limits.pdf.maxDepth || ++nodes > limits.pdf.maxObjects) {
        throw const FormatException('Authored Illustrator structure exceeds its limits.');
      }
      switch (node) {
        case AiArtworkLayer():
          line('%AI5_BeginLayer');
          line('${node.visible ? 1 : 0} 1 ${node.locked ? 0 : 1} ${node.printing ? 1 : 0} 0 0 0 79 128 255 Lb');
          line('(${latin1.encode(node.name).map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()}) Ln');
          for (final AiArtworkNode child in node.children) {
            write(child, depth + 1);
          }
          line('LB');
          line('%AI5_EndLayer');
        case AiArtworkGroup():
          line('u');
          for (final AiArtworkNode child in node.children) {
            write(child, depth + 1);
          }
          line('U');
        case AiArtworkPath():
          line('${node.locked ? 1 : 0} A');
          if (node.fill case final AiColor fill) {
            color(fill, false);
          }
          if (node.stroke case final AiColor stroke) {
            color(stroke, true);
          }
          line('${number(node.strokeWidth)} w ${node.lineCap} J ${node.lineJoin} j ${number(node.miterLimit)} M');
          line('[${node.dash.map(number).join(' ')}] ${number(node.dashPhase)} d');
          line('${node.evenOdd ? 1 : 0} XR');
          for (final AiPathSegment segment in node.segments) {
            line('${segment.coordinates.map(number).join(' ')} ${segment.operator}');
          }
          final String paint = node.fill == null
              ? (node.stroke == null ? 'N' : 'S')
              : node.stroke == null
              ? 'F'
              : 'B';
          line(node.closed ? paint.toLowerCase() : paint);
      }
    }

    line('%!PS-Adobe-3.0');
    line('%%Creator: AiKit');
    line('%%BoundingBox: ${bounds.left.floor()} ${bounds.bottom.floor()} ${bounds.right.ceil()} ${bounds.top.ceil()}');
    line('%%HiResBoundingBox: ${bounds.left} ${bounds.bottom} ${bounds.right} ${bounds.top}');
    line('%AI5_FileFormat: 3');
    line('%%EndComments');
    line('%%BeginProlog');
    line(_artworkProlog);
    line('%%EndProlog');
    line('%%BeginSetup');
    line('AiKitDrawing begin');
    line('%%EndSetup');
    for (final AiArtworkNode child in children) {
      write(child, 0);
    }
    line('%%PageTrailer');
    line('end showpage');
    line('%%Trailer');
    line('%%EOF');
    return AiDecoder(limits: limits).convert(latin1.encode(output.toString())) as AiPostScriptDocument;
  }
}

/// Self-contained PostScript definitions for the emitted AI7 operator subset.
const String _artworkProlog = r'''
/AiKitDrawing 80 dict def AiKitDrawing begin
/_shown true def /_fill [0] def /_stroke [0] def /_evenOdd false def
/_color { dup length 1 eq { aload pop setgray } {
  dup length 3 eq { aload pop setrgbcolor } { aload pop setcmykcolor } ifelse
} ifelse } bind def
/g { 1 array astore /_fill exch def } bind def
/G { 1 array astore /_stroke exch def } bind def
/Xa { 3 array astore /_fill exch def } bind def
/XA { 3 array astore /_stroke exch def } bind def
/k { 4 array astore /_fill exch def } bind def
/K { 4 array astore /_stroke exch def } bind def
/A { pop } bind def /XR { 0 ne /_evenOdd exch def } bind def
/w { setlinewidth } bind def /J { setlinecap } bind def
/j { setlinejoin } bind def /M { setmiterlimit } bind def /d { setdash } bind def
/m { moveto } bind def /l { lineto } bind def /L { lineto } bind def
/c { curveto } bind def /C { curveto } bind def
/v { 4 dict begin /ey exch def /ex exch def /cy exch def /cx exch def
  currentpoint cx cy ex ey curveto end } bind def
/V { v } bind def /y { 2 copy curveto } bind def /Y { y } bind def
/_paintFill { _fill _color _evenOdd { eofill } { fill } ifelse } bind def
/N { newpath } bind def /n { closepath N } bind def
/F { _shown { _paintFill } { newpath } ifelse } bind def
/S { _shown { _stroke _color stroke } { newpath } ifelse } bind def
/B { _shown { gsave _paintFill grestore _stroke _color stroke } { newpath } ifelse } bind def
/f { closepath F } bind def /s { closepath S } bind def /b { closepath B } bind def
/u { gsave 8 dict begin } bind def /U { end grestore } bind def
/Lb { 16 dict begin pop pop pop pop pop pop /_printing exch 0 ne def pop pop
  /_shown exch 0 ne _shown and _printing and def } bind def
/Ln { pop } bind def /LB { end } bind def
end''';
