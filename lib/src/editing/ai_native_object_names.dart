part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Writes qualified display-name fields while preserving all other metadata.
List<AiSourceEdit> _nativeObjectNameEdits(AiNativeDrawing drawing, AiNativeObject object, List<int> value, int budget) {
  final List<int> encoded = _nativeLiteralString(value, budget);
  if (encoded.length * max(1, object.names.length) + (object.names.isEmpty ? 96 : object.names.length) > budget) {
    throw const AiLimitException(message: 'Native display names exceed the transaction byte limit.');
  }
  if (object.names.isNotEmpty) {
    return [
      for (final AiNativeEntry field in object.names)
        if (field.items.isEmpty)
          AiSourceEdit(start: field.typeToken!.start, end: field.typeToken!.start, bytes: [...encoded, 32])
        else ...[
          AiSourceEdit(start: field.items.first.start, end: field.items.first.end, bytes: encoded),
          for (final AiNativeItem fragment in field.items.skip(1)) AiSourceEdit(start: fragment.start, end: fragment.end, bytes: []),
        ],
    ];
  }
  final AiNativeContainer? dictionary = object.dictionary;
  final String literal = latin1.decode(encoded);
  if (dictionary == null) {
    return [AiSourceEdit(start: object.source.end, end: object.source.end, bytes: latin1.encode('\n%_/ArtDictionary :\n%_$literal /String (AIArtName) ,\n%_;\n'))];
  }
  final List<AiToken> tokens = drawing.records._projection.tokens;
  final int closingIndex = _pathOffset(tokens, dictionary.end, (token) => token.start) - 1;
  final AiToken closing = tokens[closingIndex];
  int previous = closingIndex - 1;
  while (previous >= 0 && tokens[previous].kind == .comment) {
    previous--;
  }
  final String separator = dictionary.entries.isNotEmpty && tokens[previous].lexeme != ',' ? ', ' : '';
  final String prefix = drawing.records._projection.isPrivate(closing.start) ? '%_' : '';
  return [AiSourceEdit(start: closing.start, end: closing.start, bytes: latin1.encode('$separator$literal /String (AIArtName) ,\n$prefix'))];
}

/// Replaces display-name literals without rewriting artwork or XML identities.
AiNativeDrawing _renameNativeObjects(AiNativeDrawing drawing, Map<AiNativeItem, List<int>> names) {
  if (names.isEmpty) {
    throw ArgumentError('Native object renaming requires at least one current artwork handle.');
  }
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final MapEntry<AiNativeItem, List<int>> requested in names.entries) {
    final AiNativeObject object = _ordinaryObject(drawing, requested.key);
    if (object.source is AiNativePath && (object.source as AiNativePath).isPrivate || object.source is AiNativeGroup && (object.source as AiNativeGroup).opening.isPrivate) {
      throw UnsupportedError('Private appearance names require their enclosing authoring contract.');
    }
    final List<AiSourceEdit> values = _nativeObjectNameEdits(drawing, object, requested.value, remaining);
    remaining -= values.fold(0, (sum, edit) => sum + edit.bytes.length);
    edits.addAll(values);
  }
  final AiNativeDrawing result = _groupLifecycleResult(drawing, edits, paths: drawing.paths.length, groups: drawing.groups.length);
  for (final MapEntry<AiNativeItem, List<int>> requested in names.entries) {
    final int index = drawing._objects.objects.indexOf(drawing._objects.forSource(requested.key));
    final AiNativeObject object = result._objects.objects[index];
    if (object.bindingIssue != null || object.names.isEmpty || object.names.any((field) => latin1.decode(field.stringBytes!) != latin1.decode(requested.value))) {
      throw const FormatException('Renamed native artwork lost its literal display-name ownership.');
    }
  }
  return result;
}

/// Renames private authoring objects through their qualified complete body owners.
AiNativeAppearances _renameNativeAppearanceObjects(AiNativeAppearances model, Map<AiNativeItem, List<int>> names, List<AiNativeAppearanceArtwork> artwork) {
  if (names.isEmpty) {
    throw ArgumentError('Private artwork renaming requires current authoring objects.');
  }
  final List<AiNativeAppearanceArtwork> owners = _selectedBodyAppearanceArtwork(model, artwork);
  if (owners.any((owner) => owner.liveShape != null)) {
    throw UnsupportedError('Live-shape names require their synchronized alternative metadata contract.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final Map<AiNativeItem, AiNativeAppearanceArtwork> targets = {
    for (final AiNativeAppearanceArtwork owner in owners)
      for (final AiNativeObject object in _pathInterval(drawing._objects.objects, owner.authoring.start, owner.authoring.end, (object) => object.source.start))
        if (object.source.end <= owner.authoring.end) object.source: owner,
  };
  if (names.keys.any((target) => !targets.containsKey(target)) || owners.any((owner) => !names.keys.any((target) => identical(targets[target], owner)))) {
    throw ArgumentError('Private names require exactly the complete owners of all selected authoring objects.');
  }
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final MapEntry<AiNativeItem, List<int>> entry in names.entries) {
    final AiNativeObject object = drawing._objects.forSource(entry.key);
    final List<AiSourceEdit> values = _nativeObjectNameEdits(drawing, object, entry.value, remaining);
    remaining -= values.fold(0, (sum, edit) => sum + edit.bytes.length);
    edits.addAll(values);
  }
  final AiNativeAppearances result = _nativeAppearanceResult(model, edits, owners.map((owner) => owner.use).toList());
  for (final MapEntry<AiNativeItem, List<int>> entry in names.entries) {
    final int index = drawing._objects.objects.indexOf(drawing._objects.forSource(entry.key));
    final AiNativeObject object = result.structure.drawing._objects.objects[index];
    if (object.names.isEmpty || object.names.any((field) => !_sameNativeBytes(field.stringBytes!, entry.value))) {
      throw const FormatException('Private name replacement lost its authoring metadata owner.');
    }
  }
  return result;
}
