import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource, appearanceArtworkState;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_graph_test.dart' show newAppearanceFill;
import 'ai_native_appearance_nested_editing_test.dart' show nestedStyleSource;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceOwners;
import 'ai_native_opacity_masks_test.dart' show opacityMaskSource;
import 'ai_native_transparency_test.dart' show transparencyPrinting;

/// Host cyan expansion that restores the original outgoing process fill.
const String _cyan = 'u\n0 1 1 Xa\n0 0 m 10 0 L 10 10 L f\n0 0 0 1 k\nU';

/// Adds a fresh resource without changing any current application.
AiNativeAppearances _source(String source) => appearanceEditingModel(source: source).createStyle(nameBytes: latin1.encode('New style'), execution: newAppearanceFill());

/// Reads a complete original object interval for preservation assertions.
List<int> _bytes(AiNativeAppearances model, int start, int end) => model.structure.drawing.records.program.bytes.sublist(start, end);

/// Exercises independent resource creation, selected application and cleanup.
void main() {
  test('applies an existing new style to one ordinary user without cloning resources', () {
    final AiNativeAppearances source = _source(appearanceArtworkSource(metadata: true));
    final AiNativeAppearanceArtwork original = source.artworkFor(use: source.uses.first);
    final AiNativeAppearanceArtwork neighbor = source.artworkFor(use: source.uses.last);
    final AiNativeAppearances result = source.applyStyle(
      appearance: source.styles.last,
      artwork: [appearanceArtworkReplacement(source, 0, bytes: _cyan)],
    );
    check(result.styles).length.equals(2);
    check(result.resolve(use: result.uses.first)).identicalTo(result.styles.last);
    check(result.resolve(use: result.uses.last)).identicalTo(result.styles.first);
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
    final AiNativeAppearanceArtwork retained = result.artworkFor(use: result.uses.last);
    check(_bytes(result, after.authoring.start, after.authoring.end)).deepEquals(_bytes(source, original.authoring.start, original.authoring.end));
    check(_bytes(result, after.dictionary!.start, after.dictionary!.end)).deepEquals(_bytes(source, original.dictionary!.start, original.dictionary!.end));
    check(_bytes(result, retained.start, retained.end)).deepEquals(_bytes(source, neighbor.start, neighbor.end));
    check(result.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(source.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes)));
  });

  test('rebinds all users then removes the old definition without dropping authoring data', () {
    final AiNativeAppearances source = _source(appearanceArtworkSource(metadata: true));
    final AiNativeAppearances applied = source.applyStyle(
      appearance: source.styles.last,
      artwork: [for (int index = 0; index < source.uses.length; index++) appearanceArtworkReplacement(source, index, bytes: _cyan)],
    );
    check(applied.styles.first.uses).isEmpty();
    final AiNativeAppearances removed = applied.removeStyles(styles: [applied.styles.first]);
    check(removed.styles).length.equals(1);
    check(removed.styles.single.uses).length.equals(2);
    for (final AiNativeResourceUse use in removed.uses) {
      check(removed.resolve(use: use)).identicalTo(removed.styles.single);
      check(removed.artworkFor(use: use).path).isNotNull();
    }
    check(() => removed.removeStyles(styles: removed.styles)).throws<UnsupportedError>();
  });

  test('selects a private child application through one complete outer printing owner', () {
    final AiNativeAppearances source = _source(nestedStyleSource(reset: true));
    final AiNativeResourceUse outer = nestedAppearanceOwners(source).first;
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: outer);
    final AiNativeAppearances result = source.applyStyle(
      appearance: source.styles.last,
      artwork: [
        AiNativeAppearanceReplacement(artwork: owner, uses: [owner.nestedUses.first], bytes: latin1.encode(_cyan), bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140)),
      ],
    );
    final AiNativeAppearanceArtwork after = result.artworkFor(use: nestedAppearanceOwners(result).first);
    check(result.resolve(use: after.use)).identicalTo(result.styles.first);
    check(result.resolve(use: after.nestedUses.first)).identicalTo(result.styles.last);
    check(result.resolve(use: after.nestedUses.last)).identicalTo(result.styles[1]);
    final AiNativeItem first = owner.authoringFor(use: owner.nestedUses.first);
    final AiNativeItem next = after.authoringFor(use: after.nestedUses.first);
    check(_bytes(result, next.start, next.end)).deepEquals(_bytes(source, first.start, first.end));
  });

  test('preserves native mask fields when reapplying a different appearance', () {
    final AiNativeAppearances source = _source(opacityMaskSource());
    final AiNativeOpacityMask before = source.artworkFor(use: source.uses.first).opacityMasks.single;
    final AiNativeAppearances result = source.applyStyle(
      appearance: source.styles.last,
      artwork: [appearanceArtworkReplacement(source, 0, bytes: transparencyPrinting)],
    );
    final AiNativeOpacityMask after = result.artworkFor(use: result.uses.first).opacityMasks.single;
    check(_bytes(result, after.record.start, after.record.end)).deepEquals(_bytes(source, before.record.start, before.record.end));
  });

  test('rejects incomplete stale duplicated and foreign application ownership', () {
    final AiNativeAppearances source = _source(appearanceArtworkSource());
    final AiNativeAppearanceReplacement first = appearanceArtworkReplacement(source, 0, bytes: _cyan);
    check(() => source.applyStyle(appearance: source.styles.last, artwork: [])).throws<ArgumentError>();
    check(() => source.applyStyle(appearance: source.styles.last, artwork: [first, first])).throws<ArgumentError>();
    check(() => source.applyStyle(appearance: _source(appearanceArtworkSource()).styles.last, artwork: [first])).throws<ArgumentError>();
    final AiNativeAppearances result = source.applyStyle(appearance: source.styles.last, artwork: [first]);
    check(() => result.applyStyle(appearance: result.styles.last, artwork: [first])).throws<ArgumentError>();
    check(
      () => source.applyStyle(
        appearance: source.styles.last,
        artwork: [appearanceArtworkReplacement(source, 0, bytes: 'u\n0.8 g 0 0 m 1 1 L S\nU')],
      ),
    ).throws<UnsupportedError>();
  });

  test('rejects changed inherited state reaching an unqualified following consumer', () {
    final String source = appearanceArtworkSource();
    final String dependent = source
        .replaceRange(source.lastIndexOf(appearanceArtworkState), source.lastIndexOf(appearanceArtworkState) + appearanceArtworkState.length, '')
        .replaceAll('0 0 0 1 k\n', '');
    final AiNativeAppearances model = _source(dependent);
    check(
      () => model.applyStyle(
        appearance: model.styles.last,
        artwork: [appearanceArtworkReplacement(model, 0, bytes: 'u\n0 0 m 10 0 L 10 10 L f\nU')],
      ),
    ).throws<UnsupportedError>();
    check(model.styles.first.uses).length.equals(2);
    check(model.styles.last.uses).isEmpty();
  });
}
