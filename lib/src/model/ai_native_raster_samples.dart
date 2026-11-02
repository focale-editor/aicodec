part of 'package:aikit/src/model/ai_native_records.dart';

/// Owned process-color pixels and optional same-depth alpha for native images.
///
/// Rows are padded to whole bytes. Packed components start with the most
/// significant bits; sixteen-bit components use big-endian byte order. Alpha
/// is a separate plane, not interleaved with the color components.
final class AiNativeRasterSamples {
  /// Number of columns in each sample plane.
  final int width;

  /// Number of rows in each sample plane.
  final int height;

  /// Component depth: one, two, four, eight or sixteen bits.
  final int bitsPerComponent;

  /// Process channels: one gray, three RGB or four CMYK components.
  final int components;

  /// Whether zero bits paint with the current fill and one bits stay transparent.
  final bool imageMask;

  /// Immutable interleaved process-color samples, without profile conversion.
  final Uint8List colorSamples;

  /// Immutable same-depth alpha plane, or null for an opaque image.
  final Uint8List? alphaSamples;

  /// Validates complete rows and byte values before copying caller-owned data.
  factory AiNativeRasterSamples({
    required int width,
    required int height,
    required int bitsPerComponent,
    required int components,
    required List<int> colorSamples,
    List<int>? alphaSamples,
    bool imageMask = false,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        width > colorSamples.length * 8 ||
        height > colorSamples.length ||
        !const {1, 2, 4, 8, 16}.contains(bitsPerComponent) ||
        !const {1, 3, 4}.contains(components) ||
        imageMask && (components != 1 || bitsPerComponent != 1 || alphaSamples != null)) {
      throw ArgumentError('Invalid native raster sample layout.');
    }
    final int colorRow = (width * components * bitsPerComponent + 7) ~/ 8;
    final int alphaRow = (width * bitsPerComponent + 7) ~/ 8;
    if (colorRow > colorSamples.length ~/ height ||
        colorRow * height != colorSamples.length ||
        alphaSamples != null && (alphaRow > alphaSamples.length ~/ height || alphaRow * height != alphaSamples.length) ||
        colorSamples.any((byte) => byte < 0 || byte > 255) ||
        (alphaSamples?.any((byte) => byte < 0 || byte > 255) ?? false)) {
      throw ArgumentError('Native raster planes must contain exactly the declared sample bytes.');
    }
    return AiNativeRasterSamples._(
      width: width,
      height: height,
      bitsPerComponent: bitsPerComponent,
      components: components,
      imageMask: imageMask,
      colorSamples: Uint8List.fromList(colorSamples).asUnmodifiableView(),
      alphaSamples: alphaSamples == null ? null : Uint8List.fromList(alphaSamples).asUnmodifiableView(),
    );
  }

  /// Retains checked, owned planes with no mutable views exposed.
  const AiNativeRasterSamples._({
    required this.width,
    required this.height,
    required this.bitsPerComponent,
    required this.components,
    required this.imageMask,
    required this.colorSamples,
    required this.alphaSamples,
  });

  /// Serializes host-composed samples as one public native printing image.
  ///
  /// The affine matrix uses Illustrator's pixel placement convention, matching
  /// `AiNativeRasterDefinition`. The returned section has no object identity,
  /// cache metadata or paint assignments. Enclose it in a complete printing
  /// group, supply its ink bounds and preserve the owner's outgoing state.
  /// Alpha remains a separate plane; no rendering or color conversion occurs.
  Uint8List encodePrintingArtwork({required List<double> matrix, AiNativeLimits limits = const AiNativeLimits()}) {
    limits.validate();
    _nativeImageBounds(matrix, [0, -height.toDouble(), width.toDouble(), 0]);
    if (colorSamples.length + (alphaSamples?.length ?? 0) > limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'Printing raster samples exceed native byte limits.');
    }
    final Uint8List bytes = _nativeRasterBytes(this, matrix, '', limits.maxDecodedBytes);
    AiPostScript.tokenize(bytes, maxBytes: limits.maxDecodedBytes, maxTokens: limits.maxTokens, maxDepth: limits.maxDepth);
    return bytes.asUnmodifiableView();
  }
}
