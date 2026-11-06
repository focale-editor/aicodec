part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Uses the original program's line-ending convention for newly written layers.
String _layerLineEnding(AiProgram program) {
  final int lineEnd = program.bytes.indexOf(10);
  return lineEnd > 0 && program.bytes[lineEnd - 1] == 13 ? '\r\n' : '\n';
}

/// Validates a selected header and every enclosing layer before structural edits.
void _qualifiedLayerHeader(AiNativeLayers model, AiNativeLayer layer) {
  model._requireOwned(layer);
  AiNativeLayer? current = layer;
  while (current != null) {
    if (current.bindingIssue case final String issue) {
      throw UnsupportedError(issue);
    }
    _ordinaryArtworkFollowing(model.drawing, current.source.end.end);
    int following = _nativeImageOwners(model.drawing).where((owner) => owner.span.start >= current!.end).firstOrNull?.span.start ?? model.drawing.records.program.bodyEnd;
    for (int index = _pathOffset(model.drawing.items, current.end, (item) => item.start); index < model.drawing.items.length; index++) {
      final AiNativeItem item = model.drawing.items[index];
      if (item.start >= following) {
        break;
      }
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

/// Copies a header dictionary while assigning a distinct caller-owned XML name.
List<int> _newLayerDictionary(AiNativeLayers model, AiNativeLayer layer, List<int>? identifierBytes) {
  if ((layer.identifier == null) != (identifierBytes == null)) {
    throw ArgumentError('Identified layer templates require a fresh identifier; anonymous templates retain their layout.');
  }
  final List<AiSourceEdit> edits = [];
  if (identifierBytes != null) {
    edits.add(_nativeIdentityEdit(layer.identifier!, identifierBytes, _nativeIdentityNames(model.structure), model.drawing.records.program.limits.maxDecodedBytes));
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
  final List<int> name = _nativeLiteralString(nameBytes, program.limits.maxDecodedBytes);
  final List<int> dictionary = _newLayerDictionary(model, after, identifierBytes);
  final String newline = _layerLineEnding(program);
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

/// Serializes an explicit empty layer at a complete root or layer boundary.
AiNativeLayers _createNativeLayer(AiNativeLayers model, AiNativeLayerDefinition definition, AiNativeLayer? parent, bool discardViewState) {
  if (parent != null) {
    _qualifiedLayerHeader(model, parent);
  } else if (!model.rootCountMatches) {
    throw const FormatException('The declared native root-layer count disagrees with its owners.');
  }
  final AiProgram program = model.drawing.records.program;
  final int rootCount = model.rootCount + (parent == null ? 1 : 0);
  final List<AiSourceEdit> edits = _layerDeclarations(model, rootCount, discardViewState);
  final List<int> name = _nativeLiteralString(definition.nameBytes, program.limits.maxDecodedBytes);
  final List<int>? identifier = definition.identifierBytes == null ? null : _newNativeIdentity(definition.identifierBytes!, _nativeIdentityNames(model.structure), program.limits.maxDecodedBytes);
  final String newline = _layerLineEnding(program);
  final StringBuffer output = StringBuffer(
    '$newline%AI5_BeginLayer$newline${definition.attributes.map((value) => value.toInt()).join(' ')} Lb$newline${latin1.decode(name)} Ln$newline${definition.expanded ? 1 : 0} AE$newline',
  );
  if (identifier != null) {
    output.write('%_/ArtDictionary :$newline%_/XMLUID : ${latin1.decode(identifier)} ; (AI10_ArtUID) ,$newline%_;$newline');
  }
  output.write('LB$newline%AI5_EndLayer--$newline');
  if (output.length > program.limits.maxDecodedBytes) {
    throw const AiLimitException(message: 'Created layer exceeds the native output limit.');
  }
  final int position = parent?.source.end.start ?? program.bodyEnd;
  final int changedPosition = position + edits.fold<int>(0, (offset, edit) => offset + (edit.end <= position ? edit.bytes.length - (edit.end - edit.start) : 0));
  edits.add(AiSourceEdit(start: position, end: position, bytes: latin1.encode(output.toString())));
  final AiNativeDrawing drawing = _pathLifecycleResult(model.drawing, edits, model.drawing.paths.length);
  final AiNativeLayers result = AiNativeLayers.decode(drawing: drawing);
  final List<AiNativeLayer> created = result.layers.where((layer) => layer.start >= changedPosition && layer.end <= changedPosition + output.length).toList();
  if (result.layers.length != model.layers.length + 1 || result.rootCount != rootCount || !result.rootCountMatches || created.length != 1 || created.single.bindingIssue != null) {
    throw const FormatException('Created layer changed unrelated ownership or root counts.');
  }
  return result;
}
