part of 'package:aicodec/src/model/ai_native_records.dart';

/// Qualifies the enclosing and trailing owners of an ordinary retained image.
int _nativeImageAttributeOwner(AiNativeDrawing drawing, AiNativeItem image, List<_NativeSubtreeSpan> images) {
  final ({AiNativeInstruction instruction, AiNativeContainer? dictionary}) fields = _nativeImageFields(image);
  if (image.start < drawing.records.program.bodyStart || image.end > drawing.records.program.bodyEnd || fields.instruction.isPrivate) {
    throw UnsupportedError('Image attributes require ordinary printable body ownership.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final AiNativeStructureNode? node = structure.nodes.where((node) => node.start == fields.instruction.start && node.kind == .instruction).singleOrNull;
  if (node == null || node.versions.isNotEmpty) {
    throw UnsupportedError('Image attributes require unconditional instruction ownership.');
  }
  _sourceMovementParents(drawing, _artworkParents(structure, structure.parentOf(node)));
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  _ordinaryArtworkPrefix(
    drawing,
    image.start,
    drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((first, second) => first.end.compareTo(second.end)),
    _layerHeaderItems(layers),
    privateState: true,
    resolvedBoundary: images.where((span) => span.end <= image.start).lastOrNull?.end,
  );
  final AiNativeItem? terminator = drawing.items.where((item) => item.start >= image.end).firstOrNull;
  final int end = fields.dictionary?.end ?? (terminator is AiNativeInstruction && terminator.operator == 'N' && terminator.operands.isEmpty && !terminator.isPrivate ? terminator.end : image.end);
  final int next = _nativeNeutralArtwork(drawing).where((span) => span.start >= end).firstOrNull?.start ?? drawing.records.program.bodyEnd;
  final List<AiNativeItem> following = _pathInterval(drawing.items, end, next, (item) => item.start).toList();
  _ordinaryPathFollowing(following, end);
  int boundary = following.whereType<AiNativeInstruction>().where((command) => const {'m', 'u', 'U', 'Lb', 'LB'}.contains(command.operator)).firstOrNull?.start ?? next;
  for (final AiNativeLayer layer in layers.layers) {
    if (layer.bindingIssue == null && layer.start >= end && layer.start < boundary) {
      boundary = layer.start;
    }
  }
  _ordinaryGroupMetadata(drawing, end, boundary);
  return end;
}

/// Plans explicit name updates without changing XML or sample-cache identifiers.
List<AiSourceEdit> _nativeImageNameEdits(AiNativeRecords records, AiNativeItem image, int end, List<int> bytes, bool unicode) {
  if (unicode && bytes.length.isOdd) {
    throw ArgumentError('Unicode image names require complete UTF-16 code units.');
  }
  final String literal = latin1.decode(_nativeLiteralString(bytes, records.program.limits.maxDecodedBytes));
  final String type = unicode ? 'UnicodeString' : 'String';
  final AiNativeContainer? dictionary = _nativeImageFields(image).dictionary;
  final List<AiNativeEntry> names = dictionary?.entries.where((entry) => const {'AIArtName', 'Object name'}.contains(entry.key)).toList() ?? [];
  if (names.isNotEmpty) {
    return [
      for (final AiNativeEntry name in names)
        if (name.type != type || !_samePlacedBytes(name.stringBytes, bytes))
          AiSourceEdit(start: name.items.firstOrNull?.start ?? name.typeToken!.start, end: name.typeToken!.end, bytes: latin1.encode('$literal /$type')),
    ];
  }
  if (dictionary == null) {
    return [AiSourceEdit(start: end, end: end, bytes: latin1.encode('\n%_/ArtDictionary :\n%_$literal /$type (AIArtName) ,\n%_;\n'))];
  }
  final AiToken closing = records._projection.tokens.singleWhere((token) => token.end == dictionary.end && token.lexeme == ';');
  final String prefix = records._projection.isPrivate(closing.start) ? '%_' : '';
  return [AiSourceEdit(start: closing.start, end: closing.start, bytes: latin1.encode('$literal /$type (AIArtName) ,\n$prefix'))];
}

/// Wraps selected attribute assignments with exact source-state restoration.
AiNativeRasters _updateNativeRasterAttributes(
  AiNativeRasters source,
  AiNativeRaster image,
  double? opacity,
  AiNativeTransparency? transparency,
  bool? hidden,
  bool? locked,
  bool? overprint,
  List<int>? nameBytes,
  bool unicodeName,
) {
  source.validateSourceLayout(image: image);
  final AiNativeRecords records = _updateNativeImageAttributes(source.records, image, opacity, transparency, hidden, locked, overprint, nameBytes, unicodeName);
  return identical(records, source.records) ? source : AiNativeRasters.decode(records: records);
}

/// Resolves shared image metadata without changing its concrete owner.
({AiNativeInstruction instruction, AiNativeContainer? dictionary}) _nativeImageFields(AiNativeItem image) => switch (image) {
  AiNativeRaster() => (instruction: image.instruction, dictionary: image.dictionary),
  AiNativePlacedObject() => (instruction: image.instruction, dictionary: image.dictionary),
  _ => throw ArgumentError('Expected an owned raster or linked placement.'),
};

/// Updates shared scalar attributes while retaining payload and link bytes.
AiNativeRecords _updateNativeImageAttributes(
  AiNativeRecords records,
  AiNativeItem image,
  double? opacity,
  AiNativeTransparency? transparency,
  bool? hidden,
  bool? locked,
  bool? overprint,
  List<int>? nameBytes,
  bool unicodeName,
) {
  if (opacity != null && (!opacity.isFinite || opacity < 0 || opacity > 1 || transparency != null) || unicodeName && nameBytes == null) {
    throw ArgumentError('Image attributes require unit opacity or explicit transparency without conflicting inputs, and explicit Unicode name bytes.');
  }
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final List<_NativeSubtreeSpan> images = _imageCreationNeutralSpans(drawing);
  final int end = _nativeImageAttributeOwner(drawing, image, images);
  final List<AiSourceEdit> edits = nameBytes == null ? [] : _nativeImageNameEdits(records, image, end, nameBytes, unicodeName);
  final Map<String, double> values = {
    'Xy': ?transparency?.opacity ?? opacity,
    if (hidden != null) 'Xw': hidden ? 1 : 0,
    if (locked != null) 'A': locked ? 1 : 0,
    if (overprint != null) 'O': overprint ? 1 : 0,
  };
  final StringBuffer prefix = StringBuffer();
  final StringBuffer suffix = StringBuffer();
  if (values.isNotEmpty) {
    final _NativeShapeInputs incoming = _shapeCopyInputs(drawing, [image.start], neutralSpans: images)[image.start]!;
    for (final MapEntry<String, double> entry in values.entries) {
      final AiNativeInstruction? printing = incoming.printing[entry.key];
      final AiNativeInstruction? native = incoming.native[entry.key];
      if (printing == null || native == null) {
        throw UnsupportedError('Image attribute changes cannot restore unknown ${entry.key} state.');
      }
      final int operand = entry.key == 'Xy' ? 1 : 0;
      final List<double>? tuple = entry.key == 'Xy' ? transparency?.operands : null;

      /// Compares the selected scalar or entire tuple without lexical normalization.
      bool matches(AiNativeInstruction command) =>
          tuple == null ? command.operands[operand].number == entry.value : command.operands.length == tuple.length && tuple.indexed.every((value) => command.operands[value.$1].number == value.$2);

      if (matches(printing) && matches(native)) {
        continue;
      }

      /// Keeps unselected flags unless the caller supplies the complete tuple.
      String assignment(AiNativeInstruction command, bool private) =>
          '${private ? '%_' : ''}${tuple?.join(' ') ?? command.operands.indexed.map((value) => value.$1 == operand ? entry.value.toString() : value.$2.lexeme).join(' ')} ${command.operator}\n';

      final String ordinary = assignment(printing, false);
      prefix.write(ordinary);
      if (assignment(native, false) != ordinary) {
        prefix.write(assignment(native, true));
      }
      suffix.write(_shapeStateText(printing, private: false));
      if (!_sameNativeArtworkState(printing, native)) {
        suffix.write(_shapeStateText(native, private: true));
      }
    }
  }
  if (prefix.isNotEmpty) {
    edits.add(AiSourceEdit(start: image.start, end: image.start, bytes: latin1.encode(prefix.toString())));
    edits.add(AiSourceEdit(start: end, end: end, bytes: latin1.encode('\n$suffix')));
    edits.addAll(
      AiNativeEditor.includeBoundsEdits(
        program: records.program,
        bounds: switch (image) {
          AiNativeRaster() => _nativeImageBounds(image.matrix, [0, -image.height.toDouble(), image.width.toDouble(), 0]),
          AiNativePlacedObject() => _nativeImageBounds(image.matrix, image.bounds),
          _ => throw ArgumentError('Expected an image.'),
        },
      ),
    );
  }
  if (edits.isEmpty) {
    return records;
  }
  return AiNativeRecords.decode(
    program: AiNativeEditor.apply(program: records.program, edits: edits),
  );
}
