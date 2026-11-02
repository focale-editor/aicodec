import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

import '../test/ai_native_appearance_editing_test.dart';
import '../test/ai_native_color_resources_test.dart';
import '../test/ai_native_color_save_test.dart' show colorSave;
import '../test/ai_native_inks_test.dart';

/// Emits complete synthetic saves for independent cross-reference inspection.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/inks').create(recursive: true);

  /// Saves the exact native program alongside its explicitly supplied PDF view.
  Future<void> save(String name, AiNativeInks model, double cyan) async {
    final AiPdfDocument document = colorSave(model.records, pdfCommands: 'q $cyan 0.3 0.4 0.5 k 0 0 10 10 re f Q');
    await File('${output.path}/$name.ps').writeAsBytes(model.records.program.bytes);
    await File('${output.path}/$name.ai').writeAsBytes(const AiCodec().encode(document));
  }

  const String palette = '%AI5_BeginPalette\n0 0 Pb\n0 0 0 1 (Ink) 1 Xs\n(Ink) Pc\nPB\n%AI5_EndPalette';
  final AiNativeGradientResources resources = colorResources(setup: '0 Bn\n0 Bn\n$palette', body: '${inkMesh()}\n$inkPaints').create(
    nameBytes: latin1.encode('Gradient'),
    radial: false,
    stops: [inkStop(0, .2), inkStop(100, .9)],
    ramps: [inkRamp()],
  );
  final String source = latin1.decode(resources.records.program.bytes).replaceFirst('%%EndComments', '%%DocumentCustomColors: (Ink) (Other)\n%%CMYKCustomColor: 0 0 0 1 (Ink)\n%%EndComments');
  final AiNativeInks model = inkModel(source);
  final AiNativeInk ink = model.inks.singleWhere((ink) => latin1.decode(ink.nameBytes) == 'Ink');
  final AiNativeInks first = model.redefine(
    ink: ink,
    cmyk: inkCmyk(),
    rgb: inkRgb(),
    ramps: {
      ink.gradients.first: [inkRamp()],
    },
  );
  await save('references-1', first, .2);
  final AiPdfDocument complete = colorSave(first.records);
  final AiNativeInks reopened = AiNativeInks.decode(
    records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(complete).single.bytes)),
  );
  final AiNativeInk next = reopened.inks.singleWhere((ink) => latin1.decode(ink.nameBytes) == 'Ink');
  final AiNativeGradientRamp nextRamp = AiNativeGradientRamp(
    kind: .customCmyk,
    channels: [
      for (final double value in [.9, .3, .4, .5, .6]) AiNativeGradientChannel.constant(value: value),
    ],
  );
  final AiNativeInks second = reopened.redefine(
    ink: next,
    cmyk: inkCmyk(.9),
    rgb: inkRgb(),
    ramps: {
      next.gradients.first: [nextRamp],
    },
  );
  await save('references-2', second, .9);

  final AiNativeInks styled = inkModel(appearanceEditingSource().replaceFirst('0.2 0.3 0.4 Xa', '0 0 0 1 (Ink) 0.5 Xs'));
  final AiNativeInks changed = styled.redefine(ink: styled.inks.single, cmyk: inkCmyk(), artwork: inkPrinting(styled));
  await save('appearance-1', changed, .2);
  final AiNativeInks repeated = changed.redefine(ink: changed.inks.single, cmyk: inkCmyk(.9), artwork: inkPrinting(changed));
  await save('appearance-2', repeated, .9);
  stdout.writeln('Wrote four complete named-ink saves to ${output.path}.');
}
