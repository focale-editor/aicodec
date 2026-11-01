import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboards_test.dart' show mixedArtboardSource;
import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;

/// An explicit closed rectangle with four unique native points.
const String topologyRectangle = '0 0 m 20 0 L 20 20 L 0 20 L 0 0 L';

/// A nested compound and clip with distinct native identities and an untouched peer.
String topologySource() => objectSource('''q
*u
4 As $topologyRectangle f
${objectDictionary(identifier: 'Outer')}
u 4 As $topologyRectangle f
${objectDictionary(identifier: 'Inner')}
U
*U
${objectDictionary(identifier: 'Compound')}
4 As $topologyRectangle f
Q
${objectDictionary(identifier: 'Clip')}
4 As $topologyRectangle f
''');

/// Host-authored geometry retaining a corner curve and an implicit closed edge.
List<AiPathSegment> topologyGeometry() => [
  AiPathSegment(operator: 'm', coordinates: [5, 5]),
  AiPathSegment(operator: 'C', coordinates: [8, 2, 16, 2, 18, 6]),
  AiPathSegment(operator: 'L', coordinates: [15, 15]),
];

/// Host-computed ink bounds already contained by the fixture's drawing extent.
AiBoundingBox get topologyBounds => AiBoundingBox(left: 0, bottom: 0, right: 20, top: 20);

/// Reads native bytes without reserialization or text normalization.
String _source(AiNativeDrawing drawing) => latin1.decode(drawing.records.program.bytes);

