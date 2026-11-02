part of 'package:aicodec/src/model/ai_native_records.dart';

/// Replaces complete ordinary artwork without changing its metadata ownership.
AiNativeDrawing _replaceNativePathArtwork(
  AiNativeDrawing drawing,
  AiNativePath path,
  AiArtworkPath artwork,
  AiBoundingBox bounds,
  double opacity,
  bool hidden,
  bool fillOverprint,
  bool strokeOverprint, {
  AiNativeTransparency? transparency,
  AiNativeNamedColor? namedFill,
  AiNativeNamedColor? namedStroke,
  AiNativeShapeParameters? shapeParameters,
  double? rotationRadians,
}) {
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing)));
  if (retained.any((owner) => path.start >= owner.start && path.end <= owner.end)) {
    throw UnsupportedError('Appearance descendants require their complete native and printing transaction.');
  }
  final AiNativeInstruction? count = _ordinaryPathCounts(drawing, [path], appearanceArtwork: retained)[path];
  final AiNativeObject object = _ordinaryObject(drawing, path);
  if ((object.liveShape != null) != (shapeParameters != null)) {
    throw UnsupportedError('Dynamic shapes require synchronized native parameters and artwork.');
  }
  final _NativeSubtreeSpan source = (start: count?.start ?? path.start, end: object.end);
  final List<_NativeSubtreeSpan> images = _imageCreationNeutralSpans(drawing).where((span) => span.end <= source.start).toList();
  final Map<int, _NativeShapeInputs> original = _shapeCopyInputs(drawing, [source.start, source.end], neutralSpans: images, appearanceArtwork: retained);
  final List<AiSourceEdit> metadata = [];
  if (shapeParameters != null) {
    final AiLiveShape shape = object.liveShape!;
    metadata.add(_replaceShapeParameterDictionary(drawing, shape.parameters, shapeParameters));
    if (shape.handler != shapeParameters.handler) {
      final AiNativeEntry handler = shape.definition['ai::LiveShape::HandlerName']!;
      metadata.add(AiSourceEdit(start: handler.items.first.start, end: handler.items.first.end, bytes: _nativeString(shapeParameters.handler)));
      metadata.addAll(handler.items.skip(1).map((item) => AiSourceEdit(start: item.start, end: item.end, bytes: [])));
    }
    metadata.addAll(_nativeFrameRotationEdits(drawing.records, object.dictionary, object.end, rotationRadians));
  }
  final List<int> replacement = [
    ..._createdNativePathBytes(
      drawing,
      AiNativePathDefinition(
        artwork: artwork,
        namedFill: namedFill,
        namedStroke: namedStroke,
        bounds: bounds,
        counted: count != null,
        opacity: opacity,
        transparency: transparency,
        hidden: hidden,
        fillOverprint: fillOverprint,
        strokeOverprint: strokeOverprint,
      ),
      retainedCenter: _pathInterval(drawing.items, source.start, path.start, (item) => item.start).whereType<AiNativeInstruction>().where((item) => item.operator == 'Ap').toList(),
    ),
    ...AiNativeEditor.copyRange(program: drawing.records.program, start: path.end, end: object.end, edits: metadata),
  ];
  final AiNativeDrawing provisional = _pathLifecycleResult(drawing, [AiSourceEdit(start: source.start, end: source.end, bytes: replacement)], drawing.paths.length);
  final _NativeSubtreeSpan span = (start: source.start, end: source.start + replacement.length);
  final List<AiNativeInstruction> commands = _pathInterval(provisional.items, span.start, span.end, (item) => item.start).whereType<AiNativeInstruction>().toList();
  final List<AiNativeAppearanceArtwork> provisionalArtwork = _nativeBodyAppearanceArtwork(AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: provisional)));
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(provisional, [span.start, span.end], neutralSpans: images, appearanceArtwork: provisionalArtwork);
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    provisional,
    span,
    commands,
    const {},
    _subtreeCopyAccess(provisional, commands, const [], states),
    states[span.start]!,
    states[span.end]!,
    original[source.start]!,
    original[source.end]!,
    maxBytes: drawing.records.program.limits.maxDecodedBytes,
  );
  _sourceFollowingDependencies(drawing, {source: placed.replacement}, retainedArtwork: retained);
  return _pathLifecycleResult(drawing, [
    AiSourceEdit(start: source.start, end: source.end, bytes: placed.bytes),
    ...AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds),
  ], drawing.paths.length);
}
