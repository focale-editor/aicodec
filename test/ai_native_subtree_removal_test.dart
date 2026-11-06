import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath, movementState;
import 'ai_native_objects_test.dart' show objectDictionary;
import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;

/// Supplies nested mixed owners with identified CC metadata in both alternatives.
String subtreeRemovalSource({bool following = false, bool reset = false}) {
  final String text = identifiedShapeLifecycleSource();
  final AiNativeDrawing source = _drawing(text);
  final AiLiveShape first = source.liveShapes.first;
  final AiLiveShape last = source.liveShapes.last;
  final String one = text.substring(first.start, first.end);
  final String two = text.substring(last.start, last.end);
  final String a = movementLayer('A', '0 Ae\nu\nu\n$one\n70 0 m 71 1 L f\nU\n${objectDictionary(identifier: 'inner')}\nU\n${objectDictionary(identifier: 'outer')}');
  final String b = movementLayer('B', movementLayer('B1', 'u\n$two\nU', hidden: true), hidden: true);
  return text.replaceRange(
    first.start,
    last.end,
    '$a\n$b\n${following ? '${reset ? '$movementState 0 1 0 0 0 Xy\n' : ''}90 0 m 91 1 L f\n' : ''}',
  );
}

/// Opens a bounded immutable source before selecting its exact handles.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Selects ordinary group roots without confusing their printing expansions.
List<AiNativeGroup> _roots(AiNativeDrawing drawing) =>
    drawing.groups.where((group) => group.opening.operator == 'u' && group.paths.any((path) => path.isPrivate)).toList()..sort((first, second) => first.start.compareTo(second.start));

/// Retains exact setup and every unselected complete pair.
void _retained(AiNativeDrawing source, AiNativeDrawing result, {int pair = 1}) {
  check(result.liveShapes).length.equals(1);
  final AiLiveShape before = source.liveShapes[pair];
  final AiLiveShape after = result.liveShapes.single;
  check(result.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.records.program.bytes.sublist(before.start, before.end));
  check(result.records.program.bytes.take(result.records.program.bodyStart)).deepEquals(source.records.program.bytes.take(source.records.program.bodyStart));
}