/// Requires exact paint, object identities, metadata and nested group ordering.
void _retained(AiNativeDrawing before, AiNativeDrawing after, Set<int> changed) {
  check(after.groups.map((group) => group.opening.operator)).deepEquals(before.groups.map((group) => group.opening.operator));
  check(after.paths.map((path) => path.paint.operator)).deepEquals(before.paths.map((path) => path.paint.operator));
  final AiNativeObjects original = AiNativeObjects.decode(drawing: before);
  final AiNativeObjects result = AiNativeObjects.decode(drawing: after);
  check(result.objects.map((object) => object.identifier?.bytes)).deepEquals(original.objects.map((object) => object.identifier?.bytes));
  for (final (int, AiNativePath) entry in before.paths.indexed) {
    if (!changed.contains(entry.$1)) {
      final AiNativePath retained = after.paths[entry.$1];
      check(after.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(before.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    }
  }
}

/// Exercises authoritative contour changes, shared masks and atomic refusals.
void main() {
  test('edits a nested compound contour while preserving geometry siblings and native identities', () {
    final AiNativeDrawing drawing = groupCreationDrawing(topologySource());
    final AiNativePath path = drawing.paths[1];
    final AiNativePathTopology topology = drawing.pathTopology(path: path);
    check(topology.groups.map((group) => group.opening.operator)).deepEquals(['q', '*u', 'u']);
    check(topology.compound).identicalTo(drawing.groups[1]);
    check(topology.clippingGroup).identicalTo(drawing.groups[2]);
    check(topology.mask).equals(AiNativePathMask.none);
    final List<AiPathSegment> supplied = topologyGeometry();
    final AiNativePathEdit edit = AiNativePathEdit(path: path, segments: supplied);
    supplied.clear();
    check(edit.segments!).length.equals(3);
    check(() => edit.segments!.clear()).throws<UnsupportedError>();
    check(topology.groups.clear).throws<UnsupportedError>();
    final AiNativeDrawing result = drawing.editPaths(edits: [edit], bounds: topologyBounds);
    _retained(drawing, result, {1});
    check(result.paths[1].geometry.map((command) => command.operator)).deepEquals(['m', 'C', 'L', 'L']);
    check(result.pathTopology(path: result.paths[1]).pointCount!.numbers).isNotNull().deepEquals([3]);
    check(_source(drawing)).equals(topologySource());
  });

  test('keeps counted closure consistent for all mask paint and geometry combinations', () {
    for (final String control in ['h', 'H']) {
      for (final String paint in ['n', 'N', 'f', 'F', 's', 'S', 'b', 'B']) {
        for (final bool counted in [false, true]) {
          final bool closed = control == 'h' || paint == paint.toLowerCase();
          final String count = counted ? '${closed ? 4 : 5} As ' : '';
          final AiNativeDrawing drawing = groupCreationDrawing(objectSource('q $count$topologyRectangle $control W $paint Q'));
          final AiNativeDrawing result = drawing.editPaths(
            edits: [AiNativePathEdit(path: drawing.paths.single, segments: topologyGeometry())],
            bounds: topologyBounds,
          );
          final AiNativePath path = result.paths.single;
          final AiNativePathTopology topology = result.pathTopology(path: path);
          check(path.paint.operator).equals(paint);
          check(path.geometry).length.equals(counted && closed ? 4 : 3);
          check(topology.mask).equals(control == 'h' ? AiNativePathMask.closed : AiNativePathMask.open);
          check(topology.pointCount?.numbers ?? []).deepEquals(counted ? [3] : []);
        }
      }
    }
  });

  test('enables switches and removes a local mask without changing enclosing state or later geometry', () {
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource('q u 3 As 0 0 m 20 0 L 20 20 L N U 4 As $topologyRectangle f Q'));
    final AiNativeDrawing closed = drawing.editPaths(
      edits: [AiNativePathEdit(path: drawing.paths.first, mask: .closed)],
      bounds: topologyBounds,
    );
    check(closed.paths.first.geometry).length.equals(4);
    check(closed.pathTopology(path: closed.paths.first).pointCount!.numbers).isNotNull().deepEquals([3]);
    check(closed.pathTopology(path: closed.paths.first).mask).equals(AiNativePathMask.closed);
    final AiNativeDrawing open = closed.editPaths(
      edits: [AiNativePathEdit(path: closed.paths.first, mask: .open)],
      bounds: topologyBounds,
    );
    check(open.pathTopology(path: open.paths.first).pointCount!.numbers).isNotNull().deepEquals([4]);
    final AiNativeDrawing cleared = open.editPaths(
      edits: [AiNativePathEdit(path: open.paths.first, mask: .none)],
      bounds: topologyBounds,
    );
    check(cleared.pathTopology(path: cleared.paths.first).mask).equals(AiNativePathMask.none);
    _retained(drawing, cleared, {0});
    check(
      cleared.editPaths(
        edits: [AiNativePathEdit(path: cleared.paths.first, mask: .none)],
        bounds: topologyBounds,
      ),
    ).identicalTo(cleared);
  });

  test('updates every compound mask contour in one atomic transaction', () {
    final AiNativeDrawing drawing = groupCreationDrawing(topologySource());
    check(
      () => drawing.editPaths(
        edits: [AiNativePathEdit(path: drawing.paths.first, mask: .closed)],
        bounds: topologyBounds,
      ),
    ).throws<UnsupportedError>();
    final AiNativeDrawing result = drawing.editPaths(
      edits: [for (final AiNativePath path in drawing.groups[1].paths) AiNativePathEdit(path: path, mask: .closed)],
      bounds: topologyBounds,
    );
    _retained(drawing, result, {0, 1});
    check(result.paths.take(2).map((path) => result.pathTopology(path: path).mask)).deepEquals([AiNativePathMask.closed, AiNativePathMask.closed]);
    check(
      () => result.editPaths(
        edits: [AiNativePathEdit(path: result.paths.first, mask: .none)],
        bounds: topologyBounds,
      ),
    ).throws<UnsupportedError>();
    final AiNativeDrawing cleared = result.editPaths(
      edits: [for (final AiNativePath path in result.groups[1].paths) AiNativePathEdit(path: path, mask: .none)],
      bounds: topologyBounds,
    );
    check(cleared.paths.take(2).map((path) => cleared.pathTopology(path: path).mask)).deepEquals([AiNativePathMask.none, AiNativePathMask.none]);
  });

  test('preserves complete CC neighbors and rejects independent edits to either representation', () {
    final String text = mixedArtboardSource().replaceFirst('%%Trailer', '*u 4 As $topologyRectangle f 4 As $topologyRectangle f *U\n%%Trailer');
    final AiNativeDrawing drawing = groupCreationDrawing(text);
    final AiNativeDrawing result = drawing.editPaths(
      edits: [AiNativePathEdit(path: drawing.paths.last, segments: topologyGeometry())],
      bounds: topologyBounds,
    );
    for (final (int, AiLiveShape) entry in drawing.liveShapes.indexed) {
      final AiLiveShape retained = result.liveShapes[entry.$1];
      check(result.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(drawing.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
      for (final AiNativePath path in [entry.$2.path!, ...entry.$2.appearancePaths]) {
        check(
          () => drawing.editPaths(
            edits: [AiNativePathEdit(path: path, segments: topologyGeometry())],
            bounds: topologyBounds,
          ),
        ).throws<UnsupportedError>();
      }
    }
    check(_source(drawing)).equals(text);
  });

  test('retains hidden locked layer state and requires host bounds independently of artboards', () {
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource(movementLayer('Hidden', '*u 4 As $topologyRectangle f 4 As $topologyRectangle f *U', hidden: true)));
    final AiNativeDrawing result = drawing.editPaths(
      edits: [AiNativePathEdit(path: drawing.paths.first, segments: topologyGeometry())],
      bounds: AiBoundingBox(left: -10, bottom: -20, right: 120, top: 130),
    );
    check(result.records.program.layers.single.visible).isFalse();
    check(result.records.program.layers.single.begin.numbers).isNotNull().deepEquals(drawing.records.program.layers.single.begin.numbers!);
    check(_source(result)).contains('%%BoundingBox: -10 -20 120 130');
  });

  test('rejects malformed controls counts owners and opaque dependencies atomically', () {
    for (final String body in [
      '$topologyRectangle h W n',
      'q $topologyRectangle W n Q',
      'q $topologyRectangle h W W n Q',
      'q $topologyRectangle h 1 W n Q',
      'q $topologyRectangle h W n 17 FuturePaint Q',
      'q 3 As $topologyRectangle h W n Q',
      '4 As q $topologyRectangle h W n Q',
      'q 4 As 4 As $topologyRectangle h W n Q',
      '*u $topologyRectangle f *U ${objectDictionary(extra: '(future) /String (UnknownAppearance) ,')}',
      'q 0 0 m 1 g 10 10 L N Q',
      '%_q $topologyRectangle h W n Q',
      'q $topologyRectangle h\n%AI24_ClipOwner: hidden\nW n Q',
    ]) {
      final String text = objectSource(body);
      final AiNativeDrawing drawing = groupCreationDrawing(text);
      expect(
        () => drawing.editPaths(
          edits: [AiNativePathEdit(path: drawing.paths.first, segments: topologyGeometry())],
          bounds: topologyBounds,
        ),
        throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
      );
      check(_source(drawing)).equals(text);
    }
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource('$topologyRectangle f'));
    check(
      () => drawing.editPaths(
        edits: [AiNativePathEdit(path: drawing.paths.first, mask: .open)],
        bounds: topologyBounds,
      ),
    ).throws<UnsupportedError>();
  });

  test('rejects stale duplicate foreign and invalid input without accepting partial batches', () {
    final AiNativeDrawing drawing = groupCreationDrawing(topologySource());
    final AiNativeDrawing foreign = groupCreationDrawing(topologySource());
    final AiNativePathEdit edit = AiNativePathEdit(path: drawing.paths.first, segments: topologyGeometry());
    check(() => drawing.editPaths(edits: [], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.editPaths(edits: [edit, edit], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => foreign.editPaths(edits: [edit], bounds: topologyBounds)).throws<ArgumentError>();
    final AiNativeDrawing changed = drawing.editPaths(edits: [edit], bounds: topologyBounds);
    check(() => changed.editPaths(edits: [edit], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => AiNativePathEdit(path: drawing.paths.first)).throws<ArgumentError>();
    for (final List<AiPathSegment> invalid in [
      <AiPathSegment>[],
      topologyGeometry().skip(1).toList(),
      [...topologyGeometry(), topologyGeometry().first],
      [
        AiPathSegment(operator: 'm', coordinates: [1e20, 0]),
      ],
    ]) {
      check(() => AiNativePathEdit(path: drawing.paths.first, segments: invalid)).throws<ArgumentError>();
    }
  });

  test('keeps aggregate output limits and normalizes hundreds of contours in one transaction', () {
    final String text = topologySource();
    final AiNativeDrawing bounded = groupCreationDrawing(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(
      () => bounded.editPaths(
        edits: [
          AiNativePathEdit(path: bounded.paths.first, segments: [topologyGeometry().first, ...List.generate(500, (_) => topologyGeometry().last)]),
        ],
        bounds: topologyBounds,
      ),
    ).throws<FormatException>();
    check(_source(bounded)).equals(text);
    final AiNativeDrawing many = groupCreationDrawing(objectSource(List.filled(200, '*u 4 As $topologyRectangle f 4 As $topologyRectangle f *U').join('\n')));
    final AiNativeDrawing result = many.editPaths(
      edits: [for (final AiNativePath path in many.paths) AiNativePathEdit(path: path, segments: topologyGeometry())],
      bounds: topologyBounds,
    );
    check(result.paths).length.equals(400);
    check(result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As').every((item) => item.numbers!.single == 3)).isTrue();
  });
}
