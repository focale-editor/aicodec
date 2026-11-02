part of 'package:aikit/src/model/ai_native_records.dart';

/// Serializes the complete typed parameter dictionary without deriving geometry.
String _nativeShapeParametersSource(AiNativeShapeParameters parameters, {required String prefix, bool notRecorded = false}) {
  final StringBuffer output = StringBuffer('/Dictionary :${notRecorded ? ' /NotRecorded ,' : ''}\n');
  for (final MapEntry<String, double> entry in parameters.numbers.entries) {
    final String type = _nativeShapeParameterType(parameters.handler, entry.key);
    output.writeln('$prefix${type == 'Int' ? entry.value.toInt() : entry.value} /$type (${parameters.handler}::${entry.key}) ,');
  }
  for (final MapEntry<String, bool> entry in parameters.flags.entries) {
    output.writeln('$prefix${entry.value ? 1 : 0} /Bool (${parameters.handler}::${entry.key}) ,');
  }
  for (final MapEntry<String, String> entry in parameters.choices.entries) {
    output.writeln('$prefix(${entry.value}) /UnicodeString (${parameters.handler}::${entry.key}) ,');
  }
  output.write('$prefix;');
  return output.toString();
}

/// Checks portable framing and the family's explicit open/closed contour contract.
void _nativeShapeAuthoring(AiNativeShapeParameters parameters, bool closed, double? rotationRadians) {
  if (closed != (parameters.handler != 'ai::Line')) {
    throw ArgumentError('Native line handlers require open contours; other shape handlers require closed contours.');
  }
  if (rotationRadians != null && (!rotationRadians.isFinite || rotationRadians.abs() > 2 * pi)) {
    throw ArgumentError('Native shape framing requires an angle in -2π..2π.');
  }
}

/// Promotes exactly one ordinary contour, retaining all unrelated source bytes.
AiNativeDrawing _setNativePathLiveShape(AiNativeDrawing drawing, AiNativePath path, AiNativeShapeParameters parameters, double? rotationRadians) {
  _nativeShapeAuthoring(parameters, path.closed, rotationRadians);
  _nativePathTopologies(drawing, [path]);
  final AiNativeObject object = _ordinaryObject(drawing, path);
  if (object.liveShape != null) {
    throw ArgumentError('The selected contour already owns native live-shape parameters.');
  }
  final AiNativeContainer? dictionary = object.dictionary;
  final AiNativeEntry? angle = dictionary?['BBAccumRotation'];
  final bool private = dictionary == null || drawing.records._projection.isPrivate(dictionary.start);
  final String prefix = private ? '%_' : '';
  final StringBuffer output = StringBuffer();
  if (dictionary == null) {
    output.write('\n%_/ArtDictionary :\n%_');
  }
  output.write('/Dictionary :\n$prefix(${parameters.handler}) /UnicodeString (ai::LiveShape::HandlerName) ,\n$prefix');
  output.write(_nativeShapeParametersSource(parameters, prefix: prefix));
  output.write(' (ai::LiveShape::Params) ,\n$prefix; (ai::LiveShape) ,\n$prefix');
  if (angle == null && rotationRadians != null) {
    output.write('($rotationRadians) /String (BBAccumRotation) ,\n$prefix');
  }
  final int position;
  if (dictionary == null) {
    position = path.end;
    output.write(';');
  } else {
    position = drawing.records._projection.tokens.singleWhere((token) => token.end == dictionary.end && token.lexeme == ';').start;
  }
  if (output.length > drawing.records.program.limits.maxDecodedBytes) {
    throw const AiLimitException(message: 'Native shape metadata exceeds the output limit.');
  }
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: position, end: position, bytes: latin1.encode(output.toString())),
      if (angle != null) ..._nativeFrameRotationEdits(drawing.records, dictionary, object.end, rotationRadians),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length,
    liveShapes: drawing.liveShapes.length + 1,
  );
  final AiNativePath changed = result.paths[drawing.paths.indexOf(path)];
  final AiLiveShape shape = result.liveShapes.singleWhere((shape) => identical(shape.path, changed));
  if (_directNativeShapeIssue(shape) != null) {
    throw const FormatException('Created native shape did not bind one complete direct owner.');
  }
  return result;
}

/// Creates ordinary painted source data before attaching its native parameters.
AiNativeDrawing _createNativeLiveShape(AiNativeDrawing drawing, AiNativePathDefinition definition, AiNativeShapeParameters parameters, double? rotationRadians, AiNativeGroup? parent, AiLayer? layer) {
  _nativeShapeAuthoring(parameters, definition.artwork.closed, rotationRadians);
  final int position = _nativeCreationPosition(drawing, parent, layer);
  final int index = drawing.paths.where((path) => path.start < position).length;
  final AiNativeDrawing created = _createNativePath(drawing, definition, parent, layer);
  return _setNativePathLiveShape(created, created.paths[index], parameters, rotationRadians);
}

/// Reuses complete path/state replacement while retaining native parameter ownership.
AiNativeDrawing _replaceNativeDirectLiveShape(AiNativeDrawing drawing, AiLiveShape shape, AiNativePathDefinition definition, AiNativeShapeParameters parameters, double? rotationRadians) {
  if (!drawing.liveShapes.contains(shape) || _directNativeShapeIssue(shape) != null || definition.nameBytes != null || definition.identifierBytes != null) {
    throw ArgumentError('Direct shape replacement requires an owned complete shape and retained name/identity.');
  }
  _nativeShapeAuthoring(parameters, definition.artwork.closed, rotationRadians);
  _shapeCopyDictionary(drawing, shape, shape.dictionary);
  _shapeFamilyChange(AiNativeShapeParameters.fromShape(shape: shape), parameters, definition.artwork.segments);
  return _replaceNativePathArtwork(
    drawing,
    shape.path!,
    definition.artwork,
    definition.bounds,
    definition.opacity,
    definition.hidden,
    definition.fillOverprint,
    definition.strokeOverprint,
    transparency: definition.transparency,
    shapeParameters: parameters,
    rotationRadians: rotationRadians,
  );
}
