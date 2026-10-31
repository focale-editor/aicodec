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
      for (final (String, AiProgram) variant in [('rebuilt', program), ('translated', moved.records.program)]) {
        final PdfDocument pdf;
        if (document is AiPdfDocument) {
          final AiPdfDocument saved = AiNativePdf.save(source: source, program: variant.$2, pageBounds: [rectangle]);
          pdf = saved.pdf;
          await File('${output.path}/$name.${variant.$1}.ai').writeAsBytes(const AiCodec().encode(saved));
        } else {
          pdf = AiNativePdf.render(program: variant.$2, bounds: rectangle);
        }
        await File('${output.path}/$name.${variant.$1}.pdf').writeAsBytes(const PdfEncoder().convert(pdf));
      }
    } else {
      bounds = null;
    }
    report.add({'file': name, 'pdfBacked': document is AiPdfDocument, 'images': images, 'bounds': bounds});
    stdout.writeln('$name: ${images.length} images inspected, ${printable.length} translated and rendered');
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
  await _probes(output);
}

/// Places known RGB/alpha samples over blue with object-level transparency.
Future<void> _probes(Directory output) async {
  final AiProgram program = AiProgram.decode(
    bytes: [
      ...latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%EndSetup
0 0 1 Xa 0 0 m 100 0 L 100 100 L 0 100 L f
0 0.5 0 0 0 Xy
%AI5_BeginRaster
() 1 XG
/DeviceRGB XN
[ 40 0 0 40 10 90 ] 2 2 0 Xh
[ 40 0 0 40 10 90 ] 0 0 2 2 2 2 8 3 1 17 1 0 4 4 0 0
%%BeginData: 16
XI
'''),
      255,
      0,
      0,
      0,
      255,
      0,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      128,
      0,
      255,
      ...latin1.encode('%%EndData\nXH\n%AI5_EndRaster\nN\n%%Trailer\n%%EOF\n'),
    ],
  );
  final PdfDocument pdf = AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100));
  await File('${output.path}/alpha-probes.pdf').writeAsBytes(const PdfEncoder().convert(pdf));
  final AiProgram stencil = AiProgram.decode(
    bytes: [
      ...latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%EndSetup
0 0 1 Xa 0 0 m 100 0 L 100 100 L 0 100 L f
1 0 0 Xa
%AI5_BeginRaster
() 1 XG
[ 40 0 0 80 10 90 ] 2 1 0 Xh
[ 40 0 0 80 10 90 ] 0 0 2 1 2 1 1 1 0 0 1 1
%%BeginData: 5
XI
'''),
      0x40,
      ...latin1.encode('%%EndData\nXH\n%AI5_EndRaster\nN\n%%Trailer\n%%EOF\n'),
    ],
  );
  await File('${output.path}/stencil-probes.pdf').writeAsBytes(const PdfEncoder().convert(AiNativePdf.render(program: stencil, bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100))));
}
