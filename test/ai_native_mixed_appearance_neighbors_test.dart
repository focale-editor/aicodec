import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceAuthoring;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_removal_test.dart' show appearanceRemovalSource;
import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Builds a complete pair followed by a uniquely identified inheriting contour.
AiNativeLayers _source() => AiNativeLayers.decode(
  drawing: appearanceEditingModel(
    source: appearanceRemovalSource(
      tail:
          '''
200 0 m 210 0 L 210 10 L f
%_/ArtDictionary : /XMLUID : (neighbor) ; (AI10_ArtUID) , ;
${movementLayer('Destination', '')}
''',
    ).replaceFirst('%AI5_NumLayers: 1', '%AI5_NumLayers: 2'),
  ).structure.drawing,
);

/// Locates the original editable path through its immutable native identity.
AiNativePath _neighbor(AiNativeLayers model) =>
    model.drawing.paths.singleWhere((path) => latin1.decode(AiNativeObjects.decode(drawing: model.drawing).forSource(path).identifier?.bytes ?? []) == 'neighbor');

/// Captures complete private authoring, metadata and public printing without decoding it.
List<int> _pair(AiNativeLayers model) {
  final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: model.structure);
  final AiNativeAppearanceArtwork owner = appearances.artworkFor(use: appearances.uses.single);
  return model.drawing.records.program.bytes.sublist(owner.start, owner.end);
}

/// Selects the ordinary parent without confusing it with the printing group.
AiNativeGroup _containerGroup(AiNativeLayers model) {
  final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: model.structure);
  final AiNativeAppearanceArtwork owner = appearances.artworkFor(use: appearances.uses.single);
  return model.drawing.groups.singleWhere((group) => group.start < owner.start && group.end > owner.end);
}

