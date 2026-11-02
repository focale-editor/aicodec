part of 'package:aicodec/src/model/ai_native_records.dart';

/// Qualifies disjoint current complete body owners before any offsets change.
List<AiNativeAppearanceArtwork> _selectedBodyAppearanceArtwork(AiNativeAppearances model, List<AiNativeAppearanceArtwork> artwork) {
  if (artwork.isEmpty || artwork.any((owner) => !identical(owner._owner, model)) || artwork.map((owner) => owner.use).toSet().length != artwork.length) {
    throw ArgumentError('Appearance lifecycle requires distinct current complete artwork handles.');
  }
  if (artwork.any((owner) => owner.resource != null)) {
    throw UnsupportedError('Resource-local appearance lifecycle requires dependent-instance propagation.');
  }
  final List<AiNativeAppearanceArtwork> selected = [...artwork]..sort((first, second) => first.start.compareTo(second.start));
  for (int index = 1; index < selected.length; index++) {
    if (selected[index].start < selected[index - 1].end) {
      throw ArgumentError('Appearance lifecycle requires disjoint complete source owners.');
    }
  }
  return selected;
}

/// Copies exact complete source owners with fresh metadata and unchanged pixels.
AiNativeAppearances _duplicateNativeAppearanceArtwork(
  AiNativeAppearances model,
  List<AiNativeAppearanceArtwork> artwork,
  Map<AiNativeContainer, List<int>> identifiers,
) {
  final List<AiNativeAppearanceArtwork> selected = _selectedBodyAppearanceArtwork(model, artwork);
  if (selected.any((owner) => owner.leaves.values.any((leaf) => leaf.text != null))) {
    throw UnsupportedError('Text appearance lifecycle requires updating its global story resources first.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiNativeRecords records = drawing.records;

  /// Includes every copied metadata descendant, including nested mask objects.
  bool copied(int start, int end) => selected.any((owner) => start >= owner.start && end <= owner.end);

  final List<AiNativeObjectIdentifier> saved = model.structure.identifiers.where((identity) => copied(identity.field.owner.start, identity.field.owner.end)).toList();
  final Set<AiNativeContainer> expected = saved.map((identity) => identity.field.owner.source as AiNativeContainer).toSet();
  if (identifiers.length != expected.length || identifiers.keys.any((record) => !expected.contains(record)) || expected.length != saved.length) {
    throw ArgumentError('Appearance copies require one fresh identifier for each identified metadata container.');
  }
  if (saved.map((identity) => latin1.decode(identity.bytes)).toSet().length != saved.length) {
    throw UnsupportedError('Copying repeated appearance identities requires an explicit alias contract.');
  }
  final Set<String> reserved = _nativeIdentityNames(model.structure);
  final List<AiSourceEdit> metadata = [];
  int metadataBudget = records.program.limits.maxDecodedBytes;
  for (final AiNativeObjectIdentifier identity in saved) {
    final AiSourceEdit edit = _nativeIdentityEdit(identity, identifiers[identity.field.owner.source]!, reserved, metadataBudget);
    metadata.add(edit);
    metadataBudget -= edit.bytes.length;
  }
  final _RasterIdentifiers caches = _RasterIdentifiers(records: records);
  caches._used.addAll(reserved.where(_rasterIdentifier.hasMatch).map((value) => value.toLowerCase()));
  for (final AiNativeContainer record in records.containers.where((record) => copied(record.start, record.end))) {
    for (final AiNativeEntry field in record.entries.where((field) => const {'AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'}.contains(field.key))) {
      if (!const {'String', 'UnicodeString'}.contains(field.type) || field.text() == null || field.items.isEmpty || field.typeToken == null) {
        throw UnsupportedError('Copied mask images require literal sample-cache identifiers.');
      }
      final List<int> bytes = latin1.encode('(${caches.next()}) /String');
      metadataBudget -= bytes.length;
      if (metadataBudget < 0) {
        throw const AiLimitException(message: 'Copied appearance metadata exceeds native byte limits.');
      }
      metadata.add(AiSourceEdit(start: field.items.first.start, end: field.typeToken!.end, bytes: bytes));
    }
  }
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      for (final AiNativeAppearanceArtwork owner in selected) ...[owner.start, owner.end],
    ],
    clipping: true,
    appearanceArtwork: retained,
  );
  final List<AiSourceEdit> edits = [];
  final Map<int, _NativeSourceReplacement> insertions = {};
  int remaining = records.program.limits.maxDecodedBytes - records.program.bytes.length;
  for (final AiNativeAppearanceArtwork owner in selected) {
    final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(drawing, owner, owner._commands);
    final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
      drawing,
      (start: owner.start, end: owner.end),
      owner._commands,
      const {},
      access,
      states[owner.start]!,
      states[owner.end]!,
      states[owner.end]!,
      states[owner.end]!,
      maxBytes: remaining,
      sourceEdits: metadata,
    );
    edits.add(AiSourceEdit(start: owner.end, end: owner.end, bytes: placed.bytes));
    insertions[owner.end] = (
      commands: owner._commands,
      styles: owner._styleReads,
      prefix: placed.replacement.prefix,
      suffix: placed.replacement.suffix,
      unresolved: placed.replacement.unresolved,
      printingUnresolved: placed.replacement.printingUnresolved,
      discard: false,
    );
    remaining -= placed.bytes.length;
  }
  _sourceFollowingDependencies(drawing, const {}, insertions: insertions, retainedArtwork: retained, clipping: true, patterns: model._patternNames);
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    edits,
    appearanceLeaves: true,
    paths: drawing.paths.length + drawing.paths.where((path) => copied(path.start, path.end)).length,
    groups: drawing.groups.length + drawing.groups.where((group) => copied(group.start, group.end)).length,
    liveShapes: drawing.liveShapes.length + drawing.liveShapes.where((shape) => copied(shape.start, shape.end)).length,
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  final List<({AiNativeResourceUse source, bool copy})> uses = [];
  for (final AiNativeResourceUse use in model.uses) {
    uses.add((source: use, copy: false));
    if (selected.where((owner) => identical(owner.use, use)).singleOrNull case final AiNativeAppearanceArtwork owner) {
      uses.addAll(model.uses.where((child) => child.instruction.start >= owner.start && child.instruction.end <= owner.end).map((child) => (source: child, copy: true)));
    }
  }
  if (updated.styles.length != model.styles.length || updated.uses.length != uses.length || updated.structure.identifiers.length != model.structure.identifiers.length + saved.length) {
    throw const FormatException('Copying appearance artwork disrupted native resources or identities.');
  }
  for (final (int, ({AiNativeResourceUse source, bool copy})) entry in uses.indexed) {
    final AiNativeResourceUse use = updated.uses[entry.$1];
    if (!_sameNativeBytes(use.nameBytes, entry.$2.source.nameBytes) || use.instruction.isPrivate != entry.$2.source.instruction.isPrivate) {
      throw const FormatException('Copying appearance artwork changed a style application.');
    }
    if (retained.any((owner) => identical(owner.use, entry.$2.source))) {
      final AiNativeAppearanceArtwork owner = updated.artworkFor(use: use);
      if (entry.$2.copy) {
        for (final AiNativeOpacityMask mask in owner.opacityMasks) {
          _replacementMaskImageIdentifiers(records, result.records, mask.record);
        }
      }
    }
  }
  return updated;
}
