import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aikit/src/codec/ai_native_data.dart';
import 'package:aikit/src/codec/ai_postscript.dart';
import 'package:aikit/src/model/ai_document.dart';
import 'package:aikit/src/model/ai_native_records.dart';
import 'package:aikit/src/model/ai_program.dart';
import 'package:pdfcore/pdfcore.dart';

part '../codec/ai_printable_gradient.dart';
part '../codec/ai_printable_parser.dart';
part '../codec/ai_printable_raster.dart';
part '../editing/ai_printable_gradient_writer.dart';
part '../editing/ai_printable_raster_writer.dart';
part '../editing/ai_printable_pdf_writer.dart';

/// Supplies explicit process pixels for one current native linked placement.
///
/// The host resolves file paths, decodes image formats and chooses color policy
/// before rendering. Returning null rejects an unresolved link; saved previews
/// are never used implicitly. The callback runs once per printable placement,
/// including placements in hidden layers, and never for private authoring art.
/// It may return `object.preview?.toSamples()` as an explicit preview fallback.
typedef AiNativePlacementResolver = AiNativeRasterSamples? Function(AiNativePlacedObject object);

/// Rebuilds PDF compatibility artwork from native printable Illustrator drawings.
///
/// This interprets declarative process-color paths, layers, groups, compound
/// paths, clipping, classic gradient fills/strokes, embedded or host-resolved
/// process-color images and supported opacity records.
/// It does not execute a prolog.
/// Unsupported drawing operations reject the whole export. Private authoring
/// paths remain in the native program and do not paint a second time.
abstract final class AiNativePdf {
  /// Exports a native drawing into one bounded PDF page.
  ///
  /// [bounds] specifies the page in native drawing points, with y upwards.
  /// It is explicit because artwork bounds and Illustrator artboards differ.
  /// Hidden or nonprinting layers do not paint; their authoring data is retained
  /// only when packaging with [save]. Classic gradients require explicit
  /// printing matrices and process colors; stop opacity uses a PDF soft mask.
  /// Stroke appearances retain their curves, dashes, caps and joins as PDF paths.
  /// Compound contours share their final paint, including gradients and holes.
  /// Complete gradient appearance notes without a path do not paint.
  /// Embedded binary rasters retain native samples, placement and separate alpha.
  /// [resolvePlacement] supplies pixels for qualified CC raster links without
  /// incorporating them into the native program. Missing links, text, patterns,
  /// spot colors and unresolved appearances reject export.
  static PdfDocument render({required AiProgram program, required AiBoundingBox bounds, AiNativePlacementResolver? resolvePlacement, PdfLimits limits = const PdfLimits()}) {
    limits.validate();
    final PdfDocument empty = PdfDocument.fromPages(
      pages: [PdfPageSource(width: bounds.right - bounds.left, height: bounds.top - bounds.bottom, content: [])],
    );
    final PdfDocument document = PdfDocument(objects: empty.objects, trailer: empty.trailer, limits: limits);
    return _writePrintablePdf(program, document, [bounds], resolvePlacement);
  }

  /// Saves edited native bytes and regenerated PDF pages in one new snapshot.
  ///
  /// [source] must be the document's sole extracted native program. Each entry
  /// in [pageBounds] maps one existing PDF page to native drawing coordinates;
  /// its dimensions must match that page's MediaBox. Page trees, metadata,
  /// annotations and other producers' private data remain in the original graph.
  /// All owners of the Illustrator program receive the same rewritten bytes.
  ///
  /// The native operation must already have synchronized its printable paths.
  /// This method does not regenerate them from opaque effects or ATE data. It
  /// rejects unsupported visible and hidden operations instead of dropping art.
  /// [resolvePlacement] updates PDF image appearances while keeping the native
  /// file references, preview bytes and placed-object records unchanged.
  static AiPdfDocument save({
    required AiNativeSource source,
    required AiProgram program,
    required List<AiBoundingBox> pageBounds,
    AiNativePlacementResolver? resolvePlacement,
    AiNativeLimits limits = const AiNativeLimits(),
  }) {
    final AiDocument original = source.document;
    if (original is! AiPdfDocument || AiNativeData.extract(original, limits: limits).length != 1) {
      throw ArgumentError('PDF synchronization requires a single native program in a PDF-backed document.');
    }
    final PdfDocument synchronized = _writePrintablePdf(program, original.pdf, pageBounds, resolvePlacement);
    return AiNativeData.replace(source: source, program: program.bytes, synchronizedPdf: synchronized, limits: limits);
  }
}

