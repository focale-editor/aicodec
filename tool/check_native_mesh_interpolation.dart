import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Evaluates native tensors and colors at independently located Adobe samples.
Future<void> main() async {
  final Directory output = Directory('test/corpus/output/meshes');
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/mesh_manifest.json').readAsString()) as Map).cast<String, Object?>();
  final List<Object?> reference = jsonDecode(await File('${output.path}/interpolation-oracle-report.json').readAsString()) as List;
  final List<Map<String, Object?>> results = [];
  for (final Object? raw in manifest['files']! as List) {
    final String name = (raw! as Map)['file'] as String;
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeMeshes meshes = AiNativeMeshes.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(document).single.bytes)),
      bodyOnly: true,
    );
    final AiNativeMesh mesh = meshes.meshes.single;
    final AiNativeMeshInterpolation interpolation = AiNativeMeshInterpolation(mesh: mesh, resolveColor: _processColor);
    final Map<String, Object?> row = (reference.singleWhere((item) => (item! as Map)['file'] == name)! as Map).cast<String, Object?>();
    final List<Map<String, Object?>> samples = [];
    for (final Object? value in row['matches']! as List) {
      final Map<String, Object?> match = (value! as Map).cast<String, Object?>();
      final List<Object?> indices = match['nativeCell']! as List;
      final AiNativeMeshPatch patch = mesh.patches.singleWhere((patch) => patch.firstIndex == indices[0] && patch.secondIndex == indices[1]);
      final List<List<double>> parameters = [for (final Object? point in match['parameters']! as List) (point! as List).map((value) => (value as num).toDouble()).toList()];
      samples.add({
        'pdfPatch': match['pdfPatch'],
        'parameters': parameters,
        'colors': [for (final List<double> point in parameters) interpolation.colorAt(patch: patch, first: point[0], second: point[1]).components],
      });
    }
    results.add({
      'file': name,
      'space': interpolation.space.name,
      'opacity': interpolation.opacity,
      'surfaces': [
        for (final AiNativeMeshSurface surface in interpolation.surfaces)
          {
            'cell': [surface.patch.firstIndex, surface.patch.secondIndex],
            'bounds': [surface.bounds.firstStart, surface.bounds.firstEnd, surface.bounds.secondStart, surface.bounds.secondEnd],
            'controls': surface.controlPoints.map((point) => [point.x, point.y]).toList(),
            'positions': [
              for (final (double, double) parameters in const [(0.0, 0.0), (0.2, 0.7), (0.5, 0.5), (1.0, 1.0)]) _position(surface, parameters.$1, parameters.$2),
            ],
          },
      ],
      'samples': samples,
    });
    stdout.writeln('$name: ${interpolation.surfaces.length} Dart surfaces, ${samples.length * 4} color samples');
  }
  await File('${output.path}/dart-interpolation.json').writeAsString(const JsonEncoder.withIndent('  ').convert(results));
}

/// Records public geometry evaluation independently of direct control access.
List<double> _position(AiNativeMeshSurface surface, double first, double second) {
  final ({double x, double y}) point = surface.positionAt(first: first, second: second);
  return [point.x, point.y];
}

/// Maps only this pinned fixture's canonical process inks into explicit CMYK.
AiNativeMeshProcessColor _processColor(AiNativeMeshNode corner) {
  if (corner.colorSpace!.deviceName == 'DeviceCMYK') {
    return AiNativeMeshProcessColor(space: .cmyk, components: corner.color);
  }
  if (corner.colorSpace!.deviceName == 'DeviceGray') {
    return AiNativeMeshProcessColor(space: .cmyk, components: [0, 0, 0, 1 - corner.color.single]);
  }
  const Map<String, List<double>> alternatives = {
    'Cyan': [1, 0, 0, 0],
    'Magenta': [0, 1, 0, 0],
    'Yellow': [0, 0, 1, 0],
    'Black': [0, 0, 0, 1],
  };
  final List<double> components = [0, 0, 0, 0];
  if (corner.inkTints.isEmpty) {
    throw StateError('Missing qualified process inks.');
  }
  for (final ({AiNativeMeshInk ink, double tint}) tint in corner.inkTints) {
    final List<double>? expected = alternatives[latin1.decode(tint.ink.nameBytes)];
    if (expected == null || tint.ink.deviceName != 'DeviceCMYK' || tint.ink.components.indexed.any((component) => component.$2 != expected[component.$1])) {
      throw StateError('Unexpected process ink declaration.');
    }
    for (int component = 0; component < 4; component++) {
      components[component] += expected[component] * tint.tint;
    }
  }
  return AiNativeMeshProcessColor(space: .cmyk, components: components);
}
