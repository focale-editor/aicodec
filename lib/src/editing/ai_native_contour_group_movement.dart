part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies complete ordinary contour trees and all owned scalar instructions.
List<AiNativeInstruction> _nativeContourGroupCommands(AiNativeDrawing drawing, AiNativeGroup root) {
  final AiNativeObject owner = _nativeContourOwner(drawing, root);
  final List<AiNativeGroup> groups = drawing.groups.where((group) => group.start >= root.start && group.end <= root.end).toList();
  _nativeContourParents(drawing, groups.map(drawing._objects.structure.nodeFor));
  final List<AiNativePathTopology> topology = root.paths.isEmpty ? [] : _nativePathTopologies(drawing, root.paths.toList());
  for (final AiNativeGroup group in groups.where((group) => group.compound)) {
    _nativeCompoundElements(drawing, group.children, compound: group, retainContourData: true);
  }
  if (topology.any((path) => path.pointCount != null && path.pointCount!.start < owner.start)) {
    throw UnsupportedError('A moved contour group must own every descendant point count.');
  }
  final Set<AiNativeInstruction> geometry = {
    for (final AiNativePathTopology path in topology) ...[...path.path.geometry, path.path.paint, ...path.maskControls, ?path.pointCount],
    for (final AiNativeGroup group in groups) ...[group.opening, group.closing],
  };
  final List<AiNativeInstruction> commands = [];
  for (final AiNativeItem item in _pathInterval(drawing.items, owner.start, owner.end, (item) => item.start)) {
    if (_ordinaryObjectAttachment(drawing, item) || drawing._pathTopologyScope.retainedMetadata.contains(drawing._objects._attachments[item.start]?.dictionary)) {
      continue;
    }
    if (item is! AiNativeInstruction || !geometry.contains(item) && _nativeContourStateKey(item) == null) {
      throw UnsupportedError('Contour group movement requires complete ordinary geometry and literal state.');
    }
    commands.add(item);
  }
  return commands;
}

/// Tracks inherited reads and surviving writes through compound and clip scopes.
_NativeShapeAccess _nativeContourGroupAccess(AiNativeDrawing drawing, List<AiNativeInstruction> commands) {
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  final Map<int, AiNativeGroup> endings = {for (final AiNativeGroup group in drawing.groups) group.closing.start: group};
  final Set<String> printingReads = {};
  final Set<String> nativeReads = {};
  final Set<String> printingWrites = {};
  final Set<String> nativeWrites = {};
  final List<({Set<String> printing, Set<String> native})?> clips = [];
  int compoundDepth = 0;

  /// Records only reads that still depend on the subtree's inherited input.
  void read(Set<String> keys) {
    printingReads.addAll(keys.difference(printingWrites));
    nativeReads.addAll(keys.difference(nativeWrites));
  }

  for (final AiNativeInstruction command in commands) {
    final String? key = _nativeContourStateKey(command);
    if (key != null) {
      nativeWrites.add(key);
      if (!command.isPrivate) {
        printingWrites.add(key);
      }
      continue;
    }
    if (const {'u', '*u', 'q'}.contains(command.operator)) {
      read({'A', 'Xw'});
    }
    if (paths[command.start] case final AiNativePath path) {
      read(compoundDepth == 0 ? _shapeCopyReads(drawing, path) : _nativeContourFlags);
    }
    switch (command.operator) {
      case '*u':
        compoundDepth++;
      case '*U':
        read(_shapeCopyReads(drawing, endings[command.start]!.paths.last)..removeAll(_nativeContourFlags));
        compoundDepth--;
      case 'q':
        clips.add(compoundDepth == 0 ? (printing: Set.of(printingWrites), native: Set.of(nativeWrites)) : null);
      case 'Q':
        if (clips.removeLast() case final ({Set<String> printing, Set<String> native}) saved) {
          printingWrites
            ..removeAll(_nativeClipStateKeys)
            ..addAll(saved.printing.intersection(_nativeClipStateKeys));
          nativeWrites
            ..removeAll(_nativeClipStateKeys)
            ..addAll(saved.native.intersection(_nativeClipStateKeys));
        }
    }
  }
  return (printingReads: printingReads, nativeReads: nativeReads, printingWrites: printingWrites, nativeWrites: nativeWrites);
}

