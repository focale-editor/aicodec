part of 'package:aikit/src/model/ai_native_records.dart';

/// Writes explicit normal-path attributes, geometry, count and requested metadata.
List<int> _createdNativePathBytes(AiNativeDrawing drawing, AiNativePathDefinition definition) {
  final AiArtworkPath path = definition.artwork;
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  final StringBuffer output = StringBuffer();

  /// Bounds each new command before retaining the complete source fragment.
  void line(String value) {
    if (output.length + value.length + 1 > maximum) {
      throw const AiLimitException(message: 'Created path exceeds the native output limit.');
    }
    output.writeln(value);
  }

  /// Preserves the supplied process color space without using a rendering engine.
  void color(AiColor value, {required bool stroke}) {
    final String operator = switch (value.space) {
      AiColorSpace.gray => stroke ? 'G' : 'g',
      AiColorSpace.rgb => stroke ? 'XA' : 'Xa',
      AiColorSpace.cmyk => stroke ? 'K' : 'k',
    };
    line('${value.channels.join(' ')} $operator');
  }

  line('${path.locked ? 1 : 0} A');
  line('${definition.hidden ? 1 : 0} Xw');
  line('0 Ap');
  line('0 D');
  line('${path.evenOdd ? 1 : 0} XR');
  if (path.fill != null || path.stroke != null) {
    line('0 ${definition.opacity} 0 0 0 Xy');
  }
  if (path.fill case final AiColor fill) {
    line('${definition.fillOverprint ? 1 : 0} O');
    color(fill, stroke: false);
  }
  if (path.stroke case final AiColor stroke) {
    line('${definition.strokeOverprint ? 1 : 0} R');
    color(stroke, stroke: true);
    line('${path.strokeWidth} w');
    line('${path.lineCap} J');
    line('${path.lineJoin} j');
    line('${path.miterLimit} M');
    line('[${path.dash.join(' ')}] ${path.dashPhase} d');
  }
  final List<AiPathSegment> segments = [...path.segments];
  if (definition.counted && path.closed) {
    final List<double> first = segments.first.coordinates;
    final List<double> last = segments.last.coordinates;
    if (segments.length == 1 || first[0] != last[last.length - 2] || first[1] != last.last) {
      segments.add(AiPathSegment(operator: 'L', coordinates: first));
    }
  }
  if (definition.counted) {
    line('${segments.length - (path.closed ? 1 : 0)} As');
  }
  for (final AiPathSegment segment in segments) {
    line('${segment.coordinates.join(' ')} ${segment.operator}');
  }
  final String paint = path.fill == null
      ? path.stroke == null
            ? 'N'
            : 'S'
      : path.stroke == null
      ? 'F'
      : 'B';
  line(path.closed ? paint.toLowerCase() : paint);
  final List<int> metadata = _createdNativeMetadata(drawing, definition.nameBytes, definition.identifierBytes, '\n');
  if (output.length + metadata.length > maximum) {
    throw const AiLimitException(message: 'Created path metadata exceeds the native output limit.');
  }
  return [...latin1.encode(output.toString()), ...metadata];
}

/// Creates a source-native path and restores both outgoing state projections.
AiNativeDrawing _createNativePath(AiNativeDrawing drawing, AiNativePathDefinition definition, AiNativeGroup? parent, AiLayer? layer) {
  final int position = _nativeCreationPosition(drawing, parent, layer);
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final List<AiLiveShape> bound = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((first, second) => first.end.compareTo(second.end));
  _ordinaryArtworkPrefix(drawing, position, bound, _layerHeaderItems(layers), privateState: true);
  final _NativeShapeInputs incoming = _shapeCopyInputs(drawing, [position])[position]!;
  final List<int> bytes = _createdNativePathBytes(drawing, definition);
  final AiNativeDrawing provisional = _pathLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: position, end: position, bytes: [10, ...bytes]),
    ],
    drawing.paths.length + 1,
  );
  final _NativeSubtreeSpan span = (start: position + 1, end: position + 1 + bytes.length);
  final AiNativePath path = provisional.paths.singleWhere((path) => path.start >= span.start && path.end <= span.end);
  _ordinaryPathCounts(provisional, [path]);
  final AiNativeObject object = _ordinaryObject(provisional, path);
  if (object.start != path.start || object.end > span.end) {
    throw UnsupportedError('Creating a path cannot capture existing native metadata.');
  }
  final List<AiNativeInstruction> commands = _pathInterval(provisional.items, span.start, span.end, (item) => item.start).whereType<AiNativeInstruction>().toList();
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(provisional, [span.start, span.end]);
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    provisional,
    span,
    commands,
    const {},
    _subtreeCopyAccess(provisional, commands, const [], states),
    states[span.start]!,
    states[span.end]!,
    incoming,
    incoming,
    maxBytes: drawing.records.program.limits.maxDecodedBytes,
  );
  _sourceFollowingDependencies(drawing, const {}, insertions: {position: placed.replacement});
  return _groupLifecycleResult(
    drawing,
    [AiSourceEdit(start: position, end: position, bytes: placed.bytes), ...AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: definition.bounds)],
    paths: drawing.paths.length + 1,
    groups: drawing.groups.length,
    liveShapes: drawing.liveShapes.length,
  );
}
