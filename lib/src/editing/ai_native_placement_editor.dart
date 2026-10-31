part of 'package:aikit/src/model/ai_native_records.dart';

/// Checks the observed CC raster-placement contract before source edits.
void _validateRasterPlacement(AiNativePlacedObject object) {
  final List<double> matrix = object.matrix;
  final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
  if (!determinant.isFinite || determinant == 0 || object.bounds[2] <= object.bounds[0] || object.bounds[3] <= object.bounds[1]) {
    throw const FormatException('Degenerate native placed-object geometry.');
  }
  if (object.fileType != 1 || object.extensions.length != 3 || object.extensions[0] != 4 || object.extensions[1] != 4 || object.extensions[2] != 0) {
    throw UnsupportedError('Native placement editing requires a qualified CC raster file.');
  }
  final List<AiToken> includes = object.comments.where((token) => token.lexeme.startsWith('%%IncludeFile:')).toList();
  if (includes.length != 1 || includes.single.lexeme.substring('%%IncludeFile:'.length).trim() != latin1.decode(object.pathBytes)) {
    throw UnsupportedError('Native placed-file references disagree.');
  }
  final List<String> expected = [
    if (object.relativeDirectory != null) ...[
      '%AI17_Begin_Content_if_version_gt:24 12',
      '%AI28_BeginPlacedRelativePath',
      '%AI28_EndPlacedRelativePath',
      '%AI17_Alternate_Content',
      '%AI17_End_Versioned_Content',
    ],
    if (object.preview != null) ...[
      '%AI17_Begin_Content_if_version_gt:24 5',
      '%AI26_BeginPlacedObjectPreview',
      '%AI26_EndPlacedObjectPreview',
      '%AI17_End_Versioned_Content',
    ],
  ];
  final List<AiToken> metadata = object.comments.where((token) => !token.lexeme.startsWith('%%IncludeFile:') && !token.lexeme.startsWith('%%FileType:')).toList();
  if (metadata.length != expected.length ||
      metadata.indexed.any((item) => item.$2.lexeme != expected[item.$1] || item.$2.start <= object.instruction.end || item.$2.end >= object.closing.start) ||
      object.comments.first.start >= object.instruction.start ||
      !object.comments.first.lexeme.startsWith('%%FileType:') ||
      includes.single.start <= object.instruction.end ||
      includes.single.end >= (metadata.isEmpty ? object.closing.start : metadata.first.start)) {
    throw UnsupportedError('Unresolved native placed-object metadata or version branches.');
  }
}

/// Translates linked file geometry without changing link resolution or previews.
AiNativePlacements _translateNativePlacements(AiNativePlacements source, List<AiNativePlacedObject> objects, double deltaX, double deltaY) {
  if (!deltaX.isFinite || !deltaY.isFinite || objects.toSet().length != objects.length || objects.any((object) => !source.objects.contains(object))) {
    throw ArgumentError('Translation requires finite offsets and owned placed objects.');
  }
  if (objects.isEmpty || deltaX == 0 && deltaY == 0) {
    return source;
  }
  final List<AiSourceEdit> edits = [...AiNativeEditor.translationBoundsEdits(program: source.records.program, deltaX: deltaX, deltaY: deltaY)];
  for (final AiNativePlacedObject object in objects) {
    _validateRasterPlacement(object);
    for (final (int, double) coordinate in [(5, deltaX), (6, deltaY)]) {
      final AiToken token = object.instruction.operands[coordinate.$1];
      final double value = token.number!.toDouble() + coordinate.$2;
      if (!value.isFinite || value.abs() > 9007199254740991) {
        throw ArgumentError('Placed-object translation exceeds finite coordinate bounds.');
      }
      edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode(value.toString())));
    }
  }
  return AiNativePlacements.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
  );
}

