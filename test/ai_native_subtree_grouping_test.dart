import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_shape_reordering_test.dart' show shapeReorderingSource;
import 'ai_native_subtree_reordering_test.dart' show subtreeReorderingFlags, subtreeReorderingGroups, subtreeReorderingSource;

/// Opens exact source under the same bounded parser used by public transactions.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Supplies a group, an ordinary counted path and complete CC pairs as siblings.
String subtreeGroupingSource() {
  final String text = shapeReorderingSource();
  final AiLiveShape first = _drawing(text).liveShapes.first;
  return text.replaceRange(
    first.start,
    first.end,
    'u\n${text.substring(first.start, first.end)}\nU\n${objectDictionary(identifier: 'parent', name: 'Mixed')}\n2 As 70 0 m 71 1 L S\n${objectDictionary(identifier: 'ordinary')}',
  );
}

/// Locates the source-first enclosing group independently of traversal order.
AiNativeGroup _outer(AiNativeDrawing drawing) => (drawing.groups.toList()..sort((first, second) => first.start.compareTo(second.start))).first;

/// Observes identities and local flags without assuming equal parent topology.
void _retained(AiNativeDrawing source, AiNativeDrawing result, {Set<String> removed = const {}}) {
  check(result.paths.length).equals(source.paths.length);
  check(result.liveShapes.length).equals(source.liveShapes.length);
  check(AiNativeStructure.decode(drawing: result).identifiers.map((identity) => latin1.decode(identity.bytes)))
      .deepEquals(AiNativeStructure.decode(drawing: source).identifiers.map((identity) => latin1.decode(identity.bytes)).where((name) => !removed.contains(name)).toList());
  for (final bool private in [false, true]) {
    check(subtreeReorderingFlags(result, private: private)).deepEquals(subtreeReorderingFlags(source, private: private));
  }
  for (final (int, AiLiveShape) entry in source.liveShapes.indexed) {
    final AiLiveShape after = result.liveShapes[entry.$1];
    check(result.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
  }
}

/// Checks mixed selection, metadata disposal and deliberate parent inheritance.
void main() {
  test('groups consecutive complete pairs and dissolves only their new parent', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    final AiNativeDrawing grouped = source.groupArtwork(liveShapes: source.liveShapes.take(2).toList().reversed.toList());
    check(grouped.groups.length).equals(source.groups.length + 1);
    _retained(source, grouped);
    final AiNativeDrawing result = grouped.ungroup(groups: [_outer(grouped)]);
    check(result.groups.length).equals(source.groups.length);
    _retained(source, result);
  });

  test('groups paths, groups and pairs together in source order with point counts', () {
    final AiNativeDrawing source = _drawing(subtreeGroupingSource());
    final AiNativeGroup parent = subtreeReorderingGroups(source, prefix: 'parent').single;
    final AiNativePath path = source.paths.singleWhere((path) => path.geometry.first.numbers!.first == 70);
    final AiNativeDrawing result = source.groupArtwork(groups: [parent], paths: [path], liveShapes: [source.liveShapes[1]]);
    check(_outer(result).children).length.equals(4);
    check(latin1.decode(result.records.program.bytes)).contains('2 As 70 0 m 71 1 L S');
    _retained(source, result);
  });

  test('groups complete nested subtrees and retains all descendant identities', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource());
    final AiNativeDrawing result = source.groupArtwork(groups: subtreeReorderingGroups(source).reversed.toList());
    _retained(source, result);
    check(_outer(result).children).length.equals(3);
  });

  test('dissolves identified mixed parents only with explicit metadata disposal', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource());
    final List<AiNativeGroup> groups = subtreeReorderingGroups(source);
    check(() => source.ungroup(groups: groups)).throws<UnsupportedError>();
    final AiNativeDrawing result = source.ungroup(groups: groups, discardMetadata: true);
    _retained(source, result, removed: {'outer_0', 'outer_1', 'outer_2'});
    check(result.groups.length).equals(source.groups.length - 3);
    check(subtreeReorderingGroups(result, prefix: 'inner_')).length.equals(3);
  });

  test('deletes only parent identities while preserving descendant aliases', () {
    final AiNativeDrawing source = _drawing(subtreeReorderingSource().replaceFirst('(author_1)', '(author_0)'));
    final AiNativeDrawing result = source.ungroup(groups: [subtreeReorderingGroups(source).first], discardMetadata: true);
    _retained(source, result, removed: {'outer_0'});
    final AiNativeDrawing aliases = _drawing(subtreeReorderingSource().replaceFirst('(outer_1)', '(outer_0)'));
    check(() => aliases.ungroup(groups: [subtreeReorderingGroups(aliases).first], discardMetadata: true)).throws<UnsupportedError>();
  });

  test('preserves opaque external references on grouping but refuses identity disposal', () {
    final String text = subtreeReorderingSource().replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (outer_0) ; (Reference) , ;\n%%EndSetup');
    final AiNativeDrawing source = _drawing(text);
    _retained(source, source.groupArtwork(groups: subtreeReorderingGroups(source)));
    check(() => source.ungroup(groups: [subtreeReorderingGroups(source).first], discardMetadata: true)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('requires explicit inheritance for unknown or non-neutral native and printing flags', () {
    for (final String prefix in ['1 A', '%_1 A', '1 Xw', '%_1 Xw', '']) {
      final String text = shapeReorderingSource().replaceFirst('0 A 0 Xw ', '$prefix ');
      final AiNativeDrawing source = _drawing(text);
      check(() => source.groupArtwork(liveShapes: source.liveShapes)).throws<UnsupportedError>();
      final AiNativeDrawing grouped = source.groupArtwork(liveShapes: source.liveShapes, inheritParentFlags: true);
      _retained(source, grouped);
      check(() => grouped.ungroup(groups: [_outer(grouped)])).throws<UnsupportedError>();
      _retained(source, grouped.ungroup(groups: [_outer(grouped)], inheritParentFlags: true));
    }
  });

  test('refuses incomplete pairs, skipped siblings and overlapping selections', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    check(() => source.groupArtwork(paths: [source.liveShapes.first.path!])).throws<UnsupportedError>();
    check(() => source.groupArtwork(groups: [source.liveShapes.first.appearanceGroup!])).throws<UnsupportedError>();
    check(() => source.ungroup(groups: [source.liveShapes.first.appearanceGroup!], discardMetadata: true)).throws<UnsupportedError>();
    check(() => source.groupArtwork(liveShapes: [source.liveShapes.first, source.liveShapes.last])).throws<UnsupportedError>();
    final AiNativeDrawing nested = _drawing(subtreeReorderingSource());
    check(() => nested.groupArtwork(groups: [subtreeReorderingGroups(nested).first], liveShapes: [nested.liveShapes.first])).throws<ArgumentError>();
    check(() => nested.groupArtwork(liveShapes: [nested.liveShapes.first, nested.liveShapes.last])).throws<ArgumentError>();
  });

  test('rejects foreign, repeated, stale and empty handles without source mutation', () {
    final AiNativeDrawing source = _drawing(shapeReorderingSource());
    final AiLiveShape first = source.liveShapes.first;
    for (final List<AiLiveShape> shapes in [
      <AiLiveShape>[],
      [first, first],
      [_drawing(shapeReorderingSource()).liveShapes.first],
    ]) {
      check(() => source.groupArtwork(liveShapes: shapes)).throws<ArgumentError>();
    }
    final AiNativeDrawing grouped = source.groupArtwork(liveShapes: source.liveShapes);
    check(() => grouped.groupArtwork(liveShapes: [first])).throws<ArgumentError>();
    check(latin1.decode(source.records.program.bytes)).equals(shapeReorderingSource());
  });

  test('retains applied styles and rejects unknown parent metadata even with disposal', () {
    for (final String suffix in ['6 () XW', objectDictionary(extra: '(opaque) /String (Future) ,')]) {
      final AiNativeDrawing source = _drawing(objectSource('u 0 0 m 1 1 L f U\n$suffix', setup: ''));
      check(() => source.ungroup(groups: source.groups, discardMetadata: true)).throws<UnsupportedError>();
    }
  });

  test('dissolves qualified named and rotated ordinary parents without changing children', () {
    final AiNativeDrawing source = _drawing(
      objectSource(
        'u 0 0 m 1 1 L f U\n${objectDictionary(name: 'Parent', extra: '(0.5) /String (BBAccumRotation) ,')}',
        setup: '',
      ),
    );
    final AiNativeDrawing result = source.ungroup(groups: source.groups, discardMetadata: true);
    check(result.groups).isEmpty();
    check(result.paths).length.equals(1);
    check(result.records.containers).isEmpty();
  });

  test('keeps aggregate parser and output ceilings during group creation', () {
    final String text = shapeReorderingSource();
    final AiNativeDrawing bytes = _drawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length + 1));
    check(() => bytes.groupArtwork(liveShapes: bytes.liveShapes)).throws<FormatException>();
    final String plain = objectSource('0 0 m 1 1 L N', setup: '');
    final int tokens = AiPostScript.tokenize(latin1.encode(plain)).length;
    final AiNativeDrawing bounded = _drawing(plain, limits: AiNativeLimits(maxTokens: tokens + 1));
    check(() => bounded.groupArtwork(paths: bounded.paths)).throws<AiLimitException>();
  });
}
