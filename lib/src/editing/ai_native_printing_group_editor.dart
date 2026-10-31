part of 'package:aikit/src/model/ai_native_records.dart';

/// Attaches complete derived groups without changing resources or outgoing state.
AiNativeDrawing _replaceNativePrintingGroups(AiNativeDrawing drawing, List<AiNativePrintingGroupReplacement> replacements) {
  if (replacements.isEmpty || replacements.map((replacement) => replacement.shape).toSet().length != replacements.length) {
    throw ArgumentError('Printing replacement requires a nonempty distinct shape selection.');
  }
  final AiProgram program = drawing.records.program;
  final List<AiSourceEdit> edits = [];
  final List<AiBoundingBox> bounds = [];
  AiNativeGradientResources? resources;
  int total = 0;
  for (final AiNativePrintingGroupReplacement replacement in replacements) {
    final AiNativeGroup source = _printingShapeGroup(drawing, replacement.shape);
    total += replacement.bytes.length;
    if (total > program.limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'Supplied printing groups exceed native output limits.');
    }
    final AiNativeDrawing supplied = _printingFragment(replacement.bytes, program.limits);
    final AiNativeGroup group = supplied.groups.last;
    final Map<String, String> before = _printingState(drawing, source);
    final Map<String, String> after = _printingState(supplied, group);
    if (before.length != after.length || before.entries.any((entry) => after[entry.key] != entry.value)) {
      throw UnsupportedError('Supplied printing artwork changes the outgoing paint state; preserve the source group boundary.');
    }
    final Map<AiNativePath, AiNativeInstruction> oldCounts = _printingPointCounts(drawing, source);
    final Map<AiNativePath, AiNativeInstruction> newCounts = _printingPointCounts(supplied, group);
    if (oldCounts.isEmpty != newCounts.isEmpty || oldCounts.isNotEmpty && (oldCounts.length != source.paths.length || newCounts.length != group.paths.length)) {
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
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: program, edits: edits),
    ),
  );
  if (result.liveShapes.length != drawing.liveShapes.length || result.liveShapes.indexed.any((entry) => drawing.liveShapes[entry.$1].isBound && !entry.$2.isBound)) {
    throw const FormatException('Supplied printing groups changed native shape ownership.');
  }
  return result;
}

/// Parses one bounded group without letting fragment comments redefine its body.
AiNativeDrawing _printingFragment(List<int> bytes, AiNativeLimits limits) {
  final List<AiToken> tokens = AiPostScript.tokenize(bytes, maxBytes: limits.maxDecodedBytes, maxTokens: limits.maxTokens, maxDepth: limits.maxDepth);
  if (tokens.any((token) => token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%%') || token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%_')))) {
    throw UnsupportedError('A printing group cannot contain document boundaries, private metadata or opaque payloads.');
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
  return drawing;
}

/// Compares native names byte-for-byte without selecting a text encoding.
bool _sameNativeBytes(List<int> first, List<int> second) => first.length == second.length && first.indexed.every((entry) => entry.$2 == second[entry.$1]);
