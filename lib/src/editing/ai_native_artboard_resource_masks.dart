part of 'package:aikit/src/model/ai_native_records.dart';

/// Checks flags and owned mask artwork without changing its linked coordinates.
void _artboardOpacityMask(_ArtboardResourceInspection scope, AiNativeContainer source) {
  final AiNativeRecords records = scope.layers.drawing.records;
  if (source.hasBinary ||
      source.end > records.program.bodyStart ||
      scope.layers.structure.nodeFor(source).versions.isNotEmpty ||
      source.entries.any((entry) => entry.key != null || entry.type != null || entry.isQualifier || entry.items.isEmpty)) {
    throw UnsupportedError('Retained opacity masks require unconditional literal setup fields.');
  }
  // Mask uses dictionary suffixes, but generic inspection preserves its raw entries.
  final AiNativeContainer mask = AiNativeContainer._(
    start: source.start,
    end: source.end,
    type: source.type,
    entries: source.entries.map((entry) => _NativeRecordReader._entry(type: 'Dictionary', items: entry.items)).toList(),
  );
  _referenceFields(
    mask,
    {
      'Bool': {'Linked', 'Disabled', 'Clipping', 'Inverted'},
    },
    nested: {
      'Art': (entry) {
        if (entry.type != null || entry.items.isEmpty) {
          throw const FormatException('A retained opacity mask requires a complete artwork field.');
        }
      },
    },
  );
  if (mask.entries.length != 5 || mask['Art'] == null) {
    throw UnsupportedError('Retained opacity masks require explicit artwork and all four flags.');
  }
  final AiNativeEntry art = mask['Art']!;
  final List<AiNativeRaster> rasters = _pathInterval(scope.rasters, source.start, source.end, (image) => image.start).toList();
  final Map<AiNativeContainer, AiNativeRaster> metadata = {};
  for (final AiNativeRaster image in rasters) {
    if (image.start < art.items.first.start || image.end > art.items.last.end) {
      throw const FormatException('A retained mask raster crosses its artwork field.');
    }
    _artboardResourceRaster(records, image);
    if (image.dictionary != null) {
      metadata[image.dictionary!] = image;
    }
  }
  final List<AiNativeItem> items = [];
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
  int rasterIndex = 0;
  AiNativeRaster? active;
  for (final AiNativeItem item in art.items) {
    while (rasterIndex < rasters.length && rasters[rasterIndex].end <= item.start) {
      rasterIndex++;
    }
    if (rasterIndex < rasters.length && item.start >= rasters[rasterIndex].start) {
      final AiNativeRaster image = rasters[rasterIndex];
      if (item.end > image.end) {
        throw const FormatException('Retained raster commands cross their owned section.');
      }
      if (!identical(active, image)) {
        reader.finish();
        items.add(image);
        active = image;
      }
      continue;
    }
    if (item is AiNativeContainer) {
      reader.finish();
      _artboardSymbolMetadata(scope, item, raster: metadata[item]);
      items.add(item);
    } else if (item is AiNativeToken) {
      final AiNativeInstruction? instruction = reader.add(item.token, isPrivate: records._projection.isPrivate(item.start));
      if (instruction != null) {
        if (instruction.operator == 'N' && instruction.operands.isNotEmpty) {
          throw const FormatException('A retained raster terminator cannot consume operands.');
        }
        items.add(instruction);
      }
    } else {
      throw const FormatException('Unexpected retained opacity mask artwork.');
    }
  }
  reader.finish();
  if (items.length < 2 ||
      items.first is! AiNativeInstruction ||
      items.last is! AiNativeInstruction ||
      (items.first as AiNativeInstruction).operator != 'X=' ||
      (items.last as AiNativeInstruction).operator != 'X+' ||
      (items.first as AiNativeInstruction).operands.isNotEmpty ||
      (items.last as AiNativeInstruction).operands.isNotEmpty ||
      (items.first as AiNativeInstruction).isPrivate != (items.last as AiNativeInstruction).isPrivate) {
    throw const FormatException('Retained opacity masks require matching empty artwork boundaries.');
  }
  _artboardResourceAnnotations(scope, source.start, source.end, rasters);
  scope.drawings.add(_NativeDrawingReader(records: records).readItems(items.sublist(1, items.length - 1)));
}
