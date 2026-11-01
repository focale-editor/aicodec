import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_contour_group_movement_test.dart' show contourGroupWidths;
import 'ai_native_contour_movement_test.dart' show contourMovementContour, contourMovementGroup, contourMovementPath;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds;

/// Exercises compound branches with different local and deferred paint values.
String contourBranchSource({bool mask = false}) {
  final String control = mask ? 'H W' : '';
  final String opening = mask ? 'q' : 'u';
  final String closing = mask ? 'Q' : 'U';
  return objectSource('''0 1 0 0 0 Xy
q 4 w
%_5 w
*u $opening ${contourMovementPath(10, mask: control)}
6 w
%_7 w
${contourMovementPath(11, mask: control)}$closing
${objectDictionary(identifier: 'Branch')}
$opening ${contourMovementPath(20, mask: control)}$closing
${objectDictionary(identifier: 'Sibling')}
9 w
%_13 w
*U
${objectDictionary(identifier: 'Source')}
Q
0.8 g 2 w
%_3 w
q *u $opening ${contourMovementPath(30, paint: 'F', mask: control)}$closing
${objectDictionary(identifier: 'TargetBranch')}
*U
${objectDictionary(identifier: 'Target')}
Q
u ${contourMovementPath(40)}U
${objectDictionary(identifier: 'Destination')}
${contourMovementPath(50)}
''', setup: '');
}

/// Supplies an ordinary mask branch containing two distinct clipping leaves.
String contourBranchTreeSource() =>
    contourBranchSource(mask: true).replaceFirst('*u q', '*u u q').replaceFirst('9 w', 'U\n${objectDictionary(identifier: 'Tree')}\n${contourMovementPath(25, mask: 'H W')}9 w');

/// Moves a named branch through the same public API used for complete groups.
AiNativeDrawing moveContourBranch(AiNativeDrawing drawing, String group, String parent, {bool inheritCompoundAppearance = false}) => drawing.moveContourGroups(
  groups: [contourMovementGroup(drawing, group)],
  parent: contourMovementGroup(drawing, parent),
  bounds: topologyBounds,
  inheritCompoundAppearance: inheritCompoundAppearance,
  inheritParentFlags: true,
);

/// Checks exact owned dictionaries and geometry independently of inserted state.
void _retained(AiNativeDrawing before, AiNativeDrawing after) {
  final AiNativeObjects original = AiNativeObjects.decode(drawing: before);
  final AiNativeObjects actual = AiNativeObjects.decode(drawing: after);
  final Map<String, AiNativeObject> result = {for (final AiNativeObject owner in actual.objects.where((owner) => owner.identifier != null)) latin1.decode(owner.identifier!.bytes): owner};
  for (final AiNativeObject owner in original.objects.where((owner) => owner.identifier != null)) {
    final AiNativeObject changed = result.remove(latin1.decode(owner.identifier!.bytes))!;
    check(after.records.program.bytes.sublist(changed.dictionary!.start, changed.dictionary!.end)).deepEquals(before.records.program.bytes.sublist(owner.dictionary!.start, owner.dictionary!.end));
    if (owner.source case final AiNativePath path) {
      check((changed.source as AiNativePath).geometry.map((command) => command.numbers)).deepEquals(path.geometry.map((command) => command.numbers));
      check(after.pathTopology(path: changed.source as AiNativePath).pointCount?.numbers?.single).equals(before.pathTopology(path: path).pointCount?.numbers?.single);
    }
  }
  check(result).isEmpty();
}

