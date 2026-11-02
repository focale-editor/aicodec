import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupsSource;

/// Complete ordinary CC owners with explicit native and printing transparency.
String transparencySource({bool grouped = false}) =>
    (grouped ? appearanceGroupsSource() : appearanceArtworkSource(metadata: true)).replaceFirst('0 0.5 0 0 0 Xy', '9 0.5 1 2 1 Xy').replaceAll('\nU\n', '\n0 1 0 0 0 Xy\nU\n');

/// Host-produced printing artwork with the original outgoing drawing state.
const String transparencyPrinting = 'u\n0 0 0 1 k\n1 0.25 1 1 0 Xy\n0 0 m 10 0 L 10 10 L f\n0 1 0 0 0 Xy\nU';

/// Explicit application data; no rendering is used to produce these settings.
AiNativeTransparency transparencyValue() => AiNativeTransparency(blendMode: .multiply, opacity: 0.25, isolated: true, knockout: .on, alphaIsShape: false);

/// Saves a selected or shared ordinary appearance with supplied printing groups.
AiNativeAppearances editTransparency(AiNativeAppearances source, {bool shared = false, String printing = transparencyPrinting}) {
  final AiNativeAppearance style = source.styles.single;
  final List<AiNativePaintChange> paints = [AiNativePaintChange.transparency(assignment: appearanceAssignment(style, 7, .transparency), value: transparencyValue())];
  final List<AiNativeAppearanceReplacement> artwork = [
    appearanceArtworkReplacement(source, 0, bytes: printing),
    if (shared) appearanceArtworkReplacement(source, 1, bytes: printing),
  ];
  return shared
      ? source.updateShared(appearance: style, paints: paints, artwork: artwork)
      : source.updateSelected(appearance: style, paints: paints, artwork: artwork, nameBytes: latin1.encode('Transparent selection'));
}

/// Copies one exact record for assertions about retained source bytes.
List<int> _bytes(AiNativeAppearances model, AiNativeItem item) => model.structure.drawing.records.program.bytes.sublist(item.start, item.end);

