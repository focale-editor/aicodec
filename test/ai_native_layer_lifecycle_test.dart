import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Declares all persistent attributes without relying on interpreter defaults.
const String _state = '0 A 0 Xw 0.1 g 0 G 2 w [] 0 d 0 O 0 R 0 XR 0 D 0 Ap 0 J 0 j 10 M';

/// Retains CC wrappers, explicit identity and optional nested ordinary artwork.
String _layer(String name, {String body = '', bool hidden = false}) =>
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

/// Gives independent paths distinct native positions and consumed point counts.
String _path(int position) => '2 As $position 0 m ${position + 1} 1 L S';

/// Removes only the fixture's known identity dictionaries for anonymous cases.
String _anonymous(String source) => source.replaceAll(RegExp(r'%_/ArtDictionary :\n%_/XMLUID : \([^\n]*\) ; \(AI10_ArtUID\) ,\n%_;\n'), '');

/// Uses only qualified declarative owners so identity deletion has no opaque scope.
String get _deletable => '${_layer('A', body: '${_path(10)}\n${_layer('A1', body: '0.7 g 5 w 1 A 1 Xw u ${_path(20)} U')}')}\n${_layer('B', body: _path(30))}\n${_layer('C')}';

/// Includes nested hidden owners, changing state and an unrelated opaque sibling.
String get _body => [
  _layer('A', body: '0.2 g ${_path(10)}\n${_layer('A1', hidden: true, body: '1 A 1 Xw 5 w u ${_path(20)} U')}'),
  _layer('B', hidden: true, body: '0 A 0 Xw 0.7 g 4 w ${_path(30)}\n${_layer('B1', body: 'u ${_path(40)} 0.4 g ${_path(50)} U')}'),
  _layer('C', body: '0.9 g'),
  _layer('Opaque', body: '17 FuturePaint\n/FutureRecord : (opaque) /Data ;'),
].join('\n');

/// Reopens one immutable snapshot with bounded native parsing.
AiNativeLayers _decode(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
    ),
  ),
);

/// Supplies stable declarations and optional explicit initial state.
AiNativeLayers _model({String? body, String state = _state, int roots = 4, String view = '%AI5_OpenViewLayers: 37', AiNativeLimits limits = const AiNativeLimits()}) => _decode(
  '%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%AI5_NumLayers: $roots\n$view\n%%EndComments\n%%EndSetup\n$state\n${body ?? _body}\n%%Trailer\n%%EOF\n',
  limits: limits,
);

/// Selects source handles by their fixture names, without cross-snapshot reuse.
AiNativeLayer _named(AiNativeLayers model, String name) => model.layers.singleWhere((layer) => layer.source.name == name);

/// Observes effective source assignments when each unique ordinary path begins.
Map<double, Map<String, List<String>>> _pathStates(AiNativeLayers model) {
  final Map<String, List<String>> state = {};
  final Map<double, Map<String, List<String>>> result = {};
  for (final AiNativeInstruction item in model.drawing.items.whereType<AiNativeInstruction>()) {
    if (const {'A', 'Xw', 'g', 'G', 'k', 'K', 'Xa', 'XA', 'w', 'd', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'M'}.contains(item.operator)) {
      final String key = const {'g', 'k', 'Xa'}.contains(item.operator)
          ? 'fill'
          : const {'G', 'K', 'XA'}.contains(item.operator)
          ? 'stroke'
          : item.operator;
      state[key] = [item.operator, ...item.operands.map((token) => token.lexeme)];
    } else if (item.operator == 'm') {
      result[item.numbers!.first] = Map.of(state);
    }
  }
  return result;
}

