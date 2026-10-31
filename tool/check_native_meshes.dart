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
    final AiNativeMeshes all = AiNativeMeshes.decode(records: source.records);
    if (all.meshes.length != source.meshes.length || all.meshes.indexed.any((item) => item.$2.start != source.meshes[item.$1].start)) {
      throw StateError('Global and body mesh inventories disagree for $name.');
    }
    if (source.meshes.isEmpty) {
      throw StateError('$name contains no qualified native mesh.');
    }
    await File('${output.path}/$name.ps').writeAsBytes(program.bytes);
    final AiNativeMesh selected = source.meshes.single;
    final List<({int first, int second, AiNativeMeshProcessColor? color, double? opacity})> paints = [
      (first: 0, second: 0, color: AiNativeMeshProcessColor(space: .rgb, components: [0.2, 0.3, 0.4]), opacity: 0.8),
      (first: 5, second: 5, color: AiNativeMeshProcessColor(space: .gray, components: [0.25]), opacity: null),
      (first: 5, second: 11, color: AiNativeMeshProcessColor(space: .cmyk, components: [0.1, 0.2, 0.3, 0.4]), opacity: 0.6),
      (first: 8, second: 7, color: AiNativeMeshProcessColor(space: .rgb, components: [0.6, 0.2, 0.7]), opacity: null),
      (first: 15, second: 12, color: null, opacity: 0.3),
    ];
    final AiNativeMeshes painted = source.paintVertices(
      mesh: selected,
      changes: [
        for (final paint in paints)
          AiNativeMeshVertexPaint(
            vertex: selected.vertices.singleWhere((vertex) => vertex.firstIndex == paint.first && vertex.secondIndex == paint.second),
            color: paint.color,
            opacity: paint.opacity,
          ),
      ],
    );
    final AiNativeMeshes translucent = source.paintVertices(
      mesh: selected,
      changes: selected.vertices.map((vertex) => AiNativeMeshVertexPaint(vertex: vertex, opacity: 0.5)).toList(),
    );
    final AiNativeMeshes inked = source.paintVertices(
      mesh: selected,
      changes: [
        AiNativeMeshVertexPaint(vertex: selected.vertices.singleWhere((vertex) => vertex.firstIndex == 5 && vertex.secondIndex == 11), tints: [0.21, 0.43, 0.65]),
        AiNativeMeshVertexPaint(vertex: selected.vertices.singleWhere((vertex) => vertex.firstIndex == 8 && vertex.secondIndex == 7), tints: [0.45], opacity: 0.6),
      ],
    );
    await File('${output.path}/$name.painted.ps').writeAsBytes(painted.records.program.bytes);
    await File('${output.path}/$name.translucent.ps').writeAsBytes(translucent.records.program.bytes);
    await File('${output.path}/$name.inked.ps').writeAsBytes(inked.records.program.bytes);
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
            'vertices': [
              for (final AiNativeMeshVertex vertex in mesh.vertices)
                {
                  'indices': [vertex.firstIndex, vertex.secondIndex],
                  'position': [vertex.position.x, vertex.position.y],
                  'corners': vertex.corners.map((corner) => corner.field.start).toList(),
                },
            ],
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
                        'inks': [
                          for (final AiNativeMeshInk ink in node.colorSpace?.inks ?? <AiNativeMeshInk>[]) {'name': ink.nameBytes.toList(), 'deviceName': ink.deviceName, 'components': ink.components},
                        ],
                        'inkTints': [
                          for (final component in node.inkTints) {'name': component.ink.nameBytes.toList(), 'tint': component.tint},
                        ],
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
