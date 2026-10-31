import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_printing_test.dart' show printingFixture;

/// Builds a source with explicit bounds and an untouched opaque setup record.
AiNativeDrawing _drawing({String body = _body, AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('%!PS-Adobe-3.0\n%%BoundingBox: 0 0 100 100\n%%EndComments\n/FutureSetup : (retained) /Data ;\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'),
      limits: limits,
    ),
  ),
);

/// Keeps object flags, paint and dashes different at successive boundaries.
const String _body = '''0 1 0 1 0 0 1 0 79 128 255 0 50 0 Lb (Hidden locked) Ln
0 AE
0 A 0 Xw 0.1 g 0 G 2 w [] 0 d
u
3 As 0 0 m 10 0 L 10 10 L 0 0 L f
0.7 g 1 A 1 Xw [2 3] 1 d 5 w
u 2 As 20 20 m 30 30 L S U
U
0 A 0 Xw 0.4 g 0 G 2 w [] 0 d
u 40 40 m 50 50 L f 0.9 g 4 w U
60 60 m 70 70 L N
LB''';

/// Finds an owned group by the x coordinate of its first path and path count.
AiNativeGroup _group(AiNativeDrawing drawing, double x, int count) => drawing.groups.singleWhere((group) => group.paths.length == count && group.paths.first.geometry.first.numbers!.first == x);

/// Observes source attribute values at each consumed path without using edits.
List<Map<String, Object>> _painted(AiNativeDrawing drawing) {
  final Map<String, Object> state = {};
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.paint.start: path};
  final List<Map<String, Object>> result = [];
  for (final AiNativeInstruction command in drawing.items.whereType<AiNativeInstruction>()) {
    if (const {'g', 'G', 'k', 'K', 'Xa', 'XA', 'A', 'Xw', 'w', 'd', 'O', 'R', 'XR', 'D', 'Ap', 'J', 'j', 'M'}.contains(command.operator)) {
      final String key = const {'g', 'k', 'Xa'}.contains(command.operator)
          ? 'fill'
          : const {'G', 'K', 'XA'}.contains(command.operator)
          ? 'stroke'
          : command.operator;
      state[key] = [command.operator, ...command.operands.map((operand) => operand.number ?? operand.lexeme)];
    }
    if (paths[command.start] case final AiNativePath path) {
      result.add({...state, 'geometry': path.geometry.map((command) => command.numbers).toList(), 'paint': path.paint.operator});
    }
  }
  return result;
}

