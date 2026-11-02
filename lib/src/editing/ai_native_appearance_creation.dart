part of 'package:aikit/src/model/ai_native_records.dart';

/// Shares ordinary contour serialization without exposing private lines publicly.
void _writeNativeAppearancePath(_NativeDocumentBytes bytes, AiNativeDrawing drawing, AiNativePathDefinition definition, {AiNativePathMask mask = .none}) {
  final List<int> data = _createdNativePathBytes(drawing, definition, mask: mask);
  for (final String line in latin1.decode(data).split('\n')) {
    if (line.isNotEmpty) {
      bytes.text('${line.startsWith('%_') ? '' : '%_'}$line\n');
    }
  }
}

/// Inserts an unpainted private path whose existing style owns its appearance.
AiNativeAppearances _createNativeAppearancePath(
  AiNativeAppearances model,
  AiNativePathDefinition definition,
  List<int> styleNameBytes,
  List<int> printingBytes,
  AiNativeGroup? parent,
  AiLayer? layer,
) {
  if (definition.filled || definition.stroked) {
    throw ArgumentError('A standalone appearance contour must be unpainted; its named style owns the paints.');
  }
  if (styleNameBytes.isEmpty || styleNameBytes.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('A standalone appearance requires a nonempty literal style name.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiNativeLimits limits = drawing.records.program.limits;
  _printingFragment(printingBytes, limits);
  final _NativeDocumentBytes bytes = _NativeDocumentBytes(maximum: limits.maxDecodedBytes);
  bytes.text('${definition.artwork.locked ? 1 : 0} A\n${definition.hidden ? 1 : 0} Xw\n');
  bytes.add(printingBytes);
  bytes.text('\n6 () XW\n');
  _writeNativeAppearancePath(bytes, drawing, definition);
  bytes.text('1 ');
  bytes.add(_nativeLiteralString(styleNameBytes, limits.maxDecodedBytes));
  bytes.text(' XW\n');
  return model.createArtwork(bytes: bytes.takeBytes(), bounds: definition.bounds, parent: parent, layer: layer);
}

/// Serializes explicit private children using the ordinary path/metadata writer.
AiNativeAppearances _createNativeAppearanceTree(
  AiNativeAppearances model,
  AiNativeAppearanceGroupDefinition definition,
  List<int> printingBytes,
  AiBoundingBox bounds,
  AiNativeGroup? parent,
  AiLayer? layer,
) {
  if (definition.styleNameBytes == null) {
    throw ArgumentError('A complete group appearance requires its root style name.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiNativeLimits limits = drawing.records.program.limits;
  _printingFragment(printingBytes, limits);
  final _NativeDocumentBytes bytes = _NativeDocumentBytes(maximum: limits.maxDecodedBytes);
  bytes.text('${definition.locked ? 1 : 0} A\n${definition.hidden ? 1 : 0} Xw\n');
  bytes.add(printingBytes);
  bytes.text('\n6 () XW\n');
  _writeNativeAppearanceElement(bytes, drawing, definition, bounds, root: true);
  return model.createArtwork(bytes: bytes.takeBytes(), bounds: bounds, parent: parent, layer: layer);
}

/// Writes a bounded typed subtree for creation and retained topology changes.
void _writeNativeAppearanceElement(
  _NativeDocumentBytes bytes,
  AiNativeDrawing drawing,
  AiNativeAppearanceElementDefinition definition,
  AiBoundingBox bounds, {
  bool root = false,
  void Function()? writeChildren,
}) {
  final AiNativeLimits limits = drawing.records.program.limits;
  int nodes = 0;

  /// Bounds recursion and writes private state without reinterpreting string data.
  void write(AiNativeAppearanceElementDefinition element, int depth, {bool root = false}) {
    if (depth > limits.maxDepth || ++nodes > limits.maxTokens) {
      throw const AiLimitException(message: 'Created appearance tree exceeds native structure limits.');
    }
    switch (element) {
      case AiNativeAppearancePathDefinition():
        _writeNativeAppearancePath(bytes, drawing, element.definition);
        if (element.styleNameBytes case final List<int> name) {
          bytes.text('%_0 ');
          bytes.add(_nativeLiteralString(name, limits.maxDecodedBytes));
          bytes.text(' XW\n');
        }
      case AiNativeAppearanceGroupDefinition():
        bytes.text('%_${element.locked ? 1 : 0} A\n%_${element.hidden ? 1 : 0} Xw\n%_${element.clip == null ? 'u' : 'q'}\n');
        if (element.clip case final AiNativeAppearanceClipDefinition clip) {
          if (++nodes > limits.maxTokens || depth + 1 > limits.maxDepth) {
            throw const AiLimitException(message: 'Created clipping contours exceed native structure limits.');
          }
          _writeNativeAppearancePath(
            bytes,
            drawing,
            AiNativePathDefinition(
              artwork: AiArtworkPath(segments: clip.segments, closed: clip.mask == .closed, evenOdd: clip.evenOdd),
              bounds: bounds,
              counted: clip.counted,
              nameBytes: clip.nameBytes,
              identifierBytes: clip.identifierBytes,
            ),
            mask: clip.mask,
          );
        }
        if (element.leaf case final AiNativeAppearanceLeafDefinition leaf) {
          _writeNativeAppearanceLeaf(bytes, drawing, leaf, private: true);
        } else if (depth == 1 && writeChildren != null) {
          writeChildren();
        } else {
          for (final AiNativeAppearanceElementDefinition child in element.children) {
            write(child, depth + 1);
          }
        }
        bytes.text('%_${element.clip == null ? 'U' : 'Q'}\n');
        bytes.add(_createdNativeMetadata(drawing, element.nameBytes, element.identifierBytes, '\n'));
        if (element.styleNameBytes case final List<int> name) {
          bytes.text(root ? '1 ' : '%_0 ');
          bytes.add(_nativeLiteralString(name, limits.maxDecodedBytes));
          bytes.text(' XW\n');
        }
    }
  }

  write(definition, 1, root: root);
}

/// Collects independently qualified body owners; opaque neighbors keep barriers.
List<AiNativeAppearanceArtwork> _nativeBodyAppearanceArtwork(AiNativeAppearances model) {
  final List<AiNativeAppearanceArtwork> owners = [];
  for (final AiNativeResourceUse use in model.uses.where((use) => !use.instruction.isPrivate && use.instruction.start >= model.structure.drawing.records.program.bodyStart)) {
    try {
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: use);
      if (owner.resource == null) {
        owners.add(owner);
      }
    } on AiLimitException {
      rethrow;
    } on UnsupportedError {
      // Unknown owners remain preserved source with unknown outgoing state.
    } on FormatException {
      // Malformed neighbors cannot establish inherited values for new artwork.
    }
  }
  return owners;
}

/// Tracks literal reads/writes and private style effects without executing them.
_NativeShapeAccess _nativeAppearanceArtworkAccess(AiNativeDrawing drawing, AiNativeAppearanceArtwork owner, List<AiNativeInstruction> commands) => _nativeArtworkCommandsAccess(
  drawing,
  [
    for (final AiNativeInstruction command in commands)
      if (!owner.leaves.values.any((leaf) => command.start >= leaf.group.opening.end && command.end <= leaf.group.closing.start)) command,
    for (final AiNativeAppearanceLeaf leaf in owner.leaves.values)
      for (final AiNativeInstruction command in leaf._commands)
        if (commands.isNotEmpty && command.start >= commands.first.start && command.end <= commands.last.end) command,
  ]..sort((first, second) => first.start.compareTo(second.start)),
  {
    for (final AiNativeResourceUse use in [owner.use, ...owner.nestedUses]) use.instruction.end: _nativeAppearanceAccessStyle(owner, use),
  },
  printingImages: [...owner.printingRasters, ...owner.leaves.values.map((leaf) => leaf.raster).whereType<AiNativeRaster>()],
);

/// Resolves definite assignments separately from potential style writes.
({Set<String> reads, Set<String> writes, Set<String> assigned}) _nativeAppearanceAccessStyle(AiNativeAppearanceArtwork owner, AiNativeResourceUse use) {
  final AiNativeAppearance style = owner._owner.resolve(use: use)!;
  final ({Set<String> reads, Set<String> writes}) state = _nativeAppearanceStyleState(owner._owner, style);
  return (reads: state.reads, writes: state.writes, assigned: _nativeAppearanceScalarState(style, state.reads, colors: true).keys.toSet());
}

/// Tracks qualified complete commands, including compound and clipping scopes.
_NativeShapeAccess _nativeArtworkCommandsAccess(
  AiNativeDrawing drawing,
  List<AiNativeInstruction> commands,
  Map<int, ({Set<String> reads, Set<String> writes, Set<String> assigned})> styles, {
  Iterable<AiNativeRaster> printingImages = const [],
}) {
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  final Map<int, AiNativeRaster> images = {for (final AiNativeRaster image in printingImages) image.instruction.start: image};
  late final Map<int, AiNativeItem> ordinaryImages = {for (final _NativeImageOwner owner in _nativeImageOwners(drawing)) owner.instruction.start: owner.image};
  final Map<int, AiNativeGroup> endings = {for (final AiNativeGroup group in drawing.groups) group.closing.start: group};
  final Set<String> nativeAssigned = {};
  final Set<String> printingAssigned = {};
  final Set<String> nativeWrites = {};
  final Set<String> printingWrites = {};
  final Set<String> nativeReads = {};
  final Set<String> printingReads = {};
  final List<({Set<String> native, Set<String> printing})?> clips = [];
  int compoundDepth = 0;
  for (final AiNativeInstruction command in commands) {
    final String? key = _nativeArtworkStateKey(command);
    if (key != null) {
      nativeAssigned.add(key);
      nativeWrites.add(key);
      if (!command.isPrivate) {
        printingAssigned.add(key);
        printingWrites.add(key);
      }
      continue;
    }
    final ({Set<String> reads, Set<String> writes, Set<String> assigned})? style = styles[command.end];
    final AiNativePath? path = paths[command.start];
    final Set<String> reads = const {'XI', '`'}.contains(command.operator)
        ? _nativeImageReads(images[command.start] ?? ordinaryImages[command.start] ?? (throw UnsupportedError('Artwork state requires qualified image ownership.')))
        : const {'aikit:text', 'aikit:mesh', 'aikit:symbol'}.contains(command.operator)
        ? _nativeArtworkStateKeys
        : path != null
        ? compoundDepth == 0
              ? _shapeCopyReads(drawing, path)
              : {..._nativeContourFlags}
        : const {'u', '*u', 'q'}.contains(command.operator)
        ? {'A', 'Xw'}
        : _marker(command, 6)
        ? {'Xy'}
        : style != null
        ? style.reads
        : {};
    if (endings[command.start] case final AiNativeGroup group when command.operator == '*U' && group.paths.isNotEmpty) {
      reads.addAll(_shapeCopyReads(drawing, group.paths.last)..removeAll(_nativeContourFlags));
    }
    nativeReads.addAll(reads.difference(nativeAssigned));
    if (!command.isPrivate && command.operator != 'XW') {
      printingReads.addAll(reads.difference(printingAssigned));
    }
    if (style != null) {
      nativeWrites.addAll(style.writes);
      nativeAssigned.addAll(style.assigned);
    }
    switch (command.operator) {
      case '*u':
        compoundDepth++;
      case '*U':
        compoundDepth--;
      case 'q':
        clips.add(compoundDepth == 0 ? (native: nativeAssigned.intersection(_nativeClipStateKeys), printing: printingAssigned.intersection(_nativeClipStateKeys)) : null);
      case 'Q':
        if (clips.removeLast() case final ({Set<String> native, Set<String> printing}) saved) {
          nativeAssigned
            ..removeAll(_nativeClipStateKeys)
            ..addAll(saved.native);
          if (!command.isPrivate) {
            printingAssigned
              ..removeAll(_nativeClipStateKeys)
              ..addAll(saved.printing);
          }
        }
    }
  }
  return (nativeReads: nativeReads, printingReads: printingReads, nativeWrites: nativeWrites, printingWrites: printingWrites);
}

/// Qualifies one inserted pair and its optional scalar prefix as a complete unit.
AiNativeAppearanceArtwork _createdAppearanceOwner(AiNativeAppearances model, _NativeSubtreeSpan span) {
  final List<AiNativeResourceUse> uses = model.uses.where((use) => use.instruction.start >= span.start && use.instruction.end <= span.end).toList();
  final List<AiNativeResourceUse> public = uses.where((use) => !use.instruction.isPrivate).toList();
  if (public.length != 1) {
    throw const FormatException('New appearance artwork requires exactly one public style application.');
  }
  final AiNativeAppearanceArtwork owner = model.artworkFor(use: public.single);
  if (owner.start < span.start ||
      owner.end > span.end ||
      owner.resource != null ||
      uses.length != owner.nestedUses.length + 1 ||
      uses.any((use) => !identical(use, owner.use) && !owner.nestedUses.contains(use))) {
    throw UnsupportedError('New appearance artwork cannot capture external geometry or style applications.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  for (final AiNativeItem item in _pathInterval(drawing.items, span.start, span.end, (item) => item.start)) {
    if (item.start >= owner.start && item.end <= owner.end) {
      continue;
    }
    if (item.end > owner.start || item is! AiNativeInstruction || _nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('New appearance artwork accepts only a scalar prefix outside its complete owner.');
    }
  }
  if (_nativeAppearanceMetadataComments(drawing, span.start, owner.start, const []) || _nativeAppearanceMetadataComments(drawing, owner.end, span.end, const [])) {
    throw UnsupportedError('New appearance prefixes cannot contain document sections or opaque data.');
  }
  return owner;
}

/// Inserts independent native/printing data with fresh identities and state replay.
AiNativeAppearances _createNativeAppearanceArtwork(AiNativeAppearances model, List<int> input, AiBoundingBox bounds, AiNativeGroup? parent, AiLayer? layer) {
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiProgram program = drawing.records.program;
  if (input.length + 2 > program.limits.maxDecodedBytes - program.bytes.length) {
    throw const AiLimitException(message: 'Created appearance artwork exceeds native output limits.');
  }
  if (input.isEmpty || input.any((byte) => byte < 0 || byte > 255) || [bounds.left, bounds.bottom, bounds.right, bounds.top].any((value) => value.abs() > 9007199254740991)) {
    throw ArgumentError('Created appearances require native bytes and portable host ink bounds.');
  }
  final Uint8List bytes = Uint8List.fromList([10, ...input, 10]);
  final int position = _nativeCreationPosition(drawing, parent, layer);
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final List<_NativeSubtreeSpan> neutral = _nativeNeutralArtwork(drawing);
  _ordinaryArtworkPrefix(
    drawing,
    position,
    drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((first, second) => first.end.compareTo(second.end)),
    _layerHeaderItems(AiNativeLayers.decode(drawing: drawing)),
    privateState: true,
    resolvedBoundary: [
      program.bodyStart,
      ...neutral.where((span) => span.end <= position).map((span) => span.end),
      ...retained.where((owner) => owner.end <= position).map((owner) => owner.end),
    ].reduce(max),
  );
  final _NativeShapeInputs incoming = _shapeCopyInputs(drawing, [position], clipping: true, neutralSpans: neutral, appearanceArtwork: retained)[position]!;
  final AiNativeDrawing provisional = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: program,
        edits: [AiSourceEdit(start: position, end: position, bytes: bytes)],
      ),
    ),
  );
  if (provisional.records.program.bodyStart != program.bodyStart ||
      provisional.records.program.bodyEnd != program.bodyEnd + bytes.length ||
      provisional.records.artboards.length != drawing.records.artboards.length ||
      provisional.records.program.layers.length != program.layers.length) {
    throw const FormatException('Created appearance artwork cannot change document sections, layers or boards.');
  }
  final AiNativeAppearances created = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: provisional));
  final _NativeSubtreeSpan span = (start: position, end: position + bytes.length);
  final AiNativeAppearanceArtwork owner = _createdAppearanceOwner(created, span);
  if (created.styles.length != model.styles.length ||
      created.uses.length != model.uses.length + owner.nestedUses.length + 1 ||
      provisional.liveShapes.length != drawing.liveShapes.length + (owner.liveShape == null ? 0 : 1) + owner.leaves.values.where((leaf) => leaf.shape != null).length) {
    throw const FormatException('Created artwork changed unrelated appearance declarations or owners.');
  }
  final Set<String> identities = _nativeIdentityNames(model.structure);
  for (final AiNativeObjectIdentifier identity in created.structure.identifiers.where((identity) => identity.field.owner.start >= span.start && identity.field.owner.end <= span.end)) {
    _newNativeIdentity(identity.bytes, identities, program.limits.maxDecodedBytes);
  }
  for (final AiNativeOpacityMask mask in owner.opacityMasks) {
    _opacityMaskWithoutIdentities(created, mask.record);
    _replacementMaskImageIdentifiers(drawing.records, provisional.records, mask.record);
  }
  final List<AiNativeInstruction> commands = _pathInterval(provisional.items, span.start, span.end, (item) => item.start).whereType<AiNativeInstruction>().toList();
  final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(provisional, owner, commands);
  if (access.nativeReads.any((key) => !incoming.native.containsKey(key)) || access.printingReads.any((key) => !incoming.printing.containsKey(key))) {
    throw UnsupportedError('Created appearance artwork requires explicit scalar inputs instead of unknown inherited defaults.');
  }
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(provisional, [span.start, span.end], clipping: true, appearanceArtwork: _nativeBodyAppearanceArtwork(created));
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    provisional,
    span,
    commands,
    const {},
    access,
    states[span.start]!,
    states[span.end]!,
    incoming,
    incoming,
    maxBytes: program.limits.maxDecodedBytes,
  );
  // New internal reads were qualified above. Only final unresolved differences
  // reach the original following source; inserted command offsets are not its IDs.
  _sourceFollowingDependencies(
    drawing,
    const {},
    insertions: {
      position: (commands: [], styles: {}, prefix: [], suffix: [], unresolved: placed.replacement.unresolved, printingUnresolved: placed.replacement.printingUnresolved, discard: false),
    },
    retainedArtwork: retained,
    clipping: true,
    patterns: created._patternNames,
  );
  final AiNativeDrawing result = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: program,
        edits: [
          AiSourceEdit(start: position, end: position, bytes: placed.bytes),
          ...AiNativeEditor.includeBoundsEdits(program: program, bounds: bounds),
        ],
      ),
    ),
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  if (updated.uses.length != created.uses.length ||
      result.paths.length != provisional.paths.length ||
      result.groups.length != provisional.groups.length ||
      result.liveShapes.length != provisional.liveShapes.length) {
    throw const FormatException('Created appearance state replay disrupted source ownership.');
  }
  updated.artworkFor(use: updated.uses[created.uses.indexOf(owner.use)]);
  return updated;
}
