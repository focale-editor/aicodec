import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboards_test.dart' show artboardModel, mixedArtboardSource;
import '../test/ai_native_print_job_test.dart' show printJobSource;
import 'check_native_artboards.dart' show artboardInventory;

/// Binds independently inspectable native print values and exact source spans.
Map<String, Object?> printJobInventory(AiNativeArtboards model) => {
  ...artboardInventory(model),
  'printJob': [model.printJob!.record.start, model.printJob!.record.end],
  'printFields': {
    for (final String key in ['/attributes/job.printallartboards', '/attributes/job.artboardrange', '/attributes/job.printall', '/attributes/job.pagerange'])
      key: {
        'type': model.printJob!.record[key]!.type,
        'typeSpan': [model.printJob!.record[key]!.typeToken!.start, model.printJob!.record[key]!.typeToken!.end],
        'items': [
          for (final AiNativeItem item in model.printJob!.record[key]!.items) [item.start, item.end],
        ],
      },
  },
};

/// Emits native print selections and chained board edits without composing pages.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/print-jobs').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final String name in ['units-525x801_origin_at_100_100_CC.ai', 'units-20000x10000_origin_at_100_100_CC.ai', 'units-20x40mm_origin_topleft_CC.ai', 'synthetic-print']) {
    final AiNativeArtboards original = name == 'synthetic-print'
        ? artboardModel(printJobSource(source: mixedArtboardSource()))
        : AiNativeArtboards.decode(
            records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes)),
          );
    await File('${output.path}/$name.original.ps').writeAsBytes(original.records.program.bytes);
    AiNativeArtboards model = original;
    String predecessor = 'original';

    /// Records each immutable predecessor and complete resulting native snapshot.
    Future<void> record(String variant, AiNativeArtboards result) async {
      await File('${output.path}/$name.$variant.ps').writeAsBytes(result.records.program.bytes);
      rows.add({'source': name, 'variant': variant, 'original': '$name.$predecessor.ps', 'result': '$name.$variant.ps', 'before': printJobInventory(model), 'after': printJobInventory(result)});
      model = result;
      predecessor = variant;
      stdout.writeln('$name/$variant passed');
    }

    await record(
      'select',
      model.reorder(
        artboards: model.artboards,
        cropBounds: null,
        artboardPrinting: AiNativePrintSelection(count: model.artboards.length, indices: {0, model.artboards.length - 1}.toList()),
        pagePrinting: AiNativePrintSelection(count: 9, indices: [1, 4]),
      ),
    );
    await record(
      'create',
      model.create(
        definition: newArtboard(),
        index: 0,
        lastArtboardId: model.lastArtboardId! + 7,
        cropBounds: null,
        pagePrinting: AiNativePrintSelection(count: 12, indices: [0, 5, 11]),
      ),
    );
    await record(
      'reorder',
      model.reorder(
        artboards: model.artboards.reversed.toList(),
        cropBounds: null,
        pagePrinting: AiNativePrintSelection(count: 8, indices: [3, 7]),
      ),
    );
    final Set<int> selected = model.printJob!.artboardIndices!.toSet();
    final AiNativeArtboard retained = model.artboards.indexed.firstWhere((board) => !selected.contains(board.$1)).$2;
    await record(
      'remove',
      model.remove(
        artboards: selected.map((index) => model.artboards[index]),
        activeArtboard: selected.contains(model.activeIndex) ? retained : null,
        cropBounds: null,
        artboardPrinting: AiNativePrintSelection(count: model.artboards.length - selected.length, indices: null),
        pagePrinting: AiNativePrintSelection(count: 5, indices: null),
      ),
    );
    await record(
      'resize',
      model.resize(
        artboard: model.artboards.first,
        bounds: AiBoundingBox(left: -20, bottom: -40, right: 250, top: 120),
        cropBounds: null,
        pagePrinting: AiNativePrintSelection(count: 4, indices: [2]),
      ),
    );
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
