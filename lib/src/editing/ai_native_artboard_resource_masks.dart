part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Checks flags and owned mask artwork without changing its linked coordinates.
void _artboardOpacityMask(_ArtboardResourceInspection scope, AiNativeContainer source) {
  final AiNativeRecords records = scope.layers.drawing.records;
  final List<AiNativeVersionMembership> versions = scope.layers.structure.nodeFor(source).versions;
  final bool authoritativeShape =
      !scope.setupOnly &&
      scope.layers.drawing.liveShapes.any(
        (shape) =>
            shape.isBound &&
            shape.dictionary.start < source.start &&
            shape.dictionary.end >= source.end &&
            versions.every((version) => version.branch == .newer && version.block.start >= shape.path!.end && version.block.end < shape.end),
      );
  if (source.hasBinary ||
      scope.setupOnly && source.end > records.program.bodyStart ||
      versions.isNotEmpty && !authoritativeShape ||
      source.entries.any((entry) => entry.key != null || entry.type != null || entry.isQualifier || entry.items.isEmpty)) {
    throw UnsupportedError('Retained opacity masks require unconditional literal setup fields.');
  }
  final AiNativeContainer mask = _nativeOpacityMaskFields(source);
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
  final List<AiNativeContainer> shapes = [];
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
      if (item.type == 'ArtDictionary' && item['ai::LiveShape'] != null) {
        shapes.add(item);
      } else {
        _artboardSymbolMetadata(scope, item, raster: metadata[item]);
      }
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
  final AiNativeDrawing drawing = _NativeDrawingReader(records: records).readItems(items.sublist(1, items.length - 1));
  final Set<AiNativeContainer> qualified = {
    for (final AiNativeGroup group in drawing.groups)
      if (_readNativeAppearanceLeaf(drawing, group)?.shape case final AiLiveShape shape) shape.dictionary,
  };
  if (!qualified.containsAll(shapes)) {
    throw UnsupportedError('Mask shapes require complete qualified native wrappers.');
  }
  scope.drawings.add(drawing);
}
