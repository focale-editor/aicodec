part of 'package:aikit/src/model/ai_native_records.dart';

/// Revises complete private trees with retained source and explicit new children.
AiNativeAppearances _replaceNativeAppearanceTrees(
  AiNativeAppearances model,
  List<AiNativeAppearanceTreeChange> changes,
) {
  if (changes.isEmpty) {
    throw ArgumentError('Private topology requires at least one complete owner.');
  }
  final List<AiNativeAppearanceArtwork> owners = _selectedBodyAppearanceArtwork(model, changes.map((change) => change.artwork.artwork).toList());
  for (final AiNativeAppearanceTreeChange change in changes) {
    final AiNativeAppearanceArtwork owner = change.artwork.artwork;
    if (owner.group == null || owner.liveShape != null || change.artwork.uses.length != 1 || !identical(change.artwork.uses.single, owner.use)) {
      throw ArgumentError('Child topology requires complete ordinary group printing owners.');
    }
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiProgram program = drawing.records.program;
  final AiNativeObjects objects = drawing._objects;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  final Map<AiNativeItem, _NativeSubtreeSpan> spans = {};
  final Map<AiNativeItem, AiNativeResourceUse> applications = {
    for (final AiNativeAppearanceArtwork owner in owners)
      for (final AiNativeResourceUse use in [owner.use, ...owner.nestedUses]) owner.authoringFor(use: use): use,
  };
  final Set<AiNativePath> clips = {
    for (final AiNativeAppearanceArtwork owner in owners)
      for (final AiNativePathTopology contour in owner.groupContours.where((contour) => contour.mask != .none)) contour.path,
  };
  final Map<AiNativeItem, AiNativeAppearanceArtwork> sourceOwners = {};

  /// Includes counts, panel metadata and direct style applications in each slot.
  void locate(AiNativeItem item, AiNativeAppearanceArtwork owner) {
    sourceOwners[item] = owner;
    final AiNativeObject object = objects.forSource(item);
    final AiNativeInstruction? count = item is AiNativePath ? owner.groupContours.singleWhere((contour) => identical(contour.path, item)).pointCount : null;
    spans[item] = (start: min(object.start, count?.start ?? object.start), end: max(object.end, applications[item]?.instruction.end ?? object.end));
    if (item is AiNativeGroup) {
      for (final AiNativeItem child in item.children) {
        locate(child, owner);
      }
    }
  }

  for (final AiNativeAppearanceArtwork owner in owners) {
    locate(owner.group!, owner);
  }
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      for (final AiNativeAppearanceArtwork owner in owners) ...[owner.start, owner.end],
      ...spans.values.map((span) => span.start),
      ...spans.keys.whereType<AiNativeGroup>().map((group) => group.closing.start),
    ],
    clipping: true,
    appearanceArtwork: retained,
  );
  late _NativeDocumentBytes bytes;
  late AiBoundingBox bounds;
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
      throw ArgumentError('Private topology requires distinct current children from the selected complete owners.');
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
        bounds,
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
    final AiNativeAppearanceArtwork owner = sourceOwners[item]!;
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

  final List<AiSourceEdit> printingEdits = _nativeAppearancePrintingEdits(model, changes.map((change) => change.artwork).toList());
  final List<AiSourceEdit> edits = [];
  final Set<AiSourceEdit> embeddedPrinting = {};
  int outputBytes = 0;
  for (final AiNativeAppearanceTreeChange change in changes) {
    final AiNativeAppearanceArtwork owner = change.artwork.artwork;
    final AiNativeGroup root = owner.group!;
    bytes = _NativeDocumentBytes(maximum: program.limits.maxDecodedBytes - outputBytes);
    bounds = change.artwork.bounds;
    final AiSourceEdit printable = printingEdits.singleWhere((edit) => edit.start == owner.printingGroup.start && edit.end == owner.printingGroup.end);
    embeddedPrinting.add(printable);
    copy(owner.start, printable.start);
    bytes.add(printable.bytes);
    copy(printable.end, spans[root]!.start);
    write(AiNativeAppearanceTreeChild.retain(source: root, children: change.children), 1);
    copy(spans[root]!.end, owner.end);
    final Uint8List replacement = bytes.takeBytes();
    outputBytes += replacement.length;
    edits.add(AiSourceEdit(start: owner.start, end: owner.end, bytes: replacement));
  }
  edits.sort((a, b) => a.start.compareTo(b.start));
  final List<AiNativeObjectIdentifier> removed = model.structure.identifiers
      .where((identity) => owners.any((owner) => identity.field.owner.start >= owner.start && identity.field.owner.end <= owner.end))
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
        edits: edits,
      ),
    ),
  );
  final AiNativeAppearances candidate = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: provisional));
  if (candidate.styles.length != model.styles.length || provisional.liveShapes.length != drawing.liveShapes.length) {
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
  final List<AiSourceEdit> placedEdits = [];
  final Map<_NativeSubtreeSpan, _NativeSourceReplacement> replacements = {};
  final List<int> useIndices = [];
  int offset = 0;
  final Map<int, _NativeShapeInputs> revisedStates = _shapeCopyInputs(
    provisional,
    [
      for (final AiNativeAppearanceArtwork owner in _nativeBodyAppearanceArtwork(candidate)) ...[owner.start, owner.end],
    ],
    clipping: true,
    appearanceArtwork: _nativeBodyAppearanceArtwork(candidate),
  );
  for (final AiSourceEdit edit in edits) {
    final AiNativeAppearanceArtwork owner = owners.singleWhere((owner) => owner.start == edit.start);
    final _NativeSubtreeSpan span = (start: edit.start + offset, end: edit.start + offset + edit.bytes.length);
    offset += edit.bytes.length - (edit.end - edit.start);
    final AiNativeAppearanceArtwork revised = _createdAppearanceOwner(candidate, span);
    if (revised.group == null) {
      throw const FormatException('Private topology must retain each complete group owner.');
    }
    final List<AiNativeInstruction> commands = _pathInterval(provisional.items, span.start, span.end, (item) => item.start).whereType<AiNativeInstruction>().toList();
    final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(provisional, revised, commands);
    final _NativeShapeInputs incoming = states[owner.start]!;
    if (!incoming.native.keys.toSet().containsAll(access.nativeReads) || !incoming.printing.keys.toSet().containsAll(access.printingReads)) {
      throw UnsupportedError('Private topology requires explicit complete owner inputs.');
    }
    // Owner ranges may omit a scalar prefix emitted by this transaction. Inspect
    // exact replacement boundaries so restoration covers that prefix as well.
    final Map<int, _NativeShapeInputs> boundaries = revisedStates.containsKey(span.start) && revisedStates.containsKey(span.end)
        ? revisedStates
        : _shapeCopyInputs(provisional, [span.start, span.end], clipping: true, appearanceArtwork: _nativeBodyAppearanceArtwork(candidate));
    final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
      provisional,
      span,
      commands,
      const {},
      access,
      boundaries[span.start]!,
      boundaries[span.end]!,
      incoming,
      states[owner.end]!,
      maxBytes: program.limits.maxDecodedBytes,
    );
    placedEdits.add(AiSourceEdit(start: owner.start, end: owner.end, bytes: placed.bytes));
    replacements[(start: owner.start, end: owner.end)] = (
      commands: [],
      styles: {},
      prefix: [],
      suffix: [],
      unresolved: placed.replacement.unresolved,
      printingUnresolved: placed.replacement.printingUnresolved,
      discard: false,
    );
    useIndices.add(candidate.uses.indexOf(revised.use));
  }
  _sourceFollowingDependencies(drawing, replacements, retainedArtwork: retained, clipping: true, patterns: candidate._patternNames);
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [...placedEdits, ...printingEdits.where((edit) => !embeddedPrinting.contains(edit))],
    paths: provisional.paths.length,
    groups: provisional.groups.length,
    liveShapes: drawing.liveShapes.length,
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  for (final int index in useIndices) {
    updated.artworkFor(use: updated.uses[index]);
  }
  return updated;
}
