import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Exercises a real CC placement with both its preview and host-resolved pixels.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-placements').create(recursive: true);
  final AiPostScriptDocument document = const AiCodec().decode(await File('test/corpus/files/image_linked_original_cc.ai').readAsBytes()) as AiPostScriptDocument;
  if (document.dscIssue != null) {
    throw StateError('The intact placement must have complete DSC metadata.');
  }
  final AiProgram program = AiProgram.decode(bytes: document.postScriptBytes);
  final AiNativePlacements placements = AiNativePlacements.decode(records: AiNativeRecords.decode(program: program));
  final AiNativePlacedObject object = placements.objects.single;
  final AiNativePlacedPreview preview = object.preview!;
  await File('${output.path}/original.ps').writeAsBytes(program.bytes);
  await File('${output.path}/preview.argb').writeAsBytes(preview.bytes);
  final AiNativePlacements moved = placements.translate(objects: placements.objects, deltaX: 37, deltaY: -19);
  await File('${output.path}/translated.ps').writeAsBytes(moved.records.program.bytes);
  final AiDocument host = const AiCodec().decode(await File('test/corpus/files/raster_v2020.ai').readAsBytes());
  final AiNativeRasters hostImages = AiNativeRasters.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(host).single.bytes)),
  );
  final AiNativeRaster resolved = hostImages.images.singleWhere((image) => image.isPrintable(program: hostImages.records.program));
  final AiNativeRasterSamples full = AiNativeRasterSamples(
    width: resolved.width,
    height: resolved.height,
    bitsPerComponent: resolved.bitsPerComponent,
    components: resolved.components,
    colorSamples: resolved.colorSamples,
    alphaSamples: resolved.alphaSamples,
  );
  await File('${output.path}/host-source.ps').writeAsBytes(hostImages.records.program.bytes);
  final List<Map<String, Object?>> variants = [];
  final List<(String, AiNativePlacements, AiNativeRasterSamples)> cases = [('preview', placements, preview.toSamples()), ('resolved', placements, full), ('translated', moved, full)];
  for (final (String, AiNativePlacements, AiNativeRasterSamples) variant in cases) {
    final AiNativeRasters embedded = variant.$2.embed(object: variant.$2.objects.single, samples: variant.$3);
    await File('${output.path}/${variant.$1}.embedded.ps').writeAsBytes(embedded.records.program.bytes);
    variants.add({'variant': variant.$1, 'width': variant.$3.width, 'height': variant.$3.height, 'components': variant.$3.components});
  }
  await File('${output.path}/report.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'pathBytes': object.pathBytes,
      'relativeDirectoryBytes': object.relativeDirectoryBytes,
      'matrix': object.matrix,
      'bounds': object.bounds,
      'preview': {'width': preview.width, 'height': preview.height, 'rowBytes': preview.rowBytes, 'bits': preview.bitsPerPixel, 'format': preview.format},
      'variants': variants,
    }),
  );
  stdout.writeln('CC placement: three native embedding variants and translated placement saved');
}
