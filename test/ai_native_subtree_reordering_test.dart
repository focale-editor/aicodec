import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_objects_test.dart' show objectDictionary;
import 'ai_native_shape_reordering_test.dart' show shapeReorderingSource;

/// Opens exact immutable native source with optional safety limits.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Wraps three existing pairs in identified nested groups or nested layers.
String subtreeReorderingSource({bool layers = false, bool following = false, bool reset = false}) {
  String text = shapeReorderingSource();
  final AiNativeDrawing original = _drawing(text);
  for (final (int, AiLiveShape) entry in original.liveShapes.indexed.toList().reversed) {
    final int index = entry.$1;
    final AiLiveShape shape = entry.$2;
    final String pair = text.substring(shape.start, shape.end);
    final String child = '${70 + index} 0 m ${80 + index} 1 L f';
    final String group = '0 Ae\nu\nu\n$pair\n$child\nU\n${objectDictionary(identifier: 'inner_$index')}\nU\n${objectDictionary(identifier: 'outer_$index')}';
    text = text.replaceRange(shape.start, shape.end, layers ? movementLayer('Layer_$index', movementLayer('Child_$index', group, hidden: index == 1)) : group);
  }
  if (layers) {
    text = text.replaceFirst('%%EndComments', '%AI5_NumLayers: 3\n%%EndComments');
  }
  if (following) {
    text = text.replaceFirst('%%Trailer', '${reset ? '0.7 g\n' : ''}90 0 m 91 1 L f\n%%Trailer');
  }
  return text;
}

/// Keeps two complete paired descendants together in the first selected parent.
String subtreeBatchReorderingSource() {
  final String text = subtreeReorderingSource();
  final AiNativeDrawing initial = _drawing(text);
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: initial);
  final List<AiNativeObject> owners = subtreeReorderingGroups(initial).map(objects.forSource).toList();
  final String first = 'u\n${text.substring(owners[0].start, owners[1].end)}\nU\n${objectDictionary(identifier: 'batch_a')}';
  final String second = 'u\n${text.substring(owners[2].start, owners[2].end)}\nU\n${objectDictionary(identifier: 'batch_b')}';
  return text.replaceRange(owners[2].start, owners[2].end, second).replaceRange(owners[0].start, owners[1].end, first);
}

/// Selects only the outer ordinary parents, retaining source order.
List<AiNativeGroup> subtreeReorderingGroups(AiNativeDrawing drawing, {String prefix = 'outer_'}) {
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: drawing);
  return drawing.groups.where((group) => latin1.decode(objects.forSource(group).identifier?.bytes ?? const []).startsWith(prefix)).toList()
    ..sort((first, second) => first.start.compareTo(second.start));
}

/// Reads explicit flags at every contour in either source interpretation.
List<List<Object?>> subtreeReorderingFlags(AiNativeDrawing drawing, {required bool private}) {
  final Map<String, Object?> state = {};
  final List<List<Object?>> result = [];
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.isPrivate && !private) {
      continue;
    }
    if (const {'D', 'A', 'Xw', 'Xy'}.contains(item.operator)) {
      state[item.operator] = item.numbers;
    } else if (item.operator == 'm') {
      result.add([
        item.isPrivate,
        item.numbers,
        ...['D', 'A', 'Xw', 'Xy'].map((key) => state[key]),
      ]);
    }
  }
  return result;
}

/// Checks exact source owners separately from state replay around their new slots.
void _retained(AiNativeDrawing source, AiNativeDrawing result, List<int> order) {
  final AiNativeObjects before = AiNativeObjects.decode(drawing: source);
  final AiNativeObjects after = AiNativeObjects.decode(drawing: result);
  final List<AiNativeGroup> originals = subtreeReorderingGroups(source);
  final List<AiNativeGroup> copies = subtreeReorderingGroups(result);
  check(result.paths.length).equals(source.paths.length);
  check(result.groups.length).equals(source.groups.length);
  check(result.liveShapes.length).equals(source.liveShapes.length);
  for (final (int, int) entry in order.indexed) {
    final AiNativeObject old = before.forSource(originals[entry.$2]);
    final AiNativeObject moved = after.forSource(copies[entry.$1]);
    check(result.records.program.bytes.sublist(moved.start, moved.end)).deepEquals(source.records.program.bytes.sublist(old.start, old.end));
  }
  for (final bool private in [false, true]) {
    final int count = private ? 5 : 4;
    final List<List<Object?>> flags = subtreeReorderingFlags(source, private: private);
    check(subtreeReorderingFlags(result, private: private)).deepEquals([for (final int index in order) ...flags.sublist(index * count, (index + 1) * count), ...flags.skip(order.length * count)]);
  }
}

