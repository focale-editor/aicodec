import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Reads source-owned bytes without normalizing dictionaries or style records.
List<int> _bytes(AiNativeAppearances model, AiNativeItem item) => model.structure.drawing.records.program.bytes.sublist(item.start, item.end);

/// Keeps the supplied printing geometry independent from authoring closure flags.
AiNativeAppearanceReplacement _printing(AiNativeAppearances model, AiNativeAppearanceArtwork owner) => AiNativeAppearanceReplacement(
  artwork: owner,
  bytes: _bytes(model, owner.printingGroup),
  bounds: AiBoundingBox(left: 0, bottom: 0, right: 10, top: 10),
);

/// Supplies all authoring anchors without a count-only closing endpoint.
AiNativeAppearanceContourChange _change(AiNativePath path, {required bool closed, required bool flags}) => AiNativeAppearanceContourChange(
  path: path,
  segments: [
    AiPathSegment(operator: 'm', coordinates: [0, 0]),
    AiPathSegment(operator: 'L', coordinates: [10, 0]),
    AiPathSegment(operator: 'L', coordinates: [10, 10]),
  ],
  closed: closed,
  hidden: flags,
  locked: flags,
);

/// Deferred regressions for complete standalone closure and flag transactions.
void main() {
  test('opens and recloses counted paths while retaining dictionaries styles and following state', () {
    for (final bool metadata in [false, true]) {
      final AiNativeAppearances original = appearanceEditingModel(source: appearanceArtworkSource(counted: true, metadata: metadata));
      final AiNativeAppearanceArtwork first = original.artworkFor(use: original.uses.first);
      AiNativeAppearances current = original;
      for (final bool closed in [false, true, false]) {
        final AiNativeAppearanceArtwork before = current.artworkFor(use: current.uses.first);
        final AiNativeAppearances changed = current.replaceArtworkContours(
          changes: [_change(before.path!, closed: closed, flags: !closed)],
          artwork: [_printing(current, before)],
        );
        final AiNativeAppearanceArtwork after = changed.artworkFor(use: changed.uses.first);
        check(after.path!.paint.operator).equals(closed ? 'n' : 'N');
        check(after.path!.geometry).length.equals(closed ? 4 : 3);
        final AiNativeInstruction count = changed.structure.drawing.items.whereType<AiNativeInstruction>().singleWhere(
          (item) => item.isPrivate && item.operator == 'As' && item.start > after.printingGroup.end && item.end < after.path!.start,
        );
        check(count.numbers!.single).equals(3.0);
        check(after.use.nameBytes).deepEquals(first.use.nameBytes);
        check(changed.styles).length.equals(original.styles.length);
        if (metadata) {
          check(_bytes(changed, after.dictionary!)).deepEquals(_bytes(original, first.dictionary!));
          check(_bytes(changed, after.printingDictionary!)).deepEquals(_bytes(original, first.printingDictionary!));
        }
        check(AiNativeObjects.decode(drawing: changed.structure.drawing).forSource(after.printingGroup).expansion).isNotNull();
        for (final bool native in [false, true]) {
          final List<Map<String, List<Object>>> states = artworkStates(changed.structure.drawing, native: native);
          check(states.first['A']).isNotNull().deepEquals(['A', if (closed) 0 else 1]);
          check(states.first['Xw']).isNotNull().deepEquals(['Xw', if (closed) 0 else 1]);
          if (native) {
            check(states[1]['A']).isNotNull().deepEquals(['A', if (closed) 0 else 1]);
            check(states[1]['Xw']).isNotNull().deepEquals(['Xw', if (closed) 0 else 1]);
          }
          check(states.skip(native ? 2 : 1)).deepEquals(artworkStates(original.structure.drawing, native: native).skip(native ? 2 : 1));
        }
        final AiNativeAppearanceArtwork neighbor = changed.artworkFor(use: changed.uses.last);
        final AiNativeAppearanceArtwork oldNeighbor = original.artworkFor(use: original.uses.last);
        check(changed.structure.drawing.records.program.bytes.sublist(neighbor.start, neighbor.end))
            .deepEquals(original.structure.drawing.records.program.bytes.sublist(oldNeighbor.start, oldNeighbor.end));
        current = changed;
      }
    }
  });

  test('keeps exact mask Art and its path carrier while changing attributes', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource(metadata: true));
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final List<int> art = AiNativeOpacityMask.encodeVectorArtwork(records: source.structure.drawing.records, elements: []);
    final AiNativeAppearances masked = source.createOpacityMasks(
      masks: [
        AiNativeOpacityMaskAttachment(
          artwork: owner,
          target: owner.path,
          settings: const AiNativeOpacityMaskSettings(linked: false, disabled: true, clipping: true, inverted: false),
          artworkBytes: art,
        ),
      ],
      artwork: [_printing(source, owner)],
    );
    final AiNativeAppearanceArtwork before = masked.artworkFor(use: masked.uses.first);
    final AiNativeAppearances result = masked.replaceArtworkContours(changes: [_change(before.path!, closed: false, flags: true)], artwork: [_printing(masked, before)]);
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
    check(after.authoringForMask(mask: after.opacityMasks.single)).identicalTo(after.path!);
    check(after.opacityMasks.single.artworkBytes).deepEquals(art);
    check(_bytes(result, after.dictionary!)).deepEquals(_bytes(masked, before.dictionary!));
    check(after.path!.geometry).length.equals(3);
    check(after.path!.paint.operator).equals('N');
  });

  test('requires exact current printing coverage and proven outgoing flag values', () {
    final String text = appearanceArtworkSource();
    final AiNativeAppearances model = appearanceEditingModel(source: text);
    final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
    final AiNativeAppearanceContourChange change = _change(owner.path!, closed: false, flags: true);
    check(() => model.replaceArtworkContours(changes: [change], artwork: [])).throws<ArgumentError>();
    check(() => model.replaceArtworkContours(changes: [change, change], artwork: [_printing(model, owner)])).throws<ArgumentError>();
    check(
      () => model.replaceArtworkContours(
        changes: [change],
        artwork: [_printing(model, model.artworkFor(use: model.uses.last))],
      ),
    ).throws<ArgumentError>();
    check(() => model.replaceArtworkContours(changes: [_change(owner.printingGroup.paths.single, closed: false, flags: true)], artwork: [_printing(model, owner)])).throws<ArgumentError>();
    final AiNativeAppearances foreign = appearanceEditingModel(source: text);
    check(() => foreign.replaceArtworkContours(changes: [change], artwork: [_printing(model, owner)])).throws<ArgumentError>();
    final AiNativeAppearances unknown = appearanceEditingModel(source: text.replaceAll('0 A', ''));
    final AiNativeAppearanceArtwork unproven = unknown.artworkFor(use: unknown.uses.first);
    check(() => unknown.replaceArtworkContours(changes: [_change(unproven.path!, closed: false, flags: true)], artwork: [_printing(unknown, unproven)])).throws<UnsupportedError>();
    check(latin1.decode(model.structure.drawing.records.program.bytes)).equals(text);
  });
}
