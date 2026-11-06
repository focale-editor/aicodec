import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;
import 'ai_native_shape_reordering_test.dart' show shapeReorderingSource;

/// Opens a source snapshot with optional resource ceilings.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Supplies three complete pairs in ordinary groups and optional identified layers.
String shapeMovementSource({bool layers = true, String targetFlags = ''}) {
  final String text = shapeReorderingSource();
  final AiNativeDrawing drawing = _drawing(text);
  final List<String> pairs = [
    for (final (int, AiLiveShape) entry in drawing.liveShapes.indexed)
      '0 ${0.2 + entry.$1 * 0.2} 0 0 0 Xy\n%_0 ${0.3 + entry.$1 * 0.2} 0 0 0 Xy\n${entry.$1 % 2} D\n%_${1 - entry.$1 % 2} D\n${text.substring(entry.$2.start, entry.$2.end)}',
  ];
  final String first = 'u\n${pairs[0]}\nU\nu\n${pairs[1]}\nU';
  final String second = '$targetFlags\nu\n${pairs[2]}\nU\nu U';
  return text.replaceRange(
    drawing.liveShapes.first.start,
    drawing.liveShapes.last.end,
    layers ? '${movementLayer('A', first)}\n${movementLayer('B', second, hidden: true)}\n${movementLayer('Empty', '')}' : '$first\n$second',
  );
}

/// Resolves the ordinary immediate parent separately from the printing expansion.
AiNativeGroup _parent(AiNativeDrawing drawing, int shape) {
  final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
  return structure.parentOf(structure.nodeFor(drawing.liveShapes[shape].appearanceGroup!))!.source as AiNativeGroup;
}

/// Captures flags and opacity at each distinct contour in either interpretation.
List<List<Object?>> _inputs(AiNativeDrawing drawing, {required bool private}) {
  final Map<String, List<double>?> values = {};
  final List<List<Object?>> result = [];
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.isPrivate && !private) {
      continue;
    }
    if (const {'A', 'Xw', 'D', 'Ap', 'XR', 'Xy'}.contains(item.operator)) {
      values[item.operator] = item.numbers;
    } else if (item.operator == 'm') {
      result.add([
        item.isPrivate,
        item.numbers!.first,
        for (final String key in ['A', 'Xw', 'D', 'Ap', 'XR', 'Xy']) values[key],
      ]);
    }
  }
  return result;
}

/// Checks retained complete pair bytes, both input states and layer headers.
void _retained(AiNativeDrawing source, AiNativeDrawing result, List<int> order) {
  check(result.paths).length.equals(source.paths.length);
  check(result.groups).length.equals(source.groups.length);
  check(result.liveShapes).length.equals(source.liveShapes.length);
  for (final (int, int) entry in order.indexed) {
    final AiLiveShape before = source.liveShapes[entry.$2];
    final AiLiveShape after = result.liveShapes[entry.$1];
    check(result.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.records.program.bytes.sublist(before.start, before.end));
  }
  for (final bool private in [false, true]) {
    final List<List<Object?>> original = _inputs(source, private: private);
    final int count = private ? 4 : 3;
    check(_inputs(result, private: private)).deepEquals([for (final int index in order) ...original.sublist(index * count, (index + 1) * count)]);
  }
  final AiNativeLayers before = AiNativeLayers.decode(drawing: source);
  final AiNativeLayers after = AiNativeLayers.decode(drawing: result);
  for (final (int, AiNativeLayer) entry in before.layers.indexed) {
    final AiNativeLayer changed = after.layers[entry.$1];
    check(changed.parentIndex).equals(entry.$2.parentIndex);
    check(result.records.program.bytes.sublist(changed.start, changed.bodyStart)).deepEquals(source.records.program.bytes.sublist(entry.$2.start, entry.$2.bodyStart));
  }
}

