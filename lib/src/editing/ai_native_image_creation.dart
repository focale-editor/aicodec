part of 'package:aicodec/src/model/ai_native_records.dart';

/// Validates portable nonsingular placement and computes exact corner bounds.
AiBoundingBox _nativeImageBounds(List<double> matrix, List<double> local) {
  if (matrix.length != 6 || local.length != 4 || [...matrix, ...local].any((value) => !value.isFinite || value.abs() > 9007199254740991) || local[0] >= local[2] || local[1] >= local[3]) {
    throw ArgumentError('Image creation requires bounded matrix and rectangle values.');
  }
  final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
  if (!determinant.isFinite || determinant == 0) {
    throw ArgumentError('Image creation requires a nonsingular placement.');
  }
  final List<double> horizontal = [];
  final List<double> vertical = [];
  for (final double x in [local[0], local[2]]) {
    for (final double y in [local[1], local[3]]) {
      horizontal.add(matrix[0] * x + matrix[2] * y + matrix[4]);
      vertical.add(matrix[1] * x + matrix[3] * y + matrix[5]);
    }
  }
  if ([...horizontal, ...vertical].any((value) => !value.isFinite || value.abs() > 9007199254740991) ||
      horizontal.reduce(min) == horizontal.reduce(max) ||
      vertical.reduce(min) == vertical.reduce(max)) {
    throw ArgumentError('Image corners exceed portable coordinate precision.');
  }
  return AiBoundingBox(left: horizontal.reduce(min), bottom: vertical.reduce(min), right: horizontal.reduce(max), top: vertical.reduce(max));
}

/// Inserts process samples and fresh plane identities using the common raster writer.
AiNativeDrawing _createNativeRaster(AiNativeDrawing drawing, AiNativeRasterDefinition definition, AiNativeGroup? parent, AiLayer? layer) {
  final AiNativeRasterSamples samples = definition.samples;
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  final _RasterIdentifiers identifiers = _RasterIdentifiers(records: drawing.records);
  final String colorIdentity = identifiers.next();
  final String? alphaIdentity = samples.alphaSamples == null ? null : identifiers.next();
  final List<int> metadata = _createdImageMetadata(drawing, definition.attributes, [
    '($colorIdentity) /String (AI24 ImageRawDataUUID) ,',
    if (alphaIdentity != null) '($alphaIdentity) /String (AI24 ImageAlphaRawDataUUID) ,',
  ]);
  final AiNativeDrawing result = _insertNativeFlaggedArtwork(
    drawing,
    parent,
    layer,
    (locked: definition.attributes.locked, hidden: definition.attributes.hidden, opacity: definition.attributes.opacity, overprint: definition.attributes.overprint),
    _nativeRasterBytes(samples, definition.matrix, '', maximum),
    metadata,
    _nativeImageBounds(definition.matrix, [0, -samples.height.toDouble(), samples.width.toDouble(), 0]),
    transparency: definition.attributes.transparency,
    stencilColor: definition.stencilColor,
  );
  final List<AiNativeRaster> images = _readNativeRasters(result.records, false);
  if (images.length != _readNativeRasters(drawing.records, false).length + 1) {
    throw const FormatException('Image insertion changed unrelated raster ownership.');
  }
  final AiNativeRaster created = images.singleWhere((image) => image.dictionary?['AI24 ImageRawDataUUID']?.text() == colorIdentity);
  _artboardResourceRaster(result.records, created);
  return result;
}

