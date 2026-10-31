part of 'package:aikit/src/model/ai_native_records.dart';

/// Known ruler display units; drawing coordinates are not converted by the kit.
enum AiNativeRulerUnit {
  /// Inches, stored as ordinary ruler code 0.
  inches,

  /// Millimeters, stored as ordinary ruler code 1.
  millimeters,

  /// Points, stored as ordinary ruler code 2.
  points,

  /// Picas, stored as ordinary ruler code 3.
  picas,

  /// Centimeters, stored as ordinary ruler code 4.
  centimeters,

  /// Pixels, stored as ordinary ruler code 6.
  pixels,

  /// Mixed feet/inches, stored as large ruler code 7.
  feetAndInches,

  /// Meters, stored as large ruler code 8.
  meters,

  /// Yards, stored as large ruler code 9.
  yards,

  /// Feet, stored as large ruler code 10.
  feet,
}

/// One validated numeric declaration retaining its exact header source span.
final class AiNativeHeaderField {
  /// Complete original comment token, including its prefix and numeric spelling.
  final AiToken token;

  /// Finite numeric components in source order.
  final List<double> values;

  /// Captures a declaration without normalizing its source bytes.
  AiNativeHeaderField._({required this.token, required List<double> values}) : values = List.unmodifiable(values);
}

/// A saved text-document ruler origin with explicit native record ownership.
final class AiNativeTextRulerOrigin {
  /// Owning setup AI11TextDocument, not an artboard or PDF page.
  final AiNativeContainer document;

  /// Source entry that stores the two canvas coordinates.
  final AiNativeEntry entry;

  /// Creates an origin after validating its numeric layout.
  const AiNativeTextRulerOrigin._({required this.document, required this.entry});

  /// Canvas coordinates with y down; no page-origin fallback is inferred.
  List<double> get coordinates => entry.numbers!;
}

/// Source-backed document settings without inferred page or object ownership.
///
/// Header declarations, artboard ruler origins and text-document origins remain
/// separate. Missing settings stay absent, unknown unit codes remain available,
/// and conditional or repeated header settings are not chosen implicitly.
final class AiNativeDocumentSettings {
  /// Immutable native snapshot owning all returned fields and records.
  final AiNativeRecords records;

  /// Qualified numeric comments keyed by their DSC names without punctuation.
  final Map<String, AiNativeHeaderField> header;

  /// Top-level Document records, retaining Recorded and NotRecorded sections.
  final List<AiNativeContainer> documents;

  /// Artboards in source order, each retaining its document and local index.
  final List<AiNativeArtboard> artboards;

  /// Explicit setup text origins, without merging independent documents.
  final List<AiNativeTextRulerOrigin> textRulerOrigins;

  /// Reads bounded settings without reshaping or editing native records.
  factory AiNativeDocumentSettings.decode({required AiNativeRecords records}) => _nativeDocumentSettings(records);

  /// Owns the validated collections while retaining original source handles.
  AiNativeDocumentSettings._({
    required this.records,
    required Map<String, AiNativeHeaderField> header,
    required List<AiNativeContainer> documents,
    required List<AiNativeArtboard> artboards,
    required List<AiNativeTextRulerOrigin> textRulerOrigins,
  }) : header = Map.unmodifiable(header),
       documents = List.unmodifiable(documents),
       artboards = List.unmodifiable(artboards),
       textRulerOrigins = List.unmodifiable(textRulerOrigins);

  /// Original ordinary ruler code, including unknown future values.
  int? get rulerUnitCode => header['AI5_RulerUnits']?.values.single.toInt();

  /// Explicit large-canvas ruler code, taking precedence even when unknown.
  int? get largeRulerUnitCode => header['AI24_RulerUnitsLarge']?.values.single.toInt();

  /// Known display unit, or null for absent or unqualified codes.
  AiNativeRulerUnit? get rulerUnit => largeRulerUnitCode != null
      ? switch (largeRulerUnitCode) {
          7 => .feetAndInches,
          8 => .meters,
          9 => .yards,
          10 => .feet,
          _ => null,
        }
      : switch (rulerUnitCode) {
          0 => .inches,
          1 => .millimeters,
          2 => .points,
          3 => .picas,
          4 => .centimeters,
          6 => .pixels,
          _ => null,
        };

  /// Explicit canvas scale, without applying it or inventing a missing value.
  double? get largeCanvasScale => header['AI24_LargeCanvasScale']?.values.single;

  /// Declared square canvas extent or pair of extents, without deriving bounds.
  List<double>? get canvasSize => header['Canvassize']?.values;

  /// Saved template coordinates, independent of artboards and artwork ink bounds.
  List<double>? get templateBox => header['AI3_TemplateBox']?.values;

  /// Saved page-origin pair, never substituted for a canvas ruler origin.
  List<double>? get pageOrigin => header['PageOrigin']?.values;
}
