part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Complete authoring/printing ownership and declarative state dependencies.
final class _NativeShapeBundle {
  /// Source shape whose geometry, alternatives and shared style stay together.
  final AiLiveShape shape;

  /// First owned byte, including an optional outer panel-expansion instruction.
  final int start;

  /// Declarative commands preceding the final known-style application.
  final List<AiNativeInstruction> commands;

  /// Persistent state potentially assigned by the retained appearance style.
  final Set<String> styleWrites;

  /// Attributes a style part may inherit before assigning its own values.
  final Set<String> styleReads;

  /// Retains a qualified complete bundle without moving any source bytes.
  _NativeShapeBundle({required this.shape, required this.start, required this.commands, required this.styleWrites, required this.styleReads});
}

/// Validates metadata without admitting unknown references into copied objects.
void _shapeCopyDictionary(AiNativeDrawing drawing, AiLiveShape shape, AiNativeContainer dictionary, {void Function(AiNativeContainer)? opacityMask}) {
  if (!_shapeParameters.containsKey(shape.handler)) {
    throw UnsupportedError('Shape copies require a known native parameter schema.');
  }
  _LiveShapeEditor(drawing: drawing, shapes: [shape])._checkDictionary(dictionary, shape.handler, opacityMasks: opacityMask != null);
  if (dictionary.entries.any((entry) => entry.key == 'Adobe_AI9_ArtStyle_Dictionary') || dictionary.entries.map((entry) => entry.key).toSet().length != dictionary.entries.length) {
    throw UnsupportedError('Shape copies require qualified distinct metadata fields.');
  }
  if (dictionary['AI9_Mask'] case final AiNativeEntry field) {
    opacityMask!(_referenceRecord(field, 'Mask'));
  }
  final AiNativeContainer? definition = dictionary['ai::LiveShape']?.container;
  if (definition != null) {
    final AiNativeContainer? parameters = definition['ai::LiveShape::Params']?.container;
    if (definition.type != 'Dictionary' ||
        parameters?.type != 'Dictionary' ||
        definition['ai::LiveShape::HandlerName']?.type != 'UnicodeString' ||
        definition.entries.map((entry) => entry.key).toSet().length != definition.entries.length ||
        parameters!.entries.map((entry) => entry.key).toSet().length != parameters.entries.length) {
      throw UnsupportedError('Shape copies require typed native parameter owners.');
    }
    for (final AiNativeEntry field in parameters.entries.where((field) => !field.isQualifier)) {
      final String name = field.key!.substring(shape.handler.length + 2);
      final String type = _nativeShapeParameterType(shape.handler, name);
      if (field.type != type || (type == 'UnicodeString' ? field.stringBytes == null : field.number == null || field.number!.abs() > 9007199254740991)) {
        throw UnsupportedError('Shape copies require scalar native parameters without hidden references.');
      }
    }
  }
  final AiNativeEntry? rotation = dictionary['BBAccumRotation'];
  if (rotation != null && (rotation.type != 'String' || double.tryParse(rotation.text() ?? '')?.isFinite != true)) {
    throw UnsupportedError('Shape copies require a finite accumulated rotation.');
  }
}

