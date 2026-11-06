import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart';
import 'ai_native_color_application_test.dart';
import 'ai_native_color_resources_test.dart';
import 'ai_native_test.dart' as fixtures;

/// Complete selected-user gradient edit followed by explicit palette creation.
AiNativeRecords editedColorRecords() {
  final AiNativeAppearances model = gradientApplicationModel();
  final AiNativeGradientDefinition target = AiNativeGradientResources.decode(records: model.structure.drawing.records).definitions
      .singleWhere((definition) => latin1.decode(definition.nameBytes) == 'Hard');
  final AiNativeAppearances edited = model.updateSelected(
    appearance: model.styles.single,
    paints: [AiNativePaintChange.gradient(assignment: appearanceAssignment(model.styles.single, 2, .gradient), definition: target)],
    printing: [appearancePrinting(model, 0, bytes: hardStopPrinting)],
    nameBytes: latin1.encode('Selected gradient'),
  );
  final AiNativeSwatches process = AiNativeSwatches.decode(records: edited.structure.drawing.records).createProcess(
    nameBytes: latin1.encode('Process'),
    color: AiColor(space: .rgb, channels: [0.2, 0.3, 0.4]),
    cmykAlternative: AiColor(space: .cmyk, channels: [0.1, 0.2, 0.3, 0.4]),
  );
  final AiNativeSwatches named = process.createNamed(
    nameBytes: latin1.encode('Named'),
    color: AiNativeNamedColor(kind: .namedCmyk, components: [0, 0.5, 0.75, 0], nameBytes: latin1.encode('Ink'), tint: 0.25),
  );
  final AiNativeGradientDefinition current = AiNativeGradientResources.decode(records: named.records).definitions.singleWhere((definition) => latin1.decode(definition.nameBytes) == 'Hard');
  return named.createGradient(nameBytes: latin1.encode('Hard swatch'), definition: current).records;
}

/// Host PDF content supplied independently of the native edit implementation.
const String colorPdfCommands = 'q 0 g 0 0 10 10 re f 1 g 10 0 10 10 re f 0 g 10 20 20 20 re f Q';

/// Produces a complete compressed AI save with shared native owners.
AiPdfDocument colorSave(AiNativeRecords records, {String pdfCommands = colorPdfCommands}) {
  final AiPdfDocument original = fixtures.nativePdf(
    compression: .zstandard,
    alias: true,
    thumbnail: true,
    nativeProgram: latin1.decode(gradientApplicationModel().structure.drawing.records.program.bytes),
  );
  final AiNativeSource source = AiNativeData.extract(original).single;
  final PdfEditor host = PdfEditor(document: original.pdf);
  for (int index = 0; index < host.document.pages.length; index++) {
    host.setPageContent(pageIndex: index, bytes: latin1.encode(pdfCommands));
  }
  return const AiCodec().decode(const AiCodec().encode(AiNativeData.replace(source: source, program: records.program.bytes, synchronizedPdf: host.document, blockBytes: 71))) as AiPdfDocument;
}

/// Exercises full-file persistence rather than only local parser round trips.
void main() {
  test('reopens hard stops, exact application selection, swatches and matching host PDF', () {
    final AiNativeRecords edited = editedColorRecords();
    final AiPdfDocument reopened = colorSave(edited);
    final AiNativeSource source = AiNativeData.extract(reopened).single;
    check(source.owners).length.equals(2);
    final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes));
    final AiNativeGradientDefinition hard = AiNativeGradientResources.decode(records: records).definitions.singleWhere((definition) => latin1.decode(definition.nameBytes) == 'Hard');
    check(hard.stops.map((stop) => stop.position)).deepEquals([100.0, 50.0, 50.0, 0.0]);
    final AiNativeAppearances model = appearanceEditingModel(source: latin1.decode(source.bytes));
    check(model.styles.last.uses).length.equals(1);
    check(latin1.decode(appearanceAssignment(model.styles.last, 2, .gradient).gradient!.geometry.nameBytes)).equals('Hard');
    check(latin1.decode(appearanceAssignment(model.styles.last, 3, .gradient).gradient!.geometry.nameBytes)).equals('Old');
    final AiNativeSwatches palette = AiNativeSwatches.decode(records: records);
    check(palette.palettes.single.swatches.map((swatch) => latin1.decode(swatch.nameBytes!))).deepEquals(['Process', 'Named', 'Hard swatch']);
    check(palette.palettes.single.swatches[1].namedColor!.tint).equals(0.25);
    for (final PdfPage page in reopened.pdf.pages) {
      check(latin1.decode(reopened.pdf.pageContent(page))).equals(colorPdfCommands);
    }
    final AiNativeGradientResources next = AiNativeGradientResources.decode(records: records)
        .create(nameBytes: latin1.encode('Temporary'), radial: true, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]);
    final AiNativeGradientResources removed = next.remove(definition: next.definitions.singleWhere((definition) => latin1.decode(definition.nameBytes) == 'Temporary'));
    check(removed.definitions).length.equals(2);
  });

  test('capability reports keep resource and palette operations conditional', () {
    final AiNativeSource source = AiNativeData.extract(colorSave(editedColorRecords())).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final AiNativeCapability program = report.findings.firstWhere((finding) => finding.feature == .program);
    check(program.edits.map((edit) => edit.operation)).contains(AiNativeEditOperation.gradientCreation);
    final AiNativeCapability palette = report.findings.singleWhere((finding) => finding.feature == .palette);
    check(palette.edits.every((edit) => edit.support == .requiresValidation)).isTrue();
    check(
      report.findings
          .where((finding) => finding.feature == .gradientResource)
          .every((finding) => finding.edits.any((edit) => edit.operation == .gradientRemoval && edit.support == .requiresValidation)),
    ).isTrue();
  });
}
