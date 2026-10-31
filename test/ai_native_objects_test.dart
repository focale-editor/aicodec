import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath, movementState;

/// Encodes only the observed metadata fields, without appearance/private records.
String objectDictionary({String? identifier, String? name, String extra = '', bool private = true}) {
  final String value =
      '/ArtDictionary :\n'
      '${identifier == null ? '' : '/XMLUID : ($identifier) ; (AI10_ArtUID) ,\n'}'
      '${name == null ? '' : '($name) /String (AIArtName) ,\n'}'
      '$extra\n;';
  return private ? value.split('\n').map((line) => '%_$line').join('\n') : value;
}

/// Supplies distinct identities for paths and their containing ordinary group.
String get objectMetadataSource => objectSource(
  'u\n${movementPath(10)}\n${objectDictionary(identifier: 'path_a', name: 'First')}\n'
  '0.6 g\n${movementPath(20)}\n${objectDictionary(identifier: 'path_b', name: 'Second')}\nU\n'
  '${objectDictionary(identifier: 'group_a', name: 'Pair')}\n'
  '0.9 g\n${movementPath(30)}\n${objectDictionary(name: 'Anonymous', extra: '(0.5) /String (BBAccumRotation) ,\n')}',
);

/// Retains an opaque setup dictionary independently of selected ordinary objects.
String objectSource(String body, {String setup = '/Dictionary : (retained) /String (FutureSetup) , ;'}) =>
    '%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%%BoundingBox: 0 0 100 100\n%%EndComments\n%%BeginProlog\n%%EndProlog\n%%BeginSetup\n$setup\n%%EndSetup\n$movementState\n$body\n%%Trailer\n%%EOF\n';

/// Opens a complete native snapshot under optional parser ceilings.
AiNativeDrawing _drawing(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Selects source artwork by a unique coordinate instead of a mutable index.
AiNativePath _path(AiNativeDrawing drawing, int x) => drawing.paths.singleWhere((path) => path.geometry.first.numbers!.first == x);

/// Reads each path's identity, name and geometry from their retained source owners.
List<List<Object?>> _paths(AiNativeDrawing drawing) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  return [
    for (final AiNativePath path in drawing.paths)
      [path.geometry.first.numbers!.first, objects.forSource(path).identifier?.bytes, objects.forSource(path).names.map((entry) => entry.stringBytes).toList()],
  ];
}

/// Reads saved IDs in lexical order, including group owners and their descendants.
List<String?> _identities(AiNativeDrawing drawing) =>
    AiNativeObjects.decode(drawing: drawing).objects.map((object) => object.identifier == null ? null : latin1.decode(object.identifier!.bytes)).toList();

