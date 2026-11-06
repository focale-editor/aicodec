part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Native document working mode, independent of the host's color conversion.
enum AiNativeDocumentColorMode {
  /// CMYK document mode, stored as native code zero.
  cmyk,

  /// RGB document mode, stored as native code one.
  rgb,
}

/// An authored layer tree for initial document creation, without source handles.
final class AiNativeDocumentLayer {
  /// Explicit layer attributes, name, panel state and optional XML identity.
  final AiNativeLayerDefinition definition;

  /// Ordinary native paths, in paint order before this layer's child layers.
  final List<AiNativePathDefinition> paths;

  /// Nested layers, in native source order.
  final List<AiNativeDocumentLayer> children;

  /// Freezes the tree; creation validates aggregate depth, identities and bytes.
  AiNativeDocumentLayer({required this.definition, List<AiNativePathDefinition> paths = const [], List<AiNativeDocumentLayer> children = const []})
    : paths = List.unmodifiable(paths),
      children = List.unmodifiable(children);
}

/// Explicit correspondence between a new document's native board and PDF page.
final class AiNativeDocumentPage {
  /// Current artboard from the exact native records being packaged.
  final AiNativeArtboard artboard;

  /// Current indirect page in the supplied PDF graph.
  final PdfReference page;

  /// Binds representations without deriving page order from names or UUIDs.
  const AiNativeDocumentPage({required this.artboard, required this.page});
}

/// Creates editable CC native documents and their first PDF-backed AI container.
///
/// No source file, Adobe template, renderer or application dependency is needed.
/// Native creation authors a version-24 profile. The host supplies all printing
/// and PDF representations and remains responsible for their visual equivalence.
abstract final class AiNativeDocument {
  /// Builds bounded native records with boards, layer trees and ordinary paths.
  ///
  /// Artboard names retain their supplied native UnicodeString byte encoding;
  /// layer names and title retain native string bytes. All identities are supplied
  /// by the host. Bounds enclose the supplied ink bounds of every created path;
  /// without inkBounds they also enclose all boards. Ruler coordinates are explicit
  /// in each board definition; pageOrigin does not translate any geometry.
  /// No fonts, profiles, previews or advanced appearances are synthesized. Populate
  /// further native data through existing APIs before calling createPdf.
  static AiNativeRecords create({
    required List<AiNativeArtboardDefinition> artboards,
    required List<AiNativeDocumentLayer> layers,
    required List<int> titleBytes,
    required AiNativeDocumentColorMode colorMode,
    required DateTime createdAt,
    int activeArtboard = 0,
    int? lastArtboardId,
    AiBoundingBox? inkBounds,
    AiNativeRulerUnit rulerUnit = .points,
    List<double> pageOrigin = const [0, 0],
    double canvasSize = 16383,
    AiNativeLimits limits = const AiNativeLimits(),
  }) => _createNativeDocument(artboards, layers, titleBytes, colorMode, createdAt, activeArtboard, lastArtboardId ?? artboards.length, inkBounds, rulerUnit, pageOrigin, canvasSize, limits);

  /// Packages current native records and matching host PDF pages without a template.
  ///
  /// Supply every current board/page once in their shared order. Unrotated unit-
  /// scale PDF pages must match board dimensions at TrimBox, or CropBox/MediaBox
  /// when absent. Bleed MediaBoxes and nonzero PDF origins are retained. The host
  /// supplies the corresponding content transforms; they are not inferred.
  /// Existing Illustrator attachments reject, including partial ones. Other PDF
  /// metadata/resources stay exact. Version-24 Zstandard blocks and a full header
  /// cache are shared by all pages; no stale native thumbnails are invented.
  /// Reopen/extract the result and use AiNativeData.replace for subsequent saves.
  /// Unknown artwork operators are preserved, not treated as editable or rendered.
  static AiPdfDocument createPdf({
    required AiNativeRecords records,
    required PdfDocument compatibilityPdf,
    required List<AiNativeDocumentPage> pages,
    required DateTime modifiedAt,
    int blockBytes = 1024 * 1024,
  }) => _createNativeDocumentPdf(records, compatibilityPdf, pages, modifiedAt, blockBytes);
}
