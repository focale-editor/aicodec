import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Records source-local capabilities for every pinned native corpus fixture.
Future<void> main() async {
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/manifest.json').readAsString()) as Map).cast<String, Object?>();
  final Directory output = await Directory('test/corpus/output/capabilities').create(recursive: true);
  final List<Map<String, Object?>> rows = [];
  for (final Object? entry in manifest['files']! as List) {
    final String name = (entry! as Map)['file'] as String;
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final List<AiNativeSource> sources = AiNativeData.extract(document);
    for (final (int, AiNativeSource) item in sources.indexed) {
      final AiNativeSource source = item.$2;
      final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
      final String native = '$name.${item.$1}.ps';
      await File('${output.path}/$native').writeAsBytes(source.bytes);
      rows.add({
        'file': name,
        'sourceIndex': item.$1,
        'native': native,
        'owners': source.owners,
        'complete': report.complete,
        'findings': [
          for (final AiNativeCapability finding in report.findings)
            {
              'feature': finding.feature.name,
              'selector': finding.selector,
              'start': finding.start,
              'end': finding.end,
              'support': finding.support.name,
              'editable': finding.editable,
              'message': finding.message,
              'edits': [
                for (final AiNativeEditCapability edit in finding.edits) {'operation': edit.operation.name, 'support': edit.support.name},
              ],
            },
        ],
      });
      stdout.writeln('$name ${item.$1}: ${report.findings.length} findings; complete=${report.complete}');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
}
