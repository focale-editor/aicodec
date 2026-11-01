import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_brush_descriptors_test.dart' show artboardBrushDescriptors, artboardCalligraphicStyle;
import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboards_test.dart' show artboardModel, artboardSource;
import 'check_native_artboard_svg_filters.dart' show retainedSvgFilterCarrier;
import 'check_native_artboards.dart' show artboardInventory;

/// Copies complete descriptor panels and the previously excluded calligraphic styles.
String _carrier(AiNativeSource source) {
  final String text = latin1.decode(source.bytes);
  final List<String> descriptors = RegExp(r'%AI8_BeginPluginObject[\s\S]*?%AI8_EndPluginObject').allMatches(text).map((match) => match[0]!).toList();
  if (descriptors.length != 8 && descriptors.length != 12) {
    throw StateError('The pinned brush carrier has an unexpected descriptor set.');
  }
  final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes));
  final List<String> styles = [];
  for (final AiNativeContainer record in records.roots.where((record) => record.type == 'KnownStyle')) {
    final String style = text.substring(record.start, record.end);
    if (style.contains('(Adobe Calligraphic Brush Tool)')) {
      styles.add(style);
    }
  }
  return retainedSvgFilterCarrier(source).replaceFirst('%%EndSetup', "${descriptors.join('\n')}\n${styles.join('\n')}\n%%EndSetup");
}

/// Exercises four native artboard edits with exact retained brush descriptors.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-brush-descriptors').create(recursive: true);
  final Map<String, String> carriers = {};
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    await File('${output.path}/$name.producer.ps').writeAsBytes(source.bytes);
    carriers[name] = _carrier(source);
  }
  // The independent reader requires an explicit compound execution wrapper.
  final String style = artboardCalligraphicStyle()
      .replaceFirst('/ActiveStyle : /BasicFilter :', '/ActiveStyle : /CompoundFilter : (Chain Style Filter) 0 0 /Filter , 1 /Visible , /BasicFilter :')
      .replaceFirst('/Execution', '/Part , ; /Execution');
  carriers['synthetic-descriptor'] = artboardSource(extra: '${artboardBrushDescriptors()}$style');
  final List<Map<String, Object?>> rows = [];
  for (final MapEntry<String, String> carrier in carriers.entries) {
    final AiNativeArtboards before = artboardModel(carrier.value);
    await File('${output.path}/${carrier.key}.original.ps').writeAsBytes(before.records.program.bytes);
    for (final String operation in ['create', 'resize', 'reorder', 'remove']) {
      final AiNativeArtboards after = switch (operation) {
        'create' => before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: AiBoundingBox(left: -10, bottom: -20, right: 30, top: 40)),
        'resize' => before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -10, bottom: -20, right: 500, top: 800), cropBounds: null),
        'reorder' => before.reorder(artboards: [before.artboards[2], before.artboards[0], before.artboards[1]], cropBounds: null),
        'remove' => before.remove(artboards: [before.artboards[2]], activeArtboard: before.artboards[1], cropBounds: null),
        _ => throw StateError('Unknown artboard brush-descriptor transaction.'),
      };
      await File('${output.path}/${carrier.key}.$operation.ps').writeAsBytes(after.records.program.bytes);
      rows.add({'source': carrier.key, 'operation': operation, 'before': artboardInventory(before), 'after': artboardInventory(after)});
      stdout.writeln('${carrier.key}/$operation passed');
    }
  }
  await _completeSource(output);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}

/// Exercises every board operation against the complete original text document.
Future<void> _completeSource(Directory output) async {
  const String name = 'text_transforms.ai';
  final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
  final AiNativeArtboards before = AiNativeArtboards.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
  );
  final List<Map<String, Object?>> rows = [];

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
  await File('${output.path}/full-report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
