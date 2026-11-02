import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentSave;
import '../test/ai_native_gradient_paint_test.dart' show gradientPaintOwner;

/// Writes relative gradient styles for independent native/container inspection.
Future<void> main(List<String> arguments) async {
  final Directory output = await Directory(arguments.isEmpty ? 'test/corpus/output/gradient-paints' : arguments.single).create(recursive: true);
  for (final bool radial in [false, true]) {
    for (final bool stroke in [false, true]) {
      final String name = '${radial ? 'radial' : 'linear'}-${stroke ? 'stroke' : 'fill'}';
      final AiNativeRecords records = gradientPaintOwner(radial: radial, stroke: stroke).structure.drawing.records;
      await File('${output.path}/$name.ps').writeAsBytes(records.program.bytes);
      await File('${output.path}/$name.ai').writeAsBytes(const AiCodec().encode(newDocumentSave(records, newDocumentPdf(blank: true))));
    }
  }
  stdout.writeln('Wrote four gradient-style native/container fixtures; supplied placeholder printing is not rendering acceptance.');
}
