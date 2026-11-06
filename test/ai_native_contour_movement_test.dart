import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboards_test.dart' show mixedArtboardSource;
import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_contour_metadata_test.dart' show contourMetadataSource;
import 'ai_native_direct_shape_test.dart' show directShape;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds, topologyRectangle;

/// Gives each source contour a distinct identity and initial coordinate.
String contourMovementPath(int x, {String paint = 'S', String mask = ''}) => '2 As $x 0 m ${x + 1} 1 L $mask $paint\n${objectDictionary(identifier: 'P$x')}\n';

/// Exercises shared compound paint, private line state and independent clips.
String contourMovementSource() => objectSource('''0 1 0 0 0 Xy
q 0.2 g 4 w
%_5 w
*u ${contourMovementPath(10)}
0.4 g 9 w
%_13 w
${contourMovementPath(20)}
*U
${objectDictionary(identifier: 'Source')}
Q
0.8 g 2 w
%_3 w
*u ${contourMovementPath(30, paint: 'F')}${contourMovementPath(40, paint: 'F')}*U
${objectDictionary(identifier: 'Target')}
u ${contourMovementPath(50, paint: 'F')}U
${objectDictionary(identifier: 'Destination')}
q ${contourMovementPath(60, paint: 'N', mask: 'H W')}Q
${objectDictionary(identifier: 'Clip')}
${contourMovementPath(70)}
''', setup: '');

/// Resolves an exact current group through its preserved native identity.
AiNativeGroup contourMovementGroup(AiNativeDrawing drawing, String name) =>
    AiNativeObjects.decode(drawing: drawing).objects.singleWhere((owner) => owner.identifier != null && latin1.decode(owner.identifier!.bytes) == name).source as AiNativeGroup;

/// Selects an original contour by its stable coordinate, not a changing index.
AiNativePath contourMovementContour(AiNativeDrawing drawing, int x) => drawing.paths.singleWhere((path) => path.geometry.first.numbers!.first == x);

/// Records literal stroke state at each contour in both scalar projections.
Map<double, List<double?>> _widths(AiNativeDrawing drawing) {
  double? printing;
  double? native;
  final List<List<double?>> stack = [];
  final Map<double, List<double?>> values = {};
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    if (item.operator == 'q') {
      stack.add([printing, native]);
    } else if (item.operator == 'Q') {
      final List<double?> restored = stack.removeLast();
      printing = restored[0];
      native = restored[1];
    } else if (item.operator == 'w') {
      native = item.numbers!.single;
      if (!item.isPrivate) {
        printing = native;
      }
    } else if (item.operator == 'm') {
      values[item.numbers!.first] = [printing, native];
    }
  }
  return values;
}

/// Checks exact retained identities without conflating source and destination order.
void _identities(AiNativeDrawing before, AiNativeDrawing after) {
  final List<String> original = AiNativeObjects.decode(drawing: before).objects.where((owner) => owner.identifier != null).map((owner) => latin1.decode(owner.identifier!.bytes)).toList()..sort();
  final List<String> actual = AiNativeObjects.decode(drawing: after).objects.where((owner) => owner.identifier != null).map((owner) => latin1.decode(owner.identifier!.bytes)).toList()..sort();
  check(actual).deepEquals(original);
}

