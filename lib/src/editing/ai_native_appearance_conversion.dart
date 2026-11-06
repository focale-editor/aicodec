part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Retains one ordinary owner's identity and slot while changing its paint model.
AiNativeAppearances _convertNativeAppearancePath(
  AiNativeAppearances model,
  AiNativePath path,
  AiArtworkPath artwork,
  AiBoundingBox bounds,
  List<int> styleNameBytes,
  List<int> printingBytes,
  bool hidden,
) {
  if (artwork.fill != null || artwork.stroke != null) {
    throw ArgumentError('Converted appearance geometry must be unpainted; its named style owns the paints.');
  }
  if (styleNameBytes.isEmpty || styleNameBytes.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('A converted appearance requires a nonempty literal style name.');
  }
  final AiNativeDrawing drawing = model.structure.drawing;
  final AiProgram program = drawing.records.program;
  final List<AiNativeAppearanceArtwork> retained = _nativeBodyAppearanceArtwork(model);
  if (retained.any((owner) => path.start >= owner.start && path.end <= owner.end)) {
    throw UnsupportedError('Appearance descendants require their complete native and printing transaction.');
  }
  final AiNativeInstruction? count = _ordinaryPathCounts(drawing, [path], ownership: model.structure, appearanceArtwork: retained)[path];
  final AiNativeObject object = _ordinaryObject(drawing, path);
  if (object.liveShape != null) {
    throw UnsupportedError('Dynamic shapes require their native parameter conversion contract.');
  }
  final _NativeSubtreeSpan source = (start: count?.start ?? path.start, end: object.end);
  final List<_NativeSubtreeSpan> neutral = _nativeNeutralArtwork(drawing);
  final Map<int, _NativeShapeInputs> original = _shapeCopyInputs(drawing, [source.start, source.end], clipping: true, neutralSpans: neutral, appearanceArtwork: retained);
  _printingFragment(printingBytes, program.limits);
  final _NativeDocumentBytes bytes = _NativeDocumentBytes(maximum: program.limits.maxDecodedBytes);
  bytes.text('\n${artwork.locked ? 1 : 0} A\n${hidden ? 1 : 0} Xw\n');
  bytes.add(printingBytes);
  bytes.text('\n6 () XW\n');
  _writeNativeAppearancePath(bytes, drawing, AiNativePathDefinition(artwork: artwork, bounds: bounds, counted: count != null, hidden: hidden));
  // Postfix metadata already belongs to the private native interpretation.
  // Copy it verbatim instead of allocating or rewriting the original XMLUID.
  bytes.add(Uint8List.sublistView(program.bytes, path.end, object.end));
  bytes.text('\n1 ');
  bytes.add(_nativeLiteralString(styleNameBytes, program.limits.maxDecodedBytes));
  bytes.text(' XW\n');
  final Uint8List replacement = bytes.takeBytes();
  final AiNativeDrawing provisional = AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: program,
        edits: [AiSourceEdit(start: source.start, end: source.end, bytes: replacement)],
      ),
    ),
  );
  final AiNativeAppearances created = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: provisional));
  final _NativeSubtreeSpan span = (start: source.start, end: source.start + replacement.length);
  final AiNativeAppearanceArtwork owner = _createdAppearanceOwner(created, span);
  if (owner.path == null ||
      owner.nestedUses.isNotEmpty ||
      owner.opacityMasks.isNotEmpty ||
      created.styles.length != model.styles.length ||
      created.uses.length != model.uses.length + 1 ||
      created.structure.identifiers.length != model.structure.identifiers.length ||
      provisional.records.artboards.length != drawing.records.artboards.length ||
      provisional.records.program.layers.length != program.layers.length) {
    throw const FormatException('Path conversion changed unrelated native ownership.');
  }
  final List<AiNativeInstruction> commands = _pathInterval(provisional.items, span.start, span.end, (item) => item.start).whereType<AiNativeInstruction>().toList();
  final _NativeShapeAccess access = _nativeAppearanceArtworkAccess(provisional, owner, commands);
  final _NativeShapeInputs incoming = original[source.start]!;
  if (access.nativeReads.any((key) => !incoming.native.containsKey(key)) || access.printingReads.any((key) => !incoming.printing.containsKey(key))) {
    throw UnsupportedError('Converted appearance requires explicit scalar inputs instead of unknown inherited defaults.');
  }
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(
    provisional,
    [span.start, span.end],
    clipping: true,
    neutralSpans: _nativeNeutralArtwork(provisional),
    appearanceArtwork: _nativeBodyAppearanceArtwork(created),
  );
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    provisional,
    span,
    commands,
    const {},
    access,
    states[span.start]!,
    states[span.end]!,
    incoming,
    original[source.end]!,
    maxBytes: program.limits.maxDecodedBytes,
  );
  // Internal inputs were checked against the unchanged source entry above.
  // Provisional command offsets are not handles into the original program.
  _sourceFollowingDependencies(
    drawing,
    {
      source: (commands: [], styles: {}, prefix: [], suffix: [], unresolved: placed.replacement.unresolved, printingUnresolved: placed.replacement.printingUnresolved, discard: false),
    },
    retainedArtwork: retained,
    clipping: true,
    patterns: created._patternNames,
  );
  final AiNativeDrawing result = _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: source.start, end: source.end, bytes: placed.bytes),
      ...AiNativeEditor.includeBoundsEdits(program: program, bounds: bounds),
    ],
    paths: provisional.paths.length,
    groups: provisional.groups.length,
    liveShapes: drawing.liveShapes.length,
  );
  final AiNativeAppearances updated = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: result));
  final AiNativeAppearanceArtwork converted = updated.artworkFor(use: updated.uses[created.uses.indexOf(owner.use)]);
  final AiNativeObject after = AiNativeObjects.decode(drawing: result).forSource(converted.path!);
  if (!_sameNativeBytes(result.records.program.bytes.sublist(after.dictionary?.start ?? after.end, after.end), program.bytes.sublist(object.dictionary?.start ?? object.end, object.end))) {
    throw const FormatException('Path conversion changed retained object metadata.');
  }
  return updated;
}
