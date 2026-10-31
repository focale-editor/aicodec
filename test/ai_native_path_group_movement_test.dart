import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath;
import 'ai_native_direct_shape_test.dart' show directShapeSource;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_subtree_movement_test.dart' show subtreeMovementSource;
import 'ai_native_subtree_reordering_test.dart' show subtreeReorderingFlags, subtreeReorderingGroups;

/// Opens exact immutable owners under caller-controlled byte/token limits.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Supplies identified counted paths, changed paint and a populated/empty parent.
String pathGroupSource({bool layers = false}) {
  final String first = '0 0.2 0 0 0 Xy u\n${movementPath(10)}\n${objectDictionary(identifier: 'path_a')}\n0.6 g 4 w ${movementPath(11)}\nU\n${objectDictionary(identifier: 'source')}';
  final String second = '0.9 g 0.8 G 6 w 0 0.8 0 0 0 Xy\nu\n${movementPath(20)}\nU\n${objectDictionary(identifier: 'destination')}\nu U\n${objectDictionary(identifier: 'empty')}\n${movementPath(40)}';
  return objectSource(
        layers ? '${movementLayer('From', first)}\n${movementLayer('To', second, hidden: true)}' : '$first\n$second',
        setup: '',
      )
      .replaceFirst('%%EndComments', '%AI3_TemplateBox: 50 -50 50 -50\n%AI5_ArtSize: 100 100\n${layers ? '%AI5_NumLayers: 2\n%AI5_OpenViewLayers: 3\n' : ''}%%EndComments')
      .replaceAll(' 0 m', ' -10 m')
      .replaceAll(' 1 L', ' -20 L');
}

/// Makes following geometry consume assignments retained from the moved count.
String countedPathGroupSource() =>
    pathGroupSource().replaceFirst('2 As 10 -10 m', '2 As 0.25 g\n%_1 D\n10 -10 m').replaceFirst('0.6 g 4 w', '4 w').replaceFirst('2 As 11 -10 m 12 -20 L S', '3 As 11 -10 m 21 -20 L 11 -20 L F');

/// Establishes different explicit native/printing inputs for the ordinary children.
String mixedPathGroupSource({bool layers = false}) {
  String text = subtreeMovementSource(layers: layers);
  for (int index = 0; index < 3; index++) {
    text = text.replaceFirst(
      '${70 + index} 0 m ${80 + index} 1 L f',
      '${0.2 + index * 0.1} g\n%_${0.6 + index * 0.1} g\n${70 + index} -20 m ${80 + index} -30 L ${70 + index} -30 L f',
    );
  }
  return text;
}

/// Selects an ordinary source by its uniquely authored first horizontal coordinate.
AiNativePath pathGroupPath(AiNativeDrawing drawing, int x) => drawing.paths.singleWhere((path) => path.geometry.first.numbers!.first == x);

/// Finds a directly identified ordinary parent after reparsing a changed source.
AiNativeGroup pathGroupParent(AiNativeDrawing drawing, String name) => subtreeReorderingGroups(drawing, prefix: name).single;

/// Observes consumed paint and object flags at each ordinary contour in either stream.
Map<double, Map<String, List<String>>> _states(AiNativeDrawing drawing, {required bool private}) {
  final Map<String, List<String>> state = {};
  final Map<double, Map<String, List<String>>> result = {};
  final Map<int, String> paints = {for (final AiNativePath path in drawing.paths) path.start: path.paint.operator};
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.isPrivate && !private) {
      continue;
    }
    if (const {'g', 'G', 'A', 'Xw', 'w', 'd', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'M', 'Xy'}.contains(item.operator)) {
      state[item.operator] = item.operands.map((token) => token.lexeme).toList();
    } else if (item.operator == 'm') {
      final String paint = paints[item.start]!;
      final Set<String> consumed = {
        'A',
        'Xw',
        'D',
        'Ap',
        'XR',
        if (!const {'n', 'N'}.contains(paint)) 'Xy',
        if (const {'f', 'F', 'b', 'B'}.contains(paint)) ...['g', 'O'],
        if (const {'s', 'S', 'b', 'B'}.contains(paint)) ...['G', 'R', 'w', 'd', 'J', 'j', 'M'],
      };
      result[item.numbers!.first] = {
        for (final MapEntry<String, List<String>> value in state.entries)
          if (consumed.contains(value.key)) value.key: value.value,
      };
    }
  }
  return result;
}

