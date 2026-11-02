import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboard_styles_test.dart' show artboardActiveStyle;
import '../test/ai_native_artboard_symbols_test.dart' show symbolArtboardSource;
import '../test/ai_native_artboards_test.dart' show artboardModel;
import 'check_native_artboard_text.dart' show retainedTextCarrier;
import 'check_native_artboards.dart' show artboardInventory;

/// Copies complete supported style owners and all symbols except the blend source.
String retainedAppearanceCarrier(AiNativeSource source) {
  final String text = latin1.decode(source.bytes);
  final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes));
  final StringBuffer styles = StringBuffer('%AI9_BeginArtStyles\n');
  for (final AiNativeContainer style in records.roots.where((record) => record.type == 'KnownStyle')) {
    final String original = text.substring(style.start, style.end);
    // The complete calligraphic style has a brush GObjRef, qualified separately.
    if (!original.contains('(Adobe Calligraphic Brush Tool)')) {
      final int start = text.substring(style.start - 2, style.start) == '%_' ? style.start - 2 : style.start;
      styles.writeln(text.substring(start, style.end));
    }
  }
  styles.writeln('%AI9_EndArtStyles');
  final StringBuffer symbols = StringBuffer();
  final List<String> names = [];
  for (final RegExpMatch definition in RegExp(r'%AI14_BeginSymbol\s+\(((?:\\.|[^)])*)\)[\s\S]*?%AI10_EndSymbol').allMatches(text)) {
    if (definition[1] != 'Band') {
      symbols.writeln(definition[0]);
      names.add('(${definition[1]})');
    }
  }
  if (names.length != 5 && names.length != 15) {
    throw StateError('The pinned appearance carrier has an unexpected symbol set.');
  }
  if (names.length == 15) {
    final RegExpMatch? inventory = RegExp(r'%AI(10|24)_BeginSymbolList\x00?[\s\S]*?%AI\1_EndSymbolList\x00?').firstMatch(text);
    if (inventory == null) {
      throw StateError('The complete producer symbols require their original panel inventory.');
    }
    symbols.writeln(inventory[0]);
  } else {
    symbols.writeln('%AI24_BeginSymbolList\n${names.join('\n')}\n%AI24_EndSymbolList');
  }
  return retainedTextCarrier(source).replaceFirst('%%EndSetup', '$styles\n$symbols\n%%EndSetup');
}

/// Exercises four native artboard edits with exact retained appearance resources.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-styles').create(recursive: true);
  final Map<String, String> carriers = {};
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    await File('${output.path}/$name.producer.ps').writeAsBytes(source.bytes);
    carriers[name] = retainedAppearanceCarrier(source);
  }
  carriers['synthetic-style'] = symbolArtboardSource(style: artboardActiveStyle());
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
        _ => throw StateError('Unknown artboard appearance transaction.'),
      };
      await File('${output.path}/${carrier.key}.$operation.ps').writeAsBytes(after.records.program.bytes);
      rows.add({'source': carrier.key, 'operation': operation, 'before': artboardInventory(before), 'after': artboardInventory(after)});
      stdout.writeln('${carrier.key}/$operation passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
