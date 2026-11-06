import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboards_test.dart' show mixedArtboardSource;
import 'ai_native_artwork_movement_test.dart' show movementLayer, movementState;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds, topologyRectangle;

/// Ordinary siblings with differing contour state and an unaffected final peer.
String clippingLifecycleSource() => objectSource('''3 As 0 0 m 20 0 L 20 20 L N
${objectDictionary(identifier: 'Mask')}
1 J 2 j 7 w 4 M [2 3] 1 d
%_9 w
4 As $topologyRectangle f
${objectDictionary(identifier: 'Content')}
4 As $topologyRectangle f
''', setup: '');

/// Reads the complete immutable native source without reserialization.
String _source(AiNativeDrawing drawing) => latin1.decode(drawing.records.program.bytes);

/// Selects the first two siblings, making the first a new closed clipping contour.
AiNativeDrawing createClippingFixture(AiNativeDrawing drawing) => drawing.clipArtwork(
  paths: drawing.paths.take(2).toList(),
  masks: [AiNativePathEdit(path: drawing.paths.first, mask: .closed)],
  bounds: topologyBounds,
);

/// Requires all existing saved path identities to remain in their source order.
void _identities(AiNativeDrawing before, AiNativeDrawing after) {
  final AiNativeObjects old = AiNativeObjects.decode(drawing: before);
  final AiNativeObjects current = AiNativeObjects.decode(drawing: after);
  check(after.paths.map((path) => current.forSource(path).identifier?.bytes)).deepEquals(before.paths.map((path) => old.forSource(path).identifier?.bytes));
}