/// Relocates complete contour trees without losing their source's persistent state.
AiNativeDrawing _moveNativeContourGroups(
  AiNativeDrawing drawing,
  List<AiNativeGroup> groups,
  AiNativeGroup? parent,
  AiLayer? layer,
  AiBoundingBox bounds,
  AiNativeGroup? after,
  bool inheritCompoundAppearance,
  bool inheritParentFlags,
) {
  _nativeTopologyBounds(bounds);
  if (groups.isEmpty || groups.toSet().length != groups.length) {
    throw ArgumentError('Contour group movement requires distinct current source owners.');
  }
  if (parent != null && layer != null) {
    throw ArgumentError('Choose one destination group or layer.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeObject> owners = groups.map((group) => _nativeContourOwner(drawing, group)).toList();
  final List<AiNativeObject> ordered = [...owners]..sort((first, second) => first.start.compareTo(second.start));
  if (ordered.indexed.any((entry) => entry.$1 > 0 && ordered[entry.$1 - 1].end > entry.$2.start)) {
    throw ArgumentError('Moved contour groups cannot contain each other.');
  }
  final AiNativeStructureNode? target = parent != null
      ? structure.nodeFor(parent)
      : layer == null
      ? null
      : structure.nodeFor(layer);
  final List<AiNativeStructureNode> targetParents = _artworkParents(structure, target);
  final List<List<AiNativeStructureNode>> sourceParents = [for (final AiNativeGroup group in groups) _artworkParents(structure, structure.parentOf(structure.nodeFor(group)))];
  _nativeContourParents(drawing, {...targetParents, ...sourceParents.expand((value) => value)});
  final AiNativeGroup? targetCompound = targetParents.where((node) => node.kind == .compound).firstOrNull?.source as AiNativeGroup?;
  final List<AiNativeGroup?> sourceCompounds = [for (final List<AiNativeStructureNode> parents in sourceParents) parents.where((node) => node.kind == .compound).firstOrNull?.source as AiNativeGroup?];
  if ([targetParents, ...sourceParents].any((parents) => parents.where((node) => node.kind == .compound).length > 1) ||
      targetCompound != null && groups.any((group) => drawing.groups.any((child) => child.compound && child.start >= group.start && child.end <= group.end))) {
    throw UnsupportedError('Contour group movement cannot nest compound owners.');
  }
  if (targetCompound != null && !inheritCompoundAppearance && sourceCompounds.any((source) => !identical(source, targetCompound))) {
    throw UnsupportedError('Entering a different compound requires explicit inheritCompoundAppearance.');
  }
  final Set<AiNativeGroup> compounds = {?targetCompound, ...sourceCompounds.nonNulls};
  for (final AiNativeGroup compound in compounds) {
    _nativeCompoundElements(drawing, compound.children, compound: compound, retainContourData: true);
    if (compound.paths.map((path) => path.paint.operator.toUpperCase()).toSet().length != 1) {
      throw UnsupportedError('Moving compound branches requires a consistent shared paint mode.');
    }
  }
  _nativeContourTransforms(drawing, sourceParents, targetParents);
  if (after != null) {
    if (groups.contains(after) || structure.nodeFor(after).parentIndex != target?.index) {
      throw ArgumentError('The group anchor must be an unselected direct child of the destination.');
    }
    _nativeContourParents(drawing, [structure.nodeFor(after)]);
  }
  final int position = after == null ? parent?.closing.start ?? layer?.end.start ?? drawing.records.program.bodyEnd : _nativeContourOwner(drawing, after).end;
  if (owners.any((owner) => position > owner.start && position < owner.end || parent != null && parent.start >= owner.start && parent.end <= owner.end)) {
    throw ArgumentError('Contour groups cannot move into their own source owners.');
  }
  final List<List<AiNativeInstruction>> commands = groups.map((group) => _nativeContourGroupCommands(drawing, group)).toList();
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      position,
      for (final AiNativeObject owner in owners) ...[owner.start, owner.end],
      for (final AiNativeStructureNode node in {...targetParents, ...sourceParents.expand((value) => value)})
        if (node.source is AiNativeGroup) node.start,
      if (compounds.isNotEmpty) ...[
        ...compounds.map((compound) => compound.closing.start),
        for (final AiNativePath path in groups.expand((group) => group.paths)) path.start,
        for (final AiNativeInstruction command in commands.expand((value) => value))
          if (const {'u', '*u', 'q', '*U'}.contains(command.operator)) command.start,
      ],
    ],
    clipping: true,
    retainedMetadata: drawing._pathTopologyScope.retainedMetadata,
    stateKey: _nativeContourStateKey,
  );
  _nativeContourInheritance(sourceParents, targetParents, states, inheritParentFlags);
  final BytesBuilder inserted = BytesBuilder(copy: false);
  final List<AiSourceEdit> edits = [];
  final _NativeContourDifferences changed = (printing: {}, native: {});
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final (int, AiNativeObject) entry in owners.indexed) {
    final AiNativeObject owner = entry.$2;
    final List<int> retained = _nativeClipStateReplay(drawing, states[owner.start]!, states[owner.end]!, maxBytes: remaining, keys: _nativeArtworkStateKeys).bytes;
    remaining -= retained.length;
    final List<int> bytes;
    if (compounds.isNotEmpty) {
      bytes = _nativeContourBranchPlacement(
        drawing,
        owner,
        commands[entry.$1],
        states,
        states[position]!,
        changed,
        sourceCompound: sourceCompounds[entry.$1],
        targetCompound: targetCompound,
        maxBytes: remaining,
      );
    } else {
      final _NativeShapeAccess access = _nativeContourGroupAccess(drawing, commands[entry.$1]);
      final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
        drawing,
        (start: owner.start, end: owner.end),
        commands[entry.$1],
        const {},
        access,
        states[owner.start]!,
        states[owner.end]!,
        states[position]!,
        states[position]!,
        maxBytes: remaining,
        stateKey: _nativeContourStateKey,
      );
      _nativeContourPlaced(changed, access, placed.replacement);
      bytes = placed.bytes;
    }
    remaining -= bytes.length;
    inserted.add(bytes);
    edits.add(AiSourceEdit(start: owner.start, end: owner.end, bytes: retained.isEmpty ? const [32] : retained));
  }
  _nativeContourFollowing(drawing, position, targetParents, owners, states, changed);
  edits.add(AiSourceEdit(start: position, end: position, bytes: inserted.takeBytes()));
  final AiNativeDrawing result = _nativeCompoundResult(drawing, edits, bounds, drawing.groups.length);
  final List<AiNativeGroup> moved = [for (final AiNativeGroup root in groups) ...drawing.groups.where((group) => group.start >= root.start && group.end <= root.end)];
  final Set<AiNativeGroup> selected = moved.toSet();
  final List<AiNativeGroup> order = [
    ...drawing.groups.where((group) => group.closing.start < position && !selected.contains(group)),
    ...moved,
    ...drawing.groups.where((group) => group.closing.start >= position && !selected.contains(group)),
  ];
  for (final AiNativeGroup compound in compounds) {
    final AiNativeGroup updated = result.groups[order.indexOf(compound)];
    if (updated.paths.isEmpty) {
      throw UnsupportedError('Contour group movement cannot leave an empty compound; move or release its complete owner.');
    }
    _nativeCompoundElements(result, updated.children, compound: updated, retainContourData: true);
  }
  // Requalify mask ownership after changing compound boundaries and clip scopes.
  final List<AiNativePath> ordinary = result.paths.where((path) => !result._pathTopologyScope.derived.contains(path)).toList();
  if (ordinary.isNotEmpty) {
    _nativePathTopologies(result, ordinary);
  }
  return result;
}
