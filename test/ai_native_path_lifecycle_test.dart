import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_printing_test.dart' show printingFixture;

/// Builds a native source with retained setup and unrelated header metadata.
AiNativeDrawing _drawing({String body = _body, String setup = '', AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('%!PS-Adobe-3.0\n%%BoundingBox: 0 0 100 100\n%%EndComments\n$setup\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'),
      limits: limits,
    ),
  ),
);

/// Counts include the initial point and exclude an explicit closed endpoint.
const String _first = '3 As\n0 0 m\n10 0 L % ordinary source comment\n10 10 L\n0 0 L f';

/// Several paths deliberately share attributes assigned before the first one.
const String _body = '0 1 0 1 0 0 1 0 79 128 255 0 50 0 Lb (Hidden locked) Ln\n0 AE\n1 A\n1 Xw\n0.2 g\nu\n$_first\n2 As\n20 20 m 30 30 L S\nU\nLB';

/// Explicit host ink bounds and finite geometry with an implicit closing edge.
AiNativePathInsertion _insertion(AiNativePath after, double x) => AiNativePathInsertion(
  after: after,
  segments: [
    AiPathSegment(operator: 'm', coordinates: [x, 1]),
    AiPathSegment(operator: 'L', coordinates: [x + 2, 3]),
  ],
  bounds: AiBoundingBox(left: x - 1, bottom: -2, right: x + 3, top: 4),
);

