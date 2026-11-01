part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies retained body dependencies once for each immutable drawing snapshot.
({AiNativeLayers layers, Set<AiNativePath> derived}) _nativePathTopologyScope(AiNativeDrawing drawing) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final ({List<({int start, int end})> ranges, Set<AiNativeContainer> objects}) text = _artboardTextScope(layers);
  _nativeReferenceBody(
    layers,
    _layerHeaderItems(layers),
    inspect: (model, start, end, headers) => _artboardArtworkInterval(model, start, end, headers, textOwners: text.objects, styles: const {}),
    qualifyShapeNeighbors: false,
  );
  final Set<AiNativePath> derived = {
    for (final AiLiveShape shape in drawing.liveShapes) ...[?shape.path, ...shape.appearancePaths],
    for (final AiNativeGradient gradient in drawing.gradients) ...gradient.paths,
  };
  final List<AiLiveShape> shapes = [...drawing.liveShapes]..sort((first, second) => first.start.compareTo(second.start));
  int shapeIndex = 0;
  int shapeEnd = 0;
  for (final AiNativePath path in drawing.paths) {
    while (shapeIndex < shapes.length && shapes[shapeIndex].start < path.end) {
      shapeEnd = max(shapeEnd, shapes[shapeIndex++].end);
    }
    if (shapeEnd > path.start) {
      derived.add(path);
    }
  }
  return (layers: layers, derived: Set.unmodifiable(derived));
}

/// Resolves local contour ownership without promoting retained CC expansions.
List<AiNativePathTopology> _nativePathTopologies(AiNativeDrawing drawing, List<AiNativePath> paths) {
  if (paths.isEmpty || paths.toSet().length != paths.length) {
    throw ArgumentError('Native path edits require distinct handles from the current drawing.');
  }
  paths.forEach(drawing._objects.forSource);
  final AiNativeLayers layers = drawing._pathTopologyScope.layers;
  final List<AiNativePathTopology> result = [];
  for (final AiNativePath path in paths) {
    if (path.isPrivate || drawing._pathTopologyScope.derived.contains(path)) {
      throw UnsupportedError('Path topology edits require authoritative ordinary geometry, not derived appearances or live-shape parameters.');
    }
    final AiNativeStructureNode node = layers.structure.nodeFor(path);
    final List<AiNativeStructureNode> parents = _artworkParents(layers.structure, layers.structure.parentOf(node));
    if (node.versions.isNotEmpty ||
        parents.any(
          (parent) => parent.versions.isNotEmpty || !const {AiNativeStructureKind.layer, AiNativeStructureKind.group, AiNativeStructureKind.compound, AiNativeStructureKind.clip}.contains(parent.kind),
        )) {
      throw UnsupportedError('Native path topology requires unconditional ordinary group and layer ownership.');
    }
    final List<AiNativeGroup> groups = parents.map((parent) => parent.source).whereType<AiNativeGroup>().toList().reversed.toList();
    if (groups.any((group) => group.opening.isPrivate)) {
      throw UnsupportedError('Private groups cannot supply ordinary editable contours.');
    }
    final int ordinal = _pathOffset(drawing.paths, path.start, (value) => value.start);
    final int previous = ordinal == 0 ? drawing.records.program.bodyStart : drawing.paths[ordinal - 1].end;
    final List<AiNativeInstruction> counts = _pathInterval(drawing.items, previous, path.start, (item) => item.start).whereType<AiNativeInstruction>().where((item) => item.operator == 'As').toList();
    if (counts.length > 1) {
      throw const FormatException('A native contour cannot own multiple point counts.');
    }
    final List<AiNativeInstruction> controls = _pathInterval(drawing.items, path.geometry.last.end, path.paint.start, (item) => item.start).cast<AiNativeInstruction>().toList();
    result.add(AiNativePathTopology._(path: path, groups: groups, pointCount: counts.singleOrNull, maskControls: controls));
  }
  return result;
}

