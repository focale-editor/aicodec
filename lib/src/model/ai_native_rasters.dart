part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Embedded native raster samples with their original placement and source spans.
final class AiNativeRaster extends AiNativeItem {
  /// Raster operator and source-backed operands, including version extensions.
  final AiNativeInstruction instruction;

  /// Commands within this raster section, preserving unrecognized metadata.
  final List<AiNativeInstruction> commands;

  /// Exact opaque sample span, excluding XI and the DSC delimiters.
  final AiToken data;

  /// Source-backed DSC declaration whose count includes the binary invocation.
  final AiToken declaration;

  /// Immediately attached native object metadata, when present in the source.
  final AiNativeContainer? dictionary;

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
  AiNativeRaster._({
    required super.start,
    required super.end,
    required this.instruction,
    required List<AiNativeInstruction> commands,
    required this.data,
    required this.declaration,
    required this.dictionary,
    required Uint8List samples,
  }) : commands = List.unmodifiable(commands),
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

  /// Editing-frame angle in radians, or null when no angle is recorded.
  ///
  /// This metadata is independent of the image matrix. Unknown scalar layouts
  /// reject access rather than guessing an angle from transformed image axes.
  double? get frameRotationRadians => _nativeFrameRotation(dictionary);

  /// Checks process-color placement and metadata before editing or rendering.
  ///
  /// Decoding preserves unknown fields; operations requiring known semantics
  /// call this method and reject unsupported flags, color spaces or cropping.
  void validateProcessLayout() {
    final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
    if (!determinant.isFinite || determinant == 0 || bounds[2] <= bounds[0] || bounds[3] <= bounds[1]) {
      throw const FormatException('Degenerate native raster placement.');
    }
    if (bounds[0] != 0 || bounds[1] != 0 || bounds[2] != width || bounds[3] != height) {
      throw UnsupportedError('Native raster cropping requires qualified image-bound semantics.');
    }
    final int colorFlag = switch (components) {
      1 => 0,
      3 => 1,
      _ => 2,
    };
    if (flags != 0 && flags != colorFlag + (hasAlpha ? 16 : 0) ||
        extensions.isNotEmpty && (extensions.length < 3 || extensions[0] != 4 || extensions[1] != 4 || extensions.skip(2).any((flag) => flag != 0))) {
      throw UnsupportedError('Unsupported native raster producer flags.');
    }
    final Set<String> seen = {};
    for (final AiNativeInstruction command in commands) {
      if (!seen.add(command.operator)) {
        throw const FormatException('Repeated native raster metadata.');
      }
      final List<AiToken> operands = command.operands;
      switch (command.operator) {
        case 'XG':
          if (operands.length != 2 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands.first.kind) || !const {0, 1}.contains(operands.last.number)) {
            throw const FormatException('Invalid native raster source metadata.');
          }
        case 'XN':
          if (operands.length != 1 ||
              operands.single.lexeme !=
                  switch (components) {
                    1 => '/DeviceGray',
                    3 => '/DeviceRGB',
                    _ => '/DeviceCMYK',
                  }) {
            throw UnsupportedError('Native raster color spaces require an explicit color policy.');
          }
        case 'Xh':
          if (operands.length != 11 ||
              operands.first.kind != .arrayStart ||
              operands[7].kind != .arrayEnd ||
              operands.skip(1).take(6).indexed.any((item) => item.$2.number != matrix[item.$1]) ||
              operands[8].number != width ||
              operands[9].number != height ||
              operands[10].number != 0) {
            throw UnsupportedError('Native raster placement metadata disagrees with its samples.');
          }
        case 'XI':
          continue;
        case 'XH':
          if (operands.isNotEmpty || command != commands.last) {
            throw const FormatException('Invalid native raster termination.');
          }
        default:
          throw UnsupportedError('Unsupported native raster command: ${command.operator}.');
      }
    }
  }

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

  /// Validates ordinary source framing, process samples and literal image metadata.
  ///
  /// Unlike sample-layout inspection alone, this rejects unknown annotations,
  /// malformed identities and unsupported dependent object-cache fields. The
  /// caller still qualifies enclosing ownership, paint state and representations.
  /// Exact handles from this snapshot are required; no bytes are changed.
  void validateSourceLayout({required AiNativeRaster image}) {
    if (!images.contains(image)) {
      throw ArgumentError('Image validation requires an owned current raster.');
    }
    _artboardResourceRaster(records, image);
    _validateNativeImageMetadata(records, image.end, image.dictionary, raster: true);
  }

  /// Translates embedded images and their redundant placement matrices together.
  ///
  /// Samples, source links, pixel identities, rotation and scale metadata stay
  /// unchanged. Enclosing clips, groups and artboards are independent objects.
  /// DSC drawing bounds expand conservatively to include the translated artwork.
  AiNativeRasters translate({required List<AiNativeRaster> images, required double deltaX, required double deltaY}) => _translateNativeRasters(this, images, deltaX, deltaY);

  /// Sets an image's affine placement and explicit editing-frame orientation.
  ///
  /// For `[a, b, c, d, tx, ty]`, pixel `(x, y)` maps to
  /// `(a*x - c*y + tx, b*x - d*y + ty)` in native drawing points. Both XI and
  /// Xh matrices update together; pixels, sample UUIDs and original scale stay
  /// unchanged. [rotationRadians] describes the editing frame independently of
  /// the matrix, within -2π to 2π, and is stored to six decimal places. Pass null
  /// only when the source has no `BBAccumRotation` field and none is requested.
  /// Unknown object-cache fields reject the edit. Printable DSC bounds expand;
  /// enclosing clips, groups and artboards remain independent objects.
  AiNativeRasters setPlacement({required AiNativeRaster image, required List<double> matrix, required double? rotationRadians}) => _setNativeRasterPlacement(this, image, matrix, rotationRadians);

  /// Replaces embedded pixels while retaining their placed extent and object identity.
  ///
  /// Dimensions, process channels, depth and alpha may change. Both placement
  /// matrices compensate for a resolution change; no resampling or color
  /// conversion is performed. Existing color/alpha UUIDs change only for changed
  /// planes, and XG marks the embedded copy as modified. Unknown raster layouts
  /// reject editing. The host must regenerate matching PDF artwork before saving.
  AiNativeRasters replacePixels({required AiNativeRaster image, required AiNativeRasterSamples samples}) => _replaceNativeRasterSamples(this, image, samples);

  /// Changes ordinary body-image attributes while preserving samples and identities.
  ///
  /// Null values retain the source. Opacity changes preserve the other literal
  /// transparency flags independently in native and printing state. Known state
  /// is restored after the image, so following artwork remains unchanged.
  /// [transparency] replaces all five flags in both representations; it cannot
  /// be combined with [opacity]. The host supplies matching PDF compositing.
  /// [nameBytes] replaces all existing name fields, or creates `AIArtName`;
  /// [unicodeName] selects UTF-16 big-endian bytes instead of a native String.
  /// Private, conditional, clipped and appearance-owned images require separate
  /// contracts. Visual edits require a matching host PDF before serialization.
  AiNativeRasters updateAttributes({
    required AiNativeRaster image,
    double? opacity,
    AiNativeTransparency? transparency,
    bool? hidden,
    bool? locked,
    bool? overprint,
    List<int>? nameBytes,
    bool unicodeName = false,
  }) => _updateNativeRasterAttributes(this, image, opacity, transparency, hidden, locked, overprint, nameBytes, unicodeName);
}