/// Qualifies exact pair moves, explicit inheritance, dependent state and failures.
void main() {
  test('moves complete sibling pairs forward and backward with both input states', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    _retained(source, source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last), [1, 2, 0]);
    _retained(source, source.moveLiveShapeAfter(shape: source.liveShapes.last, after: source.liveShapes.first), [0, 2, 1]);
  });

  test('moves between groups with matching inherited flags without an opt-in', () {
    final AiNativeDrawing source = _drawing(shapeMovementSource(layers: false));
    final AiNativeDrawing result = source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last);
    check(_parent(result, 1)).identicalTo(_parent(result, 2));
    _retained(source, result, [1, 2, 0]);
  });

  test('requires explicit inheritance for cross-layer movement and preserves headers', () {
    final AiNativeDrawing source = _drawing(shapeMovementSource());
    check(() => source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last)).throws<UnsupportedError>();
    final AiNativeDrawing result = source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last, inheritParentFlags: true);
    check(_parent(result, 1)).identicalTo(_parent(result, 2));
    _retained(source, result, [1, 2, 0]);
  });

  test('appends to an empty group while leaving its boundaries and panel unchanged', () {
    final AiNativeDrawing source = _drawing(shapeMovementSource(layers: false));
    final AiNativeGroup empty = source.groups.singleWhere((group) => group.paths.isEmpty);
    final AiNativeDrawing result = source.moveLiveShapeToGroup(shape: source.liveShapes.first, group: empty);
    check(_parent(result, 2)).identicalTo(result.groups.lastWhere((group) => group.paths.any((path) => path.isPrivate)));
    _retained(source, result, [1, 2, 0]);
  });

  test('lifts to a containing or empty layer only with explicit ancestor inheritance', () {
    final AiNativeDrawing source = _drawing(shapeMovementSource());
    for (final AiLayer layer in [source.records.program.layers.first, source.records.program.layers.last]) {
      check(() => source.moveLiveShapeToLayer(shape: source.liveShapes.first, layer: layer)).throws<UnsupportedError>();
      final AiNativeDrawing result = source.moveLiveShapeToLayer(shape: source.liveShapes.first, layer: layer, inheritParentFlags: true);
      final List<int> order = identical(layer, source.records.program.layers.first) ? [1, 0, 2] : [1, 2, 0];
      final AiNativeStructure structure = AiNativeStructure.decode(drawing: result);
      check(structure.parentOf(structure.nodeFor(result.liveShapes[order.indexOf(0)].appearanceGroup!))!.kind).equals(AiNativeStructureKind.layer);
      _retained(source, result, order);
    }
  });

  test('compares ancestor flags in both printing and private interpretations', () {
    for (final String flags in ['1 A 1 Xw', '%_1 A\n%_1 Xw']) {
      final AiNativeDrawing source = _drawing(shapeMovementSource(layers: false, targetFlags: flags));
      check(() => source.moveLiveShapeToGroup(shape: source.liveShapes.first, group: _parent(source, 2))).throws<UnsupportedError>();
      final AiNativeDrawing result = source.moveLiveShapeToGroup(shape: source.liveShapes.first, group: _parent(source, 2), inheritParentFlags: true);
      _retained(source, result, [1, 2, 0]);
    }
  });

  test('retains metadata alternatives, opaque external references and outer expansion flags', () {
    final String text = shapeReorderingSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (author_0) ; (Reference) , ;\n%%EndSetup').replaceFirst('\nu\n', '\n0 Ae\nu\n');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last);
    check(AiNativeObjects.decode(drawing: result).forSource(result.liveShapes.last.appearanceGroup!).expanded).equals(false);
    check(latin1.decode(result.records.program.bytes)).contains('/XMLUID : (author_0) ; (Reference) ,');
    check(AiNativeStructure.decode(drawing: result).identifiers.map((identity) => latin1.decode(identity.bytes))).deepEquals(['author_1', 'older_1', 'author_2', 'older_2', 'author_0', 'older_0']);
    _retained(source, result, [1, 2, 0]);
  });

  test('rejects printing, compound and foreign group destinations', () {
    final AiNativeDrawing source = _drawing(shapeMovementSource());
    check(() => source.moveLiveShapeToGroup(shape: source.liveShapes.first, group: source.liveShapes.last.appearanceGroup!, inheritParentFlags: true)).throws<UnsupportedError>();
    final AiNativeGroup compound = source.groups.firstWhere((group) => group.opening.operator == '*u');
    check(() => source.moveLiveShapeToGroup(shape: source.liveShapes.last, group: compound, inheritParentFlags: true)).throws<UnsupportedError>();
    check(() => source.moveLiveShapeToGroup(shape: source.liveShapes.first, group: _parent(_drawing(shapeMovementSource()), 0))).throws<ArgumentError>();
  });

  test('rejects self anchors and foreign or stale source and layer handles', () {
    final AiNativeDrawing source = _drawing(shapeMovementSource());
    final AiNativeDrawing foreign = _drawing(shapeMovementSource());
    check(() => source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.first)).throws<ArgumentError>();
    check(() => source.moveLiveShapeAfter(shape: foreign.liveShapes.first, after: source.liveShapes.first)).throws<ArgumentError>();
    check(() => source.moveLiveShapeToLayer(shape: source.liveShapes.first, layer: foreign.records.program.layers.last, inheritParentFlags: true)).throws<ArgumentError>();
    final AiNativeDrawing result = source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes[1]);
    check(() => result.moveLiveShapeAfter(shape: source.liveShapes.first, after: result.liveShapes.first)).throws<ArgumentError>();
  });

  test('does not replace an unknown incoming attribute with a later assignment', () {
    final AiNativeDrawing source = _drawing(identifiedShapeLifecycleSource().replaceFirst('0 D ', '').replaceFirst('*u', '1 D\n*u'));
    check(() => source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last)).throws<UnsupportedError>();
  });

  test('checks following native dependencies at both the source and destination', () {
    for (final bool reset in [false, true]) {
      final String text = shapeReorderingSource().replaceFirst('%%Trailer', '${reset ? '0.7 g\n' : ''}70 70 m 80 80 L f\n%%Trailer');
      final AiNativeDrawing source = _drawing(text);
      for (final bool forward in [false, true]) {
        final AiLiveShape moved = forward ? source.liveShapes.first : source.liveShapes.last;
        final AiLiveShape anchor = forward ? source.liveShapes.last : source.liveShapes.first;
        if (reset) {
          check(source.moveLiveShapeAfter(shape: moved, after: anchor).paths).length.equals(13);
        } else {
          check(() => source.moveLiveShapeAfter(shape: moved, after: anchor)).throws<UnsupportedError>();
        }
      }
    }
  });

  test('retains unknown input provenance without introducing default flags', () {
    final AiNativeDrawing source = _drawing(identifiedShapeLifecycleSource().replaceFirst('0 A 0 Xw ', ''));
    final AiNativeDrawing result = source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last);
    check(result.items.whereType<AiNativeInstruction>().where((item) => const {'A', 'Xw'}.contains(item.operator))).isEmpty();
  });

  test('does not let private restoration mask a changed printing dependency at insertion', () {
    final String text = identifiedShapeLifecycleSource().replaceFirst('0 G ', '');
    final AiLiveShape first = _drawing(text).liveShapes.first;
    final AiNativeDrawing source = _drawing(
      '${text.substring(0, first.end)}\n%_0 G\n70 70 m 80 80 L s\n'
      '${text.substring(first.end).replaceFirst('\nu\n', '\nu\n1 G\n')}',
    );
    check(() => source.moveLiveShapeAfter(shape: source.liveShapes.last, after: source.liveShapes.first))
        .throws<UnsupportedError>()
        .has((error) => error.message, 'message')
        .isNotNull()
        .contains('unresolved printing state: stroke');
  });

  test('rejects malformed destination boundaries without changing the snapshot', () {
    final String text = shapeMovementSource(layers: false).replaceFirst('u U', 'u 3 U');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeGroup empty = source.groups.singleWhere((group) => group.paths.isEmpty);
    check(() => source.moveLiveShapeToGroup(shape: source.liveShapes.first, group: empty)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('bounds replay token growth under the owning native parser limit', () {
    final String text = shapeReorderingSource();
    final int tokens = AiPostScript.tokenize(latin1.encode(text.replaceAll(RegExp(r'^%_', multiLine: true), ''))).length;
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxTokens: tokens));
    check(() => source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last)).throws<FormatException>();
  });

  test('bounds added state under the original byte budget and leaves failures immutable', () {
    final String text = shapeReorderingSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(() => source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last)).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('reports movement as a source-qualified operation', () {
    final AiNativeSource source = AiNativeData.extract(const AiCodec().decode(latin1.encode(shapeReorderingSource()))).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    for (final AiNativeCapability finding in report.findings.where((finding) => finding.feature == .liveShape)) {
      check(finding.edits.singleWhere((edit) => edit.operation == .liveShapeReparenting).support).equals(AiNativeEditSupport.requiresValidation);
    }
  });
}
