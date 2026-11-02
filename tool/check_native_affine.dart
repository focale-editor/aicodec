import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_live_shape_affine_save_test.dart' show affineSave, parallelogramReplacement;
import '../test/ai_live_shape_affine_test.dart';
import '../test/ai_native_test.dart' as fixtures;

/// Emits synthetic structural evidence without rendering native artwork.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/affine').create(recursive: true);
  for (final bool pair in [false, true]) {
    final String prefix = pair ? 'paired' : 'direct';
    final AiPdfDocument original = fixtures.nativePdf(
      compression: .zstandard,
      alias: true,
      thumbnail: true,
      nativeProgram: latin1.decode(affineDrawing(pair: pair).records.program.bytes),
    );
    final AiNativeSource native = AiNativeData.extract(original).single;
    final AiNativeDrawing source = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: native.bytes)),
    );
    final AiNativeParallelogram expected = AiNativeParallelogram(centerX: 15, centerY: 5, ux: 10, uy: 0, vx: 5, vy: 5);
    final AiNativeDrawing sheared = source.transformLiveShapes(
      shapes: source.liveShapes,
      transform: AiNativeAffineTransform.shear(horizontal: 1, vertical: 0, pivotX: 0, pivotY: 0),
      bounds: affineBounds,
      printing: {if (pair) source.liveShapes.single: affinePrinting(expected.segments)},
    );
    final AiNativeDrawing edited = sheared.replaceLiveShapes(
      replacements: [parallelogramReplacement(sheared.liveShapes.single, AiNativeParallelogram(centerX: 20, centerY: 10, ux: 15, uy: 0, vx: 5, vy: 10))],
    );
    for (final (String name, AiNativeDrawing drawing, String pdf) stage in [
      ('sheared', sheared, '0 g 0 0 m 20 0 l 30 10 l 10 10 l h f 50 0 m 60 10 l S'),
      ('edited', edited, '0 g 0 0 m 30 0 l 40 20 l 10 20 l h f 50 0 m 60 10 l S'),
    ]) {
      final String name = '$prefix.${stage.$1}';
      await File('${output.path}/$name.ps').writeAsBytes(stage.$2.records.program.bytes);
      await File('${output.path}/$name.ai').writeAsBytes(const AiCodec().encode(affineSave(original, native, stage.$2, stage.$3)));
    }
  }
  stdout.writeln('Wrote 4 native snapshots and complete AI saves to ${output.path}.');
}
