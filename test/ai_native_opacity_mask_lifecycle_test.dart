import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel, appearanceEditingSource;
import 'ai_native_artboard_masks_test.dart' show artboardMaskRaster, artboardOpacityMask;
import 'ai_native_opacity_masks_test.dart' show changedMaskSettings, opacityMaskSource;
import 'ai_native_transparency_test.dart' show transparencyPrinting, transparencySource;

/// Complete host-authored grayscale content with explicit native boundaries.
List<int> _art({String content = '%_0.3 g 0 0 m 10 0 L 10 10 L f\n'}) => latin1.encode('X=\n%_0 Ae u 0 Ap\n$content%_U\n%_9 () XW\n%_X+');

/// Supplies one complete owner for a native mask transaction.
List<AiNativeAppearanceReplacement> _printing(AiNativeAppearances model) => [appearanceArtworkReplacement(model, 0, bytes: transparencyPrinting)];

/// Reads a native source span without normalizing its formatting.
List<int> _bytes(AiNativeAppearances model, int start, int end) => model.structure.drawing.records.program.bytes.sublist(start, end);

/// Exercises attachment/removal ownership while keeping rendering in the host.
void main() {
  test('creates and deletes an outer path or group mask retaining metadata and neighbors', () {
    for (final bool grouped in [false, true]) {
      final String source = transparencySource(grouped: grouped);
      final AiNativeAppearances model = appearanceEditingModel(source: source);
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
      final AiNativeAppearances created = model.createOpacityMasks(
        masks: [AiNativeOpacityMaskAttachment(artwork: owner, settings: changedMaskSettings, artworkBytes: _art())],
        artwork: _printing(model),
      );
      final AiNativeAppearanceArtwork after = created.artworkFor(use: created.uses.first);
      check(after.opacityMasks.single.artworkBytes).deepEquals(_art());
      check(after.opacityMasks.single.settings.inverted).isTrue();
      check(after.opacityMasks.single.settings.linked).isFalse();
      check(after.opacityMasks.single.artworkDrawing.paths).length.equals(1);
      check(_bytes(created, after.authoring.start, after.authoring.end)).deepEquals(_bytes(model, owner.authoring.start, owner.authoring.end));
      for (final AiNativeEntry field in owner.dictionary!.entries) {
        check(after.dictionary![field.key!]!.text()).equals(field.text());
      }
      final AiNativeAppearanceArtwork neighbor = model.artworkFor(use: model.uses.last);
      final AiNativeAppearanceArtwork retained = created.artworkFor(use: created.uses.last);
      check(_bytes(created, retained.start, retained.end)).deepEquals(_bytes(model, neighbor.start, neighbor.end));
      final AiNativeAppearances removed = created.deleteOpacityMasks(masks: after.opacityMasks, artwork: _printing(created));
      check(removed.artworkFor(use: removed.uses.first).opacityMasks).isEmpty();
      check(removed.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(model.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes)));
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
    }
  });

  test('creates authoring metadata when absent and appends after a final undelimited field', () {
    for (final String source in [
      appearanceArtworkSource().replaceAll('\nU\n', '\n0 1 0 0 0 Xy\nU\n'),
      transparencySource().replaceFirst('(0.5) /String (BBAccumRotation) , ;', '(0.5) /String (BBAccumRotation) ;'),
    ]) {
      final AiNativeAppearances model = appearanceEditingModel(source: source);
      final AiNativeAppearances created = model.createOpacityMasks(
        masks: [
          AiNativeOpacityMaskAttachment(
            artwork: model.artworkFor(use: model.uses.first),
            settings: changedMaskSettings,
            artworkBytes: _art(content: ''),
          ),
        ],
        artwork: _printing(model),
      );
      check(created.artworkFor(use: created.uses.first).opacityMasks.single.artworkDrawing.paths).isEmpty();
      final AiNativeAppearances removed = created.deleteOpacityMasks(
        masks: created.artworkFor(use: created.uses.first).opacityMasks,
        artwork: _printing(created),
      );
      check(removed.artworkFor(use: removed.uses.first).opacityMasks).isEmpty();
    }
  });

  test('attaches to private children and outer groups with one complete printing replacement', () {
    final AiNativeAppearances model = appearanceEditingModel(source: transparencySource(grouped: true));
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
    final AiNativeGroup nested = owner.group!.children.whereType<AiNativeGroup>().single;
    final List<AiNativeItem> targets = [owner.authoring, owner.group!.paths.first, nested];
    final AiNativeAppearances created = model.createOpacityMasks(
      masks: [for (final AiNativeItem target in targets) AiNativeOpacityMaskAttachment(artwork: owner, target: target, settings: changedMaskSettings, artworkBytes: _art())],
      artwork: _printing(model),
    );
    final AiNativeAppearanceArtwork after = created.artworkFor(use: created.uses.first);
    check(after.opacityMasks).length.equals(3);
    final AiNativeAppearances removed = created.deleteOpacityMasks(masks: [after.opacityMasks[1]], artwork: _printing(created));
    final List<AiNativeOpacityMask> remaining = removed.artworkFor(use: removed.uses.first).opacityMasks;
    check(remaining).length.equals(2);
    check(remaining.every((mask) => mask.settings.disabled)).isTrue();
    final AiNativeAppearances cleared = removed.deleteOpacityMasks(masks: remaining, artwork: _printing(removed));
    check(cleared.artworkFor(use: cleared.uses.first).opacityMasks).isEmpty();
  });

  test('preserves counted binary mask bytes containing native delimiters', () {
    final List<int> pixels = latin1.encode('X+\n%_/Mask : ; %%EndData\u0000');
    final String raster = artboardMaskRaster(pixels: pixels)
        .replaceFirst('(board-0) /UnicodeString (AI24 ImageRawDataUUID) ,', '')
        .replaceFirst('(kept-alpha) /String (AI24 ImageAlphaRawDataUUID) ,', '');
    final AiNativeAppearances model = appearanceEditingModel(source: transparencySource());
    final List<int> bytes = _art(content: raster);
    final AiNativeOpacityMaskAttachment attachment = AiNativeOpacityMaskAttachment(
      artwork: model.artworkFor(use: model.uses.first),
      settings: changedMaskSettings,
      artworkBytes: bytes,
    );
    bytes[0] = 0;
    final AiNativeAppearances created = model.createOpacityMasks(masks: [attachment], artwork: _printing(model));
    final AiNativeOpacityMask mask = created.artworkFor(use: created.uses.first).opacityMasks.single;
    check(mask.artworkBytes).deepEquals(_art(content: raster));
    check(mask.artworkDrawing.items.whereType<AiNativeRaster>()).length.equals(1);
    check(() => attachment.artworkBytes[0] = 0).throws<UnsupportedError>();
    final AiNativeAppearances removed = created.deleteOpacityMasks(masks: [mask], artwork: _printing(created));
    check(removed.artworkFor(use: removed.uses.first).opacityMasks).isEmpty();
  });

  test('removes a final mask field while retaining its dictionary terminator', () {
    final String source = opacityMaskSource().replaceFirst('%_(AI9_Mask) , (0.5) /String (BBAccumRotation) , ;', '%_(AI9_Mask) ;');
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeAppearances removed = model.deleteOpacityMasks(
      masks: model.artworkFor(use: model.uses.first).opacityMasks,
      artwork: _printing(model),
    );
    final AiNativeAppearanceArtwork after = removed.artworkFor(use: removed.uses.first);
    check(after.opacityMasks).isEmpty();
    check(after.dictionary!['AIArtName']!.text()).equals('Native');
    check(after.dictionary!['AI10_ArtUID']).isNotNull();
  });

  test('requires distinct current targets and exactly the affected printing owners', () {
    final AiNativeAppearances model = appearanceEditingModel(source: transparencySource(grouped: true));
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
    final AiNativeOpacityMaskAttachment attachment = AiNativeOpacityMaskAttachment(artwork: owner, settings: changedMaskSettings, artworkBytes: _art());
    check(() => model.createOpacityMasks(masks: [attachment], artwork: [])).throws<ArgumentError>();
    check(() => model.createOpacityMasks(masks: [attachment, attachment], artwork: _printing(model))).throws<ArgumentError>();
    check(
      () => model.createOpacityMasks(
        masks: [attachment],
        artwork: [
          ..._printing(model),
          appearanceArtworkReplacement(model, 1, bytes: transparencyPrinting),
        ],
      ),
    ).throws<ArgumentError>();
    for (final AiNativeItem target in [owner.printingGroup, model.artworkFor(use: model.uses.last).authoring]) {
      check(
        () => model.createOpacityMasks(
          masks: [AiNativeOpacityMaskAttachment(artwork: owner, target: target, settings: changedMaskSettings, artworkBytes: _art())],
          artwork: _printing(model),
        ),
      ).throws<ArgumentError>();
    }
    final AiNativeAppearances created = model.createOpacityMasks(masks: [attachment], artwork: _printing(model));
    check(() => created.createOpacityMasks(masks: [attachment], artwork: _printing(created))).throws<ArgumentError>();
    final AiNativeAppearanceArtwork after = created.artworkFor(use: created.uses.first);
    check(
      () => created.createOpacityMasks(
        masks: [AiNativeOpacityMaskAttachment(artwork: after, settings: changedMaskSettings, artworkBytes: _art())],
        artwork: _printing(created),
      ),
    ).throws<ArgumentError>();
    check(() => model.deleteOpacityMasks(masks: after.opacityMasks, artwork: _printing(model))).throws<ArgumentError>();
    check(() => created.deleteOpacityMasks(masks: [after.opacityMasks.single, after.opacityMasks.single], artwork: _printing(created))).throws<ArgumentError>();
  });

  test('rejects opaque dependencies stale cache IDs and identified artwork atomically', () {
    final String source = transparencySource();
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    for (final String content in [
      '%_(unresolved) load\n',
      artboardMaskRaster(),
      '%_0.3 g 0 0 m 10 0 L 10 10 L f\n%_/ArtDictionary : /XMLUID : (mask-art) ; (AI10_ArtUID) , ;\n',
    ]) {
      check(
        () => model.createOpacityMasks(
          masks: [
            AiNativeOpacityMaskAttachment(
              artwork: model.artworkFor(use: model.uses.first),
              settings: changedMaskSettings,
              artworkBytes: _art(content: content),
            ),
          ],
          artwork: _printing(model),
        ),
      ).throws<UnsupportedError>();
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
    }
    final AiNativeAppearances identified = appearanceEditingModel(
      source: opacityMaskSource(mask: artboardOpacityMask(art: '%_0.3 g 0 0 m 10 0 L 10 10 L f\n%_/ArtDictionary : /XMLUID : (mask-art) ; (AI10_ArtUID) , ;\n')),
    );
    check(
      () => identified.deleteOpacityMasks(
        masks: identified.artworkFor(use: identified.uses.first).opacityMasks,
        artwork: _printing(identified),
      ),
    ).throws<UnsupportedError>();
  });

  test('rejects malformed artwork and a printing state change before exposing a snapshot', () {
    final AiNativeAppearances model = appearanceEditingModel(source: transparencySource());
    final AiNativeOpacityMaskAttachment incomplete = AiNativeOpacityMaskAttachment(
      artwork: model.artworkFor(use: model.uses.first),
      settings: changedMaskSettings,
      artworkBytes: latin1.encode('X='),
    );
    check(() => model.createOpacityMasks(masks: [incomplete], artwork: _printing(model))).throws<FormatException>();
    final AiNativeOpacityMaskAttachment attachment = AiNativeOpacityMaskAttachment(
      artwork: model.artworkFor(use: model.uses.first),
      settings: changedMaskSettings,
      artworkBytes: _art(),
    );
    check(
      () => model.createOpacityMasks(
        masks: [attachment],
        artwork: [appearanceArtworkReplacement(model, 0, bytes: 'u\n0.8 g 0 0 m 1 1 L S\nU')],
      ),
    ).throws<UnsupportedError>();
  });

  test('creates updates and removes an authoritative live-shape mask without changing geometry', () {
    final String source = appearanceEditingSource()
        .replaceAll('%AI17_Begin_Content_if_version_gt:17 4\n', '')
        .replaceAll('%AI17_Alternate_Content\n%_/ArtDictionary : (0) /String (BBAccumRotation) , ;\n%AI17_End_Versioned_Content\n', '');
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
    final AiNativeAppearances created = model.createOpacityMasks(
      masks: [AiNativeOpacityMaskAttachment(artwork: owner, settings: changedMaskSettings, artworkBytes: _art())],
      artwork: [appearanceArtworkReplacement(model, 0)],
    );
    final AiNativeAppearanceArtwork after = created.artworkFor(use: created.uses.first);
    check(after.liveShape).isNotNull();
    check(after.opacityMasks).length.equals(1);
    check(_bytes(created, after.path!.start, after.path!.end)).deepEquals(_bytes(model, owner.path!.start, owner.path!.end));
    check(after.liveShape!.parameters.entries.map((field) => field.key!)).deepEquals(owner.liveShape!.parameters.entries.map((field) => field.key!));
    for (final String key in owner.liveShape!.parameters.entries.map((field) => field.key!)) {
      check(after.liveShape!.parameters[key]!.number).equals(owner.liveShape!.parameters[key]!.number);
    }
    check(() => created.structure.drawing.translateLiveShapes(shapes: [after.liveShape!], deltaX: 1, deltaY: 0)).throws<UnsupportedError>();
    final AiNativeAppearances updated = created.updateOpacityMasks(
      changes: [AiNativeOpacityMaskChange(mask: after.opacityMasks.single, settings: const AiNativeOpacityMaskSettings(linked: true, disabled: false, clipping: false, inverted: false))],
      artwork: [appearanceArtworkReplacement(created, 0)],
    );
    final AiNativeOpacityMask mask = updated.artworkFor(use: updated.uses.first).opacityMasks.single;
    check(mask.settings.disabled).isFalse();
    check(mask.artworkBytes).deepEquals(_art());
    final AiNativeAppearances removed = updated.deleteOpacityMasks(masks: [mask], artwork: [appearanceArtworkReplacement(updated, 0)]);
    check(removed.artworkFor(use: removed.uses.first).opacityMasks).isEmpty();
    check(removed.structure.drawing.liveShapes.every((shape) => shape.isBound)).isTrue();
  });

  test('refuses new masks across live-shape metadata alternatives', () {
    final AiNativeAppearances model = appearanceEditingModel();
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
    check(
      () => model.createOpacityMasks(
        masks: [AiNativeOpacityMaskAttachment(artwork: owner, settings: changedMaskSettings, artworkBytes: _art())],
        artwork: [appearanceArtworkReplacement(model, 0)],
      ),
    ).throws<UnsupportedError>();
  });
}