/// One drawable path or container with independent object-level opacity.
final class _PrintableNode {
  /// Fully specified PDF path paint, or container-local child nodes.
  final List<PdfOperation> operations;

  /// Children in native drawing order.
  final List<_PrintableNode> children;

  /// Whether this node is a group eligible for a following appearance modifier.
  final bool group;

  /// Whether a clipping path must persist in the enclosing graphics state.
  final bool clip;

  /// Whether layer visibility and printing flags allow this node to paint.
  final bool visible;

  /// Native gradient fill or stroke and its absolute printing geometry.
  final _PrintableGradient? gradient;

  /// Embedded or explicitly resolved image pixels and their native placement.
  final _PrintableRaster? raster;

  /// Stroke painted after the gradient clip has been restored.
  final List<PdfOperation> gradientStroke;

  /// Winding rule used to bound the gradient to its painted geometry.
  final bool evenOdd;

  /// Opacity applied to the complete object, including overlapping fill/stroke.
  double opacity;

  /// PDF blend mode applied to this complete native object.
  String blend;

  /// Whether a group blends its children against a transparent backdrop.
  bool isolated;

  /// Whether group members knock out one another before group compositing.
  bool knockout;

  /// Captures a node during bounded compilation, before exposing the PDF graph.
  _PrintableNode({
    this.operations = const [],
    this.children = const [],
    this.group = false,
    this.clip = false,
    this.visible = true,
    this.gradient,
    this.raster,
    this.gradientStroke = const [],
    this.evenOdd = false,
    this.opacity = 1,
    this.blend = 'Normal',
    this.isolated = false,
    this.knockout = false,
  });
}

/// Native style state, retained across object boundaries until explicitly changed.
final class _PrintableState {
  /// Current process paints and stroke attributes, with explicit PDF defaults.
  final Map<String, PdfOperation> attributes;

  /// Current fill rule.
  bool evenOdd;

  /// Object opacity from the native path modifier.
  double opacity;

  /// Current Illustrator blend mode mapped to its PDF name.
  String blend;

  /// Current group-isolation flag.
  bool isolated;

  /// Current group-knockout flag.
  bool knockout;

  /// Initializes native style tracking with the default opaque normal paint.
  _PrintableState() : attributes = {}, evenOdd = false, opacity = 1, blend = 'Normal', isolated = false, knockout = false;

  /// Captures the final subpath's paint before later instructions change state.
  _PrintableState.copy({required _PrintableState source})
    : attributes = Map.of(source.attributes),
      evenOdd = source.evenOdd,
      opacity = source.opacity,
      blend = source.blend,
      isolated = source.isolated,
      knockout = source.knockout;
}

/// One native group or layer while the bounded instruction stream is compiled.
final class _PrintableContainer {
  /// Matching closing native operator, or empty for the root.
  final String end;

  /// Whether this layer participates in visible printing.
  final bool visible;

  /// Completed child nodes in source order.
  final List<_PrintableNode> children = [];

  /// Compound geometry accumulated until the group's final paint is known.
  final List<PdfOperation> compound = [];

  /// Final compound paint, whose style applies to every subpath.
  String? paint;

  /// Final subpath's complete style, shared by all compound contours.
  _PrintableState? paintState;

  /// Gradient declared on the final subpath, shared by the compound fill.
  _PrintableGradient? gradient;

  /// Whether the compound group establishes a clipping path.
  bool clip = false;

  /// Retains the bounded group boundary and layer visibility.
  _PrintableContainer({required this.end, this.visible = true});
}
