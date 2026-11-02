import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_artboard_masks_test.dart' show artboardMaskRaster, artboardOpacityMask;
import 'ai_native_transparency_test.dart' show editTransparency, transparencyPrinting, transparencySource;

/// Adds a complete source mask to a path, group or private group child.
String opacityMaskSource({bool grouped = false, bool child = false, String? mask}) {
  final String source = transparencySource(grouped: grouped);
  final String label = grouped ? (child ? 'First contour' : 'Outer group') : 'Native';
  return source.replaceFirst('($label) /String (AIArtName)', '($label) /String (AIArtName) ,\n${mask ?? artboardOpacityMask(art: '%_0.3 g 0 0 m 10 0 L 10 10 L f\n')}%_(AI9_Mask)');
}

/// Explicit host settings exercising every nondefault flag.
const AiNativeOpacityMaskSettings changedMaskSettings = AiNativeOpacityMaskSettings(linked: false, disabled: true, clipping: true, inverted: true);

/// Changes one selected complete owner with independently supplied printing.
AiNativeAppearances editOpacityMask(AiNativeAppearances model, {List<int>? artworkBytes, AiNativeOpacityMaskSettings? settings = changedMaskSettings, String printing = transparencyPrinting}) =>
    model.updateOpacityMasks(
      changes: [
        AiNativeOpacityMaskChange(
          mask: model.artworkFor(use: model.uses.first).opacityMasks.single,
          settings: settings,
          artworkBytes: artworkBytes,
        ),
      ],
      artwork: [appearanceArtworkReplacement(model, 0, bytes: printing)],
    );

