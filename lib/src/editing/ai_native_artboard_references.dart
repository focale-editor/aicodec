part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies retained owners separately from artwork identity deletion.
void _nativeArtboardReferenceScope(AiNativeArtboards model) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: model.records));
  final _ArtboardResourceScope resources = _artboardResourceScope(layers);
  final _ArtboardBrushScope brushes = _artboardBrushScope(layers, resources.brushes);
  final ({List<({int start, int end})> ranges, Set<AiNativeContainer> objects, bool empty}) text = _artboardTextScope(layers);
  final Map<AiNativeInstruction, AiNativeResourceUse> styles = {for (final AiNativeResourceUse use in layers.structure.resourceUses) use.instruction: use};
  final Map<int, AiNativeResourceUse> references = {for (final AiNativeResourceUse use in styles.values) use.instruction.start: use};
  final List<_NativeSubtreeSpan> images = _nativeImageOwners(layers.drawing).map((owner) => owner.span).toList();
  // The retained-body checker owns every interval outside each complete pair.
  final Set<AiNativeContainer> dictionaries = _nativeReferenceBody(
    layers,
    _layerHeaderItems(layers),
    inspect: (model, start, end, headers) => _artboardArtworkInterval(model, start, end, headers, textOwners: text.objects, styles: styles, retainedImages: images),
    qualifyShapeNeighbors: false,
  )..addAll({...text.objects, ...resources.objects});
  final List<_NativeFontEncoding> fonts = [];
  final List<({int start, int end})> independent = _referenceGradientRanges(layers, fontDeclarations: fonts);
  independent.addAll(_artboardFontSetupRanges(layers, fonts));
  independent.addAll(resources.ranges);
  independent.addAll(brushes.ranges);
  independent.addAll(_artboardSvgFilterRanges(layers));
  independent.addAll(_artboardSetupRanges(layers, patternNames: resources.patterns, symbolNames: resources.symbols));
  independent.addAll(text.ranges);
  for (final AiNativeContainer record in model.records.roots.where((record) => !dictionaries.contains(record))) {
    switch (record.type) {
      case 'KnownStyle':
        _artboardRetainedStyle(layers, record, references, resources.patterns, brushes.names);
      case 'SVGFilter':
        // The complete declaration and its XML owner were checked together.
        continue;
      case 'Document':
        _referenceDocument(layers, record);
      case 'AI11TextDocument' || 'AI11UndoFreeTextDocument':
        // Both complete binary owners were qualified together above.
        independent.add((start: record.start, end: record.end));
        continue;
      default:
        throw UnsupportedError('Artboard edits require qualification of the retained ${record.type} dependency owner.');
    }
    independent.add((start: record.start, end: record.end));
  }
  _referenceProgram(layers, independent..sort((first, second) => first.start.compareTo(second.start)));
}

/// Refuses conditional ownership and annotations outside a checked binary span.
void _artboardSetupRecord(AiNativeLayers layers, AiNativeContainer record, {List<({int start, int end})> checked = const [], bool setupOnly = true}) {
  final AiNativeRecords records = layers.drawing.records;
  if (setupOnly && record.end > records.program.bodyStart || layers.structure.nodeFor(record).versions.isNotEmpty) {
    throw UnsupportedError('Artboard dependency qualification requires unconditional setup records.');
  }
  for (final AiToken token in _pathInterval(records._projection.tokens, record.start, record.end, (token) => token.start)) {
    if (checked.any((range) => token.start >= range.start && token.end <= range.end)) {
      continue;
    }
    if (record.hasBinary && token.start >= record._binaryStart! && token.end <= record._binaryEnd!) {
      continue;
    }
    if (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'))) {
      throw UnsupportedError('Artboard dependency records cannot hide conditional or opaque annotations.');
    }
  }
}
