import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel, appearanceEditingSource, appearancePrinting;

/// Supplies the two CC pairs with one literal simple appearance definition.
String simpleAppearanceSource({String commands = '0.1 0.2 0.3 0.4 k 0.6 G 0 O 1 R 1 J 2 j 3 w 8 M [2 3] -1 d 1 XR 0 0.8 0 0 0 Xy 1 0 Xd'}) {
  final String source = appearanceEditingSource();
  return source.replaceRange(source.indexOf('/KnownStyle'), source.indexOf('%%EndSetup'), '/KnownStyle : (Shared) /Name , /SimpleStyle : $commands /Paint ; /Def ;\n');
}

/// Resolves one literal assignment from the simple-style Paint owner.
AiNativePaintAssignment _assignment(AiNativeAppearance style, AiNativePaintParameter parameter) => style.simplePaint!.assignments.singleWhere((assignment) => assignment.parameter == parameter);

/// Checks simple-style editing without widening unrelated geometry transforms.
void main() {
  test('isolates a simple-style user and preserves the source definition and other user', () {
    final AiNativeAppearances source = appearanceEditingModel(source: simpleAppearanceSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: _assignment(style, .fillColor), values: [0.4, 0.3, 0.2, 0.1]),
      ],
      printing: [appearancePrinting(source, 0)],
      nameBytes: latin1.encode('Simple selected'),
    );
    check(changed.styles.last.parts).isEmpty();
    check(_assignment(changed.styles.last, .fillColor).numbers).isNotNull().deepEquals([0.4, 0.3, 0.2, 0.1]);
    check(_assignment(changed.styles.first, .fillColor).numbers).isNotNull().deepEquals([0.1, 0.2, 0.3, 0.4]);
    final AiLiveShape before = source.structure.drawing.liveShapes.last;
    final AiLiveShape after = changed.structure.drawing.liveShapes.last;
    check(changed.structure.drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(before.start, before.end));
    check(changed.styles.last.uses).length.equals(1);
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(simpleAppearanceSource());
  });

  test('updates all shared simple-style users and preserves other scalar assignments', () {
    final AiNativeAppearances source = appearanceEditingModel(source: simpleAppearanceSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateShared(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: _assignment(style, .strokeWidth), values: [6]),
      ],
      printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)],
    );
    check(changed.styles).length.equals(1);
    check(changed.styles.single.uses).length.equals(2);
    check(_assignment(changed.styles.single, .strokeWidth).numbers).isNotNull().deepEquals([6.0]);
    check(_assignment(changed.styles.single, .dash).dash!.lengths).deepEquals([2.0, 3.0]);
    check(_assignment(changed.styles.single, .fillStrokeFlags).numbers).isNotNull().deepEquals([1.0, 0.0]);
  });

  test('retains inherited paint and keeps unrelated geometry transforms unsupported', () {
    final AiNativeAppearances source = appearanceEditingModel(source: simpleAppearanceSource(commands: '0.2 g'));
    check(
      () => source.updateSelected(
        appearance: source.styles.single,
        paints: [
          AiNativePaintChange(assignment: _assignment(source.styles.single, .fillColor), values: [0.4]),
        ],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      ),
    ).returnsNormally();
    final AiNativeDrawing drawing = source.structure.drawing;
    check(() => drawing.scaleLiveShapes(shapes: [drawing.liveShapes.first], factor: 2, pivotX: 0, pivotY: 0)).throws<UnsupportedError>();
  });

  test('does not infer disabled stroke semantics from simple-style display flags', () {
    for (final bool reset in [false, true]) {
      final String text = simpleAppearanceSource(commands: '0.6 G 1 0 Xd').replaceFirst('%%Trailer', '${reset ? '0 G ' : ''}0 0 m 10 10 L S\n%%Trailer');
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      AiNativeAppearances edit() => source.updateSelected(
        appearance: source.styles.single,
        paints: [
          AiNativePaintChange(assignment: _assignment(source.styles.single, .strokeColor), values: [0.3]),
        ],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      );
      if (reset) {
        check(edit().styles).length.equals(2);
      } else {
        check(edit).throws<UnsupportedError>();
      }
    }
  });

  test('edits unused simple styles without creating a derived representation', () {
    final String full = simpleAppearanceSource();
    final String empty = '${full.substring(0, full.indexOf('%%EndSetup'))}%%EndSetup\n%%Trailer\n%%EOF\n';
    final AiNativeAppearances source = appearanceEditingModel(source: empty);
    final AiNativeAppearances changed = source.updateShared(
      appearance: source.styles.single,
      paints: [
        AiNativePaintChange(assignment: _assignment(source.styles.single, .strokeWidth), values: [9.5]),
      ],
      printing: [],
    );
    check(changed.structure.drawing.liveShapes).isEmpty();
    check(changed.styles.single.parts).isEmpty();
    check(_assignment(changed.styles.single, .strokeWidth).numbers).isNotNull().deepEquals([9.5]);
    check(latin1.decode(changed.structure.drawing.records.program.bytes)).equals(empty.replaceFirst('3 w', '9.5 w'));
  });

  test('retains complete simple-style pairs through qualified copying and removal', () {
    final AiNativeDrawing source = appearanceEditingModel(source: simpleAppearanceSource()).structure.drawing;
    final AiNativeDrawing copied = source.duplicateLiveShapes(shapes: [source.liveShapes.first]);
    final AiLiveShape original = source.liveShapes.first;
    final AiLiveShape duplicate = copied.liveShapes[1];
    check(copied.liveShapes).length.equals(3);
    check(copied.records.program.bytes.sublist(duplicate.start, duplicate.end)).deepEquals(source.records.program.bytes.sublist(original.start, original.end));
    check(copied.liveShapes.every((shape) => identical(shape.style, copied.liveShapes.first.style))).isTrue();
    final AiNativeDrawing removed = source.removeLiveShapes(shapes: [source.liveShapes.last]);
    check(removed.liveShapes).length.equals(1);
    check(removed.records.program.bytes.sublist(removed.liveShapes.single.start, removed.liveShapes.single.end)).deepEquals(source.records.program.bytes.sublist(original.start, original.end));
    final AiNativeContainer retained = removed.liveShapes.single.style!;
    check(removed.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(source.records.program.bytes.sublist(original.style!.start, original.style!.end));
    final AiNativeDrawing dependent = appearanceEditingModel(source: simpleAppearanceSource().replaceFirst('%%Trailer', '0 0 m 10 10 L S\n%%Trailer')).structure.drawing;
    check(() => dependent.removeLiveShapes(shapes: [dependent.liveShapes.last])).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(simpleAppearanceSource());
  });

  test('reports simple-style edits as requiring source and expansion validation', () {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(latin1.encode(simpleAppearanceSource()))).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final List<AiNativeEditCapability> edits = report.findings.where((finding) => finding.feature == .appearance).expand((finding) => finding.edits).toList();
    check(edits.map((edit) => edit.operation)).deepEquals([AiNativeEditOperation.sharedAppearance, AiNativeEditOperation.selectedAppearance]);
    check(edits.every((edit) => edit.support == .requiresValidation)).isTrue();
  });

  test('rejects unknown simple paint schemas and conditional or repeated owners', () {
    for (final String text in [
      simpleAppearanceSource(commands: '0.2 g 7 FuturePaint'),
      simpleAppearanceSource(commands: '0.2 g 0 0 0 1 (Spot) 0.5 FutureInk'),
      simpleAppearanceSource().replaceFirst('/Paint ;', '/Paint , 1 /FutureCache ;'),
      simpleAppearanceSource().replaceFirst('/Paint ;', '/Paint , 0 g /Paint ;'),
      simpleAppearanceSource().replaceFirst('/KnownStyle', '%AI17_Begin_Content_if_version_gt:24 4\n/KnownStyle').replaceFirst('%%EndSetup', '%AI17_End_Versioned_Content\n%%EndSetup'),
    ]) {
      void edit() {
        final AiNativeAppearances source = appearanceEditingModel(source: text);
        source.updateSelected(
          appearance: source.styles.single,
          paints: [AiNativePaintChange(assignment: _assignment(source.styles.single, .fillColor), values: _assignment(source.styles.single, .fillColor).numbers!)],
          printing: [appearancePrinting(source, 1)],
          nameBytes: [65],
        );
      }

      if (text.contains('/Paint , 0 g /Paint')) {
        check(edit).throws<AiNativeAmbiguousFieldError>();
      } else {
        check(edit).throws<UnsupportedError>();
      }
    }
  });
}
