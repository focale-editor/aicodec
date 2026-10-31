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

/// Reserves qualified XML artwork identities without merging equal source owners.
Set<String> _nativeIdentityNames(AiNativeStructure structure) => {
  for (final AiNativeObjectIdentifier identifier in structure.identifiers)
    if (identifier.kind == .xmlArt) latin1.decode(identifier.bytes),
};

/// Encodes one fresh identity and replaces only its source-owned string token.
AiSourceEdit _nativeIdentityEdit(AiNativeObjectIdentifier identifier, List<int> identifierBytes, Set<String> reserved, int maxBytes) {
  final List<int> encoded = _nativeLiteralString(identifierBytes, maxBytes);
  if (identifierBytes.any((byte) => byte > 127) || !RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(latin1.decode(identifierBytes))) {
    throw ArgumentError('New artwork identifiers require a nonempty portable XML name.');
  }
  if (!reserved.add(latin1.decode(identifierBytes))) {
    throw ArgumentError('The new artwork identifier already belongs to the native source or this transaction.');
  }
  final AiNativeItem value = identifier.field.entry.container!.entries.single.items.single;
  return AiSourceEdit(start: value.start, end: value.end, bytes: encoded);
}

/// Enumerates the complete selected object trees without merging equal identities.
List<AiNativeObject> _selectedNativeObjects(AiNativeDrawing drawing, List<AiNativeItem> sources) => [
  for (final AiNativeItem source in sources) ..._pathInterval(drawing._objects.objects, source.start, source.end, (object) => object.start),
];

/// Requires fresh identities for every identified object in copied subtrees.
List<AiSourceEdit> _objectCopyEdits(AiNativeDrawing drawing, List<AiNativeItem> sources, Map<AiNativeItem, List<int>> identifiers, {Set<String>? reserved, int? maxBytes}) {
  final List<AiNativeObject> objects = _selectedNativeObjects(drawing, sources).where((object) => object.identifier != null).toList();
  final Set<AiNativeItem> expected = objects.map((object) => object.source).toSet();
  if (identifiers.length != expected.length || identifiers.keys.any((source) => !expected.contains(source))) {
    throw ArgumentError('Copies require fresh identifiers for exactly their identified source objects and descendants.');
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
void _nativeRemovalReferences(AiNativeLayers model, List<AiNativeObjectIdentifier> identifiers, Map<int, AiNativeLayer> headers) {
  if (identifiers.isEmpty) {
    return;
  }
  final Set<AiNativeContainer> dictionaries = {
    for (final AiNativeLayer layer in model.layers)
      if (layer.dictionary != null && layer.bindingIssue == null) layer.dictionary!,
    for (final AiNativeObject object in model.drawing._objects.objects)
      if (object.dictionary != null && object.bindingIssue == null) object.dictionary!,
  };
  if (model.drawing.records.roots.any((record) => !dictionaries.contains(record))) {
    throw UnsupportedError('Deleting identified artwork requires qualification of native document, resource and opaque reference owners.');
  }
  final Map<String, int> occurrences = {};
  for (final AiNativeObjectIdentifier identifier in model.structure.identifiers.where((identifier) => identifier.kind == .xmlArt)) {
    occurrences.update(latin1.decode(identifier.bytes), (count) => count + 1, ifAbsent: () => 1);
  }
  if (identifiers.any((identifier) => occurrences[latin1.decode(identifier.bytes)] != 1)) {
    throw UnsupportedError('Deleting artwork requires an unambiguous native identity.');
  }
  final AiProgram program = model.drawing.records.program;
  _layerInterval(model, program.bodyStart, program.bodyEnd, headers);
  final Set<int> declarations = {if (model.rootCountHeader != null) model.rootCountHeader!.token.start, ...model.viewComments.map((token) => token.start)};
  const Set<String> markers = {'%%EndComments', '%%BeginProlog', '%%EndProlog', '%%BeginSetup', '%%EndSetup', '%%PageTrailer', '%%Trailer', '%%EOF'};
  const Set<String> fields = {'%%Creator', '%%Title', '%%For', '%%CreationDate', '%%BoundingBox', '%%HiResBoundingBox', '%%Pages', '%%Orientation', '%%PageOrder', '%%DocumentData', '%%LanguageLevel'};
  final RegExp native = RegExp(r'^%{1,2}AI');
  for (final AiToken token in model.drawing.records._projection.tokens) {
    if (token.start >= program.bodyStart && token.start < program.bodyEnd) {
      continue;
    }
    final bool unknown = native.hasMatch(token.lexeme) || token.lexeme.startsWith('%%') && !markers.contains(token.lexeme) && !fields.contains(token.lexeme.split(':').first);
    if (token.kind != .comment || !declarations.contains(token.start) && unknown) {
      throw UnsupportedError('Deleting identified artwork requires a declarative source without unqualified external reference sections.');
    }
  }
}
