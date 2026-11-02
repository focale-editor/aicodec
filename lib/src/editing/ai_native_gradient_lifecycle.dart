part of 'package:aicodec/src/model/ai_native_records.dart';

/// Validates ordered stops without sorting away the two sides of a hard edge.
void _validateGradientStops(List<AiNativeGradientStop> stops, List<AiNativeGradientRamp> ramps) {
  if (stops.length < 2 || ramps.length != stops.length - 1 || stops.first.position >= stops.last.position) {
    throw ArgumentError('Gradients require a positive extent, at least two stops and one explicit ramp per adjacent pair.');
  }
  for (int index = 1; index < stops.length; index++) {
    if (stops[index].position > stops[index - 1].position && stops[index].position / 100 == stops[index - 1].position / 100) {
      throw const FormatException('Gradient interval collapses at floating-point precision.');
    }
    if (stops[index].position < stops[index - 1].position) {
      throw ArgumentError('Gradient positions must be nondecreasing; equal-position stop order is significant.');
    }
  }
}

/// Qualifies complete resource references, including retained setup and artwork.
AiNativeAppearances _paintResourceScope(AiNativeRecords records) {
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final AiNativeAppearances model = AiNativeAppearances.decode(structure: layers.structure);
  final _ArtboardResourceScope resources = _artboardResourceScope(layers);
  final _ArtboardBrushScope brushes = _artboardBrushScope(layers, resources.brushes);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  _nativeReferenceScope(
    layers,
    headers,
    bodyDictionaries: _nativeReferenceBody(
      layers,
      headers,
      inspect: _nativeAppearanceInterval,
      qualifyShapeNeighbors: false,
      clipping: true,
      appearanceArtwork: _nativeRetainedAppearanceArtwork(model),
      patterns: model._patternNames,
    ),
    retainedResources: resources,
    retainedBrushes: brushes,
  );
  final AiNativeSymbols symbols = AiNativeSymbols.decode(artworkResources: model.artworkResources);
  for (final AiNativeSymbolInstance instance in symbols.instances) {
    if (instance.definition == null || instance.resource != null || instance.otherEntries.isNotEmpty || instance.node.versions.isNotEmpty) {
      throw UnsupportedError('Resource edits require uniquely resolved unconditional static symbol instances.');
    }
    _nativeSymbolDefinition(instance.record);
  }
  return model;
}

/// Emits a complete CC gradient while retaining caller-supplied interpolation.
Uint8List _nativeGradientDefinitionBytes(List<int> name, bool radial, List<AiNativeGradientStop> stops, List<AiNativeGradientRamp> ramps, int limit) {
  final _GradientResourceWriter writer = _GradientResourceWriter(limit: limit);
  writer.add('\n%AI5_BeginGradient: ');
  writer.string(name);
  writer.add('\n');
  writer.string(name);
  writer.add(' ${radial ? 1 : 0} ${stops.length} Bd\n[\n');
  for (final AiNativeGradientRamp ramp in ramps) {
    for (final AiNativeGradientChannel channel in ramp.channels) {
      if (channel.constant case final double value) {
        writer.add('$value\n');
      } else {
        writer.hex(channel.samples!);
        writer.add('\n');
      }
    }
    writer.add('${ramp.kind.index} %_Br\n');
  }
  writer.add('[\n');
  for (final AiNativeGradientStop stop in radial ? stops : stops.reversed) {
    writer.stop(stop);
    writer.add(' %_BS\n%_');
    writer.stop(stop);
    writer.add(' Bs\n');
  }
  writer.add('BD\n%AI5_EndGradient\n');
  return writer.output.takeBytes();
}

