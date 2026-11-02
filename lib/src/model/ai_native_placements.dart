part of 'package:aicodec/src/model/ai_native_records.dart';

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

  /// Independent editing-frame angle in radians, or null when absent.
  ///
  /// String, UnicodeString and Real fields are supported; unknown scalar
  /// layouts reject access instead of deriving an angle from the matrix.
  double? get frameRotationRadians => _nativeFrameRotation(dictionary);

  /// Whether this object belongs to the printable body rather than private art.
  bool isPrintable({required AiProgram program}) => start >= program.bodyStart && end <= program.bodyEnd && !instruction.isPrivate;

  /// Checks the qualified CC raster link and its appearance-related metadata.
  void validateRasterLayout() {
    _validateRasterPlacement(this);
    if (dictionary?.entries.any((entry) => !const {'BBAccumRotation', 'Raster Art Original Scale', 'AI10_ArtUID', 'AIArtName', 'Object name'}.contains(entry.key)) ?? false) {
      throw UnsupportedError('Raster placement requires qualified object dictionary fields.');
    }
  }

  /// Maps host-decoded pixels to native points while retaining the linked extent.
  ///
  /// The result uses the embedded raster convention: its origin is the first
  /// pixel's upper-left corner. For `[a, b, c, d, tx, ty]`, pixel `(x, y)` maps
  /// to `(a*x - c*y + tx, b*x - d*y + ty)` in native drawing points.
  /// Resolution changes preserve reflection, shear and the native placed box.
  /// No file resolution, sampling, profile conversion or source edit occurs.
  List<double> rasterMatrix({required int width, required int height}) {
    validateRasterLayout();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Placed image dimensions must be positive.');
    }
    final double horizontal = (bounds[2] - bounds[0]) / width;
    final double vertical = (bounds[3] - bounds[1]) / height;
    final List<double> result = [
      matrix[0] * horizontal,
      matrix[1] * horizontal,
      -matrix[2] * vertical,
      -matrix[3] * vertical,
      _placedRasterOrigin(matrix[0] * bounds[0] + matrix[2] * bounds[1] + matrix[4]),
      _placedRasterOrigin(matrix[1] * bounds[0] + matrix[3] * bounds[1] + matrix[5]),
    ];
    final double determinant = result[0] * result[3] - result[1] * result[2];
    if (!determinant.isFinite || determinant == 0 || result.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('Resolved pixels exceed finite nonsingular placement bounds.');
    }
    return List.unmodifiable(result);
  }
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

  /// Changes ordinary object attributes without rewriting links or saved previews.
  ///
  /// The selected handle must belong to this snapshot. Scalar changes restore
  /// following native and printing state independently; unknown owners reject.
  /// [transparency] replaces all five flags in both representations, whereas
  /// [opacity] retains the other flags. Supply at most one of these arguments.
  /// Visual edits require a matching host PDF before serialization.
  AiNativePlacements updateAttributes({
    required AiNativePlacedObject object,
    double? opacity,
    AiNativeTransparency? transparency,
    bool? hidden,
    bool? locked,
    bool? overprint,
    List<int>? nameBytes,
    bool unicodeName = false,
  }) {
    if (!objects.contains(object)) {
      throw ArgumentError('The placed object belongs to another native snapshot.');
    }
    object.validateRasterLayout();
    final AiNativeRecords updated = _updateNativeImageAttributes(records, object, opacity, transparency, hidden, locked, overprint, nameBytes, unicodeName);
    return identical(updated, records) ? this : AiNativePlacements.decode(records: updated);
  }

  /// Moves placements without changing file references or cached sample rows.
  AiNativePlacements translate({required List<AiNativePlacedObject> objects, required double deltaX, required double deltaY}) => _translateNativePlacements(this, objects, deltaX, deltaY);

  /// Sets linked raster geometry and its explicit editing-frame orientation.
  ///
  /// [matrix] maps the existing local rectangle to native drawing points using
  /// `(a*x + c*y + tx, b*x + d*y + ty)`. Its local y axis points downwards.
  /// Paths, previews, local bounds and original scale remain unchanged.
  /// [rotationRadians] is the independent frame angle within -2π to 2π, stored
  /// to six decimal places. Null is valid only when no source angle is present.
  /// Unknown geometry caches reject editing; printable DSC bounds expand while
  /// artboards and enclosing clipping paths stay fixed.
  AiNativePlacements setPlacement({required AiNativePlacedObject object, required List<double> matrix, required double? rotationRadians}) =>
      _setNativeLinkedPlacement(this, object, matrix, rotationRadians);

  /// Incorporates host-resolved pixels as an editable native embedded raster.
  ///
  /// The placed extent and object metadata stay fixed. The file reference and
  /// preview are replaced together; an unused DocumentFiles dependency is
  /// removed. Unknown placement or object-metadata semantics reject conversion.
  /// The host supplies matching PDF artwork to AiNativeData.replace when saving.
  AiNativeRasters embed({required AiNativePlacedObject object, required AiNativeRasterSamples samples}) => _embedNativePlacement(this, object, samples);

  /// Changes one external reference and explicitly replaces or removes its preview.
  ///
  /// Paths are raw encoded bytes. [relativeDirectoryBytes] is the host-resolved
  /// directory relative to the owning document, or null to remove that section.
  /// [preview] must be eight-bit RGB with optional straight alpha; null removes
  /// the saved preview. No image decoding, resizing or color conversion occurs.
  /// Native geometry and stable object metadata remain unchanged. DocumentFiles
  /// dependencies update atomically, retaining an old path still used elsewhere.
  /// The host resolves the new file and supplies matching PDF artwork when saving.
  AiNativePlacements relink({required AiNativePlacedObject object, required List<int> pathBytes, required List<int>? relativeDirectoryBytes, required AiNativeRasterSamples? preview}) =>
      _relinkNativePlacement(this, object, pathBytes, relativeDirectoryBytes, preview);
}
