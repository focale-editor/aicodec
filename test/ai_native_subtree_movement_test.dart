import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_objects_test.dart' show objectSource;
import 'ai_native_subtree_reordering_test.dart' show subtreeBatchReorderingSource, subtreeReorderingFlags, subtreeReorderingGroups, subtreeReorderingSource;

/// Opens exact source handles under optional parser ceilings.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Supplies identified nested owners and an empty group or layer destination.
String subtreeMovementSource({bool layers = false}) {
  final String text = subtreeReorderingSource(layers: layers);
  return layers
      ? text.replaceFirst('%AI5_NumLayers: 3', '%AI5_NumLayers: 4').replaceFirst('%%Trailer', '${movementLayer('Empty', 'u U')}\n%%Trailer')
      : text.replaceFirst('%%Trailer', 'u U\n%%Trailer');
}

/// Checks all exact pair bytes, contour inputs and immutable object counts.
void _retained(AiNativeDrawing source, AiNativeDrawing result, List<int> order) {
  check(result.paths.length).equals(source.paths.length);
  check(result.groups.length).equals(source.groups.length);
  check(result.liveShapes.length).equals(source.liveShapes.length);
  for (final (int, int) entry in order.indexed) {
    final AiLiveShape old = source.liveShapes[entry.$2];
    final AiLiveShape moved = result.liveShapes[entry.$1];
    check(result.records.program.bytes.sublist(moved.start, moved.end)).deepEquals(source.records.program.bytes.sublist(old.start, old.end));
  }
  for (final bool private in [false, true]) {
    final int count = private ? 5 : 4;
    final List<List<Object?>> before = subtreeReorderingFlags(source, private: private);
    check(subtreeReorderingFlags(result, private: private)).deepEquals([
      for (final int index in order) ...before.sublist(index * count, (index + 1) * count),
      ...before.skip(order.length * count),
    ]);
  }
}

/// Finds a named layer after reparsing a moved immutable snapshot.
AiNativeLayer _layer(AiNativeLayers model, String name) => model.layers.singleWhere((layer) => latin1.decode(layer.nameBytes!) == name);

