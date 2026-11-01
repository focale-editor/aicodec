import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'check_native_artboards.dart' show artboardInventory;

/// Saves complete source-backed transactions, without replacing producer setup.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-complete-sources').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai', 'layers_and_sublayers.ai']) {
    await _completeSource(output, name, rows);
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}

/// Exercises every board operation against complete original Illustrator programs.
Future<void> _completeSource(Directory output, String name, List<Map<String, Object?>> rows) async {
  final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
  final AiNativeArtboards before = AiNativeArtboards.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
  );

  /// Records unchanged original owners and chained intermediate native snapshots.
  Future<void> record(String variant, String original, AiNativeArtboards model, AiNativeArtboards after) async {
    final String result = '$name.full.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(model.records.program.bytes);
    await File('${output.path}/$result').writeAsBytes(after.records.program.bytes);
    rows.add({'source': name, 'variant': variant, 'original': original, 'result': result, 'before': artboardInventory(model), 'after': artboardInventory(after)});
    stdout.writeln('$name/full/$variant passed');
  }

  await record('resize', '$name.full.original.ps', before, before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -25, bottom: -950, right: 2000, top: 40), cropBounds: null));
  final AiNativeArtboards front = before.create(definition: newArtboard(selected: true), index: 0, lastArtboardId: before.lastArtboardId! + 7, cropBounds: null);
  await record('create-front', '$name.full.original.ps', before, front);
  final AiNativeArtboards reordered = front.reorder(artboards: front.artboards.reversed.toList(), cropBounds: null);
  await record('reorder', '$name.full.create-front.ps', front, reordered);
  await record('remove-new', '$name.full.reorder.ps', reordered, reordered.remove(artboards: [reordered.artboards.last], activeArtboard: null, cropBounds: null));
  final AiNativeArtboards active = before.create(definition: newArtboard(), index: 1, lastArtboardId: before.lastArtboardId! + 11, cropBounds: null, activate: true);
  await record('create-active', '$name.full.original.ps', before, active);
  await record('remove-original', '$name.full.create-active.ps', active, active.remove(artboards: [active.artboards.first], activeArtboard: null, cropBounds: null));
}
