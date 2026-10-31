part of 'package:aikit/src/model/ai_native_records.dart';

/// Ordered artboards and separate active, selected and crop state for one owner.
///
/// `CropAreaActive` chooses an artboard independently of `IsArtboardSelected`.
/// The program's `AI3_Cropmarks` rectangle is retained separately, without
/// equating it with the selected/active board, drawing bounds or a PDF page.
final class AiNativeArtboards {
  /// Immutable source snapshot owning the document and its native fields.
  final AiNativeRecords records;

  /// Explicit top-level Document owner, never inferred from PDF page counts.
  final AiNativeContainer document;

  /// Source-ordered artboards belonging only to this document.
  final List<AiNativeArtboard> artboards;

  /// Explicit saved active-index entry, or null when no index was recorded.
  final AiNativeEntry? activeEntry;

  /// Source-owned initial crop declaration, independent of document ink bounds.
  final AiNativeHeaderField? cropHeader;

  /// Saved LastArtboardID entry, whose value is not an array index or count.
  final AiNativeEntry? lastIdEntry;

  /// Reads one owned document, requiring an explicit choice when owners differ.
  factory AiNativeArtboards.decode({required AiNativeRecords records, AiNativeContainer? document}) {
    final List<AiNativeContainer> documents = records.roots.where((root) => root.type == 'Document').toList();
    if (document == null && documents.length != 1 || document != null && !documents.contains(document)) {
      throw ArgumentError('Artboards require one explicitly owned native Document.');
    }
    final AiNativeContainer owner = document ?? documents.single;
    final AiNativeContainer? recorded = owner['Recorded']?.container;
    final AiNativeContainer? notRecorded = owner['NotRecorded']?.container;
    if (recorded?.type != 'Dictionary' || owner['NotRecorded'] != null && notRecorded?.type != 'Dictionary') {
      throw const FormatException('Artboards require typed native document settings.');
    }
    final AiNativeContainer? array = recorded!['ArtboardArray']?.container;
    if (array?.type != 'Array' || array!.entries.any((entry) => entry.key != null || entry.type != null || entry.isQualifier)) {
      throw const FormatException('Artboards require an ordinary native ArtboardArray.');
    }
    final List<AiNativeArtboard> artboards = records.artboards.where((board) => identical(board.document, owner)).toList();
    final AiNativeEntry? active = recorded['CropAreaActive'];
    final AiNativeEntry? lastId = notRecorded?['LastArtboardID'];
    for (final AiNativeEntry? field in [active, lastId]) {
      if (field != null && (field.type != 'Int' || field.number == null || field.number! < 0 || field.number! > 9007199254740991 || field.number != field.number!.truncateToDouble())) {
        throw const FormatException('Artboard state requires portable nonnegative integer fields.');
      }
    }
    if (active != null && active.number! >= artboards.length) {
      throw const FormatException('The saved active artboard index is outside its owning array.');
    }
    final AiNativeHeaderField? crop = _nativeNumericHeader(records, {'AI3_Cropmarks'})['AI3_Cropmarks'];
    if (crop != null) {
      if (crop.values.length != 4) {
        throw const FormatException('A native crop declaration requires four coordinates.');
      }
      AiBoundingBox(left: crop.values[0], bottom: crop.values[1], right: crop.values[2], top: crop.values[3]);
    }
    return AiNativeArtboards._(records: records, document: owner, artboards: artboards, activeEntry: active, cropHeader: crop, lastIdEntry: lastId);
  }

  /// Freezes qualified ownership without selecting or normalizing native values.
  AiNativeArtboards._({required this.records, required this.document, required List<AiNativeArtboard> artboards, required this.activeEntry, required this.cropHeader, required this.lastIdEntry})
    : artboards = List.unmodifiable(artboards);

  /// Saved zero-based active index, or null without an explicit source field.
  int? get activeIndex => activeEntry?.number?.toInt();

  /// Artboard designated by CropAreaActive, without consulting selection flags.
  AiNativeArtboard? get activeArtboard => activeIndex == null ? null : artboards[activeIndex!];

  /// Independently selected boards, including multiple or no selected objects.
  List<AiNativeArtboard> get selectedArtboards => List.unmodifiable(artboards.where((board) => board.selected));

  /// Saved LastArtboardID integer, without interpreting it as a live board index.
  int? get lastArtboardId => lastIdEntry?.number?.toInt();

  /// Explicit program crop bounds, without deriving them from another rectangle.
  AiBoundingBox? get cropBounds => cropHeader == null ? null : AiBoundingBox(left: cropHeader!.values[0], bottom: cropHeader!.values[1], right: cropHeader!.values[2], top: cropHeader!.values[3]);

  /// Replaces one board's bounds and explicitly retains or replaces crop bounds.
  ///
  /// Pass null for [cropBounds] to retain the existing crop declaration. An
  /// optional [rulerOrigin] replaces its existing two-coordinate native field;
  /// omitted origins remain exact. Artwork and drawing bounds do not move.
  /// Unknown native dependency owners reject. Saving also requires synchronized
  /// host PDF pages and any cached header representation; this edits native data.
  AiNativeArtboards resize({required AiNativeArtboard artboard, required AiBoundingBox bounds, required AiBoundingBox? cropBounds, List<double>? rulerOrigin}) =>
      _resizeNativeArtboard(this, artboard, bounds, cropBounds, rulerOrigin);
}
