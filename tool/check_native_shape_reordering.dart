import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;
import '../test/ai_native_shape_reordering_test.dart' show shapeReorderingSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;

/// Opens native programs without changing their compatibility representations.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Records fixed sibling-slot permutations and explicit input/state refusals.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/shape-reordering').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Saves both exact programs and the requested original source-handle ordering.
  Future<void> record(String name, String variant, AiNativeDrawing source, List<int> order, {bool reject = false}) async {
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = source.reorderLiveShapes(shapes: order.map((index) => source.liveShapes[index]).toList());
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected reordering qualification for $name/$variant.');
    }
    final String original = '$name.original.ps';
    final String target = '$name.$variant.ps';
    await File('${output.path}/$original').writeAsBytes(source.records.program.bytes);
    await File('${output.path}/$target').writeAsBytes(result.records.program.bytes);
    rows.add({
      'source': name,
      'variant': variant,
      'original': original,
      'result': target,
      'order': order,
      'rejected': reject,
      'issue': issue,
      'before': shapeLifecycleInventory(source),
      'after': shapeLifecycleInventory(result),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing source = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final int first = name == 'gradient_linear.ai' ? 0 : 1;
    await record(name, 'adjacent', source, [first + 1, first]);
    await record(name, 'ends', source, [source.liveShapes.length - 1, first]);
    await record(name, 'reverse', source, [for (int index = source.liveShapes.length - 1; index >= first; index--) index]);
    if (first == 0) {
      await record(name, 'unchanged', source, [0, 1]);
    } else {
      await record(name, 'reject-first', source, [1, 0], reject: true);
    }
  }
  final AiNativeDrawing plain = _drawing(latin1.encode(shapeReorderingSource()));
  await record('synthetic', 'rotate', plain, [2, 0, 1]);
  await record('synthetic', 'ends', plain, [2, 0]);
  await record('synthetic', 'reverse', plain, [2, 1, 0]);
  await record('synthetic', 'unchanged', plain, [0, 1, 2]);
  await record('synthetic-unknown', 'reverse', _drawing(latin1.encode(identifiedShapeLifecycleSource().replaceFirst('0 A 0 Xw ', ''))), [1, 0]);
  await record('synthetic-panel', 'reverse', _drawing(latin1.encode(shapeReorderingSource().replaceFirst('\nu\n', '\n0 Ae\nu\n'))), [2, 1, 0]);
  await record(
    'synthetic-reference',
    'reverse',
    _drawing(latin1.encode(shapeReorderingSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author_0) ; (Reference) , ;\n%%EndSetup'))),
    [2, 1, 0],
  );
  await record('synthetic-following', 'reverse', _drawing(latin1.encode(shapeReorderingSource().replaceFirst('%%Trailer', '70 70 m 80 80 L f\n%%Trailer'))), [2, 1, 0], reject: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
