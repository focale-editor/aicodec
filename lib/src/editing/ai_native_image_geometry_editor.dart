part of 'package:aikit/src/model/ai_native_records.dart';

/// Sets both embedded-image matrices without touching their sample data.
AiNativeRasters _setNativeRasterPlacement(AiNativeRasters source, AiNativeRaster image, List<double> matrix, double? rotationRadians) {
  if (!source.images.contains(image)) {
    throw ArgumentError('The image belongs to another native raster snapshot.');
  }
  image.validateProcessLayout();
  final List<AiSourceEdit> edits = _imagePlacementEdits(
    records: source.records,
    end: image.end,
    dictionary: image.dictionary,
    matrix: matrix,
    rotationRadians: rotationRadians,
    commands: image.commands.where((command) => command.operator == 'XI' || command.operator == 'Xh'),
    local: [0, -image.height.toDouble(), image.width.toDouble(), 0],
    printable: image.isPrintable(program: source.records.program),
    raster: true,
  );
  if (edits.isEmpty) {
    return source;
  }
  final AiNativeRasters changed = AiNativeRasters.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
  );
  changed.images.singleWhere((candidate) => candidate.start == image.start + _imageEditShift(edits, image.start)).validateProcessLayout();
  return changed;
}

/// Sets linked-object geometry while retaining every external resource record.
AiNativePlacements _setNativeLinkedPlacement(AiNativePlacements source, AiNativePlacedObject object, List<double> matrix, double? rotationRadians) {
  if (!source.objects.contains(object)) {
    throw ArgumentError('The placed object belongs to another native snapshot.');
  }
  object.validateRasterLayout();
  final List<AiSourceEdit> edits = _imagePlacementEdits(
    records: source.records,
    end: object.end,
    dictionary: object.dictionary,
    matrix: matrix,
    rotationRadians: rotationRadians,
    commands: [object.instruction],
    local: object.bounds,
    printable: object.isPrintable(program: source.records.program),
    raster: false,
  );
  if (edits.isEmpty) {
    return source;
  }
  final AiNativePlacements changed = AiNativePlacements.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: source.records.program, edits: edits),
    ),
  );
  changed.objects.singleWhere((candidate) => candidate.start == object.start + _imageEditShift(edits, object.start)).validateRasterLayout();
  return changed;
}

/// Locates a rewritten object after changed header-bound lengths.
int _imageEditShift(List<AiSourceEdit> edits, int start) => edits.where((edit) => edit.end <= start).fold(0, (shift, edit) => shift + edit.bytes.length - (edit.end - edit.start));

