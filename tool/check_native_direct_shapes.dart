import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_direct_shape_test.dart' show directShapeSource;
import 'native_layer_support.dart';
import 'native_object_support.dart';

/// Opens a source snapshot without constructing a host compatibility appearance.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Retains source ownership separately from expected edit results.
Map<String, Object?> _inventory(AiNativeDrawing drawing) => {
  'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
  'objects': nativeObjectInventory(drawing),
  'shapes': drawing.liveShapes.length,
};

/// Exercises direct native authoring through existing whole-object operations.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/direct-shapes').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Records complete immutable source snapshots and the exact selected owners.
  Future<void> record(
    String source,
    String operation,
    AiNativeDrawing before,
    AiNativeDrawing after, {
    List<AiNativeItem> objects = const [],
    List<AiNativeLayer> layers = const [],
    Map<AiNativeItem, List<int>> identifiers = const {},
    Map<AiNativeLayer, List<int>> layerIdentifiers = const {},
    AiNativeItem? anchor,
  }) async {
    final AiNativeObjects inventory = AiNativeObjects.decode(drawing: before);
    final String original = '$source.original.ps';
    final String result = '$source.$operation.ps';
    await File('${output.path}/$original').writeAsBytes(before.records.program.bytes);
    await File('${output.path}/$result').writeAsBytes(after.records.program.bytes);
    rows.add({
      'source': source,
      'original': original,
      'result': result,
      'operation': operation,
      'objects': objects.map((object) => inventory.objects.indexOf(inventory.forSource(object))).toList(),
      'layers': layers.map((layer) => layer.index).toList(),
      'anchor': anchor == null ? null : inventory.objects.indexOf(inventory.forSource(anchor)),
      'artworkIdentifiers': [
        for (final MapEntry<AiNativeItem, List<int>> entry in identifiers.entries) {'object': inventory.objects.indexOf(inventory.forSource(entry.key)), 'bytes': entry.value},
      ],
      'layerIdentifiers': [
        for (final MapEntry<AiNativeLayer, List<int>> entry in layerIdentifiers.entries) {'layer': entry.key.index, 'bytes': entry.value},
      ],
      'before': _inventory(before),
      'after': _inventory(after),
    });
    stdout.writeln('$result passed');
  }

  for (final String source in ['circle.ai', 'cmyk_rectangle.ai', 'rgb_rectangle.ai', 'opacity.ai', 'rectangle_with_rounded_corners.ai', 'rectangle-rounded-corners-all-different.ai', 'styles.ai']) {
    final AiNativeDrawing before = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$source').readAsBytes())).single.bytes);
    final AiNativePath path = before.paths.first;
    if (!identical(before.liveShapes.first.path, path) || path.isPrivate) {
      throw StateError('The pinned first object is no longer a directly authored live shape.');
    }
    await record(source, 'duplicate-path', before, before.duplicatePaths(paths: [path]), objects: [path]);
    await record(source, 'remove-path', before, before.removePaths(paths: [path]), objects: [path]);
  }
  final AiNativeDrawing before = _drawing(latin1.encode(directShapeSource));
  final Map<AiNativeItem, List<int>> pathIds = {before.paths.first: latin1.encode('copy_rect')};
  final Map<AiNativeItem, List<int>> groupIds = {before.paths[1]: latin1.encode('copy_child')};
  await record(
    'synthetic',
    'duplicate-path',
    before,
    before.duplicatePaths(paths: [before.paths.first], identifiers: pathIds),
    objects: [before.paths.first],
    identifiers: pathIds,
  );
  await record('synthetic', 'remove-path', before, before.removePaths(paths: [before.paths.first]), objects: [before.paths.first]);
  await record(
    'synthetic',
    'duplicate-group',
    before,
    before.duplicateGroups(groups: before.groups, identifiers: groupIds),
    objects: before.groups,
    identifiers: groupIds,
  );
  await record('synthetic', 'remove-group', before, before.removeGroups(groups: before.groups), objects: before.groups);
  await record(
    'synthetic',
    'move-path',
    before,
    before.movePathAfter(path: before.paths.first, after: before.paths.last, inheritParentFlags: true),
    objects: [before.paths.first],
    anchor: before.paths.last,
  );
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: before);
  final Map<AiNativeLayer, List<int>> layerIds = {layers.layers.first: latin1.encode('Copy_A')};
  final Map<AiNativeItem, List<int>> artworkIds = {before.paths[0]: latin1.encode('copy_a'), before.paths[1]: latin1.encode('copy_child')};
  await record(
    'synthetic',
    'copy',
    before,
    layers.duplicate(layers: [layers.layers.first], identifiers: layerIds, artworkIdentifiers: artworkIds).drawing,
    layers: [layers.layers.first],
    layerIdentifiers: layerIds,
    identifiers: artworkIds,
  );
  await record('synthetic', 'remove-layers', before, layers.remove(layers: [layers.layers.first]).drawing, layers: [layers.layers.first]);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
