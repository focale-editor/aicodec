import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkSource;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel, appearanceEditingSource;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupsSource;

/// A changed contour with a curve and a different number of authoring anchors.
List<AiPathSegment> _geometry() => [
  AiPathSegment(operator: 'm', coordinates: [2, 3]),
  AiPathSegment(operator: 'C', coordinates: [4, 5, 12, 5, 15, 8]),
  AiPathSegment(operator: 'L', coordinates: [18, 20]),
  AiPathSegment(operator: 'L', coordinates: [2, 20]),
];

/// Independent supplied printing retaining the original outgoing CMYK fill.
AiNativeAppearanceReplacement _printing(AiNativeAppearanceArtwork owner, {bool counted = false}) => AiNativeAppearanceReplacement(
  artwork: owner,
  bytes: latin1.encode('u\n0 0 0 1 k\n${counted ? '4 As\n' : ''}2 3 m 4 5 12 5 15 8 C 18 20 L 2 20 L 2 3 L f\nU'),
  bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140),
);

/// Reads exact intervals for source preservation assertions.
List<int> _bytes(AiNativeAppearances model, AiNativeItem item) => model.structure.drawing.records.program.bytes.sublist(item.start, item.end);

/// Deferred geometry, ownership and synchronized printing regression cases.
void main() {
  test('changes a private contour and its count while preserving identity metadata and neighbors', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource(counted: true, metadata: true));
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativeAppearanceArtwork neighbor = source.artworkFor(use: source.uses.last);
    final AiNativeAppearanceReplacement printing = _printing(owner, counted: true);
    final AiNativeAppearances result = source.editArtworkPaths(
      edits: [AiNativePathEdit(path: owner.path!, segments: _geometry())],
      artwork: [printing],
    );
    final AiNativeAppearanceArtwork changed = result.artworkFor(use: result.uses.first);
    check(changed.path!.paint.operator).equals('n');
    check(changed.path!.isPrivate).isTrue();
    check(changed.path!.geometry).length.equals(5);
    check(changed.path!.geometry.first.numbers).isNotNull().deepEquals([2.0, 3.0]);
    check(changed.path!.geometry.last.numbers).isNotNull().deepEquals([2.0, 3.0]);
    check(_bytes(result, changed.dictionary!)).deepEquals(_bytes(source, owner.dictionary!));
    check(_bytes(result, changed.printingGroup)).deepEquals(printing.bytes);
    final AiNativeAppearanceArtwork unchanged = result.artworkFor(use: result.uses.last);
    check(result.structure.drawing.records.program.bytes.sublist(unchanged.start, unchanged.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(neighbor.start, neighbor.end));
    check(_bytes(result, result.styles.single.resource.definition.source as AiNativeContainer)).deepEquals(_bytes(source, source.styles.single.resource.definition.source as AiNativeContainer));
    check(owner.path!.geometry.first.numbers).isNotNull().deepEquals([0.0, 0.0]);
  });

  test('edits nested and compound children with one printing replacement and explicit frames', () {
    for (final bool compound in [false, true]) {
      for (final bool counted in [false, true]) {
        final AiNativeAppearances source = appearanceEditingModel(
          source: appearanceGroupsSource(compound: compound, counted: counted),
        );
        final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
        final List<AiNativePath> paths = owner.group!.paths.toList();
        final AiNativeAppearances result = source.editArtworkPaths(
          edits: [for (final AiNativePath path in paths) AiNativePathEdit(path: path, segments: _geometry())],
          artwork: [_printing(owner)],
          frameAngles: {owner.group!: 0.7, paths.first: 1.1},
        );
        final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
        check(after.group!.compound).equals(compound);
        check(after.groupContours.map((contour) => contour.pointCount?.numbers?.single)).deepEquals([if (counted) 4.0 else null, if (counted) 4.0 else null]);
        check(after.group!.paths.every((path) => path.geometry.length == (counted ? 5 : 4) && path.isPrivate)).isTrue();
        check(after.dictionary!['BBAccumRotation']!.text()).equals('0.700000');
        final AiNativeObject child = AiNativeObjects.decode(drawing: result.structure.drawing).forSource(after.group!.paths.first);
        check(child.dictionary!['BBAccumRotation']!.text()).equals('1.100000');
        check(child.dictionary!['AIArtName']!.text()).equals('First contour');
      }
    }
  });

  test('retains clipping and compound mask roles with their correct closure counts', () {
    for (final String variant in ['open', 'closed', 'compound', 'nested', 'leaves']) {
      final AiNativeAppearances source = appearanceEditingModel(source: clippingAppearanceSource(variant: variant));
      final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
      final AiNativeAppearances result = source.editArtworkPaths(
        edits: [for (final AiNativePathTopology contour in owner.groupContours) AiNativePathEdit(path: contour.path, segments: _geometry())],
        artwork: [_printing(owner)],
      );
      final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
      check(after.groupContours.map((contour) => contour.mask)).deepEquals(owner.groupContours.map((contour) => contour.mask));
      check(after.groupContours.every((contour) => contour.pointCount!.numbers!.single == 4)).isTrue();
      check(after.groupContours.map((contour) => contour.path.paint.operator)).deepEquals(owner.groupContours.map((contour) => contour.path.paint.operator));
      check(after.groupContours.map((contour) => contour.groups.map((group) => group.opening.operator).toList()))
          .deepEquals(owner.groupContours.map((contour) => contour.groups.map((group) => group.opening.operator).toList()));
    }
  });

  test('requires exact complete owner coverage and rejects printing or foreign geometry atomically', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource());
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativeAppearanceArtwork other = source.artworkFor(use: source.uses.last);
    final List<int> original = source.structure.drawing.records.program.bytes.toList();
    final AiNativePathEdit edit = AiNativePathEdit(path: owner.path!, segments: _geometry());
    check(() => source.editArtworkPaths(edits: [edit], artwork: [])).throws<ArgumentError>();
    check(() => source.editArtworkPaths(edits: [edit], artwork: [_printing(other)])).throws<ArgumentError>();
    check(() => source.editArtworkPaths(edits: [edit], artwork: [_printing(owner), _printing(other)])).throws<ArgumentError>();
    check(() => source.editArtworkPaths(edits: [edit, edit], artwork: [_printing(owner)])).throws<ArgumentError>();
    check(
      () => source.editArtworkPaths(
        edits: [AiNativePathEdit(path: owner.printingGroup.paths.single, segments: _geometry())],
        artwork: [_printing(owner)],
      ),
    ).throws<ArgumentError>();
    check(
      () => source.editArtworkPaths(
        edits: [AiNativePathEdit(path: owner.path!, segments: _geometry(), mask: .closed)],
        artwork: [_printing(owner)],
      ),
    ).throws<ArgumentError>();
    check(() => source.editArtworkPaths(edits: [edit], artwork: [_printing(owner)], frameAngles: {other.path!: 0.5})).throws<ArgumentError>();
    final AiNativeAppearances fresh = appearanceEditingModel(source: latin1.decode(original));
    check(() => fresh.editArtworkPaths(edits: [edit], artwork: [_printing(owner)])).throws<ArgumentError>();
    check(source.structure.drawing.records.program.bytes).deepEquals(original);
  });

  test('rejects live-shape contour changes without their parameter transaction', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceEditingSource());
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    check(owner.liveShape).isNotNull();
    check(
      () => source.editArtworkPaths(
        edits: [AiNativePathEdit(path: owner.path!, segments: _geometry())],
        artwork: [_printing(owner)],
      ),
    ).throws<UnsupportedError>();
  });
  test('bounds newly supplied private geometry before publishing a replacement', () {
    final String text = appearanceArtworkSource();
    final AiNativeAppearances source = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length + 512),
    );
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final List<AiPathSegment> segments = [
      AiPathSegment(operator: 'm', coordinates: [0, 0]),
      for (int index = 0; index < text.length; index++) AiPathSegment(operator: 'L', coordinates: [index.toDouble(), 1]),
    ];
    check(
      () => source.editArtworkPaths(
        edits: [AiNativePathEdit(path: owner.path!, segments: segments)],
        artwork: [_printing(owner)],
      ),
    ).throws<AiLimitException>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });
}
