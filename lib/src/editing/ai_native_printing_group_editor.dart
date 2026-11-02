part of 'package:aikit/src/model/ai_native_records.dart';

/// Writes supplied samples while restoring every observable source assignment.
AiNativeAppearanceReplacement _nativeRasterAppearanceReplacement(
  AiNativeAppearanceArtwork artwork,
  AiNativeRasterSamples samples,
  List<double> matrix,
  AiNativeTransparency transparency,
  AiBoundingBox bounds,
) {
  if (artwork.resource != null || artwork.liveShape != null || samples.imageMask) {
    throw UnsupportedError('Raster appearance replacements require process pixels and an ordinary body owner.');
  }
  final AiNativeDrawing drawing = artwork._owner.structure.drawing;
  final AiNativeLimits limits = drawing.records.program.limits;
  final Set<String> keys = {..._printingState(drawing, artwork.printingGroup, clipping: true).keys, 'Xy'};
  final _NativeShapeInputs state = _shapeCopyInputs(
    drawing,
    [artwork.printingGroup.end],
    clipping: true,
    appearanceArtwork: _nativeBodyAppearanceArtwork(artwork._owner),
  )[artwork.printingGroup.end]!;
  final StringBuffer suffix = StringBuffer('\n');
  for (final String key in keys) {
    final AiNativeInstruction? value = state.printing[key];
    if (value == null) {
      throw UnsupportedError('Raster appearance replacement cannot restore unknown printing $key state.');
    }
    suffix.write(_shapeStateText(value, private: false));
  }
  suffix.write('U');
  final List<int> prefix = latin1.encode('u\n${transparency.operands.join(' ')} Xy\n');
  final Uint8List image = samples.encodePrintingArtwork(matrix: matrix, limits: limits);
  if (prefix.length + image.length + suffix.length > limits.maxDecodedBytes) {
    throw const AiLimitException(message: 'Composed raster printing exceeds native byte limits.');
  }
  return AiNativeAppearanceReplacement(artwork: artwork, bytes: [...prefix, ...image, ...latin1.encode(suffix.toString())], bounds: bounds);
}

/// Attaches complete derived groups without changing resources or outgoing state.
AiNativeDrawing _replaceNativePrintingGroups(AiNativeDrawing drawing, List<AiNativePrintingGroupReplacement> replacements) {
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: drawing.records.program, edits: _nativePrintingGroupEdits(drawing, replacements)),
    ),
  );
  if (result.liveShapes.length != drawing.liveShapes.length || result.liveShapes.indexed.any((entry) => drawing.liveShapes[entry.$1].isBound && !entry.$2.isBound)) {
    throw const FormatException('Supplied printing groups changed native shape ownership.');
  }
  return result;
}

/// Plans validated group and bounds edits for a single atomic native transaction.
List<AiSourceEdit> _nativePrintingGroupEdits(AiNativeDrawing drawing, List<AiNativePrintingGroupReplacement> replacements) {
  if (replacements.isEmpty || replacements.map((replacement) => replacement.shape).toSet().length != replacements.length) {
    throw ArgumentError('Printing replacement requires a nonempty distinct shape selection.');
  }
  return _nativePrintingSourceEdits(drawing, [
    for (final AiNativePrintingGroupReplacement replacement in replacements)
      (group: _printingShapeGroup(drawing, replacement.shape, clipping: true), bytes: replacement.bytes, bounds: replacement.bounds),
  ]);
}

