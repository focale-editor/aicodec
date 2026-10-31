import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aikit/aikit.dart';

/// Composes a host-selected drawing transform with an existing native matrix.
List<double> _compose(List<double> transform, List<double> matrix) => [
  transform[0] * matrix[0] + transform[2] * matrix[1],
  transform[1] * matrix[0] + transform[3] * matrix[1],
  transform[0] * matrix[2] + transform[2] * matrix[3],
  transform[1] * matrix[2] + transform[3] * matrix[3],
  transform[0] * matrix[4] + transform[2] * matrix[5] + transform[4],
  transform[1] * matrix[4] + transform[3] * matrix[5] + transform[5],
];

/// Chooses three distinct affine operations about the fixed artboard center.
Map<String, List<double>> _transforms(AiBoundingBox bounds) {
  final double x = (bounds.left + bounds.right) / 2;
  final double y = (bounds.bottom + bounds.top) / 2;
  return {
    for (final (String, List<double>) item in <(String, List<double>)>[
      ('resize', [0.75, 0, 0, 0.5]),
      ('rotate', [0, 0.5, -0.5, 0]),
      ('reflect-shear', [-0.75, 0.125, 0.25, 0.75]),
    ])
      item.$1: [...item.$2, x - item.$2[0] * x - item.$2[2] * y, y - item.$2[1] * x - item.$2[3] * y],
  };
}

/// Supplies an explicit transformed frame-axis angle when metadata is present.
double? _angle(AiNativeContainer? dictionary, List<double> transform) {
  final AiNativeEntry? entry = dictionary?['BBAccumRotation'];
  if (entry == null) {
    return null;
  }
  final double before = entry.number ?? double.parse(entry.text()!);
  final double x = cos(before);
  final double y = sin(before);
  return atan2(transform[1] * x + transform[3] * y, transform[0] * x + transform[2] * y);
}

/// Saves real native affine edits and independent-verifier inputs.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-image-geometry').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final String name in ['raster_ai8.ai', 'raster_v2020.ai', 'empty_cs.ai', 'empty_cs2.ai', 'simple_shapes_cc.ai']) {
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeSource native = AiNativeData.extract(document).single;
    final AiNativeRasters original = AiNativeRasters.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: native.bytes)),
    );
    final RegExpMatch? crop = RegExp(r'%AI3_Cropmarks:\s*([^\r\n]+)').firstMatch(latin1.decode(native.bytes));
    final AiBoundingBox bounds = crop == null ? AiBoundingBox(left: 0, bottom: -792, right: 612, top: 0) : AiBoundingBox.parse(value: crop[1]!);
    await File('${output.path}/$name.original.ps').writeAsBytes(native.bytes);
    final List<int> selected = [
      for (final (int, AiNativeRaster) item in original.images.indexed)
        if (!item.$2.instruction.isPrivate) item.$1,
    ];
    final bool printable = original.images.any((image) => image.isPrintable(program: original.records.program));
    final Map<String, List<double>> transforms = _transforms(bounds);
    for (final MapEntry<String, List<double>> operation in transforms.entries) {
      AiNativeRasters changed = original;
      for (final int index in selected) {
        final AiNativeRaster image = changed.images[index];
        changed = changed.setPlacement(image: image, matrix: _compose(operation.value, image.matrix), rotationRadians: _angle(image.dictionary, operation.value));
      }
      final String stem = '${output.path}/$name.${operation.key}';
      await File('$stem.ps').writeAsBytes(changed.records.program.bytes);
      if (printable) {
        final PdfDocument pdf;
        if (document is AiPdfDocument) {
          final AiPdfDocument saved = AiNativePdf.save(source: native, program: changed.records.program, pageBounds: [bounds]);
          await File('$stem.ai').writeAsBytes(const AiCodec().encode(saved));
          pdf = saved.pdf;
        } else {
          pdf = AiNativePdf.render(program: changed.records.program, bounds: bounds);
        }
        await File('$stem.pdf').writeAsBytes(const PdfEncoder().convert(pdf));
      }
    }
    // These private fuzzy-mask records have dependent effect semantics.
    for (final AiNativeRaster image in original.images.where((image) => image.instruction.isPrivate)) {
      bool rejected = false;
      try {
        original.setPlacement(image: image, matrix: _compose(transforms.values.first, image.matrix), rotationRadians: null);
      } on UnsupportedError {
        rejected = true;
      }
      if (!rejected) {
        throw StateError('Expected the private fuzzy-mask fixture to reject geometry editing.');
      }
    }
    report.add({
      'file': name,
      'selected': selected,
      'printable': printable,
      'pdfBacked': document is AiPdfDocument,
      'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
      'transforms': transforms,
    });
  }
  final AiPdfDocument carrier = const AiCodec().decode(await File('test/corpus/output/native-placements/resolved.linked.ai').readAsBytes()) as AiPdfDocument;
  final AiNativeSource native = AiNativeData.extract(carrier).single;
  final AiNativePlacements original = AiNativePlacements.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: native.bytes)),
  );
  final AiNativePlacedObject object = original.objects.single;
  final AiNativeRasterSamples pixels = object.preview!.toSamples();
  final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: -792, right: 612, top: 0);
  final Map<String, List<double>> transforms = _transforms(bounds);
  await File('${output.path}/linked.original.ps').writeAsBytes(native.bytes);
  for (final MapEntry<String, List<double>> operation in transforms.entries) {
    final AiNativePlacements changed = original.setPlacement(object: object, matrix: _compose(operation.value, object.matrix), rotationRadians: _angle(object.dictionary, operation.value));
    final String stem = '${output.path}/linked.${operation.key}';
    await File('$stem.ps').writeAsBytes(changed.records.program.bytes);
    await File('$stem.pdf').writeAsBytes(const PdfEncoder().convert(AiNativePdf.render(program: changed.records.program, bounds: bounds, resolvePlacement: (_) => pixels)));
    await File('$stem.ai').writeAsBytes(const AiCodec().encode(AiNativePdf.save(source: native, program: changed.records.program, pageBounds: [bounds], resolvePlacement: (_) => pixels)));
  }
  report.add({
    'file': 'linked',
    'bounds': [0, -792, 612, 0],
    'transforms': transforms,
  });
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('Native image geometry: 66 embedded and 3 linked edits saved; two private effect images rejected.');
}
