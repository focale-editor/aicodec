import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artwork_movement_test.dart' show artworkMovementSource;
import 'native_layer_support.dart';

/// Reopens exact native bytes without creating a rendered representation.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Records source spans for independent topology, count and byte checks.
Map<String, Object?> _inventory(AiNativeDrawing drawing) {
  int previous = drawing.records.program.bodyStart;
  final List<Map<String, Object?>> paths = [];
  for (final AiNativePath path in drawing.paths) {
    final List<AiNativeInstruction> counts = drawing.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As' && item.start >= previous && item.end <= path.start).toList();
    paths.add({
      'start': path.start,
      'end': path.end,
      'count': counts.isEmpty ? null : [counts.single.start, counts.single.end],
    });
    previous = path.end;
  }
  return {
    'layers': nativeLayerInventory(AiNativeLayers.decode(drawing: drawing)),
    'paths': paths,
    'groups': [
      for (final AiNativeGroup group in drawing.groups) {'start': group.start, 'end': group.end, 'paths': group.paths.map((path) => drawing.paths.indexOf(path)).toList()},
    ],
  };
}

/// Writes cross-layer transactions and their explicitly qualified prerequisites.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artwork-movement').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves one requested relocation with exact before/after object inventories.
  Future<void> record(String source, String original, String label, String operation, AiNativeDrawing before, AiNativeDrawing after, int selected, {int? anchor, int? layer}) async {
    final String result = '$source.$label.ps';
    await File('${output.path}/$result').writeAsBytes(after.records.program.bytes);
    rows.add({
      'source': source,
      'original': original,
      'result': result,
      'operation': operation,
      'selected': selected,
      'anchor': ?anchor,
      'layer': ?layer,
      'inheritParentFlags': true,
      'before': _inventory(before),
      'after': _inventory(after),
    });
    stdout.writeln('$result passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai']) {
    final AiNativeDrawing original = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    await File('${output.path}/$name.original.ps').writeAsBytes(original.records.program.bytes);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: original);
    final AiNativeDrawing inserted = layers
        .insertAfter(after: layers.layers.single, nameBytes: latin1.encode('Destination'), identifierBytes: latin1.encode('AiCodec_destination'), discardViewState: true)
        .drawing;
    await record(name, '$name.original.ps', 'insert', 'insert', original, inserted, 0);
    await record(
      name,
      '$name.insert.ps',
      'path',
      'path-layer',
      inserted,
      inserted.movePathToLayer(path: inserted.paths[18], layer: inserted.records.program.layers.last, inheritParentFlags: true),
      18,
      layer: 1,
    );
    final AiNativeDrawing grouped = inserted.groupPaths(paths: [inserted.paths[18]]);
    await record(name, '$name.insert.ps', 'group', 'group', inserted, grouped, 18);
    final AiNativeGroup selected = grouped.groups.singleWhere((group) => group.paths.contains(grouped.paths[18]));
    await record(
      name,
      '$name.group.ps',
      'subtree',
      'group-layer',
      grouped,
      grouped.moveGroupToLayer(group: selected, layer: grouped.records.program.layers.last, inheritParentFlags: true),
      grouped.groups.indexOf(selected),
      layer: 1,
    );
  }

  const String name = 'synthetic-state';
  final AiNativeDrawing source = _drawing(latin1.encode(artworkMovementSource));
  await File('${output.path}/$name.original.ps').writeAsBytes(source.records.program.bytes);
  for (final bool forward in [true, false]) {
    final String direction = forward ? 'forward' : 'backward';
    final int path = forward ? 1 : 3;
    final int anchor = forward ? 3 : 1;
    await record(
      name,
      '$name.original.ps',
      'path-$direction',
      'path-after',
      source,
      source.movePathAfter(path: source.paths[path], after: source.paths[anchor], inheritParentFlags: true),
      path,
      anchor: anchor,
    );
    final int group = forward ? 0 : 1;
    await record(
      name,
      '$name.original.ps',
      'group-$direction',
      'group-after',
      source,
      source.moveGroupAfter(group: source.groups[group], after: source.groups[1 - group], inheritParentFlags: true),
      group,
      anchor: 1 - group,
    );
  }
  await record(
    name,
    '$name.original.ps',
    'path-empty',
    'path-layer',
    source,
    source.movePathToLayer(path: source.paths[1], layer: source.records.program.layers.last, inheritParentFlags: true),
    1,
    layer: 3,
  );
  await record(
    name,
    '$name.original.ps',
    'group-empty',
    'group-layer',
    source,
    source.moveGroupToLayer(group: source.groups.first, layer: source.records.program.layers.last, inheritParentFlags: true),
    0,
    layer: 3,
  );
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
