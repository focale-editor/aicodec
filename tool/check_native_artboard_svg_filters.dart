import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboard_svg_filters_test.dart' show artboardSvgFilter;
import '../test/ai_native_artboards_test.dart' show artboardModel, artboardSource;
import 'check_native_artboard_brushes.dart' show retainedBrushCarrier;
import 'check_native_artboards.dart' show artboardInventory;

/// Copies all native filter trees with their exact attributes and animations.
String retainedSvgFilterCarrier(AiNativeSource source) {
  final String text = latin1.decode(source.bytes);
  final List<String> filters = RegExp(r'%AI10_BeginSVGFilter[\s\S]*?%AI10_EndSVGFilter').allMatches(text).map((match) => match[0]!).toList();
  if (filters.length != 1 || AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)).roots.where((root) => root.type == 'SVGFilter').length != 18) {
    throw StateError('The pinned SVG-filter carrier has an unexpected definition set.');
  }
  return retainedBrushCarrier(source).replaceFirst('%%EndSetup', "${filters.join('\n')}\n%%EndSetup");
}

/// Exercises four native artboard edits with exact retained SVG-filter resources.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-svg-filters').create(recursive: true);
  final Map<String, String> carriers = {};
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    await File('${output.path}/$name.producer.ps').writeAsBytes(source.bytes);
    carriers[name] = retainedSvgFilterCarrier(source);
  }
  carriers['synthetic-filter'] = artboardSource(extra: artboardSvgFilter());
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
        _ => throw StateError('Unknown artboard SVG-filter transaction.'),
      };
      await File('${output.path}/${carrier.key}.$operation.ps').writeAsBytes(after.records.program.bytes);
      rows.add({'source': carrier.key, 'operation': operation, 'before': artboardInventory(before), 'after': artboardInventory(after)});
      stdout.writeln('${carrier.key}/$operation passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
