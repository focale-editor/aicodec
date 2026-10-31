import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import 'check_native_pdf.dart' as fixtures;

/// Checks complete CC drawings with compound gradients and appearance notes.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-pdf-compounds').create(recursive: true);
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/pdf_manifest.json').readAsString()) as Map).cast<String, Object?>();
  final List<Map<String, Object?>> report = [];
  int failures = 0;
  for (final Object? raw in manifest['files']! as List) {
    final Map<String, Object?> entry = (raw! as Map).cast<String, Object?>();
    final String name = entry['file']! as String;
    final bool rejection = entry['expected'] == 'reject';
    try {
      final AiPdfDocument original = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes()) as AiPdfDocument;
      final AiNativeSource source = AiNativeData.extract(original).single;
      final AiProgram program = AiProgram.decode(bytes: source.bytes);
      final AiNativeDrawing drawing = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
      final AiBoundingBox crop = AiBoundingBox.parse(value: RegExp(r'%AI3_Cropmarks:\s*([^\r\n]+)').firstMatch(latin1.decode(program.bytes))![1]!);
      final List<double> media = (original.pdf.resolve(original.pdf.pages.single.inherited['MediaBox']!) as PdfArray).values.cast<PdfNumber>().map((number) => number.value.toDouble()).toList();
      final AiBoundingBox bounds = AiBoundingBox(left: crop.left, bottom: crop.bottom, right: crop.left + media[2] - media[0], top: crop.bottom + media[3] - media[1]);
      await File('${output.path}/$name.original.pdf').writeAsBytes(const AiCodec().encode(original));
      await File('${output.path}/$name.native.ps').writeAsBytes(program.bytes);
      final List<AiNativeGradient> printed = drawing.gradients.where((gradient) => !gradient.opening.isPrivate && gradient.paths.isNotEmpty).toList();
      final int compounds = drawing.groups.where((group) => group.compound && !group.opening.isPrivate && printed.any((gradient) => gradient.start >= group.start && gradient.end <= group.end)).length;
      if (compounds != 1) {
        throw StateError('Expected one genuine gradient compound in each fixture.');
      }
      try {
        final AiPdfDocument rebuilt = AiNativePdf.save(source: source, program: program, pageBounds: [bounds]);
        if (rejection) {
          throw StateError('Expected native gradient stroke rejection.');
        }
        final Set<String> names = printed.map((gradient) => latin1.decode(gradient.geometry.nameBytes)).toSet();
        final AiProgram colors = fixtures.replaceNativeGradientColors(program, names: names);
        final AiPdfDocument edited = AiNativePdf.save(source: source, program: colors, pageBounds: [bounds]);
        await File('${output.path}/$name.rebuilt.ai').writeAsBytes(const AiCodec().encode(rebuilt));
        await File('${output.path}/$name.colors.ai').writeAsBytes(const AiCodec().encode(edited));
        await File('${output.path}/$name.colors.ps').writeAsBytes(colors.bytes);
        for (final (AiPdfDocument, AiProgram) pair in [(rebuilt, program), (edited, colors)]) {
          final AiDocument reopened = const AiCodec().decode(const AiCodec().encode(pair.$1));
          if (latin1.decode(AiNativeData.extract(reopened).single.bytes) != latin1.decode(pair.$2.bytes)) {
            throw StateError('Native data and PDF source differ after saving.');
          }
        }
        report.add({
          'file': name,
          'status': 'accepted',
          'compounds': compounds,
          'printedGradients': printed.length,
          'gradientResources': names.toList(),
          'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
        });
        stdout.writeln('$name: complete drawing and edited gradient resources saved');
      } on UnsupportedError catch (error) {
        if (!rejection || !printed.any((gradient) => gradient.onStroke) || !error.toString().contains('gradient stroke')) {
          rethrow;
        }
        report.add({'file': name, 'status': 'rejected', 'reason': error.toString()});
        stdout.writeln('$name: unexpanded gradient stroke explicitly rejected');
      }
    } on Object catch (error, stack) {
      failures++;
      report.add({'file': name, 'status': 'failed', 'error': '$error'});
      stderr.writeln('$name: $error\n$stack');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await _checkProbes(output);
  if (failures != 0) {
    exitCode = 1;
  }
}

/// Writes independently positioned probes for holes, alpha and appearance notes.
Future<void> _checkProbes(Directory output) async {
  /// Builds a ring with its gradient declaration on the final contour only.
  String ring(int left, {bool evenOdd = false, bool grouped = false, bool stroke = false, String name = 'Opaque'}) =>
      '''${evenOdd ? 1 : 0} XR *u
${grouped ? 'u u' : ''}
${left + 30} 30 m ${left + (evenOdd ? 70 : 30)} ${evenOdd ? 30 : 70} L ${left + 70} 70 L ${left + (evenOdd ? 30 : 70)} ${evenOdd ? 70 : 30} L f
${left + 10} 10 m ${left + 90} 10 L ${left + 90} 90 L ${left + 10} 90 L
Bb 1 ($name) 0 0 0 1 1 0 0 1 0 0 Bg
80 0 0 -80 ${left + 10} 90 Xm f ${stroke ? 2 : 0} BB
${grouped ? 'U U 9 () XW' : ''}
*U''';

  final AiProgram program = AiProgram.decode(
    bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BeginSetup
%AI5_BeginGradient: (Opaque)
(Opaque) 0 2 Bd [ 0 0 50 100 %_Bs
1 0 50 0 %_Bs
BD
%AI5_EndGradient
%AI5_BeginGradient: (Alpha)
(Alpha) 0 2 Bd [
%_0 0 0.5 6 50 100 Bs
%_1 0 0.5 6 50 0 Bs
BD
%AI5_EndGradient
%%EndSetup
0 0 1 Xa 0 0 m 100 0 L 100 120 L 0 120 L f
${ring(0, evenOdd: true)}
0 0.5 0 0 0 Xy
${ring(100, grouped: true)}
0 0 1 XA 10 w
${ring(200, stroke: true, name: 'Alpha')}
0 1 0 0 0 Xy 1 0 0 Xa
Bb 2 (Unused note) 0 0 0 1 1 0 0 1 0 0 Bg 0 BB
320 20 m 380 20 L 380 80 L 320 80 L f
%%Trailer
%%EOF
'''),
  );
  final PdfDocument pdf = AiNativePdf.render(program: program, bounds: AiBoundingBox(left: 0, bottom: 0, right: 400, top: 120));
  await File('${output.path}/compound-probes.pdf').writeAsBytes(const PdfEncoder().convert(pdf));
}
