part of 'package:aicodec/src/model/ai_native_records.dart';

/// Qualifies complete Cartesian body packets without promoting opaque neighbors.
List<AiNativeMeshArtwork> _readNativeMeshArtwork(AiNativeDrawing drawing) {
  final List<AiNativeMesh> meshes;
  try {
    meshes = _readNativeMeshes(drawing.records, true);
  } on AiLimitException {
    rethrow;
  } on UnsupportedError {
    return [];
  } on FormatException {
    return [];
  }
  final AiNativeStructure structure = drawing._objects.structure;
  final List<AiNativeMeshArtwork> result = [];
  for (final AiNativeMesh mesh in meshes) {
    try {
      _validateMeshPaintOwner(drawing.records, mesh, drawing: drawing);
      AiNativeMeshDefinition.fromSource(mesh: mesh);
      final int first = _pathOffset(drawing.items, mesh.start, (item) => item.start);
      final AiNativeItem? item = first < drawing.items.length ? drawing.items[first] : null;
      if (item is! AiNativeInstruction || item.start != mesh.start || item.operator != 'X!' || item.isPrivate) {
        continue;
      }
      final AiNativeStructureNode node = structure.nodeFor(item);
      final List<AiNativeStructureNode> parents = _artworkParents(structure, structure.parentOf(node));
      if (parents.any((parent) => parent.kind != .group && parent.kind != .layer)) {
        continue;
      }
      for (final AiNativeStructureNode parent in parents) {
        if (parent.source case final AiNativeGroup group) {
          _ordinaryObject(drawing, group);
        }
      }
      int after = _pathOffset(drawing.items, mesh.end, (item) => item.start);
      int end = mesh.end;
      if (after < drawing.items.length) {
        if (drawing.items[after] case final AiNativeInstruction terminator when terminator.operator == 'N' && terminator.operands.isEmpty && !terminator.isPrivate) {
          end = terminator.end;
          after++;
        }
      }
      final AiNativeItem? next = after < drawing.items.length ? drawing.items[after] : null;
      final AiNativeContainer? dictionary = next is AiNativeContainer && next.type == 'ArtDictionary' ? next : null;
      if (dictionary != null) {
        _gradientArtworkMetadata(dictionary, numericRotation: true);
        end = dictionary.end;
        after++;
      }
      if (after < drawing.items.length) {
        if (drawing.items[after] case final AiNativeInstruction style when style.operator == 'XW') {
          continue;
        }
      }
      if (structure.versions.memberships(start: mesh.start, end: end).isNotEmpty ||
          _nativeObjectMetadataComments(drawing, mesh.start, end) ||
          drawing.paths.any((path) => path.start < end && path.end > mesh.start) ||
          drawing.liveShapes.any((shape) => shape.start < end && shape.end > mesh.start)) {
        continue;
      }
      final Map<int, int> fields = {for (final AiNativeMeshField field in mesh.fields) field.start: field.end};
      for (final AiNativeItem command in _pathInterval(drawing.items, mesh.start, end, (item) => item.start)) {
        if (command.end > end || !_sameNativeObjectOwner(node, structure.nodeFor(command))) {
          throw UnsupportedError('Mesh ownership crosses another native object.');
        }
        if (command.start > mesh.start && command.end < mesh.end && (command is! AiNativeInstruction || fields[command.start] != command.end)) {
          throw UnsupportedError('Mesh ownership contains an unqualified command.');
        }
      }
      result.add(AiNativeMeshArtwork._(mesh: mesh, opening: item, dictionary: dictionary, end: end));
    } on AiLimitException {
      rethrow;
    } on UnsupportedError {
      // Unqualified packets remain opaque boundaries to lifecycle operations.
    } on FormatException {
      // Invalid geometry grants no movable native owner.
    } on ArgumentError {
      // Source coordinates outside the authoring contract remain unqualified.
    }
  }
  return result;
}

