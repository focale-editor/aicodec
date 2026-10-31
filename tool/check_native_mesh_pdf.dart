import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import 'mesh_corpus.dart';

/// Regenerates source-derived mesh excerpts and optionally the complete drawing.
///
/// `--full` requires full-document native/PDF synchronization. The pinned file's
/// unrelated opacity mask currently rejects that mode; excerpt checks never
/// package edited native data with stale full-document PDF artwork.
Future<void> main(List<String> arguments) async {
  if (arguments.any((argument) => argument != '--full')) {
    throw ArgumentError('Only --full is accepted.');
  }
  const String name = 'gradient_mesh_apple_example_1.ai';
  final Directory output = await Directory('test/corpus/output/mesh-pdf').create(recursive: true);
  final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
  final AiNativeSource source = AiNativeData.extract(document).single;
  final AiProgram program = AiProgram.decode(bytes: source.bytes);
  final AiNativeMeshes meshes = AiNativeMeshes.decode(records: AiNativeRecords.decode(program: program), bodyOnly: true);
  final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: -519, right: 822, top: 0);
  final AiNativeMesh mesh = meshes.meshes.single;
  final AiProgram isolated = _excerpt(meshes);
  final PdfDocument meshOnly = AiNativePdf.render(program: isolated, bounds: bounds, resolveMeshColor: resolveMeshProcessColor);
  await File('${output.path}/mesh.pdf').writeAsBytes(const PdfEncoder().convert(meshOnly));
  if (arguments.contains('--full')) {
    final PdfDocument baseline = AiNativePdf.render(program: program, bounds: bounds, resolveMeshColor: resolveMeshProcessColor);
    await File('${output.path}/baseline.pdf').writeAsBytes(const PdfEncoder().convert(baseline));
  }
  for (final bool opacity in [false, true]) {
    final AiNativeMeshes changed = meshes.paintVertices(
      mesh: mesh,
      changes: [
        for (final AiNativeMeshVertex vertex in mesh.vertices)
          if (opacity || vertex.firstIndex == 5 && vertex.secondIndex == 5)
            AiNativeMeshVertexPaint(
              vertex: vertex,
              color: opacity ? null : AiNativeMeshProcessColor(space: .cmyk, components: [0.9, 0.1, 0.1, 0]),
              opacity: opacity ? 0.5 : null,
            ),
      ],
    );
    final String variant = opacity ? 'opacity' : 'painted';
    await File('${output.path}/$variant.ps').writeAsBytes(changed.records.program.bytes);
    final PdfDocument rendered = AiNativePdf.render(program: _excerpt(changed), bounds: bounds, resolveMeshColor: resolveMeshProcessColor);
    await File('${output.path}/$variant.pdf').writeAsBytes(const PdfEncoder().convert(rendered));
    if (arguments.contains('--full')) {
      final AiPdfDocument saved = AiNativePdf.save(source: source, program: changed.records.program, pageBounds: [bounds], resolveMeshColor: resolveMeshProcessColor);
      await File('${output.path}/$variant.ai').writeAsBytes(const AiCodec().encode(saved));
      final List<int> recovered = AiNativeData.extract(const AiCodec().decode(await File('${output.path}/$variant.ai').readAsBytes())).single.bytes;
      if (recovered.length != changed.records.program.bytes.length || recovered.indexed.any((item) => item.$2 != changed.records.program.bytes[item.$1])) {
        throw StateError('Saved native mesh program differs from its edited snapshot.');
      }
    }
    stdout.writeln('$variant: source-native mesh excerpt rendered');
  }
  stdout.writeln('Mesh excerpt PDF generated${arguments.contains('--full') ? ' and full drawing synchronized' : ''}.');
}

/// Selects only the native mesh packet for a clearly separated rendering probe.
AiProgram _excerpt(AiNativeMeshes meshes) {
  final AiNativeMesh mesh = meshes.meshes.single;
  final String body = latin1.decode(meshes.records.program.bytes.sublist(mesh.start, mesh.end));
  return AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'));
}
