part of 'package:aikit/src/model/ai_native_records.dart';

/// Replaces one bounded raster plane set and its dependent native metadata.
AiNativeRasters _replaceNativeRasterSamples(AiNativeRasters source, AiNativeRaster image, AiNativeRasterSamples samples) {
  if (!source.images.contains(image)) {
    throw ArgumentError('The image belongs to another native raster snapshot.');
  }
  image.validateProcessLayout();
  final bool geometryChanged = image.width != samples.width || image.height != samples.height || image.bitsPerComponent != samples.bitsPerComponent;
  final bool colorsChanged = geometryChanged || image.components != samples.components || image.imageMask != samples.imageMask || !_sameRasterBytes(image.colorSamples, samples.colorSamples);
  final bool alphaChanged = image.hasAlpha != (samples.alphaSamples != null) || image.hasAlpha && (geometryChanged || !_sameRasterBytes(image.alphaSamples!, samples.alphaSamples!));
  if (!colorsChanged && !alphaChanged) {
    return source;
  }
  if (image.extensions.isEmpty && samples.alphaSamples != null) {
    throw UnsupportedError('Authoring legacy raster alpha requires a qualified producer layout.');
  }
  final int length = samples.colorSamples.length + (samples.alphaSamples?.length ?? 0);
  if (source.records.program.bytes.length - (image.data.end - image.data.start) + length > source.records.program.limits.maxDecodedBytes) {
    throw const FormatException('Replacement raster exceeds the native decoded byte limit.');
  }
  final List<AiSourceEdit> edits = [];

  /// Keeps unchanged tokens byte-exact, including producer numeric precision.
  void replace(AiToken token, Object value) {
    if (value == token.number || value == token.lexeme) {
      return;
    }
    edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode(value.toString())));
  }

  for (final AiNativeInstruction command in image.commands) {
    final List<AiToken> operands = command.operands;
    switch (command.operator) {
      case 'XG':
        replace(operands.last, 1);
      case 'XN':
        replace(operands.single, switch (samples.components) {
          1 => '/DeviceGray',
          3 => '/DeviceRGB',
          _ => '/DeviceCMYK',
        });
      case 'XI' || 'Xh':
        for (int index = 0; index < 4; index++) {
          final double scale = index < 2 ? image.width / samples.width : image.height / samples.height;
          final double coordinate = image.matrix[index] * scale;
          if (!coordinate.isFinite || coordinate.abs() > 9007199254740991 || image.matrix[index] != 0 && coordinate == 0) {
            throw ArgumentError('Replacement raster exceeds finite placement bounds.');
          }
          replace(operands[index + 1], coordinate);
        }
        if (command.operator == 'Xh') {
          replace(operands[8], samples.width);
          replace(operands[9], samples.height);
        } else {
          replace(operands[10], samples.width);
          replace(operands[11], samples.height);
          replace(operands[12], samples.width);
          replace(operands[13], samples.height);
          replace(operands[14], samples.bitsPerComponent);
          replace(operands[15], samples.components);
          replace(operands[16], samples.alphaSamples == null ? 0 : 1);
          final int flags =
              (switch (samples.components) {
                1 => 0,
                3 => 1,
                _ => 2,
              }) +
              (samples.alphaSamples == null ? 0 : 16);
          replace(operands[17], image.extensions.isEmpty ? 0 : flags);
          replace(operands[19], samples.imageMask ? 1 : 0);
        }
      case 'XH':
        continue;
    }
  }
  final int prefix = image.data.start - image.instruction.token.start;
  replace(image.declaration, '%%BeginData: ${prefix + length} Binary Bytes');
  edits.add(
    AiSourceEdit(
      start: image.data.start,
      end: image.data.end,
      bytes:
          (BytesBuilder(copy: false)
                ..add(samples.colorSamples)
                ..add(samples.alphaSamples ?? []))
              .takeBytes(),
    ),
  );
  final _RasterIdentifiers identifiers = _RasterIdentifiers(records: source.records);
  for (final (String, bool) field in [('AI24 ImageRawDataUUID', colorsChanged), ('AI24 ImageAlphaRawDataUUID', alphaChanged)]) {
    final AiNativeEntry? entry = image.dictionary?[field.$1];
    if (!field.$2 || entry == null) {
      continue;
    }
    if (entry.text() case final String identifier when const {'String', 'UnicodeString'}.contains(entry.type) && _rasterIdentifier.hasMatch(identifier) && entry.items.isNotEmpty) {
      edits.add(AiSourceEdit(start: entry.items.first.start, end: entry.items.first.end, bytes: latin1.encode('(${identifiers.next()})')));
      for (final AiNativeItem fragment in entry.items.skip(1)) {
        edits.add(AiSourceEdit(start: fragment.start, end: fragment.end, bytes: []));
      }
    } else {
      throw UnsupportedError('Unrecognized native raster sample identity.');
    }
  }
  final AiNativeRasters result = AiNativeRasters.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
  );
  // Recheck finite nonsingular placement after dimension-dependent rounding.
  result.images.singleWhere((candidate) => candidate.start == image.start).validateProcessLayout();
  return result;
}

/// Compares plane bytes without copying either immutable source view.
bool _sameRasterBytes(List<int> first, List<int> second) => first.length == second.length && first.indexed.every((item) => item.$2 == second[item.$1]);

/// Canonical UUID syntax observed in native sample identity entries.
final RegExp _rasterIdentifier = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Allocates sample identities without reusing source or newly allocated UUIDs.
final class _RasterIdentifiers {
  /// Native source consulted only when an existing identity must be replaced.
  final AiNativeRecords records;

  /// Existing scalar UUIDs, normalized independently of their native key names.
  late final Set<String> _used = {
    for (final AiNativeContainer container in records.containers)
      for (final AiNativeEntry entry in container.entries)
        if (entry.text() case final String value when _rasterIdentifier.hasMatch(value)) value.toLowerCase(),
  };

  /// Portable random bytes for resource identities, never security credentials.
  late final Random _random = Random();

  /// Reserves identifiers lazily from the bounded source hierarchy.
  _RasterIdentifiers({required this.records});

  /// Produces a UUID version four distinct from all observed source identities.
  String next() {
    for (int attempt = 0; attempt < 16; attempt++) {
      final List<int> bytes = List.generate(16, (_) => _random.nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final String hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final String identifier = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      if (_used.add(identifier)) {
        return identifier;
      }
    }
    throw StateError('Could not allocate a distinct Illustrator raster identifier.');
  }
}
