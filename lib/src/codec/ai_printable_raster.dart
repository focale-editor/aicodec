part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Immutable pixel and placement views shared by embedded and linked images.
final class _PrintableRaster {
  /// Owned or source-backed immutable interleaved process samples.
  final Uint8List colorSamples;

  /// Separate same-depth transparency samples, when present.
  final Uint8List? alphaSamples;

  /// Number of pixel columns.
  final int width;

  /// Number of pixel rows.
  final int height;

  /// Native sample depth, retaining row padding and big-endian words.
  final int bitsPerComponent;

  /// Process channel count: one gray, three RGB or four CMYK channels.
  final int components;

  /// Whether one-bit samples use the current nonstroking paint as a stencil.
  final bool imageMask;

  /// Pixel-to-native transform with the embedded raster origin convention.
  final List<double> matrix;

  /// Qualified canonical image-space bounds.
  final List<double> bounds;

  /// Borrows already validated native image samples without allocating copies.
  _PrintableRaster.embedded({required AiNativeRaster image})
    : colorSamples = image.colorSamples,
      alphaSamples = image.alphaSamples,
      width = image.width,
      height = image.height,
      bitsPerComponent = image.bitsPerComponent,
      components = image.components,
      imageMask = image.imageMask,
      matrix = image.matrix,
      bounds = image.bounds;

  /// Maps explicit host pixels into the link's unchanged native rectangle.
  _PrintableRaster.placed({required AiNativePlacedObject object, required AiNativeRasterSamples samples})
    : colorSamples = samples.colorSamples,
      alphaSamples = samples.alphaSamples,
      width = samples.width,
      height = samples.height,
      bitsPerComponent = samples.bitsPerComponent,
      components = samples.components,
      imageMask = samples.imageMask,
      matrix = object.rasterMatrix(width: samples.width, height: samples.height),
      bounds = List.unmodifiable([0.0, 0.0, samples.width.toDouble(), samples.height.toDouble()]);
}
