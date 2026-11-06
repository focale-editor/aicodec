part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies direct gradient owners independently of opaque neighboring artwork.
List<AiNativeGradientArtwork> _readNativeGradientArtwork(AiNativeDrawing drawing) {
  if (drawing.gradients.isEmpty) {
    return [];
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeGradientArtwork> result = [];
  for (final AiNativeGradient gradient in drawing.gradients) {
    try {
      if (gradient.opening.isPrivate ||
          gradient.onStroke ||
          !const {0, 1, 2}.contains(gradient.closing.numbers!.single) ||
          gradient.paths.length != 1 ||
          gradient.geometry.flag != 1 ||
          gradient.geometry.length <= 0 ||
          gradient.geometry.relativeToArtwork && gradient.imagingMatrices.isEmpty) {
        continue;
      }
      final AiNativePath path = gradient.paths.single;
      if (path.isPrivate ||
          !const {'f', 'F'}.contains(path.paint.operator) ||
          gradient.closing.numbers!.single == 2 && !path.closed ||
          path.geometry.last.end > gradient.start ||
          path.geometry.skip(1).any((command) => command.operator == 'm')) {
        continue;
      }
      final AiNativeStructureNode node = structure.nodeFor(path);
      if (_artworkParents(structure, structure.parentOf(node)).any((parent) => parent.kind != .group && parent.kind != .layer)) {
        continue;
      }
      for (final AiNativeStructureNode parent in _artworkParents(structure, structure.parentOf(node))) {
        if (parent.source case final AiNativeGroup group) {
          _ordinaryObject(drawing, group);
        }
      }
      final AiNativeResourceUse? use = structure.resourceUses.where((use) => use.kind == .gradient && use.instruction.start == gradient.geometry.instruction.start).singleOrNull;
      if (use?.resolution != .resolved || use!.candidates.single.versions.isNotEmpty) {
        continue;
      }
      final AiNativeGradientDefinition resource = use.candidates.single.definition.source as AiNativeGradientDefinition;
      if (gradient.highlight != null && (!resource.radial || gradient.highlight!.numbers!.last < 0 || gradient.highlight!.numbers!.last > 1)) {
        continue;
      }
      final int previous = _pathOffset(drawing.items, path.start, (item) => item.start) - 1;
      final AiNativeItem? preceding = previous < 0 ? null : drawing.items[previous];
      final AiNativeInstruction? count = preceding is AiNativeInstruction && preceding.operator == 'As' ? preceding : null;
      if (count != null) {
        final List<double> first = path.geometry.first.numbers!;
        final List<double> last = path.geometry.last.numbers!;
        if (count.isPrivate ||
            count.numbers?.length != 1 ||
            count.numbers!.single != path.geometry.length - (path.closed ? 1 : 0) ||
            path.closed && (path.geometry.length < 2 || first.first != last[last.length - 2] || first.last != last.last)) {
          continue;
        }
      }
      final int start = count?.start ?? path.start;
      final int after = _pathOffset(drawing.items, gradient.end, (item) => item.start);
      final AiNativeItem? next = after < drawing.items.length ? drawing.items[after] : null;
      final AiNativeContainer? metadata = next is AiNativeContainer && next.type == 'ArtDictionary' ? next : null;
      final int end = metadata?.end ?? gradient.end;
      if (structure.versions.memberships(start: start, end: end).isNotEmpty ||
          drawing.liveShapes.any((shape) => shape.start < end && shape.end > start) ||
          drawing.paths.any((other) => !identical(other, path) && other.start < end && other.end > start)) {
        continue;
      }
      final Set<AiNativeItem> owned = {
        ?count,
        ...path.geometry,
        path.paint,
        gradient.opening,
        gradient.geometry.instruction,
        ?gradient.highlight,
        ...gradient.imagingMatrices,
        gradient.closing,
        ?metadata,
      };
      if (_pathInterval(drawing.items, start, end, (item) => item.start).any((item) => !owned.contains(item) || item.end > end) ||
          [?count, gradient.closing, ?metadata].any((item) => !_sameNativeObjectOwner(node, structure.nodeFor(item))) ||
          _nativeObjectMetadataComments(drawing, start, end)) {
        continue;
      }
      if (metadata != null) {
        _gradientArtworkMetadata(metadata);
      }
      result.add(AiNativeGradientArtwork._(gradient: gradient, path: path, pointCount: count, dictionary: metadata, start: start, end: end));
    } on AiLimitException {
      rethrow;
    } on UnsupportedError {
      // Unqualified neighbors retain their state and ownership barriers.
    } on FormatException {
      // Malformed native data never gains an editable gradient owner.
    }
  }
  return result..sort((first, second) => first.start.compareTo(second.start));
}

/// Requires literal ordinary identities and names without unknown cross-references.
void _gradientArtworkMetadata(AiNativeContainer dictionary, {bool numericRotation = false}) {
  if (dictionary.notRecorded || dictionary.entries.map((entry) => entry.key).toSet().length != dictionary.entries.length) {
    throw UnsupportedError('Gradient artwork metadata must have unique recorded fields.');
  }
  for (final AiNativeEntry entry in dictionary.entries) {
    if (entry.key == 'AI10_ArtUID') {
      final AiNativeContainer identity = _referenceRecord(entry, 'XMLUID');
      if (identity.entries.length != 1 || identity.entries.single.key != null || identity.entries.single.type != null || identity.entries.single.stringBytes?.isNotEmpty != true) {
        throw UnsupportedError('Gradient artwork requires one literal XML identifier.');
      }
    } else if (numericRotation && entry.key == 'BBAccumRotation' && entry.type == 'Real') {
      if (entry.number == null || !entry.number!.isFinite || entry.number!.abs() > 9007199254740991) {
        throw UnsupportedError('Artwork frame rotation must be a portable scalar.');
      }
    } else if (!const {'AIArtName', 'Object name', 'BBAccumRotation'}.contains(entry.key) || !const {'String', 'UnicodeString'}.contains(entry.type) || entry.stringBytes == null) {
      throw UnsupportedError('Gradient artwork metadata contains an unresolved field.');
    } else if (entry.key == 'BBAccumRotation') {
      final double? angle = double.tryParse(latin1.decode(entry.stringBytes!));
      if (entry.type != 'String' || angle == null || !angle.isFinite || angle.abs() > 9007199254740991) {
        throw UnsupportedError('Gradient artwork rotation must be a portable literal.');
      }
    }
  }
}

/// Requires a resolved resource before authoring a new native application.
void _validateCreatedGradientFill(AiNativeDrawing drawing, AiNativePathDefinition definition, AiNativeGradientFillDefinition gradient) {
  if (definition.artwork.fill == null) {
    throw ArgumentError('Direct gradient artwork requires a filled contour.');
  }
  final List<AiNativeGradientDefinition> resources = AiNativeGradientResources.decode(records: drawing.records).definitions
      .where((resource) => _sameNativeBytes(resource.nameBytes, gradient.nameBytes))
      .toList();
  if (resources.length != 1 || gradient.highlight != null && !resources.single.radial) {
    throw UnsupportedError('Created gradient fills require one named resource and radial geometry for a highlight.');
  }
}

/// Creates an entire gradient path and restores source state after its metadata.
AiNativeDrawing _createNativeGradientArtwork(AiNativeDrawing drawing, AiNativePathDefinition definition, AiNativeGradientFillDefinition gradient, AiNativeGroup? parent, AiLayer? layer) {
  _validateCreatedGradientFill(drawing, definition, gradient);
  final int position = _nativeCreationPosition(drawing, parent, layer);
  final List<AiLiveShape> shapes = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((first, second) => first.end.compareTo(second.end));
  _ordinaryArtworkPrefix(
    drawing,
    position,
    shapes,
    _layerHeaderItems(AiNativeLayers.decode(drawing: drawing)),
    privateState: true,
    resolvedBoundary: _nativeCreationBoundary(drawing, position, _nativeCreationAppearances(drawing)),
  );
  final List<int> bytes = _createdNativePathBytes(drawing, definition, gradient: gradient);
  return _writeNativeGradientArtwork(drawing, (start: position, end: position), bytes, definition.bounds, drawing.paths.length + 1, gradientDelta: 1);
}

/// Replaces one complete path/application while retaining its original metadata.
AiNativeDrawing _replaceNativeGradientArtwork(AiNativeDrawing drawing, AiNativeGradientArtwork owner, AiNativePathDefinition definition, AiNativeGradientFillDefinition gradient) {
  if (!drawing.gradientArtwork.contains(owner)) {
    throw ArgumentError('Gradient replacement requires a current owned artwork handle.');
  }
  if (definition.nameBytes != null || definition.identifierBytes != null) {
    throw ArgumentError('Gradient replacement retains its original metadata and identity.');
  }
  _validateCreatedGradientFill(drawing, definition, gradient);
  final List<int> bytes = [
    ..._createdNativePathBytes(drawing, definition, gradient: gradient),
    if (owner.dictionary case final AiNativeContainer metadata) ...drawing.records.program.bytes.sublist(metadata.start, metadata.end),
  ];
  return _writeNativeGradientArtwork(drawing, (start: owner.start, end: owner.end), bytes, definition.bounds, drawing.paths.length);
}

/// Places complete explicit artwork with independent native/printing restoration.
AiNativeDrawing _writeNativeGradientArtwork(AiNativeDrawing drawing, _NativeSubtreeSpan source, List<int> bytes, AiBoundingBox bounds, int paths, {int gradientDelta = 0, bool gradientOutput = true}) {
  final List<_NativeSubtreeSpan> neutral = _nativeNeutralArtwork(drawing);
  final Map<int, _NativeShapeInputs> original = _shapeCopyInputs(drawing, [source.start, source.end], neutralSpans: neutral, appearanceArtwork: _nativeCreationAppearances(drawing));
  final AiNativeDrawing provisional = _pathLifecycleResult(drawing, [
    AiSourceEdit(start: source.start, end: source.end, bytes: [10, ...bytes, 10]),
  ], paths);
  final _NativeSubtreeSpan span = (start: source.start, end: source.start + bytes.length + 2);
  final List<AiNativeGradientArtwork> owners = provisional.gradientArtwork.where((owner) => owner.start >= span.start && owner.end <= span.end).toList();
  if (owners.length != (gradientOutput ? 1 : 0)) {
    throw const FormatException('Created gradient artwork did not bind one complete native owner.');
  }
  final AiNativeLayers model = AiNativeLayers.decode(drawing: provisional);
  final List<AiNativeInstruction> commands = _layerInterval(
    model,
    span.start,
    span.end,
    _layerHeaderItems(model),
    privateState: true,
    retainImages: true,
  );
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(provisional, [span.start, span.end], appearanceArtwork: _nativeCreationAppearances(provisional));
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    provisional,
    span,
    commands,
    const {},
    _subtreeCopyAccess(provisional, commands, const [], states),
    states[span.start]!,
    states[span.end]!,
    original[source.start]!,
    original[source.end]!,
    maxBytes: drawing.records.program.limits.maxDecodedBytes,
  );
  if (source.start == source.end) {
    _sourceFollowingDependencies(drawing, const {}, insertions: {source.start: placed.replacement});
  } else {
    _sourceFollowingDependencies(drawing, {source: placed.replacement});
  }
  final AiNativeDrawing result = _pathLifecycleResult(drawing, [
    AiSourceEdit(start: source.start, end: source.end, bytes: placed.bytes),
    ...AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds),
  ], paths);
  if (result.gradientArtwork.length != drawing.gradientArtwork.length + gradientDelta) {
    throw const FormatException('Gradient artwork transaction changed unexpected native owners.');
  }
  return result;
}