/// Checks native group topology, inherited state and atomic source edits.
void main() {
  test('groups consecutive paths with counts and state changes in source order', () {
    final AiNativeDrawing source = _drawing(body: '0 A 0 g\n2 As 0 0 m 1 1 L N\n1 A 0.8 g\n2 2 m 3 3 L S');
    final List<AiNativePath> selected = source.paths.reversed.toList();
    final AiNativeDrawing result = source.groupPaths(paths: selected, inheritParentFlags: true);
    check(result.groups.single.paths).length.equals(2);
    check(_painted(result)).deepEquals(_painted(source));
    check(latin1.decode(result.records.program.bytes)).contains('u\n2 As');
    check(selected.first).identicalTo(source.paths.last);
    check(source.groups).isEmpty();
    final AiNativeDrawing dissolved = result.ungroup(groups: result.groups, inheritParentFlags: true);
    check(dissolved.groups).isEmpty();
    check(_painted(dissolved)).deepEquals(_painted(source));
  });

  test('duplicates nested groups with original incoming flags, fill and dash state', () {
    final AiNativeDrawing source = _drawing();
    final AiNativeGroup outer = _group(source, 0, 2);
    final List<Map<String, Object>> expected = _painted(source);
    final AiNativeDrawing result = source.duplicateGroups(groups: [outer]);
    check(_painted(result)).deepEquals([...expected.take(2), ...expected]);
    check(result.groups).length.equals(5);
    check(result.records.program.layers.single.visible).isFalse();
    check(result.records.program.layers.single.locked).isTrue();
    check(result.records.program.bytes.take(outer.end).toList()).deepEquals(source.records.program.bytes.take(outer.end).toList());
    check(latin1.decode(result.records.program.bytes)).endsWith(latin1.decode(source.records.program.bytes.sublist(outer.end)));
    check(source.paths).length.equals(4);
  });

  test('removes complete subtrees but retains assignments used by following paths', () {
    final AiNativeDrawing source = _drawing(body: '0 A 0 g\nu 0 0 m 1 1 L N 0.7 g 1 A u 2 As 2 2 m 3 3 L S U U\n4 4 m 5 5 L f');
    final AiNativeDrawing result = source.removeGroups(groups: [source.groups.last]);
    check(result.groups).isEmpty();
    check(_painted(result)).deepEquals([_painted(source).last]);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As')).isEmpty();
    check(latin1.decode(result.records.program.bytes)).contains('0.7 g\n1 A');
    check(latin1.decode(result.records.program.bytes)).contains('%%BoundingBox: 0 0 100 100');
  });

  test('ungroups only selected outer boundaries and preserves nested children', () {
    final AiNativeDrawing source = _drawing();
    final AiNativeDrawing result = source.ungroup(groups: [_group(source, 0, 2)]);
    check(result.groups).length.equals(2);
    check(_painted(result)).deepEquals(_painted(source));
    check(result.groups.first.paths.single.geometry.first.numbers!).deepEquals([20.0, 20.0]);
  });

  test('reorders sibling groups while restoring each source-slot outgoing state', () {
    final AiNativeDrawing source = _drawing();
    final AiNativeGroup first = _group(source, 0, 2);
    final AiNativeGroup second = _group(source, 40, 1);
    final List<Map<String, Object>> expected = _painted(source);
    final AiNativeDrawing result = source.reorderGroups(groups: [second, first]);
    check(_painted(result)).deepEquals([expected[2], expected[0], expected[1], expected[3]]);
    check(result.groups).length.equals(source.groups.length);
    check(source.reorderGroups(groups: [first, second])).identicalTo(source);
    check(latin1.decode(result.records.program.bytes)).contains('/FutureSetup : (retained) /Data ;');
  });

  test('moves a group between parents with changed inherited state in both directions', () {
    final AiNativeDrawing source = _drawing(body: '0 A 0 Xw 0.1 g\nu u 0 0 m 1 1 L f 0.2 g U U\n0.7 g\nu u 2 2 m 3 3 L f 0.9 g U U\n4 4 m 5 5 L f');
    final AiNativeGroup first = source.groups[0];
    final AiNativeGroup second = source.groups[2];
    final List<Map<String, Object>> expected = _painted(source);
    final AiNativeDrawing result = source.moveGroupAfter(group: first, after: second);
    check(_painted(result)).deepEquals([expected[1], expected[0], expected[2]]);
    check(result.groups.first.children).isEmpty();
    check(result.groups.last.children).length.equals(2);
    final AiNativeDrawing reverse = source.moveGroupAfter(group: second, after: first);
    check(_painted(reverse)).deepEquals(expected);
    check(reverse.groups.last.children).isEmpty();
    check(reverse.groups[2].children).length.equals(2);
  });

  test('retains empty anonymous owners and state assigned before their first path', () {
    final AiNativeDrawing empty = _drawing(body: '0 A u U');
    check(empty.duplicateGroups(groups: empty.groups).groups).length.equals(2);
    check(empty.removeGroups(groups: empty.groups).groups).isEmpty();
    final AiNativeDrawing source = _drawing(body: 'u 0.7 g 0 0 m 1 1 L f U');
    check(_painted(source.duplicateGroups(groups: source.groups))).deepEquals([..._painted(source), ..._painted(source)]);
  });

  test('replays process color representations and stroke flags without conversion', () {
    final AiNativeDrawing source = _drawing(
      body:
          '0 A 0 Xw 0.1 0.2 0.3 Xa 0 G 0 O 0 R 0 XR 0 D 0 Ap 0 J 0 j 10 M\n'
          'u 0 0 m 1 1 L B\n'
          '0.1 0.2 0.3 0.4 k 0 0 0 1 0.5 0.6 0.7 XA 1 O 1 R 1 XR 1 D 1 Ap 2 J 1 j 20 M\n'
          '2 2 m 3 3 L B U\n4 4 m 5 5 L B',
    );
    final List<Map<String, Object>> expected = _painted(source);
    check(expected.first['fill']).isA<List<Object>>().deepEquals(['Xa', 0.1, 0.2, 0.3]);
    check(expected[1]['stroke']).isA<List<Object>>().deepEquals(['XA', 0, 0, 0, 1, 0.5, 0.6, 0.7]);
    check(_painted(source.duplicateGroups(groups: source.groups))).deepEquals([expected[0], expected[1], expected[0], expected[1], expected[2]]);
    check(_painted(source.removeGroups(groups: source.groups))).deepEquals([expected[2]]);
  });

  test('refuses unknown inherited or outgoing values instead of inventing defaults', () {
    final AiNativeDrawing unknown = _drawing(body: 'u 0 0 m 1 1 L f 0.7 g 2 2 m 3 3 L f U');
    check(() => unknown.duplicateGroups(groups: unknown.groups)).throws<UnsupportedError>();
    final AiNativeDrawing unknownFlags = _drawing(body: 'u 1 A 0 0 m 1 1 L N U');
    check(() => unknownFlags.duplicateGroups(groups: unknownFlags.groups)).throws<UnsupportedError>();
    final AiNativeDrawing source = _drawing(body: 'u 0 0 m 1 1 L N U\n0.2 g\nu 2 2 m 3 3 L f U');
    check(() => source.moveGroupAfter(group: source.groups.last, after: source.groups.first)).throws<UnsupportedError>();
    check(() => source.ungroup(groups: source.groups)).throws<UnsupportedError>();
    check(source.ungroup(groups: source.groups, inheritParentFlags: true).groups).isEmpty();
  });

  test('rejects nonconsecutive paths, different parents and overlapping group selections', () {
    final AiNativeDrawing paths = _drawing(body: '0 0 m 1 1 L N 2 2 m 3 3 L N 4 4 m 5 5 L N');
    check(() => paths.groupPaths(paths: [paths.paths.first, paths.paths.last])).throws<ArgumentError>();
    final AiNativeDrawing source = _drawing();
    check(() => source.groupPaths(paths: source.paths.take(2).toList())).throws<ArgumentError>();
    check(() => source.removeGroups(groups: source.groups.take(2).toList())).throws<ArgumentError>();
    check(() => source.moveGroupAfter(group: source.groups[1], after: source.groups.first)).throws<ArgumentError>();
    check(() => source.reorderGroups(groups: [source.groups[2], source.groups.first])).throws<ArgumentError>();
  });

  test('rejects foreign, duplicate, empty and stale group handles atomically', () {
    final AiNativeDrawing source = _drawing();
    final List<int> original = source.records.program.bytes.toList();
    for (final List<AiNativeGroup> groups in [
      <AiNativeGroup>[],
      [_drawing().groups.first],
      [source.groups.first, source.groups.first],
    ]) {
      check(() => source.duplicateGroups(groups: groups)).throws<ArgumentError>();
      check(() => source.removeGroups(groups: groups)).throws<ArgumentError>();
      check(() => source.ungroup(groups: groups)).throws<ArgumentError>();
      check(() => source.reorderGroups(groups: groups)).throws<ArgumentError>();
    }
    final AiNativeDrawing changed = source.duplicateGroups(groups: [source.groups.first]);
    check(() => changed.removeGroups(groups: [source.groups.first])).throws<ArgumentError>();
    check(source.records.program.bytes).deepEquals(original);
  });

  test('refuses private expansions, compounds, clips, versions and attached metadata', () {
    final AiNativeDrawing printing = printingFixture();
    check(() => printing.removeGroups(groups: [printing.liveShapes.first.appearanceGroup!])).throws<UnsupportedError>();
    for (final String body in [
      '*u 0 0 m 1 1 L N *U',
      'q 0 0 m 1 1 L N Q',
      '%_u 0 0 m 1 1 L N U',
      'u *u 0 0 m 1 1 L N *U U',
      'u 0 0 m 1 1 L N U\n/ArtDictionary : /XMLUID : (owned) ; (AI10_ArtUID) , ;',
      'u 0 0 m 1 1 L N U\n0 A\n/AdobeURL (https://example.test) XT',
      '%AI17_Begin_Content_if_version_gt:24 4\nu 0 0 m 1 1 L N U\n%AI17_End_Versioned_Content',
      '%AI3_Note: native note\nu U',
      '%AI8_FutureOwner: 1\nu U',
      'u U\n%AI8_FutureOwner: 1\n0 A\n0 0 m 1 1 L N',
      '2 Ae u 0 0 m 1 1 L N U',
      '17 FuturePaint u U',
      'u 2 As U',
    ]) {
      final AiNativeDrawing source = _drawing(body: body);
      check(() => source.removeGroups(groups: [source.groups.last])).throws<UnsupportedError>();
      check(() => source.ungroup(groups: [source.groups.last])).throws<UnsupportedError>();
    }
  });

  test('rejects malformed attributes and preserves an entire failed batch', () {
    for (final String assignment in ['2 g', '2 A', '-1 w', '[0 0] 0 d', '[-2 3] 0 d', '0 0 Xa']) {
      final AiNativeDrawing source = _drawing(body: 'u 0 0 m 1 1 L N U u $assignment 2 2 m 3 3 L N U');
      final List<int> before = source.records.program.bytes.toList();
      check(() => source.removeGroups(groups: source.groups)).throws<FormatException>();
      check(source.records.program.bytes).deepEquals(before);
    }
  });

  test('preserves opaque siblings but refuses moving across unknown data or layer boundaries', () {
    final AiNativeDrawing source = _drawing(body: 'u 0 0 m 1 1 L N U\n2 2 m 3 3 L N\n/FutureObject : 7 /Data ;');
    final AiNativeDrawing result = source.removeGroups(groups: source.groups);
    check(latin1.decode(result.records.program.bytes)).endsWith('2 2 m 3 3 L N\n/FutureObject : 7 /Data ;\n%%Trailer\n%%EOF\n');
    final AiNativeDrawing crossed = _drawing(body: 'u 0 0 m 1 1 L N U\n2 2 m 3 3 L N\n/FutureObject : 7 /Data ;\n4 4 m 5 5 L N\nu 6 6 m 7 7 L N U');
    check(() => crossed.moveGroupAfter(group: crossed.groups.first, after: crossed.groups.last)).throws<UnsupportedError>();
    const String layer = '1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb';
    final AiNativeDrawing layers = _drawing(body: '$layer u 0 0 m 1 1 L N U LB $layer u 2 2 m 3 3 L N U LB');
    check(() => layers.moveGroupAfter(group: layers.groups.first, after: layers.groups.last)).throws<UnsupportedError>();
  });

  test('keeps output and aggregate parser budgets in force', () {
    const String body = 'u 0 0 m 1 1 L N U';
    final AiNativeDrawing baseline = _drawing(body: body);
    final int tokens = AiPostScript.tokenize(baseline.records.program.bytes).length;
    final AiNativeDrawing source = _drawing(
      body: body,
      limits: AiNativeLimits(maxTokens: tokens + 1),
    );
    check(() => source.duplicateGroups(groups: source.groups)).throws<AiLimitException>();
    final AiNativeDrawing small = _drawing(
      body: body,
      limits: AiNativeLimits(maxDecodedBytes: baseline.records.program.bytes.length + 1),
    );
    check(() => small.duplicateGroups(groups: small.groups)).throws<FormatException>();
    final StringBuffer repeated = StringBuffer('[${List.filled(200, '1').join(' ')}] 0 d\n');
    for (int index = 0; index < 40; index++) {
      if (index == 20) {
        repeated.writeln('[] 0 d');
      }
      repeated.writeln('u $index 0 m $index 1 L S U');
    }
    final AiNativeDrawing reference = _drawing(body: repeated.toString());
    final AiNativeDrawing bounded = _drawing(
      body: repeated.toString(),
      limits: AiNativeLimits(maxDecodedBytes: reference.records.program.bytes.length + 100),
    );
    check(() => bounded.reorderGroups(groups: bounded.groups.reversed.toList())).throws<AiLimitException>();
    check(bounded.records.program.bytes).deepEquals(reference.records.program.bytes);
  });

  test('reorders and duplicates a large batch with distinct paints and stable source slots', () {
    final StringBuffer body = StringBuffer('0 A 0 Xw 0 g\n');
    for (int index = 0; index < 200; index++) {
      body.writeln('u $index 0 m ${index + 1} 1 L f ${index / 200} g U');
    }
    body.writeln('1000 0 m 1001 1 L f');
    final AiNativeDrawing source = _drawing(body: body.toString());
    final List<Map<String, Object>> expected = _painted(source);
    final AiNativeDrawing reordered = source.reorderGroups(groups: source.groups.reversed.toList());
    check(_painted(reordered)).deepEquals([...expected.take(200).toList().reversed, expected.last]);
    final AiNativeDrawing duplicated = source.duplicateGroups(groups: source.groups);
    check(_painted(duplicated)).deepEquals([
      for (final Map<String, Object> path in expected.take(200)) ...[path, path],
      expected.last,
    ]);
    check(source.groups).length.equals(200);
  });
}