/// Creates explicit native mesh data while restoring both outgoing state views.
AiNativeDrawing _createNativeMeshArtwork(AiNativeDrawing drawing, AiNativeMeshArtworkDefinition definition, AiNativeGroup? parent, AiLayer? layer) {
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  final List<int> bytes = _nativeMeshDefinitionBytes(definition.mesh, maximum);
  final List<int> metadata = _createdNativeMetadata(drawing, definition.nameBytes, definition.identifierBytes, '\n');
  final AiNativeDrawing result = _insertNativeFlaggedArtwork(
    drawing,
    parent,
    layer,
    (locked: definition.locked, hidden: definition.hidden, opacity: definition.opacity, overprint: definition.overprint),
    bytes,
    metadata,
    definition.bounds,
    transparency: definition.transparency,
  );
  if (result.meshArtwork.length != drawing.meshArtwork.length + 1 || _readNativeMeshes(result.records, true).length != _readNativeMeshes(drawing.records, true).length + 1) {
    throw const FormatException('Mesh creation did not bind exactly one complete native owner.');
  }
  return result;
}

/// Replaces explicit mesh data and flags while retaining source identity metadata.
AiNativeDrawing _replaceNativeMeshArtwork(AiNativeDrawing drawing, AiNativeMeshArtwork owner, AiNativeMeshArtworkDefinition definition, double? rotationRadians) {
  if (!drawing.meshArtwork.contains(owner)) {
    throw ArgumentError('Mesh replacement requires a current complete owner.');
  }
  if (definition.nameBytes != null || definition.identifierBytes != null) {
    throw ArgumentError('Mesh replacement retains its original name and identity.');
  }
  final List<AiSourceEdit> frame = _meshFrameRotationEdits(drawing.records, owner.mesh, rotationRadians);
  final AiNativeContainer? dictionary = owner.dictionary;
  final List<int> metadata = dictionary == null
      ? [for (final AiSourceEdit edit in frame) ...edit.bytes]
      : AiNativeEditor.copyRange(program: drawing.records.program, start: dictionary.start, end: dictionary.end, edits: frame);
  final AiNativeDrawing result = _insertNativeFlaggedArtwork(
    drawing,
    null,
    null,
    (locked: definition.locked, hidden: definition.hidden, opacity: definition.opacity, overprint: definition.overprint),
    _nativeMeshDefinitionBytes(definition.mesh, drawing.records.program.limits.maxDecodedBytes),
    metadata,
    definition.bounds,
    transparency: definition.transparency,
    replacement: (start: owner.start, end: owner.end),
  );
  if (result.meshArtwork.length != drawing.meshArtwork.length) {
    throw const FormatException('Mesh replacement changed unexpected native owners.');
  }
  return result;
}

/// Copies entire qualified mesh owners with fresh values for existing identities.
AiNativeDrawing _duplicateNativeMeshArtwork(AiNativeDrawing drawing, List<AiNativeMeshArtwork> artwork, Map<AiNativeItem, List<int>> identifiers) {
  if (artwork.isEmpty || artwork.toSet().length != artwork.length || artwork.any((owner) => !drawing.meshArtwork.contains(owner))) {
    throw ArgumentError('Mesh copies require distinct current artwork handles.');
  }
  final List<_NativeSubtreeSpan> spans = [for (final AiNativeMeshArtwork owner in artwork) (start: owner.start, end: owner.end)];
  final List<AiSourceEdit> replacements = _subtreeCopyEdits(drawing, artwork, spans, const [], identifiers);
  final AiNativeDrawing result = _pathLifecycleResult(drawing, _copiedNativeSubtrees(AiNativeLayers.decode(drawing: drawing), spans, const [], replacements), drawing.paths.length);
  if (result.meshArtwork.length != drawing.meshArtwork.length + artwork.length) {
    throw const FormatException('Mesh copies changed unexpected native owners.');
  }
  return result;
}