/// Duplicates complete gradient owners with fresh values for existing identities.
AiNativeDrawing _duplicateNativeGradientArtwork(AiNativeDrawing drawing, List<AiNativeGradientArtwork> artwork, Map<AiNativeItem, List<int>> identifiers) {
  if (artwork.isEmpty || artwork.toSet().length != artwork.length || artwork.any((owner) => !drawing.gradientArtwork.contains(owner))) {
    throw ArgumentError('Gradient copies require distinct current artwork handles.');
  }
  final List<_NativeSubtreeSpan> spans = [for (final AiNativeGradientArtwork owner in artwork) (start: owner.start, end: owner.end)];
  final List<AiSourceEdit> replacements = _subtreeCopyEdits(drawing, artwork, spans, const [], identifiers);
  final AiNativeDrawing result = _pathLifecycleResult(drawing, _copiedNativeSubtrees(AiNativeLayers.decode(drawing: drawing), spans, const [], replacements), drawing.paths.length + artwork.length);
  if (result.gradientArtwork.length != drawing.gradientArtwork.length + artwork.length) {
    throw const FormatException('Gradient duplication changed unexpected native owners.');
  }
  return result;
}

/// Converts an independent process path to a complete named gradient application.
AiNativeDrawing _setNativePathGradient(AiNativeDrawing drawing, AiNativePath path, AiNativePathDefinition definition, AiNativeGradientFillDefinition gradient) {
  final AiNativeInstruction? count = _ordinaryPathCounts(drawing, [path])[path];
  final AiNativeObject object = _ordinaryObject(drawing, path);
  if (object.liveShape != null || definition.nameBytes != null || definition.identifierBytes != null) {
    throw UnsupportedError('Gradient conversion retains ordinary path metadata; live shapes use their parameter/appearance contract.');
  }
  _validateCreatedGradientFill(drawing, definition, gradient);
  final List<int> bytes = [
    ..._createdNativePathBytes(drawing, definition, gradient: gradient),
    ...drawing.records.program.bytes.sublist(path.end, object.end),
  ];
  return _writeNativeGradientArtwork(drawing, (start: count?.start ?? path.start, end: object.end), bytes, definition.bounds, drawing.paths.length, gradientDelta: 1);
}

/// Converts a complete gradient owner to explicit ordinary process artwork.
AiNativeDrawing _clearNativeGradientArtwork(AiNativeDrawing drawing, AiNativeGradientArtwork owner, AiNativePathDefinition definition) {
  if (!drawing.gradientArtwork.contains(owner) || definition.nameBytes != null || definition.identifierBytes != null) {
    throw ArgumentError('Clearing a gradient requires a current owner and retains its metadata.');
  }
  final List<int> bytes = [
    ..._createdNativePathBytes(drawing, definition),
    if (owner.dictionary case final AiNativeContainer metadata) ...drawing.records.program.bytes.sublist(metadata.start, metadata.end),
  ];
  return _writeNativeGradientArtwork(drawing, (start: owner.start, end: owner.end), bytes, definition.bounds, drawing.paths.length, gradientDelta: -1, gradientOutput: false);
}