/// Inserts a linked raster and updates all declared file dependency inventories.
AiNativeDrawing _createNativePlacement(AiNativeDrawing drawing, AiNativePlacementDefinition definition, AiNativeGroup? parent, AiLayer? layer) {
  final int maximum = drawing.records.program.limits.maxDecodedBytes;
  _validatePlacedLinkInputs(definition.pathBytes, definition.relativeDirectoryBytes, definition.preview, maximum);
  final String path = latin1.decode(definition.pathBytes);
  final String header = '%AI5_BeginPlace\n%%FileType: 1\n[ ${definition.matrix.join(' ')} ] ${definition.bounds.join(' ')} 4 4 0 ${_placedPathString(definition.pathBytes)}`\n';
  final List<int> metadata = _createdImageMetadata(drawing, definition.attributes, const []);
  final Uint8List link = _placedLinkMetadata('', path, definition.relativeDirectoryBytes, definition.preview, maximum);
  if (header.length + link.length + 20 > maximum) {
    throw const AiLimitException(message: 'Created placement exceeds the native byte limit.');
  }
  final AiNativeDrawing result = _insertNativeFlaggedArtwork(
    drawing,
    parent,
    layer,
    (locked: definition.attributes.locked, hidden: definition.attributes.hidden, opacity: definition.attributes.opacity, overprint: definition.attributes.overprint),
    [...latin1.encode(header), ...link, ...latin1.encode('~\n%AI5_EndPlace\nN')],
    metadata,
    _nativeImageBounds(definition.matrix, definition.bounds),
    transparency: definition.attributes.transparency,
    dependencies: _placedFileEdits(AiNativePlacements.decode(records: drawing.records), null, replacement: path),
  );
  final List<AiNativePlacedObject> objects = _readNativePlacements(result.records, false);
  if (objects.length != _readNativePlacements(drawing.records, false).length + 1) {
    throw const FormatException('Image insertion changed unrelated placement ownership.');
  }
  for (final AiNativePlacedObject object in objects.where((object) => _samePlacedBytes(object.pathBytes, definition.pathBytes))) {
    object.validateRasterLayout();
  }
  return result;
}

/// Shares ordinary artwork metadata while adding independently identified samples.
List<int> _createdImageMetadata(AiNativeDrawing drawing, AiNativeImageAttributes attributes, List<String> fields) {
  final List<int> ordinary = _createdNativeMetadata(drawing, attributes.nameBytes, attributes.identifierBytes, '\n');
  final String base = ordinary.isEmpty ? '%_/ArtDictionary :\n%_;\n' : latin1.decode(ordinary);
  final String value = '${base.substring(0, base.length - 4)}${fields.map((field) => '%_$field\n').join()}%_;\n';
  if (value.length > drawing.records.program.limits.maxDecodedBytes) {
    throw const AiLimitException(message: 'Created image metadata exceeds the native byte limit.');
  }
  return latin1.encode(value);
}

/// Finds qualified image intervals whose operators leave ordinary paint state intact.
List<_NativeSubtreeSpan> _imageCreationNeutralSpans(AiNativeDrawing drawing) => drawing._neutralImageSpans;

/// Qualifies image framing once per immutable native drawing snapshot.
List<_NativeSubtreeSpan> _readImageCreationNeutralSpans(AiNativeDrawing drawing) {
  final List<_NativeSubtreeSpan> result = [];
  final List<AiNativeItem> images = [];
  for (final List<AiNativeItem> Function() read in [() => _readNativeRasters(drawing.records, true), () => _readNativePlacements(drawing.records, true)]) {
    try {
      images.addAll(read());
    } on AiLimitException {
      rethrow;
    } on UnsupportedError {
      // A family with unqualified framing supplies no independent boundaries.
    } on FormatException {
      // Unrelated malformed records remain opaque to ordinary-path operations.
    }
  }
  for (final AiNativeItem item in images) {
    final AiNativeContainer? dictionary;
    try {
      if (item is AiNativeRaster) {
        _artboardResourceRaster(drawing.records, item);
        dictionary = item.dictionary;
      } else {
        final AiNativePlacedObject object = item as AiNativePlacedObject;
        object.validateRasterLayout();
        dictionary = object.dictionary;
      }
      _validateNativeImageMetadata(drawing.records, item.end, dictionary, raster: item is AiNativeRaster);
      result.add((start: item.start, end: dictionary?.end ?? item.end));
    } on UnsupportedError {
      // Unqualified neighboring images remain opaque state barriers.
    } on FormatException {
      // Invalid metadata cannot establish safe inherited state.
    }
  }
  result.sort((first, second) => first.start.compareTo(second.start));
  return result;
}

