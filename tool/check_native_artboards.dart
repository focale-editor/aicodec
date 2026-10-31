import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_artboards_test.dart' show artboardModel, artboardSource, mixedArtboardSource;

/// Retains independently checkable owners and scalar values without PDF inference.
Map<String, Object?> _inventory(AiNativeArtboards model) => {
  'document': [model.document.start, model.document.end],
  'active': model.activeIndex,
  'lastId': model.lastArtboardId,
  'crop': model.cropHeader?.values,
  'cropSpan': model.cropHeader == null ? null : [model.cropHeader!.token.start, model.cropHeader!.token.end],
  'boards': [
    for (final AiNativeArtboard board in model.artboards)
      {
        'name': latin1.decode(board.nameBytes),
        'identifier': board.identifier,
        'selected': board.selected,
        'bounds': [board.bounds.left, board.bounds.bottom, board.bounds.right, board.bounds.top],
        'origin': board.rulerOrigin,
        'coordinates': {
          for (final String key in ['PositionPoint1', 'PositionPoint2', 'RulerOrigin'])
            if (board.record[key] != null) key: board.record[key]!.items.map((item) => [item.start, item.end]).toList(),
        },
      },
  ],
};

/// Emits native rectangle transactions while leaving compatibility saves explicit.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/artboards').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves original ownership, requested coordinates and immutable outcomes.
  Future<void> record(String name, String variant, AiNativeArtboards model, {int? selected, bool crop = false, bool origin = false, bool reject = false}) async {
    final AiBoundingBox bounds = AiBoundingBox(left: -25, bottom: -950, right: 2000, top: 40);
    final AiBoundingBox? replacementCrop = crop ? AiBoundingBox(left: 1, bottom: 2, right: 300, top: 400) : null;
    final List<double>? replacementOrigin = origin ? [7000, 7100] : null;
    AiNativeArtboards result = model;
    String? issue;
    if (selected != null) {
      try {
        result = model.resize(artboard: model.artboards[selected], bounds: bounds, cropBounds: replacementCrop, rulerOrigin: replacementOrigin);
      } on UnsupportedError catch (error) {
        if (!reject) {
          rethrow;
        }
        issue = error.message;
      }
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected artboard qualification for $name/$variant.');
    }
    final String original = '$name.original.ps';
    final String target = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(model.records.program.bytes);
    if (selected != null && !reject) {
      await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    }
    rows.add({
      'source': name,
      'variant': variant,
      'original': original,
      'result': selected == null || reject ? original : target,
      'selected': selected,
      'crop': crop,
      'origin': origin,
      'rejected': reject,
      'issue': issue,
      'before': _inventory(model),
      'after': _inventory(result),
    });
    stdout.writeln('$name/$variant passed');
  }

  for (final String name in [
    'simple_shapes_cc.ai',
    'layers_and_sublayers.ai',
    'units-525x801_origin_at_100_100_CC.ai',
    'units-20000x10000_origin_at_100_100_CC.ai',
    'units-20x40mm_origin_topleft_CC.ai',
    'reuters-preview-dev.ai',
  ]) {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single;
    final AiNativeArtboards model = AiNativeArtboards.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    await record(name, 'inspection', model);
    if (name.startsWith('units-')) {
      await record(name, 'bounds', model, selected: 0);
      await record(name, 'explicit', model, selected: 0, crop: true, origin: true);
    } else {
      await record(name, 'rejected', model, selected: name == 'reuters-preview-dev.ai' ? 4 : 0, reject: true);
    }
  }
  final AiNativeArtboards synthetic = artboardModel(artboardSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f'));
  for (final int index in [0, 1, 2]) {
    await record('synthetic', 'board-$index', synthetic, selected: index, crop: index == 2, origin: index == 1);
  }
  await record('synthetic-mixed', 'board-1', artboardModel(mixedArtboardSource()), selected: 1, crop: true, origin: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
