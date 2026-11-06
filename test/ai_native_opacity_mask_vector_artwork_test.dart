import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_opacity_masks_test.dart' show changedMaskSettings;
import 'ai_native_transparency_test.dart' show transparencyPrinting, transparencySource;

/// Explicit grayscale content with real opacity and no mask-local XML identity.
AiNativePathDefinition _path({double gray = .4, List<int>? identifier}) => AiNativePathDefinition(
  artwork: AiArtworkPath(
    segments: [
      AiPathSegment(operator: 'm', coordinates: [0, 0]),
      AiPathSegment(operator: 'L', coordinates: [10, 0]),
      AiPathSegment(operator: 'L', coordinates: [10, 10]),
    ],
    fill: AiColor(space: .gray, channels: [gray]),
    stroke: AiColor(space: .rgb, channels: [.2, .3, .4]),
    strokeWidth: 2,
    dash: [4, 2],
    closed: true,
  ),
  bounds: AiBoundingBox(left: 0, bottom: 0, right: 12, top: 12),
  opacity: .7,
  nameBytes: utf8.encode('Masque (été)\n%_literal'),
  identifierBytes: identifier,
);

/// An independently named clipped branch whose contours remain native artwork.
List<AiNativeAppearanceElementDefinition> _tree() => [
  AiNativeAppearanceGroupDefinition(
    nameBytes: utf8.encode('Groupe de masque'),
    clip: AiNativeAppearanceClipDefinition(segments: _path().artwork.segments, nameBytes: ascii.encode('Clip'), evenOdd: true),
    children: [
      AiNativeAppearancePathDefinition(definition: _path()),
      AiNativeAppearanceGroupDefinition(children: [AiNativeAppearancePathDefinition(definition: _path(gray: .8))]),
    ],
  ),
];

/// Supplies the complete owner's independent printable representation.
List<AiNativeAppearanceReplacement> _printing(AiNativeAppearances model) => [appearanceArtworkReplacement(model, 0, bytes: transparencyPrinting)];

