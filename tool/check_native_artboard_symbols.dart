import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboard_lifecycle_test.dart' show newArtboard;
import '../test/ai_native_artboard_symbols_test.dart' show symbolArtboardSource;
import '../test/ai_native_artboards_test.dart' show artboardModel;
import 'check_native_artboard_text.dart' show retainedTextCarrier;
import 'check_native_artboards.dart' show artboardInventory;

/// Fixed producer symbols whose retained artwork has no mask or blend owner.
const Set<String> retainedSymbols = {
  'Button_over',
  'Credit Card',
  'DateField_over',
  'Dropdown_over',
  'Home',
  'Panel_CloseButtonOver',
  'PopUpButton_over',
  'Print',
  'RSS',
  'Shopping Cart',
  'TabBar-tab_over',
  'TextArea_focus',
  'Gerbera',
  r'Schnittmarken \(9-Slice\)',
  'Vektorschmutz',
};

/// Copies complete pinned definitions, keeping unsupported families explicit.
String _carrier(AiNativeSource source) {
  final String text = latin1.decode(source.bytes);
  final StringBuffer symbols = StringBuffer();
  final List<String> names = [];
  for (final RegExpMatch definition in RegExp(r'%AI14_BeginSymbol\s+\(((?:\\.|[^)])*)\)[\s\S]*?%AI10_EndSymbol').allMatches(text)) {
    if (retainedSymbols.contains(definition[1])) {
      symbols.writeln(definition[0]);
      names.add('(${definition[1]})');
    }
  }
  if (names.length != 3 && names.length != 12) {
    throw StateError('The pinned symbol carrier has an unexpected definition set.');
  }
  symbols.writeln('%AI24_BeginSymbolList\n${names.join('\n')}\n%AI24_EndSymbolList');
  return retainedTextCarrier(source).replaceFirst('%%EndSetup', '$symbols\n%%EndSetup');
}

/// Exercises four native artboard edits with exact retained symbol resources.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboard-symbols').create(recursive: true);
  final Map<String, String> carriers = {};
  for (final String name in ['simple_cc_legacy.ai', 'simple_v2020.ai', 'text_transforms.ai', 'flowtext.ai']) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    await File('${output.path}/$name.producer.ps').writeAsBytes(source.bytes);
    carriers[name] = _carrier(source);
  }
  carriers['synthetic-symbol'] = symbolArtboardSource();
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
        _ => throw StateError('Unknown artboard symbol transaction.'),
      };
      await File('${output.path}/${carrier.key}.$operation.ps').writeAsBytes(after.records.program.bytes);
      rows.add({'source': carrier.key, 'operation': operation, 'before': artboardInventory(before), 'after': artboardInventory(after)});
      stdout.writeln('${carrier.key}/$operation passed');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
