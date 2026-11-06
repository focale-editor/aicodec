import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Complete explicit process state, including attributes shared across layers.
const String movementState = '0 A 0 Xw 0.1 g 0 G 2 w [] 0 d 0 O 0 R 0 XR 0 D 0 Ap 0 J 0 j 10 M';

/// Creates an identified layer with known wrappers and optional hidden flags.
String movementLayer(String name, String body, {bool hidden = false}) =>
    '''%AI5_BeginLayer
${hidden ? '0 1 0 1 0 0 0' : '1 1 1 1 0 0 1'} 0 79 128 255 0 50 0 Lb
($name) Ln
1 AE
%_/ArtDictionary :
%_/XMLUID : ($name) ; (AI10_ArtUID) ,
%_;
$body
LB
%AI5_EndLayer--''';

/// Distinguishes each counted path by its initial horizontal coordinate.
String movementPath(int x) => '2 As $x 0 m ${x + 1} 1 L S';

/// Uses nested hidden owners, changing group paint and an empty destination.
String get artworkMovementSource => _source(
  '${movementLayer('A', '${movementPath(10)}\n${movementLayer('A1', '1 A 1 Xw 0.3 g 5 w u ${movementPath(20)} 0.6 g ${movementPath(25)} U', hidden: true)}')}\n'
  '${movementLayer('B', '0 A 0 Xw 0.8 g 1 G 3 w u ${movementPath(30)} 0.7 g ${movementPath(35)} U ${movementPath(40)}', hidden: true)}\n'
  '${movementLayer('Empty', '')}',
);

/// Supplies layer declarations without changing them during artwork movement.
String _source(String body, {String state = movementState, int roots = 3}) =>
    '''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%AI5_NumLayers: $roots
%AI5_OpenViewLayers: 37
%%EndComments
%%BeginProlog
%%EndProlog
%%BeginSetup
%%EndSetup
$state
$body
%%PageTrailer
%%Trailer
%%EOF
''';

/// Decodes the complete immutable source under caller-specified parser limits.
AiNativeDrawing _drawing(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Observes retained effective assignments by each path's unique coordinate.
Map<double, Map<String, List<String>>> _states(AiNativeDrawing drawing) {
  final Map<String, List<String>> state = {};
  final Map<double, Map<String, List<String>>> result = {};
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (const {'g', 'G', 'A', 'Xw', 'w', 'd', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'M'}.contains(item.operator)) {
      state[item.operator] = item.operands.map((token) => token.lexeme).toList();
    } else if (item.operator == 'm') {
      result[item.numbers!.first] = Map.of(state);
    }
  }
  return result;
}

/// Checks every layer header, identity, declared count and saved view exactly.
void _retained(AiNativeDrawing before, AiNativeDrawing after) {
  final AiNativeLayers original = AiNativeLayers.decode(drawing: before);
  final AiNativeLayers result = AiNativeLayers.decode(drawing: after);
  check(result.layers).length.equals(original.layers.length);
  for (final (int, AiNativeLayer) entry in original.layers.indexed) {
    final AiNativeLayer changed = result.layers[entry.$1];
    check(changed.parentIndex).equals(entry.$2.parentIndex);
    check(after.records.program.bytes.sublist(changed.start, changed.bodyStart)).deepEquals(before.records.program.bytes.sublist(entry.$2.start, entry.$2.bodyStart));
  }
  check(result.rootCountHeader!.token.lexeme).equals(original.rootCountHeader!.token.lexeme);
  check(result.viewComments.map((token) => token.lexeme)).deepEquals(original.viewComments.map((token) => token.lexeme));
  check(_states(after)).deepEquals(_states(before));
  check(after.paths).length.equals(before.paths.length);
  check(after.groups).length.equals(before.groups.length);
}

