import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart';
import 'ai_native_color_resources_test.dart';
import 'ai_native_simple_style_editing_test.dart' show simpleAppearanceSource;

/// Two same-resource fill applications in one shared appearance.
AiNativeAppearances gradientApplicationModel() {
  final AiNativeGradientResources old = colorResources().create(nameBytes: latin1.encode('Old'), radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]);
  final AiNativeGradientResources resources = old.create(
    nameBytes: latin1.encode('Hard'),
    radial: false,
    stops: [colorStop(0, 0), colorStop(50, 0), colorStop(50, 1), colorStop(100, 1)],
    ramps: [colorRamp(0), colorRamp(0), colorRamp(1)],
  );
  final String setup = latin1.decode(resources.records.program.bytes).split('%%BeginSetup').last.split('%%EndSetup').first;
  const String gradient = 'Bb 2 (Old) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB';
  return appearanceEditingModel(source: appearanceEditingSource().replaceFirst('%%EndSetup', '$setup\n%%EndSetup').replaceFirst('0.2 0.3 0.4 Xa', gradient).replaceFirst('0.9 g', gradient));
}

/// Explicit independently specified host expansion for the hard color boundary.
const String hardStopPrinting = 'u\n0 g\n0 0 m 10 0 L 10 10 L 0 10 L f\n1 g\n10 0 m 20 0 L 20 10 L 10 10 L f\n0 0 0 1 k\nU';

