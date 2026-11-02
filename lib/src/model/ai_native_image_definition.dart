part of 'package:aikit/src/model/ai_native_records.dart';

/// Explicit ordinary-image attributes, independent of ancestor visibility.
final class AiNativeImageAttributes {
  /// Whether the native object is locked.
  final bool locked;

  /// Whether the native object is hidden.
  final bool hidden;

  /// Normal object opacity, from zero to one.
  final double opacity;

  /// Complete object blending, replacing the normal-opacity shorthand when set.
  ///
  /// Keep [opacity] at its default when supplying this explicit native tuple.
  final AiNativeTransparency? transparency;

  /// Whether the image overprints underlying artwork.
  final bool overprint;

  /// Optional display name in the host's native byte encoding.
  final List<int>? nameBytes;

  /// Optional fresh XML artwork identity.
  final List<int>? identifierBytes;

  /// Freezes explicit attributes; insertion checks names against the source.
  AiNativeImageAttributes({this.locked = false, this.hidden = false, this.opacity = 1, this.transparency, this.overprint = false, List<int>? nameBytes, List<int>? identifierBytes})
    : nameBytes = nameBytes == null ? null : List.unmodifiable(nameBytes),
      identifierBytes = identifierBytes == null ? null : List.unmodifiable(identifierBytes) {
    if (!opacity.isFinite || opacity < 0 || opacity > 1 || transparency != null && opacity != 1 || [...?nameBytes, ...?identifierBytes].any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Image attributes require unit opacity or explicit transparency without conflicting inputs, and encoded metadata bytes.');
    }
  }
}

/// Complete embedded image data for native creation, without file decoding.
final class AiNativeRasterDefinition {
  /// Immutable process samples and optional straight alpha.
  final AiNativeRasterSamples samples;

  /// Pixel-to-document matrix using `(a*x - c*y + tx, b*x - d*y + ty)`.
  final List<double> matrix;

  /// Explicit visibility, opacity, overprint and object metadata.
  final AiNativeImageAttributes attributes;

  /// Explicit process fill for a one-bit stencil; absent for ordinary images.
  final AiColor? stencilColor;

  /// Freezes geometry and requires a paint only when samples form a stencil.
  AiNativeRasterDefinition({required this.samples, required List<double> matrix, AiNativeImageAttributes? attributes, this.stencilColor})
    : matrix = List.unmodifiable(matrix),
      attributes = attributes ?? AiNativeImageAttributes() {
    if (samples.imageMask != (stencilColor != null)) {
      throw ArgumentError('A stencil requires an explicit process color; ordinary images do not.');
    }
    _nativeImageBounds(matrix, [0, -samples.height.toDouble(), samples.width.toDouble(), 0]);
  }
}

/// Host-resolved raster link and optional preview for native creation.
final class AiNativePlacementDefinition {
  /// Encoded external filename, without interpretation or filesystem access.
  final List<int> pathBytes;

  /// Encoded directory relative to the owning document, or no relative hint.
  final List<int>? relativeDirectoryBytes;

  /// Local-to-document matrix using `(a*x + c*y + tx, b*x + d*y + ty)`.
  final List<double> matrix;

  /// Local downward-y rectangle `[left, top, right, bottom]` of the linked file.
  final List<double> bounds;

  /// Optional host-composed eight-bit RGB preview with straight alpha.
  final AiNativeRasterSamples? preview;

  /// Explicit visibility, opacity, overprint and object metadata.
  final AiNativeImageAttributes attributes;

  /// Freezes geometry and link metadata; insertion checks aggregate byte limits.
  AiNativePlacementDefinition({
    required List<int> pathBytes,
    required List<double> matrix,
    required List<double> bounds,
    List<int>? relativeDirectoryBytes,
    this.preview,
    AiNativeImageAttributes? attributes,
  }) : pathBytes = List.unmodifiable(pathBytes),
       relativeDirectoryBytes = relativeDirectoryBytes == null ? null : List.unmodifiable(relativeDirectoryBytes),
       matrix = List.unmodifiable(matrix),
       bounds = List.unmodifiable(bounds),
       attributes = attributes ?? AiNativeImageAttributes() {
    _nativeImageBounds(matrix, bounds);
  }
}