/// Validates atomic lifecycle edits independently of host rendering.
void main() {
  test('duplicates counted paths in source order and retains inherited layer and paint state', () {
    final AiNativeDrawing source = _drawing(setup: '/FutureResource : 42 /Value ;');
    final List<int> original = source.records.program.bytes.toList();
    final AiNativeDrawing result = source.duplicatePaths(paths: source.paths.reversed.toList());
    check(result.paths).length.equals(4);
    check(result.paths.map((path) => path.paint.operator)).deepEquals(['f', 'f', 'S', 'S']);
    check(result.paths.map((path) => path.geometry.first.numbers)).deepEquals([
      [0.0, 0.0],
      [0.0, 0.0],
      [20.0, 20.0],
      [20.0, 20.0],
    ]);
    check(result.records.program.layers.single.visible).isFalse();
    check(result.records.program.layers.single.locked).isTrue();
    check(result.groups.single.paths).length.equals(4);
    check(result.items.whereType<AiNativeInstruction>().where((item) => const {'A', 'Xw', 'g'}.contains(item.operator)).map((item) => item.numbers)).deepEquals([
      [1.0],
      [1.0],
      [0.2],
    ]);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As').map((item) => item.numbers!.single)).deepEquals([3.0, 3.0, 2.0, 2.0]);
    check(result.records.program.bytes.take(source.paths.first.end).toList()).deepEquals(original.take(source.paths.first.end).toList());
    check(source.records.program.bytes).deepEquals(original);
    check(result.duplicatePaths(paths: [result.paths[1]]).paths).length.equals(5);
  });

  test('removes geometry and consumed counts without deleting persistent state', () {
    final AiNativeDrawing source = _drawing();
    final AiNativeDrawing result = source.removePaths(paths: source.paths);
    check(result.paths).isEmpty();
    check(result.groups.single.children).isEmpty();
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As')).isEmpty();
    check(result.records.program.layers.single.name).equals('Hidden locked');
    check(latin1.decode(result.records.program.bytes)).contains('1 A\n1 Xw\n0.2 g');
    check(latin1.decode(result.records.program.bytes)).contains('%%BoundingBox: 0 0 100 100');
    final AiNativeDrawing one = source.removePaths(paths: [source.paths.first]);
    check(one.paths.single.paint.operator).equals('S');
    check(one.paths.single.segments.map((segment) => segment.coordinates)).deepEquals(source.paths.last.segments.map((segment) => segment.coordinates));
  });

  test('inserts ordered geometry with inherited paint, complete closures and supplied ink bounds', () {
    final AiNativeDrawing source = _drawing();
    final AiNativeDrawing result = source.insertPaths(insertions: [_insertion(source.paths.first, -20), _insertion(source.paths.first, 120)]);
    check(result.paths.map((path) => path.geometry.first.numbers)).deepEquals([
      [0.0, 0.0],
      [-20.0, 1.0],
      [120.0, 1.0],
      [20.0, 20.0],
    ]);
    check(result.paths.map((path) => path.paint.operator)).deepEquals(['f', 'f', 'f', 'S']);
    check(result.paths[1].geometry.last.numbers!).deepEquals([-20.0, 1.0]);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As').map((item) => item.numbers!.single)).deepEquals([3.0, 2.0, 2.0, 2.0]);
    check(latin1.decode(result.records.program.bytes)).contains('%%BoundingBox: -21 -2 123 100');
    check(result.records.program.bytes.sublist(result.paths[2].end + 1)).deepEquals(source.records.program.bytes.sublist(source.paths.first.end));
  });

  test('keeps uncounted closure syntax and preserves opaque siblings outside selected objects', () {
    final AiNativeDrawing source = _drawing(setup: '/FutureRecord : (opaque) /Data ;', body: '0 g\n0 0 m 10 0 L f\n0 A\n20 20 m 30 30 L N\n/FutureRecord : 7 /Data ;');
    final AiNativeDrawing result = source.insertPaths(insertions: [_insertion(source.paths.first, 5)]);
    check(result.paths[1].geometry).length.equals(2);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As')).isEmpty();
    check(result.records.roots.map((record) => record['Data']!.items.length)).deepEquals([1, 1]);
    check(source.duplicatePaths(paths: [source.paths.first]).paths).length.equals(3);
    check(source.removePaths(paths: [source.paths.first]).paths).length.equals(1);
  });

  test('rejects empty, foreign, duplicate and stale selections before changing source bytes', () {
    final AiNativeDrawing source = _drawing();
    final List<int> original = source.records.program.bytes.toList();
    for (final List<AiNativePath> paths in [
      <AiNativePath>[],
      [source.paths.first, source.paths.first],
      [_drawing().paths.first],
    ]) {
      check(() => source.duplicatePaths(paths: paths)).throws<ArgumentError>();
      check(() => source.removePaths(paths: paths)).throws<ArgumentError>();
    }
    check(() => source.insertPaths(insertions: [])).throws<ArgumentError>();
    check(() => source.insertPaths(insertions: [_insertion(_drawing().paths.first, 0)])).throws<ArgumentError>();
    final AiNativeDrawing changed = source.duplicatePaths(paths: [source.paths.first]);
    check(() => changed.removePaths(paths: [source.paths.first])).throws<ArgumentError>();
    check(source.records.program.bytes).deepEquals(original);
  });

  test('refuses private, printing, compound, clipped and version-dependent paths', () {
    final AiNativeDrawing printing = printingFixture();
    for (final AiNativePath path in [printing.liveShapes.first.path!, ...printing.liveShapes.first.appearancePaths]) {
      check(() => printing.duplicatePaths(paths: [path])).throws<UnsupportedError>();
      check(() => printing.removePaths(paths: [path])).throws<UnsupportedError>();
    }
    for (final String body in [
      '%_0 0 m 1 1 L N',
      '*u 0 0 m 1 1 L N *U',
      'q 0 0 m 1 1 L N Q',
      '%AI17_Begin_Content_if_version_gt:24 4\n0 0 m 1 1 L N\n%AI17_End_Versioned_Content',
      '0 0 m 1 g 1 1 L N',
    ]) {
      final AiNativeDrawing source = _drawing(body: body);
      check(() => source.removePaths(paths: source.paths)).throws<UnsupportedError>();
    }
  });

  test('refuses trailing object identities, parent metadata, tags and path notes', () {
    for (final String body in [
      '0 0 m 1 1 L N\n/ArtDictionary : /XMLUID : (owned) ; (AI10_ArtUID) , ;',
      'u 0 0 m 1 1 L N U\n/FutureOwner : 1 /Index ;',
      '0 0 m 1 1 L N\n/AdobeURL (https://example.test) XT',
      '0 0 m 1 1 L N\n0 A\n/ArtDictionary : /XMLUID : (owned) ; (AI10_ArtUID) , ;',
      '%AI3_Note: retained authoring note\n0 0 m 1 1 L N',
      '0 0 m\n%AI3_Note: interleaved note\n1 1 L N',
    ]) {
      final AiNativeDrawing source = _drawing(body: body);
      check(() => source.duplicatePaths(paths: source.paths)).throws<UnsupportedError>();
      check(() => source.removePaths(paths: source.paths)).throws<UnsupportedError>();
    }
  });

  test('distinguishes a preceding bound shape style from an unresolved appearance context', () {
    final AiNativeDrawing fixture = printingFixture();
    final AiProgram program = AiNativeEditor.apply(
      program: fixture.records.program,
      edits: [
        AiSourceEdit(start: fixture.liveShapes.last.end, end: fixture.liveShapes.last.end, bytes: latin1.encode('\n0 R\n0 G\n0 0 m 10 10 L S\n')),
      ],
    );
    final AiNativeDrawing source = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
    final AiNativePath path = source.paths.last;
    check(source.records.program.paths.last.hasDependentAppearance).isTrue();
    final AiNativeDrawing result = source.duplicatePaths(paths: [path]);
    check(result.liveShapes).length.equals(2);
    check(result.paths).length.equals(source.paths.length + 1);
    check(result.records.program.bytes.take(path.end).toList()).deepEquals(source.records.program.bytes.take(path.end).toList());
    final AiNativeDrawing unsupported = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(
        program: AiNativeEditor.apply(
          program: program,
          edits: [
            AiSourceEdit(start: path.start, end: path.start, bytes: latin1.encode('17 FuturePaint\n')),
          ],
        ),
      ),
    );
    check(() => unsupported.duplicatePaths(paths: [unsupported.paths.last])).throws<UnsupportedError>();
  });

  test('checks source point-count ownership and rejects a batch atomically', () {
    for (final String body in ['3 As 0 0 m 1 1 L N', '2 As 2 As 0 0 m 1 1 L N', '2 As u 0 0 m 1 1 L N U', '2 As 0 0 m 1 1 L n', '0 0 m 2 As 1 1 L N']) {
      final AiNativeDrawing source = _drawing(body: body);
      check(() => source.duplicatePaths(paths: source.paths)).throws<UnsupportedError>();
    }
    final AiNativeDrawing source = _drawing(body: '0 0 m 1 1 L N\n0 g\n0 0 m 1 1 L N\n/FutureRecord : 7 /Data ;');
    final List<int> original = source.records.program.bytes.toList();
    check(() => source.removePaths(paths: source.paths)).throws<UnsupportedError>();
    check(source.records.program.bytes).deepEquals(original);
  });

  test('reorders sibling paths and transfers counted and uncounted layouts', () {
    final AiNativeDrawing source = _drawing(body: '0.3 g\nu\n$_first\n20 20 m 30 30 L S\n2 As\n40 40 m 50 50 L N\nU');
    final AiNativeDrawing result = source.reorderPaths(paths: source.paths.reversed.toList());
    check(result.paths.map((path) => path.geometry.first.numbers)).deepEquals([
      [40.0, 40.0],
      [20.0, 20.0],
      [0.0, 0.0],
    ]);
    check(result.paths.map((path) => path.paint.operator)).deepEquals(['N', 'S', 'f']);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As').map((item) => item.numbers!.single)).deepEquals([2.0, 3.0]);
    final AiNativeDrawing mixed = source.reorderPaths(paths: [source.paths[1], source.paths[0]]);
    check(mixed.paths.map((path) => path.paint.operator)).deepEquals(['S', 'f', 'N']);
    check(mixed.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As').map((item) => item.numbers!.single)).deepEquals([3.0, 2.0]);
    check(source.reorderPaths(paths: source.paths)).identicalTo(source);
    check(latin1.decode(result.records.program.bytes)).contains('0.3 g');
  });

  test('moves paths between ordinary groups without changing inherited attributes', () {
    final AiNativeDrawing source = _drawing(body: '1 A\n0.2 g\nu\n$_first\nU\nu\n20 20 m 30 30 L S\nU');
    final AiNativeDrawing result = source.movePathAfter(path: source.paths.first, after: source.paths.last);
    check(result.paths.map((path) => path.paint.operator)).deepEquals(['S', 'f']);
    check(result.groups.first.children).isEmpty();
    check(result.groups.last.paths).length.equals(2);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As').single.numbers!).deepEquals([3.0]);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'A').single.numbers!).deepEquals([1.0]);
    check(source.groups.map((group) => group.paths.length)).deepEquals([1, 1]);
    final AiNativeDrawing reversed = source.movePathAfter(path: source.paths.last, after: source.paths.first);
    check(reversed.groups.first.paths).length.equals(2);
    check(reversed.groups.last.children).isEmpty();
  });

  test('rejects path movement across changed state, distinct layers or unresolved structure', () {
    final AiNativeDrawing unchangedState = _drawing();
    check(unchangedState.reorderPaths(paths: unchangedState.paths.reversed.toList()).paths.first.paint.operator).equals('S');
    for (final String separator in ['0.5 g', '0 A', '0 Xw', '17 FuturePaint', '%AI3_Note: attached note']) {
      final AiNativeDrawing source = _drawing(body: '0 g\n0 0 m 1 1 L N\n$separator\n2 2 m 3 3 L N');
      final List<int> original = source.records.program.bytes.toList();
      check(() => source.reorderPaths(paths: source.paths.reversed.toList())).throws<UnsupportedError>();
      check(() => source.movePathAfter(path: source.paths.first, after: source.paths.last)).throws<UnsupportedError>();
      check(source.records.program.bytes).deepEquals(original);
    }
    final AiNativeDrawing groups = _drawing(body: 'u 0 0 m 1 1 L N U u 2 2 m 3 3 L N U');
    check(() => groups.reorderPaths(paths: groups.paths.reversed.toList())).throws<ArgumentError>();
    check(() => groups.movePathAfter(path: groups.paths.first, after: groups.paths.first)).throws<ArgumentError>();
    const String layer = '1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb';
    final AiNativeDrawing layers = _drawing(body: '$layer 0 0 m 1 1 L N LB $layer 2 2 m 3 3 L N LB');
    check(() => layers.movePathAfter(path: layers.paths.first, after: layers.paths.last)).throws<UnsupportedError>();
  });

  test('freezes supplied geometry and bounds output bytes and aggregate tokens', () {
    final AiNativeDrawing source = _drawing(body: '0 0 m 1 1 L N', limits: const AiNativeLimits(maxDecodedBytes: 200));
    final List<AiPathSegment> segments = [
      AiPathSegment(operator: 'm', coordinates: [1, 2]),
      AiPathSegment(operator: 'L', coordinates: [3, 4]),
    ];
    final AiNativePathInsertion insertion = AiNativePathInsertion(after: source.paths.single, segments: segments, bounds: AiBoundingBox(left: 0, bottom: 0, right: 10, top: 10));
    segments.clear();
    check(insertion.segments).length.equals(2);
    check(insertion.segments.clear).throws<UnsupportedError>();
    check(() => source.insertPaths(insertions: List.filled(20, insertion))).throws<FormatException>();
    final AiNativeDrawing bounded = _drawing(body: '0 0 m 1 1 L N', limits: const AiNativeLimits(maxTokens: 14));
    check(() => bounded.duplicatePaths(paths: bounded.paths)).throws<AiLimitException>();
    check(() => AiNativePathInsertion(after: source.paths.single, segments: [], bounds: insertion.bounds)).throws<ArgumentError>();
    check(
      () => AiNativePathInsertion(
        after: source.paths.single,
        segments: [
          AiPathSegment(operator: 'm', coordinates: [1e20, 0]),
        ],
        bounds: insertion.bounds,
      ),
    ).throws<ArgumentError>();
  });
}
