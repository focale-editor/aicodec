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
    for (final String body in ['17 FuturePaint', '1 Ae u U', '3 As', '%AI3_Note: (note)\nu U', '%_0 0 m\n%_1 1 L\n%_S']) {
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
}
