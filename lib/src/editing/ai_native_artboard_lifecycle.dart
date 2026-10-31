part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies complete source dependencies and unambiguous artboard identities.
void _nativeArtboardStructureScope(AiNativeArtboards model) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: model.records));
  _nativeReferenceScope(layers, _layerHeaderItems(layers));
  final Set<String> identities = {};
  for (final AiNativeContainer record in model.records.containers) {
    final AiNativeEntry? entry = record['ArtboardUUID'];
    if (entry == null) {
      continue;
    }
    final Uint8List? bytes = entry.stringBytes;
    if (bytes == null || bytes.isEmpty || bytes.any((byte) => byte < 33 || byte > 126) || !identities.add(latin1.decode(bytes).toLowerCase())) {
      throw UnsupportedError('Artboard structure changes require unambiguous portable ASCII identities.');
    }
  }
}

/// Uses the first actual source line ending, including carriage-return-only data.
String _nativeArtboardLineEnding(AiProgram program) {
  for (final (int, int) byte in program.bytes.indexed) {
    if (byte.$2 == 13) {
      return byte.$1 + 1 < program.bytes.length && program.bytes[byte.$1 + 1] == 10 ? '\r\n' : '\r';
    }
    if (byte.$2 == 10) {
      return '\n';
    }
  }
  return '\n';
}

/// Writes one ordinary private CC dictionary with bounded escaped strings.
Uint8List _newNativeArtboard(AiNativeArtboards model, AiNativeArtboardDefinition definition) {
  final int maximum = model.records.program.limits.maxDecodedBytes;
  final String identifier = latin1.decode(definition.identifierBytes).toLowerCase();
  if (model.records.containers.any((record) => record['ArtboardUUID']?.text()?.toLowerCase() == identifier)) {
    throw ArgumentError('The new artboard UUID already belongs to the source.');
  }
  final List<int> name = _nativeLiteralString(definition.nameBytes, maximum);
  final List<int> uuid = _nativeLiteralString(definition.identifierBytes, maximum - name.length);
  final AiBoundingBox bounds = definition.bounds;
  final String newline = _nativeArtboardLineEnding(model.records.program);
  final List<String> lines = [
    '/Dictionary :',
    '${latin1.decode(name)} /UnicodeString (Name) ,',
    '${bounds.left} ${bounds.top} /RealPointRelToROrigin (PositionPoint1) ,',
    '${bounds.right} ${bounds.bottom} /RealPointRelToROrigin (PositionPoint2) ,',
    '${definition.rulerOrigin.join(' ')} /RealPoint (RulerOrigin) ,',
    '${latin1.decode(uuid)} /String (ArtboardUUID) ,',
    '${definition.selected ? 1 : 0} /Bool (IsArtboardSelected) ,',
    '${definition.defaultName ? 1 : 0} /Bool (IsArtboardDefaultName) ,',
    '${definition.pixelAspectRatio} /Real (PAR) ,',
    '0 /Int (DisplayMark) ,',
    '; ,',
    '',
  ];
  final String source = lines.join('$newline%_');
  if (source.length > maximum) {
    throw const AiLimitException(message: 'New artboard data exceeds the native byte limit.');
  }
  return latin1.encode(source);
}

/// Retains source dictionaries and their separator trivia in a qualified array.
({int start, int end, List<Uint8List> entries}) _nativeArtboardEntries(AiNativeArtboards model) {
  final AiNativeContainer array = model.document['Recorded']!.container!['ArtboardArray']!.container!;
  final List<AiToken> tokens = _pathInterval(model.records._projection.tokens, array.start, array.end, (token) => token.start).toList();
  if (tokens.length < 3 || tokens.last.lexeme != ';' || tokens.where((token) => token.kind != .comment).any((token) => !model.records._projection.isPrivate(token.start))) {
    throw UnsupportedError('Structural artboard edits require a complete private native array.');
  }
  final int end = tokens.last.start;
  final List<Uint8List> entries = [];
  final AiProgram program = model.records.program;
  for (final (int, AiNativeArtboard) indexed in model.artboards.indexed) {
    final AiNativeContainer record = indexed.$2.record;
    final int next = indexed.$1 + 1 < model.artboards.length ? model.artboards[indexed.$1 + 1].record.start : end;
    final List<AiToken> separators = _pathInterval(tokens, record.end, next, (token) => token.start).where((token) => token.kind != .comment).toList();
    if (separators.length > 1 || separators.isNotEmpty && separators.single.lexeme != ',' || separators.isEmpty && indexed.$1 + 1 < model.artboards.length) {
      throw UnsupportedError('Artboard entries require qualified native comma separators.');
    }
    entries.add(
      AiNativeEditor.copyRange(
        program: program,
        start: record.start,
        end: next,
        edits: [
          if (separators.isEmpty) AiSourceEdit(start: record.end, end: record.end, bytes: [32, 44]),
        ],
      ),
    );
  }
  return (start: model.artboards.isEmpty ? end : model.artboards.first.record.start, end: end, entries: entries);
}