/// Checks metadata ownership, whole-object edits, identities and atomic rejection.
void main() {
  test('binds immutable direct dictionaries to exact path and group handles', () {
    final AiNativeDrawing drawing = _drawing(objectMetadataSource);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
    check(AiNativeObjects.decode(drawing: drawing)).identicalTo(objects);
    check(objects.objects).length.equals(4);
    check(objects.objects.every((object) => object.bindingIssue == null)).isTrue();
    check(_identities(drawing)).deepEquals(['group_a', 'path_a', 'path_b', null]);
    final AiNativeObject group = objects.forSource(drawing.groups.single);
    check(group.end).equals(group.dictionary!.end);
    check(group.start).equals(drawing.groups.single.start);
    check(group.names.single.stringBytes!).deepEquals(latin1.encode('Pair'));
    check(objects.objects.clear).throws<UnsupportedError>();
    check(group.names.clear).throws<UnsupportedError>();
    check(() => objects.forSource(_drawing(objectMetadataSource).paths.first)).throws<ArgumentError>();
  });

  test('duplicates identified paths with fresh IDs and exact remaining metadata', () {
    final AiNativeDrawing source = _drawing(objectMetadataSource);
    final List<int> identifier = latin1.encode('new_path');
    final Map<AiNativeItem, List<int>> replacements = {source.paths.first: identifier};
    final AiNativeDrawing copied = source.duplicatePaths(paths: [source.paths.first], identifiers: replacements);
    identifier[0] = 120;
    replacements.clear();
    check(_identities(copied)).deepEquals(['group_a', 'path_a', 'new_path', 'path_b', null]);
    check(_paths(copied)).deepEquals([
      _paths(source)[0],
      [
        10.0,
        latin1.encode('new_path'),
        [latin1.encode('First')],
      ],
      ..._paths(source).skip(1),
    ]);
    final AiNativeObject original = AiNativeObjects.decode(drawing: source).forSource(source.paths.first);
    check(copied.records.program.bytes.take(original.end).toList()).deepEquals(source.records.program.bytes.take(original.end).toList());
    check(latin1.decode(copied.records.program.bytes)).endsWith(latin1.decode(source.records.program.bytes.sublist(original.end)));
    check(latin1.decode(source.records.program.bytes)).equals(objectMetadataSource);
  });

  test('requires exactly owned fresh portable IDs without changing the source', () {
    final AiNativeDrawing source = _drawing(objectMetadataSource);
    final AiNativePath selected = source.paths.first;
    for (final Map<AiNativeItem, List<int>> identifiers in [
      <AiNativeItem, List<int>>{},
      {source.paths.last: latin1.encode('new')},
      {_drawing(objectMetadataSource).paths.first: latin1.encode('new')},
      {selected: latin1.encode('path_b')},
      {selected: latin1.encode('group_a')},
      {selected: latin1.encode('1 invalid')},
      {
        selected: [256],
      },
      {selected: latin1.encode('new'), source.paths.last: latin1.encode('extra')},
    ]) {
      check(() => source.duplicatePaths(paths: [selected], identifiers: identifiers)).throws<ArgumentError>();
    }
    check(latin1.decode(source.records.program.bytes)).equals(objectMetadataSource);
  });

  test('preserves external reference bytes while copying identity declarations', () {
    final AiNativeDrawing source = _drawing(objectSource('${movementPath(10)}\n${objectDictionary(identifier: 'path_a')}', setup: '/FutureRefs : (path_a) /String (Target) , ;'));
    final AiNativeDrawing result = source.duplicatePaths(paths: source.paths, identifiers: {source.paths.single: latin1.encode('copy_a')});
    check(_identities(result)).deepEquals(['path_a', 'copy_a']);
    check(latin1.decode(result.records.program.bytes)).contains('/FutureRefs : (path_a) /String (Target) , ;');
  });

  test('moves and reorders complete metadata across changed state repeatedly', () {
    final AiNativeDrawing source = _drawing(objectMetadataSource);
    final AiNativeDrawing reordered = source.reorderPaths(paths: [source.paths[1], source.paths[0]]);
    check(_paths(reordered)).deepEquals([_paths(source)[1], _paths(source)[0], _paths(source)[2]]);
    final AiNativeDrawing moved = reordered.movePathAfter(path: _path(reordered, 10), after: _path(reordered, 30), inheritParentFlags: true);
    check(_paths(moved)).deepEquals([_paths(source)[1], _paths(source)[2], _paths(source)[0]]);
    check(AiNativeObjects.decode(drawing: moved).forSource(moved.paths.last).node.parentIndex).isNull();
    final AiNativeDrawing restored = moved.movePathAfter(path: _path(moved, 10), after: _path(moved, 20), inheritParentFlags: true);
    check(_paths(restored)).deepEquals(_paths(reordered));
    check(_identities(restored)).deepEquals(['group_a', 'path_b', 'path_a', null]);
  });

  test('inserts after metadata and removes anonymous metadata with its object', () {
    final AiNativeDrawing source = _drawing(objectMetadataSource);
    final AiNativeDrawing inserted = source.insertPaths(
      insertions: [
        AiNativePathInsertion(
          after: source.paths.first,
          segments: [
            AiPathSegment(operator: 'm', coordinates: [12, 0]),
            AiPathSegment(operator: 'L', coordinates: [13, 1]),
          ],
          bounds: AiBoundingBox(left: 12, bottom: 0, right: 13, top: 1),
        ),
      ],
    );
    check(_identities(inserted)).deepEquals(['group_a', 'path_a', null, 'path_b', null]);
    check(AiNativeObjects.decode(drawing: inserted).forSource(inserted.paths[1]).dictionary).isNull();
    final AiNativeDrawing removed = inserted.removePaths(paths: [inserted.paths.last]);
    check(latin1.decode(removed.records.program.bytes).contains('Anonymous')).isFalse();
    check(latin1.decode(removed.records.program.bytes).contains('BBAccumRotation')).isFalse();
    check(_identities(removed)).deepEquals(['group_a', 'path_a', null, 'path_b']);
  });

  test('duplicates group metadata and every identified descendant atomically', () {
    final AiNativeDrawing source = _drawing(objectMetadataSource);
    final Map<AiNativeItem, List<int>> identifiers = {
      source.groups.single: latin1.encode('group_copy'),
      source.paths[0]: latin1.encode('path_a_copy'),
      source.paths[1]: latin1.encode('path_b_copy'),
    };
    check(() => source.duplicateGroups(groups: source.groups)).throws<ArgumentError>();
    final AiNativeDrawing result = source.duplicateGroups(groups: source.groups, identifiers: identifiers);
    check(_identities(result)).deepEquals(['group_a', 'path_a', 'path_b', 'group_copy', 'path_a_copy', 'path_b_copy', null]);
    check(result.groups.map((group) => group.paths.length)).deepEquals([2, 2]);
    check(AiNativeObjects.decode(drawing: result).forSource(result.groups.last).names.single.stringBytes!).deepEquals(latin1.encode('Pair'));
    identifiers[source.paths[1]] = latin1.encode('group_copy');
    check(() => source.duplicateGroups(groups: source.groups, identifiers: identifiers)).throws<ArgumentError>();
    check(latin1.decode(source.records.program.bytes)).equals(objectMetadataSource);
  });

  test('keeps group dictionaries through reordering and relocation', () {
    final AiNativeDrawing initial = _drawing(objectMetadataSource);
    final AiNativeDrawing source = initial.groupPaths(paths: [initial.paths.last]);
    final AiNativeGroup first = source.groups.first;
    final AiNativeGroup second = source.groups.last;
    final AiNativeDrawing reordered = source.reorderGroups(groups: [second, first]);
    check(_identities(reordered)).deepEquals([null, null, 'group_a', 'path_a', 'path_b']);
    final AiNativeDrawing moved = source.moveGroupAfter(group: first, after: second);
    check(_identities(moved)).deepEquals(_identities(reordered));
    check(_paths(moved)).deepEquals(_paths(reordered));
    final AiNativeDrawing removed = moved.removeGroups(groups: [moved.groups.first]);
    check(_identities(removed)).deepEquals(['group_a', 'path_a', 'path_b']);
    check(latin1.decode(removed.records.program.bytes).contains('Anonymous')).isFalse();
  });

  test('groups identified children and dissolves empty group dictionaries only', () {
    final AiNativeDrawing source = _drawing(objectSource('${movementPath(10)}\n${objectDictionary(identifier: 'first')}\n${movementPath(20)}\n${objectDictionary(identifier: 'second')}'));
    final AiNativeDrawing grouped = source.groupPaths(paths: source.paths);
    check(_identities(grouped)).deepEquals([null, 'first', 'second']);
    final AiNativeDrawing dissolved = grouped.ungroup(groups: grouped.groups);
    check(_paths(dissolved)).deepEquals(_paths(source));
    final AiNativeDrawing empty = _drawing(objectSource('u ${movementPath(10)}\n${objectDictionary(identifier: 'child')}\nU\n${objectDictionary()}'));
    check(_identities(empty.ungroup(groups: empty.groups))).deepEquals(['child']);
    for (final String metadata in [objectDictionary(name: 'Named'), objectDictionary(identifier: 'identified'), objectDictionary(extra: '(1) /String (BBAccumRotation) ,')]) {
      final AiNativeDrawing named = _drawing(objectSource('u ${movementPath(10)} U\n$metadata'));
      check(() => named.ungroup(groups: named.groups)).throws<UnsupportedError>();
    }
  });

  test('rejects unresolved identified deletion and missing copied child identities', () {
    final AiNativeDrawing source = _drawing(objectMetadataSource);
    check(() => source.removePaths(paths: [source.paths.first])).throws<UnsupportedError>();
    check(() => source.removeGroups(groups: source.groups)).throws<UnsupportedError>();
    final AiNativeDrawing nested = _drawing(objectSource(movementLayer('Layer', '${movementPath(10)}\n${objectDictionary(identifier: 'child')}')));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: nested);
    check(() => layers.duplicate(layers: layers.layers, identifiers: {layers.layers.single: latin1.encode('LayerCopy')})).throws<ArgumentError>();
    check(() => layers.remove(layers: layers.layers)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(objectMetadataSource);
  });

  test('moves identified artwork into layers while retaining both kinds of identity', () {
    final AiNativeDrawing source = _drawing(
      objectSource('${movementLayer('From', 'u ${movementPath(10)}\n${objectDictionary(identifier: 'path')}\nU\n${objectDictionary(identifier: 'group')}')}\n${movementLayer('To', '')}'),
    );
    final AiNativeDrawing moved = source.moveGroupToLayer(group: source.groups.single, layer: source.records.program.layers.last, inheritParentFlags: true);
    check(_identities(moved)).deepEquals(['group', 'path']);
    check(AiNativeLayers.decode(drawing: moved).layers.map((layer) => latin1.decode(layer.identifier!.bytes))).deepEquals(['From', 'To']);
    final AiNativeDrawing pathMoved = moved.movePathToLayer(path: moved.paths.single, layer: moved.records.program.layers.first, inheritParentFlags: true);
    check(_identities(pathMoved)).deepEquals(['path', 'group']);
    check(pathMoved.groups.single.paths).isEmpty();
  });

  test('reports opaque dictionaries and rejects malformed metadata without altering bytes', () {
    for (final String extra in [
      '(future) /String (SVG_ShapeType) ,',
      '(future) /String (UnknownReference) ,',
      '1 /Integer (AIArtName) ,',
      '(NaN) /String (BBAccumRotation) ,',
    ]) {
      final String input = objectSource('${movementPath(10)}\n${objectDictionary(extra: extra)}');
      final AiNativeDrawing source = _drawing(input);
      check(AiNativeObjects.decode(drawing: source).objects.single.bindingIssue).isNotNull();
      check(() => source.duplicatePaths(paths: source.paths)).throws<UnsupportedError>();
      check(() => source.removePaths(paths: source.paths)).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(input);
    }
    check(() => _drawing(objectSource('${movementPath(10)}\n${objectDictionary(extra: '(first) /String (AIArtName) , (second) /String (AIArtName) ,')}'))).throws<FormatException>();
    final AiNativeDrawing malformed = _drawing(objectSource('${movementPath(10)}\n/ArtDictionary : (bad) /String (AI10_ArtUID) , ;'));
    check(() => AiNativeObjects.decode(drawing: malformed)).throws<FormatException>();
  });

  test('refuses intervening metadata, repeated dictionaries and version boundaries', () {
    for (final String postfix in [
      '0 A\n${objectDictionary()}',
      '${objectDictionary()}\n${objectDictionary()}',
      '%AI8_FutureOwner: 1\n${objectDictionary()}',
      '%AI17_Begin_Content_if_version_gt:24 4\n${objectDictionary()}\n%AI17_End_Versioned_Content',
    ]) {
      final AiNativeDrawing source = _drawing(objectSource('${movementPath(10)}\n$postfix'));
      check(() => source.duplicatePaths(paths: source.paths)).throws<UnsupportedError>();
    }
  });

  test('qualifies bare metadata without accepting unrelated appearance prefixes', () {
    final String dictionary = objectDictionary(private: false);
    final AiNativeDrawing source = _drawing(objectSource('${movementPath(10)}\n$dictionary\n${movementPath(20)}\n$dictionary'));
    final AiNativeDrawing result = source.duplicatePaths(paths: [source.paths.last]);
    check(result.paths).length.equals(3);
    check(result.removePaths(paths: [result.paths.first]).paths).length.equals(2);
    final AiNativeDrawing dependent = _drawing(objectSource('${movementPath(10)}\n$dictionary\n0 XW ${movementPath(20)}'));
    check(() => dependent.duplicatePaths(paths: [dependent.paths.last])).throws<UnsupportedError>();
  });

  test('reports qualified metadata without qualifying private or opaque artwork', () {
    final String input = objectSource('${movementPath(10)}\n${objectDictionary(identifier: 'known')}\n${movementPath(20)}\n${objectDictionary(extra: '(unknown) /String (SVG_ShapeType) ,')}');
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(latin1.encode(input))).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final List<AiNativeCapability> metadata = report.findings.where((finding) => finding.selector.startsWith('object-metadata:')).toList();
    check(metadata.map((finding) => finding.support)).deepEquals([AiNativeDataSupport.typed, AiNativeDataSupport.preserved]);
    check(metadata.every((finding) => !finding.editable)).isTrue();
  });

  test('bounds expanded IDs, total copy output and source token counts', () {
    final String input = objectSource('${movementPath(10)}\n${objectDictionary(identifier: 'original')}');
    final AiNativeDrawing source = _drawing(input, limits: AiNativeLimits(maxDecodedBytes: input.length + 30));
    check(() => source.duplicatePaths(paths: source.paths, identifiers: {source.paths.single: latin1.encode('copy')})).throws<FormatException>();
    check(() => source.duplicatePaths(paths: source.paths, identifiers: {source.paths.single: latin1.encode('x' * 200)})).throws<AiLimitException>();
    final AiNativeDrawing limited = _drawing(input, limits: AiNativeLimits(maxTokens: AiPostScript.tokenize(latin1.encode(input.replaceAll('%_', '  '))).length + 1));
    check(() => limited.duplicatePaths(paths: limited.paths, identifiers: {limited.paths.single: latin1.encode('copy')})).throws<AiLimitException>();
    check(latin1.decode(source.records.program.bytes)).equals(input);
  });
}
