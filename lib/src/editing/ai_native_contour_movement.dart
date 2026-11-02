part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies complete literal transparency for contour state preservation only.
String? _nativeContourStateKey(AiNativeInstruction command) {
  if (command.operator == 'Xy') {
    _artboardRetainedOpacity(command);
    return 'Xy';
  }
  return _nativeArtworkStateKey(command);
}

/// Captures contour inputs while retaining qualified import and transparency data.
Map<int, _NativeShapeInputs> _nativeContourInputs(AiNativeDrawing drawing, Iterable<int> boundaries) => _shapeCopyInputs(
  drawing,
  boundaries,
  clipping: true,
  retainedMetadata: drawing._pathTopologyScope.retainedMetadata,
  stateKey: _nativeContourStateKey,
);

/// Retains qualified import dictionaries without authorizing their disposal.
AiNativeObject _nativeContourOwner(AiNativeDrawing drawing, AiNativeItem source) {
  final AiNativeObject object = drawing._objects.forSource(source);
  if (object.bindingIssue != null && !drawing._pathTopologyScope.retainedMetadata.contains(object.dictionary)) {
    throw UnsupportedError(object.bindingIssue!);
  }
  return object;
}

/// Qualifies destination ancestry without promoting a CC printing expansion.
void _nativeContourParents(AiNativeDrawing drawing, Iterable<AiNativeStructureNode> parents) {
  for (final AiNativeStructureNode parent in parents) {
    if (parent.versions.isNotEmpty || !const {AiNativeStructureKind.layer, AiNativeStructureKind.group, AiNativeStructureKind.compound, AiNativeStructureKind.clip}.contains(parent.kind)) {
      throw UnsupportedError('Contour movement requires unconditional ordinary ancestors.');
    }
    if (parent.source case final AiNativeGroup group) {
      if (group.opening.isPrivate ||
          drawing.liveShapes.any((shape) => group.start >= shape.start && group.end <= shape.end) ||
          drawing.gradients.any((gradient) => group.start >= gradient.start && group.end <= gradient.end)) {
        throw UnsupportedError('Derived or private groups cannot receive independent contours.');
      }
      _nativeContourOwner(drawing, group);
    } else if (parent.source case final AiLayer source) {
      final AiNativeLayer layer = drawing._pathTopologyScope.layers.layerFor(source);
      if (layer.bindingIssue != null && !drawing._pathTopologyScope.retainedMetadata.contains(layer.dictionary)) {
        throw UnsupportedError(layer.bindingIssue!);
      }
    }
  }
}

/// Keeps imported coordinate bases identical across source and destination parents.
void _nativeContourTransforms(AiNativeDrawing drawing, Iterable<List<AiNativeStructureNode>> parents, List<AiNativeStructureNode> targetParents) {
  final List<AiNativeGroup> targetGroups = targetParents.map((node) => node.source).whereType<AiNativeGroup>().toList();
  final List<AiNativeGroup> targetTransforms = targetGroups.where((owner) => drawing._objects.forSource(owner).dictionary?['AdobeObjectMatrix'] != null).toList();
  for (final List<AiNativeStructureNode> sourceParents in parents) {
    final List<AiNativeGroup> sourceTransforms = sourceParents
        .map((node) => node.source)
        .whereType<AiNativeGroup>()
        .where((owner) => drawing._objects.forSource(owner).dictionary?['AdobeObjectMatrix'] != null)
        .toList();
    if (sourceTransforms.length != targetTransforms.length || sourceTransforms.indexed.any((entry) => !identical(entry.$2, targetTransforms[entry.$1]))) {
      throw UnsupportedError('Changing imported transform ancestry requires a separate coordinate and metadata rebasing contract.');
    }
  }
}

/// Requires explicit acceptance of changed inherited flags, depth or layers.
void _nativeContourInheritance(
  Iterable<List<AiNativeStructureNode>> parents,
  List<AiNativeStructureNode> targetParents,
  Map<int, _NativeShapeInputs> states,
  bool inheritParentFlags, {
  String inheritanceOption = 'inheritParentFlags',
}) {
  final List<AiNativeGroup> targetGroups = targetParents.map((node) => node.source).whereType<AiNativeGroup>().toList();
  if (!inheritParentFlags) {
    final AiNativeStructureNode? targetLayer = targetParents.where((node) => node.kind == .layer).firstOrNull;
    for (final List<AiNativeStructureNode> sourceParents in parents) {
      final AiNativeStructureNode? sourceLayer = sourceParents.where((node) => node.kind == .layer).firstOrNull;
      final List<AiNativeGroup> sourceGroups = sourceParents.map((node) => node.source).whereType<AiNativeGroup>().toList();
      if (!identical(sourceLayer, targetLayer) ||
          sourceGroups.length != targetGroups.length ||
          sourceGroups.indexed.any((entry) {
            final _NativeShapeInputs source = states[entry.$2.start]!;
            final _NativeShapeInputs destination = states[targetGroups[entry.$1].start]!;
            return const {'A', 'Xw'}.any(
              (key) =>
                  !_sameShapeAttribute(source.printing, source.printingOrigins, destination.printing, destination.printingOrigins, key) ||
                  !_sameShapeAttribute(source.native, source.nativeOrigins, destination.native, destination.nativeOrigins, key),
            );
          })) {
        throw UnsupportedError('Changing ancestor flags, depth or layers requires explicit $inheritanceOption.');
      }
    }
  }
}

