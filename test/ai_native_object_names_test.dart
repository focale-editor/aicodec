import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementPath;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectMetadataSource, objectSource;
import 'ai_native_shape_creation_test.dart' show authoredRectangle, authoredShape;

/// Checks literal names without using them as native ownership identities.
List<List<String>> _names(AiNativeDrawing drawing) => [
  for (final AiNativeObject object in AiNativeObjects.decode(drawing: drawing).objects) object.names.map((entry) => utf8.decode(entry.stringBytes!)).toList(),
];

/// Registers bounded immutable naming transactions for final validation.
void main() {
  test('renames a path and its group while retaining identity and raw contours', () {
    final AiNativeDrawing source = groupCreationDrawing(objectMetadataSource);
    final List<int> name = utf8.encode('Tracé (renommé)');
    final AiNativeDrawing result = source.renameObjects(names: {source.paths.first: name, source.groups.single: utf8.encode('Groupe')});
    name[0] = 0;
    check(_names(result).take(2)).deepEquals([
      ['Groupe'],
      ['Tracé (renommé)'],
    ]);
    for (int index = 0; index < source.paths.length; index++) {
      check(result.records.program.bytes.sublist(result.paths[index].start, result.paths[index].end))
          .deepEquals(source.records.program.bytes.sublist(source.paths[index].start, source.paths[index].end));
      expect(AiNativeObjects.decode(drawing: result).forSource(result.paths[index]).identifier?.bytes, AiNativeObjects.decode(drawing: source).forSource(source.paths[index]).identifier?.bytes);
    }
    check(latin1.decode(source.records.program.bytes)).equals(objectMetadataSource);
  });

  test('updates both literal aliases while retaining their declared scalar types', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('${movementPath(10)}\n${objectDictionary(name: 'First', extra: '(First) /UnicodeString (Object name) ,')}'));
    final AiNativeDrawing result = source.renameObjects(names: {source.paths.single: utf8.encode('Étoile')});
    check(_names(result).single).deepEquals(['Étoile', 'Étoile']);
    check(AiNativeObjects.decode(drawing: result).objects.single.names.map((entry) => entry.type)).deepEquals(['String', 'UnicodeString']);
  });

  test('adds names to missing metadata and retains named live-shape parameters', () {
    final AiNativeDrawing empty = groupCreationDrawing(objectSource('', setup: ''));
    final AiNativeDrawing source = empty.createLiveShape(definition: authoredShape(metadata: false), parameters: authoredRectangle());
    final AiNativeDrawing named = source.renameObjects(names: {source.paths.single: utf8.encode('Rectangle')});
    check(_names(named).single).deepEquals(['Rectangle']);
    check(AiNativeShapeParameters.fromShape(shape: named.liveShapes.single).numbers).deepEquals(authoredRectangle().numbers);
    check(AiNativeObjects.decode(drawing: named).objects.single.identifier).isNull();
    final AiNativeDrawing ordinary = groupCreationDrawing(objectSource('u ${movementPath(10)} U', setup: ''));
    final AiNativeDrawing inserted = ordinary.renameObjects(names: {ordinary.paths.single: utf8.encode('Path'), ordinary.groups.single: utf8.encode('Group')});
    check(_names(inserted)).deepEquals([
      ['Group'],
      ['Path'],
    ]);
  });

  test('rejects foreign handles, invalid bytes and opaque selected metadata atomically', () {
    final AiNativeDrawing source = groupCreationDrawing(objectMetadataSource);
    final AiNativeDrawing foreign = groupCreationDrawing(objectMetadataSource);
    check(
      () => source.renameObjects(
        names: {
          foreign.paths.first: [65],
        },
      ),
    ).throws<ArgumentError>();
    check(
      () => source.renameObjects(
        names: {
          source.paths.first: [256],
        },
      ),
    ).throws<ArgumentError>();
    check(() => source.renameObjects(names: {})).throws<ArgumentError>();
    final AiNativeDrawing opaque = groupCreationDrawing(objectSource('${movementPath(10)} ${objectDictionary(extra: '(unknown) /String (FutureField) ,')}'));
    check(
      () => opaque.renameObjects(
        names: {
          opaque.paths.single: [65],
        },
      ),
    ).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(objectMetadataSource);
  });

  test('fills an empty name and inserts after a final field without a comma', () {
    for (final String metadata in [
      '%_/ArtDictionary : /String (AIArtName) , (0.5) /String (BBAccumRotation) ;',
      '%_/ArtDictionary : (0.5) /String (BBAccumRotation) ;',
    ]) {
      final AiNativeDrawing source = groupCreationDrawing(objectSource('${movementPath(10)}\n$metadata'));
      final AiNativeDrawing result = source.renameObjects(names: {source.paths.single: utf8.encode('Nommé')});
      check(_names(result).single).deepEquals(['Nommé']);
      check(AiNativeObjects.decode(drawing: result).forSource(result.paths.single).dictionary!['BBAccumRotation']!.text()).equals('0.5');
    }
  });
}
