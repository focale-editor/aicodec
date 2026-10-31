part of 'package:aikit/src/model/ai_native_records.dart';

/// Source-backed preview retained for a linked object, independently of its file.
final class AiNativePlacedPreview extends AiNativeItem {
  /// Width in preview pixels, independent of the placed file's resolution.
  final int width;

  /// Height in preview pixels.
  final int height;

  /// Source bytes per row, including padding.
  final int rowBytes;

  /// Producer bit depth, retained even when its color layout is unsupported.
  final int bitsPerPixel;

  /// Producer format field; 17 denotes the observed straight ARGB layout.
  final int format;

  /// Opaque sample rows without the numeric header or section delimiters.
  final Uint8List bytes;

  /// Keeps checked immutable rows with their source span.
  AiNativePlacedPreview._({required super.start, required super.end, required AiPlacedPreviewData layout, required Uint8List source})
    : width = layout.width,
      height = layout.height,
      rowBytes = layout.rowBytes,
      bitsPerPixel = layout.bits,
      format = layout.format,
      bytes = Uint8List.sublistView(source, layout.samples, layout.end).asUnmodifiableView();

  /// Converts qualified straight ARGB rows into separate native RGB/alpha planes.
  ///
  /// This is the saved preview, not the full-resolution external file. Callers
  /// explicitly choose whether to use it when the original cannot be resolved.
  AiNativeRasterSamples toSamples() {
    if (bitsPerPixel != 32 || format != 17 || rowBytes < width * 4) {
      throw UnsupportedError('Unknown placed preview color layout.');
    }
    final Uint8List colors = Uint8List(width * height * 3);
    final Uint8List alpha = Uint8List(width * height);
    for (int row = 0; row < height; row++) {
      for (int column = 0; column < width; column++) {
        final int input = row * rowBytes + column * 4;
        final int pixel = row * width + column;
        alpha[pixel] = bytes[input];
        colors.setRange(pixel * 3, pixel * 3 + 3, bytes, input + 1);
      }
    }
    return AiNativeRasterSamples(width: width, height: height, bitsPerComponent: 8, components: 3, colorSamples: colors, alphaSamples: alpha);
  }
}

/// A linked CC placed object with native coordinates and explicit file references.
final class AiNativePlacedObject extends AiNativeItem {
  /// Native placement command, including its path and producer extensions.
  final AiNativeInstruction instruction;

  /// Matching placement terminator.
  final AiNativeInstruction closing;

  /// Producer file type, without inferring it from a path extension.
  final int? fileType;

  /// Retained section comments for explicit edit qualification.
  final List<AiToken> comments;

  /// Directory string relative to the owning document, when written by the producer.
  final AiToken? relativeDirectory;

  /// Optional source-backed image retained for missing-file previews.
  final AiNativePlacedPreview? preview;

  /// Immediately attached metadata for this object, preserving stable identities.
  final AiNativeContainer? dictionary;

  /// Mapping from the placed file's local coordinates to native drawing points.
  final List<double> matrix;

  /// Local file rectangle; qualified raster placements use a downward y axis.
  final List<double> bounds;

  /// Producer operands between the rectangle and file path.
  final List<int> extensions;

  /// Checks finite source geometry and retains unrelated original records.
  AiNativePlacedObject._({
    required super.start,
    required super.end,
    required this.instruction,
    required this.closing,
    required this.fileType,
    required List<AiToken> comments,
    required this.relativeDirectory,
    required this.preview,
    required this.dictionary,
  }) : comments = List.unmodifiable(comments),
       matrix = List.unmodifiable(instruction.operands.skip(1).take(6).map((token) => token.number!.toDouble())),
       bounds = List.unmodifiable(instruction.operands.skip(8).take(4).map((token) => token.number!.toDouble())),
       extensions = List.unmodifiable(instruction.operands.skip(12).take(instruction.operands.length - 13).map((token) => token.number!.toInt()));

  /// Original path bytes decoded from PostScript escaping, without guessing encoding.
  Uint8List get pathBytes => aiStringBytes(instruction.operands.last).asUnmodifiableView();

  /// Original relative directory bytes, or null when no directory was stored.
  Uint8List? get relativeDirectoryBytes => relativeDirectory == null ? null : aiStringBytes(relativeDirectory!).asUnmodifiableView();

  /// Whether this object belongs to the printable body rather than private art.
  bool isPrintable({required AiProgram program}) => start >= program.bodyStart && end <= program.bodyEnd && !instruction.isPrivate;
}

/// Immutable linked placements whose external files are resolved by the caller.
///
/// Paths remain raw source bytes. The kit does not open file paths or infer their
/// encoding, file format or color profile. Embedding accepts explicitly decoded
/// process samples from the application's chosen format package.
final class AiNativePlacements {
  /// Native snapshot owning every placement and its metadata.
  final AiNativeRecords records;

  /// Source-ordered linked placements, including private authoring records.
  final List<AiNativePlacedObject> objects;

  /// Reads placed-file sections while preserving opaque preview samples.
  factory AiNativePlacements.decode({required AiNativeRecords records, bool bodyOnly = false}) => AiNativePlacements._(records: records, objects: _readNativePlacements(records, bodyOnly));

  /// Retains source ownership and immutable ordered objects.
  AiNativePlacements._({required this.records, required List<AiNativePlacedObject> objects}) : objects = List.unmodifiable(objects);

  /// Moves placements without changing file references or cached sample rows.
  AiNativePlacements translate({required List<AiNativePlacedObject> objects, required double deltaX, required double deltaY}) => _translateNativePlacements(this, objects, deltaX, deltaY);

  /// Incorporates host-resolved pixels as an editable native embedded raster.
  ///
  /// The placed extent and object metadata stay fixed. The file reference and
  /// preview are replaced together; an unused DocumentFiles dependency is
  /// removed. Unknown placement or object-metadata semantics reject conversion.
  /// Use AiNativePdf.save with the returned program for synchronized PDF artwork.
  AiNativeRasters embed({required AiNativePlacedObject object, required AiNativeRasterSamples samples}) => _embedNativePlacement(this, object, samples);
}
