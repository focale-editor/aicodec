part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Retains observable boundary values without replaying deleted drawing scopes.
({List<int> bytes, _NativeSourceReplacement replacement}) _removedAppearanceState(
  _NativeShapeAccess access,
  _NativeShapeInputs before,
  _NativeShapeInputs after,
  int maximum,
) {
  if (maximum < 1) {
    throw const AiLimitException(message: 'Removed appearance state exceeds the native byte limit.');
  }
  final List<_NativeShapeReplay> replay = [];
  final Set<String> unresolved = {};
  final Set<String> printingUnresolved = {};
  final Set<String> publicWrites = {};
  final StringBuffer bytes = StringBuffer('\n');

  /// Bounds retained scalar state under the complete transaction's output budget.
  void append(AiNativeInstruction value, {required bool private}) {
    final String text = _shapeStateText(value, private: private);
    if (bytes.length + text.length > maximum) {
      throw const AiLimitException(message: 'Removed appearance state exceeds the native byte limit.');
    }
    bytes.write(text);
    replay.add((value: value, private: private));
  }

  for (final String key in access.printingWrites) {
    if (after.printing[key] case final AiNativeInstruction value) {
      append(value, private: false);
      publicWrites.add(key);
    } else if (!_sameShapeAttribute(before.printing, before.printingOrigins, after.printing, after.printingOrigins, key)) {
      printingUnresolved.add(key);
    }
  }
  for (final String key in {...access.nativeWrites, ...publicWrites}) {
    if (after.native[key] case final AiNativeInstruction value) {
      // A public assignment also changes the native interpretation. Restore its
      // separate final value even when a private clipping scope inherited it.
      append(value, private: true);
    } else if (publicWrites.contains(key) || !_sameShapeAttribute(before.native, before.nativeOrigins, after.native, after.nativeOrigins, key)) {
      unresolved.add(key);
    }
  }
  return (
    bytes: latin1.encode(bytes.toString()),
    replacement: (commands: [], styles: {}, prefix: replay, suffix: [], unresolved: unresolved, printingUnresolved: printingUnresolved, discard: true),
  );
}

/// Deletes disjoint complete owners while retaining shared styles and neighbors.
AiNativeAppearances _removeNativeAppearanceArtwork(AiNativeAppearances model, List<AiNativeAppearanceArtwork> artwork) {
  final List<AiNativeAppearanceArtwork> selected = _selectedBodyAppearanceArtwork(model, artwork);
  if (selected.any((owner) => owner.leaves.values.any((leaf) => leaf.text != null))) {
    throw UnsupportedError('Text appearance lifecycle requires updating its global story resources first.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);

  /// Selects only descendants whose entire source ownership leaves with the pair.
  bool removed(int start, int end) => selected.any((owner) => start >= owner.start && end <= owner.end);

  final List<AiNativeObjectIdentifier> identities = model.structure.identifiers.where((identity) => removed(identity.field.owner.start, identity.field.owner.end)).toList();
  if (identities.isNotEmpty) {
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
    final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
    _nativeRemovalReferences(
      layers,
      identities,
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
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    drawing,
    [
      for (final AiNativeAppearanceArtwork owner in selected) ...[owner.start, owner.end],
    ],
    clipping: true,
    appearanceArtwork: retained,
  );
  final List<AiSourceEdit> edits = [];
  final Map<_NativeSubtreeSpan, _NativeSourceReplacement> replacements = {};
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final AiNativeAppearanceArtwork owner in selected) {
    final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(drawing, owner, owner._commands);
    final ({List<int> bytes, _NativeSourceReplacement replacement}) state = _removedAppearanceState(access, states[owner.start]!, states[owner.end]!, remaining);
    edits.add(AiSourceEdit(start: owner.start, end: owner.end, bytes: state.bytes));
    replacements[(start: owner.start, end: owner.end)] = state.replacement;
    remaining -= state.bytes.length;
  }
  _sourceFollowingDependencies(drawing, replacements, retainedArtwork: retained, clipping: true, patterns: model._patternNames);
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    edits,
    appearanceLeaves: true,
    paths: drawing.paths.where((path) => !removed(path.start, path.end)).length,
    groups: drawing.groups.where((group) => !removed(group.start, group.end)).length,
    liveShapes: drawing.liveShapes.where((shape) => !removed(shape.start, shape.end)).length,
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  final List<AiNativeResourceUse> uses = model.uses.where((use) => !removed(use.instruction.start, use.instruction.end)).toList();
  if (updated.styles.length != model.styles.length || updated.uses.length != uses.length || updated.structure.identifiers.length != model.structure.identifiers.length - identities.length) {
    throw const FormatException('Removing appearance artwork disrupted retained resources or identities.');
  }
  for (final (int, AiNativeResourceUse) entry in uses.indexed) {
    final AiNativeResourceUse use = updated.uses[entry.$1];
    if (!_sameNativeBytes(use.nameBytes, entry.$2.nameBytes) || use.instruction.isPrivate != entry.$2.instruction.isPrivate) {
      throw const FormatException('Removing appearance artwork changed a retained style application.');
    }
    if (retained.any((owner) => identical(owner.use, entry.$2))) {
      updated.artworkFor(use: use);
    }
  }
  return updated;
}
