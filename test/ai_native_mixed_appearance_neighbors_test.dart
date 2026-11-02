import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_removal_test.dart' show appearanceRemovalSource;
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

  test('does not admit a private contour as an ordinary mixed owner', () {
    final AiNativeLayers source = _source();
    final AiNativePath private = source.drawing.paths.firstWhere((path) => path.isPrivate);
    check(() => source.moveArtwork(artwork: private, parent: source.layers.last, inheritParentFlags: true)).throws<UnsupportedError>();
    check(() => source.removeArtwork(artwork: [private])).throws<UnsupportedError>();
  });
}
