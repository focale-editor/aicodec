part of 'package:aikit/src/model/ai_native_records.dart';

/// Validates a selected header and every enclosing layer before structural edits.
void _qualifiedLayerHeader(AiNativeLayers model, AiNativeLayer layer) {
  model._requireOwned(layer);
  AiNativeLayer? current = layer;
  while (current != null) {
    if (current.bindingIssue case final String issue) {
      throw UnsupportedError(issue);
    }
    _ordinaryPathFollowing(model.drawing.items, current.source.end.end);
    int following = model.drawing.records.program.bodyEnd;
    for (int index = _pathOffset(model.drawing.items, current.end, (item) => item.start); index < model.drawing.items.length; index++) {
      final AiNativeItem item = model.drawing.items[index];
      if (item is AiNativeInstruction && const {'m', 'u', 'U', 'Lb', 'LB'}.contains(item.operator)) {
        following = item.start;
        if (item.operator == 'Lb') {
          final AiNativeLayer next = model.layers.firstWhere((layer) => layer.source.begin.start == item.start);
          following = next.start;
        }
        break;
      }
    }
    _ordinaryGroupMetadata(model.drawing, current.end, following);
    current = current.parentIndex == null ? null : model.layers[current.parentIndex!];
  }
  if (!model.rootCountMatches) {
    throw const FormatException('The declared native root-layer count disagrees with its owners.');
  }
}

/// Plans count updates and explicitly requested invalidation of opaque panel data.
List<AiSourceEdit> _layerDeclarations(AiNativeLayers model, int rootCount, bool discardViewState) {
  if (model.viewComments.isNotEmpty && !discardViewState) {
    throw UnsupportedError('Changing layer structure requires discardViewState for the unqualified saved layer-view mapping.');
  }
  final List<AiSourceEdit> edits = [for (final AiToken token in model.viewComments) AiSourceEdit(start: token.start, end: token.end, bytes: [])];
  if (model.rootCountHeader case final AiNativeHeaderField field) {
    if (rootCount != model.rootCount) {
      final String prefix = field.token.lexeme.substring(0, field.token.lexeme.indexOf(':') + 1);
      edits.add(AiSourceEdit(start: field.token.start, end: field.token.end, bytes: latin1.encode('$prefix $rootCount')));
    }
  }
  return edits;
}

/// Encodes caller-supplied byte strings after bounding their escaped output size.
List<int> _layerString(List<int> value, int maxBytes) {
  if (value.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('A native layer name or identifier must contain bytes.');
  }
  if (value.length * 4 + 2 > maxBytes) {
    throw const AiLimitException(message: 'Escaped layer strings exceed the native byte limit.');
  }
  return latin1.encode('(${value.map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()})');
}

/// Reserves qualified XML artwork identities without merging equal source owners.
Set<String> _layerIdentityNames(AiNativeLayers model) => {
  for (final AiNativeObjectIdentifier identifier in model.structure.identifiers)
    if (identifier.kind == .xmlArt) latin1.decode(identifier.bytes),
};

/// Encodes one fresh identity and replaces only its source-owned string token.
AiSourceEdit _layerIdentityEdit(AiNativeLayer layer, List<int> identifierBytes, Set<String> reserved, int maxBytes) {
  final List<int> encoded = _layerString(identifierBytes, maxBytes);
  if (identifierBytes.any((byte) => byte > 127) || !RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(latin1.decode(identifierBytes))) {
    throw ArgumentError('New layer identifiers require a nonempty portable XML name.');
  }
  if (!reserved.add(latin1.decode(identifierBytes))) {
    throw ArgumentError('The new layer identifier already belongs to the native source or this transaction.');
  }
  final AiNativeItem value = layer.identifier!.field.entry.container!.entries.single.items.single;
  return AiSourceEdit(start: value.start, end: value.end, bytes: encoded);
}

/// Copies a header dictionary while assigning a distinct caller-owned XML name.
List<int> _newLayerDictionary(AiNativeLayers model, AiNativeLayer layer, List<int>? identifierBytes) {
  if ((layer.identifier == null) != (identifierBytes == null)) {
    throw ArgumentError('Identified layer templates require a fresh identifier; anonymous templates retain their layout.');
  }
  final List<AiSourceEdit> edits = [];
  if (identifierBytes != null) {
    edits.add(_layerIdentityEdit(layer, identifierBytes, _layerIdentityNames(model), model.drawing.records.program.limits.maxDecodedBytes));
  }
  final AiNativeContainer? dictionary = layer.dictionary;
  if (dictionary == null) {
    return [];
  }
  return [
    if (model.drawing.records._projection.isPrivate(dictionary.start)) ...[37, 95],
    ...AiNativeEditor.copyRange(program: model.drawing.records.program, start: dictionary.start, end: dictionary.end, edits: edits),
  ];
}

/// Creates one empty layer while leaving all source artwork and paint unchanged.
AiNativeLayers _insertNativeLayer(AiNativeLayers model, AiNativeLayer after, List<int> nameBytes, List<int>? identifierBytes, bool discardViewState) {
  _qualifiedLayerHeader(model, after);
  final AiProgram program = model.drawing.records.program;
  final List<AiSourceEdit> edits = _layerDeclarations(model, model.rootCount + (after.parentIndex == null ? 1 : 0), discardViewState);
  final List<int> name = _layerString(nameBytes, program.limits.maxDecodedBytes);
  final List<int> dictionary = _newLayerDictionary(model, after, identifierBytes);
  final int lineEnd = program.bytes.indexOf(10);
  final String newline = lineEnd > 0 && program.bytes[lineEnd - 1] == 13 ? '\r\n' : '\n';
  final BytesBuilder bytes = BytesBuilder(copy: false);

  /// Bounds the complete inserted wrapper before retaining copied source data.
  void append(List<int> value) {
    if (bytes.length + value.length > program.limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'Inserted layer exceeds the native output limit.');
    }
    bytes.add(value);
  }

  append(latin1.encode(newline));
  if (after.openingComment != null) {
    append(latin1.encode('%AI5_BeginLayer$newline'));
  }
  append(Uint8List.sublistView(program.bytes, after.source.begin.start, after.source.begin.end));
  append(latin1.encode(newline));
  append(name);
  append(latin1.encode(' Ln$newline'));
  if (after.expansion != null) {
    append(latin1.encode('0 AE$newline'));
  }
  if (dictionary.isNotEmpty) {
    append(dictionary);
    append(latin1.encode(newline));
  }
  append(latin1.encode('LB$newline'));
  if (after.closingComment != null) {
    append(latin1.encode('${after.closingComment!.lexeme}$newline'));
  }
  edits.add(AiSourceEdit(start: after.end, end: after.end, bytes: bytes.takeBytes()));
  final AiNativeDrawing drawing = _pathLifecycleResult(model.drawing, edits, model.drawing.paths.length);
  final AiNativeLayers result = AiNativeLayers.decode(drawing: drawing);
  if (result.layers.length != model.layers.length + 1 || result.rootCount != model.rootCount + (after.parentIndex == null ? 1 : 0) || !result.rootCountMatches) {
    throw const FormatException('Inserted layer changed unrelated ownership or root counts.');
  }
  return result;
}
