import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_text_test.dart' show artboardTextDrawing, populatedArtboardSource;
import 'ai_native_artboards_test.dart' show mixedArtboardSource;
import 'ai_native_artwork_movement_test.dart' show movementLayer, movementState;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds, topologyRectangle;

/// Three identified contours with a nested ordinary element and a following peer.
String compoundLifecycleSource() => objectSource('''4 As $topologyRectangle f
${objectDictionary(identifier: 'First')}
0.6 g u
4 As $topologyRectangle f
${objectDictionary(identifier: 'Second')}
u 0.8 g 4 As $topologyRectangle f U
U
${objectDictionary(identifier: 'Branch')}
4 As $topologyRectangle f
''', setup: '');

/// Reads the complete native program without a lossy text round trip.
String _source(AiNativeDrawing drawing) => latin1.decode(drawing.records.program.bytes);

/// Requires unchanged contour data, names and identities in their source order.
void _retained(AiNativeDrawing original, AiNativeDrawing result) {
  check(result.paths.length).equals(original.paths.length);
  final AiNativeObjects before = AiNativeObjects.decode(drawing: original);
  final AiNativeObjects after = AiNativeObjects.decode(drawing: result);
  for (final (int, AiNativePath) entry in original.paths.indexed) {
    final AiNativePath path = result.paths[entry.$1];
    check(result.records.program.bytes.sublist(path.start, path.end)).deepEquals(original.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    check(after.forSource(path).identifier?.bytes ?? []).deepEquals(before.forSource(entry.$2).identifier?.bytes ?? []);
  }
}

/// Exercises compound topology independently of rendering and live-shape models.
void main() {
  test('wraps complete sibling contours and ordinary branches in source order', () {
    final AiNativeDrawing drawing = groupCreationDrawing(compoundLifecycleSource());
    final AiNativeGroup branch = drawing.groups.last;
    final AiNativeDrawing result = drawing.compoundArtwork(paths: [drawing.paths.first], groups: [branch], bounds: topologyBounds);
    final AiNativeGroup compound = result.groups.singleWhere((group) => group.compound);
    check(compound.paths.length).equals(3);
    check(compound.children.length).equals(2);
    check(result.pathTopology(path: result.paths[2]).groups.map((group) => group.opening.operator)).deepEquals(['*u', 'u', 'u']);
    check(result.pathTopology(path: result.paths.last).compound).isNull();
    _retained(drawing, result);
    final int start = drawing.pathTopology(path: drawing.paths.first).pointCount!.start;
    final int end = AiNativeObjects.decode(drawing: drawing).forSource(branch).end;
    final String source = _source(drawing);
    check(_source(result)).equals('${source.substring(0, start)}\n*u\n${source.substring(start, end)}\n*U\n${source.substring(end)}');
    final AiNativeDrawing released = result.releaseCompounds(groups: [compound], bounds: topologyBounds);
    _retained(drawing, released);
    check(released.groups.map((group) => group.opening.operator)).deepEquals(['u', 'u']);
    check(_source(drawing)).equals(compoundLifecycleSource());
  });

  test('disposes only explicitly selected parent metadata and neutral group resets', () {
    final String source = objectSource('''1 Ae *u
4 As $topologyRectangle f
${objectDictionary(identifier: 'Child')}
*U
${objectDictionary(identifier: 'Parent', name: 'Compound')}
9 () XW
4 As $topologyRectangle f
''', setup: '');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(() => drawing.releaseCompounds(groups: drawing.groups, bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing result = drawing.releaseCompounds(groups: drawing.groups, bounds: topologyBounds, discardMetadata: true);
    _retained(drawing, result);
    check(result.groups).isEmpty();
    check(_source(result).contains('Parent')).isFalse();
    check(_source(result).contains('Ae')).isFalse();
    check(_source(result).contains('XW')).isFalse();
    check(_source(result)).contains('Child');
  });

  test('retains clipping scopes and all mask controls when combining and releasing masks', () {
    for (final String body in [
      'q 4 As $topologyRectangle h W n 4 As $topologyRectangle h W n Q',
      'q u q 4 As $topologyRectangle h W n Q q 4 As $topologyRectangle h W n Q U Q',
    ]) {
      final AiNativeDrawing drawing = groupCreationDrawing(objectSource(body));
      final bool direct = body.startsWith('q 4');
      final AiNativeDrawing result = drawing.compoundArtwork(
        paths: direct ? drawing.paths : [],
        groups: direct ? [] : [drawing.groups.firstWhere((group) => group.opening.operator == 'u')],
        bounds: topologyBounds,
        inheritParentFlags: true,
      );
      final AiNativeGroup compound = result.groups.singleWhere((group) => group.compound);
      check(compound.paths.length).equals(2);
      check(result.paths.map((path) => result.pathTopology(path: path).mask)).deepEquals([AiNativePathMask.closed, AiNativePathMask.closed]);
      final AiNativeDrawing released = result.releaseCompounds(groups: [compound], bounds: topologyBounds, inheritParentFlags: true);
      _retained(drawing, released);
      check(released.groups.map((group) => group.opening.operator)).deepEquals(drawing.groups.map((group) => group.opening.operator));
    }
  });

  test('keeps complete neighboring CC pairs and rejects their native or printing paths', () {
    final String source = mixedArtboardSource().replaceFirst('%%Trailer', '0 A 0 Xw 4 As $topologyRectangle f 4 As $topologyRectangle f\n%%Trailer');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeDrawing result = drawing.compoundArtwork(paths: drawing.paths.skip(drawing.paths.length - 2).toList().reversed.toList(), bounds: topologyBounds);
    for (final (int, AiLiveShape) entry in drawing.liveShapes.indexed) {
      final AiLiveShape retained = result.liveShapes[entry.$1];
      check(result.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(drawing.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
      for (final AiNativePath path in [entry.$2.path!, ...entry.$2.appearancePaths]) {
        check(() => drawing.compoundArtwork(paths: [path], bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
      }
    }
    final AiNativeDrawing released = result.releaseCompounds(groups: [result.groups.last], bounds: topologyBounds);
    _retained(drawing, released);
  });

  test('keeps hidden layers and requires explicit inheritance of non-neutral or unknown flags', () {
    for (final String state in ['1 A 1 Xw', '']) {
      final String source = objectSource(movementLayer('Hidden', '$state 4 As $topologyRectangle f 4 As $topologyRectangle f', hidden: true)).replaceFirst(movementState, '');
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      check(() => drawing.compoundArtwork(paths: drawing.paths, bounds: topologyBounds)).throws<UnsupportedError>();
      final AiNativeDrawing result = drawing.compoundArtwork(paths: drawing.paths, bounds: AiBoundingBox(left: -20, bottom: -30, right: 150, top: 160), inheritParentFlags: true);
      check(result.records.program.layers.single.visible).isFalse();
      check(_source(result)).contains('%%BoundingBox: -20 -30 150 160');
      check(() => result.releaseCompounds(groups: result.groups, bounds: topologyBounds)).throws<UnsupportedError>();
      final AiNativeDrawing released = result.releaseCompounds(groups: result.groups, bounds: topologyBounds, inheritParentFlags: true);
      check(released.records.program.layers.single.begin.numbers).isNotNull().deepEquals(drawing.records.program.layers.single.begin.numbers!);
    }
  });

  test('rejects stale handles duplicates skipped siblings and different parents atomically', () {
    final AiNativeDrawing drawing = groupCreationDrawing(compoundLifecycleSource());
    final AiNativeDrawing foreign = groupCreationDrawing(compoundLifecycleSource());
    check(() => drawing.compoundArtwork(bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.compoundArtwork(paths: [drawing.paths.first, drawing.paths.first], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.compoundArtwork(paths: [foreign.paths.first], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.compoundArtwork(paths: [drawing.paths.first, drawing.paths.last], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.compoundArtwork(paths: [drawing.paths[1]], groups: [drawing.groups.last], bounds: topologyBounds)).throws<ArgumentError>();
    final AiNativeDrawing changed = drawing.compoundArtwork(paths: [drawing.paths.first], bounds: topologyBounds);
    check(() => changed.compoundArtwork(paths: [drawing.paths.first], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => changed.compoundArtwork(paths: [changed.paths.first], bounds: topologyBounds)).throws<UnsupportedError>();
    check(() => changed.releaseCompounds(groups: [changed.groups.first, changed.groups.first], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => changed.releaseCompounds(groups: [drawing.groups.last], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.releaseCompounds(groups: drawing.groups, bounds: topologyBounds)).throws<ArgumentError>();
  });

  test('rejects mixed masks opaque fields bad counts and non-contour subgroup owners', () {
    for (final String body in [
      'q 4 As $topologyRectangle h W n 4 As $topologyRectangle f Q',
      '3 As $topologyRectangle f',
      '4 As $topologyRectangle f 1 FuturePaint',
      '4 As $topologyRectangle f ${objectDictionary(extra: '(future) /String (Appearance) ,')}',
    ]) {
      final String source = objectSource(body);
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      expect(() => drawing.compoundArtwork(paths: drawing.paths, bounds: topologyBounds, inheritParentFlags: true), throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())));
      check(_source(drawing)).equals(source);
    }
    for (final String body in ['u U', 'q 4 As $topologyRectangle f Q', 'q u 4 As $topologyRectangle h W n U Q', '*u 4 As $topologyRectangle f *U']) {
      final AiNativeDrawing drawing = groupCreationDrawing(objectSource(body));
      check(() => drawing.compoundArtwork(groups: [drawing.groups.last], bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    }
  });

  test('checks whole-source references before removing a compound identity', () {
    for (final String setup in ['/Dictionary : (Parent) /String (FutureReference) , ;', '']) {
      final AiNativeDrawing drawing = groupCreationDrawing(
        objectSource(
          '*u 4 As $topologyRectangle f *U\n${objectDictionary(identifier: 'Parent')}\n4 As $topologyRectangle f\n${objectDictionary(identifier: 'Parent')}',
          setup: setup,
        ),
      );
      check(() => drawing.releaseCompounds(groups: drawing.groups, bounds: topologyBounds, discardMetadata: true)).throws<UnsupportedError>();
    }
    final AiNativeDrawing opaque = groupCreationDrawing(objectSource('*u 4 As $topologyRectangle f *U ${objectDictionary(identifier: 'Parent')}'));
    check(() => opaque.releaseCompounds(groups: opaque.groups, bounds: topologyBounds, discardMetadata: true)).throws<UnsupportedError>();
  });

  test('retains neighboring compact text but rejects treating it as a compound contour', () {
    final String text = artboardTextDrawing().replaceFirst('1 (board-0) XW', '1 () XW');
    for (final bool inside in [false, true]) {
      for (final bool releasing in [false, true]) {
        final String marker = releasing ? '*' : '';
        final String source = populatedArtboardSource(body: '${inside ? '' : text}${marker}u 4 As $topologyRectangle f\n${inside ? text : ''}${marker}U');
        final AiNativeDrawing drawing = groupCreationDrawing(source);

        /// Applies the requested boundary edit to the current source snapshot.
        AiNativeDrawing edit() => releasing
            ? drawing.releaseCompounds(groups: drawing.groups, bounds: topologyBounds, inheritParentFlags: true)
            : drawing.compoundArtwork(groups: drawing.groups, bounds: topologyBounds, inheritParentFlags: true);
        if (inside) {
          check(edit).throws<UnsupportedError>();
        } else {
          final AiNativeDrawing result = edit();
          _retained(drawing, result);
          check(result.groups.where((group) => group.compound)).length.equals(releasing ? 0 : 1);
        }
        check(_source(drawing)).equals(source);
      }
    }
  });

  test('releases disjoint compound batches and retains original parser and output ceilings', () {
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource(List.filled(200, '*u 4 As $topologyRectangle f 4 As $topologyRectangle f *U').join('\n')));
    final AiNativeDrawing released = drawing.releaseCompounds(groups: drawing.groups, bounds: topologyBounds);
    check(released.groups).isEmpty();
    _retained(drawing, released);
    final String source = compoundLifecycleSource();
    final AiNativeDrawing bounded = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => bounded.compoundArtwork(paths: [bounded.paths.first], bounds: topologyBounds)).throws<FormatException>();
    check(_source(bounded)).equals(source);
    check(() => drawing.compoundArtwork(paths: [drawing.paths.first], bounds: AiBoundingBox(left: 0, bottom: 0, right: 1e20, top: 20))).throws<ArgumentError>();
  });
}