/// Ensures precise selection is independent of shared names and neighboring fills.
void main() {
  test('rebinds one exact fill on one shared-style user, retaining the other fill and user', () {
    final AiNativeAppearances source = gradientApplicationModel();
    final AiNativeAppearance style = source.styles.single;
    final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: source.structure.drawing.records);
    final AiNativeGradientDefinition target = resources.definitions.singleWhere((definition) => latin1.decode(definition.nameBytes) == 'Hard');
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      paints: [AiNativePaintChange.gradient(assignment: appearanceAssignment(style, 2, .gradient), definition: target)],
      printing: [appearancePrinting(source, 0, bytes: hardStopPrinting)],
      nameBytes: latin1.encode('Selected gradient'),
    );
    check(latin1.decode(appearanceAssignment(changed.styles.last, 2, .gradient).gradient!.geometry.nameBytes)).equals('Hard');
    check(latin1.decode(appearanceAssignment(changed.styles.last, 3, .gradient).gradient!.geometry.nameBytes)).equals('Old');
    check(latin1.decode(appearanceAssignment(changed.styles.first, 2, .gradient).gradient!.geometry.nameBytes)).equals('Old');
    final AiLiveShape before = source.structure.drawing.liveShapes.last;
    final AiLiveShape after = changed.structure.drawing.liveShapes.last;
    check(changed.structure.drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(before.start, before.end));
    check(changed.styles.last.uses).length.equals(1);
  });

  test('global application changes require every user and reject foreign resources', () {
    final AiNativeAppearances source = gradientApplicationModel();
    final AiNativeAppearance style = source.styles.single;
    final AiNativeGradientDefinition target = AiNativeGradientResources.decode(records: source.structure.drawing.records).definitions
        .singleWhere((definition) => latin1.decode(definition.nameBytes) == 'Hard');
    final AiNativePaintChange change = AiNativePaintChange.gradient(assignment: appearanceAssignment(style, 3, .gradient), definition: target);
    check(() => source.updateShared(appearance: style, paints: [change], printing: [appearancePrinting(source, 0)])).throws<UnsupportedError>();
    final AiNativeAppearances changed = source.updateShared(appearance: style, paints: [change], printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)]);
    check(latin1.decode(appearanceAssignment(changed.styles.single, 3, .gradient).gradient!.geometry.nameBytes)).equals('Hard');
    final AiNativeGradientDefinition foreign = AiNativeGradientResources.decode(records: gradientApplicationModel().structure.drawing.records).definitions.first;
    check(
      () => source.updateSelected(
        appearance: style,
        paints: [AiNativePaintChange.gradient(assignment: appearanceAssignment(style, 2, .gradient), definition: foreign)],
        printing: [appearancePrinting(source, 0)],
        nameBytes: [65],
      ),
    ).throws<ArgumentError>();
  });

  test('edits all named-ink representations in selected and shared appearances', () {
    for (final (AiNativeNamedColorKind kind, String command, int count) fixture in [
      (AiNativeNamedColorKind.legacyCmyk, '0 0 0 1 (Ink) 0.5 x', 4),
      (AiNativeNamedColorKind.customCmyk, '0 0 0 1 (Ink) 0.5 0 Xx', 4),
      (AiNativeNamedColorKind.customRgb, '0.1 0.2 0.3 (Ink) 0.5 1 Xx', 3),
      (AiNativeNamedColorKind.namedCmyk, '0 0 0 1 (Ink) 0.5 Xs', 4),
      (AiNativeNamedColorKind.namedRgb, '0 0 0 1 0.1 0.2 0.3 (Ink) 0.5 1 Xz', 7),
    ]) {
      final AiNativeAppearances source = appearanceEditingModel(source: appearanceEditingSource().replaceFirst('0.2 0.3 0.4 Xa', fixture.$2));
      final AiNativeAppearance style = source.styles.single;
      final AiNativePaintAssignment assignment = appearanceAssignment(style, 2, .fillColor);
      check(assignment.colors).isEmpty();
      check(assignment.namedColor!.kind).equals(fixture.$1);
      final AiNativePaintChange change = AiNativePaintChange.namedColor(
        assignment: assignment,
        value: AiNativeNamedColor(kind: fixture.$1, components: List.filled(fixture.$3, 0.25), nameBytes: latin1.encode('Ink'), tint: 0.75),
      );
      final AiNativeAppearances selected = source.updateSelected(appearance: style, paints: [change], printing: [appearancePrinting(source, 0)], nameBytes: [65]);
      check(appearanceAssignment(selected.styles.last, 2, .fillColor).namedColor!.tint).equals(0.75);
      check(appearanceAssignment(selected.styles.first, 2, .fillColor).namedColor!.tint).equals(0.5);
      final AiNativeAppearances shared = source.updateShared(appearance: style, paints: [change], printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)]);
      check(appearanceAssignment(shared.styles.single, 2, .fillColor).namedColor!.components).deepEquals(List.filled(fixture.$3, 0.25));
    }
  });

  test('edits named simple styles and validates named printing state without tint conversion', () {
    final AiNativeAppearances source = appearanceEditingModel(source: simpleAppearanceSource(commands: '0 0 0 1 (Ink) 0.5 Xs'));
    final AiNativeAppearance style = source.styles.single;
    final AiNativePaintAssignment assignment = style.simplePaint!.assignments.single;
    final AiNativePaintChange change = AiNativePaintChange.namedColor(
      assignment: assignment,
      value: AiNativeNamedColor(kind: .namedCmyk, components: [0, 0, 0, 1], nameBytes: latin1.encode('Ink'), tint: 0.75),
    );
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      paints: [change],
      printing: [appearancePrinting(source, 0, bytes: 'u\n0 0 0 1 (Ink) 0.75 Xs\n0 0 m 20 0 L 20 20 L f\n0 0 0 1 k\nU')],
      nameBytes: [65],
    );
    check(changed.styles.last.simplePaint!.assignments.single.namedColor!.tint).equals(0.75);
    check(() => AiNativePaintChange(assignment: assignment, values: [])).throws<ArgumentError>();
    check(
      () => AiNativePaintChange.namedColor(
        assignment: assignment,
        value: AiNativeNamedColor(kind: .namedCmyk, components: [0, 0, 0, 1], nameBytes: [66], tint: 0.5),
      ),
    ).throws<ArgumentError>();
  });
  test('named stroke alternatives remain typed and malformed named commands reject', () {
    for (final String command in ['0 0 0 1 (Ink) 0.5 X', '0 0 0 1 (Ink) 0.5 0 XX', '0.1 0.2 0.3 (Ink) 0.5 1 XX', '0 0 0 1 (Ink) 0.5 XS', '0 0 0 1 0.1 0.2 0.3 (Ink) 0.5 1 XZ']) {
      final AiNativeAppearances source = appearanceEditingModel(source: appearanceEditingSource().replaceFirst('0.1 0.2 0.3 0.4 0.5 0.6 0.7 XA', command));
      final AiNativePaintAssignment assignment = appearanceAssignment(source.styles.single, 6, .strokeColor);
      final AiNativeNamedColor color = assignment.namedColor!;
      final AiNativeAppearances changed = source.updateShared(
        appearance: source.styles.single,
        paints: [
          AiNativePaintChange.namedColor(
            assignment: assignment,
            value: AiNativeNamedColor(kind: color.kind, components: color.components, nameBytes: color.nameBytes, tint: 0.75),
          ),
        ],
        printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)],
      );
      check(appearanceAssignment(changed.styles.single, 6, .strokeColor).namedColor!.tint).equals(0.75);
      check(() => color.components[0] = 1).throws<UnsupportedError>();
      check(() => color.nameBytes[0] = 0).throws<UnsupportedError>();
    }
    for (final String command in ['0 0 0 1 (Ink) 2 Xs', '0 0 0 1 () 0.5 Xs', '0 0 (Ink) 0.5 x', '0 0 0 1 (Ink) 0.5 2 Xx', '0 0 0 1 0 0 0 (Ink) 0.5 0 Xz']) {
      final AiNativeAppearances model = appearanceEditingModel(source: appearanceEditingSource().replaceFirst('0.2 0.3 0.4 Xa', command));
      check(() => appearanceAssignment(model.styles.single, 2, .fillColor)).throws<FormatException>();
    }
  });
}
