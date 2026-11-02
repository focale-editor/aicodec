part of 'package:aikit/src/model/ai_native_records.dart';

/// Supplies literal process paint state without geometry, guides or identities.
Iterable<String> _nativePathPaintCommands(AiNativePathDefinition definition) sync* {
  final AiArtworkPath path = definition.artwork;
  yield '${path.evenOdd ? 1 : 0} XR';
  yield '${definition.transparency?.operands.join(' ') ?? '0 ${definition.opacity} 0 0 0'} Xy';
  yield '${definition.fillOverprint ? 1 : 0} O';
  yield '${definition.strokeOverprint ? 1 : 0} R';
  for (final (AiColor? value, bool stroke) in [(path.fill, false), (path.stroke, true)]) {
    if (value != null) {
      final String operator = switch (value.space) {
        .gray => stroke ? 'G' : 'g',
        .rgb => stroke ? 'XA' : 'Xa',
        .cmyk => stroke ? 'K' : 'k',
      };
      yield '${value.channels.join(' ')} $operator';
    }
  }
  yield '${path.strokeWidth} w';
  yield '${path.lineCap} J';
  yield '${path.lineJoin} j';
  yield '${path.miterLimit} M';
  yield '[${path.dash.join(' ')}] ${path.dashPhase} d';
}

/// Writes explicit artwork while optionally retaining nonvisual center assignments.
List<int> _createdNativePathBytes(
  AiNativeDrawing drawing,
  AiNativePathDefinition definition, {
  AiNativeGradientFillDefinition? gradient,
  List<AiNativeInstruction>? retainedCenter,
  AiNativePathMask mask = .none,
}) {
  final AiArtworkPath path = definition.artwork;
  if (mask != .none && (gradient != null || path.fill != null || path.stroke != null || path.closed != (mask == .closed))) {
    throw ArgumentError('Created clipping paths require unpainted geometry with matching explicit closure.');
  }
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  final StringBuffer output = StringBuffer();

  /// Bounds each new command before retaining the complete source fragment.
  void line(String value) {
    if (output.length + value.length + 1 > maximum) {
      throw const AiLimitException(message: 'Created path exceeds the native output limit.');
    }
    output.writeln(value);
  }

  line('${path.locked ? 1 : 0} A');
  line('${definition.hidden ? 1 : 0} Xw');
  if (retainedCenter == null) {
    line('0 Ap');
  } else {
    for (final AiNativeInstruction instruction in retainedCenter) {
      line(_shapeStateText(instruction, private: instruction.isPrivate).trimRight());
    }
  }
  line('0 D');
  _nativePathPaintCommands(definition).forEach(line);
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
  if (gradient != null) {
    line('Bb');
    if (gradient.highlight case final List<double> highlight) {
      line('${highlight.join(' ')} Bh');
    }
    final String name = latin1.decode(_nativeLiteralString(gradient.nameBytes, maximum));
    line('1 $name ${gradient.origin.join(' ')} ${gradient.angle} ${gradient.length} ${gradient.matrix.join(' ')} Bg');
  }
  final String paint = gradient != null
      ? 'F'
      : path.fill == null
      ? path.stroke == null
            ? 'N'
            : 'S'
      : path.stroke == null
      ? 'F'
      : 'B';
  if (mask == .none) {
    line(path.closed ? paint.toLowerCase() : paint);
  } else {
    line('${mask == .closed ? 'h' : 'H'} W N');
  }
  if (gradient != null) {
    line(
      '${path.stroke == null
          ? 0
          : path.closed
          ? 2
          : 1} BB',
    );
  }
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
  final List<_NativeSubtreeSpan> images = _nativeNeutralArtwork(drawing).where((span) => span.end <= position).toList();
  final List<AiNativeAppearanceArtwork> appearances = _nativeCreationAppearances(drawing);
  _ordinaryArtworkPrefix(drawing, position, bound, _layerHeaderItems(layers), privateState: true, resolvedBoundary: _nativeCreationBoundary(drawing, position, appearances));
  final _NativeShapeInputs incoming = _shapeCopyInputs(drawing, [position], neutralSpans: images, appearanceArtwork: appearances)[position]!;
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
  _ordinaryPathCounts(provisional, [path], appearanceArtwork: _nativeCreationAppearances(provisional));
  final AiNativeObject object = _ordinaryObject(provisional, path);
  if (object.start != path.start || object.end > span.end) {
    throw UnsupportedError('Creating a path cannot capture existing native metadata.');
  }
  final List<AiNativeInstruction> commands = _pathInterval(provisional.items, span.start, span.end, (item) => item.start).whereType<AiNativeInstruction>().toList();
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(provisional, [span.start, span.end], neutralSpans: images, appearanceArtwork: _nativeCreationAppearances(provisional));
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
