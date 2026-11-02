import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupsSource;
import 'ai_native_opacity_masks_test.dart' show opacityMaskSource;

/// Reads exact bytes for independent geometry, printing and mask preservation.
List<int> _bytes(AiNativeAppearances model, AiNativeItem item) => model.structure.drawing.records.program.bytes.sublist(item.start, item.end);

/// Reads the current source names through exact authoring handles.
List<List<int>> _names(AiNativeAppearances model, AiNativeItem target) => AiNativeObjects.decode(drawing: model.structure.drawing).forSource(target).names.map((name) => name.stringBytes!).toList();

/// Deferred regressions for nonvisual private metadata transactions.
void main() {
  test('renames root child and nested group without touching printing styles or neighbor owners', () {
    for (final bool metadata in [false, true]) {
      final String text = appearanceGroupsSource(metadata: metadata);
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
      final AiNativeGroup nested = owner.group!.children.whereType<AiNativeGroup>().single;
      final AiNativeAppearances result = model.renameArtworkObjects(
        names: {
          owner.authoring: utf8.encode('Groupe (été)'),
          owner.group!.paths.first: utf8.encode('Tracé'),
          nested: utf8.encode('Interne'),
          nested.paths.single: utf8.encode('Ajout'),
        },
        artwork: [owner],
      );
      final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
      check(_names(result, after.authoring)).deepEquals([utf8.encode('Groupe (été)')]);
      check(_names(result, after.group!.paths.first)).deepEquals([utf8.encode('Tracé')]);
      check(_names(result, after.group!.children.whereType<AiNativeGroup>().single)).deepEquals([utf8.encode('Interne')]);
      check(_names(result, after.group!.paths.last)).deepEquals([utf8.encode('Ajout')]);
      check(_bytes(result, after.printingGroup)).deepEquals(_bytes(model, owner.printingGroup));
      for (final (int index, AiNativePath path) in owner.group!.paths.indexed) {
        check(_bytes(result, after.group!.paths.elementAt(index))).deepEquals(_bytes(model, path));
      }
      check(_bytes(result, result.styles.single.definition)).deepEquals(_bytes(model, model.styles.single.definition));
      final AiNativeAppearanceArtwork neighbor = model.artworkFor(use: model.uses.last);
      final AiNativeAppearanceArtwork retained = result.artworkFor(use: result.uses.last);
      check(result.structure.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(model.structure.drawing.records.program.bytes.sublist(neighbor.start, neighbor.end));
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('retains mask Art identities and shared applications when naming a standalone carrier', () {
    final AiNativeAppearances model = appearanceEditingModel(source: opacityMaskSource());
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
    final AiNativeAppearances result = model.renameArtworkObjects(names: {owner.path!: utf8.encode('Porteur renommé')}, artwork: [owner]);
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
    check(after.opacityMasks.single.artworkBytes).deepEquals(owner.opacityMasks.single.artworkBytes);
    check(after.authoringForMask(mask: after.opacityMasks.single)).identicalTo(after.path!);
    check(_bytes(result, after.path!)).deepEquals(_bytes(model, owner.path!));
    check(_bytes(result, after.printingGroup)).deepEquals(_bytes(model, owner.printingGroup));
    check(after.use.nameBytes).deepEquals(owner.use.nameBytes);
    check(result.structure.identifiers.map((identity) => identity.bytes)).deepEquals(model.structure.identifiers.map((identity) => identity.bytes));
  });

  test('fills empty aliases and appends a missing name after an undelimited metadata field', () {
    final String base = appearanceArtworkSource(metadata: true);
    for (final String text in [
      base.replaceFirst('(Native) /String (AIArtName)', '/String (AIArtName) , /UnicodeString (Object name)'),
      base.replaceFirst('(Native) /String (AIArtName) , ', '').replaceFirst('(0.5) /String (BBAccumRotation) , ;', '(0.5) /String (BBAccumRotation) ;'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
      final AiNativeAppearances result = model.renameArtworkObjects(
        names: {
          owner.path!: [65, 66],
        },
        artwork: [owner],
      );
      final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
      check(_names(result, after.path!).every((name) => latin1.decode(name) == 'AB')).isTrue();
      check(after.dictionary!['BBAccumRotation']!.text()).equals('0.5');
      check(after.dictionary!['AI10_ArtUID']!.container!.entries.single.stringBytes).isNotNull().deepEquals(owner.dictionary!['AI10_ArtUID']!.container!.entries.single.stringBytes!);
    }
  });

  test('rejects foreign printing mask-art and incompletely covered objects atomically', () {
    final AiNativeAppearances model = appearanceEditingModel(source: opacityMaskSource());
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
    final List<int> before = model.structure.drawing.records.program.bytes.toList();
    for (final AiNativeItem target in [owner.printingGroup, owner.opacityMasks.single.artworkDrawing.paths.single, model.artworkFor(use: model.uses.last).authoring]) {
      check(
        () => model.renameArtworkObjects(
          names: {
            target: [65],
          },
          artwork: [owner],
        ),
      ).throws<ArgumentError>();
    }
    check(
      () => model.renameArtworkObjects(
        names: {
          owner.path!: [65],
        },
        artwork: [],
      ),
    ).throws<ArgumentError>();
    check(
      () => model.renameArtworkObjects(
        names: {
          owner.path!: [256],
        },
        artwork: [owner],
      ),
    ).throws<ArgumentError>();
    check(() => model.renameArtworkObjects(names: {}, artwork: [owner])).throws<ArgumentError>();
    check(
      () => appearanceEditingModel(source: opacityMaskSource()).renameArtworkObjects(
        names: {
          owner.path!: [65],
        },
        artwork: [owner],
      ),
    ).throws<ArgumentError>();
    check(model.structure.drawing.records.program.bytes).deepEquals(before);
  });
}
