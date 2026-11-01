import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboard_masks_test.dart' show artboardOpacityMask, maskArtboardSource;
import '../test/ai_native_artboards_test.dart' show artboardModel;
import 'check_native_artboard_text.dart' show retainedTextCarrier;
import 'check_native_artboards.dart' show artboardInventory;

/// Copies complete producer mask dictionaries into an explicit symbol carrier.
String _carrier(AiNativeSource source) {
  final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes));
  final List<AiNativeContainer> masks = records.roots.where((record) => record.type == 'ArtDictionary' && record['AI9_Mask'] != null).toList();
  if (masks.length != 2) {
    throw StateError('The pinned producer must contain two setup mask owners.');
  }
  final String text = latin1.decode(source.bytes);
  final StringBuffer symbol = StringBuffer('%AI14_BeginSymbol\n(Retained masks)\n0 A 0 Xw 0 Ae u\n');
  for (final AiNativeContainer mask in masks) {
    if (mask.end >= records.program.bodyStart) {
      throw StateError('Only the pinned setup symbol masks belong in this carrier.');
    }
    final int start = text.substring(mask.start - 2, mask.start) == '%_' ? mask.start - 2 : mask.start;
    symbol.writeln('0.3 g 0 0 m 10 10 L f');
    symbol.writeln(text.substring(start, mask.end));
  }
  symbol.writeln('U\n9 () XW\n%AI10_EndSymbol\n%AI24_BeginSymbolList\n(Retained masks)\n%AI24_EndSymbolList');
  return retainedTextCarrier(source).replaceFirst('%%EndSetup', '$symbol\n%%EndSetup');
}

/// Emits four artboard transactions with intact source mask artwork and samples.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-masks').create(recursive: true);
  final Map<String, String> carriers = {};
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    await File('${output.path}/$name.producer.ps').writeAsBytes(source.bytes);
    carriers[name] = _carrier(source);
  }
  carriers['synthetic-raster'] = maskArtboardSource();
  carriers['synthetic-vector'] = maskArtboardSource(mask: artboardOpacityMask(art: '%_4 As 0.3 g 0 0 m 10 0 L 10 10 L 0 10 L 0 0 L f\n'));
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
        _ => throw StateError('Unknown artboard mask transaction.'),
      };
      await File('${output.path}/${carrier.key}.$operation.ps').writeAsBytes(after.records.program.bytes);
      rows.add({'source': carrier.key, 'operation': operation, 'before': artboardInventory(before), 'after': artboardInventory(after)});
      stdout.writeln('${carrier.key}/$operation passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
