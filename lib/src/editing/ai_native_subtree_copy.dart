part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Assigns fresh identities to ordinary artwork and every complete pair dictionary.
List<AiSourceEdit> _subtreeCopyEdits(
  AiNativeDrawing drawing,
  List<AiNativeItem> sources,
  List<_NativeSubtreeSpan> spans,
  List<_NativeShapeBundle> pairs,
  Map<AiNativeItem, List<int>> identifiers, {
  Set<String>? reserved,
  int? maxBytes,
}) {
  if (_nativeImageOwners(drawing).any((owner) => spans.any((span) => owner.span.start >= span.start && owner.span.end <= span.end))) {
    throw UnsupportedError('Copies containing raster images require fresh image and sample identities.');
  }
  final List<AiNativeObjectIdentifier> saved = drawing._objects.structure.identifiers
      .where((identifier) => spans.any((span) => identifier.field.owner.start >= span.start && identifier.field.owner.end <= span.end))
      .toList();
  if (saved.map((identifier) => latin1.decode(identifier.bytes)).toSet().length != saved.length) {
    throw UnsupportedError('Copying repeated subtree identities requires an explicit alias contract.');
  }
  final Map<AiNativeItem, AiNativeObjectIdentifier> expected = {
    for (final AiNativeObject object in _selectedNativeObjects(drawing, sources))
      if (object.identifier != null && !pairs.any((pair) => object.source.start >= pair.start && object.source.end <= pair.shape.end)) object.source: object.identifier!,
    for (final AiNativeGradientArtwork owner in drawing.gradientArtwork)
      if (owner.identifierBytes != null && spans.any((span) => owner.start >= span.start && owner.end <= span.end))
        owner: saved.singleWhere((identifier) => identical(identifier.field.owner.source, owner.dictionary)),
    for (final AiNativeMeshArtwork owner in drawing.meshArtwork)
      if (owner.identifierBytes != null && spans.any((span) => owner.start >= span.start && owner.end <= span.end))
        owner: saved.singleWhere((identifier) => identical(identifier.field.owner.source, owner.dictionary)),
    for (final AiNativeObjectIdentifier identifier in saved)
      if (pairs.any((pair) => identifier.field.owner.start >= pair.start && identifier.field.owner.end <= pair.shape.end)) identifier.field.owner.source as AiNativeContainer: identifier,
  };
  if (identifiers.length != expected.length || identifiers.keys.any((owner) => !expected.containsKey(owner))) {
    throw ArgumentError('Subtree copies require fresh identities for exactly their ordinary objects and paired metadata dictionaries.');
  }
  if (expected.isEmpty) {
    return [];
  }
  final Set<String> names = reserved ?? _nativeIdentityNames(drawing._objects.structure);
  final List<AiSourceEdit> edits = [];
  int remaining = maxBytes ?? drawing.records.program.limits.maxDecodedBytes;
  for (final MapEntry<AiNativeItem, AiNativeObjectIdentifier> entry in expected.entries) {
    final AiSourceEdit edit = _nativeIdentityEdit(entry.value, identifiers[entry.key]!, names, remaining);
    edits.add(edit);
    remaining -= edit.bytes.length;
  }
  return edits;
}