/// Shares expansion validation across live-shape and ordinary appearance users.
List<AiSourceEdit> _nativePrintingSourceEdits(AiNativeDrawing drawing, List<({AiNativeGroup group, List<int> bytes, AiBoundingBox bounds})> replacements, {bool documentBounds = true}) {
  if (replacements.isEmpty || replacements.map((replacement) => replacement.group).toSet().length != replacements.length) {
    throw ArgumentError('Printing replacement requires distinct owned groups.');
  }
  final AiProgram program = drawing.records.program;
  final List<AiSourceEdit> edits = [];
  final List<AiBoundingBox> bounds = [];
  AiNativeGradientResources? resources;
  int total = 0;
  for (final ({AiNativeGroup group, List<int> bytes, AiBoundingBox bounds}) replacement in replacements) {
    final AiNativeGroup source = replacement.group;
    total += replacement.bytes.length;
    if (total > program.limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'Supplied printing groups exceed native output limits.');
    }
    final AiNativeDrawing supplied = _printingFragment(replacement.bytes, program.limits);
    final AiNativeGroup group = supplied.groups.last;
    final Map<String, String> before = _printingState(drawing, source, clipping: true);
    final Map<String, String> after = _printingState(supplied, group, clipping: true);
    final Map<String, AiNativeInstruction> incoming = source.start >= program.bodyStart ? _shapeCopyInputs(drawing, [source.start], clipping: true)[source.start]!.printing : const {};
    for (final String key in {...before.keys, ...after.keys}) {
      final AiNativeInstruction? command = incoming[key];
      final String? inherited = command == null ? null : '${command.operator} ${command.operands.map((operand) => operand.number?.toDouble().toString() ?? operand.lexeme).join(' ')}';
      if ((before[key] ?? inherited) != (after[key] ?? inherited)) {
        throw UnsupportedError('Supplied printing artwork changes the outgoing paint state; preserve the source group boundary.');
      }
    }
    final Map<AiNativePath, AiNativeInstruction> oldCounts = _printingPointCounts(drawing, source);
    final Map<AiNativePath, AiNativeInstruction> newCounts = _printingPointCounts(supplied, group);
    if (source.paths.isNotEmpty && group.paths.isNotEmpty && oldCounts.isEmpty != newCounts.isEmpty ||
        oldCounts.isNotEmpty && oldCounts.length != source.paths.length ||
        newCounts.isNotEmpty && newCounts.length != group.paths.length) {
      throw UnsupportedError('Supplied printing artwork must retain the source point-count convention.');
    }
    final List<AiNativeGradient> gradients = [
      ...drawing.gradients.where((gradient) => gradient.start >= source.start && gradient.end <= source.end),
      ...supplied.gradients,
    ];
    if (gradients.isNotEmpty) {
      resources ??= AiNativeGradientResources.decode(records: drawing.records);
      for (final AiNativeGradient gradient in gradients) {
        final List<AiNativeGradientDefinition> definitions = resources.definitions.where((definition) => _sameNativeBytes(definition.nameBytes, gradient.geometry.nameBytes)).toList();
        if (definitions.length != 1 || gradient.highlight != null && !definitions.single.radial) {
          throw UnsupportedError('Printing gradients require one compatible existing resource definition.');
        }
      }
    }
    edits.add(AiSourceEdit(start: source.start, end: source.end, bytes: replacement.bytes));
    bounds.add(replacement.bounds);
  }
  if (documentBounds) {
    edits.addAll(
      AiNativeEditor.includeBoundsEdits(
        program: program,
        bounds: AiBoundingBox(
          left: bounds.map((bound) => bound.left).reduce(min),
          bottom: bounds.map((bound) => bound.bottom).reduce(min),
          right: bounds.map((bound) => bound.right).reduce(max),
          top: bounds.map((bound) => bound.top).reduce(max),
        ),
      ),
    );
  }
  return edits;
}

/// Parses one bounded group without letting fragment comments redefine its body.
AiNativeDrawing _printingFragment(List<int> bytes, AiNativeLimits limits) {
  final List<AiToken> tokens = AiPostScript.tokenize(bytes, maxBytes: limits.maxDecodedBytes, maxTokens: limits.maxTokens, maxDepth: limits.maxDepth);
  if (tokens.any(
    (token) =>
        token.kind == .comment &&
        (token.lexeme.startsWith('%_') ||
            token.lexeme.startsWith('%%') && !token.lexeme.startsWith('%%BeginData:') && token.lexeme != '%%EndData' ||
            token.lexeme.startsWith('%AI') && !const {'%AI5_BeginRaster', '%AI5_EndRaster'}.contains(token.lexeme)),
  )) {
    throw UnsupportedError('A printing group cannot contain document boundaries or private metadata.');
  }
  final List<AiToken> body = tokens.where((token) => token.kind != .comment).toList();
  if (body.isEmpty || body.first.lexeme != 'u' || body.last.lexeme != 'U') {
    throw const FormatException('Supplied printing artwork must be one ordinary group.');
  }
  const String header = '%!PS-Adobe-3.0\n%%EndComments\n%%EndSetup\n';
  const String trailer = '\n%%Trailer\n%%EOF\n';
  if (header.length + bytes.length + trailer.length > limits.maxDecodedBytes) {
    throw const AiLimitException(message: 'Supplied printing group exceeds the native inspection limit.');
  }
  final AiNativeDrawing drawing = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(bytes: [...latin1.encode(header), ...bytes, ...latin1.encode(trailer)], limits: limits),
    ),
  );
  if (drawing.groups.isEmpty || drawing.groups.last.start != header.length + body.first.start || drawing.groups.last.end != header.length + body.last.end) {
    throw const FormatException('Supplied printing artwork contains multiple root objects.');
  }
  _printingCommands(drawing, drawing.groups.last, clipping: true);
  return drawing;
}

/// Compares native names byte-for-byte without selecting a text encoding.
bool _sameNativeBytes(List<int> first, List<int> second) => first.length == second.length && first.indexed.every((entry) => entry.$2 == second[entry.$1]);