/// Adds a resource consistently to each counted printing/nonprinting bank.
AiNativeGradientResources _createNativeGradient(AiNativeGradientResources resources, List<int> name, bool radial, List<AiNativeGradientStop> stops, List<AiNativeGradientRamp> ramps) {
  _validateGradientStops(stops, ramps);
  if (name.isEmpty || name.any((byte) => byte < 0 || byte > 255) || resources.definitions.any((definition) => _sameNativeBytes(definition.nameBytes, name))) {
    throw ArgumentError('A new gradient requires an unused nonempty byte name.');
  }
  _paintResourceScope(resources.records);
  if (_readGradientInstances(resources.records).any((instance) => _sameNativeBytes(instance.geometry.nameBytes, name))) {
    throw ArgumentError('The gradient name is already referenced.');
  }
  final AiProgram program = resources.records.program;
  final List<_NativeGradientBank> banks = _nativeGradientBanks(resources);
  final List<AiToken> tokens = resources.records._projection.tokens;
  final List<AiSourceEdit> edits = [];
  int remaining = program.limits.maxDecodedBytes - program.bytes.length;
  final Uint8List definition = _nativeGradientDefinitionBytes(name, radial, stops, ramps, remaining);
  if (banks.isEmpty) {
    final List<AiToken> endings = tokens.where((token) => token.kind == .comment && token.lexeme == '%%EndSetup' && token.start < program.bodyStart).toList();
    if (endings.length != 1) {
      throw UnsupportedError('The first gradient bank requires one explicit setup boundary.');
    }
    edits.add(AiSourceEdit(start: endings.single.start, end: endings.single.start, bytes: [...latin1.encode('1 Bn\n'), ...definition]));
  } else {
    for (final _NativeGradientBank bank in banks) {
      final AiToken operator = tokens.skip(_pathOffset(tokens, bank.count.end, (token) => token.start)).firstWhere((token) => token.kind != .comment);
      final List<int> count = latin1.encode('${bank.definitions.length + 1}');
      remaining -= definition.length + count.length - (bank.count.end - bank.count.start);
      if (remaining < 0) {
        throw const AiLimitException(message: 'Gradient banks exceed the aggregate output limit.');
      }
      edits.add(AiSourceEdit(start: bank.count.start, end: bank.count.end, bytes: count));
      edits.add(AiSourceEdit(start: operator.end, end: operator.end, bytes: definition));
    }
  }
  return AiNativeGradientResources.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: program, edits: edits),
    ),
  );
}

/// Removes whole wrapper-owned resources and updates all matching bank counts.
AiNativeGradientResources _removeNativeGradient(AiNativeGradientResources resources, AiNativeGradientDefinition definition) {
  if (!resources.definitions.contains(definition)) {
    throw ArgumentError('Gradient removal requires a current resource handle.');
  }
  final AiNativeAppearances model = _paintResourceScope(resources.records);
  if (_readGradientInstances(resources.records).any((instance) => _sameNativeBytes(instance.geometry.nameBytes, definition.nameBytes))) {
    throw UnsupportedError('A referenced gradient cannot be removed.');
  }
  final List<({int start, int end})> ranges = _referenceGradientRanges(AiNativeLayers.decode(drawing: model.structure.drawing));
  final List<AiSourceEdit> edits = [];
  for (final _NativeGradientBank bank in _nativeGradientBanks(resources)) {
    final List<AiNativeGradientDefinition> selected = bank.definitions.where((entry) => _sameNativeBytes(entry.nameBytes, definition.nameBytes)).toList();
    if (selected.isEmpty) {
      continue;
    }
    edits.add(AiSourceEdit(start: bank.count.start, end: bank.count.end, bytes: latin1.encode('${bank.definitions.length - selected.length}')));
    for (final AiNativeGradientDefinition entry in selected) {
      final ({int start, int end}) span = ranges.singleWhere((span) => span.start < entry.start && span.end > entry.end);
      edits.add(AiSourceEdit(start: span.start, end: span.end, bytes: []));
    }
  }
  return AiNativeGradientResources.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: resources.records.program, edits: edits),
    ),
  );
}

/// Rebinds an exact native application without guessing dependent printing strips.
List<AiSourceEdit> _nativeGradientApplicationEdits(AiNativeRecords records, AiNativeGradient application, AiNativeGradientDefinition target) {
  if (!records._projection.tokens.contains(target.opening.token)) {
    throw ArgumentError('Gradient applications require a target from the same source snapshot.');
  }
  final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: records);
  final List<AiNativeGradientDefinition> before = resources.definitions.where((definition) => _sameNativeBytes(definition.nameBytes, application.geometry.nameBytes)).toList();
  final List<AiNativeGradientDefinition> after = resources.definitions.where((definition) => _sameNativeBytes(definition.nameBytes, target.nameBytes)).toList();
  if (before.isEmpty || after.isEmpty || before.any((definition) => definition.radial != target.radial) || after.any((definition) => definition.radial != target.radial)) {
    throw UnsupportedError('Gradient rebinding requires resolved resources of the same native kind.');
  }
  if (application.imagingMatrices.isNotEmpty) {
    final List<double> positions = target.stops.map((stop) => stop.position).toList();
    if (before.any((definition) => !_sameNativeMatrix(definition.stops.map((stop) => stop.position).toList(), positions))) {
      throw UnsupportedError('Rebinding cached interval geometry requires matching stop positions.');
    }
  }
  final AiToken name = application.geometry.instruction.operands[application.geometry.nameIndex];
  return [AiSourceEdit(start: name.start, end: name.end, bytes: _nativeLiteralString(target.nameBytes, records.program.limits.maxDecodedBytes))];
}
