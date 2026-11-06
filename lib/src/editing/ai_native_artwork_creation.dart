part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Resolves appearance boundaries before admitting independent following artwork.
List<AiNativeAppearanceArtwork> _nativeCreationAppearances(AiNativeDrawing drawing) => _nativeBodyAppearanceArtwork(AiNativeAppearances.decode(structure: drawing._objects.structure));

/// Finds the latest complete neutral or appearance owner before an insertion.
int _nativeCreationBoundary(AiNativeDrawing drawing, int position, List<AiNativeAppearanceArtwork> appearances) => [
  drawing.records.program.bodyStart,
  ..._nativeNeutralArtwork(drawing).where((span) => span.end <= position).map((span) => span.end),
  ...appearances.where((owner) => owner.end <= position).map((owner) => owner.end),
].reduce(max);

/// Qualifies one append boundary without requiring an existing sibling.
int _nativeCreationPosition(AiNativeDrawing drawing, AiNativeGroup? parent, AiLayer? layer) {
  if (parent != null && layer != null) {
    throw ArgumentError('New artwork requires at most one group or layer parent.');
  }
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  if (!layers.rootCountMatches) {
    throw const FormatException('The declared native root-layer count disagrees with its owners.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final AiNativeStructureNode? node = parent != null
      ? structure.nodeFor(parent)
      : layer != null
      ? structure.nodeFor(layer)
      : null;
  _sourceMovementParents(drawing, _artworkParents(structure, node));
  return parent?.closing.start ?? layer?.end.start ?? drawing.records.program.bodyEnd;
}

/// Writes only explicit ordinary-object names and fresh native identities.
List<int> _createdNativeMetadata(AiNativeDrawing drawing, List<int>? nameBytes, List<int>? identifierBytes, String newline) {
  if (nameBytes == null && identifierBytes == null) {
    return [];
  }
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  final List<int>? name = nameBytes == null ? null : _nativeLiteralString(nameBytes, maximum);
  final List<int>? identifier = identifierBytes == null ? null : _newNativeIdentity(identifierBytes, _nativeIdentityNames(drawing._objects.structure), maximum - (name?.length ?? 0));
  final String value =
      '%_/ArtDictionary :$newline'
      '${identifier == null ? '' : '%_/XMLUID : ${latin1.decode(identifier)} ; (AI10_ArtUID) ,$newline'}'
      '${name == null ? '' : '%_${latin1.decode(name)} /String (AIArtName) ,$newline'}'
      '%_;$newline';
  if (value.length > maximum) {
    throw const AiLimitException(message: 'Created artwork metadata exceeds the native output limit.');
  }
  return latin1.encode(value);
}

/// Appends an empty ordinary owner without changing any persistent drawing state.
AiNativeDrawing _createNativeGroup(
  AiNativeDrawing drawing,
  AiNativeGroup? parent,
  AiLayer? layer,
  List<int>? nameBytes,
  List<int>? identifierBytes,
  bool inheritParentFlags,
  bool? hidden,
  bool? locked,
) {
  final int position = _nativeCreationPosition(drawing, parent, layer);
  _nativeGroupingFlags(drawing, [position], inheritParentFlags);
  final AiProgram program = drawing.records.program;
  final int lineEnd = program.bytes.indexOf(10);
  final String newline = lineEnd > 0 && program.bytes[lineEnd - 1] == 13 ? '\r\n' : '\n';
  final List<int> bytes = [...latin1.encode('${newline}u${newline}U$newline'), ..._createdNativeMetadata(drawing, nameBytes, identifierBytes, newline)];
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [AiSourceEdit(start: position, end: position, bytes: bytes)],
    paths: drawing.paths.length,
    groups: drawing.groups.length + 1,
    liveShapes: drawing.liveShapes.length,
  );
  final AiNativeGroup created = result.groups.singleWhere((group) => group.start == position + newline.length);
  final AiNativeObject object = _ordinaryObject(result, created);
  if (object.start != created.start || object.end > position + bytes.length) {
    throw UnsupportedError('Creating a group cannot capture existing native prefixes or metadata.');
  }
  final AiNativeStructure structure = result._objects.structure;
  _sourceMovementParents(result, _artworkParents(structure, structure.nodeFor(created)));
  return hidden == null && locked == null ? result : _updateNativeGroupAttributes(result, created, hidden, locked);
}
