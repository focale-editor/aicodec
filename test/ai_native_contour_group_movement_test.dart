import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboards_test.dart' show mixedArtboardSource;
import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_contour_metadata_test.dart' show contourMetadataSource;
import 'ai_native_contour_movement_test.dart' show contourMovementGroup, contourMovementPath;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds;

/// Supplies complete compound/clip trees with distinct private contour attributes.
String contourGroupMovementSource() => objectSource('''0 1 0 0 0 Xy
q 4 w
%_5 w
*u ${contourMovementPath(10)}
9 w
%_13 w
${contourMovementPath(20)}*U
${objectDictionary(identifier: 'Compound')}
7 w
%_11 w
u ${contourMovementPath(25)}U
${objectDictionary(identifier: 'Small')}
Q
${objectDictionary(identifier: 'Source')}
0.8 g 2 w
%_3 w
u ${contourMovementPath(30)}
q 6 w
%_8 w
${contourMovementPath(40, paint: 'N', mask: 'H W')}${contourMovementPath(50)}Q
${objectDictionary(identifier: 'Clip')}
U
${objectDictionary(identifier: 'Target')}
u U
${objectDictionary(identifier: 'Empty')}
${contourMovementPath(60)}
''', setup: '');

/// Reads consumed stroke widths, including deferred compound paint and clipping.
Map<double, List<double?>> contourGroupWidths(AiNativeDrawing drawing) {
  final Map<double, List<double?>> values = {};
  final List<List<double?>?> clips = [];
  final List<double> compound = [];
  List<double?> widths = [null, null];
  bool collecting = false;
  for (final AiNativeInstruction item in drawing.items.whereType<AiNativeInstruction>()) {
    switch (item.operator) {
      case 'w':
        widths[1] = item.numbers!.single;
        if (!item.isPrivate) {
          widths[0] = widths[1];
        }
      case '*u':
        collecting = true;
      case '*U':
        for (final double coordinate in compound) {
          values[coordinate] = List.of(widths);
        }
        compound.clear();
        collecting = false;
      case 'q':
        clips.add(collecting ? null : List.of(widths));
      case 'Q':
        widths = clips.removeLast() ?? widths;
      case 'm':
        final double coordinate = item.numbers!.first;
        if (collecting) {
          compound.add(coordinate);
        } else {
          values[coordinate] = List.of(widths);
        }
    }
  }
  return values;
}

/// Requires exact bytes and identities for every moved complete source owner.
void _retained(AiNativeDrawing before, AiNativeDrawing after, List<String> groups) {
  final AiNativeObjects original = AiNativeObjects.decode(drawing: before);
  final AiNativeObjects result = AiNativeObjects.decode(drawing: after);
  for (final String name in groups) {
    final AiNativeObject first = original.forSource(contourMovementGroup(before, name));
    final AiNativeObject last = result.forSource(contourMovementGroup(after, name));
    check(after.records.program.bytes.sublist(last.start, last.end)).deepEquals(before.records.program.bytes.sublist(first.start, first.end));
  }
  check(contourGroupWidths(after)).deepEquals(contourGroupWidths(before));
  check(result.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes)).toList()..sort()).deepEquals(
    original.structure.identifiers.map((identifier) => latin1.decode(identifier.bytes)).toList()..sort(),
  );
}

