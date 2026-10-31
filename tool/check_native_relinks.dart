import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Relinks an intact CC file while retaining its placed extent and native art.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-relinks').create(recursive: true);
  final AiPostScriptDocument original = const AiCodec().decode(await File('test/corpus/files/image_linked_original_cc.ai').readAsBytes()) as AiPostScriptDocument;
  final AiNativePlacements source = AiNativePlacements.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: original.postScriptBytes)),
  );
  final AiNativePlacedObject object = source.objects.single;
  final AiNativeRasterSamples previous = object.preview!.toSamples();
  final AiNativeRasterSamples replacement = AiNativeRasterSamples(
    width: previous.width,
    height: previous.height,
    bitsPerComponent: 8,
    components: 3,
    colorSamples: previous.colorSamples.map((value) => 255 - value).toList(),
  );
  final AiPdfDocument carrier = const AiCodec().decode(await File('test/corpus/output/native-placements/resolved.linked.ai').readAsBytes()) as AiPdfDocument;
  final AiNativeSource native = AiNativeData.extract(carrier).single;
  if (native.bytes.length != original.postScriptBytes.length || native.bytes.indexed.any((item) => item.$2 != original.postScriptBytes[item.$1])) {
    throw StateError('Generate the linked PDF carrier with check_native_placements.dart first.');
  }
  final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: -792, right: 612, top: 0);
  final List<int> path = utf8.encode(File('${output.path}/assets/relinked-apple.png').absolute.path);
  final List<int> relative = utf8.encode('assets');
  await File('${output.path}/original.ps').writeAsBytes(source.records.program.bytes);
  final List<String> variants = [];
  for (final bool preview in [true, false]) {
    final String variant = preview ? 'with-preview' : 'without-preview';
    final AiNativePlacements changed = source.relink(object: object, pathBytes: path, relativeDirectoryBytes: relative, preview: preview ? replacement : null);
    final AiProgram program = changed.records.program;
    await File('${output.path}/$variant.native.ps').writeAsBytes(program.bytes);
    await File('${output.path}/$variant.pdf').writeAsBytes(const PdfEncoder().convert(AiNativePdf.render(program: program, bounds: bounds, resolvePlacement: (object) => replacement)));
    final AiPdfDocument saved = AiNativePdf.save(source: native, program: program, pageBounds: [bounds], resolvePlacement: (object) => replacement);
    await File('${output.path}/$variant.ai').writeAsBytes(const AiCodec().encode(saved));
    variants.add(variant);
  }
  await File(
    '${output.path}/report.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert({'pathBytes': path, 'relativeDirectoryBytes': relative, 'width': replacement.width, 'height': replacement.height, 'variants': variants}));
  stdout.writeln('CC relinking: two native variants, two PDFs and two synchronized AI files saved');
}
