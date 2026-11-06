import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_removal_test.dart' show appearanceRemovalSource;
import 'ai_native_image_creation_test.dart' show createdImageSamples;

/// Checks read-only boundary inspection without interpreting either view as defaults.
void main() {
  test('reports different native and printing outputs without changing source', () {
    final String bytes = appearanceRemovalSource();
    final AiNativeAppearances model = appearanceEditingModel(source: bytes);
    final AiNativeAppearanceState state = model.stateAtArtwork(artwork: model.artworkFor(use: model.uses.single));
    check(state.native['fill']!.operator).equals('g');
    check(state.native['fill']!.numbers!).deepEquals([.25]);
    check(state.printing['fill']!.operator).equals('k');
    check(state.printing['fill']!.numbers!).deepEquals([0, 0, 0, 1]);
    check(state.unknownNative).isEmpty();
    check(state.unknownPrinting).isEmpty();
    check(state.native.clear).throws<UnsupportedError>();
    check(state.unknownNative.clear).throws<UnsupportedError>();
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(bytes);
  });

  test('reports a hidden style write as unknown while retaining printing state', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceRemovalSource(visible: false));
    final AiNativeAppearanceState state = model.stateAtArtwork(artwork: model.artworkFor(use: model.uses.single));
    check(state.native.containsKey('fill')).isFalse();
    check(state.unknownNative.contains('fill')).isTrue();
    check(state.printing['fill']!.operator).equals('k');
  });

  test('rejects a complete owner from another immutable snapshot', () {
    final String source = appearanceRemovalSource();
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeAppearances foreign = appearanceEditingModel(source: source);
    check(() => model.stateAtArtwork(artwork: foreign.artworkFor(use: foreign.uses.single))).throws<ArgumentError>();
  });

  test('batches complete endpoints without accepting repeated ownership', () {
    final AiNativeAppearances model = appearanceEditingModel(source: appearanceArtworkSource());
    final List<AiNativeAppearanceArtwork> owners = [for (final AiNativeResourceUse use in model.uses) model.artworkFor(use: use)];
    final Map<AiNativeAppearanceArtwork, AiNativeAppearanceState> states = model.statesAfterArtwork(artwork: owners);
    check(states.keys).deepEquals(owners);
    for (final AiNativeAppearanceArtwork owner in owners) {
      check(states[owner]!.native.keys).deepEquals(model.stateAtArtwork(artwork: owner).native.keys);
    }
    check(states.clear).throws<UnsupportedError>();
    check(() => model.statesAfterArtwork(artwork: [owners.first, owners.first])).throws<ArgumentError>();
  });

  test('reads printable raster inputs separately from restored pair outputs', () {
    final AiNativeAppearances original = appearanceEditingModel(source: appearanceRemovalSource());
    final AiNativeAppearanceArtwork first = original.artworkFor(use: original.uses.single);
    final AiNativeAppearances model = original.applyStyle(
      appearance: original.styles.single,
      artwork: [
        AiNativeAppearanceReplacement.raster(
          artwork: first,
          samples: createdImageSamples(),
          matrix: [1, 0, 0, 1, 0, 0],
          transparency: AiNativeTransparency(blendMode: .normal, opacity: .3, isolated: false, knockout: .off, alphaIsShape: false),
          bounds: AiBoundingBox(left: 0, bottom: -10, right: 10, top: 10),
        ),
      ],
    );
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.single);
    final AiNativeAppearanceState before = model.stateAtArtwork(artwork: owner, beforeRaster: owner.printingRasters.single);
    check(before.printing['Xy']!.numbers![1]).equals(.3);
    check(model.stateAtArtwork(artwork: owner).printing['Xy']!.numbers![1]).equals(1);
    final AiNativeRaster foreign = AiNativeRasters.decode(records: model.structure.drawing.records).images.single;
    check(() => model.stateAtArtwork(artwork: owner, beforeRaster: foreign)).throws<ArgumentError>();
  });
}
