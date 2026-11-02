part of 'package:aicodec/src/model/ai_native_records.dart';

/// Complete ordinary image boundaries and their retained instruction identities.
typedef _NativeImageOwner = ({AiNativeItem image, AiNativeInstruction instruction, AiNativeContainer? dictionary, _NativeSubtreeSpan span});

/// Returns framed embedded and linked images without promoting opaque neighbors.
List<_NativeImageOwner> _nativeImageOwners(AiNativeDrawing drawing) => drawing._imageOwners;

/// Resolves complete image owners once without qualifying opaque neighboring data.
List<_NativeImageOwner> _readNativeImageOwners(AiNativeDrawing drawing) {
  final Set<_NativeSubtreeSpan> qualified = _imageCreationNeutralSpans(drawing).toSet();
  final AiNativeStructure structure = drawing._objects.structure;
  final List<_NativeImageOwner> owners = [];
  final List<AiNativeItem> images = [..._readNativeRasters(drawing.records, true), ..._readNativePlacements(drawing.records, true)]..sort((a, b) => a.start.compareTo(b.start));
  for (final AiNativeItem image in images) {
    final AiNativeInstruction instruction;
    final AiNativeContainer? dictionary;
    final bool printable;
    if (image is AiNativeRaster) {
      instruction = image.instruction;
      dictionary = image.dictionary;
      printable = image.isPrintable(program: drawing.records.program);
    } else {
      final AiNativePlacedObject placed = image as AiNativePlacedObject;
      instruction = placed.instruction;
      dictionary = placed.dictionary;
      printable = placed.isPrintable(program: drawing.records.program);
    }
    final _NativeSubtreeSpan span = (start: image.start, end: dictionary?.end ?? image.end);
    if (!qualified.contains(span) || !printable || structure.versions.memberships(start: span.start, end: span.end).isNotEmpty) {
      continue;
    }
    final AiNativeStructureNode? node = structure.nodes.where((node) => node.kind == .instruction && node.start == instruction.start).singleOrNull;
    if (node == null || _artworkParents(structure, structure.parentOf(node)).any((parent) => parent.kind != .layer && parent.kind != .group)) {
      continue;
    }
    final AiNativeItem? next = drawing.items.where((item) => item.start >= image.end).firstOrNull;
    final int end = dictionary?.end ?? (next is AiNativeInstruction && next.operator == 'N' && next.operands.isEmpty && !next.isPrivate ? next.end : image.end);
    owners.add((image: image, instruction: instruction, dictionary: dictionary, span: (start: image.start, end: end)));
  }
  return owners;
}

/// Declares scalar input consumed by either image family, including stencil paint.
Set<String> _nativeImageReads(AiNativeItem image) => {'A', 'Xw', 'Ap', 'D', 'XR', 'O', 'Xy', if (image is AiNativeRaster && image.imageMask) 'fill'};

/// Resolves a raster's lexical instruction without equating foreign snapshots.
AiNativeStructureNode _nativeRasterNode(AiNativeStructure structure, AiNativeRaster image) => structure.nodes.singleWhere((node) => node.kind == .instruction && node.start == image.instruction.start);

