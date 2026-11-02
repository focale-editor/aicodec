import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource, shapeLifecycleSource, shapeLifecycleStateSource;
import '../test/ai_native_shape_removal_test.dart' show followingShapeSource;
import 'check_native_shape_lifecycle.dart' show shapeLifecycleInventory;

/// Opens native programs independently of their host-supplied compatibility PDF.
AiNativeDrawing _drawing(List<int> bytes) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: bytes)),
);

/// Selects complete pairs without conflating direct ordinary shape owners.
List<AiLiveShape> _pairs(AiNativeDrawing drawing) => drawing.liveShapes.where((shape) => shape.appearanceGroup != null && shape.path?.isPrivate == true).toList();

/// Saves fixed real-file and synthetic complete-pair removal transactions.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/shape-removal').create(recursive: true);
  final List<Map<String, Object?>> rows = [];

  /// Retains both exact programs and the selected source pair indices.
  Future<void> record(String name, String variant, AiNativeDrawing source, List<int> selected, {bool reject = false}) async {
    final List<AiLiveShape> pairs = _pairs(source);
    AiNativeDrawing result = source;
    String? issue;
    try {
      result = source.removeLiveShapes(shapes: selected.map((index) => pairs[index]).toList());
    } on UnsupportedError catch (error) {
      if (!reject) {
        rethrow;
      }
      issue = error.message;
    }
    if (reject != (issue != null)) {
      throw StateError('Unexpected removal qualification for $name/$variant.');
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
      'selected': selected,
      'rejected': reject,
      'issue': issue,
      'before': shapeLifecycleInventory(source).where((shape) => shape['printing'] != null).toList(),
      'after': shapeLifecycleInventory(result).where((shape) => shape['printing'] != null).toList(),
    });
    stdout.writeln('$target passed');
  }

  for (final String name in ['simple_shapes.ai', 'simple_shapes_cc.ai', 'opacity.ai', 'gradient_linear.ai', 'gradient_radial.ai']) {
    final AiNativeDrawing source = _drawing(AiNativeData.extract(const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes())).single.bytes);
    final int count = _pairs(source).length;
    await record(name, 'first', source, [0]);
    if (count > 1) {
      await record(name, 'last', source, [count - 1]);
      await record(name, 'alternating', source, [for (int index = 0; index < count; index += 2) index]);
      await record(name, 'all', source, [for (int index = 0; index < count; index++) index]);
    }
  }
  final AiNativeDrawing plain = _drawing(latin1.encode(shapeLifecycleSource()));
  await record('synthetic', 'first', plain, [0]);
  await record('synthetic', 'last', plain, [1]);
  await record('synthetic', 'all', plain, [0, 1]);
  final AiNativeDrawing identified = _drawing(latin1.encode(identifiedShapeLifecycleSource()));
  await record('synthetic-identified', 'first', identified, [0]);
  await record('synthetic-identified', 'all', identified, [0, 1]);
  await record('synthetic-state', 'first', _drawing(latin1.encode(shapeLifecycleStateSource())), [0]);
  await record('synthetic-width', 'first', _drawing(latin1.encode(shapeLifecycleSource().replaceFirst('0 0 0 1 k /Def', '2 w 0 0 0 1 k /Def'))), [0]);
  await record('synthetic-following', 'last', _drawing(latin1.encode(followingShapeSource())), [1], reject: true);
  await record(
    'synthetic-reference',
    'first',
    _drawing(latin1.encode(identifiedShapeLifecycleSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author) ; (UnknownReference) , ;\n%%EndSetup'))),
    [0],
    reject: true,
  );
  await record('synthetic-alias', 'first', _drawing(latin1.encode(identifiedShapeLifecycleSource().replaceFirst('(older)', '(author)'))), [0], reject: true);
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(rows)}\n');
}
