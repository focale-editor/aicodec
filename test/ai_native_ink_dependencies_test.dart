import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupsSource;
import 'ai_native_inks_test.dart' show inkCmyk, inkModel, inkRamp, inkStop;
import 'ai_native_opacity_masks_test.dart' show opacityMaskSource;

/// Adds an independently unused ink without introducing any artwork dependency.
AiNativeInks _unused({String? source}) {
  final AiNativeInks model = inkModel(source ?? appearanceGroupsSource());
  return AiNativeInks.decode(
    records: AiNativeSwatches.decode(records: model.records)
        .createNamed(
          nameBytes: ascii.encode('Ink swatch'),
          color: AiNativeNamedColor(kind: .legacyCmyk, nameBytes: ascii.encode('Ink'), components: [0, 0, 0, 1], tint: .4),
        )
        .records,
  );
}

/// Captures complete authoring, metadata and printing bytes from one source owner.
List<int> _bytes(AiNativeInks model, AiNativeAppearanceArtwork owner) => model.records.program.bytes.sublist(owner.start, owner.end);

/// Tests source-backed dependency proofs and explicit unchanged printing coverage.
void main() {
  test('retains every independent printing owner while changing an unused master', () {
    final AiNativeInks model = _unused();
    check(model.affectedPrintingOwners(ink: model.inks.single)).isEmpty();
    final AiNativeInks revised = model.redefine(ink: model.inks.single, cmyk: inkCmyk(), retainedArtwork: model.printingOwners);
    for (final (int index, AiNativeAppearanceArtwork owner) in model.printingOwners.indexed) {
      check(_bytes(revised, revised.printingOwners[index])).deepEquals(_bytes(model, owner));
    }
    check(AiNativeNamedColor.decode(instruction: revised.inks.single.paints.single)!.components).deepEquals(inkCmyk().channels);
  });

  test('requires replacements for every user of an ink-bearing style', () {
    final AiNativeInks model = inkModel(appearanceGroupsSource().replaceFirst('0.2 0.3 0.4 Xa', '0 0 0 1 (Ink) 0.4 x'));
    check(model.affectedPrintingOwners(ink: model.inks.single)).deepEquals(model.printingOwners);
    check(() => model.redefine(ink: model.inks.single, cmyk: inkCmyk(), retainedArtwork: model.printingOwners)).throws<ArgumentError>();
    check(() => model.affectedPrintingOwners(ink: _unused().inks.single)).throws<ArgumentError>();
  });

  test('isolates a mask dependency and preserves the unrelated complete pair exactly', () {
    final AiNativeInks model = inkModel(opacityMaskSource().replaceFirst('0.3 g', '0 0 0 1 (Ink) 0.4 x'));
    check(model.affectedPrintingOwners(ink: model.inks.single)).deepEquals([model.printingOwners.first]);
    final AiNativeInks revised = model.redefine(
      ink: model.inks.single,
      cmyk: inkCmyk(),
      artwork: [appearanceArtworkReplacement(model.appearances, 0)],
      retainedArtwork: [model.printingOwners.last],
    );
    check(_bytes(revised, revised.printingOwners.last)).deepEquals(_bytes(model, model.printingOwners.last));
    check(AiNativeNamedColor.decode(instruction: revised.inks.single.paints.single)!.components).deepEquals(inkCmyk().channels);
  });

  test('tracks consumed inherited printing ink and ignores a prior explicit overwrite', () {
    final String source = appearanceArtworkSource().replaceFirst('0 g', '0 0 0 1 (Ink) 0.4 x');
    final AiNativeInks overwritten = inkModel(source);
    check(overwritten.affectedPrintingOwners(ink: overwritten.inks.single)).isEmpty();
    final AiNativeInks inherited = inkModel(source.replaceFirst('0 0 0 1 k\n', ''));
    check(inherited.affectedPrintingOwners(ink: inherited.inks.single)).deepEquals([inherited.printingOwners.first]);
    check(() => inherited.redefine(ink: inherited.inks.single, cmyk: inkCmyk(), retainedArtwork: inherited.printingOwners)).throws<ArgumentError>();
  });

  test('follows transitive pattern declarations into their named style users', () {
    const String paint = '(Tile) 3 -5 0.5 2 35 1 45 12 7 [1 0.2 0.3 1 40 70] p';
    const String pattern = '%AI3_BeginPattern: (Tile)\n(Tile) 0 0 10 10\n0 0 0 1 (Ink) 0.4 x 0 0 m 10 0 L 10 10 L f\nE\n%AI3_EndPattern\n';
    const String indirect = '%AI3_BeginPattern: (Outer)\n(Outer) 0 0 10 10\n$paint 0 0 m 10 0 L 10 10 L f\nE\n%AI3_EndPattern\n';
    final AiNativeInks model = inkModel(appearanceGroupsSource().replaceFirst('%%EndSetup', '$pattern$indirect%%EndSetup').replaceFirst('0.2 0.3 0.4 Xa', paint.replaceFirst('(Tile)', '(Outer)')));
    check(model.affectedPrintingOwners(ink: model.inks.single)).deepEquals(model.printingOwners);
    check(() => model.redefine(ink: model.inks.single, cmyk: inkCmyk(), retainedArtwork: model.printingOwners)).throws<ArgumentError>();
  });

  test('follows named gradient stops into appearance printing dependencies', () {
    final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: inkModel(appearanceGroupsSource()).records).create(
      nameBytes: ascii.encode('Ink gradient'),
      radial: false,
      stops: [inkStop(0, .2), inkStop(100, .9)],
      ramps: [inkRamp()],
    );
    final AiNativeInks model = inkModel(latin1.decode(resources.records.program.bytes).replaceFirst('0.2 0.3 0.4 Xa', 'Bb 1 (Ink gradient) 0 0 0 10 1 0 0 1 0 0 Bg 0 BB'));
    check(model.affectedPrintingOwners(ink: model.inks.single)).deepEquals(model.printingOwners);
  });

  test('rejects incomplete duplicate stale and foreign retained coverage', () {
    final AiNativeInks model = _unused();
    check(() => model.redefine(ink: model.inks.single, cmyk: inkCmyk(), retainedArtwork: [model.printingOwners.first])).throws<ArgumentError>();
    check(() => model.redefine(ink: model.inks.single, cmyk: inkCmyk(), retainedArtwork: [model.printingOwners.first, model.printingOwners.first])).throws<ArgumentError>();
    check(() => model.redefine(ink: model.inks.single, cmyk: inkCmyk(), retainedArtwork: _unused().printingOwners)).throws<ArgumentError>();
    final AiNativeInks revised = model.redefine(ink: model.inks.single, cmyk: inkCmyk(), retainedArtwork: model.printingOwners);
    check(() => revised.redefine(ink: revised.inks.single, cmyk: inkCmyk(.9), retainedArtwork: model.printingOwners)).throws<ArgumentError>();
  });
}
