part of 'package:aikit/src/model/ai_native_records.dart';

/// Internal bridge qualifying non-text owners before renumbering ATE references.
///
/// Not exported by `aikit.dart`. Text-local ownership is checked by the text
/// library; this shares the native document and setup dependency contracts.
List<({int start, int end})> validateTextLifecycleSource({required AiNativeRecords records, required Set<AiNativeContainer> textRecords}) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: records));
  for (final AiNativeContainer record in textRecords.where((record) => record.type == 'AI11Text')) {
    final AiNativeStructureNode node = layers.structure.nodeFor(record);
    _sourceMovementParents(layers.drawing, _artworkParents(layers.structure, layers.structure.parentOf(node)));
  }
  final List<_NativeImageOwner> images = _nativeImageOwners(layers.drawing);
  final List<({int start, int end})> artwork = [
    for (final _NativeImageOwner image in images) image.span,
    for (final AiNativeMeshArtwork owner in layers.drawing.meshArtwork) (start: owner.start, end: owner.end),
    for (final AiNativeGradientArtwork owner in layers.drawing.gradientArtwork) (start: owner.start, end: owner.end),
  ];
  final List<({int start, int end})> independent = [...artwork];
  independent.addAll(_artboardFontSetupRanges(layers, const []));
  final Set<AiNativeContainer> retained = {
    for (final _NativeImageOwner image in images) ?image.dictionary,
    for (final AiNativeLayer layer in layers.layers)
      if (layer.bindingIssue == null && layer.dictionary != null) layer.dictionary!,
    for (final AiNativeObject object in layers.drawing._objects.objects)
      if (object.bindingIssue == null && object.dictionary != null && _nativeTextIndependentObject(layers.drawing, object)) object.dictionary!,
    for (final AiNativeMeshArtwork owner in layers.drawing.meshArtwork) ?owner.dictionary,
    for (final AiNativeGradientArtwork owner in layers.drawing.gradientArtwork) ?owner.dictionary,
  };
  if (records.roots.where((record) => record.type == 'AI11UndoFreeTextDocument').length > 1) {
    throw UnsupportedError('Text lifecycle requires at most one independent undo-free snapshot.');
  }
  for (final AiNativeContainer record in records.roots) {
    if (textRecords.contains(record)) {
      if (record.type == 'AI11TextDocument') {
        _artboardSetupRecord(layers, record);
        if (record.entries.length > 1 ||
            record.entries.any((entry) => entry.key != 'RulerOrigin' || entry.type != null || entry.numbers?.length != 2 || entry.numbers!.any((value) => !value.isFinite))) {
          throw UnsupportedError('Main text ownership requires a literal ruler origin without extra fields.');
        }
      }
      independent.add((start: record.start, end: record.end));
    } else if (retained.contains(record)) {
      _artboardSetupRecord(layers, record, setupOnly: false);
      independent.add((start: record.start, end: record.end));
    } else if (record.type == 'Document') {
      _referenceDocument(layers, record);
      independent.add((start: record.start, end: record.end));
    } else if (record.type == 'AI11UndoFreeTextDocument') {
      _artboardSetupRecord(layers, record);
      if (!record.hasBinary || record.entries.isNotEmpty) {
        throw UnsupportedError('Undo-free text requires its independent binary namespace.');
      }
      independent.add((start: record.start, end: record.end));
    } else {
      throw UnsupportedError('Text lifecycle has no reference contract for ${record.type}.');
    }
  }
  final List<AiToken> wrappers = records._projection.tokens.where((token) => token.kind == .comment && const {'%AI11_BeginTextDocument', '%AI11_EndTextDocument'}.contains(token.lexeme)).toList();
  if (wrappers.isNotEmpty) {
    final List<AiNativeContainer> documents = records.roots.where((record) => record.type == 'AI11TextDocument' || record.type == 'AI11UndoFreeTextDocument').toList();
    if (wrappers.length != 2 ||
        wrappers.first.lexeme != '%AI11_BeginTextDocument' ||
        wrappers.last.lexeme != '%AI11_EndTextDocument' ||
        wrappers.first.end > documents.first.start ||
        wrappers.last.start < documents.last.end ||
        wrappers.last.end > records.program.bodyStart) {
      throw UnsupportedError('Text document wrappers require unconditional ordered setup ownership.');
    }
    independent.addAll(wrappers.map((token) => (start: token.start, end: token.end)));
  }
  for (final AiToken token in records._projection.tokens) {
    if (token.start >= records.program.bodyStart &&
        token.end <= records.program.bodyEnd &&
        token.kind == .comment &&
        (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')) &&
        !const {'%AI5_BeginLayer', '%AI5_EndLayer--'}.contains(token.lexeme) &&
        !artwork.any((span) => token.start >= span.start && token.end <= span.end)) {
      throw UnsupportedError('Text lifecycle cannot qualify drawing annotations or alternate representations.');
    }
  }
  // Complete artwork spans include metadata; avoid overlapping independent ranges.
  final List<({int start, int end})> ranges = independent.where((span) => !artwork.any((owner) => owner != span && span.start >= owner.start && span.end <= owner.end)).toList();
  _referenceProgram(layers, ranges..sort((first, second) => first.start.compareTo(second.start)));
  return List.unmodifiable(artwork);
}

/// Allows only literal ordinary metadata and direct scalar shape parameters.
bool _nativeTextIndependentObject(AiNativeDrawing drawing, AiNativeObject object) {
  if (object.liveShape case final AiLiveShape shape) {
    if (_directNativeShapeIssue(shape) != null) {
      return false;
    }
    _shapeCopyDictionary(drawing, shape, object.dictionary!);
    AiNativeShapeParameters.fromShape(shape: shape);
    return true;
  }
  return object.dictionary!.entries.every((field) => const {'AI10_ArtUID', 'AIArtName', 'Object name', 'BBAccumRotation'}.contains(field.key));
}