/// Changes complete contour requests while retaining all other native source.
AiNativeDrawing _editNativePaths(AiNativeDrawing drawing, List<AiNativePathEdit> changes, AiBoundingBox bounds) {
  if ([bounds.left, bounds.bottom, bounds.right, bounds.top].any((value) => value.abs() > 9007199254740991)) {
    throw ArgumentError('Native path bounds must use portable coordinates.');
  }
  if (changes.isEmpty || changes.map((change) => change.path).toSet().length != changes.length) {
    throw ArgumentError('Native path edits require distinct source contours.');
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final Set<AiNativeGroup> compounds = {
    for (final AiNativePathEdit change in changes)
      for (final AiNativeStructureNode parent in _artworkParents(structure, structure.parentOf(structure.nodeFor(change.path))))
        if (parent.source case final AiNativeGroup group when group.compound) group,
  };
  final Set<AiNativePath> inspected = {...changes.map((change) => change.path), for (final AiNativeGroup compound in compounds) ...compound.paths};
  final Map<AiNativePath, AiNativePathTopology> topology = {for (final AiNativePathTopology owner in _nativePathTopologies(drawing, inspected.toList())) owner.path: owner};
  final Map<AiNativePath, AiNativePathMask> masks = {for (final AiNativePathEdit change in changes) change.path: change.mask ?? topology[change.path]!.mask};
  for (final AiNativeGroup compound in compounds) {
    if (compound.paths.map((path) => (masks[path] ?? topology[path]!.mask) != .none).toSet().length != 1) {
      throw UnsupportedError('A compound mask requires a consistent relationship for every contour in the same transaction.');
    }
  }
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativePathEdit change in changes) {
    final AiNativePathTopology owner = topology[change.path]!;
    final AiNativePath path = owner.path;
    final AiNativePathMask mask = masks[path]!;
    if (mask != .none && owner.clippingGroup == null) {
      throw UnsupportedError('A native mask requires an existing owning clipping group.');
    }
    final bool closed = path.closed || mask == .closed;
    final List<AiPathSegment> geometry = [...change.segments ?? path.segments];
    if (owner.pointCount != null && closed) {
      final List<double> first = geometry.first.coordinates;
      final List<double> last = geometry.last.coordinates;
      if (geometry.length == 1 || first[0] != last[last.length - 2] || first[1] != last.last) {
        geometry.add(AiPathSegment(operator: 'L', coordinates: first));
      }
    }
    if (change.segments != null || geometry.length != path.geometry.length) {
      final StringBuffer output = StringBuffer();
      for (final AiPathSegment segment in geometry) {
        final String command = '${segment.coordinates.join(' ')} ${segment.operator}\n';
        if (command.length > remaining) {
          throw const AiLimitException(message: 'Native contour output exceeds the source byte limit.');
        }
        remaining -= command.length;
        output.write(command);
      }
      edits.add(AiSourceEdit(start: path.geometry.first.start, end: path.geometry.first.end, bytes: latin1.encode(output.toString())));
      edits.addAll(path.geometry.skip(1).map((item) => AiSourceEdit(start: item.start, end: item.end, bytes: const [])));
    }
    if (owner.pointCount case final AiNativeInstruction count) {
      final int value = geometry.length - (closed ? 1 : 0);
      if (count.numbers!.single != value) {
        edits.add(AiSourceEdit(start: count.operands.single.start, end: count.operands.single.end, bytes: latin1.encode('$value')));
      }
    }
    if (mask != owner.mask) {
      if (owner.maskControls.isEmpty) {
        edits.add(AiSourceEdit(start: path.paint.start, end: path.paint.start, bytes: latin1.encode('${mask == .closed ? 'h' : 'H'} W ')));
      } else if (mask == .none) {
        edits.addAll(owner.maskControls.map((control) => AiSourceEdit(start: control.start, end: control.end, bytes: const [32])));
      } else {
        final AiNativeInstruction closure = owner.maskControls.first;
        edits.add(AiSourceEdit(start: closure.start, end: closure.end, bytes: latin1.encode(mask == .closed ? 'h' : 'H')));
      }
    }
  }
  edits.addAll(AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds));
  edits.removeWhere((edit) => _sameNativeBytes(Uint8List.sublistView(drawing.records.program.bytes, edit.start, edit.end), edit.bytes));
  if (edits.isEmpty) {
    return drawing;
  }
  return _groupLifecycleResult(drawing, edits, paths: drawing.paths.length, groups: drawing.groups.length, liveShapes: drawing.liveShapes.length);
}