/// Copies native samples and qualified metadata with fresh object/cache identities.
AiNativeDrawing _copyNativeRaster(
  AiNativeDrawing drawing,
  AiNativeRasters source,
  AiNativeRaster image,
  List<double> matrix,
  AiNativeImageAttributes attributes,
  AiNativeGroup? parent,
  AiLayer? layer,
) {
  source.validateSourceLayout(image: image);
  if (attributes.identifierBytes == null) {
    throw ArgumentError('Copied images require a fresh artwork identity.');
  }
  final AiNativeDrawing original = AiNativeDrawing.decode(records: source.records);
  final List<_NativeSubtreeSpan> neutral = _imageCreationNeutralSpans(original);
  _nativeImageAttributeOwner(original, image, neutral);
  AiColor? stencil;
  if (image.imageMask) {
    final _NativeShapeInputs state = _shapeCopyInputs(original, [image.start], neutralSpans: neutral)[image.start]!;
    final AiNativeInstruction? paint = state.native['fill'];
    if (paint == null || !_sameNativeArtworkState(paint, state.printing['fill']) || !const {'g', 'Xa', 'k'}.contains(paint.operator)) {
      throw UnsupportedError('Copied stencils require one explicit process paint in both source representations.');
    }
    final AiColorSpace space = switch (paint.operator) {
      'g' => AiColorSpace.gray,
      'k' => AiColorSpace.cmyk,
      _ => AiColorSpace.rgb,
    };
    if (paint.numbers!.length !=
        switch (space) {
          AiColorSpace.gray => 1,
          AiColorSpace.rgb => 3,
          AiColorSpace.cmyk => 4,
        }) {
      throw UnsupportedError('Copied stencil paint requires a single process alternative.');
    }
    stencil = AiColor(space: space, channels: paint.numbers!);
  }
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  final AiNativeRasters placed = source.setPlacement(image: image, matrix: matrix, rotationRadians: image.frameRotationRadians);
  final AiNativeRaster selected = placed.images[source.images.indexOf(image)];
  final _RasterIdentifiers identities = _RasterIdentifiers(records: drawing.records);
  identities._used.addAll(_RasterIdentifiers(records: source.records)._used);
  final List<String> fields = [];
  for (final AiNativeEntry entry in selected.dictionary?.entries ?? const <AiNativeEntry>[]) {
    if (entry.key == 'AI10_ArtUID' || attributes.nameBytes != null && const {'AIArtName', 'Object name'}.contains(entry.key)) {
      continue;
    }
    final String value;
    final String type;
    if (const {'AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID'}.contains(entry.key)) {
      value = '(${identities.next()})';
      type = 'String';
    } else if (entry.stringBytes case final Uint8List bytes) {
      value = latin1.decode(_nativeLiteralString(bytes, maximum));
      type = entry.type!;
    } else {
      value = entry.number!.toString();
      type = entry.type!;
    }
    fields.add('$value /$type (${entry.key}) ,');
  }
  final List<int> path = aiStringBytes(selected.commands.singleWhere((command) => command.operator == 'XG').operands.first);
  if (path.isNotEmpty) {
    _validatePlacedLinkInputs(path, null, null, maximum);
  }
  return _insertNativeFlaggedArtwork(
    drawing,
    parent,
    layer,
    (locked: attributes.locked, hidden: attributes.hidden, opacity: attributes.opacity, overprint: attributes.overprint),
    [...placed.records.program.bytes.sublist(selected.start, selected.end), 10, 78],
    _createdImageMetadata(drawing, attributes, fields),
    _nativeImageBounds(matrix, [0, -image.height.toDouble(), image.width.toDouble(), 0]),
    transparency: attributes.transparency,
    stencilColor: stencil,
    dependencies: path.isEmpty ? const [] : _placedFileEdits(AiNativePlacements.decode(records: drawing.records), null, replacement: latin1.decode(path)),
  );
}

/// Copies an external reference and its exact saved preview under a fresh identity.
AiNativeDrawing _copyNativePlacement(
  AiNativeDrawing drawing,
  AiNativePlacements source,
  AiNativePlacedObject object,
  List<double> matrix,
  AiNativeImageAttributes attributes,
  AiNativeGroup? parent,
  AiLayer? layer,
) {
  if (!source.objects.contains(object) || attributes.identifierBytes == null) {
    throw ArgumentError('Copied links require an owned source and a fresh artwork identity.');
  }
  object.validateRasterLayout();
  final AiNativeDrawing original = AiNativeDrawing.decode(records: source.records);
  _nativeImageAttributeOwner(original, object, _imageCreationNeutralSpans(original));
  final AiNativePlacements placed = source.setPlacement(object: object, matrix: matrix, rotationRadians: object.frameRotationRadians);
  final AiNativePlacedObject selected = placed.objects[source.objects.indexOf(object)];
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  final List<String> fields = [];
  for (final AiNativeEntry entry in selected.dictionary?.entries ?? const <AiNativeEntry>[]) {
    if (entry.key == 'AI10_ArtUID' || attributes.nameBytes != null && const {'AIArtName', 'Object name'}.contains(entry.key)) {
      continue;
    }
    final String value = entry.stringBytes == null ? entry.number!.toString() : latin1.decode(_nativeLiteralString(entry.stringBytes!, maximum));
    fields.add('$value /${entry.type} (${entry.key}) ,');
  }
  return _insertNativeFlaggedArtwork(
    drawing,
    parent,
    layer,
    (locked: attributes.locked, hidden: attributes.hidden, opacity: attributes.opacity, overprint: attributes.overprint),
    [...placed.records.program.bytes.sublist(selected.start, selected.end), 10, 78],
    _createdImageMetadata(drawing, attributes, fields),
    _nativeImageBounds(matrix, object.bounds),
    transparency: attributes.transparency,
    dependencies: _placedFileEdits(AiNativePlacements.decode(records: drawing.records), null, replacement: latin1.decode(object.pathBytes)),
  );
}