/// Qualifies a complete source bundle rather than its individual private paths.
///
/// Callers opting out must qualify affected neighbors and enclosing effects separately.
/// Resource-local drawings supply their complete document for global style/layer
/// validation while geometry and lexical ownership remain local.
_NativeShapeBundle _shapeBundle(
  AiNativeDrawing drawing,
  AiLiveShape shape,
  AiNativeStructure structure, {
  bool qualifyNeighbors = true,
  bool clipping = false,
  AiNativeDrawing? document,
  Set<String> patterns = const {},
  void Function(AiNativeContainer)? opacityMask,
}) {
  final AiNativeGroup group = _printingShapeGroup(drawing, shape, clipping: clipping);
  if (!_shapeParameters.containsKey(shape.handler)) {
    throw UnsupportedError('Shape copies require a known native shape handler.');
  }
  _printingState(drawing, group, clipping: clipping);
  _printingPointCounts(drawing, group);
  final AiNativeObject object = drawing._objects.forSource(group);
  final AiNativeInstruction? panel = object.expansion;
  final int start = panel?.start ?? shape.start;
  final AiNativeStructureNode owner = structure.nodeFor(group);
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: document ?? drawing);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  if (qualifyNeighbors) {
    int boundary = drawing.liveShapes.where((other) => other.isBound && other.end <= start).fold(drawing.records.program.bodyStart, (end, other) => max(end, other.end));
    for (int index = _pathOffset(drawing.items, start, (item) => item.start) - 1; index >= 0 && drawing.items[index].end > boundary; index--) {
      final AiNativeItem item = drawing.items[index];
      if (_ordinaryObjectAttachment(drawing, item)) {
        boundary = item.end;
        break;
      }
      if (headers[item.start] case final AiNativeLayer layer when layer.bindingIssue == null && item.start == layer.source.end.start) {
        boundary = layer.end;
        break;
      }
      if (headers[item.start] case final AiNativeLayer layer when layer.bindingIssue == null && item.start != layer.source.begin.start && item.start != layer.source.end.start) {
        continue;
      }
      if (item is! AiNativeInstruction) {
        throw UnsupportedError('The copied shape has unresolved preceding metadata.');
      }
      if (_nativePaint.contains(item.operator) || const {'u', 'U', 'Lb', 'LB'}.contains(item.operator)) {
        boundary = item.end;
        break;
      }
      if (_nativeArtworkStateKey(item) == null) {
        throw UnsupportedError('The copied shape has an unqualified prefix ${item.operator}.');
      }
    }
    _ordinaryGroupMetadata(drawing, boundary, start);
  }
  if (structure.versions.memberships(start: start, end: shape.end).isNotEmpty || structure.nodeFor(shape.path!).parentIndex != owner.parentIndex) {
    throw UnsupportedError('Shape copies require one unconditional lexical owner.');
  }
  for (final AiNativeStructureNode parent in _artworkParents(structure, structure.parentOf(owner))) {
    if (parent.versions.isNotEmpty || !const {AiNativeStructureKind.layer, AiNativeStructureKind.group}.contains(parent.kind) && !(clipping && parent.kind == .clip)) {
      throw UnsupportedError('Shape copies cannot cross unresolved enclosing owners.');
    }
    if (parent.source case final AiNativeGroup group) {
      if (group.opening.isPrivate) {
        throw UnsupportedError('A shape copy cannot inherit a private enclosing group.');
      }
      if (qualifyNeighbors) {
        _ordinaryObjectFollowing(drawing, group, clipping: clipping);
      }
    } else if (parent.source case final AiLayer layer) {
      _qualifiedLayerHeader(layers, layers.layerFor(layer));
    }
  }
  if (shape.path!.geometry.skip(1).any((command) => command.operator == 'm')) {
    throw UnsupportedError('A copied shape requires one authoritative contour.');
  }
  final Set<AiNativeContainer> dictionaries = {shape.appearanceDictionary!, shape.dictionary, ...shape.alternativeDictionaries};
  final List<AiNativeContainer> masks = [];
  for (final AiNativeContainer dictionary in dictionaries) {
    _shapeCopyDictionary(
      drawing,
      shape,
      dictionary,
      opacityMask: opacityMask == null
          ? null
          : (mask) {
              if (!identical(dictionary, shape.dictionary)) {
                throw UnsupportedError('Live-shape masks require authoritative metadata without printing or alternate mask copies.');
              }
              opacityMask(mask);
              masks.add(mask);
            },
    );
  }
  final Set<int> versionComments = {
    for (final AiNativeVersionBlock block in structure.versions.blocks.where((block) => block.start >= shape.path!.end && block.end < shape.end)) ...[
      block.opening.start,
      if (block.alternate != null) block.alternate!.start,
      block.closing.start,
    ],
  };
  if (_pathInterval(drawing.records._projection.tokens, start, shape.end, (token) => token.start).any(
    (token) =>
        !masks.any((mask) => token.start >= mask.start && token.end <= mask.end) &&
        (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%%') || token.lexeme.startsWith('%AI')) && !versionComments.contains(token.start)),
  )) {
    throw UnsupportedError('Shape copies require ownership of all local comments and payloads.');
  }
  final List<AiNativeInstruction> commands = [];
  bool authoring = false;
  int markers = 0;
  bool counted = false;
  final Set<AiNativeInstruction> privatePath = {...shape.path!.geometry, shape.path!.paint};
  for (final AiNativeItem item in _pathInterval(drawing.items, start, shape.end, (item) => item.start)) {
    if (item.start >= group.start && item.end <= group.end) {
      commands.add(item as AiNativeInstruction);
      continue;
    }
    if (item is AiNativeContainer && dictionaries.contains(item) || item is AiNativeVersionComment && versionComments.contains(item.start)) {
      continue;
    }
    if (item is! AiNativeInstruction) {
      throw UnsupportedError('The copied shape contains an unresolved native owner.');
    }
    if (identical(item, panel)) {
      if (item.isPrivate || item.numbers?.length != 1 || !const {0, 1}.contains(item.numbers!.single) || !_sameNativeObjectOwner(owner, structure.nodeFor(item))) {
        throw UnsupportedError('The copied shape has an unresolved panel flag.');
      }
    } else if (_marker(item, 6) && item.start < shape.path!.start && !authoring) {
      if (item.isPrivate || aiStringBytes(item.operands.last).isNotEmpty) {
        throw UnsupportedError('The copied shape has an unresolved printing-style boundary.');
      }
      authoring = true;
      markers++;
    } else if (_marker(item, 1) && item.end == shape.end && !item.isPrivate && authoring) {
      markers++;
    } else if (privatePath.contains(item)) {
      if (!authoring || !item.isPrivate) {
        throw UnsupportedError('The copied shape has ambiguous private geometry.');
      }
    } else if (item.operator == 'Xd' && !authoring && !item.isPrivate && item.numbers?.length == 2 && item.numbers!.every((value) => value == 0)) {
      // Retain the observed default blend flags before their owned XW boundary.
    } else if (item.operator == 'As' && authoring && item.isPrivate && item.end < shape.path!.start) {
      final List<double> first = shape.path!.geometry.first.numbers!;
      final List<double> last = shape.path!.geometry.last.numbers!;
      if (counted ||
          item.numbers?.length != 1 ||
          item.numbers!.single != shape.path!.geometry.length - (shape.path!.closed ? 1 : 0) ||
          shape.path!.closed && (first[0] != last[last.length - 2] || first[1] != last.last)) {
        throw UnsupportedError('The copied authoring point count disagrees with its path.');
      }
      counted = true;
    } else if (_nativeArtworkStateKey(item) == null || item.isPrivate != authoring || item.start >= shape.path!.start) {
      throw UnsupportedError('Shape copies have no ownership contract for ${item.operator}.');
    }
    commands.add(item);
  }
  if (markers != 2) {
    throw UnsupportedError('A copied shape requires exactly one printing/authoring style pair.');
  }
  final ({Set<String> reads, Set<String> writes}) style = _nativeLiteralStyleState(document ?? drawing, shape.style!, patterns: patterns);
  for (final AiNativeResourceUse use in structure.resourceUses.where(
    (use) => use.instruction.start >= start && use.instruction.end <= shape.end || use.instruction.start >= shape.style!.start && use.instruction.end <= shape.style!.end,
  )) {
    if (use.resolution != .resolved || use.candidates.single.versions.isNotEmpty) {
      throw UnsupportedError('Shape copies require uniquely resolved unconditional shared resources.');
    }
  }
  if (qualifyNeighbors) {
    _ordinaryPathFollowing(drawing.items, shape.end);
    final AiNativeInstruction? following = drawing.items
        .whereType<AiNativeInstruction>()
        .where((item) => item.start >= shape.end && const {'m', 'u', 'U', 'Lb', 'LB'}.contains(item.operator))
        .firstOrNull;
    final AiNativeLayer? layer = following == null ? null : headers[following.start];
    final int next = layer != null && layer.bindingIssue == null && following!.start == layer.source.begin.start ? layer.start : following?.start ?? drawing.records.program.bodyEnd;
    _ordinaryGroupMetadata(drawing, shape.end, next);
  }
  return _NativeShapeBundle(shape: shape, start: start, commands: commands, styleWrites: style.writes, styleReads: style.reads);
}