/// Checks exact moved metadata, requested parent, local states and stable inventories.
void _retained(AiNativeDrawing source, AiNativeDrawing result, int x, String parent) {
  final AiNativeObjects before = AiNativeObjects.decode(drawing: source);
  final AiNativeObjects after = AiNativeObjects.decode(drawing: result);
  final AiNativePath old = pathGroupPath(source, x);
  final AiNativePath moved = pathGroupPath(result, x);
  check(result.records.program.bytes.sublist(moved.start, after.forSource(moved).end)).deepEquals(source.records.program.bytes.sublist(old.start, before.forSource(old).end));
  check(after.structure.parentOf(after.structure.nodeFor(moved))!.source).identicalTo(pathGroupParent(result, parent));
  check(result.paths.length).equals(source.paths.length);
  check(result.groups.length).equals(source.groups.length);
  check(result.liveShapes.length).equals(source.liveShapes.length);
  for (final bool private in [false, true]) {
    check(_states(result, private: private)).deepEquals(_states(source, private: private));
  }
}

/// Verifies empty destinations, complete owners, source replay and atomic refusals.
void main() {
  test('moves counted identified paths into empty and populated groups', () {
    final String text = pathGroupSource();
    final AiNativeDrawing source = _drawing(text);
    for (final String parent in ['destination', 'empty', 'source']) {
      final AiNativeDrawing result = source.movePathToGroup(path: pathGroupPath(source, 10), group: pathGroupParent(source, parent));
      _retained(source, result, 10, parent);
      check(pathGroupParent(result, parent).children.last).identicalTo(pathGroupPath(result, 10));
    }
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('moves backwards into an earlier parent without changing following state', () {
    final AiNativeDrawing source = _drawing(pathGroupSource());
    final AiNativeDrawing result = source.movePathToGroup(path: pathGroupPath(source, 20), group: pathGroupParent(source, 'source'));
    _retained(source, result, 20, 'source');
    check(result.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([10, 11, 20, 40]);
  });

  test('retains scalar assignments between a consumed count and its moved geometry', () {
    final String text = countedPathGroupSource();
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.movePathToGroup(path: pathGroupPath(source, 10), group: pathGroupParent(source, 'empty'));
    _retained(source, result, 10, 'empty');
    check(latin1.decode(result.records.program.bytes)).contains('2 As 0.25 g\n%_1 D\n10 -10 m');
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As')).length.equals(4);
  });

  test('requires explicit inheritance across hidden layers and retains exact headers', () {
    final AiNativeDrawing source = _drawing(pathGroupSource(layers: true));
    final AiNativePath path = pathGroupPath(source, 10);
    final AiNativeGroup parent = pathGroupParent(source, 'empty');
    check(() => source.movePathToGroup(path: path, group: parent)).throws<UnsupportedError>();
    final AiNativeDrawing result = source.movePathToGroup(path: path, group: parent, inheritParentFlags: true);
    _retained(source, result, 10, 'empty');
    final AiNativeLayers before = AiNativeLayers.decode(drawing: source);
    final AiNativeLayers after = AiNativeLayers.decode(drawing: result);
    for (final (int, AiNativeLayer) entry in before.layers.indexed) {
      final AiNativeLayer changed = after.layers[entry.$1];
      check(result.records.program.bytes.sublist(changed.start, changed.bodyStart)).deepEquals(source.records.program.bytes.sublist(entry.$2.start, entry.$2.bodyStart));
    }
    check(after.viewComments.map((token) => token.lexeme)).deepEquals(before.viewComments.map((token) => token.lexeme).toList());
    check(after.rootCount).equals(before.rootCount);
  });

  test('preserves direct live-shape parameters and identities inside the destination', () {
    final AiNativeDrawing source = _drawing(directShapeSource.replaceFirst('%%Trailer', 'u U\n%%Trailer'));
    final AiNativeDrawing result = source.movePathToGroup(path: source.paths.first, group: source.groups.singleWhere((group) => group.paths.isEmpty), inheritParentFlags: true);
    final AiLiveShape moved = result.liveShapes.last;
    check(result.records.program.bytes.sublist(moved.start, moved.end)).deepEquals(source.records.program.bytes.sublist(source.liveShapes.first.start, source.liveShapes.first.end));
    check(moved.parameters['ai::Rectangle::CenterX']!.number).equals(8206);
    check(moved.path).identicalTo(result.groups.last.paths.single);
  });

  test('moves ordinary paths through complete CC siblings with separate projection flags', () {
    final AiNativeDrawing source = _drawing(mixedPathGroupSource());
    for (final int x in [70, 72]) {
      final AiNativeGroup parent = x == 70 ? source.groups.singleWhere((group) => group.paths.isEmpty) : subtreeReorderingGroups(source).first;
      final AiNativeDrawing result = source.movePathToGroup(path: pathGroupPath(source, x), group: parent, inheritParentFlags: true);
      for (final (int, AiLiveShape) entry in source.liveShapes.indexed) {
        final AiLiveShape changed = result.liveShapes[entry.$1];
        check(result.records.program.bytes.sublist(changed.start, changed.end)).deepEquals(source.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
      }
      for (final bool private in [false, true]) {
        final List<String> expected = subtreeReorderingFlags(source, private: private).map(jsonEncode).toList()..sort();
        final List<String> actual = subtreeReorderingFlags(result, private: private).map(jsonEncode).toList()..sort();
        check(actual).deepEquals(expected);
      }
    }
  });

  test('retains opaque references and saved identities when relocating an identified path', () {
    final String text = pathGroupSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (path_a) ; (Reference) , ;\n%%EndSetup');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.movePathToGroup(path: pathGroupPath(source, 10), group: pathGroupParent(source, 'empty'));
    check(latin1.decode(result.records.program.bytes)).contains('/XMLUID : (path_a) ; (Reference) ,');
    _retained(source, result, 10, 'empty');
  });

  test('rejects unqualified native owners, source pairs, foreign and stale handles', () {
    final AiNativeDrawing source = _drawing(pathGroupSource());
    final AiNativePath path = pathGroupPath(source, 10);
    final AiNativeGroup parent = pathGroupParent(source, 'empty');
    check(() => source.movePathToGroup(path: _drawing(pathGroupSource()).paths.first, group: parent)).throws<ArgumentError>();
    check(() => source.movePathToGroup(path: path, group: _drawing(pathGroupSource()).groups.first)).throws<ArgumentError>();
    final AiNativeDrawing changed = source.movePathToGroup(path: path, group: parent);
    check(() => changed.movePathToGroup(path: path, group: changed.groups.first)).throws<ArgumentError>();
    for (final String group in ['*u *U', 'q Q', '%_u\n%_U', 'u U\n${objectDictionary(extra: '(opaque) /String (Future) ,')}']) {
      final AiNativeDrawing unsupported = _drawing(objectSource('${movementPath(10)}\n$group'));
      check(() => unsupported.movePathToGroup(path: unsupported.paths.first, group: unsupported.groups.single, inheritParentFlags: true)).throws<UnsupportedError>();
    }
    final AiNativeDrawing paired = _drawing(mixedPathGroupSource());
    check(() => paired.movePathToGroup(path: paired.liveShapes.first.path!, group: paired.groups.last, inheritParentFlags: true)).throws<UnsupportedError>();
    check(() => paired.movePathToGroup(path: pathGroupPath(paired, 70), group: paired.liveShapes.last.appearanceGroup!, inheritParentFlags: true)).throws<UnsupportedError>();
  });

  test('refuses unknown required source values and leaves failed edits immutable', () {
    final String text = pathGroupSource().replaceFirst('0 0.2 0 0 0 Xy', '');
    final AiNativeDrawing source = _drawing(text);
    check(() => source.movePathToGroup(path: pathGroupPath(source, 10), group: pathGroupParent(source, 'empty'))).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('rejects malformed counts and enforces the original output ceiling', () {
    final AiNativeDrawing source = _drawing(pathGroupSource().replaceFirst('2 As 10', '3 As 10'));
    check(() => source.movePathToGroup(path: pathGroupPath(source, 10), group: pathGroupParent(source, 'empty'))).throws<UnsupportedError>();
    final String text = pathGroupSource();
    final AiNativeDrawing bounded = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(() => bounded.movePathToGroup(path: pathGroupPath(bounded, 10), group: pathGroupParent(bounded, 'empty'))).throws<FormatException>();
  });
}
