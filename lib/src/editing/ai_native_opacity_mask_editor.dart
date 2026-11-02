part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies existing mask artwork using the retained resource grammar.
AiNativeOpacityMask _qualifiedAppearanceMask(AiNativeAppearances model, AiNativeContainer record) => model._opacityMasks.putIfAbsent(record, () {
  final AiNativeOpacityMask mask = AiNativeOpacityMask.decode(records: model.structure.drawing.records, record: record);
  // Validate the lazy artwork view before publishing a bound mask handle.
  // ignore: unnecessary_statements
  mask.artworkDrawing;
  return mask;
});

/// Reads native mask artwork using the same grammar as retained resource masks.
AiNativeDrawing _nativeOpacityMaskDrawing(AiNativeRecords records, AiNativeContainer record) {
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: records));
  final _ArtboardResourceInspection scope = _ArtboardResourceInspection(layers: layers, setupOnly: false);
  _artboardOpacityMask(scope, record);
  // Named paints/styles need dependency coverage beyond a mask-local mutation.
  if (layers.structure.resourceUses.any((use) => use.instruction.start >= record.start && use.instruction.end <= record.end)) {
    throw UnsupportedError('Mask appearance editing does not cover named resource dependencies.');
  }
  for (final AiNativeDrawing drawing in scope.drawings) {
    _artboardResourceArtwork(layers, drawing, const {}, const {});
  }
  return scope.drawings.last;
}

/// Ignores only already-qualified mask and image spans in owner annotations.
bool _nativeAppearanceMetadataComments(AiNativeDrawing drawing, int start, int end, List<AiNativeContainer> masks, {List<AiNativeRaster> rasters = const []}) =>
    _pathInterval(drawing.records._projection.tokens, start, end, (token) => token.start).any(
      (token) =>
          !masks.any((mask) => token.start >= mask.start && token.end <= mask.end) &&
          !rasters.any((image) => token.start >= image.start && token.end <= image.end) &&
          (token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'))),
    );

/// Changes source-owned fields and derived groups in one bounded transaction.
AiNativeAppearances _editNativeOpacityMasks(AiNativeAppearances model, List<AiNativeOpacityMaskChange> changes, List<AiNativeAppearanceReplacement> artwork) {
  if (changes.isEmpty ||
      changes.map((change) => change.mask).toSet().length != changes.length ||
      artwork.isEmpty ||
      artwork.any((replacement) => !identical(replacement.artwork._owner, model)) ||
      artwork.map((replacement) => replacement.artwork.printingGroup).toSet().length != artwork.length) {
    throw ArgumentError('Mask edits require distinct current masks and printing owners.');
  }
  final Map<AiNativeOpacityMask, AiNativeAppearanceReplacement> owners = {};
  for (final AiNativeAppearanceReplacement replacement in artwork) {
    if (replacement.artwork.resource != null || replacement.uses.length != 1 || !identical(replacement.uses.single, replacement.artwork.use)) {
      throw UnsupportedError('Mask edits require complete body appearance owners.');
    }
    final List<AiNativeOpacityMask> selected = replacement.artwork.opacityMasks.where((mask) => changes.any((change) => identical(change.mask, mask))).toList();
    if (selected.isEmpty) {
      throw ArgumentError('Every supplied printing owner must cover a selected native mask.');
    }
    for (final AiNativeOpacityMask mask in selected) {
      if (owners.containsKey(mask)) {
        throw ArgumentError('A mask cannot have two printing owners.');
      }
      owners[mask] = replacement;
    }
  }
  if (changes.any((change) => !owners.containsKey(change.mask))) {
    throw ArgumentError('Every mask requires its current complete printing owner.');
  }
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, artwork);
  for (final AiNativeOpacityMaskChange change in changes) {
    final AiNativeOpacityMask mask = change.mask;
    for (final MapEntry<String, bool> value in change.settings?._values.entries ?? <MapEntry<String, bool>>[]) {
      final AiNativeItem token = mask._fields[value.key]!.items.single;
      edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: [if (value.value) 49 else 48]));
    }
    if (change.artworkBytes case final Uint8List bytes) {
      if (_sameNativeBytes(bytes, mask.artworkBytes)) {
        continue;
      }
      if (model.structure.identifiers.any((identifier) => identifier.field.owner.start >= mask.record.start && identifier.field.owner.end <= mask.record.end)) {
        throw UnsupportedError('Replacing mask artwork cannot discard native identities.');
      }
      edits.add(AiSourceEdit(start: mask.artwork.items.first.start, end: mask.artwork.items.last.end, bytes: bytes));
    }
  }
  final AiNativeAppearances result = _nativeAppearanceResult(model, edits, artwork.map((replacement) => replacement.artwork.use).toList());
  for (final AiNativeAppearanceReplacement replacement in artwork) {
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses[model.uses.indexOf(replacement.artwork.use)]);
    if (after.opacityMasks.length != replacement.artwork.opacityMasks.length) {
      throw const FormatException('Mask changes disrupted native ownership.');
    }
    for (final AiNativeOpacityMask mask in after.opacityMasks) {
      final AiNativeOpacityMask before = replacement.artwork.opacityMasks[after.opacityMasks.indexOf(mask)];
      if (changes.any((change) => identical(change.mask, before) && change.artworkBytes != null && !_sameNativeBytes(change.artworkBytes!, before.artworkBytes))) {
        _replacementMaskImageIdentifiers(model.structure.drawing.records, result.structure.drawing.records, mask.record);
        if (result.structure.identifiers.any((identifier) => identifier.field.owner.start >= mask.record.start && identifier.field.owner.end <= mask.record.end)) {
          throw UnsupportedError('Replacement mask artwork cannot introduce native identities.');
        }
      }
    }
  }
  return result;
}

/// Requires fresh cache identities for changed image payloads, when supplied.
void _replacementMaskImageIdentifiers(AiNativeRecords before, AiNativeRecords after, AiNativeContainer mask) {
  final Set<String> retained = {
    for (final AiNativeContainer record in before.containers)
      for (final AiNativeEntry entry in record.entries)
        if (const {'AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'}.contains(entry.key) && entry.text() != null) entry.text()!.toLowerCase(),
  };
  final Map<String, int> counts = {};
  for (final AiNativeContainer record in after.containers) {
    for (final AiNativeEntry entry in record.entries) {
      if (const {'AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'}.contains(entry.key) && entry.text() != null) {
        counts.update(entry.text()!.toLowerCase(), (value) => value + 1, ifAbsent: () => 1);
      }
    }
  }
  for (final AiNativeContainer record in after.containers.where((record) => record.start > mask.start && record.end < mask.end)) {
    for (final AiNativeEntry entry in record.entries) {
      if (!const {'AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'}.contains(entry.key)) {
        continue;
      }
      final String? value = entry.text();
      if (value == null || !_rasterIdentifier.hasMatch(value) || retained.contains(value.toLowerCase()) || counts[value.toLowerCase()] != 1) {
        throw UnsupportedError('Replacement mask images require absent or fresh unique native cache identifiers.');
      }
    }
  }
}
