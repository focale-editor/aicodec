import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_printing_test.dart' show printingFixture;

/// Changes printing topology while returning to the original fill assignment.
const String _group = '''u
u
1 0 0 0 k
0 0 m 10 0 L 10 10 L f
U
0 0 0 1 k
20 20 m 30 20 L 30 30 L F
U''';

/// Declares an existing gradient independently of the attachment API.
const String _gradient = '''%AI5_BeginGradient: (Ink)
(Ink) 0 2 Bd
[
%_1 0 50 100 Bs
%_0 0 50 0 Bs
BD
%AI5_EndGradient
''';

/// Supplies a complete group against one current source handle.
AiNativePrintingGroupReplacement _replacement(AiLiveShape shape, {String group = _group}) => AiNativePrintingGroupReplacement(
  shape: shape,
  bytes: latin1.encode(group),
  bounds: AiBoundingBox(left: -10, bottom: -20, right: 120, top: 140),
);

/// Returns exact bytes outside the selected derived representation.
List<int> _following(AiNativeDrawing drawing, int shapeIndex) => drawing.records.program.bytes.sublist(drawing.liveShapes[shapeIndex].appearanceGroup!.end);

/// Qualifies full-group ownership, outgoing state and supplied resource use.
void main() {
  test('restores known inherited paint after introducing local printing assignments', () {
    final AiNativeDrawing source = printingFixture(group: '0 g\nu\n0 0 m 10 0 L 10 10 L f\nU');
    final AiNativeDrawing changed = source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: 'u\n1 g\n0 0 m 10 0 L 10 10 L f\n0 g\nU')]);
    check(changed.liveShapes).length.equals(source.liveShapes.length);
    check(_following(changed, 0)).deepEquals(_following(source, 0));
    check(() => source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: 'u\n1 g\n0 0 m 10 0 L 10 10 L f\nU')])).throws<UnsupportedError>();
  });

  test('replaces topology and paints while retaining all authoring and unselected bytes', () {
    final AiNativeDrawing source = printingFixture();
    final List<int> original = source.records.program.bytes.toList();
    final AiNativeDrawing changed = source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first)]);
    final AiLiveShape shape = changed.liveShapes.first;
    check(shape.isBound).isTrue();
    check(shape.appearancePaths).length.equals(2);
    check(shape.appearancePaths.map((path) => path.paint.operator)).deepEquals(['f', 'F']);
    check(changed.groups.where((group) => group.start >= shape.start && group.end <= shape.appearanceGroup!.end).map((group) => group.compound)).every((compound) => compound.isFalse());
    check(changed.records.program.bytes.sublist(shape.appearanceGroup!.start, shape.appearanceGroup!.end)).deepEquals(latin1.encode(_group));
    check(_following(changed, 0)).deepEquals(_following(source, 0));
    check(shape.style).identicalTo(changed.liveShapes.last.style);
    check(latin1.decode(changed.records.program.bytes)).contains('%%BoundingBox: -10 -20 120 140');
    check(source.records.program.bytes).deepEquals(original);
  });

  test('saves independent group replacements atomically and refuses stale handles', () {
    final AiNativeDrawing source = printingFixture();
    final List<AiNativePrintingGroupReplacement> replacements = source.liveShapes.map(_replacement).toList();
    final AiNativeDrawing changed = source.withPrintingGroups(replacements: replacements);
    check(changed.liveShapes.map((shape) => shape.appearancePaths.length)).deepEquals([2, 2]);
    check(() => changed.withPrintingGroups(replacements: replacements)).throws<ArgumentError>();
    check(() => source.withPrintingGroups(replacements: [replacements.first, replacements.first])).throws<ArgumentError>();
    check(() => source.withPrintingGroups(replacements: [_replacement(printingFixture().liveShapes.first)])).throws<ArgumentError>();
    check(() => source.withPrintingGroups(replacements: [])).throws<ArgumentError>();
    final List<int> before = source.records.program.bytes.toList();
    check(
      () => source.withPrintingGroups(
        replacements: [
          replacements.first,
          _replacement(source.liveShapes.last, group: _group.replaceFirst('0 0 0 1 k', '0 g')),
        ],
      ),
    ).throws<UnsupportedError>();
    check(source.records.program.bytes).deepEquals(before);
  });

  test('does not invent inherited defaults and validates final color representations', () {
    final AiNativeDrawing source = printingFixture();
    for (final String group in [_group.replaceFirst('0 0 0 1 k', '0 g'), _group.replaceFirst('1 0 0 0 k', '1 w\n1 0 0 0 k'), _group.replaceFirst('0 0 0 1 k', '0 0 0 Xa')]) {
      check(() => source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: group)])).throws<UnsupportedError>();
    }
    final AiNativeDrawing restored = source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: _group.replaceFirst('1 0 0 0 k', '0.5 g'))]);
    check(latin1.decode(restored.records.program.bytes)).contains('0.5 g');
  });

  test('retains outgoing opacity, stroke state and nested group flags', () {
    const String attributes = '0.2 G\n2 w\n1 J\n2 j\n4 M\n[2 3] 1 d\n1 O\n0 R\n1 XR\n0 D\n1 Ap\n0 1 0 0 0 Xy';
    final AiNativeDrawing source = printingFixture(group: _group.replaceFirst('u\n', 'u\n$attributes\n'));
    final String supplied = _group.replaceFirst('u\nu', 'u\n$attributes\n0 0.4 0 0 0 Xy\n1 Ae\nu').replaceFirst('30 30 L F', '30 30 L F\n0 1 0 0 0 Xy');
    final AiNativeDrawing changed = source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: supplied)]);
    check(latin1.decode(changed.records.program.bytes)).contains('0 0.4 0 0 0 Xy');
    check(_following(changed, 0)).deepEquals(_following(source, 0));
    check(() => source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: supplied.replaceFirst('[2 3] 1 d', '[2 3] 0 d'))])).throws<UnsupportedError>();
  });

  test('uses existing unique gradients and preserves their private resources', () {
    const String painted = '''u
0 0 0 1 k
0 0 m 10 0 L 10 10 L
Bb
1 (Ink) 0 0 0 10 1 0 0 1 0 0 Bg
f
0 BB
U''';
    final AiNativeDrawing source = printingFixture(setup: _gradient);
    final AiNativeDrawing changed = source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: painted)]);
    check(changed.gradients).length.equals(1);
    check(latin1.decode(changed.gradients.single.geometry.nameBytes)).equals('Ink');
    check(latin1.decode(changed.records.program.bytes)).contains(_gradient);
    check(_following(changed, 0)).deepEquals(_following(source, 0));
    for (final String group in [painted.replaceFirst('(Ink)', '(Missing)'), painted.replaceFirst('1 (Ink)', '0 0 0 1 Bh\n1 (Ink)'), painted.replaceFirst('0 BB', '1 BB')]) {
      check(() => source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: group)])).throws<UnsupportedError>();
    }
    final AiNativeDrawing ambiguous = printingFixture(setup: '$_gradient\n$_gradient');
    check(() => ambiguous.withPrintingGroups(replacements: [_replacement(ambiguous.liveShapes.first, group: painted)])).throws<UnsupportedError>();
  });

  test('checks counted profiles, closed endpoints and path ownership', () {
    const String counted = 'u\n0 0 0 1 k\n3 As\n0 0 m 10 0 L 10 10 L 0 0 L f\nU';
    final AiNativeDrawing source = printingFixture(group: counted);
    final String two = counted.replaceFirst('0 0 L f', '0 0 L f\n2 As\n0 0 m 20 20 L S');
    final AiNativeDrawing changed = source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: two)]);
    check(changed.liveShapes.first.appearancePaths).length.equals(2);
    for (final String invalid in [counted.replaceFirst('3 As', '2 As'), counted.replaceFirst('3 As\n', ''), counted.replaceFirst('3 As', '3 As\n3 As')]) {
      check(() => source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: invalid)])).throws<UnsupportedError>();
    }
    final AiNativeDrawing uncounted = printingFixture();
    check(() => uncounted.withPrintingGroups(replacements: [_replacement(uncounted.liveShapes.first, group: counted)])).throws<UnsupportedError>();
  });

  test('rejects document escapes, opaque dependencies and invalid local state', () {
    final AiNativeDrawing source = printingFixture();
    for (final String fragment in [
      '$_group\n$_group',
      _group.replaceFirst('1 0 0 0 k', '2 0 0 0 k'),
      _group.replaceFirst('1 0 0 0 k', '{ 1 } 0 0 0 k'),
      _group.replaceFirst('1 0 0 0 k', '[0 0] 0 d\n1 0 0 0 k'),
      _group.replaceFirst('10 0 L', '10 0 m'),
    ]) {
      check(() => source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: fragment)])).throws<FormatException>();
    }
    for (final String fragment in [
      _group.replaceFirst('u\n', 'u\n%%EndSetup\n'),
      _group.replaceFirst('u\n', 'u\n%_/ArtDictionary : ;\n'),
      _group.replaceFirst('u\n', 'u\n%%BeginData: 1 ASCII Lines\nopaque\n%%EndData\n'),
      _group.replaceFirst('u\n', 'u\n17 FuturePaint\n'),
      _group.replaceFirst('u\n', 'u\n0 0 Xd\n'),
      _group.replaceFirst('u\n', 'u\n0 Ae\n1 w\n'),
      _group.replaceFirst('10 0 L', '10 0 L\n0 g'),
    ]) {
      check(() => source.withPrintingGroups(replacements: [_replacement(source.liveShapes.first, group: fragment)])).throws<UnsupportedError>();
    }
  });

  test('owns supplied bytes and applies bounded output checks', () {
    final AiNativeDrawing source = printingFixture();
    final List<int> bytes = latin1.encode(_group).toList();
    final AiNativePrintingGroupReplacement supplied = AiNativePrintingGroupReplacement(shape: source.liveShapes.first, bytes: bytes, bounds: _replacement(source.liveShapes.first).bounds);
    bytes.clear();
    check(supplied.bytes).deepEquals(latin1.encode(_group));
    check(() => supplied.bytes[0] = 0).throws<UnsupportedError>();
    final AiNativeDrawing bounded = printingFixture(limits: AiNativeLimits(maxDecodedBytes: source.records.program.bytes.length + 10));
    check(
      () => bounded.withPrintingGroups(replacements: [_replacement(bounded.liveShapes.first, group: 'u\n${List.filled(300, _group).join('\n')}\nU')]),
    ).throws<AiLimitException>();
    check(() => AiNativePrintingGroupReplacement(shape: source.liveShapes.first, bytes: [-1], bounds: supplied.bounds)).throws<ArgumentError>();
    check(() => AiNativePrintingGroupReplacement(shape: source.liveShapes.first, bytes: [256], bounds: supplied.bounds)).throws<ArgumentError>();
    check(
      () => AiNativePrintingGroupReplacement(shape: source.liveShapes.first, bytes: supplied.bytes, bounds: AiBoundingBox(left: 0, bottom: 0, right: 1e308, top: 1e308)),
    ).throws<ArgumentError>();
  });

  test('bounds fragment tokens and aggregate bytes without partially attaching groups', () {
    final AiNativeDrawing tokenBounded = printingFixture(limits: const AiNativeLimits(maxTokens: 2000));
    final String tokens = _group.replaceFirst('1 0 0 0 k', List.filled(600, '1 0 0 0 k').join('\n'));
    check(() => tokenBounded.withPrintingGroups(replacements: [_replacement(tokenBounded.liveShapes.first, group: tokens)])).throws<AiLimitException>();
    final AiNativeDrawing original = printingFixture();
    final int limit = original.records.program.bytes.length + 200;
    final AiNativeDrawing bounded = printingFixture(limits: AiNativeLimits(maxDecodedBytes: limit));
    final String padding = List.filled(limit ~/ 2, ' ').join();
    final String group = _group.replaceFirst('u\n', 'u\n%$padding\n');
    check(latin1.encode(group).length).isLessThan(limit);
    check(latin1.encode(group).length * 2).isGreaterThan(limit);
    check(
      () => bounded.withPrintingGroups(replacements: [for (final AiLiveShape shape in bounded.liveShapes) _replacement(shape, group: group)]),
    ).throws<AiLimitException>();
    check(bounded.records.program.bytes).deepEquals(original.records.program.bytes);
  });
}