/// Deferred creation/update regressions for typed mask authoring.
void main() {
  test('creates private mask artwork with process paints counts nested clips and escaped names', () {
    final AiNativeAppearances source = appearanceEditingModel(source: transparencySource(grouped: true));
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final Uint8List bytes = AiNativeOpacityMask.encodeVectorArtwork(records: source.structure.drawing.records, elements: _tree());
    check(latin1.decode(bytes).startsWith('X=\n')).isTrue();
    check(latin1.decode(bytes).endsWith('%_X+')).isTrue();
    check(() => bytes[0] = 0).throws<UnsupportedError>();
    final AiNativeAppearances created = source.createOpacityMasks(
      masks: [AiNativeOpacityMaskAttachment(artwork: owner, settings: changedMaskSettings, artworkBytes: bytes)],
      artwork: _printing(source),
    );
    final AiNativeOpacityMask mask = created.artworkFor(use: created.uses.first).opacityMasks.single;
    final AiNativeDrawing drawing = mask.artworkDrawing;
    check(mask.artworkBytes).deepEquals(bytes);
    check(drawing.paths).length.equals(3);
    check(drawing.paths.every((path) => path.isPrivate)).isTrue();
    check((drawing.groups.toList()..sort((a, b) => a.start.compareTo(b.start))).map((group) => group.opening.operator)).deepEquals(['q', 'u']);
    check(drawing.paths.first.paint.operator).equals('N');
    check(drawing.paths.skip(1).map((path) => path.paint.operator)).deepEquals(['b', 'b']);
    check(drawing.items.whereType<AiNativeInstruction>().where((command) => command.operator == 'As').map((command) => command.numbers!.single)).deepEquals([3.0, 3.0, 3.0]);
    final List<String> names = drawing.items.whereType<AiNativeContainer>().map((record) => record['AIArtName']?.stringBytes).whereType<List<int>>().map(utf8.decode).toList();
    check(names).contains('Masque (été)\n%_literal');
    check(names).contains('Groupe de masque');
    check(mask.settings.inverted).isTrue();
    check(mask.settings.linked).isFalse();
    check(source.artworkFor(use: source.uses.first).opacityMasks).isEmpty();
  });

  test('replaces typed mask vectors repeatedly and removes the mask without changing native identities', () {
    final AiNativeAppearances source = appearanceEditingModel(source: transparencySource());
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    AiNativeAppearances model = source.createOpacityMasks(
      masks: [
        AiNativeOpacityMaskAttachment(
          artwork: owner,
          settings: changedMaskSettings,
          artworkBytes: AiNativeOpacityMask.encodeVectorArtwork(records: source.structure.drawing.records, elements: _tree()),
        ),
      ],
      artwork: _printing(source),
    );
    for (final List<AiNativeAppearanceElementDefinition> elements in [
      <AiNativeAppearanceElementDefinition>[],
      [AiNativeAppearancePathDefinition(definition: _path(gray: .9))],
    ]) {
      final Uint8List bytes = AiNativeOpacityMask.encodeVectorArtwork(records: model.structure.drawing.records, elements: elements);
      model = model.updateOpacityMasks(
        changes: [
          AiNativeOpacityMaskChange(
            mask: model.artworkFor(use: model.uses.first).opacityMasks.single,
            artworkBytes: bytes,
          ),
        ],
        artwork: _printing(model),
      );
      check(model.artworkFor(use: model.uses.first).opacityMasks.single.artworkBytes).deepEquals(bytes);
      check(model.artworkFor(use: model.uses.first).opacityMasks.single.artworkDrawing.paths).length.equals(elements.length);
      check(model.structure.identifiers.map((identity) => identity.bytes)).deepEquals(source.structure.identifiers.map((identity) => identity.bytes));
    }
    model = model.deleteOpacityMasks(
      masks: model.artworkFor(use: model.uses.first).opacityMasks,
      artwork: _printing(model),
    );
    check(model.artworkFor(use: model.uses.first).opacityMasks).isEmpty();
  });

  test('can supply public mask syntax without corrupting literal private-prefix text', () {
    final AiNativeRecords records = appearanceEditingModel(source: transparencySource()).structure.drawing.records;
    final Uint8List bytes = AiNativeOpacityMask.encodeVectorArtwork(records: records, elements: _tree(), private: false);
    final String text = latin1.decode(bytes);
    check(text.startsWith('X=\n')).isTrue();
    check(text.endsWith('\nX+')).isTrue();
    check(text.split('\n').any((line) => line.startsWith('%_'))).isFalse();
    final List<AiToken> tokens = AiPostScript.tokenize(bytes);
    check(tokens.first.lexeme).equals('X=');
    check(tokens.last.lexeme).equals('X+');
    check(tokens.where((token) => token.kind == .string).map((token) => latin1.decode(aiStringBytes(token)))).contains(latin1.decode(utf8.encode('Masque (été)\n%_literal')));
  });

  test('rejects named style and identity dependencies instead of dropping them', () {
    final AiNativeRecords records = appearanceEditingModel(source: transparencySource()).structure.drawing.records;
    for (final AiNativeAppearanceElementDefinition element in [
      AiNativeAppearancePathDefinition(definition: _path(identifier: ascii.encode('mask-path'))),
      AiNativeAppearanceGroupDefinition(
        styleNameBytes: ascii.encode('Shared'),
        children: [AiNativeAppearancePathDefinition(definition: _path())],
      ),
      AiNativeAppearanceGroupDefinition(
        identifierBytes: ascii.encode('mask-group'),
        children: [AiNativeAppearancePathDefinition(definition: _path())],
      ),
      AiNativeAppearanceGroupDefinition(
        clip: AiNativeAppearanceClipDefinition(segments: _path().artwork.segments, identifierBytes: ascii.encode('mask-clip')),
        children: [AiNativeAppearancePathDefinition(definition: _path())],
      ),
    ]) {
      check(() => AiNativeOpacityMask.encodeVectorArtwork(records: records, elements: [element])).throws<UnsupportedError>();
    }
  });

  test('binds mask carriers exactly and rejects foreign or stale mask handles', () {
    final AiNativeAppearances source = appearanceEditingModel(source: transparencySource(grouped: true));
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final Uint8List bytes = AiNativeOpacityMask.encodeVectorArtwork(records: source.structure.drawing.records, elements: _tree());
    final AiNativeAppearances created = source.createOpacityMasks(
      masks: [
        for (final AiNativeItem target in [owner.authoring, owner.group!.paths.first, owner.group!.children.whereType<AiNativeGroup>().single])
          AiNativeOpacityMaskAttachment(artwork: owner, target: target, settings: changedMaskSettings, artworkBytes: bytes),
      ],
      artwork: _printing(source),
    );
    final AiNativeAppearanceArtwork after = created.artworkFor(use: created.uses.first);
    check(after.opacityMasks.map((mask) => after.authoringForMask(mask: mask)).toSet())
        .deepEquals({after.authoring, after.group!.paths.first, after.group!.children.whereType<AiNativeGroup>().single});
    for (final AiNativeOpacityMask mask in after.opacityMasks) {
      final AiNativeItem carrier = after.authoringForMask(mask: mask);
      check(AiNativeObjects.decode(drawing: created.structure.drawing).forSource(carrier).dictionary!['AI9_Mask']!.container).identicalTo(mask.record);
      check(() => owner.authoringForMask(mask: mask)).throws<ArgumentError>();
      check(() => created.artworkFor(use: created.uses.last).authoringForMask(mask: mask)).throws<ArgumentError>();
    }
    final AiNativeAppearances changed = created.updateOpacityMasks(
      changes: [AiNativeOpacityMaskChange(mask: after.opacityMasks.first, settings: const AiNativeOpacityMaskSettings(linked: true, disabled: false, clipping: true, inverted: false))],
      artwork: _printing(created),
    );
    check(() => changed.artworkFor(use: changed.uses.first).authoringForMask(mask: after.opacityMasks.first)).throws<ArgumentError>();
  });

  test('bounds mask vector output before exposing a payload', () {
    final String source = transparencySource();
    final AiNativeRecords records = appearanceEditingModel(
      source: source,
      limits: AiNativeLimits(maxDecodedBytes: source.length),
    ).structure.drawing.records;
    check(
      () => AiNativeOpacityMask.encodeVectorArtwork(
        records: records,
        elements: [for (int index = 0; index < source.length; index++) AiNativeAppearancePathDefinition(definition: _path())],
      ),
    ).throws<AiLimitException>();
  });
}