/// Checks complete subtrees, parent inheritance and state at both edited positions.
void main() {
  test('moves complete sibling groups forward and backward without splitting descendants', () {
    final String text = subtreeMovementSource();
    final AiNativeDrawing source = _drawing(text);
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    _retained(source, source.moveGroupAfter(group: groups[0], after: groups[2]), [1, 2, 0]);
    _retained(source, source.moveGroupAfter(group: groups[2], after: groups[0]), [0, 2, 1]);
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('appends to a populated or empty group only with explicit ancestor inheritance', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource());
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    for (final AiNativeGroup parent in [groups[2], source.groups.singleWhere((group) => group.paths.isEmpty)]) {
      check(() => source.moveGroupToGroup(group: groups[0], parent: parent)).throws<UnsupportedError>();
      final AiNativeDrawing result = source.moveGroupToGroup(group: groups[0], parent: parent, inheritParentFlags: true);
      _retained(source, result, [1, 2, 0]);
      final AiNativeStructure ownership = AiNativeStructure.decode(drawing: result);
      final AiNativeGroup moved = subtreeReorderingGroups(result).last;
      check(ownership.parentOf(ownership.nodeFor(moved))!.kind).equals(AiNativeStructureKind.group);
    }
  });

  test('moves after an anchor in another group while retaining complete parent metadata', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource());
    final AiNativeGroup moved = subtreeReorderingGroups(source).first;
    final AiNativeGroup anchor = subtreeReorderingGroups(source, prefix: 'inner_').last;
    check(() => source.moveGroupAfter(group: moved, after: anchor)).throws<UnsupportedError>();
    _retained(source, source.moveGroupAfter(group: moved, after: anchor, inheritParentFlags: true), [1, 2, 0]);
  });

  test('compares the native and printing flags of same-depth ancestors separately', () {
    for (final String flags in ['1 A 1 Xw', '%_1 A\n%_1 Xw']) {
      final String text = subtreeMovementSource();
      final AiNativeDrawing initial = _drawing(text);
      final int position = AiNativeObjects.decode(drawing: initial).forSource(subtreeReorderingGroups(initial).last).start;
      final AiNativeDrawing source = _drawing('${text.substring(0, position)}$flags\n${text.substring(position)}');
      final List<AiNativeGroup> groups = subtreeReorderingGroups(source, prefix: 'inner_');
      check(() => source.moveGroupAfter(group: groups[0], after: groups[2])).throws<UnsupportedError>();
      _retained(source, source.moveGroupAfter(group: groups[0], after: groups[2], inheritParentFlags: true), [1, 2, 0]);
    }
  });

  test('appends mixed groups to a containing or empty layer and preserves all headers', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource(layers: true));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeGroup group = subtreeReorderingGroups(source).first;
    for (final AiNativeLayer layer in [_layer(layers, 'Layer_0'), _layer(layers, 'Empty')]) {
      check(() => source.moveGroupToLayer(group: group, layer: layer.source)).throws<UnsupportedError>();
      final AiNativeDrawing result = source.moveGroupToLayer(group: group, layer: layer.source, inheritParentFlags: true);
      _retained(source, result, layer == layers.layers.first ? [0, 1, 2] : [1, 2, 0]);
      final AiNativeLayers changed = AiNativeLayers.decode(drawing: result);
      for (final AiNativeLayer old in layers.layers) {
        final AiNativeLayer newLayer = _layer(changed, latin1.decode(old.nameBytes!));
        check(result.records.program.bytes.sublist(newLayer.start, newLayer.bodyStart)).deepEquals(source.records.program.bytes.sublist(old.start, old.bodyStart));
      }
    }
  });

  test('moves across layers after an owned mixed sibling with explicit inheritance', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource(layers: true));
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    check(() => source.moveGroupAfter(group: groups[0], after: groups[2])).throws<UnsupportedError>();
    _retained(source, source.moveGroupAfter(group: groups[0], after: groups[2], inheritParentFlags: true), [1, 2, 0]);
  });

  test('moves a parent containing multiple complete pairs and ordinary children', () {
    final AiNativeDrawing source = _drawing(subtreeBatchReorderingSource());
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source, prefix: 'batch_');
    _retained(source, source.moveGroupAfter(group: groups[0], after: groups[1]), [2, 0, 1]);
  });

  test('moves mixed layer subtrees between sibling slots while retaining nested headers', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource(layers: true));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeLayers result = layers.moveAfter(layer: _layer(layers, 'Layer_0'), after: _layer(layers, 'Layer_2'));
    check(result.rootCount).equals(4);
    check(result.layers.map((layer) => latin1.decode(layer.nameBytes!))).deepEquals(['Layer_1', 'Child_1', 'Layer_2', 'Child_2', 'Layer_0', 'Child_0', 'Empty']);
    _retained(source, result.drawing, [1, 2, 0]);
  });

  test('nests mixed layers under populated or empty destinations with updated root counts', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource(layers: true));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    for (final String target in ['Layer_2', 'Empty']) {
      check(() => layers.moveInto(layer: _layer(layers, 'Layer_0'), parent: _layer(layers, target))).throws<UnsupportedError>();
      final AiNativeLayers result = layers.moveInto(layer: _layer(layers, 'Layer_0'), parent: _layer(layers, target), inheritParentFlags: true);
      check(result.rootCount).equals(3);
      check(_layer(result, 'Layer_0').parentIndex).equals(_layer(result, target).index);
      _retained(source, result.drawing, [1, 2, 0]);
    }
  });

  test('lifts mixed child layers after an ancestor or another root without losing identities', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource(layers: true));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    for (final String target in ['Layer_0', 'Layer_2']) {
      final AiNativeLayer moved = _layer(layers, 'Child_0');
      check(() => layers.moveAfter(layer: moved, after: _layer(layers, target))).throws<UnsupportedError>();
      final AiNativeLayers result = layers.moveAfter(layer: moved, after: _layer(layers, target), inheritParentFlags: true);
      check(result.rootCount).equals(5);
      check(_layer(result, 'Child_0').parentIndex).isNull();
      _retained(source, result.drawing, target == 'Layer_0' ? [0, 1, 2] : [1, 2, 0]);
    }
  });

  test('retains source aliases and opaque external references during relocation', () {
    final String text = subtreeMovementSource().replaceFirst('(older_0)', '(author_0)').replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author_0) ; (Reference) , ;\n%%EndSetup');
    final AiNativeDrawing source = _drawing(text);
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    final AiNativeDrawing result = source.moveGroupAfter(group: groups[0], after: groups[2]);
    check(latin1.decode(result.records.program.bytes)).contains('/XMLUID : (author_0) ; (Reference) ,');
    _retained(source, result, [1, 2, 0]);
  });

  test('checks following native dependencies at both the source and destination', () {
    for (final bool reset in [false, true]) {
      final AiNativeDrawing source = _drawing(subtreeReorderingSource(following: true, reset: reset));
      final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
      for (final bool forward in [false, true]) {
        if (reset) {
          _retained(source, source.moveGroupAfter(group: groups[forward ? 0 : 2], after: groups[forward ? 2 : 0]), forward ? [1, 2, 0] : [0, 2, 1]);
        } else {
          check(() => source.moveGroupAfter(group: groups[forward ? 0 : 2], after: groups[forward ? 2 : 0])).throws<UnsupportedError>();
        }
      }
    }
  });

  test('rejects an unknown incoming value rather than assigning a later source value', () {
    final String text = subtreeMovementSource().replaceFirst('0 D ', '').replaceFirst('0 D\n', '');
    final AiNativeDrawing source = _drawing(text);
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    check(() => source.moveGroupAfter(group: groups[0], after: groups[2])).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('supports ordinary group insertion into another group without private descendants', () {
    final AiNativeDrawing source = _drawing(objectSource('u 10 0 m 11 1 L S U\nu U'));
    final AiNativeGroup group = source.groups.singleWhere((group) => group.paths.isNotEmpty);
    final AiNativeGroup target = source.groups.singleWhere((group) => group.paths.isEmpty);
    final AiNativeDrawing result = source.moveGroupToGroup(group: group, parent: target, inheritParentFlags: true);
    check(result.groups).length.equals(2);
    check(result.groups.last.children.whereType<AiNativeGroup>()).length.equals(1);
    check(result.paths.single.geometry.first.numbers!).deepEquals([10.0, 0.0]);
  });

  test('requires explicit invalidation of positional layer view state', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource(layers: true).replaceFirst('%%EndComments', '%AI5_OpenViewLayers: 7\n%%EndComments'));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    check(() => layers.moveAfter(layer: _layer(layers, 'Layer_0'), after: _layer(layers, 'Layer_2'))).throws<UnsupportedError>();
    final AiNativeLayers result = layers.moveAfter(layer: _layer(layers, 'Layer_0'), after: _layer(layers, 'Layer_2'), discardViewState: true);
    check(result.viewComments).isEmpty();
    _retained(source, result.drawing, [1, 2, 0]);
  });

  test('rejects self, descendant, printing, foreign and stale group handles', () {
    final AiNativeDrawing source = _drawing(subtreeMovementSource());
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    for (final AiNativeGroup parent in [groups.first, subtreeReorderingGroups(source, prefix: 'inner_').first]) {
      check(() => source.moveGroupToGroup(group: groups.first, parent: parent, inheritParentFlags: true)).throws<ArgumentError>();
    }
    check(() => source.moveGroupToGroup(group: groups.first, parent: source.liveShapes.last.appearanceGroup!, inheritParentFlags: true)).throws<UnsupportedError>();
    check(() => source.moveGroupAfter(group: groups.first, after: groups.first)).throws<ArgumentError>();
    check(() => source.moveGroupToGroup(group: groups.first, parent: _drawing(subtreeMovementSource()).groups.first, inheritParentFlags: true)).throws<ArgumentError>();
    final AiNativeDrawing result = source.moveGroupAfter(group: groups[0], after: groups[2]);
    check(() => result.moveGroupAfter(group: groups[0], after: subtreeReorderingGroups(result).first)).throws<ArgumentError>();
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: _drawing(subtreeMovementSource(layers: true)));
    check(() => layers.moveInto(layer: _layer(layers, 'Layer_0'), parent: _layer(layers, 'Child_0'), inheritParentFlags: true)).throws<ArgumentError>();
  });

  test('rejects unknown selected source or destination parent metadata', () {
    for (final String text in [
      subtreeMovementSource().replaceFirst('70 0 m', '17 Future\n70 0 m'),
      subtreeMovementSource().replaceFirst('(outer_2) ; (AI10_ArtUID) ,', '(outer_2) ; (AI10_ArtUID) , 17 /Real (Future) ,'),
    ]) {
      final AiNativeDrawing source = _drawing(text);
      final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
      check(() => source.moveGroupToGroup(group: groups[0], parent: groups[2], inheritParentFlags: true)).throws<UnsupportedError>();
    }
  });

  test('enforces the original byte ceiling before publishing a moved snapshot', () {
    final String text = subtreeMovementSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    check(() => source.moveGroupAfter(group: groups[0], after: groups[2])).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });
}