/// Applies the complete order and explicit scalar changes as one bounded edit.
AiNativeArtboards _writeNativeArtboards(
  AiNativeArtboards model, {
  required List<int?> order,
  required int? activeIndex,
  required int? lastArtboardId,
  required AiBoundingBox? cropBounds,
  AiNativeArtboardDefinition? definition,
  AiNativePrintSelection? artboardPrinting,
  AiNativePrintSelection? pagePrinting,
}) {
  _nativeArtboardStructureScope(model);
  final List<AiSourceEdit> edits = _nativeArtboardCropEdits(model, cropBounds);
  final bool changed = order.length != model.artboards.length || order.indexed.any((item) => item.$1 != item.$2);
  if (changed) {
    final ({int start, int end, List<Uint8List> entries}) source = _nativeArtboardEntries(model);
    final Uint8List? created = definition == null ? null : _newNativeArtboard(model, definition);
    final BytesBuilder bytes = BytesBuilder(copy: false);
    for (final int? index in order) {
      final Uint8List entry = index == null ? created! : source.entries[index];
      if (bytes.length + entry.length > model.records.program.limits.maxDecodedBytes) {
        throw const AiLimitException(message: 'Artboard array exceeds the native output limit.');
      }
      bytes.add(entry);
    }
    edits.add(AiSourceEdit(start: source.start, end: source.end, bytes: bytes.takeBytes()));
  }

  /// Updates only existing scalar tokens, preserving field names and qualifiers.
  void scalar(AiNativeEntry? entry, int? value) {
    if (entry != null && entry.number != value) {
      edits.add(AiSourceEdit(start: entry.items.single.start, end: entry.items.single.end, bytes: latin1.encode(value.toString())));
    }
  }

  scalar(model.activeEntry, activeIndex);
  scalar(model.lastIdEntry, lastArtboardId);
  edits.addAll(_nativeArtboardPrintEdits(model, order: order, changed: edits.isNotEmpty, artboardPrinting: artboardPrinting, pagePrinting: pagePrinting));
  return _applyNativeArtboardEdits(model, edits);
}

/// Inserts explicit metadata without deriving a creation counter from array size.
AiNativeArtboards _createNativeArtboard(
  AiNativeArtboards model,
  AiNativeArtboardDefinition definition,
  int index,
  int? lastArtboardId,
  AiBoundingBox? cropBounds,
  bool activate,
  AiNativePrintSelection? artboardPrinting,
  AiNativePrintSelection? pagePrinting,
) {
  if (index < 0 || index > model.artboards.length) {
    throw RangeError.range(index, 0, model.artboards.length, 'index');
  }
  if ((model.lastArtboardId == null) != (lastArtboardId == null) || lastArtboardId != null && (lastArtboardId <= model.lastArtboardId! || lastArtboardId > 9007199254740991)) {
    throw ArgumentError('Creation requires an explicit increasing LastArtboardID exactly when the source records one.');
  }
  if (activate && model.activeIndex == null) {
    throw UnsupportedError('Creation cannot invent a missing active-artboard field.');
  }
  final int? active = model.activeIndex;
  return _writeNativeArtboards(
    model,
    order: [for (int position = 0; position < index; position++) position, null, for (int position = index; position < model.artboards.length; position++) position],
    activeIndex: activate
        ? index
        : active == null
        ? null
        : active + (active >= index ? 1 : 0),
    lastArtboardId: lastArtboardId,
    cropBounds: cropBounds,
    definition: definition,
    artboardPrinting: artboardPrinting,
    pagePrinting: pagePrinting,
  );
}

/// Removes complete source entries and explicitly resolves a removed active owner.
AiNativeArtboards _removeNativeArtboards(
  AiNativeArtboards model,
  Iterable<AiNativeArtboard> artboards,
  AiNativeArtboard? activeArtboard,
  AiBoundingBox? cropBounds,
  AiNativePrintSelection? artboardPrinting,
  AiNativePrintSelection? pagePrinting,
) {
  final Set<int> removed = {};
  for (final AiNativeArtboard artboard in artboards) {
    if (!removed.add(_requireNativeArtboard(model, artboard))) {
      throw ArgumentError('Artboard removal cannot select the same record twice.');
    }
  }
  if (removed.length == model.artboards.length) {
    throw ArgumentError('Artboard removal must retain at least one board.');
  }
  final List<int> order = [
    for (int index = 0; index < model.artboards.length; index++)
      if (!removed.contains(index)) index,
  ];
  final int? current = model.activeIndex;
  final int? replacement = activeArtboard == null ? null : _requireNativeArtboard(model, activeArtboard);
  if (replacement != null && (current == null || !removed.contains(current) || removed.contains(replacement)) || current != null && removed.contains(current) && replacement == null) {
    throw ArgumentError('Removing the active board requires exactly one explicitly retained replacement.');
  }
  return _writeNativeArtboards(
    model,
    order: order,
    activeIndex: current == null ? null : order.indexOf(replacement ?? current),
    lastArtboardId: model.lastArtboardId,
    cropBounds: cropBounds,
    artboardPrinting: artboardPrinting,
    pagePrinting: pagePrinting,
  );
}

/// Validates a full source-owned permutation before changing any native bytes.
AiNativeArtboards _reorderNativeArtboards(
  AiNativeArtboards model,
  List<AiNativeArtboard> artboards,
  AiBoundingBox? cropBounds,
  AiNativePrintSelection? artboardPrinting,
  AiNativePrintSelection? pagePrinting,
) {
  if (artboards.length != model.artboards.length) {
    throw ArgumentError('Artboard reordering requires every current board exactly once.');
  }
  final List<int> order = artboards.map((board) => _requireNativeArtboard(model, board)).toList();
  if (order.toSet().length != order.length) {
    throw ArgumentError('Artboard reordering cannot repeat a source record.');
  }
  return _writeNativeArtboards(
    model,
    order: order,
    activeIndex: model.activeIndex == null ? null : order.indexOf(model.activeIndex!),
    lastArtboardId: model.lastArtboardId,
    cropBounds: cropBounds,
    artboardPrinting: artboardPrinting,
    pagePrinting: pagePrinting,
  );
}
