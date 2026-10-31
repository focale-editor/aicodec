import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Exposes real native image samples and synchronized placement for verification.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-rasters').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final String name in ['raster_ai8.ai', 'raster_v2020.ai', 'empty_cs.ai', 'empty_cs2.ai', 'simple_shapes_cc.ai']) {
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    if (document is AiPostScriptDocument && document.dscIssue != null) {
      throw StateError('Valid raster fixture has incomplete DSC metadata: $name');
    }
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiProgram program = AiProgram.decode(bytes: source.bytes);
    final AiNativeRasters rasters = AiNativeRasters.decode(records: AiNativeRecords.decode(program: program));
    await File('${output.path}/$name.native.ps').writeAsBytes(program.bytes);
    final List<Map<String, Object?>> images = [];
    for (final (int, AiNativeRaster) item in rasters.images.indexed) {
      final AiNativeRaster image = item.$2;
      final String prefix = '$name.${item.$1}';
      await File('${output.path}/$prefix.colors.bin').writeAsBytes(image.colorSamples);
      if (image.alphaSamples case final List<int> alpha) {
        await File('${output.path}/$prefix.alpha.bin').writeAsBytes(alpha);
      }
      images.add({
        'prefix': prefix,
        'width': image.width,
        'height': image.height,
        'components': image.components,
        'bits': image.bitsPerComponent,
        'alpha': image.hasAlpha,
        'private': image.instruction.isPrivate,
        'printable': image.isPrintable(program: program),
        'matrix': image.matrix,
        'bounds': image.bounds,
      });
    }
    final List<AiNativeRaster> printable = rasters.images.where((image) => image.isPrintable(program: program)).toList();
    final List<double>? bounds;
    if (printable.isNotEmpty) {
      final AiBoundingBox rectangle = AiBoundingBox.parse(value: RegExp(r'%AI3_Cropmarks:\s*([^\r\n]+)').firstMatch(latin1.decode(program.bytes))![1]!);
      bounds = [rectangle.left, rectangle.bottom, rectangle.right, rectangle.top];
      final AiNativeRasters moved = rasters.translate(images: printable, deltaX: 37, deltaY: -19);
      await File('${output.path}/$name.translated.ps').writeAsBytes(moved.records.program.bytes);
    } else {
      bounds = null;
    }
    report.add({'file': name, 'pdfBacked': document is AiPdfDocument, 'images': images, 'bounds': bounds});
    stdout.writeln('$name: ${images.length} images inspected, ${printable.length} translated');
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  final Map<String, Object?> rejected = (jsonDecode(await File('test/corpus/raster_manifest.json').readAsString()) as Map).cast<String, Object?>();
  final List<Map<String, Object?>> rejections = [];
  for (final Object? entry in rejected['files']! as List) {
    final String name = (entry! as Map)['file']! as String;
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    if (document is! AiPostScriptDocument || !(document.dscIssue?.message.contains('raster data boundary') ?? false)) {
      throw StateError('Damaged raster fixture requires an explicit DSC boundary diagnostic: $name');
    }
    try {
      AiProgram.decode(bytes: AiNativeData.extract(document).single.bytes);
      throw StateError('Damaged raster data was accepted: $name');
    } on FormatException catch (error) {
      if (!error.message.contains('raster data boundary')) {
        rethrow;
      }
      rejections.add({'file': name, 'error': error.message, 'dscIssueOffset': document.dscIssue!.offset});
    }
  }
  await File('${output.path}/rejections.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rejections));
}