/// Exercises immutable complete-owner transactions independently of host rendering.
void main() {
  test('moves a complete compound and preserves its deferred common appearance', () {
    final String source = contourGroupMovementSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeDrawing moved = drawing.moveContourGroups(groups: [contourMovementGroup(drawing, 'Compound')], parent: contourMovementGroup(drawing, 'Target'), bounds: topologyBounds);
    _retained(drawing, moved, ['Compound']);
    check(moved.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([25, 30, 40, 50, 10, 20, 60]);
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('moves a complete clip and keeps its internal scopes and mask ownership', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourGroupMovementSource());
    check(() => drawing.moveContourGroups(groups: [contourMovementGroup(drawing, 'Source')], parent: contourMovementGroup(drawing, 'Target'), bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing moved = drawing.moveContourGroups(
      groups: [contourMovementGroup(drawing, 'Source')],
      parent: contourMovementGroup(drawing, 'Target'),
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    _retained(drawing, moved, ['Source', 'Clip']);
    final AiNativePath mask = moved.paths.singleWhere((path) => path.geometry.first.numbers!.first == 40);
    check(moved.pathTopology(path: mask).clippingGroup).identicalTo(contourMovementGroup(moved, 'Clip'));
  });

  test('moves disjoint trees in caller order and supports an ordinary group anchor', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourGroupMovementSource());
    final AiNativeDrawing moved = drawing.moveContourGroups(
      groups: [contourMovementGroup(drawing, 'Target'), contourMovementGroup(drawing, 'Source')],
      parent: contourMovementGroup(drawing, 'Empty'),
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    _retained(drawing, moved, ['Source', 'Target']);
    check(moved.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([30, 40, 50, 10, 20, 25, 60]);
    final AiNativeDrawing reordered = drawing.moveContourGroups(
      groups: [contourMovementGroup(drawing, 'Compound')],
      parent: contourMovementGroup(drawing, 'Source'),
      after: contourMovementGroup(drawing, 'Small'),
      bounds: topologyBounds,
    );
    _retained(drawing, reordered, ['Compound']);
    check(reordered.paths.take(3).map((path) => path.geometry.first.numbers!.first)).deepEquals([25, 10, 20]);
  });

  test('moves compound masks only under a complete effective clipping owner', () {
    final String source = objectSource(
      'q *u ${contourMovementPath(10, mask: 'H W')}${contourMovementPath(20, mask: 'H W')}*U Q\nq Q\nu U',
      setup: '',
    );
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeGroup compound = drawing.groups.singleWhere((group) => group.compound);
    check(() => drawing.moveContourGroups(groups: [compound], parent: drawing.groups.last, bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeGroup destination = drawing.groups[drawing.groups.length - 2];
    final AiNativeDrawing moved = drawing.moveContourGroups(groups: [compound], parent: destination, bounds: topologyBounds);
    final AiNativeGroup clip = moved.groups.singleWhere((group) => group.opening.operator == 'q' && group.paths.isNotEmpty);
    check(moved.paths.every((path) => identical(moved.pathTopology(path: path).clippingGroup, clip))).isTrue();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('tracks inherited reads after nested clips and at deferred compound paint', () {
    final String clipped = objectSource('u q 8 w\n%_9 w\n${contourMovementPath(10)}Q\n${contourMovementPath(20)}U\n6 w\nu U', setup: '');
    final AiNativeDrawing drawing = groupCreationDrawing(clipped);
    final AiNativeDrawing moved = drawing.moveContourGroups(groups: [drawing.groups[1]], parent: drawing.groups.last, bounds: topologyBounds, inheritParentFlags: true);
    check(contourGroupWidths(moved)).deepEquals({
      10: [8, 9],
      20: [2, 2],
    });
    final String deferred = objectSource('*u ${contourMovementPath(10)}8 w ${contourMovementPath(20)}*U\n6 w u U', setup: '').replaceFirst('2 w', '');
    final AiNativeDrawing compound = groupCreationDrawing(deferred);
    final AiNativeDrawing result = compound.moveContourGroups(groups: [compound.groups.first], parent: compound.groups.last, bounds: topologyBounds, inheritParentFlags: true);
    check(contourGroupWidths(result)).deepEquals({
      10: [8, 8],
      20: [8, 8],
    });
  });

  test('moves complete owners to layers or the document root with explicit inheritance', () {
    final String source = objectSource('${movementLayer('A', '*u ${contourMovementPath(10)}*U')}\n${movementLayer('B', 'u U', hidden: true)}', setup: '');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
    final AiNativeDrawing moved = drawing.moveContourGroups(groups: [drawing.groups.first], layer: layers.layers.last.source, bounds: topologyBounds, inheritParentFlags: true);
    final AiNativeStructure ownership = AiNativeStructure.decode(drawing: moved);
    check(ownership.parentOf(ownership.nodeFor(moved.paths.single))!.kind).equals(AiNativeStructureKind.compound);
    final AiNativeGroup compound = moved.groups.singleWhere((group) => group.compound);
    final AiNativeStructureNode parent = ownership.parentOf(ownership.nodeFor(compound))!;
    check(parent.source).identicalTo(AiNativeLayers.decode(drawing: moved).layers.last.source);
    final AiNativeDrawing rooted = drawing.moveContourGroups(groups: [drawing.groups.first], bounds: topologyBounds, inheritParentFlags: true);
    final AiNativeStructure rootOwnership = AiNativeStructure.decode(drawing: rooted);
    check(rootOwnership.parentOf(rootOwnership.nodeFor(rooted.groups.last))).isNull();
    check(() => drawing.moveContourGroups(groups: [drawing.groups.first], parent: drawing.groups.last, layer: layers.layers.last.source, bounds: topologyBounds)).throws<ArgumentError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('permits unknown output only when overwritten before retained consumers', () {
    for (final String assignment in ['8 w', '%_8 w\n']) {
      final String source = objectSource('u U\nu $assignment ${contourMovementPath(10)}U', setup: '').replaceFirst('2 w', '');
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      final AiNativeDrawing moved = drawing.moveContourGroups(groups: [drawing.groups.last], parent: drawing.groups.first, bounds: topologyBounds, inheritParentFlags: true);
      check(contourGroupWidths(moved)).deepEquals(contourGroupWidths(drawing));
      final String consumed = source.replaceFirst('u U', 'u U\n${contourMovementPath(20)}');
      final AiNativeDrawing unsafe = groupCreationDrawing(consumed);
      check(() => unsafe.moveContourGroups(groups: [unsafe.groups.last], parent: unsafe.groups.first, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
      check(latin1.decode(unsafe.records.program.bytes)).equals(consumed);
    }
    for (final String opaque in ['*u *U', '*u *u ${contourMovementPath(30)}*U *U']) {
      final String source = objectSource('u U\n$opaque\nu 8 w ${contourMovementPath(10)}U', setup: '').replaceFirst('2 w', '');
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      check(() => drawing.moveContourGroups(groups: [drawing.groups.last], parent: drawing.groups.first, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
      check(latin1.decode(drawing.records.program.bytes)).equals(source);
    }
  });

  test('tracks unresolved attributes through saved and enclosing clipping scopes', () {
    final String saved = objectSource('u U\nq 2 w ${contourMovementPath(20)}Q\n${contourMovementPath(30)}u 8 w ${contourMovementPath(10)}U', setup: '').replaceFirst('2 w', '');
    final AiNativeDrawing drawing = groupCreationDrawing(saved);
    check(() => drawing.moveContourGroups(groups: [drawing.groups.last], parent: drawing.groups.first, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
    final String reset = saved.replaceFirst(contourMovementPath(30), '');
    final AiNativeDrawing safe = groupCreationDrawing(reset);
    check(contourGroupWidths(safe.moveContourGroups(groups: [safe.groups.last], parent: safe.groups.first, bounds: topologyBounds, inheritParentFlags: true))).deepEquals(contourGroupWidths(safe));
    final String enclosing = objectSource('q u U Q\n${contourMovementPath(20)}u 8 w ${contourMovementPath(10)}U', setup: '').replaceFirst('2 w', '');
    final AiNativeDrawing scoped = groupCreationDrawing(enclosing);
    check(contourGroupWidths(scoped.moveContourGroups(groups: [scoped.groups.last], parent: scoped.groups.first, bounds: topologyBounds, inheritParentFlags: true)))
        .deepEquals(contourGroupWidths(scoped));
  });

  test('retains imported group matrices while refusing a changed outer coordinate basis', () {
    final String source = contourMetadataSource().replaceFirst('u U', '0 1 0 2 0 Xy u U');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeGroup current = contourMovementGroup(drawing, 'Current');
    final AiNativeGroup view = contourMovementGroup(drawing, 'View');
    final AiNativeDrawing moved = drawing.moveContourGroups(groups: [current], parent: view, bounds: topologyBounds, inheritParentFlags: true);
    _retained(drawing, moved, ['Current']);
    check(() => drawing.moveContourGroups(groups: [contourMovementGroup(drawing, 'Compound')], parent: view, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
  });

  test('requires hidden-layer inheritance and preserves complete CC neighbors', () {
    final String layered = objectSource('${movementLayer('A', '*u ${contourMovementPath(10)}*U')}\n${movementLayer('B', 'q Q', hidden: true)}', setup: '');
    final AiNativeDrawing drawing = groupCreationDrawing(layered);
    check(() => drawing.moveContourGroups(groups: [drawing.groups.first], parent: drawing.groups.last, bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing moved = drawing.moveContourGroups(groups: [drawing.groups.first], parent: drawing.groups.last, bounds: topologyBounds, inheritParentFlags: true);
    check(moved.paths).length.equals(1);
    final String source = mixedArtboardSource().replaceFirst('%%Trailer', '*u ${contourMovementPath(90)}*U\nu U\n%%Trailer');
    final AiNativeDrawing mixed = groupCreationDrawing(source);
    final AiNativeDrawing retained = mixed.moveContourGroups(groups: [mixed.groups[mixed.groups.length - 2]], parent: mixed.groups.last, bounds: topologyBounds, inheritParentFlags: true);
    for (final (int, AiLiveShape) entry in mixed.liveShapes.indexed) {
      final AiLiveShape shape = retained.liveShapes[entry.$1];
      check(retained.records.program.bytes.sublist(shape.start, shape.end)).deepEquals(mixed.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
    }
    check(() => mixed.moveContourGroups(groups: [mixed.liveShapes.first.appearanceGroup!], parent: mixed.groups.last, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
  });

  test('rejects overlapping stale foreign and cyclic owner selections without mutation', () {
    final String source = contourGroupMovementSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeGroup root = contourMovementGroup(drawing, 'Source');
    final AiNativeGroup child = contourMovementGroup(drawing, 'Compound');
    final AiNativeGroup target = contourMovementGroup(drawing, 'Target');
    for (final List<AiNativeGroup> groups in <List<AiNativeGroup>>[
      [],
      [root, root],
      [root, child],
      [groupCreationDrawing(source).groups.first],
    ]) {
      check(() => drawing.moveContourGroups(groups: groups, parent: target, bounds: topologyBounds, inheritParentFlags: true)).throws<ArgumentError>();
    }
    check(() => drawing.moveContourGroups(groups: [root], parent: contourMovementGroup(drawing, 'Small'), bounds: topologyBounds, inheritParentFlags: true)).throws<ArgumentError>();
    check(() => drawing.moveContourGroups(groups: [child], parent: root, after: child, bounds: topologyBounds)).throws<ArgumentError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('rejects unknown state and split point-count ownership', () {
    final String counted = objectSource('2 As u 10 0 m 11 1 L S U\nu U', setup: '');
    final String unknown = objectSource('q u 8 w ${contourMovementPath(10)}U Q\nu U', setup: '').replaceFirst('2 w', '');
    for (final String source in [counted, unknown]) {
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      check(() => drawing.moveContourGroups(groups: [drawing.groups.first], parent: drawing.groups.last, bounds: topologyBounds, inheritParentFlags: true)).throws<UnsupportedError>();
      check(latin1.decode(drawing.records.program.bytes)).equals(source);
    }
  });

  test('keeps aggregate byte ceilings and handles batches of complete masked trees', () {
    final String source = contourGroupMovementSource();
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length + 1));
    check(() => limited.moveContourGroups(groups: [contourMovementGroup(limited, 'Compound')], parent: contourMovementGroup(limited, 'Target'), bounds: topologyBounds)).throws<FormatException>();
    final AiNativeDrawing batch = groupCreationDrawing(objectSource('${[for (int index = 0; index < 100; index++) 'q *u ${contourMovementPath(index, mask: 'H W')}*U Q'].join('\n')}\nu U', setup: ''));
    final AiNativeDrawing moved = batch.moveContourGroups(
      groups: batch.groups.where((group) => group.opening.operator == 'q').toList().reversed.toList(),
      parent: batch.groups.last,
      bounds: topologyBounds,
      inheritParentFlags: true,
    );
    check(moved.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([for (int index = 99; index >= 0; index--) index]);
    check(moved.paths.every((path) => moved.pathTopology(path: path).mask == .open)).isTrue();
  });
}
