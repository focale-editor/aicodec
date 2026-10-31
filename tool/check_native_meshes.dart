import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Projects every mesh record and node from the required external corpus.
Future<void> main() async {
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/mesh_manifest.json').readAsString()) as Map).cast<String, Object?>();
  final Directory output = await Directory('test/corpus/output/meshes').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final Object? raw in manifest['files']! as List) {
    final String name = (raw! as Map)['file'] as String;
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiProgram program = AiProgram.decode(bytes: AiNativeData.extract(document).single.bytes);
    final AiNativeMeshes source = AiNativeMeshes.decode(records: AiNativeRecords.decode(program: program), bodyOnly: true);
    if (source.meshes.isEmpty) {
      throw StateError('$name contains no qualified native mesh.');
    }
    await File('${output.path}/$name.ps').writeAsBytes(program.bytes);
    report.add({
      'file': name,
      'meshes': [
        for (final AiNativeMesh mesh in source.meshes)
          {
            'start': mesh.start,
            'end': mesh.end,
            'version': mesh.version,
            'size': [mesh.size.first, mesh.size.second],
            'private': mesh.isPrivate,
            'fields': mesh.fields.map(_field).toList(),
            'patches': [
              for (final AiNativeMeshPatch patch in mesh.patches)
                {
                  'position': [patch.firstIndex, patch.secondIndex],
                  'nodes': [
                    for (final AiNativeMeshNode node in patch.nodes)
                      {
                        'kind': node.kind.name,
                        'position': [node.position.x, node.position.y],
                        'firstHandle': [node.firstHandle.x, node.firstHandle.y],
                        'secondHandle': [node.secondHandle.x, node.secondHandle.y],
                        'weights': node.weights,
                        'color': node.color,
                        'opacity': node.opacity,
                        'space': node.colorSpace?.field?.values.map((token) => token.lexeme).toList(),
                        'deviceName': node.colorSpace?.deviceName,
                      },
                  ],
                },
            ],
          },
      ],
    });
    stdout.writeln('$name: ${source.meshes.length} mesh, ${source.meshes.fold(0, (count, mesh) => count + mesh.patches.length)} patches');
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
}

/// Keeps exact token lexemes and offsets for the independent source comparison.
Map<String, Object?> _field(AiNativeMeshField field) => {
  'key': field.key,
  'start': field.start,
  'end': field.end,
  'values': field.values.map((token) => token.lexeme).toList(),
};