/// Validates affine placement and plans one atomic image/frame source update.
List<AiSourceEdit> _imagePlacementEdits({
  required AiNativeRecords records,
  required int end,
  required AiNativeContainer? dictionary,
  required List<double> matrix,
  required double? rotationRadians,
  required Iterable<AiNativeInstruction> commands,
  required List<double> local,
  required bool printable,
  required bool raster,
}) {
  if (matrix.length != 6 || matrix.any((value) => !value.isFinite || value.abs() > 9007199254740991) || rotationRadians != null && (!rotationRadians.isFinite || rotationRadians.abs() > 2 * pi)) {
    throw ArgumentError('Image placement requires six bounded matrix values and an optional angle within -2π to 2π.');
  }
  final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
  if (!determinant.isFinite || determinant == 0) {
    throw ArgumentError('The image placement matrix must be nonsingular.');
  }
  final Set<String?> keys = {};
  for (final AiNativeEntry entry in dictionary?.entries ?? <AiNativeEntry>[]) {
    if (!keys.add(entry.key) ||
        !{
          'BBAccumRotation',
          'Raster Art Original Scale',
          'AI10_ArtUID',
          'AIArtName',
          'Object name',
          if (raster) ...['AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'],
        }.contains(entry.key)) {
      throw UnsupportedError('Image geometry requires unambiguous, qualified object dictionary fields.');
    }
    if (entry.key == 'Raster Art Original Scale' && (entry.type != 'Real' || entry.number == null || entry.number! <= 0)) {
      throw UnsupportedError('Unrecognized original raster scale metadata.');
    }
  }
  final List<AiSourceEdit> edits = _imageRotationEdits(records, dictionary, end, rotationRadians);
  bool geometryChanged = false;
  for (final AiNativeInstruction command in commands) {
    for (int index = 0; index < 6; index++) {
      final AiToken token = command.operands[index + 1];
      if (token.number != matrix[index]) {
        geometryChanged = true;
        edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode(matrix[index].toString())));
      }
    }
  }
  final List<double> horizontal = [];
  final List<double> vertical = [];
  for (final double x in [local[0], local[2]]) {
    for (final double y in [local[1], local[3]]) {
      horizontal.add(matrix[0] * x + matrix[2] * y + matrix[4]);
      vertical.add(matrix[1] * x + matrix[3] * y + matrix[5]);
    }
  }
  if ([...horizontal, ...vertical].any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
    throw ArgumentError('Image corners exceed finite source-coordinate bounds.');
  }
  if (horizontal.reduce(min) == horizontal.reduce(max) || vertical.reduce(min) == vertical.reduce(max)) {
    throw ArgumentError('The image placement collapses at source-coordinate precision.');
  }
  if (geometryChanged && printable) {
    edits.addAll(
      AiNativeEditor.includeBoundsEdits(
        program: records.program,
        bounds: AiBoundingBox(left: horizontal.reduce(min), bottom: vertical.reduce(min), right: horizontal.reduce(max), top: vertical.reduce(max)),
      ),
    );
  }
  return edits;
}

/// Reads an explicit frame angle without conflating it with image geometry.
double? _imageFrameRotation(AiNativeContainer? dictionary) {
  final AiNativeEntry? entry = dictionary?['BBAccumRotation'];
  if (entry == null) {
    return null;
  }
  final double? value = switch (entry.type) {
    'String' || 'UnicodeString' => double.tryParse(entry.text() ?? ''),
    'Real' => entry.number,
    _ => null,
  };
  if (value == null || !value.isFinite || entry.items.isEmpty) {
    throw UnsupportedError('Unrecognized native image frame-angle metadata.');
  }
  return value;
}

/// Updates or adds the explicitly supplied frame angle using observed precision.
List<AiSourceEdit> _imageRotationEdits(AiNativeRecords records, AiNativeContainer? dictionary, int end, double? radians) {
  final AiNativeEntry? entry = dictionary?['BBAccumRotation'];
  if (radians == null) {
    if (entry != null) {
      throw ArgumentError('An existing image frame angle requires an explicit replacement value.');
    }
    return [];
  }
  final String angle = (radians.abs() < 0.0000005 ? 0.0 : radians).toStringAsFixed(6);
  if (entry != null) {
    final bool string = const {'String', 'UnicodeString'}.contains(entry.type);
    final double previous = _imageFrameRotation(dictionary)!;
    if (previous == radians || previous == double.parse(angle)) {
      return [];
    }
    return [
      AiSourceEdit(start: entry.items.first.start, end: entry.items.first.end, bytes: latin1.encode(string ? '($angle)' : angle)),
      for (final AiNativeItem fragment in entry.items.skip(1)) AiSourceEdit(start: fragment.start, end: fragment.end, bytes: []),
    ];
  }
  if (dictionary != null) {
    final AiToken closing = records._projection.tokens.singleWhere((token) => token.end == dictionary.end && token.lexeme == ';');
    final bool private = records._projection.isPrivate(closing.start);
    return [AiSourceEdit(start: closing.start, end: closing.start, bytes: latin1.encode('($angle) /String (BBAccumRotation) ,\n${private ? '%_' : ''}'))];
  }
  // Authoring dictionaries are private metadata even after printable artwork.
  return [AiSourceEdit(start: end, end: end, bytes: latin1.encode('\n%_/ArtDictionary :\n%_($angle) /String (BBAccumRotation) ,\n%_;'))];
}