/// Covers full subtree removal, retained dependencies and immutable failures.
void main() {
  test('removes nested groups with paired and ordinary children and all metadata alternatives', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final AiNativeDrawing result = source.removeGroups(groups: [_roots(source).first]);
    check(result.paths).length.equals(4);
    check(result.groups).length.equals(3);
    check(AiNativeStructure.decode(drawing: result).identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(['A', 'B', 'B1']);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'Ae')).isEmpty();
    _retained(source, result);
  });

  test('removes a nested layer subtree with both streams and retained sibling headers', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeLayers result = layers.remove(layers: [layers.layers[1]]);
    check(result.layers.map((layer) => latin1.decode(layer.identifier!.bytes))).deepEquals(['A']);
    check(result.rootCount).equals(1);
    check(result.drawing.paths).length.equals(5);
    check(result.drawing.groups).length.equals(4);
    _retained(source, result.drawing, pair: 0);
  });

  test('removes all selected mixed roots atomically in either selection order', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final List<AiNativeGroup> groups = [_roots(source).first, _roots(source).last];
    for (final List<AiNativeGroup> selection in [groups, groups.reversed.toList()]) {
      final AiNativeDrawing result = source.removeGroups(groups: selection);
      check(result.liveShapes).isEmpty();
      check(result.paths).isEmpty();
      check(result.groups).isEmpty();
      check(result.records.program.layers).length.equals(3);
    }
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeLayers result = layers.remove(layers: layers.layers.where((layer) => layer.parentIndex == null).toList().reversed.toList());
    check(result.layers).isEmpty();
    check(result.drawing.paths).isEmpty();
    check(result.drawing.groups).isEmpty();
    check(result.drawing.liveShapes).isEmpty();
  });

  test('counts unversioned paired metadata once when it also binds to the native path', () {
    final String text = subtreeRemovalSource().replaceAllMapped(
      RegExp(r'%AI17_Begin_Content_if_version_gt:17 4\n([\s\S]*?)%AI17_Alternate_Content[\s\S]*?%AI17_End_Versioned_Content'),
      (match) => match[1]!,
    );
    final AiNativeDrawing source = _drawing(text);
    check(source.liveShapes.first.alternativeDictionaries).isEmpty();
    final AiNativeDrawing result = source.removeGroups(groups: [_roots(source).first]);
    _retained(source, result);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    check(layers.remove(layers: [layers.layers.first]).drawing.liveShapes).length.equals(1);
  });

  test('does not require state read only by ordinary children removed in the same transaction', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    check(() => source.removeLiveShapes(shapes: [source.liveShapes.first])).throws<UnsupportedError>();
    final AiNativeDrawing result = source.removeGroups(groups: [_roots(source)[1]]);
    check(result.paths).length.equals(4);
    check(result.groups).length.equals(4);
    _retained(source, result);
  });

  test('rejects unresolved inherited effects still consumed outside a removed subtree', () {
    final String text = subtreeRemovalSource(following: true);
    final AiNativeDrawing source = _drawing(text);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    check(() => source.removeGroups(groups: [_roots(source).last])).throws<UnsupportedError>();
    check(() => layers.remove(layers: [layers.layers[1]])).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
    final AiNativeDrawing reset = _drawing(subtreeRemovalSource(following: true, reset: true));
    final AiNativeLayers resetLayers = AiNativeLayers.decode(drawing: reset);
    check(resetLayers.remove(layers: [resetLayers.layers[1]]).drawing.paths).length.equals(6);
  });

  test('retains public and private assignments and definite style scalars in order', () {
    final String text = subtreeRemovalSource().replaceFirst('0 0 0 1 k /Def', '2 w 0 0 0 1 k /Def').replaceFirst('%_10 20 m', '%_[3 4] 2 d\n%_10 20 m').replaceFirst('70 0 m', '%_1 D\n70 0 m');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.removeGroups(groups: [_roots(source).first]);
    final String changed = latin1.decode(result.records.program.bytes);
    check(changed).contains('%_[3 4] 2 d');
    check(changed).contains('%_2 w');
    check(changed.indexOf('%_2 w')).isLessThan(changed.indexOf('%_1 D'));
    _retained(source, result);
  });

  test('checks every removed saved alternative identity against opaque references', () {
    for (final String reference in ['author', 'older', 'inner', 'outer', 'A']) {
      final String text = subtreeRemovalSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : ($reference) ; (Reference) , ;\n%%EndSetup');
      final AiNativeDrawing source = _drawing(text);
      final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
      check(() => source.removeGroups(groups: [_roots(source).first])).throws<UnsupportedError>();
      check(() => layers.remove(layers: [layers.layers.first])).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(text);
    }
  });

  test('retains unrelated opaque source when every selected subtree owner is anonymous', () {
    final String text = subtreeRemovalSource().replaceAll(RegExp(r'/XMLUID : \([^)]*\) ; \(AI10_ArtUID\) ,'), '').replaceFirst('%%EndSetup', '/Dictionary : (kept) /String (Unknown) , ;\n%%EndSetup');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.removeGroups(groups: [_roots(source).first]);
    check(latin1.decode(result.records.program.bytes)).contains('/Dictionary : (kept) /String (Unknown) , ;');
    _retained(source, result);
  });

  test('refuses a partial printing group, malformed pairs and unknown subtree attachments', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    check(() => source.removeGroups(groups: [source.liveShapes.first.appearanceGroup!])).throws<UnsupportedError>();
    for (final String text in [
      subtreeRemovalSource().replaceFirst('1 (Shared) XW', '1 (Missing) XW'),
      subtreeRemovalSource().replaceFirst('70 0 m', '17 Future\n70 0 m'),
      subtreeRemovalSource().replaceFirst('70 0 m', '%AI99_Reference: author\n70 0 m'),
      subtreeRemovalSource().replaceFirst('(older)', '(author)'),
    ]) {
      final AiNativeDrawing invalid = _drawing(text);
      final AiNativeLayers layers = AiNativeLayers.decode(drawing: invalid);
      check(() => layers.remove(layers: [layers.layers.first])).throws<UnsupportedError>();
      check(latin1.decode(invalid.records.program.bytes)).equals(text);
    }
  });

  test('rejects empty, duplicate, overlapping, foreign and stale selections', () {
    final AiNativeDrawing source = _drawing(subtreeRemovalSource());
    final List<AiNativeGroup> groups = _roots(source);
    for (final List<AiNativeGroup> selection in [
      <AiNativeGroup>[],
      [groups.first, groups.first],
      [groups.first, groups[1]],
      [_roots(_drawing(subtreeRemovalSource())).first],
    ]) {
      check(() => source.removeGroups(groups: selection)).throws<ArgumentError>();
    }
    final AiNativeDrawing result = source.removeGroups(groups: [groups.first]);
    check(() => result.removeGroups(groups: [groups.last])).throws<ArgumentError>();
  });

  test('preserves source limits and allows editing the retained native shape', () {
    final String text = subtreeRemovalSource();
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    final AiNativeDrawing result = source.removeGroups(groups: [_roots(source).first]);
    check(result.records.program.limits).identicalTo(source.records.program.limits);
    final AiNativeDrawing edited = result.translateLiveShapes(shapes: result.liveShapes, deltaX: 2, deltaY: 3);
    check(edited.liveShapes.single.parameters['ai::Rectangle::CenterX']!.number).equals(8002);
  });

  test('bounds restored style scalars without publishing an oversized replacement', () {
    final String dashes = List.filled(2000, '1').join(' ');
    final String text = subtreeRemovalSource().replaceFirst('0 0 0 1 k /Def', '[$dashes] 0 d 0 0 0 1 k /Def');
    final AiNativeDrawing source = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(() => source.removeGroups(groups: [_roots(source).first])).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('removes mixed and ordinary selected siblings without reinterpreting the latter', () {
    final String text = subtreeRemovalSource().replaceFirst('%%Trailer', 'u ${movementPath(100)} U\n%%Trailer');
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.removeGroups(groups: [_roots(source).first, source.groups.last]);
    check(result.paths).length.equals(4);
    _retained(source, result);
  });
}
