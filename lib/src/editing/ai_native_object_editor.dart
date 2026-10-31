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
List<AiSourceEdit> _objectCopyEdits(AiNativeDrawing drawing, List<AiNativeItem> sources, Map<AiNativeItem, List<int>> identifiers) {
  final List<AiNativeObject> objects = _selectedNativeObjects(drawing, sources).where((object) => object.identifier != null).toList();
  final Set<AiNativeItem> expected = objects.map((object) => object.source).toSet();
  if (identifiers.length != expected.length || identifiers.keys.any((source) => !expected.contains(source))) {
    throw ArgumentError('Copies require fresh identifiers for exactly their identified source objects and descendants.');
  }
  final Set<String> reserved = _nativeIdentityNames(drawing._objects.structure);
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeObject object in objects) {
    final AiSourceEdit edit = _nativeIdentityEdit(object.identifier!, identifiers[object.source]!, reserved, remaining);
    edits.add(edit);
    remaining -= edit.bytes.length;
  }
  return edits;
}

/// Retains identified objects until every possible reference owner is qualified.
void _ordinaryObjectRemoval(AiNativeDrawing drawing, List<AiNativeItem> sources) {
  if (_selectedNativeObjects(drawing, sources).any((object) => object.identifier != null)) {
    throw UnsupportedError('Deleting identified artwork requires qualification of all native reference owners.');
  }
}
