part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Binds an attachment to existing authoritative metadata, never printing art.
AiNativeContainer? _opacityMaskTarget(AiNativeAppearances model, AiNativeOpacityMaskAttachment attachment) {
  final AiNativeAppearanceArtwork owner = attachment.artwork;
  final AiNativeItem target = attachment.target;
  final AiNativeDrawing drawing = model.structure.drawing;
  if (!identical(owner._owner, model) ||
      target.start < owner.authoring.start ||
      target.end > owner.authoring.end ||
      !(target is AiNativePath && target.isPrivate && drawing.paths.contains(target) || target is AiNativeGroup && target.opening.isPrivate && drawing.groups.contains(target))) {
    throw ArgumentError('Mask targets require current private paths or groups inside their authoring owner.');
  }
  final AiNativeObject object = drawing._objects.forSource(target);
  final AiNativeContainer? dictionary = object.dictionary;
  if (dictionary != null &&
      (!owner.metadata.contains(dictionary) ||
          !(identical(target, owner.authoring) && identical(dictionary, owner.dictionary)) && !_sameNativeObjectOwner(model.structure.nodeFor(target), model.structure.nodeFor(dictionary)))) {
    throw UnsupportedError('Mask targets require uniquely bound authoring metadata.');
  }
  if (dictionary?['AI9_Mask'] != null) {
    throw ArgumentError('A native object cannot receive a second opacity mask.');
  }
  if (owner.liveShape?.alternativeDictionaries.isNotEmpty == true) {
    throw UnsupportedError('New live-shape masks require authoring without alternate metadata copies.');
  }
  return dictionary;
}

/// Serializes flags around the exact host artwork without touching binary bytes.
Uint8List _createdOpacityMaskField(AiNativeOpacityMaskAttachment attachment, bool private) {
  final String prefix = private ? '%_' : '';
  final BytesBuilder result = BytesBuilder(copy: false);
  result.add(latin1.encode('/Mask : ${attachment.settings.linked ? 1 : 0} /Bool (Linked) ,\n$prefix'));
  result.add(attachment.artworkBytes);
  result.add(
    latin1.encode(
      ' (Art) ,\n$prefix${attachment.settings.disabled ? 1 : 0} /Bool (Disabled) , '
      '${attachment.settings.clipping ? 1 : 0} /Bool (Clipping) , '
      '${attachment.settings.inverted ? 1 : 0} /Bool (Inverted) , ;\n$prefix(AI9_Mask) ,\n$prefix',
    ),
  );
  return result.takeBytes();
}

/// Removes the selected field's tokens without consuming the parent terminator.
List<AiSourceEdit> _removedOpacityMaskField(AiNativeRecords records, AiNativeContainer dictionary, AiNativeOpacityMask mask) {
  final List<AiToken> tokens = records._projection.tokens;
  int index = _pathOffset(tokens, mask.record.end, (token) => token.start);
  while (index < tokens.length && tokens[index].kind == .comment) {
    index++;
  }
  if (index >= tokens.length) {
    throw const FormatException('Opacity masks require a complete dictionary key.');
  }
  final AiToken key = tokens[index++];
  if (!const {AiTokenKind.string, AiTokenKind.hexString}.contains(key.kind) || latin1.decode(aiStringBytes(key)) != 'AI9_Mask' || key.end >= dictionary.end) {
    throw const FormatException('Opacity masks require their owned AI9_Mask key.');
  }
  while (index < tokens.length && tokens[index].kind == .comment) {
    index++;
  }
  if (index >= tokens.length) {
    throw const FormatException('Opacity masks require a complete field separator.');
  }
  final AiToken separator = tokens[index];
  if (separator.lexeme != ',' && !(separator.lexeme == ';' && separator.end == dictionary.end)) {
    throw const FormatException('Opacity masks require a complete owned field separator.');
  }
  return [
    AiSourceEdit(start: mask.record.start, end: mask.record.end, bytes: []),
    AiSourceEdit(start: key.start, end: key.end, bytes: []),
    if (separator.lexeme == ',') AiSourceEdit(start: separator.start, end: separator.end, bytes: []),
  ];
}

/// Rejects identity-bearing artwork until its references can join the transaction.
void _opacityMaskWithoutIdentities(AiNativeAppearances model, AiNativeContainer mask) {
  if (model.structure.identifiers.any((identifier) => identifier.field.owner.start >= mask.start && identifier.field.owner.end <= mask.end)) {
    throw UnsupportedError('Mask lifecycle changes require artwork without native object identities.');
  }
}

