import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_subtree_reordering_test.dart' show subtreeReorderingFlags, subtreeReorderingGroups, subtreeReorderingSource;

/// Supplies nested panel flags, default group styles and changing path opacity.
String get groupMetadataSource => objectSource(
  '0 0.8 0 0 0 Xy\n'
  '1 Ae u\n0 0.25 0 0 0 Xy 0.2 g ${movementPath(10)}\n${objectDictionary()}\n'
  '0 Ae u\n0 0.5 0 0 0 Xy ${movementPath(20)}\n${objectDictionary()}\nU\n${objectDictionary()}\n9 () XW\n'
  '0 0.4 0 0 0 Xy\nU\n${objectDictionary()}\n9 () XW\n'
  '${movementPath(30)}\n0 0.9 0 0 0 Xy 0.7 g\n'
  '0 Ae u ${movementPath(40)}\n${objectDictionary()}\nU\n${objectDictionary()}\n9 () XW\n'
  '${movementPath(50)}',
  setup: '',
);

/// Attaches neutral resets to identified parents containing complete CC pairs.
String groupResetSource() {
  final AiNativeDrawing source = _drawing(subtreeReorderingSource(following: true, reset: true));
  final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
  return latin1.decode(
    AiNativeEditor.apply(
      program: source.records.program,
      edits: [
        for (final AiNativeGroup group in subtreeReorderingGroups(source)) AiSourceEdit(start: objects.forSource(group).end, end: objects.forSource(group).end, bytes: latin1.encode('\n9 () XW\n')),
      ],
    ).bytes,
  );
}

/// Retains nonunit child opacity around an empty reset-owning sibling.
String get groupResetEmptySource => objectSource('0 0.8 0 0 0 Xy u ${movementPath(10)} U\n0 0.2 0 0 0 Xy\n1 Ae u U 9 () XW\n${movementPath(20)}', setup: '');

/// Decodes a complete snapshot under the requested native parser limits.
AiNativeDrawing _drawing(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Reads path order and persistent opacity directly from the native instructions.
List<List<double>> _paths(AiNativeDrawing drawing) {
  final List<List<double>> result = [];
  double? opacity;
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.operator == 'Xy') {
      opacity = item.numbers![1];
    } else if (item.operator == 'm') {
      result.add([item.numbers!.first, opacity!]);
    }
  }
  return result;
}

/// Reads group metadata without mistaking layer panel flags for artwork flags.
List<bool?> _expanded(AiNativeDrawing drawing) => _groups(drawing).map((group) => AiNativeObjects.decode(drawing: drawing).forSource(group).expanded).toList();

/// Orders groups by their opening instruction rather than their closing event.
List<AiNativeGroup> _groups(AiNativeDrawing drawing) => [...drawing.groups]..sort((first, second) => first.start.compareTo(second.start));

