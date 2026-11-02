import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_symbols_test.dart' show symbolInspectionInstance, symbolInspectionMaster, symbolInspectionResources, symbolInspectionSource;

/// Emits source-bound symbol references for independent parser comparison.
Future<void> main(List<String> arguments) async {
  final Directory output = await Directory(arguments.isEmpty ? 'test/corpus/output/symbol-inspection' : arguments.single).create(recursive: true);

  /// Gives the independent reader an executable header even for empty masters.
  String declaration(String name, {String artwork = ''}) => symbolInspectionMaster(name, artwork: '0 A\n$artwork');

  final Map<String, String> fixtures = {
    'literal': symbolInspectionSource(setup: declaration('S'), body: '${symbolInspectionInstance('S')}${symbolInspectionInstance('Missing')}'),
    'duplicate': symbolInspectionSource(setup: '${declaration('S')}${declaration('S')}', body: symbolInspectionInstance('S')),
    'branches': symbolInspectionSource(
      setup:
          '%AI17_Begin_Content_if_version_gt:24 4\n${declaration('S')}${symbolInspectionInstance('S')}%AI17_Alternate_Content\n${declaration('S')}${symbolInspectionInstance('S')}%AI17_End_Versioned_Content\n',
      body: symbolInspectionInstance('S'),
    ),
    'local': symbolInspectionSource(
      setup: '${declaration('S')}${declaration('Container', artwork: symbolInspectionInstance('S'))}',
      body: symbolInspectionInstance('Container'),
    ),
  };
  final List<Map<String, Object?>> report = [];
  for (final MapEntry<String, String> fixture in fixtures.entries) {
    final AiNativeArtworkResources resources = symbolInspectionResources(fixture.value);
    final AiNativeSymbols symbols = AiNativeSymbols.decode(artworkResources: resources);
    await File('${output.path}/${fixture.key}.ps').writeAsBytes(resources.structure.drawing.records.program.bytes);
    report.add({
      'source': fixture.key,
      'definitions': [
        for (final AiNativeArtworkResource resource in resources.resources)
          {
            'span': [resource.start, resource.end],
            'body': [resource.artworkStart, resource.artworkEnd],
            'name': resource.nameBytes,
          },
      ],
      'instances': [
        for (final AiNativeSymbolInstance instance in symbols.instances)
          {
            'span': [instance.record.start, instance.record.end],
            'name': instance.nameBytes,
            'matrix': instance.relativeTransform,
            'candidates': instance.candidates.map(resources.resources.indexOf).toList(),
            'resolution': instance.resolution?.name,
            'resource': instance.resource == null ? null : resources.resources.indexOf(instance.resource!),
          },
      ],
    });
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln('Wrote four synthetic symbol inspection cases; no instance creation or rendering acceptance is implied.');
}
