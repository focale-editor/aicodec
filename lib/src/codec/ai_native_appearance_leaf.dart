part of 'package:aikit/src/model/ai_native_records.dart';

/// Recognizes one complete native payload without accepting opaque commands.
AiNativeAppearanceLeaf? _readNativeAppearanceLeaf(AiNativeDrawing drawing, AiNativeGroup group) => drawing._appearanceLeaves.putIfAbsent(group, () {
  try {
    return _inspectNativeAppearanceLeaf(drawing, group);
  } on UnsupportedError {
    // A nonmatching wrapper may still use another existing native contract.
    // Callers must qualify its original grammar; this grants no editable leaf.
    return null;
  }
});

/// Qualifies complete payload ownership once in each immutable drawing snapshot.
AiNativeAppearanceLeaf? _inspectNativeAppearanceLeaf(AiNativeDrawing drawing, AiNativeGroup group) {
  if (!drawing.groups.contains(group)) {
    throw ArgumentError('Appearance leaves require a group from the current drawing.');
  }
  if (group.opening.operator != 'u' || group.children.any((child) => child is AiNativeGroup)) {
    return null;
  }
  final List<AiNativeItem> items = _pathInterval(drawing.items, group.opening.end, group.closing.start, (item) => item.start).toList();
  final bool imagePayload = items.any((item) => item is AiNativeRaster || item is AiNativeInstruction && item.operator == 'XI');
  final bool meshPayload = items.any((item) => item is AiNativeInstruction && item.operator == 'X!' && item.operands.singleOrNull?.lexeme == '/Mesh');
  final List<AiNativeRaster> rasters = (imagePayload ? drawing._appearanceRasters : const <AiNativeRaster>[]).where((image) => image.start > group.start && image.end < group.end).toList();
  final List<AiNativeMesh> meshes = (meshPayload ? drawing._appearanceMeshes : const <AiNativeMesh>[]).where((mesh) => mesh.start > group.start && mesh.end < group.end).toList();
  final List<AiLiveShape> shapes = drawing.liveShapes.where((shape) => shape.path != null && shape.path!.start > group.start && shape.dictionary.end < group.end).toList();
  final List<AiNativeContainer> texts = items.whereType<AiNativeContainer>().where((record) => record.type == 'AI11Text').toList();
  final List<AiNativeContainer> symbols = items.whereType<AiNativeContainer>().where((record) => record.type == 'SymbolInstance').toList();
  if (symbols.isEmpty && rasters.isEmpty && meshes.isEmpty && shapes.isEmpty && texts.isEmpty) {
    return null;
  }
  if (rasters.length + meshes.length + shapes.length + texts.length + symbols.length != 1 || group.paths.length != shapes.length) {
    throw UnsupportedError('A native appearance leaf requires exactly one complete payload.');
  }
  final AiNativeRaster? raster = rasters.singleOrNull;
  final AiNativeMesh? mesh = meshes.singleOrNull;
  final AiLiveShape? shape = shapes.singleOrNull;
  final AiNativeContainer? text = texts.singleOrNull;
  final AiNativeContainer? symbol = symbols.singleOrNull;
  final int start;
  final int end;
  if (raster != null) {
    _artboardResourceRaster(drawing.records, raster);
    if (raster.imageMask || raster.dictionary != null) {
      throw UnsupportedError('Appearance images require process pixels and wrapper-owned metadata.');
    }
    start = raster.start;
    end = raster.end;
  } else if (mesh != null) {
    AiNativeMeshDefinition.fromSource(mesh: mesh);
    start = mesh.start;
    end = mesh.end;
  } else if (shape != null) {
    if (_directNativeShapeIssue(shape, appearanceLeaf: true) case final String issue) {
      throw UnsupportedError(issue);
    }
    final AiNativeShapeParameters parameters = AiNativeShapeParameters.fromShape(shape: shape);
    _nativeShapeAuthoring(parameters, shape.path!.closed, null);
    if (shape.dictionary.entries.any((entry) => !const {'ai::LiveShape', 'BBAccumRotation'}.contains(entry.key))) {
      throw UnsupportedError('Appearance shapes require wrapper-owned identities and masks.');
    }
    start = shape.dictionary.start;
    end = shape.dictionary.end;
  } else if (symbol != null) {
    _nativeSymbolDefinition(symbol);
    start = symbol.start;
    end = symbol.end;
  } else {
    if (text!.hasBinary ||
        text.notRecorded ||
        text.entries.map((entry) => entry.key).toSet().length != text.entries.length ||
        text.entries.any((entry) => entry.type != null || entry.isQualifier || !const {'FreeUndo', 'StoryIndex', 'FrameIndex', 'TextAntialiasing', 'ConfiningPath'}.contains(entry.key))) {
      throw UnsupportedError('Appearance text has unqualified drawing-reference fields.');
    }
    for (final String key in ['FreeUndo', 'StoryIndex', 'FrameIndex', if (text['TextAntialiasing'] != null) 'TextAntialiasing']) {
      _artboardTextRecordIndex(text, key);
    }
    if (text['ConfiningPath']?.container case final AiNativeContainer confinement) {
      _artboardTextConfinement(AiNativeArt.decode(records: drawing.records, record: confinement));
    }
    if (text['FreeUndo']?.number != 0) {
      throw UnsupportedError('Appearance text requires explicit story and frame references.');
    }
    start = text.start;
    end = text.end;
  }
  if ((raster?.instruction.isPrivate ?? mesh?.isPrivate ?? shape?.path?.isPrivate ?? drawing.records._projection.isPrivate((text ?? symbol)!.start)) != group.opening.isPrivate) {
    throw UnsupportedError('A leaf payload must share its wrapper representation.');
  }
  final List<AiNativeInstruction> commands = [];
  bool termination = false;
  for (final AiNativeItem item in items) {
    if (item.start >= start && item.end <= end) {
      if (raster != null && item is AiNativeInstruction) {
        commands.add(item);
      }
      continue;
    }
    if (text != null && item is AiNativeContainer && item.type == 'ArtDictionary' && item.start >= text.end) {
      _artboardTextMetadata(item);
      continue;
    }
    if (item is! AiNativeInstruction || item.isPrivate != group.opening.isPrivate) {
      throw UnsupportedError('Appearance payloads cannot contain unrelated records or mixed representations.');
    }
    if (shape != null && (shape.path!.geometry.contains(item) || identical(item, shape.path!.paint) || item.operator == 'As')) {
      if (item.operator == 'As') {
        _nativeAppearanceCount(shape.path!, item);
      }
      commands.add(item);
    } else if (item.operator == 'N' && item.start >= end && item.operands.isEmpty && !termination && text == null && shape == null) {
      termination = true;
    } else if (_nativeArtworkStateKey(item) != null || item.operator == 'Xd' && item.numbers?.length == 2 && item.numbers!.every((value) => value == 0 || value == 1)) {
      commands.add(item);
    } else {
      throw UnsupportedError('Appearance payloads contain an unqualified command ${item.operator}.');
    }
  }
  final int paintStart = raster?.instruction.start ?? mesh?.start ?? shape?.path?.start ?? (text ?? symbol)!.start;
  final Map<String, AiNativeInstruction> inputs = {
    for (final AiNativeInstruction command in commands.where((command) => command.start < paintStart))
      if (_nativeArtworkStateKey(command) case final String key) key: command,
  };
  final AiNativeTransparency? blend = inputs['Xy'] == null ? null : AiNativeTransparency.decode(instruction: inputs['Xy']!);
  if (blend == null ||
      blend.opacity != 1 ||
      blend.blendMode != .normal ||
      blend.isolated ||
      blend.knockout != .off ||
      blend.alphaIsShape ||
      inputs['A']?.numbers?.singleOrNull != 0 ||
      inputs['Xw']?.numbers?.singleOrNull != 0 ||
      shape == null && (inputs['O']?.numbers?.singleOrNull != 0 || inputs['R']?.numbers?.singleOrNull != 0)) {
    throw UnsupportedError('Private payload blending and visibility belong to their explicit wrapper.');
  }
  if (mesh != null || text != null || symbol != null) {
    commands.add(
      AiNativeInstruction._(
        token: AiToken(
          kind: .executableName,
          start: start,
          end: end,
          lexeme: mesh != null
              ? 'aikit:mesh'
              : symbol != null
              ? 'aikit:symbol'
              : 'aikit:text',
        ),
        operands: [],
        isPrivate: group.opening.isPrivate,
      ),
    );
    commands.sort((first, second) => first.start.compareTo(second.start));
  }
  return AiNativeAppearanceLeaf._(group: group, raster: raster, mesh: mesh, shape: shape, text: text, symbol: symbol, commands: commands);
}

/// Validates static literal instance fields without guessing its coordinate basis.
AiNativeAppearanceSymbolDefinition _nativeSymbolDefinition(AiNativeContainer record) {
  if (record.hasBinary ||
      record.notRecorded ||
      record.entries.length != 2 ||
      record.entries.any((entry) => entry.isQualifier || entry.type != null || !const {'SymbolRef', 'RTransformMatrix'}.contains(entry.key)) ||
      record.values('SymbolRef').length != 1 ||
      record.values('RTransformMatrix').length != 1) {
    throw UnsupportedError('Static symbol instances require only one literal reference and relative matrix.');
  }
  final AiNativeEntry reference = record['SymbolRef']!;
  final List<int>? name = reference.items.length == 1 ? reference.stringBytes : null;
  final List<double>? matrix = record['RTransformMatrix']!.numbers;
  if (name == null || matrix == null) {
    throw UnsupportedError('Symbol references and matrices must be literal.');
  }
  return AiNativeAppearanceSymbolDefinition(nameBytes: name, relativeTransform: matrix);
}