/// Tests host-facing transparency data and atomic selected/shared serialization.
void main() {
  test('decodes every native mode and retains all three knockout states', () {
    for (final AiNativeBlendMode mode in AiNativeBlendMode.values) {
      for (final AiNativeKnockout knockout in AiNativeKnockout.values) {
        final AiNativeAppearances source = appearanceEditingModel(source: transparencySource().replaceFirst('9 0.5 1 2 1 Xy', '${mode.index} 0.5 1 ${knockout.index} 1 Xy'));
        final AiNativePaintAssignment assignment = appearanceAssignment(source.styles.single, 7, .transparency);
        final AiNativeTransparency value = assignment.transparency!;
        check(value.blendMode).equals(mode);
        check(value.opacity).equals(0.5);
        check(value.isolated).isTrue();
        check(value.knockout).equals(knockout);
        check(value.alphaIsShape).isTrue();
        check(value.operands).deepEquals(assignment.numbers!);
        check(value.operands.clear).throws<UnsupportedError>();
      }
    }
  });

  test('keeps fill and whole-object opacity separate without inherited defaults', () {
    final AiNativeAppearance style = appearanceEditingModel(source: transparencySource()).styles.single;
    check(appearanceAssignment(style, 2, .transparency).transparency!.opacity).equals(0.8);
    check(appearanceAssignment(style, 7, .transparency).transparency!.opacity).equals(0.5);
    check(style.parts[3].paints.single.style.assignments.where((assignment) => assignment.parameter == .transparency)).isEmpty();
    check(appearanceAssignment(style, 2, .fillColor).transparency).isNull();
  });

  test('edits selected ordinary paths and groups with exact neighboring preservation', () {
    for (final bool grouped in [false, true]) {
      final String text = transparencySource(grouped: grouped);
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      final AiNativeAppearances changed = editTransparency(source);
      check(changed.styles).length.equals(2);
      check(appearanceAssignment(changed.styles.last, 7, .transparency).numbers).isNotNull().deepEquals(transparencyValue().operands);
      check(_bytes(changed, changed.styles.first.definition)).deepEquals(_bytes(source, source.styles.single.definition));
      for (final int index in [0, 1]) {
        final AiNativeAppearanceArtwork before = source.artworkFor(use: source.uses[index]);
        final AiNativeAppearanceArtwork after = changed.artworkFor(use: changed.uses[index]);
        check(_bytes(changed, after.authoring)).deepEquals(_bytes(source, before.authoring));
        if (index == 0) {
          check(_bytes(changed, after.printingGroup)).deepEquals(latin1.encode(transparencyPrinting));
        } else {
          check(changed.structure.drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(before.start, before.end));
        }
      }
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('updates a shared style only with complete host-supplied coverage', () {
    final AiNativeAppearances source = appearanceEditingModel(source: transparencySource(grouped: true));
    final AiNativeAppearances changed = editTransparency(source, shared: true);
    check(changed.styles).length.equals(1);
    check(appearanceAssignment(changed.styles.single, 7, .transparency).numbers).isNotNull().deepEquals(transparencyValue().operands);
    for (final AiNativeResourceUse use in changed.uses) {
      check(_bytes(changed, changed.artworkFor(use: use).printingGroup)).deepEquals(latin1.encode(transparencyPrinting));
    }
    check(
      () => source.updateShared(
        appearance: source.styles.single,
        paints: [AiNativePaintChange.transparency(assignment: appearanceAssignment(source.styles.single, 7, .transparency), value: transparencyValue())],
        artwork: [appearanceArtworkReplacement(source, 0, bytes: transparencyPrinting)],
      ),
    ).throws<UnsupportedError>();
  });

  test('rejects state leakage and unknown printing transparency atomically', () {
    final String text = transparencySource();
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    for (final String printing in [transparencyPrinting.replaceFirst('0 1 0 0 0 Xy', '2 1 0 0 0 Xy'), transparencyPrinting.replaceFirst('1 0.25 1 1 0 Xy', '16 0.25 1 1 0 Xy')]) {
      check(() => editTransparency(source, printing: printing)).throws<UnsupportedError>();
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('restores proven incoming printing transparency without inventing a default', () {
    final String text = transparencySource().replaceAll('\n0 1 0 0 0 Xy\nU\n', '\nU\n');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances changed = editTransparency(source);
    check(_bytes(changed, changed.artworkFor(use: changed.uses.first).printingGroup)).deepEquals(latin1.encode(transparencyPrinting));
    final AiNativeAppearances unknown = appearanceEditingModel(source: text.replaceAll('0 1 0 0 0 Xy', ''));
    check(() => editTransparency(unknown)).throws<UnsupportedError>();
  });

  test('retains unqualified source commands and rejects malformed or unknown tuples', () {
    for (final String tuple in ['16 0.5 0 0 0', '0 1.1 0 0 0', '0 0.5 2 0 0', '0 0.5 0 3 0', '0 0.5 0 0 2']) {
      final String text = transparencySource().replaceFirst('9 0.5 1 2 1', tuple);
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      check(() => source.styles.single.parts[7].paints.single.style.assignments).throws<UnsupportedError>();
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
    final AiNativeAppearances malformed = appearanceEditingModel(source: transparencySource().replaceFirst('9 0.5 1 2 1 Xy', '0 0.5 Xy'));
    check(() => malformed.styles.single.parts[7].paints.single.style.assignments).throws<FormatException>();
    for (final double opacity in [-0.1, 1.1, double.nan, double.infinity]) {
      check(() => AiNativeTransparency(blendMode: .normal, opacity: opacity, isolated: false, knockout: .off, alphaIsShape: false)).throws<ArgumentError>();
    }
  });

  test('rejects a transparency request on an unrelated paint assignment', () {
    final AiNativePaintAssignment color = appearanceAssignment(appearanceEditingModel().styles.single, 2, .fillColor);
    check(() => AiNativePaintChange.transparency(assignment: color, value: transparencyValue())).throws<ArgumentError>();
    check(() => AiNativeTransparency.decode(instruction: color.instruction)).throws<ArgumentError>();
  });
}
