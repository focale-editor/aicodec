import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementState;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing, groupCreationSource;
import 'ai_native_layer_creation_test.dart' show layerCreationSource, layerDefinition;
import 'ai_native_objects_test.dart' show objectSource;
import 'ai_native_path_group_movement_test.dart' show mixedPathGroupSource, pathGroupParent;

/// Supplies explicit geometry and process paints independently of source objects.
AiNativePathDefinition pathCreationDefinition({bool counted = true, bool closed = true, bool filled = true, bool stroked = true, AiColorSpace space = .rgb, String? identifier = 'Created'}) {
  final List<double> channels = switch (space) {
    .gray => [0.4],
    .rgb => [0.2, 0.4, 0.6],
    .cmyk => [0.1, 0.2, 0.3, 0.4],
  };
  return AiNativePathDefinition(
    artwork: AiArtworkPath(
      segments: [
        AiPathSegment(operator: 'm', coordinates: [10, -10]),
        AiPathSegment(operator: 'L', coordinates: [30, -10]),
        AiPathSegment(operator: 'L', coordinates: [30, -30]),
      ],
      fill: filled ? AiColor(space: space, channels: channels) : null,
      stroke: stroked ? AiColor(space: space, channels: channels.reversed.toList()) : null,
      closed: closed,
      evenOdd: true,
      locked: true,
      strokeWidth: 2,
      lineCap: 1,
      lineJoin: 2,
      dash: [4, 2],
      dashPhase: 1,
    ),
    bounds: AiBoundingBox(left: 8, bottom: -32, right: 32, top: -8),
    counted: counted,
    opacity: 0.7,
    fillOverprint: true,
    strokeOverprint: true,
    nameBytes: latin1.encode('New (path)'),
    identifierBytes: identifier == null ? null : latin1.encode(identifier),
  );
}

/// Keeps following paths' required attributes known and separate in both streams.
String get pathCreationSource => groupCreationSource.replaceFirst('10 M', '10 M\n0 0.9 0 0 0 Xy\n%_0.6 g\n%_0.8 G\n%_1 D\n%_0 0.4 0 0 0 Xy');

/// Captures concrete scalar state at each original contour without rendering it.
Map<double, Map<String, List<Object>>> _states(AiNativeDrawing drawing, {required bool private}) {
  final Map<String, List<Object>> current = {};
  final Map<double, Map<String, List<Object>>> result = {};
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.isPrivate && !private) {
      continue;
    }
    final String key = const {'g', 'Xa', 'k'}.contains(item.operator)
        ? 'fill'
        : const {'G', 'XA', 'K'}.contains(item.operator)
        ? 'stroke'
        : item.operator;
    if (const {'fill', 'stroke', 'A', 'Xw', 'Xy', 'D', 'Ap', 'XR', 'O', 'R', 'J', 'j', 'w', 'M', 'd'}.contains(key)) {
      current[key] = [item.operator, ...item.operands.map((token) => token.number ?? token.lexeme)];
    } else if (item.operator == 'm') {
      result[item.numbers!.first] = Map.of(current);
    }
  }
  return result;
}

/// Finds the newly authored identity rather than relying on changed path indices.
AiNativePath createdPath(AiNativeDrawing drawing) =>
    AiNativeObjects.decode(drawing: drawing).objects.singleWhere((object) => latin1.decode(object.identifier?.bytes ?? []) == 'Created').source as AiNativePath;

