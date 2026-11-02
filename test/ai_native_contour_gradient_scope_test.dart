import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementState;
import 'ai_native_contour_movement_test.dart' show contourMovementContour, contourMovementGroup, contourMovementPath;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds, topologyGeometry;
import 'ai_native_reference_resources_test.dart' show referenceGradient;

/// Places one bounded gradient between independent, explicitly initialized owners.
String contourGradientSource({bool relative = false, bool precedingGeometry = false, bool reset = true, String? gradient, String setup = referenceGradient}) {
  const String geometry = '3 As 90 0 m 91 0 L 91 1 L';
  final String resource = 'Bb\n1 (path_target) 10 20 0 100 1 0 0 1 0 0${relative ? ' 1' : ''} Bg\n';
  final String instance = gradient ?? '${precedingGeometry ? '$geometry\n$resource' : '$resource$geometry\n'}N\n0 BB\n';
  return objectSource('''0 1 0 0 0 Xy
u ${contourMovementPath(10)}U
${objectDictionary(identifier: 'Left')}
$instance
${reset ? '$movementState\n0 1 0 0 0 Xy' : ''}
u ${contourMovementPath(20)}U
${objectDictionary(identifier: 'Right')}
''', setup: setup);
}

/// Requires retained gradient instructions, geometry and resource bytes to stay exact.
void _retained(AiNativeDrawing before, AiNativeDrawing after) {
  check(after.records.program.bytes.sublist(0, before.records.program.bodyStart)).deepEquals(before.records.program.bytes.sublist(0, before.records.program.bodyStart));
  check(after.gradients.length).equals(before.gradients.length);
  for (final (int, AiNativeGradient) entry in before.gradients.indexed) {
    final AiNativeGradient actual = after.gradients[entry.$1];
    check(after.records.program.bytes.sublist(actual.start, actual.end)).deepEquals(before.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    check(actual.paths.map((path) => path.segments.map((segment) => segment.coordinates))).deepEquals(entry.$2.paths.map((path) => path.segments.map((segment) => segment.coordinates)));
  }
}

/// Qualifies unchanged neighbors independently of their appearance-editing APIs.
void main() {
  test('edits ordinary contours around retained legacy and CC gradient layouts', () {
    for (final bool relative in [false, true]) {
      for (final bool preceding in [false, true]) {
        final String source = contourGradientSource(relative: relative, precedingGeometry: preceding);
        final AiNativeDrawing drawing = groupCreationDrawing(source);
        final AiNativeDrawing changed = drawing.editPaths(
          edits: [AiNativePathEdit(path: contourMovementContour(drawing, 10), segments: topologyGeometry())],
          bounds: topologyBounds,
        );
        _retained(drawing, changed);
        check(changed.paths.first.geometry.length).equals(topologyGeometry().length);
        check(latin1.decode(drawing.records.program.bytes)).equals(source);
      }
    }
  });

  test('moves contours and complete owners across gradients with known slot state', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourGradientSource());
    final AiNativeDrawing moved = drawing.moveContours(paths: [contourMovementContour(drawing, 10)], group: contourMovementGroup(drawing, 'Right'), bounds: topologyBounds);
    _retained(drawing, moved);
    check(moved.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([90, 20, 10]);
    final AiNativeDrawing grouped = drawing.moveContourGroups(
      groups: [contourMovementGroup(drawing, 'Left')],
      parent: contourMovementGroup(drawing, 'Right'),
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    _retained(drawing, grouped);
  });

  test('does not infer scalar defaults across retained gradient state barriers', () {
    final String source = contourGradientSource(reset: false);
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(() => drawing.moveContours(paths: [contourMovementContour(drawing, 10)], group: contourMovementGroup(drawing, 'Right'), bounds: topologyBounds, inheritParentFlags: true))
        .throws<UnsupportedError>();
    check(() => drawing.moveContourGroups(groups: [contourMovementGroup(drawing, 'Left')], parent: contourMovementGroup(drawing, 'Right'), bounds: topologyBounds, inheritParentFlags: true))
        .throws<UnsupportedError>();
    // A geometry-only edit changes no inherited scalar at either owner.
    final AiNativeDrawing changed = drawing.editPaths(
      edits: [AiNativePathEdit(path: contourMovementContour(drawing, 20), segments: topologyGeometry())],
      bounds: topologyBounds,
    );
    _retained(drawing, changed);
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('rejects unrestorable output before an unchanged gradient consumer', () {
    final String source = contourGradientSource().replaceFirst('0 1 0 0 0 Xy', '');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(() => drawing.moveContourGroups(groups: [contourMovementGroup(drawing, 'Right')], parent: contourMovementGroup(drawing, 'Left'), bounds: topologyBounds, inheritParentFlags: true))
        .throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('retains gradient neighbors through compound and clipping lifecycle', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourGradientSource());
    final AiNativeDrawing compound = drawing.compoundArtwork(paths: [contourMovementContour(drawing, 10)], bounds: topologyBounds);
    final AiNativeDrawing released = compound.releaseCompounds(groups: compound.groups.where((group) => group.compound).toList(), bounds: topologyBounds);
    _retained(drawing, released);
    final AiNativeDrawing clipped = drawing.clipArtwork(
      paths: [contourMovementContour(drawing, 10)],
      masks: [AiNativePathEdit(path: contourMovementContour(drawing, 10), mask: .closed)],
      bounds: topologyBounds,
    );
    final AiNativeDrawing unmasked = clipped.releaseClippingGroups(groups: clipped.groups.where((group) => group.opening.operator == 'q').toList(), bounds: topologyBounds);
    _retained(drawing, unmasked);
  });

  test('keeps gradient contours protected from ordinary geometry and movement APIs', () {
    final String source = contourGradientSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativePath derived = drawing.gradients.single.paths.single;
    check(
      () => drawing.editPaths(
        edits: [AiNativePathEdit(path: derived, segments: topologyGeometry())],
        bounds: topologyBounds,
      ),
    ).throws<UnsupportedError>();
    check(() => drawing.moveContours(paths: [derived], group: contourMovementGroup(drawing, 'Right'), bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('requires a unique unconditional gradient resource in its own namespace', () {
    final String source = contourGradientSource();
    for (final String invalid in [
      contourGradientSource(setup: ''),
      contourGradientSource(setup: '$referenceGradient\n$referenceGradient'),
      contourGradientSource(setup: '%AI17_Begin_Content_if_version_gt:24 4\n$referenceGradient\n%AI17_End_Versioned_Content'),
      source.replaceFirst('1 (path_target) 10', '1 (missing) 10'),
      source.replaceFirst('Bb\n', '%AI17_Begin_Content_if_version_gt:24 4\nBb\n').replaceFirst('0 BB', '0 BB\n%AI17_End_Versioned_Content'),
    ]) {
      final AiNativeDrawing drawing = groupCreationDrawing(invalid);
      check(
        () => drawing.editPaths(
          edits: [AiNativePathEdit(path: drawing.paths.first, segments: topologyGeometry())],
          bounds: topologyBounds,
        ),
      ).throws<UnsupportedError>();
      check(latin1.decode(drawing.records.program.bytes)).equals(invalid);
    }
  });

  test('rejects gradients crossing state metadata groups or partially consumed paths', () {
    final String source = contourGradientSource();
    for (final String invalid in [
      source.replaceFirst('3 As 90', '4 w\n3 As 90'),
      source.replaceFirst('3 As 90', '${objectDictionary(identifier: 'Hidden')}\n3 As 90'),
      source.replaceFirst('3 As 90', 'u\n3 As 90').replaceFirst('0 BB', 'U\n0 BB'),
      source.replaceFirst('3 As 90', '2 As 90'),
      source.replaceFirst('0 BB', '2 As 0 BB'),
      source.replaceFirst('N\n0 BB', '0 BB\nN'),
      source.replaceFirst('0 BB', '0 BB\n%%FutureAttachedData: opaque'),
    ]) {
      final AiNativeDrawing drawing = groupCreationDrawing(invalid);
      expect(
        () => drawing.editPaths(
          edits: [AiNativePathEdit(path: drawing.paths.first, segments: topologyGeometry())],
          bounds: topologyBounds,
        ),
        throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
      );
      check(latin1.decode(drawing.records.program.bytes)).equals(invalid);
    }
    check(() => groupCreationDrawing(source.replaceFirst('100 1 0 0 1', '100 10000000000000000 0 0 1'))).throws<FormatException>();
  });

  test('retains existing limits while inspecting large shared-resource batches', () {
    final String source = contourGradientSource();
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length + 1));
    check(
      () => limited.editPaths(
        edits: [AiNativePathEdit(path: limited.paths.first, segments: topologyGeometry())],
        bounds: topologyBounds,
      ),
    ).throws<FormatException>();
    final String gradient = source.substring(source.indexOf('Bb\n'), source.indexOf('0 BB') + 4);
    final AiNativeDrawing batch = groupCreationDrawing(contourGradientSource(gradient: List.filled(100, gradient).join('\n')));
    final AiNativeDrawing changed = batch.editPaths(
      edits: [AiNativePathEdit(path: batch.paths.first, segments: topologyGeometry())],
      bounds: topologyBounds,
    );
    _retained(batch, changed);
  });
}