/// Qualifies distinct owned source bundles before changing any snapshot offsets.
List<_NativeShapeBundle> _selectedShapeBundles(AiNativeDrawing drawing, List<AiLiveShape> shapes) {
  if (shapes.isEmpty || shapes.toSet().length != shapes.length || shapes.any((shape) => !drawing.liveShapes.contains(shape))) {
    throw ArgumentError('Shape lifecycle edits require distinct owned source shapes.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final List<_NativeShapeBundle> bundles = shapes.map((shape) => _shapeBundle(drawing, shape, structure)).toList()..sort((first, second) => first.start.compareTo(second.start));
  if (bundles.indexed.any((entry) => entry.$1 > 0 && bundles[entry.$1 - 1].shape.end > entry.$2.start)) {
    throw ArgumentError('Selected shape bundles cannot overlap.');
  }
  return bundles;
}

/// Copies complete source bundles with fresh identities and unchanged resources.
AiNativeDrawing _duplicateNativeShapes(AiNativeDrawing drawing, List<AiLiveShape> shapes, Map<AiNativeContainer, List<int>> identifiers) {
  final List<_NativeShapeBundle> copies = _selectedShapeBundles(drawing, shapes);
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeObjectIdentifier> saved = structure.identifiers
      .where((identifier) => copies.any((copy) => identifier.field.owner.start >= copy.start && identifier.field.owner.end <= copy.shape.end))
      .toList();
  final Set<AiNativeContainer> expected = saved.map((identifier) => identifier.field.owner.source as AiNativeContainer).toSet();
  if (identifiers.length != expected.length || identifiers.keys.any((record) => !expected.contains(record)) || expected.length != saved.length) {
    throw ArgumentError('Shape copies require one fresh identifier for each identified metadata owner.');
  }
  if (saved.map((identifier) => latin1.decode(identifier.bytes)).toSet().length != saved.length) {
    throw UnsupportedError('Copying repeated saved identities requires an explicit alias contract.');
  }
  final Set<String> reserved = saved.isEmpty ? {} : _nativeIdentityNames(structure);
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  final List<AiSourceEdit> identityEdits = [];
  for (final AiNativeObjectIdentifier identifier in saved) {
    final AiSourceEdit edit = _nativeIdentityEdit(identifier, identifiers[identifier.field.owner.source]!, reserved, remaining);
    identityEdits.add(edit);
    remaining -= edit.bytes.length;
  }
  final List<AiSourceEdit> edits = [];
  final Map<int, _NativeShapeInputs> inputs = _shapeCopyInputs(drawing, copies.map((copy) => copy.start));
  for (final _NativeShapeBundle copy in copies) {
    final List<int> prefix = _shapeCopyPrefix(drawing, copy, inputs[copy.start]!, remaining - 1);
    final List<int> bytes = _nativeSourceSpans(drawing.records.program, [(start: copy.start, end: copy.shape.end)], remaining - prefix.length - 1, edits: identityEdits);
    edits.add(AiSourceEdit(start: copy.shape.end, end: copy.shape.end, bytes: [10, ...prefix, ...bytes]));
    remaining -= prefix.length + bytes.length + 1;
  }
  final AiNativeDrawing result = _pathLifecycleResult(
    drawing,
    edits,
    drawing.paths.length + shapes.fold(0, (count, shape) => count + shape.appearancePaths.length + 1),
    liveShapes: drawing.liveShapes.length + shapes.length,
  );
  final int groups = copies.fold(0, (count, copy) => count + drawing.groups.where((group) => group.start >= copy.start && group.end <= copy.shape.end).length);
  if (result.groups.length != drawing.groups.length + groups || result.records.program.layers.length != drawing.records.program.layers.length) {
    throw const FormatException('Shape copies changed unrelated native topology.');
  }
  return result;
}
