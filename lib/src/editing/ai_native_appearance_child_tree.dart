part of 'package:aikit/src/model/ai_native_records.dart';

/// Revises a complete private tree with retained source and explicit new children.
AiNativeAppearances _replaceNativeAppearanceChildren(
  AiNativeAppearances model,
  AiNativeAppearanceReplacement printing,
  List<AiNativeAppearanceTreeChild> children,
) {
  final AiNativeAppearanceArtwork owner = _selectedBodyAppearanceArtwork(model, [printing.artwork]).single;
  final AiNativeGroup? root = owner.group;
  if (root == null || owner.liveShape != null || printing.uses.length != 1 || !identical(printing.uses.single, owner.use)) {
    throw ArgumentError('Child topology requires one complete ordinary group printing owner.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiProgram program = drawing.records.program;
  final AiNativeObjects objects = drawing._objects;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final Map<AiNativeItem, _NativeSubtreeSpan> spans = {};
  final Map<AiNativeItem, AiNativeResourceUse> applications = {
    for (final AiNativeResourceUse use in [owner.use, ...owner.nestedUses]) owner.authoringFor(use: use): use,
  };
  final Set<AiNativePath> clips = {for (final AiNativePathTopology contour in owner.groupContours.where((contour) => contour.mask != .none)) contour.path};

  /// Includes counts, panel metadata and direct style applications in each slot.
  void locate(AiNativeItem item) {
    final AiNativeObject object = objects.forSource(item);
    final AiNativeInstruction? count = item is AiNativePath ? owner.groupContours.singleWhere((contour) => identical(contour.path, item)).pointCount : null;
    spans[item] = (start: min(object.start, count?.start ?? object.start), end: max(object.end, applications[item]?.instruction.end ?? object.end));
    if (item is AiNativeGroup) {
      item.children.forEach(locate);
    }
  }

  locate(root);
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [owner.start, owner.end, ...spans.values.map((span) => span.start), ...spans.keys.whereType<AiNativeGroup>().map((group) => group.closing.start)],
    clipping: true,
    appearanceArtwork: retained,
  );
  final _NativeDocumentBytes bytes = _NativeDocumentBytes(maximum: program.limits.maxDecodedBytes);
  final List<_NativeSubtreeSpan> preserved = [];
  final Set<AiNativeItem> used = {};
  int nodes = 0;

  /// Copies exact source slices while recording which native identities survive.
  void copy(int start, int end) {
    if (start < end) {
      bytes.add(Uint8List.sublistView(program.bytes, start, end));
      preserved.add((start: start, end: end));
    }
  }

  /// Restores literal inputs independently of new siblings and changed ancestors.
  void replay(int position, Set<String> reads) {
    final Map<String, AiNativeInstruction> values = states[position]!.native;
    if (!values.keys.toSet().containsAll(reads)) {
      throw UnsupportedError('Retained private children require proven inherited native inputs.');
    }
    bytes.text('\n');
    for (final AiNativeInstruction value in values.values) {
      bytes.text(_shapeStateText(value, private: true));
    }
    bytes.text('%_');
  }

  /// Retains each source descendant once, including unchanged nested subtrees.
  void reserve(AiNativeItem item, {required bool subtree}) {
    if (!spans.containsKey(item) || !used.add(item)) {
      throw ArgumentError('Private topology requires distinct current children from the same complete owner.');
    }
    if (subtree && item is AiNativeGroup) {
      for (final AiNativeItem child in item.children) {
        reserve(child, subtree: true);
      }
    }
  }

  /// Writes retained groups without discarding comments or scalar source gaps.
  void write(AiNativeAppearanceTreeChild child, int depth, {bool clip = false}) {
    if (++nodes > program.limits.maxTokens || depth > program.limits.maxDepth) {
      throw const AiLimitException(message: 'Private topology exceeds native structure limits.');
    }
    final AiNativeItem? item = child.source;
    if (item == null) {
      bytes.text('\n');
      _writeNativeAppearanceElement(
        bytes,
        drawing,
        child.definition!,
        printing.bounds,
        writeChildren: child.children == null
            ? null
            : () {
                for (final AiNativeAppearanceTreeChild nested in child.children!) {
                  write(nested, depth + 1);
                }
              },
      );
      return;
    }
    if (clips.contains(item) && !clip) {
      throw UnsupportedError('Private clipping contours stay attached to their original groups.');
    }
    reserve(item, subtree: child.children == null);
    final _NativeSubtreeSpan span = spans[item]!;
    final List<AiNativeInstruction> commands = owner._commands.where((command) => command.start >= span.start && command.end <= span.end).toList();
    final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(drawing, owner, commands);
    replay(span.start, access.nativeReads);
    if (child.children == null) {
      copy(span.start, span.end);
      bytes.text('\n');
      return;
    }
    final AiNativeGroup group = item as AiNativeGroup;
    if (!const {'u', 'q'}.contains(group.opening.operator)) {
      throw UnsupportedError('Compound children retain their complete contour ownership.');
    }
    copy(span.start, group.opening.end);
    bytes.text('\n');
    final List<AiNativeItem> original = group.children;
    for (final AiNativeItem mask in original.where(clips.contains)) {
      write(AiNativeAppearanceTreeChild.retain(source: mask), depth + 1, clip: true);
    }
    for (final AiNativeAppearanceTreeChild next in child.children!) {
      write(next, depth + 1);
    }
    // Retain non-artwork gaps exactly, including producer comments. Replaying
    // the old closing inputs afterwards protects the group's existing style.
    int cursor = group.opening.end;
    for (final AiNativeItem previous in original) {
      final _NativeSubtreeSpan slot = spans[previous]!;
      if (slot.start < cursor || slot.end > group.closing.start) {
        throw UnsupportedError('Private child source ownership overlaps its group boundary.');
      }
      copy(cursor, slot.start);
      bytes.text('\n');
      cursor = slot.end;
    }
    copy(cursor, group.closing.start);
    final AiNativeResourceUse? application = applications[group];
    final Set<String> reads = application == null ? <String>{} : _nativeAppearanceStyleState(model, model.resolve(use: application)!).reads;
    replay(group.closing.start, reads);
    copy(group.closing.start, span.end);
    bytes.text('\n');
  }

  final List<AiSourceEdit> printingEdits = _nativeAppearancePrintingEdits(model, [printing]);
  final AiSourceEdit printable = printingEdits.singleWhere((edit) => edit.start == owner.printingGroup.start && edit.end == owner.printingGroup.end);
  copy(owner.start, printable.start);
  bytes.add(printable.bytes);
  copy(printable.end, spans[root]!.start);
  write(AiNativeAppearanceTreeChild.retain(source: root, children: children), 1);
  copy(spans[root]!.end, owner.end);
  final Uint8List replacement = bytes.takeBytes();
  final List<AiNativeObjectIdentifier> removed = model.structure.identifiers
      .where((identity) => identity.field.owner.start >= owner.start && identity.field.owner.end <= owner.end)
      .where((identity) => !preserved.any((span) => identity.field.owner.start >= span.start && identity.field.owner.end <= span.end))
      .toList();
  if (removed.isNotEmpty) {
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
    final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
    _nativeRemovalReferences(
      layers,
      removed,
      headers,
      bodyDictionaries: _nativeReferenceBody(
        layers,
        headers,
        inspect: _nativeAppearanceInterval,
        qualifyShapeNeighbors: false,
        clipping: true,
        appearanceArtwork: retained,
        patterns: model._patternNames,
      ),
    );
  }
  final AiNativeDrawing provisional = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: program,
        edits: [AiSourceEdit(start: owner.start, end: owner.end, bytes: replacement)],
      ),
    ),
  );
  final AiNativeAppearances candidate = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: provisional));
  final _NativeSubtreeSpan span = (start: owner.start, end: owner.start + replacement.length);
  final AiNativeAppearanceArtwork revised = _createdAppearanceOwner(candidate, span);
  if (revised.group == null || candidate.styles.length != model.styles.length || provisional.liveShapes.length != drawing.liveShapes.length) {
    throw const FormatException('Private topology changed unrelated native definitions.');
  }
  final Set<String> oldNames = _nativeIdentityNames(model.structure);
  final Set<String> retainedNames = model.structure.identifiers.where((identity) => !removed.contains(identity)).map((identity) => latin1.decode(identity.bytes)).toSet();
  final Set<String> seen = {};
  for (final AiNativeObjectIdentifier identity in candidate.structure.identifiers) {
    final String name = latin1.decode(identity.bytes);
    if (!seen.add(name)) {
      throw const FormatException('Private topology introduced repeated native identities.');
    }
    if (!retainedNames.contains(name)) {
      _newNativeIdentity(identity.bytes, oldNames, program.limits.maxDecodedBytes);
    }
  }
  if (!seen.containsAll(retainedNames)) {
    throw const FormatException('Private topology lost a retained native identity.');
  }
  final List<AiNativeInstruction> commands = _pathInterval(provisional.items, span.start, span.end, (item) => item.start).whereType<AiNativeInstruction>().toList();
  final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(provisional, revised, commands);
  final _NativeShapeInputs incoming = states[owner.start]!;
  if (!incoming.native.keys.toSet().containsAll(access.nativeReads) || !incoming.printing.keys.toSet().containsAll(access.printingReads)) {
    throw UnsupportedError('Private topology requires explicit complete owner inputs.');
  }
  final Map<int, _NativeShapeInputs> revisedStates = _shapeCopyInputs(provisional, [span.start, span.end], clipping: true, appearanceArtwork: _nativeBodyAppearanceArtwork(candidate));
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    provisional,
    span,
    commands,
    const {},
    access,
    revisedStates[span.start]!,
    revisedStates[span.end]!,
    incoming,
    states[owner.end]!,
    maxBytes: program.limits.maxDecodedBytes,
  );
  _sourceFollowingDependencies(
    drawing,
    {
      (start: owner.start, end: owner.end): (
        commands: [],
        styles: {},
        prefix: [],
        suffix: [],
        unresolved: placed.replacement.unresolved,
        printingUnresolved: placed.replacement.printingUnresolved,
        discard: false,
      ),
    },
    retainedArtwork: retained,
    clipping: true,
    patterns: candidate._patternNames,
  );
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [AiSourceEdit(start: owner.start, end: owner.end, bytes: placed.bytes), ...printingEdits.where((edit) => !identical(edit, printable))],
    paths: provisional.paths.length,
    groups: provisional.groups.length,
    liveShapes: drawing.liveShapes.length,
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  updated.artworkFor(use: updated.uses[candidate.uses.indexOf(revised.use)]);
  return updated;
}