/// Checks complete attachments, nested lifecycle, inherited opacity and refusal.
void main() {
  test('owns complete group metadata and immutable source associations', () {
    final AiNativeDrawing source = _drawing(groupMetadataSource);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    check(_expanded(source)).deepEquals([true, false, false]);
    for (final AiNativeGroup group in source.groups) {
      final AiNativeObject object = objects.forSource(group);
      check(object.bindingIssue).isNull();
      check(object.start).equals(object.expansion!.start);
      check(object.end).equals(object.styleApplication!.end);
      check(object.source).identicalTo(group);
      check(object.dictionary!.end < object.styleApplication!.start).isTrue();
      check(object.expansion!.operands.clear).throws<UnsupportedError>();
    }
    check(_paths(source)).deepEquals([
      [10.0, 0.25],
      [20.0, 0.5],
      [30.0, 0.4],
      [40.0, 0.9],
      [50.0, 0.9],
    ]);
  });

  test('copies nested metadata while restoring outgoing opacity', () {
    final AiNativeDrawing source = _drawing(groupMetadataSource);
    final AiNativeDrawing result = source.duplicateGroups(groups: [_groups(source).first]);
    check(_expanded(result)).deepEquals([true, false, true, false, false]);
    check(_paths(result)).deepEquals([
      ...[..._paths(source).take(2)],
      ..._paths(source),
    ]);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'XW')).length.equals(5);
    check(latin1.decode(source.records.program.bytes)).equals(groupMetadataSource);
  });

  test('reorders and relocates complete group metadata across changed opacity', () {
    final AiNativeDrawing source = _drawing(groupMetadataSource);
    final AiNativeDrawing reordered = source.reorderGroups(groups: [source.groups.last, _groups(source).first]);
    check(_expanded(reordered)).deepEquals([false, true, false]);
    check(_paths(reordered)).deepEquals([
      [40.0, 0.9],
      [30.0, 0.4],
      [10.0, 0.25],
      [20.0, 0.5],
      [50.0, 0.9],
    ]);
    final AiNativeDrawing moved = source.moveGroupAfter(group: _groups(source).first, after: source.groups.last);
    check(_expanded(moved)).deepEquals([false, true, false]);
    check(_paths(moved)).deepEquals([
      [30.0, 0.4],
      [40.0, 0.9],
      [10.0, 0.25],
      [20.0, 0.5],
      [50.0, 0.9],
    ]);
  });

  test('removes nested attachments while retaining their outgoing assignments', () {
    final AiNativeDrawing source = _drawing(groupMetadataSource);
    final AiNativeDrawing result = source.removeGroups(groups: [_groups(source).first]);
    check(_expanded(result)).deepEquals([false]);
    check(_paths(result)).deepEquals(_paths(source).skip(2).toList());
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'XW')).length.equals(1);
  });

  test('keeps owner styles through child edits and qualifies following paths', () {
    final AiNativeDrawing source = _drawing(groupMetadataSource);
    final AiNativeDrawing copied = source.duplicatePaths(paths: [source.paths[2]]);
    check(_paths(copied)).deepEquals([..._paths(source).take(3), ..._paths(source).skip(2)]);
    final AiNativeDrawing removed = copied.removePaths(paths: [copied.paths.first]);
    check(_expanded(removed)).deepEquals([true, false, false]);
    final AiNativeDrawing moved = source.movePathAfter(path: source.paths.first, after: source.paths[2], inheritParentFlags: true);
    check(_paths(moved)).deepEquals([
      [20.0, 0.5],
      [30.0, 0.4],
      [10.0, 0.25],
      [40.0, 0.9],
      [50.0, 0.9],
    ]);
    check(moved.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'XW')).length.equals(3);
  });

  test('requires the prefixed group identity as well as descendant identities', () {
    final AiNativeDrawing source = _drawing(
      objectSource(
        '0 1 0 0 0 Xy 1 Ae u ${movementPath(10)}\n${objectDictionary(identifier: 'child')}\nU\n${objectDictionary(identifier: 'parent')}\n9 () XW',
        setup: '',
      ),
    );
    check(() => source.duplicateGroups(groups: source.groups, identifiers: {source.paths.single: latin1.encode('child_copy')})).throws<ArgumentError>();
    final AiNativeDrawing result = source.duplicateGroups(groups: source.groups, identifiers: {source.paths.single: latin1.encode('child_copy'), source.groups.single: latin1.encode('parent_copy')});
    check(AiNativeObjects.decode(drawing: result).objects.map((object) => latin1.decode(object.identifier!.bytes))).deepEquals(['parent', 'child', 'parent_copy', 'child_copy']);
    check(source.removeGroups(groups: source.groups).groups).isEmpty();
  });

  test('dissolves panel flags and neutral resets while retaining child opacity', () {
    final AiNativeDrawing source = _drawing(objectSource('1 Ae u ${movementPath(10)} U\n${objectDictionary()}'));
    final AiNativeDrawing result = source.ungroup(groups: source.groups);
    check(result.groups).isEmpty();
    check(result.items.whereType<AiNativeInstruction>().any((item) => item.operator == 'Ae')).isFalse();
    final AiNativeDrawing styled = _drawing(groupMetadataSource);
    final AiNativeDrawing dissolved = styled.ungroup(groups: [_groups(styled).first]);
    check(_paths(dissolved)).deepEquals(_paths(styled));
    check(dissolved.groups.length).equals(styled.groups.length - 1);
    check(dissolved.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'XW')).length.equals(2);
  });

  test('dissolves disjoint default-style parents while retaining nested reset ownership', () {
    final AiNativeDrawing source = _drawing(groupMetadataSource);
    final List<AiNativeGroup> groups = _groups(source);
    final AiNativeDrawing result = source.ungroup(groups: [groups.first, groups.last]);
    check(_paths(result)).deepEquals(_paths(source));
    check(result.groups).length.equals(1);
    check(AiNativeObjects.decode(drawing: result).forSource(result.groups.single).styleApplication!.operands.first.number).equals(9);
    check(latin1.decode(source.records.program.bytes)).equals(groupMetadataSource);
  });

  test('dissolves empty default-style groups without attaching resets to earlier siblings', () {
    final AiNativeDrawing source = _drawing(groupResetEmptySource);
    final AiNativeDrawing result = source.ungroup(groups: [source.groups.last]);
    check(result.groups).length.equals(1);
    check(AiNativeObjects.decode(drawing: result).forSource(result.groups.single).styleApplication).isNull();
    check(_paths(result)).deepEquals(_paths(source));
    check(result.items.whereType<AiNativeInstruction>().any((item) => item.operator == 'XW')).isFalse();
  });

  test('dissolves mixed default-style parents with exact pairs and retained following state', () {
    final String text = groupResetSource();
    final AiNativeDrawing source = _drawing(text);
    final AiNativeDrawing result = source.ungroup(groups: subtreeReorderingGroups(source), discardMetadata: true);
    check(result.groups.length).equals(source.groups.length - 3);
    check(result.liveShapes).length.equals(3);
    for (final (int, AiLiveShape) entry in source.liveShapes.indexed) {
      final AiLiveShape changed = result.liveShapes[entry.$1];
      check(result.records.program.bytes.sublist(changed.start, changed.end)).deepEquals(source.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    }
    for (final bool private in [false, true]) {
      check(subtreeReorderingFlags(result, private: private)).deepEquals(subtreeReorderingFlags(source, private: private));
    }
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('keeps nondefault, named and private group-style applications rejected on dissolution', () {
    for (final String style in ['1 (Named) XW', '2 () XW', '6 () XW', '7 () XW', '9 (Named) XW', '%_9 () XW', '9 0 XW', '9 () XW 9 () XW']) {
      final String text = objectSource('u ${movementPath(10)} U\n$style', setup: '');
      final AiNativeDrawing source = _drawing(text);
      check(() => source.ungroup(groups: source.groups, discardMetadata: true, inheritParentFlags: true)).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(text);
    }
  });

  test('rejects a default reset inside an enclosing gradient instance atomically', () {
    final String text = objectSource('Bb\n1 (Ink) 0 0 0 100 1 0 0 1 0 0 Bg\n${movementPath(10)}\nu U 9 () XW\n${movementPath(20)}\n0 BB', setup: '');
    final AiNativeDrawing source = _drawing(text);
    check(source.gradients).length.equals(1);
    check(() => source.ungroup(groups: source.groups, inheritParentFlags: true)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });

  test('preserves group metadata and opacity when moving across layer wrappers', () {
    final AiNativeDrawing source = _drawing(
      objectSource('0 0.2 0 0 0 Xy\n${movementLayer('A', '1 Ae u ${movementPath(10)} 0 0.6 0 0 0 Xy U\n${objectDictionary()}\n9 () XW')}\n${movementLayer('B', '0 0.9 0 0 0 Xy ${movementPath(20)}')}'),
    );
    final AiNativeDrawing result = source.moveGroupToLayer(group: source.groups.single, layer: source.records.program.layers.last, inheritParentFlags: true);
    check(_paths(result)).deepEquals([
      [20.0, 0.9],
      [10.0, 0.2],
    ]);
    check(_expanded(result)).deepEquals([true]);
    check(AiNativeLayers.decode(drawing: result).layers.map((layer) => layer.identifier!.bytes))
        .deepEquals(AiNativeLayers.decode(drawing: source).layers.map((layer) => layer.identifier!.bytes).toList());
    final List<AiNativeInstruction> opacity = result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'Xy').toList();
    check(opacity.last.numbers![1]).equals(0.9);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeDrawing reordered = layers.reorder(layers: layers.layers.reversed.toList()).drawing;
    check(_paths(reordered)).deepEquals([
      [20.0, 0.9],
      [10.0, 0.2],
    ]);
    check(_expanded(reordered)).deepEquals([true]);
  });

  test('rejects malformed, private, conditional and repeated attachments atomically', () {
    for (final String body in [
      '2 Ae u U',
      '1 0 Ae u U',
      '%_1 Ae\nu U',
      '1 Ae 0 Ae u U',
      '1 Ae\n%AI8_FutureOwner: 1\nu U',
      '%AI17_Begin_Content_if_version_gt:24 4\n1 Ae\n%AI17_End_Versioned_Content\nu U',
      'u U\n%AI8_FutureOwner: 1\n9 () XW',
      'u U\n%_9 () XW',
      'u U 9 () XW 9 () XW',
      'u U 9 (named) XW',
      'u U 6 () XW',
      'u U 9 0 XW',
    ]) {
      final AiNativeDrawing source = _drawing(objectSource(body));
      check(() => source.duplicateGroups(groups: source.groups)).throws<UnsupportedError>();
      check(() => source.removeGroups(groups: source.groups)).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(objectSource(body));
    }
  });

  test('refuses unqualified opacity layouts and invalid known numeric values', () {
    for (final String state in ['-1 -- 0 0 0 Xy', '16 0.5 0 0 0 Xy', '0 0.5 2 0 0 Xy', '0 0.5 Xy']) {
      final AiNativeDrawing source = _drawing(objectSource('u $state ${movementPath(10)} U'));
      check(() => source.duplicateGroups(groups: source.groups)).throws<UnsupportedError>();
    }
    for (final String state in ['0 -0.1 0 0 0 Xy', '0 1.1 0 0 0 Xy']) {
      final AiNativeDrawing source = _drawing(objectSource('u $state ${movementPath(10)} U'));
      check(() => source.removeGroups(groups: source.groups)).throws<FormatException>();
    }
  });

  test('copies literal blend isolation and knockout settings with their group', () {
    for (final String state in ['1 0.5 0 0 0 Xy', '0 0.5 1 0 0 Xy', '15 0.5 1 2 1 Xy']) {
      final AiNativeDrawing source = _drawing(objectSource('u $state ${movementPath(10)} U'));
      final AiNativeDrawing changed = source.duplicateGroups(groups: source.groups);
      check(changed.groups).length.equals(2);
      for (final AiNativeGroup group in changed.groups) {
        check(changed.records.program.bytes.sublist(group.start, group.end)).deepEquals(source.records.program.bytes.sublist(source.groups.single.start, source.groups.single.end));
      }
    }
  });

  test('refuses relocating artwork whose required opacity is unknown', () {
    final AiNativeDrawing source = _drawing(objectSource('1 Ae u ${movementPath(10)} U 9 () XW 0 0.5 0 0 0 Xy 0 Ae u ${movementPath(20)} U 9 () XW'));
    check(() => source.moveGroupAfter(group: _groups(source).first, after: source.groups.last)).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(objectSource('1 Ae u ${movementPath(10)} U 9 () XW 0 0.5 0 0 0 Xy 0 Ae u ${movementPath(20)} U 9 () XW'));
  });

  test('enforces aggregate byte and token limits after copying attachments', () {
    final AiNativeDrawing bytes = _drawing(groupMetadataSource, limits: AiNativeLimits(maxDecodedBytes: groupMetadataSource.length));
    check(() => bytes.duplicateGroups(groups: [_groups(bytes).first])).throws<FormatException>();
    final int count = AiPostScript.tokenize(latin1.encode(groupMetadataSource)).length;
    final AiNativeDrawing tokens = _drawing(groupMetadataSource, limits: AiNativeLimits(maxTokens: count));
    check(() => tokens.duplicateGroups(groups: [_groups(tokens).first])).throws<AiLimitException>();
  });
}
