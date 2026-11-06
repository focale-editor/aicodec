import 'dart:convert';
import 'dart:math';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_objects_test.dart' show objectSource;
import 'ai_native_path_topology_test.dart' show topologySource;

/// Decodes a hand-authored ordinary path fixture.
AiNativeDrawing _drawing(String source) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(source))),
);

/// Explicit host ink bounds, independent of any native path measurement.
AiBoundingBox get _bounds => AiBoundingBox(left: -100, bottom: -100, right: 200, top: 200);

/// Exercises affine maps independently of live-shape parameter regeneration.
void main() {
  test('nonuniform scaling, pivot reflection and bidirectional shear have invertible coordinates', () {
    final AiNativeAffineTransform scale = AiNativeAffineTransform.scale(scaleX: 2, scaleY: 3, pivotX: 10, pivotY: 20);
    check(scale.point(x: 12, y: 24)).deepEquals([14.0, 32.0]);
    final AiNativeAffineTransform reflection = AiNativeAffineTransform.reflection(axisRadians: pi / 4, pivotX: 10, pivotY: 20);
    check(reflection.point(x: 12, y: 24)).deepEquals([14.0, 22.0]);
    final AiNativeAffineTransform shear = AiNativeAffineTransform.shear(horizontal: 0.5, vertical: 0.25, pivotX: 10, pivotY: 20);
    check(shear.point(x: 12, y: 24)).deepEquals([14.0, 24.5]);
    for (final AiNativeAffineTransform transform in [scale, reflection, shear]) {
      final List<double> moved = transform.point(x: 12, y: 24);
      final List<double> restored = transform.inverse.point(x: moved[0], y: moved[1]);
      check(restored[0]).isCloseTo(12, 1e-12);
      check(restored[1]).isCloseTo(24, 1e-12);
    }
  });

  test('transforms cubic controls and shorthand without changing paint, widths, metadata or peers', () {
    final AiNativeDrawing source = _drawing(objectSource('3 w [4 2] 1 d\n0 0 m 3 4 7 8 10 12 C 15 16 20 22 v 24 26 30 32 Y S\n40 0 m 50 10 L s'));
    final AiNativeAffineTransform transform = AiNativeAffineTransform(a: -2, c: 0.5, d: 3, tx: 4, ty: -2);
    final AiNativeDrawing changed = source.transformPaths(paths: [source.paths.first], transform: transform, bounds: _bounds);
    check(changed.paths.first.segments.map((segment) => segment.operator)).deepEquals(['m', 'C', 'v', 'Y']);
    check(changed.paths.first.segments[1].coordinates).deepEquals([0.0, 10.0, -6.0, 22.0, -10.0, 34.0]);
    check(changed.paths.first.paint.operator).equals('S');
    check(changed.paths.last.segments.map((segment) => segment.coordinates)).deepEquals(source.paths.last.segments.map((segment) => segment.coordinates));
    check(latin1.decode(changed.records.program.bytes)).contains('3 w [4 2] 1 d');
    final AiNativeDrawing restored = changed.transformPaths(paths: [changed.paths.first], transform: transform.inverse, bounds: _bounds);
    for (int index = 0; index < source.paths.first.segments.length; index++) {
      final List<double> expected = source.paths.first.segments[index].coordinates;
      final List<double> actual = restored.paths.first.segments[index].coordinates;
      for (int axis = 0; axis < expected.length; axis++) {
        check(actual[axis]).isCloseTo(expected[axis], 1e-12);
      }
    }
  });

  test('retains compound/clip controls and point counts under reflection', () {
    final AiNativeDrawing source = _drawing(topologySource());
    final AiNativeDrawing changed = source.transformPaths(paths: source.paths.take(2).toList(), transform: AiNativeAffineTransform.scale(scaleX: -1, scaleY: 2, pivotX: 0, pivotY: 0), bounds: _bounds);
    check(changed.groups.map((group) => group.opening.operator)).deepEquals(source.groups.map((group) => group.opening.operator));
    check(changed.paths.first.segments[1].coordinates).deepEquals([-20.0, 0.0]);
    check(changed.pathTopology(path: changed.paths.first).pointCount!.numbers!).deepEquals([4.0]);
    check(changed.paths.last.segments.map((segment) => segment.coordinates)).deepEquals(source.paths.last.segments.map((segment) => segment.coordinates));
  });

  test('requires explicit frame-angle metadata and rejects stale selections and collapse', () {
    final AiNativeDrawing source = _drawing(objectSource('0 0 m 0.1 0 L S\n/ArtDictionary : (0.5) /String (BBAccumRotation) , ;'));
    final AiNativeAffineTransform transform = AiNativeAffineTransform.shear(horizontal: 1, vertical: 0, pivotX: 0, pivotY: 0);
    check(() => source.transformPaths(paths: source.paths, transform: transform, bounds: _bounds)).throws<ArgumentError>();
    final AiNativeDrawing moved = source.transformPaths(paths: source.paths, transform: transform, bounds: _bounds, frameAngles: {source.paths.single: 0.25});
    check(AiNativeObjects.decode(drawing: moved).objects.single.dictionary!['BBAccumRotation']!.text()).equals('0.250000');
    check(() => moved.transformPaths(paths: source.paths, transform: transform, bounds: _bounds)).throws<ArgumentError>();
    check(() => source.transformPaths(paths: source.paths, transform: AiNativeAffineTransform(tx: 9e15), bounds: _bounds, frameAngles: {source.paths.single: 0.5})).throws<ArgumentError>();
    for (final double invalid in [0, double.infinity, double.nan, 1e-250]) {
      check(() => AiNativeAffineTransform.scale(scaleX: invalid, scaleY: invalid, pivotX: 0, pivotY: 0)).throws<ArgumentError>();
    }
    check(() => AiNativeAffineTransform.shear(horizontal: 1, vertical: 1, pivotX: 0, pivotY: 0)).throws<ArgumentError>();
  });
}