/// Creates or deletes masks and complete printing owners atomically.
AiNativeAppearances _lifecycleNativeOpacityMasks(
  AiNativeAppearances model,
  List<AiNativeOpacityMaskAttachment> additions,
  List<AiNativeOpacityMask> removals,
  List<AiNativeAppearanceReplacement> artwork,
) {
  if (additions.isEmpty && removals.isEmpty ||
      additions.map((attachment) => attachment.target).toSet().length != additions.length ||
      removals.toSet().length != removals.length ||
      artwork.isEmpty ||
      artwork.any((replacement) => !identical(replacement.artwork._owner, model)) ||
      artwork.map((replacement) => replacement.artwork.printingGroup).toSet().length != artwork.length) {
    throw ArgumentError('Mask lifecycle changes require distinct current targets and complete printing owners.');
  }
  final AiNativeRecords records = model.structure.drawing.records;
  final Set<AiNativeOpacityMaskAttachment> coveredAdditions = {};
  final Set<AiNativeOpacityMask> coveredRemovals = {};
  final Map<AiNativeOpacityMaskAttachment, AiNativeContainer?> dictionaries = {};
  int remaining = records.program.limits.maxDecodedBytes;
  for (final AiNativeOpacityMaskAttachment attachment in additions) {
    dictionaries[attachment] = _opacityMaskTarget(model, attachment);
    remaining -= attachment.artworkBytes.length + 256;
    if (remaining < 0) {
      throw const AiLimitException(message: 'New opacity masks exceed the transaction byte limit.');
    }
  }
  for (final AiNativeAppearanceReplacement replacement in artwork) {
    final AiNativeAppearanceArtwork owner = replacement.artwork;
    if (owner.resource != null || replacement.uses.length != 1 || !identical(replacement.uses.single, owner.use)) {
      throw UnsupportedError('Mask lifecycle changes require complete body appearance owners.');
    }
    final List<AiNativeOpacityMaskAttachment> added = additions.where((attachment) => identical(attachment.artwork.use, owner.use)).toList();
    final List<AiNativeOpacityMask> removed = removals.where(owner.opacityMasks.contains).toList();
    if (added.isEmpty && removed.isEmpty || added.any(coveredAdditions.contains) || removed.any(coveredRemovals.contains)) {
      throw ArgumentError('Every printing replacement must cover distinct selected masks.');
    }
    coveredAdditions.addAll(added);
    coveredRemovals.addAll(removed);
  }
  if (coveredAdditions.length != additions.length || coveredRemovals.length != removals.length) {
    throw ArgumentError('Every mask lifecycle change requires its current complete printing owner.');
  }
  final List<AiSourceEdit> edits = _nativeAppearancePrintingEdits(model, artwork);
  for (final AiNativeOpacityMaskAttachment attachment in additions) {
    final AiNativeContainer? dictionary = dictionaries[attachment];
    if (dictionary == null) {
      final BytesBuilder bytes = BytesBuilder(copy: false);
      bytes.add(latin1.encode('\n%_/ArtDictionary :\n%_'));
      bytes.add(_createdOpacityMaskField(attachment, true));
      bytes.addByte(59);
      edits.add(AiSourceEdit(start: attachment.target.end, end: attachment.target.end, bytes: bytes.takeBytes()));
    } else {
      final AiToken closing = records._projection.tokens.singleWhere((token) => token.end == dictionary.end && token.lexeme == ';');
      int previous = _pathOffset(records._projection.tokens, closing.start, (token) => token.start) - 1;
      while (previous >= 0 && records._projection.tokens[previous].kind == .comment) {
        previous--;
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      if (dictionary.entries.isNotEmpty && records._projection.tokens[previous].lexeme != ',') {
        bytes.add(latin1.encode(', '));
      }
      bytes.add(_createdOpacityMaskField(attachment, records._projection.isPrivate(closing.start)));
      edits.add(AiSourceEdit(start: closing.start, end: closing.start, bytes: bytes.takeBytes()));
    }
  }
  for (final AiNativeOpacityMask mask in removals) {
    _opacityMaskWithoutIdentities(model, mask.record);
    final AiNativeAppearanceArtwork owner = artwork.singleWhere((replacement) => replacement.artwork.opacityMasks.contains(mask)).artwork;
    final AiNativeContainer dictionary = owner.metadata.singleWhere((record) => identical(record['AI9_Mask']?.container, mask.record));
    edits.addAll(_removedOpacityMaskField(records, dictionary, mask));
  }
  final AiNativeAppearances result = _nativeAppearanceResult(model, edits, artwork.map((replacement) => replacement.artwork.use).toList());
  for (final AiNativeAppearanceReplacement replacement in artwork) {
    final AiNativeAppearanceArtwork before = replacement.artwork;
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses[model.uses.indexOf(before.use)]);
    final List<({int position, AiNativeOpacityMask? retained, AiNativeOpacityMaskAttachment? added})> expected = [
      for (final AiNativeOpacityMask mask in before.opacityMasks)
        if (!removals.contains(mask)) (position: mask.record.start, retained: mask, added: null),
      for (final AiNativeOpacityMaskAttachment attachment in additions)
        if (identical(attachment.artwork.use, before.use)) (position: attachment.target.end, retained: null, added: attachment),
    ]..sort((first, second) => first.position.compareTo(second.position));
    if (after.opacityMasks.length != expected.length) {
      throw const FormatException('Mask lifecycle changes disrupted authoring ownership.');
    }
    for (int index = 0; index < expected.length; index++) {
      final AiNativeOpacityMask mask = after.opacityMasks[index];
      if (expected[index].retained case final AiNativeOpacityMask retained) {
        if (!_sameNativeBytes(records.program.bytes.sublist(retained.record.start, retained.record.end), result.structure.drawing.records.program.bytes.sublist(mask.record.start, mask.record.end))) {
          throw const FormatException('Mask lifecycle changes altered an unselected mask.');
        }
      } else {
        final AiNativeOpacityMaskAttachment attachment = expected[index].added!;
        if (!_sameNativeBytes(attachment.artworkBytes, mask.artworkBytes) || attachment.settings._values.entries.any((entry) => mask.settings._values[entry.key] != entry.value)) {
          throw const FormatException('New mask fields differ from the supplied artwork or settings.');
        }
        _opacityMaskWithoutIdentities(result, mask.record);
        _replacementMaskImageIdentifiers(records, result.structure.drawing.records, mask.record);
      }
    }
  }
  return result;
}