/// Per-contour flags remain independent of a compound's shared paint state.
const Set<String> _nativeContourFlags = {'A', 'Xw', 'Ap', 'D'};

/// Uses compound paint at consumption while retaining the selected contour flags.
_NativeShapeInputs _nativeContourAppearance(_NativeShapeInputs local, _NativeShapeInputs shared) => (
  printing: {
    ...shared.printing,
    for (final String key in _nativeContourFlags)
      if (local.printing[key] case final AiNativeInstruction value) key: value,
  }..removeWhere((key, _) => _nativeContourFlags.contains(key) && !local.printing.containsKey(key)),
  native: {
    ...shared.native,
    for (final String key in _nativeContourFlags)
      if (local.native[key] case final AiNativeInstruction value) key: value,
  }..removeWhere((key, _) => _nativeContourFlags.contains(key) && !local.native.containsKey(key)),
  printingOrigins: {...shared.printingOrigins, for (final String key in _nativeContourFlags) key: local.printingOrigins[key]!},
  nativeOrigins: {...shared.nativeOrigins, for (final String key in _nativeContourFlags) key: local.nativeOrigins[key]!},
);

/// Moves counted source contours and restores both scalar projections at the slot.
AiNativeDrawing _moveNativeContours(
  AiNativeDrawing drawing,
  List<AiNativePath> paths,
  AiNativeGroup group,
  AiBoundingBox bounds,
  AiNativePath? after,
  AiNativePathMask? mask,
  bool inheritCompoundAppearance,
  bool inheritParentFlags,
) {
  _nativeTopologyBounds(bounds);
  final List<AiNativePathTopology> topology = _nativePathTopologies(drawing, paths);
  final Set<AiNativePath> selected = paths.toSet();
  final AiNativeStructure structure = drawing._objects.structure;
  final AiNativeStructureNode target = structure.nodeFor(group);
  final List<AiNativeStructureNode> targetParents = [target, ..._artworkParents(structure, structure.parentOf(target))];
  final Map<AiNativePath, List<AiNativeStructureNode>> parents = {
    for (final AiNativePath path in paths) path: _artworkParents(structure, structure.parentOf(structure.nodeFor(path))),
  };
  _nativeContourParents(drawing, {...targetParents, ...parents.values.expand((value) => value)});
  if (after != null) {
    _nativePathTopologies(drawing, [after]);
  }
  if (after != null && (selected.contains(after) || structure.nodeFor(after).parentIndex != target.index)) {
    throw ArgumentError('The insertion anchor must be an unselected direct contour of the destination.');
  }
  final int position = after == null ? group.closing.start : _ordinaryObject(drawing, after).end;
  final List<AiNativeGroup> targetGroups = targetParents.map((node) => node.source).whereType<AiNativeGroup>().toList();
  _nativeContourTransforms(drawing, parents.values, targetParents);
  final AiNativeGroup? compound = targetGroups.where((owner) => owner.compound).firstOrNull;
  final AiNativeGroup? clip = targetGroups.reversed.takeWhile((owner) => !owner.compound).where((owner) => owner.opening.operator == 'q').lastOrNull;
  if (targetGroups.where((owner) => owner.compound).length > 1 || topology.any((owner) => owner.groups.where((group) => group.compound).length > 1)) {
    throw UnsupportedError('Contour movement requires non-nested compound owners.');
  }
  if (compound != null && !inheritCompoundAppearance && topology.any((owner) => !identical(owner.compound, compound))) {
    throw UnsupportedError('Entering a different compound requires explicit inheritCompoundAppearance.');
  }
  if (clip == null && topology.any((owner) => (mask ?? owner.mask) != .none)) {
    throw UnsupportedError('A moved mask requires an effective destination clipping owner.');
  }
  final Set<AiNativeGroup> compounds = {?compound, for (final AiNativePathTopology owner in topology) ?owner.compound};
  for (final AiNativeGroup owner in compounds) {
    _nativeCompoundElements(drawing, owner.children, compound: owner, retainContourData: true);
    if (owner.paths.map((path) => path.paint.operator.toUpperCase()).toSet().length != 1) {
      throw UnsupportedError('Moving compound contours requires a consistent shared paint mode.');
    }
    if (!identical(owner, compound) && owner.paths.every(selected.contains)) {
      throw UnsupportedError('Contour movement cannot leave an empty compound; move or release its complete owner.');
    }
  }
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      position,
      ...paths.map((path) => path.start),
      ...compounds.map((owner) => owner.closing.start),
      ...targetGroups.map((owner) => owner.start),
      ...parents.values.expand((value) => value).where((node) => node.source is AiNativeGroup).map((node) => node.start),
    ],
    clipping: true,
    retainedMetadata: drawing._pathTopologyScope.retainedMetadata,
    stateKey: _nativeContourStateKey,
  );
  _nativeContourInheritance(parents.values, targetParents, states, inheritParentFlags);
  final List<AiSourceEdit> replacements = _nativePathEdits(
    drawing,
    [for (final AiNativePathTopology owner in topology) AiNativePathEdit(path: owner.path, mask: mask ?? owner.mask)],
    newClipPaths: selected,
    relocating: selected,
  );
  final String? paint = compound?.paths.last.paint.operator.toUpperCase();
  if (inheritCompoundAppearance && paint != null) {
    replacements.addAll([
      for (final AiNativePath path in paths) AiSourceEdit(start: path.paint.start, end: path.paint.end, bytes: latin1.encode(path.closed ? paint.toLowerCase() : paint)),
    ]);
  }
  replacements.sort((first, second) => first.start != second.start ? first.start.compareTo(second.start) : first.end.compareTo(second.end));
  final BytesBuilder insertion = BytesBuilder(copy: false);
  final List<AiSourceEdit> edits = [];
  for (final AiNativePathTopology owner in topology) {
    final AiNativePath path = owner.path;
    final AiNativeObject object = _ordinaryObject(drawing, path);
    final _NativeShapeInputs local = states[path.start]!;
    final _NativeShapeInputs source = compound == null && owner.compound != null ? _nativeContourAppearance(local, states[owner.compound!.closing.start]!) : local;
    final Set<String> reads = compound == null ? _shapeCopyReads(drawing, path) : _nativeContourFlags;
    final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
      drawing,
      (start: path.start, end: object.end),
      [...path.geometry, ...owner.maskControls, path.paint],
      const {},
      (printingReads: reads, nativeReads: reads, printingWrites: const {}, nativeWrites: const {}),
      source,
      source,
      states[position]!,
      states[position]!,
      maxBytes: drawing.records.program.limits.maxDecodedBytes - insertion.length,
      sourceSpans: [if (owner.pointCount case final AiNativeInstruction count) (start: count.start, end: count.end), (start: path.start, end: object.end)],
      sourceEdits: _pathInterval(replacements, owner.pointCount?.start ?? path.start, object.end, (edit) => edit.start).toList(),
      stateKey: _nativeContourStateKey,
    );
    if (placed.replacement.unresolved.isNotEmpty || placed.replacement.printingUnresolved.isNotEmpty) {
      throw UnsupportedError('Contour movement cannot restore unknown outgoing appearance values.');
    }
    insertion.add(placed.bytes);
    edits.add(AiSourceEdit(start: path.start, end: object.end, bytes: const [32]));
    if (owner.pointCount case final AiNativeInstruction count) {
      edits.add(AiSourceEdit(start: count.start, end: count.end, bytes: const [32]));
    }
  }
  edits.add(AiSourceEdit(start: position, end: position, bytes: insertion.takeBytes()));
  final AiNativeDrawing result = _nativeCompoundResult(drawing, edits, bounds, drawing.groups.length);
  final Map<AiNativeGroup, int> groupIndices = {for (final (int, AiNativeGroup) entry in drawing.groups.indexed) entry.$2: entry.$1};
  for (final AiNativeGroup owner in compounds) {
    final AiNativeGroup updated = result.groups[groupIndices[owner]!];
    _nativeCompoundElements(result, updated.children, compound: updated, retainContourData: true);
  }
  final List<AiNativePath> order = [
    ...drawing.paths.where((path) => path.start < position && !selected.contains(path)),
    ...paths,
    ...drawing.paths.where((path) => path.start >= position && !selected.contains(path)),
  ];
  final Map<AiNativePath, int> pathIndices = {for (final (int, AiNativePath) entry in order.indexed) entry.$2: entry.$1};
  _nativePathTopologies(result, [for (final AiNativePath path in paths) result.paths[pathIndices[path]!]]);
  return result;
}