/// Tracks each stream's input reads and possible output changes across a subtree.
_NativeShapeAccess _subtreeCopyAccess(
  AiNativeDrawing drawing,
  List<AiNativeInstruction> ordinary,
  List<_NativeShapeBundle> pairs,
  Map<int, _NativeShapeInputs> states, {
  List<AiNativeAppearanceArtwork> appearanceArtwork = const [],
}) {
  if (appearanceArtwork.isNotEmpty) {
    return _nativeArtworkCommandsAccess(drawing, _subtreeCommands(ordinary, pairs, appearanceArtwork), {
      for (final _NativeShapeBundle pair in pairs) pair.shape.end: (reads: pair.styleReads, writes: pair.styleWrites, assigned: _restoredShapeStyle(pair, states[pair.shape.end]!).keys.toSet()),
      for (final AiNativeAppearanceArtwork owner in appearanceArtwork)
        for (final AiNativeResourceUse use in [owner.use, ...owner.nestedUses]) use.instruction.end: _nativeAppearanceAccessStyle(owner, use),
    }, printingImages: appearanceArtwork.expand((owner) => owner.printingRasters));
  }
  final List<AiNativeInstruction> commands = [...ordinary, for (final _NativeShapeBundle pair in pairs) ...pair.commands]..sort((first, second) => first.start.compareTo(second.start));
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  final Map<int, _NativeShapeBundle> styles = {for (final _NativeShapeBundle pair in pairs) pair.shape.end: pair};
  late final Map<int, AiNativeItem> images = {for (final _NativeImageOwner owner in _nativeImageOwners(drawing)) owner.instruction.start: owner.image};
  final Set<String> nativeWrites = {};
  final Set<String> printingWrites = {};
  final Set<String> nativeReads = {};
  final Set<String> printingReads = {};
  final Set<String> possibleWrites = {};
  for (final AiNativeInstruction command in commands) {
    final String? key = _nativeArtworkStateKey(command);
    if (key != null) {
      nativeWrites.add(key);
      if (!command.isPrivate) {
        printingWrites.add(key);
      }
      continue;
    }
    final _NativeShapeBundle? style = styles[command.end];
    final Set<String> reads = paths.containsKey(command.start)
        ? _shapeCopyReads(drawing, paths[command.start]!)
        : const {'aikit:text', 'aikit:mesh', 'aikit:symbol'}.contains(command.operator)
        ? _nativeArtworkStateKeys
        : const {'XI', '`'}.contains(command.operator)
        ? _nativeImageReads(images[command.start] ?? (throw UnsupportedError('Subtree image reads require qualified raster ownership.')))
        : const {'u', '*u'}.contains(command.operator)
        ? {'A', 'Xw'}
        : _marker(command, 6)
        ? {'Xy'}
        : style != null && _marker(command, 1)
        ? style.styleReads
        : {};
    nativeReads.addAll(reads.difference(nativeWrites));
    if (!command.isPrivate && command.operator != 'XW') {
      printingReads.addAll(reads.difference(printingWrites));
    }
    if (style != null && _marker(command, 1)) {
      // A hidden filter may leave a value unchanged. Potential style effects
      // cannot conceal a later read of the subtree's inherited input.
      possibleWrites.addAll(style.styleWrites);
      nativeWrites.addAll(_restoredShapeStyle(style, states[style.shape.end]!).keys);
    }
  }
  return (printingReads: printingReads, nativeReads: nativeReads, printingWrites: printingWrites, nativeWrites: {...nativeWrites, ...possibleWrites});
}

/// Repeats exact complete subtrees with fresh metadata and restored source inputs.
List<AiSourceEdit> _copiedNativeSubtrees(
  AiNativeLayers model,
  List<_NativeSubtreeSpan> spans,
  List<_NativeShapeBundle> pairs,
  List<AiSourceEdit> replacements, {
  bool groups = false,
}) {
  final AiNativeDrawing drawing = model.drawing;
  if (drawing.records.containers.any((record) => record.type == 'AI11Text' && spans.any((span) => record.start >= span.start && record.end <= span.end))) {
    throw UnsupportedError('Copies containing text require fresh stories and frame resources.');
  }
  final Map<int, _NativeShapeInputs> inputs = _shapeCopyInputs(drawing, [...spans.map((span) => span.start), ...pairs.map((pair) => pair.shape.end)]);
  final List<AiSourceEdit> edits = [];
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final _NativeSubtreeSpan span in spans) {
    final List<_NativeShapeBundle> selected = pairs.where((pair) => pair.start >= span.start && pair.shape.end <= span.end).toList();
    final List<AiNativeInstruction> ordinary = _subtreeOrdinaryCommands(model, span.start, span.end, selected, groups: groups);
    final _NativeShapeAccess access = _subtreeCopyAccess(drawing, ordinary, selected, inputs);
    final List<int> prefix = _nativeCopyPrefix(access, inputs[span.start]!, remaining - 1);
    final List<int> copied = _nativeSourceSpans(drawing.records.program, [span], remaining - prefix.length - 1, edits: replacements);
    final List<int> bytes = [10, ...prefix, ...copied];
    edits.add(AiSourceEdit(start: span.end, end: span.end, bytes: bytes));
    remaining -= bytes.length;
  }
  return edits;
}
