part of 'package:aikit/src/model/ai_native_records.dart';

/// Encodes caller-supplied byte strings after bounding their escaped output size.
List<int> _nativeLiteralString(List<int> value, int maxBytes) {
  if (value.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('A native name or identifier must contain bytes.');
  }
  if (value.length * 4 + 2 > maxBytes) {
    throw const AiLimitException(message: 'Escaped native strings exceed the native byte limit.');
  }
  return latin1.encode('(${value.map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()})');
}

/// Reserves every saved XML wrapper, including opaque owners and both branches.
///
/// Unknown owners may declare or refer to a name. Allocating that name would
/// collide with an identity or capture a reference, so neither can be reused.
Set<String> _nativeIdentityNames(AiNativeStructure structure) {
  final Set<String> result = {};
  for (final AiNativeContainer record in structure.drawing.records.containers.where((record) => record.type == 'XMLUID')) {
    if (record.entries.length != 1 || record.entries.single.key != null || record.entries.single.type != null || record.entries.single.items.length != 1 || record.entries.single.stringBytes == null) {
      throw UnsupportedError('Allocating artwork identities requires a single string in every saved XMLUID wrapper.');
    }
    result.add(latin1.decode(record.entries.single.stringBytes!));
  }
  return result;
}

/// Encodes and reserves a fresh identity for one creation or copy transaction.
List<int> _newNativeIdentity(List<int> identifierBytes, Set<String> reserved, int maxBytes) {
  final List<int> encoded = _nativeLiteralString(identifierBytes, maxBytes);
  if (identifierBytes.any((byte) => byte > 127) || !RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(latin1.decode(identifierBytes))) {
    throw ArgumentError('New artwork identifiers require a nonempty portable XML name.');
  }
  if (!reserved.add(latin1.decode(identifierBytes))) {
    throw ArgumentError('The new artwork identifier already belongs to the native source or this transaction.');
  }
  return encoded;
}

/// Encodes one fresh identity and replaces only its source-owned string token.
AiSourceEdit _nativeIdentityEdit(AiNativeObjectIdentifier identifier, List<int> identifierBytes, Set<String> reserved, int maxBytes) {
  final List<int> encoded = _newNativeIdentity(identifierBytes, reserved, maxBytes);
  final AiNativeItem value = identifier.field.entry.container!.entries.single.items.single;
  return AiSourceEdit(start: value.start, end: value.end, bytes: encoded);
}

/// Enumerates the complete selected object trees without merging equal identities.
List<AiNativeObject> _selectedNativeObjects(AiNativeDrawing drawing, List<AiNativeItem> sources) => [
  for (final AiNativeItem source in sources) ..._pathInterval(drawing._objects.objects, source.start, source.end, (object) => object.source.start),
];

/// Requires fresh identities for every identified object in copied subtrees.
List<AiSourceEdit> _objectCopyEdits(AiNativeDrawing drawing, List<AiNativeItem> sources, Map<AiNativeItem, List<int>> identifiers, {Set<String>? reserved, int? maxBytes}) {
  final List<AiNativeObject> objects = _selectedNativeObjects(drawing, sources).where((object) => object.identifier != null).toList();
  final Set<AiNativeItem> expected = objects.map((object) => object.source).toSet();
  if (identifiers.length != expected.length || identifiers.keys.any((source) => !expected.contains(source))) {
    throw ArgumentError('Copies require fresh identifiers for exactly their identified source objects and descendants.');
  }
  if (objects.isEmpty) {
    return [];
  }
  final Set<String> names = reserved ?? _nativeIdentityNames(drawing._objects.structure);
  final List<AiSourceEdit> edits = [];
  int remaining = maxBytes ?? drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeObject object in objects) {
    final AiSourceEdit edit = _nativeIdentityEdit(object.identifier!, identifiers[object.source]!, names, remaining);
    edits.add(edit);
    remaining -= edit.bytes.length;
  }
  return edits;
}

/// Validates every deleted object identity against the complete reference scope.
void _ordinaryObjectRemoval(AiNativeDrawing drawing, List<AiNativeItem> sources) {
  final List<AiNativeObjectIdentifier> identifiers = [for (final AiNativeObject object in _selectedNativeObjects(drawing, sources)) ?object.identifier];
  if (identifiers.isNotEmpty) {
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
    _nativeRemovalReferences(layers, identifiers, _layerHeaderItems(layers));
  }
}

