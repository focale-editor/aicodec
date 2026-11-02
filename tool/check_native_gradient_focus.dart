import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

/// Edits all radial resources across the pinned corpus without altering ramps.
Future<void> main() async {
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/manifest.json').readAsString()) as Map).cast<String, Object?>();
  final Directory output = await Directory('test/corpus/output/gradient-focus').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final Object? raw in manifest['files']! as List) {
    final String name = (raw! as Map)['file'] as String;
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeSource native = AiNativeData.extract(document).single;
    final AiProgram program = AiProgram.decode(bytes: native.bytes);
    final AiNativeGradientResources source = AiNativeGradientResources.decode(records: AiNativeRecords.decode(program: program));
    final Set<String> names = source.definitions.where((definition) => definition.radial).map((definition) => latin1.decode(definition.nameBytes)).toSet();
    AiNativeGradientResources changed = source;
    for (final String target in names) {
      changed = changed.setRadialFocus(
        definition: changed.definitions.firstWhere((definition) => latin1.decode(definition.nameBytes) == target),
        angle: 37,
        length: 0.375,
      );
    }
    await File('${output.path}/$name.original.ps').writeAsBytes(program.bytes);
    await File('${output.path}/$name.edited.ps').writeAsBytes(changed.records.program.bytes);
    report.add({'file': name, 'names': names.toList(), 'angle': 37, 'length': 0.375});
    stdout.writeln('$name: ${names.length} radial resources');
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
}
