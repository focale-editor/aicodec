part of 'package:aikit/src/model/ai_native_records.dart';

/// Relinks one qualified placement without changing its native drawing geometry.
AiNativePlacements _relinkNativePlacement(AiNativePlacements source, AiNativePlacedObject object, List<int> pathBytes, List<int>? relativeDirectoryBytes, AiNativeRasterSamples? preview) {
  if (!source.objects.contains(object)) {
    throw ArgumentError('The placed object belongs to another native snapshot.');
  }
  object.validateRasterLayout();
  final int maxBytes = source.records.program.limits.maxDecodedBytes;
  if (pathBytes.isEmpty ||
      pathBytes.length > maxBytes ~/ 4 ||
      pathBytes.any((byte) => byte < 32 || byte > 255 || byte == 127) ||
      pathBytes.first == 32 ||
      pathBytes.last == 32 ||
      relativeDirectoryBytes != null && (relativeDirectoryBytes.length > maxBytes ~/ 4 || relativeDirectoryBytes.any((byte) => byte <= 0 || byte > 255))) {
    throw ArgumentError('Placed paths require bounded encoded bytes and an unambiguous single-line filename.');
  }
  final String path = latin1.decode(pathBytes);
  if (path == '(atend)') {
    throw ArgumentError('The deferred DSC marker cannot be used as a placed filename.');
  }
  if (preview != null && (preview.bitsPerComponent != 8 || preview.components != 3 || preview.imageMask)) {
    throw ArgumentError('Placed previews require eight-bit RGB with optional straight alpha.');
  }
  final bool samePath = _samePlacedBytes(pathBytes, object.pathBytes);
  if (samePath && _samePlacedBytes(relativeDirectoryBytes, object.relativeDirectoryBytes) && _samePlacedPreview(object.preview, preview)) {
    return source;
  }
  final AiToken include = object.comments.singleWhere((token) => token.lexeme.startsWith('%%IncludeFile:'));
  final AiToken pathToken = object.instruction.operands.last;
  final List<AiSourceEdit> edits = [
    if (!samePath) AiSourceEdit(start: pathToken.start, end: pathToken.end, bytes: latin1.encode(_placedPathString(pathBytes))),
    AiSourceEdit(start: include.start, end: object.closing.start, bytes: _placedLinkMetadata(object, path, relativeDirectoryBytes, preview, maxBytes)),
    ..._placedFileEdits(source, object, replacement: path),
  ];
  final AiNativePlacements result = AiNativePlacements.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
  );
  final int shift = edits.where((edit) => edit.end <= object.start).fold(0, (total, edit) => total + edit.bytes.length - (edit.end - edit.start));
  result.objects.singleWhere((item) => item.start == object.start + shift).validateRasterLayout();
  return result;
}

/// Quotes path bytes without encoding guesses or executable string delimiters.
String _placedPathString(List<int> bytes) => '(${bytes.map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()})';

/// Compares optional encoded fields without allocating normalized copies.
bool _samePlacedBytes(List<int>? first, List<int>? second) =>
    first == null || second == null ? first == second : first.length == second.length && first.indexed.every((item) => item.$2 == second[item.$1]);

/// Recognizes unchanged preview pixels while retaining original padded rows.
bool _samePlacedPreview(AiNativePlacedPreview? old, AiNativeRasterSamples? replacement) {
  if (old == null || replacement == null) {
    return old == null && replacement == null;
  }
  if (old.width != replacement.width || old.height != replacement.height || old.bitsPerPixel != 32 || old.format != 17 || old.rowBytes < old.width * 4) {
    return false;
  }
  for (int row = 0; row < old.height; row++) {
    for (int column = 0; column < old.width; column++) {
      final int pixel = row * old.width + column;
      final int offset = row * old.rowBytes + column * 4;
      if (old.bytes[offset] != (replacement.alphaSamples?[pixel] ?? 255) ||
          old.bytes[offset + 1] != replacement.colorSamples[pixel * 3] ||
          old.bytes[offset + 2] != replacement.colorSamples[pixel * 3 + 1] ||
          old.bytes[offset + 3] != replacement.colorSamples[pixel * 3 + 2]) {
        return false;
      }
    }
  }
  return true;
}

/// Authors the observed CC relative-path and counted straight-ARGB sections.
Uint8List _placedLinkMetadata(AiNativePlacedObject object, String path, List<int>? relative, AiNativeRasterSamples? preview, int maxBytes) {
  final String prefix = object.instruction.isPrivate ? '%_' : '';
  final StringBuffer header = StringBuffer('%%IncludeFile:$path\n');
  if (relative != null) {
    header.write('''$prefix%AI17_Begin_Content_if_version_gt:24 12
$prefix%AI28_BeginPlacedRelativePath
$prefix${_placedPathString(relative)}
$prefix%AI28_EndPlacedRelativePath
$prefix%AI17_Alternate_Content
$prefix%AI17_End_Versioned_Content
''');
  }
  if (preview != null) {
    header.write('''$prefix%AI17_Begin_Content_if_version_gt:24 5
$prefix%AI26_BeginPlacedObjectPreview
${preview.width} ${preview.height} ${preview.width * 4} 32 17 ''');
  }
  final String footer = preview == null ? prefix : '\n$prefix%AI26_EndPlacedObjectPreview\n$prefix%AI17_End_Versioned_Content\n$prefix';
  final int pixelBytes = preview == null ? 0 : preview.width * preview.height * 4;
  if (header.length + pixelBytes + footer.length > maxBytes) {
    throw const FormatException('Placed preview metadata exceeds the native byte limit.');
  }
  final BytesBuilder result = BytesBuilder(copy: false)..add(latin1.encode(header.toString()));
  if (preview != null) {
    final Uint8List pixels = Uint8List(pixelBytes);
    for (int index = 0; index < pixelBytes ~/ 4; index++) {
      pixels[index * 4] = preview.alphaSamples?[index] ?? 255;
      pixels.setRange(index * 4 + 1, index * 4 + 4, preview.colorSamples, index * 3);
    }
    result.add(pixels);
  }
  return (result..add(latin1.encode(footer))).takeBytes();
}