/// Asserts exact identities, child geometry/state and untouched opaque artwork.
void _retained(AiNativeLayers before, AiNativeLayers after) {
  final List<String> names = before.layers.map((layer) => layer.source.name!).toList();
  for (final String name in names) {
    final AiNativeLayer old = _named(before, name);
    final AiNativeLayer changed = _named(after, name);
    check(changed.identifier!.bytes).deepEquals(old.identifier!.bytes);
    check(changed.source.begin.numbers!).deepEquals(old.source.begin.numbers!);
    check(changed.expanded).equals(old.expanded);
  }
  check(_pathStates(after)).deepEquals(_pathStates(before));
  check(after.drawing.paths.length).equals(before.drawing.paths.length);
  check(after.drawing.groups.length).equals(before.drawing.groups.length);
  final AiNativeLayer old = _named(before, 'Opaque');
  final AiNativeLayer changed = _named(after, 'Opaque');
  check(after.drawing.records.program.bytes.sublist(changed.start, changed.end)).deepEquals(before.drawing.records.program.bytes.sublist(old.start, old.end));
}

/// Qualifies subtree moves independently of empty-layer insertion.
void main() {
  test('reorders nonadjacent root slots with nested identities and changing state', () {
    final AiNativeLayers model = _model();
    final AiNativeLayers result = model.reorder(layers: [_named(model, 'C'), _named(model, 'A')], discardViewState: true);
    check(result.layers.map((layer) => layer.source.name)).deepEquals(['C', 'B', 'B1', 'A', 'A1', 'Opaque']);
    check(result.rootCount).equals(4);
    check(result.declaredRootCount).equals(4);
    check(result.viewHeader).isNull();
    _retained(model, result);
    check(model.layers.first.source.name).equals('A');
  });

  test('moves an identified root after another root without changing child ownership', () {
    final AiNativeLayers model = _model();
    final AiNativeLayers result = model.moveAfter(layer: _named(model, 'A'), after: _named(model, 'B'), discardViewState: true);
    check(result.layers.map((layer) => layer.source.name)).deepEquals(['B', 'B1', 'A', 'A1', 'C', 'Opaque']);
    check(result.childrenOf(_named(result, 'A')).single.source.name).equals('A1');
    _retained(model, result);
  });

  test('moves a root into an existing owner with explicit destination inheritance', () {
    final AiNativeLayers model = _model();
    check(() => model.moveInto(layer: _named(model, 'A'), parent: _named(model, 'B'), discardViewState: true)).throws<UnsupportedError>();
    final AiNativeLayers result = model.moveInto(layer: _named(model, 'A'), parent: _named(model, 'B'), inheritParentFlags: true, discardViewState: true);
    check(result.layers.map((layer) => layer.source.name)).deepEquals(['B', 'B1', 'A', 'A1', 'C', 'Opaque']);
    check(result.childrenOf(_named(result, 'B')).map((layer) => layer.source.name)).deepEquals(['B1', 'A']);
    check(result.declaredRootCount).equals(3);
    check(_named(result, 'A').source.visible).isTrue();
    check(_named(result, 'B').source.visible).isFalse();
    _retained(model, result);
  });

  test('appends into an empty destination and preserves the moved descendants', () {
    final AiNativeLayers model = _model();
    final AiNativeLayers result = model.moveInto(layer: _named(model, 'A'), parent: _named(model, 'C'), inheritParentFlags: true, discardViewState: true);
    check(result.childrenOf(_named(result, 'C')).single.source.name).equals('A');
    check(result.childrenOf(_named(result, 'A')).single.source.name).equals('A1');
    check(result.declaredRootCount).equals(3);
    _retained(model, result);
  });

  test('lifts a nested layer after its ancestor and updates only the root count', () {
    final AiNativeLayers model = _model();
    final AiNativeLayers result = model.moveAfter(layer: _named(model, 'A1'), after: _named(model, 'A'), inheritParentFlags: true, discardViewState: true);
    check(_named(result, 'A1').parentIndex).isNull();
    check(result.childrenOf(_named(result, 'A'))).isEmpty();
    check(result.declaredRootCount).equals(5);
    _retained(model, result);
  });

  test('reparents after a nested anchor and supports backwards movement', () {
    final AiNativeLayers model = _model();
    final AiNativeLayers forward = model.moveAfter(layer: _named(model, 'A1'), after: _named(model, 'B1'), inheritParentFlags: true, discardViewState: true);
    check(forward.childrenOf(_named(forward, 'B')).map((layer) => layer.source.name)).deepEquals(['B1', 'A1']);
    _retained(model, forward);
    final AiNativeLayers backward = model.moveInto(layer: _named(model, 'B1'), parent: _named(model, 'A1'), inheritParentFlags: true, discardViewState: true);
    check(backward.childrenOf(_named(backward, 'A1')).single.source.name).equals('B1');
    check(backward.declaredRootCount).equals(4);
    _retained(model, backward);
  });

  test('rejects stale, foreign, duplicate, overlapping and cyclic selections', () {
    final AiNativeLayers model = _model();
    final AiNativeLayer a = _named(model, 'A');
    final AiNativeLayer child = _named(model, 'A1');
    for (final List<AiNativeLayer> layers in <List<AiNativeLayer>>[
      [],
      [a, a],
      [a, child],
      [a, _model().layers.first],
    ]) {
      check(() => model.reorder(layers: layers, discardViewState: true)).throws<ArgumentError>();
    }
    check(() => model.reorder(layers: [child, _named(model, 'B1')], discardViewState: true)).throws<ArgumentError>();
    check(() => model.moveAfter(layer: a, after: a, discardViewState: true)).throws<ArgumentError>();
    check(() => model.moveAfter(layer: a, after: child, inheritParentFlags: true, discardViewState: true)).throws<ArgumentError>();
    check(() => model.moveInto(layer: a, parent: child, inheritParentFlags: true, discardViewState: true)).throws<ArgumentError>();
    final AiNativeLayers result = model.reorder(layers: [_named(model, 'B'), a], discardViewState: true);
    check(() => result.moveAfter(layer: a, after: result.layers.first)).throws<ArgumentError>();
  });

  test('retains no-op snapshots and requires explicit saved-view invalidation', () {
    final AiNativeLayers model = _model();
    check(model.reorder(layers: [_named(model, 'A'), _named(model, 'B')])).identicalTo(model);
    check(() => model.reorder(layers: [_named(model, 'B'), _named(model, 'A')])).throws<UnsupportedError>();
    check(() => model.moveAfter(layer: _named(model, 'A'), after: _named(model, 'B'))).throws<UnsupportedError>();
    final AiNativeLayers stale = _model(roots: 9);
    check(() => stale.moveAfter(layer: stale.layers.first, after: stale.layers.last, discardViewState: true)).throws<FormatException>();
  });

  test('refuses selected or intervening opaque artwork without changing source bytes', () {
    final AiNativeLayers model = _model();
    final List<int> before = model.drawing.records.program.bytes.toList();
    check(() => model.moveAfter(layer: _named(model, 'A'), after: _named(model, 'Opaque'), discardViewState: true)).throws<UnsupportedError>();
    check(() => model.reorder(layers: [_named(model, 'Opaque'), _named(model, 'A')], discardViewState: true)).throws<UnsupportedError>();
    check(model.drawing.records.program.bytes).deepEquals(before);
  });

  test('rejects unknown incoming or outgoing state instead of assuming defaults', () {
    final AiNativeLayers incoming = _model(
      body: '${_layer('A', body: _path(0))}\n${_layer('B', body: '0.7 g ${_path(10)}')}',
      state: '',
      roots: 2,
      view: '',
    );
    check(() => incoming.moveAfter(layer: incoming.layers.first, after: incoming.layers.last)).throws<UnsupportedError>();
    final AiNativeLayers outgoing = _model(
      body: '${_layer('B')}\n${_layer('A', body: '0.7 g ${_path(10)}')}',
      state: '',
      roots: 2,
      view: '',
    );
    check(() => outgoing.moveInto(layer: outgoing.layers.last, parent: outgoing.layers.first, inheritParentFlags: true)).throws<UnsupportedError>();
  });

  test('rejects dependent metadata, malformed assignments and orphan point counts', () {
    for (final String body in ['17 FuturePaint', '2 Ae u U', '3 As', '%AI3_Note: (note)\nu U', '%_0 0 m\n%_1 1 L\n%_S']) {
      final AiNativeLayers model = _model(
        body: '${_layer('A', body: body)}\n${_layer('B')}',
        roots: 2,
        view: '',
      );
      check(() => model.reorder(layers: model.layers.reversed.toList())).throws<UnsupportedError>();
    }
    final AiNativeLayers invalid = _model(
      body: '${_layer('A', body: '-1 w')}\n${_layer('B')}',
      roots: 2,
      view: '',
    );
    check(() => invalid.reorder(layers: invalid.layers.reversed.toList())).throws<FormatException>();
  });

  test('retains classic bare headers without creating identities or declarations', () {
    const String body = '1 1 1 1 0 0 0 79 128 255 Lb (A) Ln 0.2 g 0 0 m 1 1 L S LB\n1 1 1 1 0 0 1 255 79 79 Lb (B) Ln 0.7 g 2 0 m 3 1 L S LB';
    final AiNativeLayers model = _decode('%!PS-Adobe-3.0\n%%EndComments\n%%EndSetup\n$_state\n$body\n%%Trailer\n%%EOF');
    final AiNativeLayers result = model.reorder(layers: model.layers.reversed.toList());
    check(result.layers.map((layer) => layer.source.name)).deepEquals(['B', 'A']);
    check(result.declaredRootCount).isNull();
    check(result.layers.every((layer) => layer.identifier == null && layer.expansion == null && layer.openingComment == null)).isTrue();
    check(_pathStates(result)).deepEquals(_pathStates(model));
  });

  test('preserves process color alternatives and dash state across sibling slots', () {
    final AiNativeLayers model = _model(
      body: '${_layer('A', body: '0 1 0 0 k 0.2 0.3 0.4 XA [2 3] 1 d ${_path(0)}')}\n${_layer('B', body: '0 0 0 0 0.7 0.8 0.9 Xa 0 1 1 0 K [] 0 d ${_path(10)}')}',
      roots: 2,
      view: '',
    );
    final AiNativeLayers result = model.reorder(layers: model.layers.reversed.toList());
    check(_pathStates(result)).deepEquals(_pathStates(model));
    check(_pathStates(result)[0]!['fill']!).deepEquals(['k', '0', '1', '0', '0']);
    check(_pathStates(result)[10]!['stroke']!).deepEquals(['K', '0', '1', '1', '0']);
  });

  test('refuses unresolved prefixes attached before a complete layer wrapper', () {
    for (final String prefix in ['%AI3_Note: (attached)', '/FutureOwner : 7 /Index ;', '17 FuturePrefix']) {
      final AiNativeLayers model = _model(body: '$prefix\n${_layer('A')}\n${_layer('B')}', roots: 2, view: '');
      check(() => model.moveAfter(layer: model.layers.first, after: model.layers.last)).throws<UnsupportedError>();
      check(() => model.reorder(layers: model.layers.reversed.toList())).throws<UnsupportedError>();
    }
  });

  test('bounds generated assignments and keeps input immutable after limit failures', () {
    final AiNativeLayers source = _model();
    final AiNativeLayers limited = _decode(latin1.decode(source.drawing.records.program.bytes), limits: AiNativeLimits(maxDecodedBytes: source.drawing.records.program.bytes.length + 10));
    check(() => limited.moveAfter(layer: limited.layers.first, after: _named(limited, 'B'), discardViewState: true)).throws<FormatException>();
    check(limited.drawing.records.program.bytes).deepEquals(source.drawing.records.program.bytes);
  });

  test('reorders a large immutable layer batch while preserving every source identity', () {
    final AiNativeLayers model = _model(
      body: List.generate(100, (index) => _layer('Layer_$index', body: '${index / 100} g ${_path(index * 2)}')).join('\n'),
      roots: 100,
      view: '',
    );
    final List<AiNativeLayer> selected = model.layers.reversed.toList();
    final AiNativeLayers result = model.reorder(layers: selected);
    selected.clear();
    check(result.layers.map((layer) => layer.source.name)).deepEquals(model.layers.reversed.map((layer) => layer.source.name));
    check(_pathStates(result)).deepEquals(_pathStates(model));
    check(result.declaredRootCount).equals(100);
  });

  test('duplicates complete subtrees with fresh descendant identities and copied names', () {
    final AiNativeLayers model = _model();
    final AiNativeLayer root = _named(model, 'A');
    final AiNativeLayer child = _named(model, 'A1');
    final Map<AiNativeLayer, List<int>> identifiers = {root: latin1.encode('Copy_A'), child: latin1.encode('Copy_A1')};
    final Map<AiNativeLayer, List<int>> names = {root: latin1.encode('A copy'), child: latin1.encode('A1 copy')};
    final AiNativeLayers result = model.duplicate(layers: [root], identifiers: identifiers, names: names, discardViewState: true);
    identifiers[root]![0] = 0;
    names.clear();
    check(result.layers.map((layer) => layer.source.name)).deepEquals(['A', 'A1', 'A copy', 'A1 copy', 'B', 'B1', 'C', 'Opaque']);
    check(result.childrenOf(_named(result, 'A copy')).single.source.name).equals('A1 copy');
    check(_named(result, 'A copy').identifier!.bytes).deepEquals(latin1.encode('Copy_A'));
    check(_named(result, 'A1 copy').identifier!.bytes).deepEquals(latin1.encode('Copy_A1'));
    check(result.declaredRootCount).equals(5);
    check(result.drawing.paths.length).equals(model.drawing.paths.length + 2);
    check(result.drawing.groups.length).equals(model.drawing.groups.length + 1);
    check(_pathStates(result)).deepEquals(_pathStates(model));
    check(_named(result, 'A copy').expanded).equals(root.expanded);
    for (final AiNativeLayer source in model.layers) {
      final AiNativeLayer retained = _named(result, source.source.name!);
      check(result.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(model.drawing.records.program.bytes.sublist(source.start, source.end));
    }
  });

  test('duplicates disjoint nested selections and preserves external identity references', () {
    final AiNativeLayers model = _decode(latin1.decode(_model().drawing.records.program.bytes).replaceFirst('%%EndSetup', '/FutureReference : (A1) /String ;\n%%EndSetup'));
    final AiNativeLayer first = _named(model, 'A1');
    final AiNativeLayer second = _named(model, 'B1');
    final AiNativeLayers result = model.duplicate(
      layers: [second, first],
      identifiers: {first: latin1.encode('Copy_A1'), second: latin1.encode('Copy_B1')},
      discardViewState: true,
    );
    check(result.declaredRootCount).equals(4);
    check(result.childrenOf(_named(result, 'A')).map((layer) => layer.identifier!.bytes)).deepEquals([latin1.encode('A1'), latin1.encode('Copy_A1')]);
    check(result.childrenOf(_named(result, 'B')).map((layer) => layer.identifier!.bytes)).deepEquals([latin1.encode('B1'), latin1.encode('Copy_B1')]);
    check(latin1.decode(result.drawing.records.program.bytes)).contains('/FutureReference : (A1) /String ;');
    check(_pathStates(result)).deepEquals(_pathStates(model));
  });

  test('requires every copied identity and rejects foreign, colliding or extra replacements', () {
    final AiNativeLayers model = _model();
    final AiNativeLayer root = _named(model, 'A');
    final AiNativeLayer child = _named(model, 'A1');
    for (final Map<AiNativeLayer, List<int>> identifiers in <Map<AiNativeLayer, List<int>>>[
      {},
      {root: latin1.encode('Copy')},
      {root: latin1.encode('Copy'), child: latin1.encode('Copy')},
      {root: latin1.encode('B1'), child: latin1.encode('Copy')},
      {root: latin1.encode('bad name'), child: latin1.encode('Copy')},
      {
        root: [256],
        child: latin1.encode('Copy'),
      },
      {root: latin1.encode('Copy'), _model().layers[1]: latin1.encode('Child')},
      {root: latin1.encode('Copy'), child: latin1.encode('Child'), _named(model, 'C'): latin1.encode('Extra')},
    ]) {
      check(() => model.duplicate(layers: [root], identifiers: identifiers, discardViewState: true)).throws<ArgumentError>();
    }
    check(() => model.duplicate(layers: [child], identifiers: {child: latin1.encode('Copy')}, names: {root: []}, discardViewState: true)).throws<ArgumentError>();
    check(
      () => model.duplicate(
        layers: [child],
        identifiers: {child: latin1.encode('Copy')},
        names: {
          child: [-1],
        },
        discardViewState: true,
      ),
    ).throws<ArgumentError>();
  });

  test('duplicates anonymous layers without synthesizing IDs or missing names', () {
    final AiNativeLayers model = _model(body: _anonymous(_deletable), roots: 3, view: '');
    final AiNativeLayers result = model.duplicate(layers: [model.layers.first]);
    check(result.layers.length).equals(model.layers.length + 2);
    check(result.layers.every((layer) => layer.identifier == null && layer.dictionary == null)).isTrue();
    check(_pathStates(result)).deepEquals(_pathStates(model));
    check(() => model.duplicate(layers: [model.layers.first], identifiers: {model.layers.first: latin1.encode('Unexpected')})).throws<ArgumentError>();
    final AiNativeLayers unnamed = _model(body: '1 1 1 1 0 0 0 79 128 255 Lb LB', roots: 1, view: '');
    check(unnamed.duplicate(layers: unnamed.layers).layers.last.nameBytes).isNull();
    check(() => unnamed.duplicate(layers: unnamed.layers, names: {unnamed.layers.first: []})).throws<ArgumentError>();
  });

  test('removes identified subtrees and retains state consumed by following art', () {
    final AiNativeLayers model = _model(body: _deletable, roots: 3);
    final AiNativeLayers result = model.remove(layers: [model.layers.first], discardViewState: true);
    check(result.layers.map((layer) => layer.source.name)).deepEquals(['B', 'C']);
    check(result.declaredRootCount).equals(2);
    check(result.viewHeader).isNull();
    check(result.drawing.groups).isEmpty();
    check(result.drawing.paths).length.equals(1);
    check(_pathStates(result)[30]!).deepEquals(_pathStates(model)[30]!);
    check(result.structure.identifiers.map((identifier) => identifier.bytes)).deepEquals([latin1.encode('B'), latin1.encode('C')]);
    check(model.layers).length.equals(4);
  });

  test('removes nested and all root layers with exact remaining ownership and counts', () {
    final AiNativeLayers model = _model(body: _deletable, roots: 3);
    final AiNativeLayers nested = model.remove(layers: [model.layers[1]], discardViewState: true);
    check(nested.childrenOf(nested.layers.first)).isEmpty();
    check(nested.declaredRootCount).equals(3);
    check(_pathStates(nested)[10]!).deepEquals(_pathStates(model)[10]!);
    check(_pathStates(nested)[30]!).deepEquals(_pathStates(model)[30]!);
    final AiNativeLayers empty = model.remove(layers: model.layers.where((layer) => layer.parentIndex == null).toList(), discardViewState: true);
    check(empty.layers).isEmpty();
    check(empty.declaredRootCount).equals(0);
    check(empty.structure.identifiers).isEmpty();
    check(empty.drawing.paths).isEmpty();
    check(empty.drawing.groups).isEmpty();
  });

  test('rejects identity deletion when opaque or executable reference owners remain', () {
    final AiNativeLayers opaque = _model();
    check(() => opaque.remove(layers: [opaque.layers.first], discardViewState: true)).throws<UnsupportedError>();
    for (final String setup in ['/FutureReference : (A) /String ;', '/FutureReference : <41> /String ;', '/procedure { (A) FutureReference } def', '%AI99_Reference: A', '%%FutureReference: A']) {
      final AiNativeLayers model = _decode(latin1.decode(_model(body: _deletable, roots: 3).drawing.records.program.bytes).replaceFirst('%%EndSetup', '$setup\n%%EndSetup'));
      check(() => model.remove(layers: [model.layers.first], discardViewState: true)).throws<UnsupportedError>();
    }
    final AiNativeLayers duplicate = _model(body: _deletable.replaceFirst('(B) ; (AI10_ArtUID)', '(A) ; (AI10_ArtUID)'), roots: 3);
    check(() => duplicate.remove(layers: [duplicate.layers.first], discardViewState: true)).throws<UnsupportedError>();
  });

  test('removes anonymous subtrees without changing unrelated opaque siblings', () {
    final AiNativeLayers model = _model(body: _anonymous(_body));
    final AiNativeLayer opaque = _named(model, 'Opaque');
    final AiNativeLayers result = model.remove(layers: [model.layers.first], discardViewState: true);
    final AiNativeLayer retained = _named(result, 'Opaque');
    check(result.declaredRootCount).equals(3);
    check(result.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(model.drawing.records.program.bytes.sublist(opaque.start, opaque.end));
    final String anonymousRoot = _body.replaceFirst('%_/ArtDictionary :\n%_/XMLUID : (A) ; (AI10_ArtUID) ,\n%_;\n', '');
    final AiNativeLayers identifiedChild = _model(body: anonymousRoot);
    check(() => identifiedChild.remove(layers: [identifiedChild.layers.first], discardViewState: true)).throws<UnsupportedError>();
  });

  test('keeps copy and deletion selections atomic for invalid handles and opaque art', () {
    final AiNativeLayers model = _model(body: _anonymous(_body));
    final List<int> before = model.drawing.records.program.bytes.toList();
    for (final List<AiNativeLayer> selected in <List<AiNativeLayer>>[
      [],
      [model.layers.first, model.layers.first],
      [model.layers.first, model.layers[1]],
      [_model().layers.first],
    ]) {
      check(() => model.remove(layers: selected, discardViewState: true)).throws<ArgumentError>();
      check(() => model.duplicate(layers: selected, discardViewState: true)).throws<ArgumentError>();
    }
    check(() => model.remove(layers: [_named(model, 'Opaque')], discardViewState: true)).throws<UnsupportedError>();
    check(() => model.duplicate(layers: [_named(model, 'Opaque')], discardViewState: true)).throws<UnsupportedError>();
    check(() => model.remove(layers: [model.layers.first])).throws<UnsupportedError>();
    check(() => model.duplicate(layers: [model.layers.first])).throws<UnsupportedError>();
    check(model.drawing.records.program.bytes).deepEquals(before);
  });

  test('bounds aggregate identity payloads and duplicate output before committing', () {
    final AiNativeLayers source = _model(body: _deletable, roots: 3, view: '');
    final AiNativeLayers limited = _decode(latin1.decode(source.drawing.records.program.bytes), limits: AiNativeLimits(maxDecodedBytes: source.drawing.records.program.bytes.length));
    check(() => limited.duplicate(layers: [limited.layers.last], identifiers: {limited.layers.last: latin1.encode('Copy_C')})).throws<FormatException>();
    check(() => limited.duplicate(layers: [limited.layers.last], identifiers: {limited.layers.last: List.filled(source.drawing.records.program.bytes.length, 65)})).throws<AiLimitException>();
    final int part = source.drawing.records.program.bytes.length ~/ 6;
    check(() => limited.duplicate(layers: [limited.layers.first], identifiers: {limited.layers.first: List.filled(part, 65), limited.layers[1]: List.filled(part, 66)})).throws<AiLimitException>();
    final String projected = latin1.decode(source.drawing.records.program.bytes).replaceAll(RegExp(r'^%_', multiLine: true), '  ');
    final AiNativeLayers tokens = _decode(latin1.decode(source.drawing.records.program.bytes), limits: AiNativeLimits(maxTokens: AiPostScript.tokenize(latin1.encode(projected)).length + 1));
    check(() => tokens.duplicate(layers: [tokens.layers.last], identifiers: {tokens.layers.last: latin1.encode('Copy_C')})).throws<AiLimitException>();
    check(limited.drawing.records.program.bytes).deepEquals(source.drawing.records.program.bytes);
  });
}