/// Checks mask ownership, source preservation and atomic synchronization.
void main() {
  test('binds path group and child masks without conflating clipping contours', () {
    for (final (bool, bool) selection in [(false, false), (true, false), (true, true)]) {
      final AiNativeAppearances model = appearanceEditingModel(
        source: opacityMaskSource(grouped: selection.$1, child: selection.$2),
      );
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
      final AiNativeOpacityMask mask = owner.opacityMasks.single;
      check(mask.settings.linked).isTrue();
      check(mask.artworkDrawing.paths).length.equals(1);
      check(mask.settings.disabled).isFalse();
      check(mask.settings.clipping).isFalse();
      check(mask.settings.inverted).isFalse();
      check(owner.opacityMasks.clear).throws<UnsupportedError>();
      check(() => mask.artworkBytes[0] = 0).throws<UnsupportedError>();
      final AiNativeAppearances changed = editOpacityMask(model);
      final AiNativeAppearanceArtwork after = changed.artworkFor(use: changed.uses.first);
      check(after.opacityMasks.single.artworkBytes).deepEquals(mask.artworkBytes);
      check(after.opacityMasks.single.settings.linked).isFalse();
      check(after.opacityMasks.single.settings.disabled).isTrue();
      check(after.opacityMasks.single.settings.clipping).isTrue();
      check(after.opacityMasks.single.settings.inverted).isTrue();
      check(changed.styles).length.equals(model.styles.length);
      final AiNativeAppearanceArtwork neighbor = model.artworkFor(use: model.uses.last);
      final AiNativeAppearanceArtwork retained = changed.artworkFor(use: changed.uses.last);
      check(changed.structure.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(model.structure.drawing.records.program.bytes.sublist(neighbor.start, neighbor.end));
    }
  });

  test('edits each flag combination and keeps hostile raster samples exact', () {
    final String raster = artboardMaskRaster(pixels: latin1.encode('X+\n%_/Mask : 0 /Bool (Inverted) , ; %%EndData'));
    final String source = opacityMaskSource(mask: artboardOpacityMask(art: raster));
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeOpacityMask original = model.artworkFor(use: model.uses.first).opacityMasks.single;
    check(original.artworkDrawing.items.whereType<AiNativeRaster>()).length.equals(1);
    for (int flags = 0; flags < 16; flags++) {
      final AiNativeAppearances changed = editOpacityMask(
        model,
        settings: AiNativeOpacityMaskSettings(linked: flags & 1 != 0, disabled: flags & 2 != 0, clipping: flags & 4 != 0, inverted: flags & 8 != 0),
      );
      final AiNativeOpacityMask mask = changed.artworkFor(use: changed.uses.first).opacityMasks.single;
      check(mask.artworkBytes).deepEquals(original.artworkBytes);
      check(mask.settings.linked).equals(flags & 1 != 0);
      check(mask.settings.disabled).equals(flags & 2 != 0);
      check(mask.settings.clipping).equals(flags & 4 != 0);
      check(mask.settings.inverted).equals(flags & 8 != 0);
    }
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
  });

  test('replaces vector empty and raster mask artwork with bounded native syntax', () {
    final AiNativeAppearances model = appearanceEditingModel(source: opacityMaskSource());
    for (final String content in [
      '',
      '%_0.8 g 0 0 m 20 0 L 20 20 L f\n',
      artboardMaskRaster(pixels: [255, 0]).replaceFirst('(board-0) /UnicodeString (AI24 ImageRawDataUUID) ,', '').replaceFirst('(kept-alpha) /String (AI24 ImageAlphaRawDataUUID) ,', ''),
    ]) {
      final List<int> bytes = latin1.encode('X=\n%_0 Ae u 0 Ap\n$content%_U\n%_9 () XW\n%_X+');
      final AiNativeAppearances changed = editOpacityMask(model, settings: null, artworkBytes: bytes);
      final AiNativeOpacityMask mask = changed.artworkFor(use: changed.uses.first).opacityMasks.single;
      check(mask.artworkBytes).deepEquals(bytes);
      check(mask.settings.linked).isTrue();
      check(mask.settings.disabled).isFalse();
    }
  });

  test('retains recursive masks while editing the owning outer flags', () {
    final String art = '%_0.5 g 0 0 m 10 0 L 10 10 L f\n%_/ArtDictionary :\n${artboardOpacityMask(art: '')}%_(AI9_Mask) , ;\n';
    final AiNativeAppearances model = appearanceEditingModel(
      source: opacityMaskSource(mask: artboardOpacityMask(art: art)),
    );
    final AiNativeAppearances changed = editOpacityMask(model);
    check(changed.artworkFor(use: changed.uses.first).opacityMasks.single.artworkBytes).deepEquals(model.artworkFor(use: model.uses.first).opacityMasks.single.artworkBytes);
  });

  test('keeps existing transparency editing usable on a masked selected object', () {
    final AiNativeAppearances model = appearanceEditingModel(source: opacityMaskSource());
    final AiNativeAppearances changed = editTransparency(model);
    check(changed.styles).length.equals(2);
    check(changed.artworkFor(use: changed.uses.first).opacityMasks.single.artworkBytes).deepEquals(model.artworkFor(use: model.uses.first).opacityMasks.single.artworkBytes);
  });

  test('rejects stale missing duplicate or unrelated printing coverage atomically', () {
    final String source = opacityMaskSource();
    final AiNativeAppearances model = appearanceEditingModel(source: source);
    final AiNativeOpacityMaskChange change = AiNativeOpacityMaskChange(
      mask: model.artworkFor(use: model.uses.first).opacityMasks.single,
      settings: changedMaskSettings,
    );
    final AiNativeAppearances other = appearanceEditingModel(source: source);
    for (final List<AiNativeAppearanceReplacement> artwork in [
      <AiNativeAppearanceReplacement>[],
      [appearanceArtworkReplacement(model, 1)],
      [appearanceArtworkReplacement(other, 0)],
      [appearanceArtworkReplacement(model, 0), appearanceArtworkReplacement(model, 0)],
    ]) {
      check(() => model.updateOpacityMasks(changes: [change], artwork: artwork)).throws<ArgumentError>();
    }
    check(() => model.updateOpacityMasks(changes: [change, change], artwork: [appearanceArtworkReplacement(model, 0)])).throws<ArgumentError>();
    check(() => editOpacityMask(model, printing: transparencyPrinting.replaceFirst('0 1 0 0 0 Xy', '2 1 0 0 0 Xy'))).throws<UnsupportedError>();
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(source);
  });

  test('batches two masks sharing one printing owner and rebinds current handles', () {
    final String text = opacityMaskSource(grouped: true).replaceFirst('(First contour) /String (AIArtName)', '(First contour) /String (AIArtName) ,\n${artboardOpacityMask(art: '')}%_(AI9_Mask)');
    final AiNativeAppearances model = appearanceEditingModel(source: text);
    final List<AiNativeOpacityMask> masks = model.artworkFor(use: model.uses.first).opacityMasks;
    check(masks).length.equals(2);
    final AiNativeAppearances changed = model.updateOpacityMasks(
      changes: [for (final AiNativeOpacityMask mask in masks) AiNativeOpacityMaskChange(mask: mask, settings: changedMaskSettings)],
      artwork: [appearanceArtworkReplacement(model, 0, bytes: transparencyPrinting)],
    );
    check(changed.artworkFor(use: changed.uses.first).opacityMasks.every((mask) => mask.settings.inverted)).isTrue();
    check(
      () => changed.updateOpacityMasks(
        changes: [AiNativeOpacityMaskChange(mask: masks.first, settings: changedMaskSettings)],
        artwork: [appearanceArtworkReplacement(changed, 0, bytes: transparencyPrinting)],
      ),
    ).throws<ArgumentError>();
  });

  test('rejects stale image caches and accepts explicitly fresh raster identities', () {
    final AiNativeAppearances model = appearanceEditingModel(source: opacityMaskSource(mask: artboardOpacityMask()));
    final AiNativeOpacityMask mask = model.artworkFor(use: model.uses.first).opacityMasks.single;
    final String original = latin1.decode(mask.artworkBytes);
    check(() => editOpacityMask(model, artworkBytes: latin1.encode(original.replaceFirst('1 /Real', '2 /Real')))).throws<UnsupportedError>();
    final String fresh = original.replaceFirst('(board-0)', '(11111111-1111-4111-8111-111111111111)').replaceFirst('(kept-alpha)', '(22222222-2222-4222-8222-222222222222)');
    check(editOpacityMask(model, artworkBytes: latin1.encode(fresh)).structure.drawing.records.program.bytes).isNotEmpty();
    check(editOpacityMask(model, artworkBytes: mask.artworkBytes).structure.drawing.records.program.bytes).isNotEmpty();
    const String identity = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final AiNativeAppearances identified = appearanceEditingModel(source: opacityMaskSource(mask: artboardOpacityMask().replaceFirst('board-0', identity)));
    final String alias = latin1.decode(identified.artworkFor(use: identified.uses.first).opacityMasks.single.artworkBytes).replaceFirst(identity, identity.toUpperCase());
    check(() => editOpacityMask(identified, artworkBytes: latin1.encode(alias))).throws<UnsupportedError>();
  });

  test('retains identities on flag or identical-art edits and rejects implicit identity replacement', () {
    const String art = '%_0.5 g 0 0 m 10 0 L 10 10 L f\n%_/ArtDictionary : /XMLUID : (mask-child) ; (AI10_ArtUID) , ;\n';
    final AiNativeAppearances model = appearanceEditingModel(
      source: opacityMaskSource(mask: artboardOpacityMask(art: art)),
    );
    final AiNativeOpacityMask mask = model.artworkFor(use: model.uses.first).opacityMasks.single;
    check(editOpacityMask(model).structure.identifiers.map((identifier) => latin1.decode(identifier.bytes))).contains('mask-child');
    check(editOpacityMask(model, artworkBytes: mask.artworkBytes).structure.identifiers.map((identifier) => latin1.decode(identifier.bytes))).contains('mask-child');
    check(() => editOpacityMask(model, artworkBytes: latin1.encode(latin1.decode(mask.artworkBytes).replaceFirst('0.5 g', '0.7 g')))).throws<UnsupportedError>();
    final AiNativeAppearances plain = appearanceEditingModel(source: opacityMaskSource());
    check(() => editOpacityMask(plain, artworkBytes: mask.artworkBytes)).throws<UnsupportedError>();
  });

  test('keeps opaque masks inspectable and enforces source and output limits', () {
    final String text = opacityMaskSource(mask: artboardOpacityMask(art: '%_17 FutureMask\n'));
    final AiNativeAppearances model = appearanceEditingModel(source: text);
    final AiNativeRecords records = model.structure.drawing.records;
    final AiNativeContainer record = records.containers.singleWhere((record) => record.type == 'Mask');
    check(AiNativeOpacityMask.decode(records: records, record: record).settings.linked).isTrue();
    check(
      () => AiNativeOpacityMask.decode(
        records: appearanceEditingModel(source: text).structure.drawing.records,
        record: record,
      ),
    ).throws<ArgumentError>();
    check(() => model.artworkFor(use: model.uses.first)).throws<UnsupportedError>();
    final String valid = opacityMaskSource();
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: valid,
      limits: AiNativeLimits(maxDecodedBytes: latin1.encode(valid).length + 100),
    );
    final AiNativeOpacityMask mask = bounded.artworkFor(use: bounded.uses.first).opacityMasks.single;
    check(() => editOpacityMask(bounded, artworkBytes: [...mask.artworkBytes.take(2), ...List.filled(200, 32), ...mask.artworkBytes.skip(2)])).throws<FormatException>();
  });

  test('rejects malformed unknown executable and named mask dependencies', () {
    for (final String mask in [
      artboardOpacityMask(art: '').replaceFirst('1 /Bool (Linked)', '2 /Bool (Linked)'),
      artboardOpacityMask(art: '').replaceFirst('(Linked)', '(Future)'),
      artboardOpacityMask(art: '').replaceFirst('1 /Bool (Linked) ,', ''),
      artboardOpacityMask(art: '').replaceFirst('1 /Bool (Linked) ,', '1 /Bool (Linked) , 0 /Bool (Linked) ,'),
      artboardOpacityMask(art: '').replaceFirst('X=', '1 X='),
      artboardOpacityMask(art: '').replaceFirst('%_X+', 'X+'),
      artboardOpacityMask(art: '%_(Shared) load\n'),
      artboardOpacityMask(art: '%_1 (Shared) XW\n'),
      artboardOpacityMask(art: '%_%AI24_Unknown: data\n'),
    ]) {
      final String text = opacityMaskSource(mask: mask);
      final AiNativeAppearances model = appearanceEditingModel(source: text);
      expect(() => model.artworkFor(use: model.uses.firstWhere((use) => !use.instruction.isPrivate)), throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())));
      check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('rejects replacement artwork escaping its native owner or containing unknown commands', () {
    final AiNativeAppearances model = appearanceEditingModel(source: opacityMaskSource());
    for (final String bytes in ['X=\n%_1 load\n%_X+', 'X=\n%_u\n%_X+', 'X= X+ ; /ArtDictionary : (new) /String (Future) , ;', 'X=\n%_1 (Shared) XW\n%_X+']) {
      expect(() => editOpacityMask(model, artworkBytes: latin1.encode(bytes)), throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())));
    }
  });
}