/// Exercises atomic contour reparenting with explicit compound/mask policies.
void main() {
  test('leaves a compound using its final shared appearance and restores destination state', () {
    final String source = contourMovementSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeDrawing result = drawing.moveContours(
      paths: [contourMovementContour(drawing, 10)],
      group: contourMovementGroup(drawing, 'Destination'),
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    check(result.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([20, 30, 40, 50, 10, 60, 70]);
    check(_widths(result)[10]!).deepEquals([9, 13]);
    check(_widths(result)[50]!).deepEquals([2, 3]);
    check(_widths(result)[70]!).deepEquals([2, 3]);
    check(result.pathTopology(path: contourMovementContour(result, 10)).compound).isNull();
    _identities(drawing, result);
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('requires explicit compound appearance inheritance and preserves contour closure', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourMovementSource());
    final AiNativePath path = contourMovementContour(drawing, 10);
    final AiNativeGroup target = contourMovementGroup(drawing, 'Target');
    check(() => drawing.moveContours(paths: [path], group: target, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    final AiNativeDrawing result = drawing.moveContours(paths: [path], group: target, bounds: topologyBounds, inheritParentFlags: true, inheritCompoundAppearance: true);
    final AiNativePath moved = contourMovementContour(result, 10);
    check(moved.paint.operator).equals('F');
    check(moved.closed).isFalse();
    check(result.pathTopology(path: moved).pointCount!.numbers!).deepEquals([2]);
    check(result.pathTopology(path: moved).compound).identicalTo(contourMovementGroup(result, 'Target'));
    _identities(drawing, result);
  });

  test('reorders an entire compound in caller order and supports direct anchors', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourMovementSource());
    final AiNativeDrawing result = drawing.moveContours(
      paths: [contourMovementContour(drawing, 20), contourMovementContour(drawing, 10)],
      group: contourMovementGroup(drawing, 'Source'),
      bounds: topologyBounds,
    );
    check(result.paths.take(2).map((path) => path.geometry.first.numbers!.first)).deepEquals([20, 10]);
    final AiNativeDrawing inserted = result.moveContours(
      paths: [contourMovementContour(result, 70)],
      group: contourMovementGroup(result, 'Destination'),
      after: contourMovementContour(result, 50),
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    check(inserted.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([20, 10, 30, 40, 50, 70, 60]);
    _identities(drawing, inserted);
  });

  test('moves mask ownership and normalizes counted closure atomically', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourMovementSource());
    final AiNativeDrawing masked = drawing.moveContours(
      paths: [contourMovementContour(drawing, 10)],
      group: contourMovementGroup(drawing, 'Clip'),
      mask: .closed,
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    final AiNativePath moved = contourMovementContour(masked, 10);
    check(moved.geometry.map((item) => item.operator)).deepEquals(['m', 'L', 'L']);
    check(masked.pathTopology(path: moved).mask).equals(AiNativePathMask.closed);
    check(masked.pathTopology(path: moved).pointCount!.numbers!).deepEquals([2]);
    check(() => drawing.moveContours(paths: [contourMovementContour(drawing, 60)], group: contourMovementGroup(drawing, 'Destination'), bounds: topologyBounds, inheritParentFlags: true))
        .throws<UnsupportedError>();
    final AiNativeDrawing cleared = drawing.moveContours(
      paths: [contourMovementContour(drawing, 60), contourMovementContour(drawing, 10)],
      group: contourMovementGroup(drawing, 'Destination'),
      mask: .none,
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    check(cleared.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([20, 30, 40, 50, 60, 10, 70]);
    check(cleared.pathTopology(path: contourMovementContour(cleared, 60)).mask).equals(AiNativePathMask.none);
    _identities(drawing, cleared);
  });

  test('rejects empty compounds mixed masks unresolved state and stale anchors without mutation', () {
    final String source = contourMovementSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeGroup target = contourMovementGroup(drawing, 'Destination');
    check(() => drawing.moveContours(paths: drawing.paths.take(2).toList(), group: target, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    check(
      () => drawing.moveContours(
        paths: [contourMovementContour(drawing, 60)],
        group: contourMovementGroup(drawing, 'Source'),
        bounds: topologyBounds,
        inheritParentFlags: true,
        inheritCompoundAppearance: true,
      ),
    ).throws<UnsupportedError>();
    check(() => drawing.moveContours(paths: [drawing.paths.first], group: target, after: drawing.paths.first, bounds: topologyBounds, inheritParentFlags: true)).throws<ArgumentError>();
    check(() => drawing.moveContours(paths: [drawing.paths.first, drawing.paths.first], group: target, bounds: topologyBounds)).throws<ArgumentError>();
    check(() => drawing.moveContours(paths: [groupCreationDrawing(source).paths.first], group: target, bounds: topologyBounds)).throws<ArgumentError>();
    final AiNativeDrawing unknown = groupCreationDrawing(source.replaceFirst('0.8 g 2 w', '0.8 g').replaceFirst('q 0.2 g 4 w', 'q 0.2 g').replaceFirst('0 A 0 Xw 0.1 g 0 G 2 w', '0 A 0 Xw 0.1 g 0 G'));
    check(() => unknown.moveContours(paths: [unknown.paths.first], group: contourMovementGroup(unknown, 'Destination'), bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('retains imported SVG owner metadata and non-neutral transparency during movement', () {
    final String source = contourMetadataSource(state: '12 0.25 1 2 1 Xy');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeGroup destination = contourMovementGroup(drawing, 'Current');
    final AiNativeDrawing result = drawing.moveContours(paths: [drawing.paths.first], group: destination, bounds: topologyBounds, inheritParentFlags: true);
    final AiNativeGroup compound = contourMovementGroup(result, 'Compound');
    check(compound.paths).length.equals(1);
    check(result.pathTopology(path: result.paths.last).compound).isNull();
    final List<AiNativeContainer> originals = drawing.records.roots.where((record) => record.type == 'ArtDictionary').toList();
    final List<AiNativeContainer> retained = result.records.roots.where((record) => record.type == 'ArtDictionary').toList();
    for (final (int, AiNativeContainer) entry in originals.indexed) {
      check(result.records.program.bytes.sublist(retained[entry.$1].start, retained[entry.$1].end)).deepEquals(drawing.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    }
    _identities(drawing, result);
  });

  test('requires explicit hidden-layer inheritance and preserves complete CC neighbors', () {
    final String body = '${movementLayer('A', 'u ${contourMovementPath(10)}U')}\n${movementLayer('B', 'u ${contourMovementPath(20)}U', hidden: true)}';
    final AiNativeDrawing layered = groupCreationDrawing(objectSource(body, setup: ''));
    check(() => layered.moveContours(paths: [layered.paths.first], group: layered.groups.last, bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing moved = layered.moveContours(paths: [layered.paths.first], group: layered.groups.last, bounds: topologyBounds, inheritParentFlags: true);
    check(moved.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([20, 10]);
    final String source = mixedArtboardSource().replaceFirst('%%Trailer', 'u 4 As $topologyRectangle f 4 As $topologyRectangle f U\nu U\n%%Trailer');
    final AiNativeDrawing mixed = groupCreationDrawing(source);
    final AiNativeDrawing result = mixed.moveContours(paths: [mixed.paths.last], group: mixed.groups.last, bounds: topologyBounds);
    check(result.records.program.bytes.take(mixed.paths[mixed.paths.length - 2].start).toList()).deepEquals(mixed.records.program.bytes.take(mixed.paths[mixed.paths.length - 2].start).toList());
    check(() => mixed.moveContours(paths: [mixed.liveShapes.first.path!], group: mixed.groups.last, bounds: topologyBounds)).throws<UnsupportedError>();
    check(() => mixed.moveContours(paths: [mixed.paths.last], group: mixed.liveShapes.first.appearanceGroup!, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
  });

  test('refuses moving contours across imported matrix owners without a rebase contract', () {
    final String source = contourMetadataSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(() => drawing.moveContours(paths: [drawing.paths.first], group: contourMovementGroup(drawing, 'View'), bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('never splits direct or paired live shapes through a contour insertion anchor', () {
    final String mixed = mixedArtboardSource();
    final AiLiveShape pair = groupCreationDrawing(mixed).liveShapes.first;
    final String wrapped = mixed.replaceRange(pair.start, pair.end, 'u\n${mixed.substring(pair.start, pair.end)}\nU\n').replaceFirst('%%Trailer', '${contourMovementPath(90)}\n%%Trailer');
    for (final String source in [objectSource('u ${directShape(30)}\nU\n${contourMovementPath(90)}', setup: ''), wrapped]) {
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      final AiNativePath anchor = drawing.liveShapes.first.path!;
      final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
      final AiNativeGroup parent = structure.parentOf(structure.nodeFor(anchor))!.source as AiNativeGroup;
      check(parent.opening.operator).equals('u');
      check(() => drawing.moveContours(paths: [drawing.paths.last], group: parent, after: anchor, bounds: topologyBounds, inheritParentFlags: true))
          .throws<UnsupportedError>()
          .has((error) => error.message, 'message')
          .isNotNull()
          .contains('authoritative ordinary geometry');
      check(latin1.decode(drawing.records.program.bytes)).equals(source);
    }
  });

  test('moves owned counts without consuming intervening scalar assignments', () {
    final String source = contourMovementSource().replaceFirst('2 As 70 0 m', '2 As 6 w\n%_8 w\n70 0 m');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeDrawing result = drawing.moveContours(paths: [drawing.paths.last], group: contourMovementGroup(drawing, 'Destination'), bounds: topologyBounds, inheritParentFlags: true);
    check(_widths(result)[70]!).deepEquals([6, 8]);
    check(_widths(result)[60]!).deepEquals([2, 3]);
    check(latin1.decode(result.records.program.bytes)).contains(' 6 w\n%_8 w\n ');
    check(result.pathTopology(path: contourMovementContour(result, 70)).pointCount!.numbers!).deepEquals([2]);
    _identities(drawing, result);
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('refuses empty compound branches and differing shared paint modes atomically', () {
    final String branch = objectSource('*u u ${contourMovementPath(10)}U\n${contourMovementPath(20)}*U\nu U', setup: '');
    final String mixed = contourMovementSource().replaceFirst(contourMovementPath(20), contourMovementPath(20, paint: 'F'));
    for (final String source in [branch, mixed]) {
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      check(() => drawing.moveContours(paths: [drawing.paths.first], group: drawing.groups.last, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
      check(latin1.decode(drawing.records.program.bytes)).equals(source);
    }
  });

  test('preserves aggregate parser ceilings when replaying many disjoint contours', () {
    final String source = contourMovementSource();
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length + 2));
    check(() => limited.moveContours(paths: [limited.paths.first], group: contourMovementGroup(limited, 'Destination'), bounds: topologyBounds, inheritParentFlags: true)).throws<FormatException>();
    final String batchSource = objectSource('u ${[for (int index = 0; index < 200; index++) contourMovementPath(index)].join()}U\nu U', setup: '');
    final AiNativeDrawing batch = groupCreationDrawing(batchSource);
    final AiNativeDrawing result = batch.moveContours(paths: batch.paths.reversed.toList(), group: batch.groups.last, bounds: topologyBounds);
    check(result.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([for (int index = 199; index >= 0; index--) index]);
    check(result.groups.first.paths).isEmpty();
    _identities(batch, result);
    final AiNativeDrawing maskBatch = groupCreationDrawing(batchSource.replaceFirst('U\nu U', 'U\nq Q'));
    final AiNativeDrawing masked = maskBatch.moveContours(paths: maskBatch.paths.reversed.toList(), group: maskBatch.groups.last, mask: .closed, bounds: topologyBounds);
    check(masked.paths.every((path) => path.geometry.length == 3 && masked.pathTopology(path: path).mask == .closed)).isTrue();
  });
}