/// Exercises explicit authoring, separate outgoing state and immutable failures.
void main() {
  test('creates a first path from explicit geometry and paint without any source state', () {
    final String text = objectSource('', setup: '').replaceFirst(movementState, '');
    final AiNativeDrawing source = groupCreationDrawing(text);
    final AiNativeDrawing result = source.createPath(definition: pathCreationDefinition());
    final AiNativePath path = createdPath(result);
    check(path.paint.operator).equals('b');
    check(path.geometry.map((item) => item.numbers!)).deepEquals([
      [10.0, -10.0],
      [30.0, -10.0],
      [30.0, -30.0],
      [10.0, -10.0],
    ]);
    check(result.items.whereType<AiNativeInstruction>().singleWhere((item) => item.operator == 'As').numbers!).deepEquals([3.0]);
    check(latin1.decode(result.records.program.bytes)).contains('%%BoundingBox: 0 -32 100 100');
    check(result.liveShapes).isEmpty();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('supports every process color, paint combination and count/closure convention', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('', setup: ''));
    for (final AiColorSpace space in AiColorSpace.values) {
      for (final bool closed in [false, true]) {
        for (final bool counted in [false, true]) {
          for (final (bool, bool, String) paint in [(false, false, 'N'), (true, false, 'F'), (false, true, 'S'), (true, true, 'B')]) {
            final AiNativeDrawing result = source.createPath(
              definition: pathCreationDefinition(space: space, closed: closed, counted: counted, filled: paint.$1, stroked: paint.$2),
            );
            final AiNativePath path = createdPath(result);
            check(path.paint.operator).equals(closed ? paint.$3.toLowerCase() : paint.$3);
            check(path.geometry.length).equals(counted && closed ? 4 : 3);
            check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As').length).equals(counted ? 1 : 0);
          }
        }
      }
    }
  });

  test('restores both states when creating in populated and empty groups', () {
    final AiNativeDrawing source = groupCreationDrawing(pathCreationSource);
    for (final AiNativeGroup parent in source.groups) {
      final AiNativeDrawing result = source.createPath(definition: pathCreationDefinition(), parent: parent);
      final AiNativePath created = createdPath(result);
      final AiNativeStructure structure = AiNativeStructure.decode(drawing: result);
      final AiNativeGroup owner = structure.parentOf(structure.nodeFor(created))!.source as AiNativeGroup;
      check(owner.children.last).identicalTo(created);
      for (final bool private in [false, true]) {
        final Map<double, Map<String, List<Object>>> states = _states(result, private: private);
        check(states[20]!).deepEquals(_states(source, private: private)[20]!);
      }
      check(result.records.program.layers).isEmpty();
      check(result.groups.length).equals(source.groups.length);
    }
  });

  test('authors inside freshly created layers and groups and keeps the new path editable', () {
    final AiNativeLayers initial = AiNativeLayers.decode(drawing: groupCreationDrawing(layerCreationSource()));
    final AiNativeLayers layers = initial.create(definition: layerDefinition());
    final AiNativeDrawing grouped = layers.drawing.createGroup(layer: layers.layers.single.source);
    final AiNativeDrawing result = grouped.createPath(definition: pathCreationDefinition(), parent: grouped.groups.single);
    final AiNativePath created = createdPath(result);
    final AiNativeDrawing copied = result.duplicatePaths(paths: [created], identifiers: {created: latin1.encode('Copied')});
    check(copied.paths).length.equals(2);
    final AiNativeDrawing removed = copied.removePaths(paths: copied.paths);
    check(removed.paths).isEmpty();
    check(removed.createPath(definition: pathCreationDefinition(), parent: removed.groups.single).paths).length.equals(1);
  });

  test('preserves neighboring CC pairs and inherited layer flags without changing views', () {
    final AiNativeDrawing source = groupCreationDrawing(mixedPathGroupSource());
    final AiNativeDrawing result = source.createPath(definition: pathCreationDefinition(), parent: pathGroupParent(source, 'outer_0'));
    for (final (int, AiLiveShape) entry in source.liveShapes.indexed) {
      final AiLiveShape changed = result.liveShapes[entry.$1];
      check(result.records.program.bytes.sublist(changed.start, changed.end)).deepEquals(source.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    }
    final AiNativeDrawing hidden = groupCreationDrawing(layerCreationSource(body: movementLayer('Hidden', '', hidden: true), count: 1, views: true));
    final AiNativeDrawing nested = hidden.createPath(definition: pathCreationDefinition(), layer: hidden.records.program.layers.single);
    check(AiNativeLayers.decode(drawing: nested).layers.single.source.visible).isFalse();
    check(AiNativeLayers.decode(drawing: nested).viewComments.map((token) => token.lexeme)).deepEquals(AiNativeLayers.decode(drawing: hidden).viewComments.map((token) => token.lexeme).toList());
  });

  test('refuses unknown following state, unowned prefixes and invalid source owners', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('u U\n20 0 m 21 1 L F', setup: '').replaceFirst('0.1 g', ''));
    check(() => source.createPath(definition: pathCreationDefinition(), parent: source.groups.single)).throws<UnsupportedError>();
    for (final String prefix in ['3 As', '1 Ae', '17 FuturePaint', '%AI3_Note: (unowned)']) {
      final AiNativeDrawing unknown = groupCreationDrawing(objectSource(prefix, setup: ''));
      check(() => unknown.createPath(definition: pathCreationDefinition())).throws<UnsupportedError>();
    }
    for (final String group in ['*u *U', 'q Q', '%_u\n%_U']) {
      final AiNativeDrawing invalid = groupCreationDrawing(objectSource(group, setup: ''));
      check(() => invalid.createPath(definition: pathCreationDefinition(), parent: invalid.groups.single)).throws<UnsupportedError>();
    }
    check(() => source.createPath(definition: pathCreationDefinition(), parent: groupCreationDrawing(groupCreationSource).groups.first)).throws<ArgumentError>();
  });

  test('freezes metadata and rejects nonportable definitions, identities and budgets', () {
    final AiNativePathDefinition definition = pathCreationDefinition();
    check(() => definition.nameBytes![0] = 0).throws<UnsupportedError>();
    check(() => definition.identifierBytes![0] = 0).throws<UnsupportedError>();
    check(() => AiNativePathDefinition(artwork: definition.artwork, bounds: definition.bounds, opacity: double.nan)).throws<ArgumentError>();
    check(() => AiNativePathDefinition(artwork: definition.artwork, bounds: AiBoundingBox(left: 0, bottom: 0, right: 1e20, top: 1))).throws<ArgumentError>();
    final String text = objectSource('', setup: '');
    final AiNativeDrawing source = groupCreationDrawing(text);
    final AiNativeDrawing created = source.createPath(definition: definition);
    check(() => created.createPath(definition: definition)).throws<ArgumentError>();
    final AiNativeDrawing bounded = groupCreationDrawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(() => bounded.createPath(definition: definition)).throws<FormatException>();
    check(latin1.decode(bounded.records.program.bytes)).equals(text);
  });

  test('writes cubic and shorthand curves with explicit hidden zero-opacity state', () {
    final AiArtworkPath artwork = AiArtworkPath(
      segments: [
        AiPathSegment(operator: 'm', coordinates: [10, -10]),
        AiPathSegment(operator: 'c', coordinates: [12, -10, 14, -12, 16, -14]),
        AiPathSegment(operator: 'V', coordinates: [18, -16, 20, -18]),
        AiPathSegment(operator: 'y', coordinates: [22, -20, 24, -22]),
      ],
      fill: AiColor(space: .gray, channels: [0.3]),
    );
    final AiBoundingBox bounds = AiBoundingBox(left: 10, bottom: -22, right: 24, top: -10);
    final AiNativeDrawing source = groupCreationDrawing(objectSource('', setup: ''));
    final AiNativeDrawing anonymous = source.createPath(
      definition: AiNativePathDefinition(artwork: artwork, bounds: bounds, hidden: true, opacity: 0),
    );
    final AiNativePath path = anonymous.paths.single;
    check(path.segments.map((segment) => segment.operator)).deepEquals(['m', 'c', 'V', 'y']);
    check(AiNativeObjects.decode(drawing: anonymous).forSource(path).dictionary).isNull();
    check(_states(anonymous, private: false)[10]!['Xw']!).deepEquals(['Xw', 1.0]);
    check(_states(anonymous, private: false)[10]!['Xy']!).deepEquals(['Xy', 0.0, 0.0, 0.0, 0.0, 0.0]);
    final List<int> name = latin1.encode('Original');
    final List<int> identity = latin1.encode('Frozen');
    final AiNativePathDefinition definition = AiNativePathDefinition(artwork: artwork, bounds: bounds, nameBytes: name, identifierBytes: identity);
    name[0] = 0;
    identity[0] = 0;
    final AiNativeDrawing named = source.createPath(definition: definition);
    final AiNativeObject object = AiNativeObjects.decode(drawing: named).forSource(named.paths.single);
    check(object.names.single.stringBytes!).deepEquals(latin1.encode('Original'));
    check(object.identifier!.bytes).deepEquals(latin1.encode('Frozen'));
  });
}