/// Verifies native lifecycle after a qualified complete appearance boundary.
void main() {
  test('moves an inheriting neighbor while retaining the pair and both paint streams', () {
    final AiNativeLayers source = _source();
    final AiNativeLayers moved = source.moveArtwork(artwork: _neighbor(source), parent: source.layers.last, inheritParentFlags: true);
    final AiNativePath path = _neighbor(moved);
    check(moved.structure.parentOf(moved.structure.nodeFor(path))!.source).identicalTo(moved.layers.last.source);
    check(_pair(moved)).deepEquals(_pair(source));
    final int index = moved.drawing.paths.indexOf(path);
    final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: moved.structure);
    final AiNativeDrawing expanded = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(
        program: AiNativeEditor.apply(
          program: moved.drawing.records.program,
          edits: [
            AiSourceEdit(start: appearances.uses.single.instruction.end, end: appearances.uses.single.instruction.end, bytes: ascii.encode('\n%_0.25 g\n')),
          ],
        ),
      ),
    );
    check(artworkStates(expanded, native: true)[index]['fill']).isNotNull().deepEquals(['g', .25]);
    check(artworkStates(moved.drawing, native: false).last['fill']).isNotNull().deepEquals(['k', 0.0, 0.0, 0.0, 1.0]);
    final AiNativeLayers removed = moved.removeArtwork(artwork: [path]);
    check(_pair(removed)).deepEquals(_pair(source));
    check(removed.structure.identifiers.any((value) => latin1.decode(value.bytes) == 'neighbor')).isFalse();
  });

  test('removes an identified neighbor without invalidating retained appearance references', () {
    final AiNativeLayers source = _source();
    final AiNativeLayers removed = source.removeArtwork(artwork: [_neighbor(source)]);
    check(_pair(removed)).deepEquals(_pair(source));
    check(removed.drawing.paths.length).equals(source.drawing.paths.length - 1);
    check(_neighbor(source).isPrivate).isFalse();
  });

  test('keeps anonymous neighbor deletion local but checks identified references', () {
    final String text = latin1.decode(_source().drawing.records.program.bytes).replaceFirst('%%PageTrailer', '/Opaque : (neighbor) /String (ForeignReference) , ;\n%%PageTrailer');
    final AiNativeLayers identified = AiNativeLayers.decode(drawing: appearanceEditingModel(source: text).structure.drawing);
    check(() => identified.removeArtwork(artwork: [_neighbor(identified)])).throws<UnsupportedError>();
    final AiNativeLayers anonymous = AiNativeLayers.decode(
      drawing: appearanceEditingModel(source: text.replaceFirst('%_/ArtDictionary : /XMLUID : (neighbor) ; (AI10_ArtUID) , ;', '')).structure.drawing,
    );
    final AiNativePath path = anonymous.drawing.paths.singleWhere((path) => path.geometry.first.numbers!.first == 200);
    final AiNativeLayers removed = anonymous.removeArtwork(artwork: [path]);
    check(_pair(removed)).deepEquals(_pair(anonymous));
    check(latin1.decode(removed.drawing.records.program.bytes)).contains('/Opaque : (neighbor) /String (ForeignReference) , ;');
  });

  for (final bool group in [false, true]) {
    for (final bool clipped in [false, true]) {
      test('reorders, moves and removes a complete ${group ? 'group' : 'layer'} with ${clipped ? 'clipped' : 'ordinary'} appearance', () {
        final String pair = clipped ? appearanceArtworkPair().replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', clippingAppearanceAuthoring('nested')) : appearanceArtworkPair(metadata: true);
        final String contained = group ? 'u\n$pair\nU' : movementLayer('Container', pair);
        final String text = appearanceRemovalSource(
          pair: contained,
          tail: movementLayer('Destination', '200 0 m 210 0 L 210 10 L f\n%_/ArtDictionary : /XMLUID : (neighbor) ; (AI10_ArtUID) , ;'),
        ).replaceFirst('%AI5_NumLayers: 1', '%AI5_NumLayers: ${group ? 2 : 3}');
        final AiNativeLayers source = AiNativeLayers.decode(drawing: appearanceEditingModel(source: text).structure.drawing);
        final AiNativeItem owner = group ? _containerGroup(source) : source.layers[1];
        final AiNativeLayers ordered = source.reorderArtwork(artwork: [source.layers.last, owner]);
        check(_pair(ordered)).deepEquals(_pair(source));
        final AiNativeItem orderedOwner = group ? _containerGroup(ordered) : ordered.layers.last;
        final AiNativeLayers moved = ordered.moveArtwork(artwork: orderedOwner, parent: ordered.layers[1], inheritParentFlags: true);
        check(_pair(moved)).deepEquals(_pair(source));
        final AiNativeItem movedOwner = group ? _containerGroup(moved) : moved.layers.last;
        final AiNativeLayers removed = moved.removeArtwork(artwork: [movedOwner]);
        check(AiNativeAppearances.decode(structure: removed.structure).uses).isEmpty();
        check(removed.structure.identifiers.any((value) => latin1.decode(value.bytes) == 'author')).isFalse();
        check(removed.drawing.paths).length.equals(1);
        check(_neighbor(removed)).identicalTo(removed.drawing.paths.single);
        check(artworkStates(removed.drawing, native: true).single['fill']!).deepEquals(['g', .25]);
        check(artworkStates(removed.drawing, native: false).single['fill']!).deepEquals(['k', 0.0, 0.0, 0.0, 1.0]);
        check(_pair(source)).isNotEmpty();
      });
    }
  }

  test('changes artboards around complete appearance owners without rewriting their bytes', () {
    final AiNativeLayers source = _source();
    AiNativeArtboards boards = AiNativeArtboards.decode(records: source.drawing.records);
    boards = boards.create(definition: newArtboard(), index: 0, lastArtboardId: boards.lastArtboardId == null ? null : boards.lastArtboardId! + 1, cropBounds: null);
    boards = boards.resize(artboard: boards.artboards.last, bounds: AiBoundingBox(left: -20, bottom: -130, right: 180, top: 10), cropBounds: null);
    boards = boards.reorder(artboards: boards.artboards.reversed.toList(), cropBounds: null);
    boards = boards.remove(artboards: [boards.artboards.last], activeArtboard: null, cropBounds: null);
    final AiNativeLayers result = AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: boards.records));
    check(_pair(result)).deepEquals(_pair(source));
    check(boards.artboards).length.equals(1);
    check(boards.artboards.single.bounds.left).equals(-20);
  });

  test('does not admit a private contour as an ordinary mixed owner', () {
    final AiNativeLayers source = _source();
    final AiNativePath private = source.drawing.paths.firstWhere((path) => path.isPrivate);
    check(() => source.moveArtwork(artwork: private, parent: source.layers.last, inheritParentFlags: true)).throws<UnsupportedError>();
    check(() => source.removeArtwork(artwork: [private])).throws<UnsupportedError>();
    final AiNativeAppearances appearances = AiNativeAppearances.decode(structure: source.structure);
    final AiNativeGroup printing = appearances.artworkFor(use: appearances.uses.single).printingGroup;
    check(() => source.removeArtwork(artwork: [printing])).throws<UnsupportedError>();
    check(() => source.reorderArtwork(artwork: [source.layers.last, printing])).throws<UnsupportedError>();
  });
}