/// Qualifies partial branch transactions without a rendering dependency.
void main() {
  test('extracts ordinary compound branches with their deferred shared paint', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourBranchSource());
    final AiNativeDrawing moved = moveContourBranch(drawing, 'Branch', 'Destination');
    check(contourGroupWidths(moved)).deepEquals(contourGroupWidths(drawing));
    check(moved.pathTopology(path: contourMovementContour(moved, 10)).compound).isNull();
    check(contourMovementGroup(moved, 'Source').paths.length).equals(1);
    _retained(drawing, moved);
  });

  test('activates leaf clipping scopes when a compound mask branch leaves', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourBranchSource(mask: true));
    final AiNativeDrawing moved = moveContourBranch(drawing, 'Branch', 'Destination');
    check(contourGroupWidths(moved)).deepEquals(contourGroupWidths(drawing));
    for (final int coordinate in [10, 11]) {
      final AiNativePathTopology topology = moved.pathTopology(path: contourMovementContour(moved, coordinate));
      check(topology.compound).isNull();
      check(topology.clippingGroup).identicalTo(contourMovementGroup(moved, 'Branch'));
      check(topology.mask).equals(AiNativePathMask.open);
    }
    _retained(drawing, moved);
  });

  test('reorders and reparents branches within the same compound', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourBranchSource());
    final AiNativeDrawing reordered = moveContourBranch(drawing, 'Branch', 'Source');
    check(contourGroupWidths(reordered)).deepEquals(contourGroupWidths(drawing));
    check(contourMovementGroup(reordered, 'Source').paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([20, 10, 11]);
    final AiNativeDrawing nested = moveContourBranch(drawing, 'Branch', 'Sibling');
    check(contourGroupWidths(nested)).deepEquals(contourGroupWidths(drawing));
    check(contourMovementGroup(nested, 'Sibling').paths.length).equals(3);
    _retained(drawing, nested);
  });

  test('adopts destination compound paint only after explicit acceptance', () {
    for (final bool mask in [false, true]) {
      final String source = contourBranchSource(mask: mask);
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      check(() => moveContourBranch(drawing, 'Branch', 'Target')).throws<UnsupportedError>();
      final AiNativeDrawing moved = moveContourBranch(drawing, 'Branch', 'Target', inheritCompoundAppearance: true);
      for (final int coordinate in [10, 11, 30]) {
        final AiNativePath path = contourMovementContour(moved, coordinate);
        check(path.paint.operator).equals('F');
        check(moved.pathTopology(path: path).compound).identicalTo(contourMovementGroup(moved, 'Target'));
      }
      final Map<double, List<double?>> expected = contourGroupWidths(drawing)
        ..[10] = [2, 3]
        ..[11] = [2, 3];
      check(contourGroupWidths(moved)).deepEquals(expected);
      _retained(drawing, moved);
      check(latin1.decode(drawing.records.program.bytes)).equals(source);
    }
  });

  test('suppresses leaf clip restoration when entering a compound mask', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourBranchSource(mask: true));
    final AiNativeDrawing extracted = moveContourBranch(drawing, 'Branch', 'Destination');
    final AiNativeDrawing restored = moveContourBranch(extracted, 'Branch', 'Source', inheritCompoundAppearance: true);
    check(contourGroupWidths(restored)).deepEquals(contourGroupWidths(drawing));
    check(restored.pathTopology(path: contourMovementContour(restored, 10)).compound).identicalTo(contourMovementGroup(restored, 'Source'));
    _retained(drawing, restored);
  });

  test('moves non-bottom mask branches while activating every clipping leaf', () {
    final String source = contourBranchTreeSource();
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    final AiNativeDrawing moved = moveContourBranch(drawing, 'Tree', 'Destination');
    check(contourGroupWidths(moved)).deepEquals(contourGroupWidths(drawing));
    for (final int coordinate in [10, 11, 20]) {
      check(moved.pathTopology(path: contourMovementContour(moved, coordinate)).compound).isNull();
    }
    final AiNativeDrawing restored = moveContourBranch(moved, 'Tree', 'Source', inheritCompoundAppearance: true);
    check(contourGroupWidths(restored)).deepEquals(contourGroupWidths(drawing));
    _retained(drawing, restored);
  });

  test('retains contour closure and explicit ancestor inheritance on entry', () {
    final String source = contourBranchSource().replaceFirst('11 1 L  S', '11 1 L 10 0 L  s');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(contourMovementContour(drawing, 10).closed).isTrue();
    check(() => drawing.moveContourGroups(groups: [contourMovementGroup(drawing, 'Branch')], parent: contourMovementGroup(drawing, 'Destination'), bounds: topologyBounds)).throws<UnsupportedError>();
    final AiNativeDrawing moved = moveContourBranch(drawing, 'Branch', 'Target', inheritCompoundAppearance: true);
    check(contourMovementContour(moved, 10).paint.operator).equals('f');
    check(contourMovementContour(moved, 11).paint.operator).equals('F');
    _retained(drawing, moved);
  });

  test('rejects empty compound elements, mixed masks and nested compounds atomically', () {
    final AiNativeDrawing drawing = groupCreationDrawing(contourBranchSource());
    final String source = latin1.decode(drawing.records.program.bytes);
    check(
      () => drawing.moveContourGroups(
        groups: [contourMovementGroup(drawing, 'Branch'), contourMovementGroup(drawing, 'Sibling')],
        parent: contourMovementGroup(drawing, 'Destination'),
        bounds: topologyBounds,
        inheritParentFlags: true,
      ),
    ).throws<UnsupportedError>();
    check(() => moveContourBranch(drawing, 'Source', 'Target', inheritCompoundAppearance: true)).throws<UnsupportedError>();
    final AiNativeDrawing mask = groupCreationDrawing(contourBranchSource(mask: true));
    check(() => moveContourBranch(mask, 'Destination', 'Source', inheritCompoundAppearance: true)).throws<UnsupportedError>();
    check(() => moveContourBranch(mask, 'Branch', 'TargetBranch', inheritCompoundAppearance: true)).throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('does not discard emptied identified intermediate branches', () {
    final String source = objectSource(
      '*u u u ${contourMovementPath(10)}U ${objectDictionary(identifier: 'Inner')}\nU ${objectDictionary(identifier: 'Outer')}\n${contourMovementPath(20)}*U\nu U ${objectDictionary(identifier: 'Destination')}',
      setup: '',
    );
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(() => moveContourBranch(drawing, 'Inner', 'Destination')).throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('checks unresolved destination values at deferred compound consumption', () {
    for (final String assignment in ['8 w', '%_8 w\n']) {
      final String source = objectSource(
        '*u u ${contourMovementPath(30)}U ${contourMovementPath(40)}6 w *U\n*u u $assignment ${contourMovementPath(10)}U ${contourMovementPath(20)}9 w *U',
        setup: '',
      ).replaceFirst('2 w', '');
      final AiNativeDrawing drawing = groupCreationDrawing(source);
      final AiNativeDrawing moved = drawing.moveContourGroups(
        groups: [drawing.groups[2]],
        parent: drawing.groups[0],
        bounds: topologyBounds,
        inheritCompoundAppearance: true,
        inheritParentFlags: true,
      );
      check(contourGroupWidths(moved)).deepEquals({
        30: [6, 6],
        10: [6, 6],
        40: [6, 6],
        20: [9, 9],
      });
      final AiNativeDrawing unknown = groupCreationDrawing(source.replaceFirst('6 w *U', '*U'));
      check(() => unknown.moveContourGroups(groups: [unknown.groups[2]], parent: unknown.groups[0], bounds: topologyBounds, inheritCompoundAppearance: true, inheritParentFlags: true))
          .throws<UnsupportedError>();
    }
  });

  test('does not restore inactive saved clips while proving unresolved output', () {
    final String source = objectSource(
      'q *u q ${contourMovementPath(30, mask: 'H W')}Q *U Q\nq *u q 8 w ${contourMovementPath(10, mask: 'H W')}Q ${contourMovementPath(20, mask: 'H W')}9 w *U Q\n9 w',
      setup: '',
    ).replaceFirst('2 w', '');
    final AiNativeDrawing drawing = groupCreationDrawing(source);
    check(
      () => drawing.moveContourGroups(
        groups: [drawing.groups[3]],
        parent: drawing.groups[1],
        after: drawing.groups[0],
        bounds: topologyBounds,
        inheritCompoundAppearance: true,
        inheritParentFlags: true,
      ),
    ).throws<UnsupportedError>();
    check(latin1.decode(drawing.records.program.bytes)).equals(source);
  });

  test('keeps original output limits and handles batches of compound branches', () {
    final String source = contourBranchSource();
    final AiNativeDrawing limited = groupCreationDrawing(source, limits: AiNativeLimits(maxDecodedBytes: source.length + 1));
    check(() => moveContourBranch(limited, 'Branch', 'Destination')).throws<FormatException>();
    final AiNativeDrawing drawing = groupCreationDrawing(
      objectSource('*u ${[for (int index = 0; index < 100; index++) 'u ${contourMovementPath(index)}U'].join('\n')} ${contourMovementPath(100)}*U\nu U', setup: ''),
    );
    final AiNativeDrawing moved = drawing.moveContourGroups(groups: drawing.groups.take(100).toList().reversed.toList(), parent: drawing.groups.last, bounds: topologyBounds, inheritParentFlags: true);
    check(moved.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([100, for (int index = 99; index >= 0; index--) index]);
    check(contourGroupWidths(moved)).deepEquals(contourGroupWidths(drawing));
  });
}