/// Verifies complete source movement, distinct projections and atomic refusal.
void main() {
  test('reorders complete nested groups with both representations and all identities', () {
    final String text = subtreeReorderingSource();
    final AiNativeDrawing source = _drawing(text);
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    final AiNativeDrawing result = source.reorderGroups(groups: [groups[2], groups[0], groups[1]]);
    _retained(source, result, [2, 0, 1]);
    check(latin1.decode(source.records.program.bytes)).equals(text);
    check(AiNativeStructure.decode(drawing: result).identifiers.map((identity) => latin1.decode(identity.bytes))).deepEquals([
      for (final int index in [2, 0, 1]) ...['author_$index', 'older_$index', 'inner_$index', 'outer_$index'],
    ]);
  });

  test('reorders nested layer subtrees while retaining headers and root counts', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource(layers: true));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final List<AiNativeLayer> roots = layers.layers.where((layer) => layer.parentIndex == null).toList();
    final AiNativeLayers result = layers.reorder(layers: [roots[2], roots[0], roots[1]]);
    _retained(source, result.drawing, [2, 0, 1]);
    check(result.rootCount).equals(3);
    check(result.layers.map((layer) => latin1.decode(layer.nameBytes!))).deepEquals(['Layer_2', 'Child_2', 'Layer_0', 'Child_0', 'Layer_1', 'Child_1']);
    check(result.layers[5].source.visible).isFalse();
  });

  test('retains the state and exact bytes of an unselected mixed sibling', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource());
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    _retained(source, source.reorderGroups(groups: [groups[2], groups[0]]), [2, 1, 0]);
  });

  test('moves multiple complete pairs inside one parent without splitting their state flow', () {
    final AiNativeDrawing source = _drawing(subtreeBatchReorderingSource());
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source, prefix: 'batch_').reversed.toList();
    _retained(source, source.reorderGroups(groups: groups), [2, 0, 1]);
  });

  test('keeps opaque external references and existing aliases without allocating names', () {
    final String text = subtreeReorderingSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author_0) ; (Reference) , ;\n%%EndSetup').replaceFirst('(older_0)', '(author_0)');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.reorderGroups(groups: subtreeReorderingGroups(source).reversed.toList());
    _retained(source, result, [2, 1, 0]);
    check(latin1.decode(result.records.program.bytes)).contains('/XMLUID : (author_0) ; (Reference) ,');
  });

  test('rejects unknown outgoing effects observed by following artwork unless reset', () {
    for (final bool reset in [false, true]) {
      final AiNativeDrawing source = _drawing(subtreeReorderingSource(following: true, reset: reset));
      final List<AiNativeGroup> groups = subtreeReorderingGroups(source).reversed.toList();
      if (reset) {
        _retained(source, source.reorderGroups(groups: groups), [2, 1, 0]);
      } else {
        check(() => source.reorderGroups(groups: groups)).throws<UnsupportedError>();
      }
    }
  });

  test('returns unchanged snapshots for a qualified unchanged order', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource());
    check(source.reorderGroups(groups: subtreeReorderingGroups(source))).identicalTo(source);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: _drawing(subtreeReorderingSource(layers: true)));
    check(layers.reorder(layers: layers.layers.where((layer) => layer.parentIndex == null).toList())).identicalTo(layers);
  });

  test('reorders paired and ordinary siblings in the same atomic permutation', () {
    final String text = subtreeReorderingSource().replaceFirst('%%Trailer', '0.6 g\nu\n90 0 m 91 1 L f\nU\n${objectDictionary(identifier: 'outer_3')}\n%%Trailer');
    final AiNativeDrawing source = _drawing(text);
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    final AiNativeDrawing result = source.reorderGroups(groups: [groups[3], groups[0]]);
    check(subtreeReorderingGroups(result).map((group) => latin1.decode(AiNativeObjects.decode(drawing: result).forSource(group).identifier!.bytes))).deepEquals([
      'outer_3',
      'outer_1',
      'outer_2',
      'outer_0',
    ]);
    check(result.paths.length).equals(source.paths.length);
    for (final (int, int) entry in [1, 2, 0].indexed) {
      final AiLiveShape original = source.liveShapes[entry.$2];
      final AiLiveShape moved = result.liveShapes[entry.$1];
      check(result.records.program.bytes.sublist(moved.start, moved.end)).deepEquals(source.records.program.bytes.sublist(original.start, original.end));
    }
  });

  test('does not mask an unresolved printing dependency with private scalar replay', () {
    final String text = subtreeReorderingSource().replaceFirst('0 G ', '');
    final AiNativeDrawing initial = _drawing(text);
    final List<AiNativeGroup> groups = subtreeReorderingGroups(initial);
    final int boundary = AiNativeObjects.decode(drawing: initial).forSource(groups.first).end;
    final String tail = text.substring(boundary).replaceFirst('0 Ae\nu\nu', '0 Ae\nu\n1 G\nu');
    final AiNativeDrawing source = _drawing('${text.substring(0, boundary)}\n%_0 G\n99 0 m 100 1 L s\n$tail');
    final List<AiNativeGroup> selected = subtreeReorderingGroups(source);
    check(() => source.reorderGroups(groups: [selected[1], selected[0]])).throws<UnsupportedError>().has((error) => error.message, 'message').isNotNull().contains('unresolved printing state: stroke');
  });

  test('requires explicit invalidation of positional layer view state', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource(layers: true).replaceFirst('%%EndComments', '%AI5_OpenViewLayers: 7\n%%EndComments'));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final List<AiNativeLayer> order = layers.layers.where((layer) => layer.parentIndex == null).toList().reversed.toList();
    check(() => layers.reorder(layers: order)).throws<UnsupportedError>();
    final AiNativeLayers result = layers.reorder(layers: order, discardViewState: true);
    check(result.viewComments).isEmpty();
    _retained(source, result.drawing, [2, 1, 0]);
  });

  test('rejects different parents and overlapping or foreign handles', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource(layers: true));
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    check(() => source.reorderGroups(groups: subtreeReorderingGroups(source).reversed.toList())).throws<ArgumentError>();
    check(() => layers.reorder(layers: [layers.layers[3], layers.layers[1]])).throws<ArgumentError>();
    check(() => layers.reorder(layers: [layers.layers[1], layers.layers[0]])).throws<ArgumentError>();
    final AiNativeDrawing ordinary = _drawing(subtreeReorderingSource());
    final List<AiNativeGroup> groups = subtreeReorderingGroups(ordinary);
    for (final List<AiNativeGroup> selection in [
      <AiNativeGroup>[],
      [groups[0], groups[0]],
      [subtreeReorderingGroups(_drawing(subtreeReorderingSource())).first],
    ]) {
      check(() => ordinary.reorderGroups(groups: selection)).throws<ArgumentError>();
    }
    final AiNativeDrawing changed = ordinary.reorderGroups(groups: groups.reversed.toList());
    check(() => changed.reorderGroups(groups: groups)).throws<ArgumentError>();
  });

  test('refuses incomplete pairs and unknown selected body or attached metadata', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource());
    check(() => source.reorderGroups(groups: [source.liveShapes.last.appearanceGroup!, source.liveShapes.first.appearanceGroup!])).throws<UnsupportedError>();
    for (final String text in [
      subtreeReorderingSource().replaceFirst('70 0 m', '17 Future\n70 0 m'),
      subtreeReorderingSource().replaceFirst('/XMLUID : (outer_0) ; (AI10_ArtUID) ,', '/XMLUID : (outer_0) ; (AI10_ArtUID) , 17 /Real (Future) ,'),
    ]) {
      final AiNativeDrawing invalid = _drawing(text);
      check(() => invalid.reorderGroups(groups: subtreeReorderingGroups(invalid).reversed.toList())).throws<UnsupportedError>();
    }
  });

  test('retains the original snapshot when replay would exceed the byte limit', () {
    final String text = subtreeReorderingSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(() => source.reorderGroups(groups: subtreeReorderingGroups(source).reversed.toList())).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });
}
