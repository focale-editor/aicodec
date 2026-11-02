import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboard_palette_test.dart' show paletteArtboardSource;
import '../test/ai_native_artboard_topology_test.dart' show artboardTopologySource;
import '../test/ai_native_artboards_test.dart' show artboardModel, artboardSource, mixedArtboardSource;
import 'check_native_artboards.dart' show artboardInventory;

/// Emits real and mixed native structural transactions for independent decoding.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-lifecycle').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Records every complete source and result, including intermediate snapshots.
  Future<void> record(String name, String variant, String original, AiNativeArtboards before, AiNativeArtboards after) async {
    final String result = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(before.records.program.bytes);
    await File('${output.path}/$result').writeAsBytes(after.records.program.bytes);
    rows.add({'source': name, 'variant': variant, 'original': original, 'result': result, 'before': artboardInventory(before), 'after': artboardInventory(after)});
    stdout.writeln('$name/$variant passed');
  }

  for (final String name in ['units-525x801_origin_at_100_100_CC.ai', 'units-20000x10000_origin_at_100_100_CC.ai', 'units-20x40mm_origin_topleft_CC.ai', 'rgb_rectangle.ai', 'cmyk_rectangle.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeArtboards model = AiNativeArtboards.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    await record(name, 'resize', '$name.original.ps', model, model.resize(artboard: model.artboards.first, bounds: AiBoundingBox(left: -25, bottom: -950, right: 2000, top: 40), cropBounds: null));
    final AiNativeArtboards front = model.create(definition: newArtboard(selected: true), index: 0, lastArtboardId: model.lastArtboardId! + 7, cropBounds: null);
    await record(name, 'create-front', '$name.original.ps', model, front);
    final AiNativeArtboards reordered = front.reorder(artboards: front.artboards.reversed.toList(), cropBounds: null);
    await record(name, 'reorder', '$name.create-front.ps', front, reordered);
    await record(name, 'remove-new', '$name.reorder.ps', reordered, reordered.remove(artboards: [reordered.artboards.last], activeArtboard: null, cropBounds: null));
    final AiNativeArtboards end = model.create(definition: newArtboard(), index: 1, lastArtboardId: model.lastArtboardId! + 11, cropBounds: null, activate: true);
    await record(name, 'create-active', '$name.original.ps', model, end);
    await record(name, 'remove-original', '$name.create-active.ps', end, end.remove(artboards: [end.artboards.first], activeArtboard: null, cropBounds: null));
  }
  for (final String name in ['synthetic', 'synthetic-mixed', 'synthetic-topology', 'synthetic-palette']) {
    final AiNativeArtboards model = artboardModel(switch (name) {
      'synthetic' => artboardSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f'),
      'synthetic-topology' => artboardTopologySource(),
      'synthetic-palette' => paletteArtboardSource(),
      _ => mixedArtboardSource(),
    });
    await record(name, 'resize', '$name.original.ps', model, model.resize(artboard: model.artboards.first, bounds: AiBoundingBox(left: -25, bottom: -950, right: 2000, top: 40), cropBounds: null));
    await record(name, 'reorder', '$name.original.ps', model, model.reorder(artboards: [model.artboards[2], model.artboards[0], model.artboards[1]], cropBounds: null));
    await record(name, 'remove-active', '$name.original.ps', model, model.remove(artboards: [model.artboards[0], model.artboards[2]], activeArtboard: model.artboards[1], cropBounds: null));
    await record(name, 'remove-first', '$name.original.ps', model, model.remove(artboards: [model.artboards.first], activeArtboard: null, cropBounds: null));
    await record(name, 'create-middle', '$name.original.ps', model, model.create(definition: newArtboard(selected: true), index: 1, lastArtboardId: 72, cropBounds: null));
    await record(
      name,
      'create-active',
      '$name.original.ps',
      model,
      model.create(definition: newArtboard(), index: 3, lastArtboardId: 68, cropBounds: AiBoundingBox(left: -10, bottom: -20, right: 30, top: 40), activate: true),
    );
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