/// Appends explicit artwork while restoring both native and printing attributes.
AiNativeDrawing _insertNativeFlaggedArtwork(
  AiNativeDrawing drawing,
  AiNativeGroup? parent,
  AiLayer? layer,
  ({bool locked, bool hidden, double opacity, bool overprint}) attributes,
  List<int> artwork,
  List<int> metadata,
  AiBoundingBox bounds, {
  AiNativeTransparency? transparency,
  AiColor? stencilColor,
  List<AiSourceEdit> dependencies = const [],
  _NativeSubtreeSpan? replacement,
}) {
  final int position = replacement?.start ?? _nativeCreationPosition(drawing, parent, layer);
  final int end = replacement?.end ?? position;
  final List<_NativeSubtreeSpan> neutral = _nativeNeutralArtwork(drawing);
  final List<AiNativeAppearanceArtwork> appearances = _nativeCreationAppearances(drawing);
  final List<AiLiveShape> shapes = drawing.liveShapes.where((shape) => shape.isBound).toList()..sort((first, second) => first.end.compareTo(second.end));
  _ordinaryArtworkPrefix(
    drawing,
    position,
    shapes,
    _layerHeaderItems(AiNativeLayers.decode(drawing: drawing)),
    privateState: true,
    resolvedBoundary: _nativeCreationBoundary(drawing, position, appearances),
  );
  final _NativeShapeInputs outgoing = _shapeCopyInputs(drawing, [end], neutralSpans: neutral, appearanceArtwork: appearances)[end]!;
  final Set<String> writes = {'A', 'Xw', 'Ap', 'D', 'XR', 'O', 'R', 'Xy', if (stencilColor != null) 'fill'};
  final StringBuffer suffix = StringBuffer();
  for (final String key in writes) {
    final AiNativeInstruction? printing = outgoing.printing[key];
    final AiNativeInstruction? native = outgoing.native[key];
    if (printing == null || native == null) {
      throw UnsupportedError('Artwork insertion cannot restore unknown $key state.');
    }
    suffix.write(_shapeStateText(printing, private: false));
    if (!_sameNativeArtworkState(printing, native)) {
      suffix.write(_shapeStateText(native, private: true));
    }
  }
  final String paint = stencilColor == null
      ? ''
      : '${stencilColor.channels.join(' ')} ${switch (stencilColor.space) {
          AiColorSpace.gray => 'g',
          AiColorSpace.rgb => 'Xa',
          AiColorSpace.cmyk => 'k',
        }}\n';
  final String blending = transparency?.operands.join(' ') ?? '0 ${attributes.opacity} 0 0 0';
  final String prefix = '\n${attributes.locked ? 1 : 0} A\n${attributes.hidden ? 1 : 0} Xw\n0 Ap\n0 D\n0 XR\n${attributes.overprint ? 1 : 0} O\n0 R\n$blending Xy\n$paint';
  final int length = prefix.length + artwork.length + 2 + metadata.length + suffix.length;
  if (length > drawing.records.program.limits.maxDecodedBytes) {
    throw const AiLimitException(message: 'Created artwork exceeds the native byte limit.');
  }
  return _groupLifecycleResult(
    drawing,
    [
      AiSourceEdit(start: position, end: end, bytes: [...latin1.encode(prefix), ...artwork, 10, ...metadata, 10, ...latin1.encode(suffix.toString())]),
      ...dependencies,
      ...AiNativeEditor.includeBoundsEdits(program: drawing.records.program, bounds: bounds),
    ],
    paths: drawing.paths.length,
    groups: drawing.groups.length,
    liveShapes: drawing.liveShapes.length,
  );
}

/// Checks literal ordinary image metadata without inferring unknown cache semantics.
void _validateNativeImageMetadata(AiNativeRecords records, int end, AiNativeContainer? dictionary, {required bool raster}) {
  if (dictionary != null) {
    _imagePlacementEdits(
      records: records,
      end: end,
      dictionary: dictionary,
      matrix: const [1, 0, 0, 1, 0, 0],
      rotationRadians: _nativeFrameRotation(dictionary),
      commands: const [],
      local: const [0, 0, 1, 1],
      printable: false,
      raster: raster,
    );
    for (final AiNativeEntry entry in dictionary.entries) {
      if (entry.key == 'AI10_ArtUID') {
        final AiNativeContainer identity = _referenceRecord(entry, 'XMLUID');
        if (identity.entries.length != 1 || identity.entries.single.key != null || identity.entries.single.type != null || identity.entries.single.stringBytes?.isNotEmpty != true) {
          throw UnsupportedError('Image identities require one literal XML identifier.');
        }
      } else if (const {'BBAccumRotation', 'Raster Art Original Scale'}.contains(entry.key) && entry.type == 'Real') {
        if (entry.number == null) {
          throw UnsupportedError('Image geometry metadata requires literal scalar values.');
        }
      } else if (!const {'String', 'UnicodeString'}.contains(entry.type) || entry.stringBytes == null) {
        throw UnsupportedError('Image names and sample identities require literal strings.');
      }
    }
  }
}