/// Refuses identity deletion unless all possible native reference owners qualify.
void _nativeRemovalReferences(AiNativeLayers model, List<AiNativeObjectIdentifier> identifiers, Map<int, AiNativeLayer> headers, {Set<AiNativeContainer>? bodyDictionaries}) {
  if (identifiers.isEmpty) {
    return;
  }
  _nativeReferenceScope(model, headers, bodyDictionaries: bodyDictionaries);
  final Map<String, int> occurrences = {};
  for (final AiNativeObjectIdentifier identifier in model.structure.identifiers.where((identifier) => identifier.kind == .xmlArt)) {
    occurrences.update(latin1.decode(identifier.bytes), (count) => count + 1, ifAbsent: () => 1);
  }
  if (identifiers.any((identifier) => occurrences[latin1.decode(identifier.bytes)] != 1)) {
    throw UnsupportedError('Deleting artwork requires an unambiguous native identity.');
  }
}

/// Qualifies references, optionally reusing an already checked immutable body.
///
/// Appearance edits may supply fully inspected resource artwork and brushes,
/// whose identities stay unchanged. Identity deletion retains its stricter
/// resource boundary by omitting those scopes.
void _nativeReferenceScope(
  AiNativeLayers model,
  Map<int, AiNativeLayer> headers, {
  Set<AiNativeContainer>? bodyDictionaries,
  _ArtboardResourceScope? retainedResources,
  _ArtboardBrushScope? retainedBrushes,
}) {
  final Set<AiNativeContainer> dictionaries = {...bodyDictionaries ?? _nativeReferenceBody(model, headers), ...?retainedResources?.objects};
  final List<_NativeFontEncoding> fonts = [];
  final List<({int start, int end})> independent = _referenceGradientRanges(model, fontDeclarations: fonts)
    ..addAll(_artboardFontSetupRanges(model, fonts))
    ..addAll(_artboardSvgFilterRanges(model))
    ..addAll(retainedResources?.ranges ?? [])
    ..addAll(retainedBrushes?.ranges ?? [])
    ..addAll(_artboardSetupRanges(model, patternNames: retainedResources?.patterns ?? {}, symbolNames: retainedResources?.symbols ?? {}))
    ..addAll(_artboardTextScope(model, requireEmpty: true).ranges);
  final Map<int, AiNativeResourceUse> references = {for (final AiNativeResourceUse use in model.structure.resourceUses) use.instruction.start: use};
  for (final AiNativeContainer record in model.drawing.records.roots.where((record) => !dictionaries.contains(record))) {
    if (record.type == 'KnownStyle') {
      _artboardRetainedStyle(model, record, references, retainedResources?.patterns ?? {}, retainedBrushes?.names ?? {});
    } else if (record.type == 'Document') {
      _referenceDocument(model, record);
    } else if (record.type == 'SVGFilter') {
      // Complete filter declarations contain only filter-local dependencies.
      continue;
    } else if (const {'AI11TextDocument', 'AI11UndoFreeTextDocument'}.contains(record.type)) {
      // Both snapshots were checked above; neither owns stories or frames.
    } else {
      throw UnsupportedError('Native structural edits require qualification of document, resource and opaque reference owners.');
    }
    independent.add((start: record.start, end: record.end));
  }
  _referenceProgram(model, independent..sort((first, second) => first.start.compareTo(second.start)));
}

/// Returns owned artwork dictionaries after checking ordinary and paired bodies.
Set<AiNativeContainer> _nativeReferenceBody(
  AiNativeLayers model,
  Map<int, AiNativeLayer> headers, {
  void Function(AiNativeLayers, int, int, Map<int, AiNativeLayer>) inspect = _referenceArtworkInterval,
  bool qualifyShapeNeighbors = true,
}) {
  final List<_NativeShapeBundle> shapes = [
    for (final AiLiveShape shape in model.drawing.liveShapes.where((shape) => shape.appearanceGroup != null || shape.path?.isPrivate == true))
      _shapeBundle(model.drawing, shape, model.structure, qualifyNeighbors: qualifyShapeNeighbors),
  ];
  final Set<AiNativeContainer> dictionaries = {
    for (final _NativeShapeBundle bundle in shapes) ...[bundle.shape.dictionary, bundle.shape.appearanceDictionary!, ...bundle.shape.alternativeDictionaries],
    for (final AiNativeLayer layer in model.layers)
      if (layer.dictionary != null && layer.bindingIssue == null) layer.dictionary!,
    for (final AiNativeObject object in model.drawing._objects.objects)
      if (object.dictionary != null && object.bindingIssue == null) object.dictionary!,
  };
  final AiProgram program = model.drawing.records.program;
  int position = program.bodyStart;
  for (final _NativeShapeBundle bundle in shapes) {
    inspect(model, position, bundle.start, headers);
    position = bundle.shape.end;
  }
  inspect(model, position, program.bodyEnd, headers);
  return dictionaries;
}