/// Exercises atomic mask ownership and source-derived contour state restoration.
void main() {
  test('creates a complete clipping scope with normalized mask counts and outgoing state', () {
    final AiNativeDrawing drawing = groupCreationDrawing(clippingLifecycleSource());
    final AiNativeDrawing result = createClippingFixture(drawing);
    check(result.groups.single.opening.operator).equals('q');
    check(result.groups.single.paths.length).equals(2);
    check(result.paths.first.geometry.length).equals(4);
    check(result.pathTopology(path: result.paths.first).pointCount!.numbers).isNotNull().deepEquals([3]);
    check(result.pathTopology(path: result.paths.first).mask).equals(AiNativePathMask.closed);
    check(result.pathTopology(path: result.paths.last).clippingGroup).isNull();
    final String suffix = _source(result).substring(result.groups.single.closing.end);
    ['1 J', '2 j', '7 w', '4 M', '[2 3] 1 d', '%_9 w'].forEach(check(suffix).contains);
    _identities(drawing, result);
    final AiNativeDrawing released = result.releaseClippingGroups(groups: result.groups, bounds: topologyBounds);
    check(released.groups).isEmpty();
    check(released.pathTopology(path: released.paths.first).mask).equals(AiNativePathMask.none);
    check(released.pathTopology(path: released.paths.first).pointCount!.numbers).isNotNull().deepEquals([4]);
    _identities(drawing, released);
    check(_source(drawing)).equals(clippingLifecycleSource());
  });

  test('releases only the selected outer masks and retains nested clipping scopes', () {
    final AiNativeDrawing drawing = groupCreationDrawing(
      objectSource('q 4 As $topologyRectangle h W n q 4 As $topologyRectangle H W f 8 w 4 As $topologyRectangle f Q 5 w 4 As $topologyRectangle f Q 4 As $topologyRectangle f'),
    );
    final AiNativeDrawing result = drawing.releaseClippingGroups(groups: [drawing.groups.last], bounds: topologyBounds);
    check(result.groups.length).equals(1);
    check(result.paths.map((path) => result.pathTopology(path: path).mask))
        .deepEquals([AiNativePathMask.none, AiNativePathMask.open, AiNativePathMask.none, AiNativePathMask.none, AiNativePathMask.none]);
    check(_source(result)).contains('2 w');
    final AiNativeGroup original = drawing.groups.first;
    final AiNativeGroup retained = result.groups.single;
    check(result.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(drawing.records.program.bytes.sublist(original.start, original.end));
  });

  test('creates and releases a complete compound mask without selecting its expansion independently', () {
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource('*u 4 As $topologyRectangle f 4 As $topologyRectangle f *U 4 As $topologyRectangle f'));
    check(
      () => drawing.clipArtwork(
        groups: drawing.groups,
        paths: [drawing.paths.last],
        masks: [AiNativePathEdit(path: drawing.paths.first, mask: .closed)],
        bounds: topologyBounds,
      ),
    ).throws<UnsupportedError>();
    final AiNativeDrawing result = drawing.clipArtwork(
      groups: drawing.groups,
      paths: [drawing.paths.last],
      masks: [for (final AiNativePath path in drawing.groups.single.paths) AiNativePathEdit(path: path, mask: .closed)],
      bounds: topologyBounds,
    );
    check(result.groups.map((group) => group.opening.operator)).deepEquals(['*u', 'q']);
    check(result.pathTopology(path: result.paths.first).clippingGroup).identicalTo(result.groups.last);
    final AiNativeDrawing released = result.releaseClippingGroups(groups: [result.groups.last], bounds: topologyBounds);
    check(released.groups.single.compound).isTrue();
    check(released.paths.map((path) => released.pathTopology(path: path).mask)).every((mask) => mask.equals(AiNativePathMask.none));
  });

  test('requires explicit parent metadata disposal and checks removed identities', () {
    final String body = '1 Ae q 4 As $topologyRectangle h W n\n${objectDictionary(identifier: 'Child')}\n7 w Q\n${objectDictionary(identifier: 'Parent')}\n9 () XW\n4 As $topologyRectangle f';
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource(body, setup: ''));
    check(() => drawing.releaseClippingGroups(groups: drawing.groups, bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing result = drawing.releaseClippingGroups(groups: drawing.groups, bounds: topologyBounds, discardMetadata: true);
    _identities(drawing, result);
    check(_source(result).contains('Parent')).isFalse();
    check(_source(result).contains('Ae')).isFalse();
    check(_source(result).contains('XW')).isFalse();
    final AiNativeDrawing opaque = groupCreationDrawing(objectSource(body));
    check(() => opaque.releaseClippingGroups(groups: opaque.groups, bounds: topologyBounds, discardMetadata: true)).throws<UnsupportedError>();
  });

  test('normalizes compound mask branches while retaining subgroup identities', () {
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource('*u u 4 As $topologyRectangle f U\n${objectDictionary(identifier: 'Leaf')}\n4 As $topologyRectangle f *U'));
    final AiNativeDrawing result = drawing.clipArtwork(
      groups: [drawing.groups.last],
      masks: [for (final AiNativePath path in drawing.paths) AiNativePathEdit(path: path, mask: .closed)],
      bounds: topologyBounds,
    );
    check(result.groups.map((group) => group.opening.operator)).deepEquals(['q', '*u', 'q']);
    check(result.pathTopology(path: result.paths.first).clippingGroup).identicalTo(result.groups.last);
    final AiNativeDrawing released = result.releaseClippingGroups(groups: [result.groups.last], bounds: topologyBounds);
    check(released.groups.map((group) => group.opening.operator)).deepEquals(['u', '*u']);
    check(_source(released)).contains('(Leaf)');
    _identities(drawing, released);
  });

  test('retains complete CC neighbors while rejecting selection of either shape representation', () {
    final AiNativeDrawing drawing = groupCreationDrawing(mixedArtboardSource().replaceFirst('%%Trailer', '0 A 0 Xw 4 As $topologyRectangle f 4 As $topologyRectangle f\n%%Trailer'));
    final AiNativeDrawing result = drawing.clipArtwork(
      paths: drawing.paths.skip(drawing.paths.length - 2).toList(),
      masks: [AiNativePathEdit(path: drawing.paths[drawing.paths.length - 2], mask: .open)],
      bounds: topologyBounds,
    );
    for (final (int, AiLiveShape) entry in drawing.liveShapes.indexed) {
      final AiLiveShape retained = result.liveShapes[entry.$1];
      check(result.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(drawing.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
      for (final AiNativePath path in [entry.$2.path!, ...entry.$2.appearancePaths]) {
        check(
          () => drawing.clipArtwork(
            paths: [path],
            masks: [AiNativePathEdit(path: path, mask: .open)],
            bounds: topologyBounds,
            inheritParentFlags: true,
          ),
        ).throws<UnsupportedError>();
      }
    }
  });

  test('keeps hidden layer flags and uses explicit bounds and inheritance policies', () {
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource(movementLayer('Hidden', '1 A 1 Xw 4 As $topologyRectangle f', hidden: true)));
    final List<AiNativePathEdit> masks = [AiNativePathEdit(path: drawing.paths.single, mask: .open)];
    check(() => drawing.clipArtwork(paths: drawing.paths, masks: masks, bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing result = drawing.clipArtwork(paths: drawing.paths, masks: masks, bounds: AiBoundingBox(left: -30, bottom: -20, right: 130, top: 140), inheritParentFlags: true);
    check(_source(result)).contains('%%BoundingBox: -30 -20 130 140');
    check(result.records.program.layers.single.visible).isFalse();
    check(() => result.releaseClippingGroups(groups: result.groups, bounds: topologyBounds)).throws<UnsupportedError>();
    check(result.releaseClippingGroups(groups: result.groups, bounds: topologyBounds, inheritParentFlags: true).groups).isEmpty();
  });

  test('rejects invalid owners stale selections skipped siblings and masks owned by nested scopes', () {
    final AiNativeDrawing drawing = groupCreationDrawing(clippingLifecycleSource());
    final List<AiNativePathEdit> masks = [AiNativePathEdit(path: drawing.paths.first, mask: .open)];
    check(() => drawing.clipArtwork(paths: drawing.paths, masks: [], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.clipArtwork(paths: drawing.paths, masks: [masks.first, masks.first], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.clipArtwork(paths: [drawing.paths.first, drawing.paths.last], masks: masks, bounds: topologyBounds)).throws<UnsupportedError>();
    check(() => drawing.clipArtwork(paths: [drawing.paths.first, drawing.paths.first], masks: masks, bounds: topologyBounds)).throws<ArgumentError>();
    final AiNativeDrawing result = createClippingFixture(drawing);
    check(() => result.clipArtwork(paths: drawing.paths, masks: masks, bounds: topologyBounds)).throws<ArgumentError>();
    check(() => result.releaseClippingGroups(groups: [result.groups.single, result.groups.single], bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.releaseClippingGroups(groups: result.groups, bounds: topologyBounds)).throws<ArgumentError>();
    check(
      () => result.clipArtwork(
        groups: result.groups,
        masks: [AiNativePathEdit(path: result.paths.first, mask: .closed)],
        bounds: topologyBounds,
      ),
    ).throws<ArgumentError>();
  });

  test('rejects malformed opacity and unknown outgoing contour restoration atomically', () {
    for (final String state in ['16 0.5 0 0 0 Xy', '7 w']) {
      final String source = objectSource('q $state 4 As $topologyRectangle h W n Q').replaceFirst(movementState, '0 A 0 Xw');
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      check(() => drawing.releaseClippingGroups(groups: drawing.groups, bounds: topologyBounds)).throws<UnsupportedError>();
      check(_source(drawing)).equals(source);
    }
  });

  test('preserves contour state when compound mask leaves become active or inactive', () {
    final AiNativeDrawing drawing = groupCreationDrawing(
      objectSource('q u q 7 w 4 As $topologyRectangle h W n Q q 9 w 4 As $topologyRectangle h W n Q U 4 As $topologyRectangle f Q 4 As $topologyRectangle f'),
    );
    final AiNativeGroup branch = drawing.groups.firstWhere((group) => group.opening.operator == 'u');
    final AiNativeDrawing compound = drawing.compoundArtwork(groups: [branch], bounds: topologyBounds, inheritParentFlags: true);
    check('2 w'.allMatches(_source(compound)).length).equals(3);
    check(compound.pathTopology(path: compound.paths.first).clippingGroup).identicalTo(compound.groups.last);
    final AiNativeDrawing released = compound.releaseCompounds(groups: compound.groups.where((group) => group.compound).toList(), bounds: topologyBounds, inheritParentFlags: true);
    check(released.groups.map((group) => group.opening.operator)).deepEquals(drawing.groups.map((group) => group.opening.operator));
    final AiNativeDrawing unbounded = groupCreationDrawing(objectSource('u q 4 As $topologyRectangle h W n Q U'));
    check(() => unbounded.compoundArtwork(groups: [unbounded.groups.last], bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing malformed = groupCreationDrawing(objectSource('*u q 4 As $topologyRectangle h W n Q *U'));
    check(() => malformed.pathTopology(path: malformed.paths.single)).throws<UnsupportedError>();
  });

  test('keeps immutable inputs and aggregate limits when releasing many disjoint clips', () {
    final AiNativeDrawing drawing = groupCreationDrawing(objectSource(List.filled(200, 'q 7 w 4 As $topologyRectangle h W n Q').join('\n')));
    final AiNativeDrawing result = drawing.releaseClippingGroups(groups: drawing.groups, bounds: topologyBounds);
    check(result.groups).isEmpty();
    check(result.paths.length).equals(200);
    check('2 w'.allMatches(_source(result)).length).equals(201);
    final String source = clippingLifecycleSource();
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => createClippingFixture(limited)).throws<FormatException>();
    check(_source(limited)).equals(source);
    final String dash = '[${List.filled(200, '2 3').join(' ')}] 0 d';
    final String aggregate = objectSource('$dash\n${List.filled(80, 'q [] 0 d 4 As $topologyRectangle h W n Q').join('\n')}');
    final AiNativeDrawing bounded = groupCreationDrawing(aggregate, limits: AiNativeLimits(maxDecodedBytes: aggregate.length * 2));
    check(() => bounded.releaseClippingGroups(groups: bounded.groups, bounds: topologyBounds)).throws<FormatException>();
    check(_source(bounded)).equals(aggregate);
  });
}
