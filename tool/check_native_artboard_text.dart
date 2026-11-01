import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboard_text_test.dart' show artboardTextDrawing, artboardTextEngineSource, populatedArtboardSource;
import '../test/ai_native_artboards_test.dart' show artboardModel, artboardSource;
import 'check_native_artboards.dart' show artboardInventory;

/// Copies exact text snapshots and drawing owners into a declared test carrier.
String retainedTextCarrier(AiNativeSource source) {
  final String text = latin1.decode(source.bytes);
  final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes));
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final int setupStart = text.indexOf('%AI11_BeginTextDocument');
  final int setupEnd = text.indexOf('%AI11_EndTextDocument', setupStart) + '%AI11_EndTextDocument'.length;
  if (setupStart < 0 || setupEnd <= setupStart) {
    throw StateError('The producer text setup must have explicit wrappers.');
  }
  final StringBuffer body = StringBuffer();
  for (final (int, AiNativeItem) item in drawing.items.indexed) {
    if (item.$2 is! AiNativeContainer || (item.$2 as AiNativeContainer).type != 'AI11Text') {
      continue;
    }
    body.writeln(text.substring(item.$2.start, item.$2.end));
    if (item.$1 + 1 < drawing.items.length) {
      final AiNativeItem next = drawing.items[item.$1 + 1];
      if (next is AiNativeContainer && next.type == 'ArtDictionary') {
        final int start = text.substring(next.start - 2, next.start) == '%_' ? next.start - 2 : next.start;
        body.writeln(text.substring(start, next.end));
      }
    }
  }
  return artboardSource(extra: text.substring(setupStart, setupEnd), body: body.toString());
}

/// Emits native artboard transactions with unchanged producer text and caches.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-text').create(recursive: true);
  final Map<String, String> carriers = {};
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    await File('${output.path}/$name.producer.ps').writeAsBytes(source.bytes);
    carriers[name] = retainedTextCarrier(source);
  }
  carriers['synthetic-main'] = populatedArtboardSource();
  carriers['synthetic-undo'] = populatedArtboardSource(undo: artboardTextEngineSource(), body: artboardTextDrawing(snapshot: 1));
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
        _ => throw StateError('Unknown artboard text transaction.'),
      };
      await File('${output.path}/${carrier.key}.$operation.ps').writeAsBytes(after.records.program.bytes);
      rows.add({'source': carrier.key, 'operation': operation, 'before': artboardInventory(before), 'after': artboardInventory(after)});
      stdout.writeln('${carrier.key}/$operation passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