/// Qualifies cross-layer topology, source state, explicit inheritance and limits.
void main() {
  test('moves a counted path between nested hidden layers with exact own attributes', () {
    final AiNativeDrawing source = _drawing(artworkMovementSource);
    check(() => source.movePathAfter(path: source.paths[1], after: source.paths[3])).throws<UnsupportedError>();
    final AiNativeDrawing result = source.movePathAfter(path: source.paths[1], after: source.paths[3], inheritParentFlags: true);
    check(result.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([10.0, 25.0, 30.0, 20.0, 35.0, 40.0]);
    check(result.groups.map((group) => group.paths.length)).deepEquals([1, 3]);
    _retained(source, result);
  });

  test('moves a whole group backward and preserves its old outgoing assignments', () {
    final AiNativeDrawing source = _drawing(artworkMovementSource);
    check(() => source.moveGroupAfter(group: source.groups.last, after: source.groups.first)).throws<UnsupportedError>();
    final AiNativeDrawing result = source.moveGroupAfter(group: source.groups.last, after: source.groups.first, inheritParentFlags: true);
    final AiNativeStructure structure = AiNativeStructure.decode(drawing: result);
    check(structure.parentOf(structure.nodeFor(result.groups.first))!.source).identicalTo(structure.parentOf(structure.nodeFor(result.groups.last))!.source);
    _retained(source, result);
  });

  test('appends paths and groups to an empty layer without changing panel state', () {
    final AiNativeDrawing source = _drawing(artworkMovementSource);
    final AiLayer empty = source.records.program.layers.last;
    check(() => source.movePathToLayer(path: source.paths[1], layer: empty)).throws<UnsupportedError>();
    check(() => source.moveGroupToLayer(group: source.groups.first, layer: empty)).throws<UnsupportedError>();
    final AiNativeDrawing path = source.movePathToLayer(path: source.paths[1], layer: empty, inheritParentFlags: true);
    check(path.paths.last.geometry.first.numbers!.first).equals(20);
    check(path.records.program.paths.last.layerStart).equals(path.records.program.layers.last.begin.start);
    _retained(source, path);
    final AiNativeDrawing group = source.moveGroupToLayer(group: source.groups.first, layer: empty, inheritParentFlags: true);
    check(group.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([10.0, 30.0, 35.0, 40.0, 20.0, 25.0]);
    _retained(source, group);
  });

  test('moves unlayered artwork into a layer and back after a root anchor', () {
    final AiNativeDrawing source = _drawing(_source('${movementPath(10)}\n${movementLayer('A', movementPath(20))}', roots: 1));
    final AiNativeDrawing inside = source.movePathToLayer(path: source.paths.first, layer: source.records.program.layers.single, inheritParentFlags: true);
    check(inside.records.program.paths.every((path) => path.layerStart != null)).isTrue();
    final AiNativeDrawing outside = source.movePathAfter(path: source.paths.last, after: source.paths.first, inheritParentFlags: true);
    check(outside.records.program.paths.every((path) => path.layerStart == null)).isTrue();
    _retained(source, inside);
    _retained(source, outside);
  });

  test('requires explicit group inheritance when lifting to the same containing layer', () {
    final AiNativeDrawing source = _drawing(artworkMovementSource);
    final AiLayer layer = source.records.program.layers[1];
    check(() => source.movePathToLayer(path: source.paths[1], layer: layer)).throws<UnsupportedError>();
    final AiNativeDrawing result = source.movePathToLayer(path: source.paths[1], layer: layer, inheritParentFlags: true);
    check(result.groups.first.paths).length.equals(1);
    _retained(source, result);
    final AiNativeDrawing groups = _drawing(_source(movementLayer('A', 'u u ${movementPath(10)} U U'), roots: 1));
    check(() => groups.moveGroupToLayer(group: groups.groups.first, layer: groups.records.program.layers.single)).throws<UnsupportedError>();
    check(groups.moveGroupToLayer(group: groups.groups.first, layer: groups.records.program.layers.single, inheritParentFlags: true).groups).length.equals(2);
  });

  test('rejects unknown paint, malformed headers and opaque intervening owners atomically', () {
    final List<String> sources = [
      _source('${movementLayer('A', movementPath(10))}\n${movementLayer('B', '0.8 g ${movementPath(20)}')}', roots: 2, state: ''),
      _source('${movementLayer('A', movementPath(10))}\n17 FuturePaint\n${movementLayer('B', movementPath(20))}', roots: 2),
      _source('${movementLayer('A', movementPath(10))}\n${movementLayer('B', movementPath(20))}', roots: 1),
      _source('${movementLayer('A', movementPath(10))}\n${movementLayer('B', movementPath(20)).replaceFirst('1 AE', '2 AE')}', roots: 2),
    ];
    for (final (int, String) entry in sources.indexed) {
      final AiNativeDrawing drawing = _drawing(entry.$2);
      final List<int> original = drawing.records.program.bytes.toList();
      if (entry.$1 < 2) {
        check(() => drawing.movePathAfter(path: drawing.paths.first, after: drawing.paths.last, inheritParentFlags: true)).throws<UnsupportedError>();
      } else {
        check(() => drawing.movePathAfter(path: drawing.paths.first, after: drawing.paths.last, inheritParentFlags: true)).throws<FormatException>();
      }
      check(drawing.records.program.bytes).deepEquals(original);
    }
  });

  test('keeps unknown provenance distinct across opaque state boundaries for groups', () {
    final AiNativeDrawing source = _drawing(_source('u U\n17 FuturePaint\nu U', roots: 0, state: ''));
    check(() => source.moveGroupAfter(group: source.groups.first, after: source.groups.last, inheritParentFlags: true)).throws<UnsupportedError>();
  });

  test('rejects stale and foreign destination layers before serializing', () {
    final AiNativeDrawing source = _drawing(artworkMovementSource);
    final AiNativeDrawing foreign = _drawing(artworkMovementSource);
    check(() => source.movePathToLayer(path: source.paths.first, layer: foreign.records.program.layers.last, inheritParentFlags: true)).throws<ArgumentError>();
    check(() => source.moveGroupToLayer(group: source.groups.first, layer: foreign.records.program.layers.last, inheritParentFlags: true)).throws<ArgumentError>();
    final AiNativeDrawing changed = source.movePathToLayer(path: source.paths.first, layer: source.records.program.layers.last, inheritParentFlags: true);
    check(() => changed.movePathToLayer(path: changed.paths.first, layer: source.records.program.layers.last, inheritParentFlags: true)).throws<ArgumentError>();
  });

  test('retains opaque artwork outside the qualified cross-layer interval', () {
    const String tail = '17 FuturePaint\n/FutureOwner : (untouched) /Data ;\n%%PageTrailer';
    final AiNativeDrawing source = _drawing(artworkMovementSource.replaceFirst('%%PageTrailer', tail));
    final AiNativeDrawing path = source.movePathAfter(path: source.paths[1], after: source.paths[3], inheritParentFlags: true);
    final AiNativeDrawing group = source.moveGroupAfter(group: source.groups.first, after: source.groups.last, inheritParentFlags: true);
    for (final AiNativeDrawing result in [path, group]) {
      check(latin1.decode(result.records.program.bytes)).contains(tail);
      _retained(source, result);
    }
  });

  test('preserves anonymous bare layers and empty ordinary groups', () {
    const String header = '1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb';
    final AiNativeDrawing source = _drawing(_source('$header u U LB\n$header LB', roots: 2));
    final AiNativeDrawing result = source.moveGroupToLayer(group: source.groups.single, layer: source.records.program.layers.last, inheritParentFlags: true);
    check(result.groups).length.equals(1);
    check(result.paths).isEmpty();
    check(result.records.program.layers.every((layer) => layer.name == null)).isTrue();
    _retained(source, result);
  });

  test('bounds added state and aggregate tokens during cross-layer serialization', () {
    final AiNativeDrawing source = _drawing(artworkMovementSource);
    final AiNativeDrawing bytes = _drawing(artworkMovementSource, limits: AiNativeLimits(maxDecodedBytes: source.records.program.bytes.length));
    check(() => bytes.moveGroupToLayer(group: bytes.groups.first, layer: bytes.records.program.layers.last, inheritParentFlags: true)).throws<FormatException>();
    final int tokens = AiPostScript.tokenize(latin1.encode(artworkMovementSource.replaceAll(RegExp(r'^%_', multiLine: true), ''))).length;
    final AiNativeDrawing bounded = _drawing(artworkMovementSource, limits: AiNativeLimits(maxTokens: tokens));
    check(() => bounded.movePathToLayer(path: bounded.paths[1], layer: bounded.records.program.layers.last, inheritParentFlags: true)).throws<FormatException>();
  });
}
