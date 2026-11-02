import 'dart:convert';
import 'dart:io';

import 'package:aicodec/aicodec.dart';

import '../test/ai_native_appearance_editing_test.dart';
import '../test/ai_native_color_resources_test.dart';
import '../test/ai_native_color_save_test.dart';

/// Emits synthetic native and complete-file evidence for independent readers.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/colors').create(recursive: true);

  /// Keeps saved native bytes separate from the host PDF for independent checks.
  Future<void> save(String name, AiNativeRecords records) async {
    await File('${output.path}/$name.ps').writeAsBytes(records.program.bytes);
    await File('${output.path}/$name.ai').writeAsBytes(const AiCodec().encode(colorSave(records)));
  }

  await save('selected', editedColorRecords());
  final AiNativeAppearances model = appearanceEditingModel(source: appearanceEditingSource().replaceFirst('0.2 0.3 0.4 Xa', '0 0 0 1 0.1 0.2 0.3 (Ink) 0.5 1 Xz'));
  final AiNativePaintAssignment assignment = appearanceAssignment(model.styles.single, 2, .fillColor);
  final AiNativeAppearances named = model.updateShared(
    appearance: model.styles.single,
    paints: [
      AiNativePaintChange.namedColor(
        assignment: assignment,
        value: AiNativeNamedColor(kind: .namedRgb, components: [0, 0.5, 0.75, 0, 0.2, 0.3, 0.4], nameBytes: latin1.encode('Ink'), tint: 0.75),
      ),
    ],
    printing: [appearancePrinting(model, 0), appearancePrinting(model, 1)],
  );
  await save('named', named.structure.drawing.records);
  final AiNativeGradientResources banks = colorResources(setup: '0 Bn\n0 Bn').create(
    nameBytes: latin1.encode('Edge'),
    radial: true,
    stops: [colorStop(0, 0), colorStop(50, 0.2), colorStop(50, 0.8), colorStop(100, 1)],
    ramps: [colorRamp(0.1), colorRamp(0.5), colorRamp(0.9)],
  );
  await save('banks', banks.records);
  await save('removed', banks.remove(definition: banks.definitions.first).records);
  stdout.writeln('Wrote four native snapshots and complete compressed AI saves to ${output.path}.');
}
