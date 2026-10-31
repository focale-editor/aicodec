part of 'package:aikit/src/model/ai_native_records.dart';

/// Embedded native raster samples with their original placement and source spans.
final class AiNativeRaster extends AiNativeItem {
  /// Raster operator and source-backed operands, including version extensions.
  final AiNativeInstruction instruction;

  /// Commands within this raster section, preserving unrecognized metadata.
  final List<AiNativeInstruction> commands;

  /// Exact opaque sample span, excluding XI and the DSC delimiters.
  final AiToken data;

  /// Pixel-to-native-coordinate affine transform in Illustrator operand order.
  final List<double> matrix;

  /// Original image-space bounds, independent of the placed artboard bounds.
  final List<double> bounds;

  /// Number of pixel columns; older documentation labels this operand h.
  final int width;

  /// Number of pixel rows; older documentation labels this operand w.
  final int height;

  /// Bits per component, with rows padded to whole bytes.
  final int bitsPerComponent;

  /// Process component count: one gray, three RGB or four CMYK channels.
  final int components;

  /// Whether a separate same-depth alpha plane follows the color samples.
  final bool hasAlpha;

  /// Producer flags retained without guessing future bit meanings.
  final int flags;

  /// Whether this one-bit gray raster is a stencil using the current paint.
  final bool imageMask;

  /// Version-specific trailing operands, retained in their original order.
  final List<int> extensions;

  /// Number of bytes in the color plane, including per-row padding.
  final int colorByteLength;

  /// Immutable source storage shared by the color and alpha sample views.
  final Uint8List _samples;

  /// Creates a source-backed image after validating its byte layout.
  AiNativeRaster._({required super.start, required super.end, required this.instruction, required List<AiNativeInstruction> commands, required this.data, required Uint8List samples})
    : commands = List.unmodifiable(commands),
      matrix = List.unmodifiable(instruction.operands.skip(1).take(6).map((token) => token.number!.toDouble())),
      bounds = List.unmodifiable(instruction.operands.skip(8).take(4).map((token) => token.number!.toDouble())),
      width = instruction.operands[12].number!.toInt(),
      height = instruction.operands[13].number!.toInt(),
      bitsPerComponent = instruction.operands[14].number!.toInt(),
      components = instruction.operands[15].number!.toInt(),
      hasAlpha = instruction.operands[16].number == 1,
      flags = instruction.operands[17].number!.toInt(),
      imageMask = instruction.operands[19].number == 1,
      extensions = List.unmodifiable(instruction.operands.skip(20).map((token) => token.number!.toInt())),
      colorByteLength =
          ((instruction.operands[12].number!.toInt() * instruction.operands[14].number!.toInt() * instruction.operands[15].number!.toInt() + 7) ~/ 8) * instruction.operands[13].number!.toInt(),
      _samples = samples.asUnmodifiableView() {
    if (!const {0, 1}.contains(instruction.operands[19].number) || imageMask && (components != 1 || bitsPerComponent != 1 || hasAlpha)) {
      throw const FormatException('Invalid native raster stencil layout.');
    }
  }

  /// Interleaved process-color bytes, retaining channel values without conversion.
  Uint8List get colorSamples => Uint8List.sublistView(_samples, 0, colorByteLength).asUnmodifiableView();

  /// Separate alpha samples, or null when the image is opaque.
  Uint8List? get alphaSamples => hasAlpha ? Uint8List.sublistView(_samples, colorByteLength).asUnmodifiableView() : null;

  /// Whether this image belongs to the program's printable drawing body.
  bool isPrintable({required AiProgram program}) => start >= program.bodyStart && end <= program.bodyEnd && !instruction.isPrivate;
}

/// Immutable embedded raster records in artwork and native resource sections.
///
/// Binary process-color XI samples are decoded without executing PostScript,
/// converting color profiles or accessing XG file paths. Linked XF images and
/// older comment-encoded samples remain outside this binary decoding contract.
final class AiNativeRasters {
  /// Native snapshot owning every returned image and byte range.
  final AiNativeRecords records;

  /// Complete embedded image sections in source order.
  final List<AiNativeRaster> images;

  /// Validates and indexes binary XI images under the program's resource limits.
  ///
  /// Set [bodyOnly] to exclude setup resources while retaining private authoring
  /// images within the body. [AiNativeRaster.isPrintable] distinguishes them.
  factory AiNativeRasters.decode({required AiNativeRecords records, bool bodyOnly = false}) => AiNativeRasters._(records: records, images: _readNativeRasters(records, bodyOnly));

  /// Retains an immutable source-backed raster inventory.
  AiNativeRasters._({required this.records, required List<AiNativeRaster> images}) : images = List.unmodifiable(images);

  /// Translates embedded images and their redundant placement matrices together.
  ///
  /// Samples, source links, pixel identities, rotation and scale metadata stay
  /// unchanged. Enclosing clips, groups and artboards are independent objects.
  /// DSC drawing bounds expand conservatively to include the translated artwork.
  AiNativeRasters translate({required List<AiNativeRaster> images, required double deltaX, required double deltaY}) => _translateNativeRasters(this, images, deltaX, deltaY);
}
