part of 'package:aicodec/src/model/ai_native_records.dart';

/// Internal bridge qualifying non-text owners before renumbering ATE references.
///
/// Not exported by `aicodec.dart`. Text-local ownership is checked by the text
/// library; this shares the native document and setup dependency contracts.
List<({int start, int end})> validateTextLifecycleSource({required AiNativeRecords records, required Set<AiNativeContainer> textRecords}) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: records));
  final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: layers.structure);
  final List<AiNativeAppearanceArtwork> owners = _nativeBodyAppearanceArtwork(appearances);
  final Set<AiNativeContainer> privateText = {
    for (final AiNativeAppearanceArtwork owner in owners)
      for (final AiNativeAppearanceLeaf leaf in owner.leaves.values) ?leaf.text,
  };
  for (final AiNativeContainer record in textRecords.where((record) => record.type == 'AI11Text')) {
    if (records._projection.isPrivate(record.start) && !privateText.contains(record)) {
      throw UnsupportedError('Private text requires a complete qualified appearance wrapper.');
    }
    if (privateText.contains(record)) {
      continue;
    }
    final AiNativeStructureNode node = layers.structure.nodeFor(record);
    _sourceMovementParents(layers.drawing, _artworkParents(layers.structure, layers.structure.parentOf(node)));
  }
  final List<_NativeImageOwner> images = _nativeImageOwners(layers.drawing);
  final List<({int start, int end})> artwork = [
    for (final AiNativeAppearanceArtwork owner in owners) (start: owner.start, end: owner.end),
    for (final _NativeImageOwner image in images) image.span,
    for (final AiNativeMeshArtwork owner in layers.drawing.meshArtwork) (start: owner.start, end: owner.end),
    for (final AiNativeGradientArtwork owner in layers.drawing.gradientArtwork) (start: owner.start, end: owner.end),
  ];
  final List<({int start, int end})> independent = [...artwork];
  for (final AiNativePalette palette in AiNativeSwatches.decode(records: records).palettes) {
    if (palette.conditional || palette.swatches.any((cell) => cell.commands.length != 1)) {
      throw UnsupportedError('Text lifecycle requires independent literal palette cells.');
    }
    for (final AiNativeSwatch cell in palette.swatches) {
      _artboardPaletteColor(cell.commands.single);
    }
    independent.add((start: palette.start, end: palette.end));
  }
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
    if (artwork.any((owner) => record.start >= owner.start && record.end <= owner.end)) {
      continue;
    }
    if (record.type == 'KnownStyle') {
      final AiNativeAppearance style = appearances.styles.singleWhere((style) => identical(style.resource.definition.source, record));
      _nativeAppearanceStyleState(appearances, style);
      independent.add((start: record.start, end: record.end));
    } else if (textRecords.contains(record)) {
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

/// Requires an empty private ordinary wrapper in a complete appearance pair.
int validateTextAppearanceParent({required AiNativeRecords records, required AiNativeGroup parent}) {
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final AiNativeGroup? group = drawing.groups.where((group) => identical(group.opening.token, parent.opening.token)).singleOrNull;
  if (group == null ||
      !group.opening.isPrivate ||
      group.opening.operator != 'u' ||
      group.children.isNotEmpty ||
      drawing.items.any((item) => item.start >= group.opening.end && item.end <= group.closing.start)) {
    throw ArgumentError('New appearance text requires an empty source-owned private wrapper.');
  }
  final AiNativeAppearances model = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing));
  if (!_nativeBodyAppearanceArtwork(model).any((owner) => group.start >= owner.authoring.start && group.end <= owner.authoring.end)) {
    throw UnsupportedError('Text insertion requires a complete qualified appearance owner.');
  }
  return group.closing.start;
}
