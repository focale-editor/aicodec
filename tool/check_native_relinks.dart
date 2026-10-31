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
  final List<int> path = utf8.encode(File('${output.path}/assets/relinked-apple.png').absolute.path);
  final List<int> relative = utf8.encode('assets');
  await File('${output.path}/original.ps').writeAsBytes(source.records.program.bytes);
  final List<String> variants = [];
  for (final bool preview in [true, false]) {
    final String variant = preview ? 'with-preview' : 'without-preview';
    final AiNativePlacements changed = source.relink(object: object, pathBytes: path, relativeDirectoryBytes: relative, preview: preview ? replacement : null);
    final AiProgram program = changed.records.program;
    await File('${output.path}/$variant.native.ps').writeAsBytes(program.bytes);
    variants.add(variant);
  }
  await File(
    '${output.path}/report.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert({'pathBytes': path, 'relativeDirectoryBytes': relative, 'width': replacement.width, 'height': replacement.height, 'variants': variants}));
  stdout.writeln('CC relinking: two native variants saved');
}