/// Replaces a qualified linked object with explicitly supplied native pixels.
AiNativeRasters _embedNativePlacement(AiNativePlacements source, AiNativePlacedObject object, AiNativeRasterSamples samples) {
  if (!source.objects.contains(object)) {
    throw ArgumentError('The placed object belongs to another native snapshot.');
  }
  final List<double> rasterMatrix = object.rasterMatrix(width: samples.width, height: samples.height);
  final int length = samples.colorSamples.length + (samples.alphaSamples?.length ?? 0);
  if (length > source.records.program.limits.maxDecodedBytes) {
    throw const FormatException('Embedded samples exceed the native decoded byte limit.');
  }
  final String prefix = object.instruction.isPrivate ? '%_' : '';
  final String matrixText = '[ ${rasterMatrix.join(' ')} ]';
  final int flags =
      (switch (samples.components) {
        1 => 0,
        3 => 1,
        _ => 2,
      }) +
      (samples.alphaSamples == null ? 0 : 16);
  final String colorSpace = switch (samples.components) {
    1 => 'Gray',
    3 => 'RGB',
    _ => 'CMYK',
  };
  final BytesBuilder replacement = BytesBuilder(copy: false)
    ..add(
      latin1.encode('''%AI5_BeginRaster
$prefix() 1 XG
$prefix/Device$colorSpace XN
$prefix$matrixText ${samples.width} ${samples.height} 0 Xh
$prefix$matrixText 0 0 ${samples.width} ${samples.height} ${samples.width} ${samples.height} ${samples.bitsPerComponent} ${samples.components} ${samples.alphaSamples == null ? 0 : 1} $flags 1 ${samples.imageMask ? 1 : 0} 4 4 0 0
$prefix%%BeginData: ${length + 3} Binary Bytes
XI
'''),
    )
    ..add(samples.colorSamples)
    ..add(samples.alphaSamples ?? [])
    ..add(latin1.encode('\n$prefix%%EndData\n${prefix}XH\n$prefix%AI5_EndRaster\n${prefix}N'));
  final List<AiSourceEdit> edits = [AiSourceEdit(start: object.start, end: object.end, bytes: replacement.takeBytes()), ..._unusedPlacedFileEdits(source, object)];
  final AiNativeRasters result = AiNativeRasters.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
  );
  final int shift = edits.where((edit) => edit.end <= object.start).fold(0, (total, edit) => total + edit.bytes.length - (edit.end - edit.start));
  // Qualify only the authored transform after metadata edits shift its offset.
  result.images.singleWhere((image) => image.start == object.start + shift).validateProcessLayout();
  return result;
}

/// Stabilizes newly composed origins within one nanopoint of an integer.
///
/// Cancelling a large ruler origin can leave a tiny error that adds an entire
/// pixel row or column during rendering. Only the new translation is snapped;
/// scale, shear, rotation and existing embedded-raster transforms stay untouched.
double _placedRasterOrigin(double value) {
  final double nearest = value.roundToDouble();
  return (value - nearest).abs() <= 1e-9 ? nearest : value;
}

/// Removes a declared file only when no other native reference still uses it.
List<AiSourceEdit> _unusedPlacedFileEdits(AiNativePlacements source, AiNativePlacedObject object) {
  final String path = latin1.decode(object.pathBytes);
  final List<AiToken> projected = source.records._projection.tokens;
  if (projected.any(
    (token) =>
        (token.start < object.start || token.start >= object.end) &&
        ((token.kind == .string || token.kind == .hexString) && latin1.decode(aiStringBytes(token)) == path ||
            token.kind == .comment && token.lexeme.startsWith('%%IncludeFile:') && token.lexeme.substring('%%IncludeFile:'.length).trim() == path),
  )) {
    return [];
  }
  final List<AiSourceEdit> edits = [];
  final List<AiToken> deferred = [];
  bool retainedFiles = false;
  final List<AiToken> tokens = AiPostScript.tokenize(
    source.records.program.bytes,
    maxBytes: source.records.program.limits.maxDecodedBytes,
    maxTokens: source.records.program.limits.maxTokens,
    maxDepth: source.records.program.limits.maxDepth,
  );
  int procedure = 0;
  int embedded = 0;
  for (int index = 0; index < tokens.length; index++) {
    final AiToken token = tokens[index];
    if (token.kind == .procedureStart) {
      procedure++;
    }
    if (token.kind == .procedureEnd) {
      procedure--;
    }
    if (token.kind == .comment && token.lexeme.startsWith('%%BeginDocument')) {
      embedded++;
    }
    if (token.kind == .comment && token.lexeme == '%%EndDocument') {
      embedded--;
    }
    if (procedure != 0 || embedded != 0 || token.kind != .comment || !token.lexeme.startsWith('%%DocumentFiles:')) {
      continue;
    }
    final List<String> paths = [token.lexeme.substring('%%DocumentFiles:'.length).trim()];
    int end = token.end;
    while (index + 1 < tokens.length && tokens[index + 1].kind == .comment && tokens[index + 1].lexeme.startsWith('%%+')) {
      final AiToken next = tokens[++index];
      paths.add(next.lexeme.substring(3).trim());
      end = next.end;
    }
    if (paths.length == 1 && paths.single == '(atend)') {
      deferred.add(token);
      continue;
    }
    final List<String> remaining = paths.where((value) => value != path).toList();
    retainedFiles = retainedFiles || remaining.isNotEmpty;
    if (!paths.contains(path)) {
      continue;
    }
    edits.add(AiSourceEdit(start: token.start, end: end, bytes: latin1.encode(remaining.isEmpty ? '' : '%%DocumentFiles:${remaining.first}${remaining.skip(1).map((value) => '\n%%+$value').join()}')));
  }
  if (edits.isNotEmpty && !retainedFiles) {
    edits.addAll(deferred.map((token) => AiSourceEdit(start: token.start, end: token.end, bytes: [])));
  }
  return edits;
}
