import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource, shapeLifecycleSource, shapeLifecycleStateSource;

/// Decodes complete native programs without generating compatibility artwork.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Reports complete pair spans separately from printable and authoring owners.
List<Map<String, Object?>> shapeLifecycleInventory(AiNativeDrawing drawing) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  return [
    for (final AiLiveShape shape in drawing.liveShapes)
      {
        'start': shape.appearanceGroup == null ? shape.start : objects.forSource(shape.appearanceGroup!).expansion?.start ?? shape.start,
        'artworkStart': shape.start,
        'end': shape.end,
        'handler': shape.handler,
        'path': shape.path == null ? null : [shape.path!.start, shape.path!.end],
        'printing': shape.appearanceGroup == null ? null : [shape.appearanceGroup!.start, shape.appearanceGroup!.end],
        'dictionary': [shape.dictionary.start, shape.dictionary.end],
        'alternatives': [
          for (final AiNativeContainer dictionary in shape.alternativeDictionaries) [dictionary.start, dictionary.end],
        ],
        'style': shape.styleName,
      },
  ];
}

/// Exercises fixed native-pair selections, identity maps and explicit refusals.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/shape-lifecycle').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves exact before/after programs and the selected immutable source handles.
  Future<void> record(String source, String variant, AiNativeDrawing before, List<int> selected, {bool reject = false, Map<AiNativeContainer, List<int>> identifiers = const {}}) async {
    final String original = '$source.original.ps';
    final String result = '$source.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(before.records.program.bytes);
    AiNativeDrawing after = before;
    String? issue;
    try {
      after = before.duplicateLiveShapes(shapes: selected.map((index) => before.liveShapes[index]).toList(), identifiers: identifiers);
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected lifecycle qualification for $source/$variant.');
    }
    await File('${output.path}/$result').writeAsBytes(after.records.program.bytes);
    rows.add({
      'source': source,
      'original': original,
      'result': result,
      'variant': variant,
      'selected': selected,
      'rejected': reject,
      'issue': issue,
      'identifiers': [
        for (final MapEntry<AiNativeContainer, List<int>> entry in identifiers.entries)
          {
            'owner': [entry.key.start, entry.key.end],
            'bytes': entry.value,
          },
      ],
      'before': shapeLifecycleInventory(before),
      'after': shapeLifecycleInventory(after),
    });
    stdout.writeln('$result passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing before = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    if (name.startsWith('simple_shapes')) {
      for (final int index in [1, 2, 3, 4]) {
        await record(name, 'copy-$index', before, [index]);
      }
      await record(name, 'batch', before, [1, 2, 3, 4]);
      await record(name, 'reject-first', before, [0], reject: true);
    } else if (name == 'opacity.ai') {
      await record(name, 'reject-first', before, [1], reject: true);
    } else {
      final int first = name == 'gradient_linear.ai' ? 0 : 1;
      await record(name, 'copy-$first', before, [first]);
      await record(name, 'batch', before, [for (int index = first; index < before.liveShapes.length; index++) index]);
      if (first == 1) {
        await record(name, 'reject-first', before, [0], reject: true);
      }
    }
  }
  final AiNativeDrawing plain = _drawing(latin1.encode(shapeLifecycleSource()));
  await record('synthetic', 'first', plain, [0]);
  await record('synthetic', 'batch', plain, [0, 1]);
  final AiNativeDrawing identified = _drawing(latin1.encode(identifiedShapeLifecycleSource()));
  await record(
    'synthetic-identified',
    'first',
    identified,
    [0],
    identifiers: {identified.liveShapes.first.dictionary: latin1.encode('copy_author'), identified.liveShapes.first.alternativeDictionaries.single: latin1.encode('copy_older')},
  );
  await record('synthetic-state', 'first', _drawing(latin1.encode(shapeLifecycleStateSource())), [0]);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
