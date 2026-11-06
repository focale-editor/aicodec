import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath;
import 'ai_native_objects_test.dart' show objectSource;
import 'ai_native_printing_test.dart' show printingFixture;

/// Supplies a direct rectangle with its own authoritative native parameters.
String directShape(int x, {String? identifier}) =>
    '''4 As
$x 0 m ${x + 10} 0 L ${x + 10} 10 L $x 10 L $x 0 L f
%_/ArtDictionary :
${identifier == null ? '' : '%_/XMLUID : ($identifier) ; (AI10_ArtUID) ,'}
%_1 /Bool (PATH_IS_KAPPA_CURVE) ,
%_/Dictionary :
%_(ai::Rectangle) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary :
%_${8196 + x} /Real (ai::Rectangle::CenterX) ,
%_8186 /Real (ai::Rectangle::CenterY) ,
%_10 /Real (ai::Rectangle::Width) , 10 /Real (ai::Rectangle::Height) ,
%_0 /Real (ai::Rectangle::Angle) ,
%_1 /Bool (ai::Rectangle::Clockwise) , 1 /Int (ai::Rectangle::InitialQuadrant) ,
%_0 /Real (ai::Rectangle::CornerRadius::0) ,
%_(Invalid) /UnicodeString (ai::Rectangle::CornerType::0) ,
%_(Invalid) /UnicodeString (ai::Rectangle::RoundingType::0) ,
%_; (ai::LiveShape::Params) , ; (ai::LiveShape) , ;''';

/// Contains direct shapes in ordinary groups and identified layer subtrees.
String get directShapeSource => objectSource(
  '${movementLayer('A', '${directShape(10, identifier: 'rect_a')}\n0.4 g u ${directShape(30, identifier: 'rect_child')}\nU')}\n'
  '${movementLayer('B', '0.8 g ${movementPath(60)}')}',
  setup: '',
);

/// Decodes a bounded immutable source rather than sharing mutable test handles.
AiNativeDrawing _drawing(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Retains parameter values separately from path order and saved identifiers.
List<List<Object?>> _parameters(AiNativeDrawing drawing) => [
  for (final AiLiveShape shape in drawing.liveShapes)
    [
      shape.handler,
      shape.parameters.entries.map((field) => [field.key, field.type, field.numbers, field.stringBytes]).toList(),
    ],
];

/// Checks whole-object lifecycle without stripping native authoring parameters.
void main() {
  test('binds direct native shapes to their exact path and metadata owner', () {
    final AiNativeDrawing source = _drawing(directShapeSource);
    final AiNativeObjects objects = AiNativeObjects.decode(drawing: source);
    for (final AiLiveShape shape in source.liveShapes) {
      final AiNativeObject object = objects.forSource(shape.path!);
      check(object.liveShape).identicalTo(shape);
      check(object.dictionary).identicalTo(shape.dictionary);
      check(object.bindingIssue).isNull();
      check(object.end).equals(shape.end);
    }
    check(objects.forSource(source.paths.last).liveShape).isNull();
  });

  test('copies complete identified shapes and preserves later parameter editing', () {
    final AiNativeDrawing source = _drawing(directShapeSource);
    final List<int> identity = latin1.encode('copy_rect');
    final AiNativeDrawing copied = source.duplicatePaths(paths: [source.paths.first], identifiers: {source.paths.first: identity});
    identity[0] = 120;
    check(copied.liveShapes).length.equals(3);
    check(_parameters(copied)).deepEquals([_parameters(source)[0], ..._parameters(source)]);
    check(AiNativeObjects.decode(drawing: copied).forSource(copied.paths[1]).identifier!.bytes).deepEquals(latin1.encode('copy_rect'));
    final AiNativeDrawing translated = copied.translateLiveShapes(shapes: [copied.liveShapes[1]], deltaX: 5, deltaY: 2);
    check(translated.liveShapes[1].parameters['ai::Rectangle::CenterX']!.number).equals(8211);
    check(translated.paths[1].geometry.first.numbers!).deepEquals([15, 2]);
    check(_parameters(translated).first).deepEquals(_parameters(source).first);
    check(latin1.decode(source.records.program.bytes)).equals(directShapeSource);
  });

  test('removes identified shapes with their metadata and retains other owners', () {
    final AiNativeDrawing source = _drawing(directShapeSource);
    final AiNativeDrawing result = source.removePaths(paths: [source.paths.first]);
    check(result.liveShapes).length.equals(1);
    check(_parameters(result)).deepEquals([_parameters(source)[1]]);
    check(AiNativeObjects.decode(drawing: result).forSource(result.paths.first).identifier!.bytes).deepEquals(latin1.encode('rect_child'));
    check(source.liveShapes).length.equals(2);
  });

  test('reorders direct shapes with their source state and native parameters', () {
    final AiNativeDrawing source = _drawing(objectSource('${directShape(10)}\n0.9 g ${directShape(30)}', setup: ''));
    final AiNativeDrawing result = source.reorderPaths(paths: source.paths.reversed.toList());
    check(_parameters(result)).deepEquals(_parameters(source).reversed.toList());
    check(result.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([30, 10]);
  });

  test('moves native shapes across groups and hidden layers without transforming geometry', () {
    final AiNativeDrawing source = _drawing(directShapeSource);
    final AiNativeDrawing moved = source.movePathAfter(path: source.paths.first, after: source.paths.last, inheritParentFlags: true);
    check(_parameters(moved)).deepEquals(_parameters(source).reversed.toList());
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: moved);
    final AiNativeDrawing restored = moved.movePathToLayer(path: moved.paths.last, layer: layers.layers.first.source, inheritParentFlags: true);
    check(restored.liveShapes).length.equals(2);
    check(restored.liveShapes.every((shape) => shape.isBound)).isTrue();
    check(restored.paths.map((path) => path.geometry.first.numbers!.first)).deepEquals([30, 10, 60]);
  });

  test('copies and removes group and layer subtrees with all native descendants', () {
    final AiNativeDrawing source = _drawing(directShapeSource);
    final AiNativeDrawing copied = source.duplicateGroups(groups: source.groups, identifiers: {source.paths[1]: latin1.encode('group_copy')});
    check(copied.liveShapes).length.equals(3);
    check(source.removeGroups(groups: source.groups).liveShapes).length.equals(1);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    final AiNativeLayers layerCopy = layers.duplicate(
      layers: [layers.layers.first],
      identifiers: {layers.layers.first: latin1.encode('LayerCopy')},
      artworkIdentifiers: {source.paths[0]: latin1.encode('layer_rect_a'), source.paths[1]: latin1.encode('layer_rect_child')},
    );
    check(layerCopy.drawing.liveShapes).length.equals(4);
    check(_parameters(layerCopy.drawing)).deepEquals([..._parameters(source), ..._parameters(source)]);
    check(layers.remove(layers: [layers.layers.first]).drawing.liveShapes).isEmpty();
  });

  test('groups and dissolves boundaries without losing the live-shape owner', () {
    final AiNativeDrawing source = _drawing(objectSource(directShape(10), setup: ''));
    final AiNativeDrawing grouped = source.groupPaths(paths: source.paths);
    check(_parameters(grouped)).deepEquals(_parameters(source));
    final AiNativeDrawing ungrouped = grouped.ungroup(groups: grouped.groups);
    check(_parameters(ungrouped)).deepEquals(_parameters(source));
    check(ungrouped.groups).isEmpty();
  });

  test('keeps inserted ordinary geometry distinct from the native template', () {
    final AiNativeDrawing source = _drawing(objectSource(directShape(10), setup: ''));
    final AiNativeDrawing result = source.insertPaths(
      insertions: [
        AiNativePathInsertion(
          after: source.paths.single,
          segments: [
            AiPathSegment(operator: 'm', coordinates: [1, 2]),
            AiPathSegment(operator: 'L', coordinates: [3, 4]),
          ],
          bounds: AiBoundingBox(left: 1, bottom: 2, right: 3, top: 4),
        ),
      ],
    );
    check(result.paths).length.equals(2);
    check(result.liveShapes).length.equals(1);
    check(AiNativeObjects.decode(drawing: result).forSource(result.paths.last).liveShape).isNull();
  });

  test('rejects opaque metadata and unknown, nested or incorrectly typed native parameters', () {
    for (final String shape in [
      directShape(10).replaceFirst('(ai::Rectangle) /UnicodeString', '(ai::FutureShape) /UnicodeString'),
      directShape(10).replaceFirst('0 /Real (ai::Rectangle::Angle)', '0 /Real (ai::Rectangle::Future)'),
      directShape(10).replaceFirst('0 /Real (ai::Rectangle::Angle)', '(target) /String (ai::Rectangle::Angle)'),
      directShape(10).replaceFirst('0 /Real (ai::Rectangle::Angle)', '/XMLUID : (target) ; (ai::Rectangle::Angle)'),
      directShape(10).replaceFirst('1 /Bool (PATH_IS_KAPPA_CURVE)', '1 /Int (PATH_IS_KAPPA_CURVE)'),
      directShape(10).replaceFirst('1 /Bool (PATH_IS_KAPPA_CURVE)', '(target) /String (UnresolvedReference)'),
    ]) {
      final AiNativeDrawing source = _drawing(objectSource(shape, setup: ''));
      check(AiNativeObjects.decode(drawing: source).forSource(source.paths.single).bindingIssue).isNotNull();
      check(() => source.duplicatePaths(paths: source.paths)).throws<UnsupportedError>();
    }
  });

  test('keeps private printing pairs and versioned authoring outside ordinary lifecycle', () {
    final AiNativeDrawing printing = printingFixture();
    check(() => printing.duplicatePaths(paths: [printing.liveShapes.first.path!])).throws<UnsupportedError>();
    check(() => printing.duplicateGroups(groups: [printing.liveShapes.first.appearanceGroup!])).throws<UnsupportedError>();
    final AiNativeDrawing conditional = _drawing(objectSource('%AI17_Begin_Content_if_version_gt:24 4\n${directShape(10)}\n%AI17_End_Versioned_Content', setup: ''));
    check(() => conditional.removePaths(paths: conditional.paths)).throws<UnsupportedError>();
  });

  test('does not let direct metadata bypass an unresolved prefix or interleaved state', () {
    for (final String body in ['7 (Unknown) XW\n${directShape(10)}', '19 FutureState\n${directShape(10)}', directShape(10).replaceFirst('10 0 m', '10 0 m 5 w')]) {
      final AiNativeDrawing source = _drawing(objectSource(body, setup: ''));
      check(() => source.duplicatePaths(paths: source.paths)).throws<UnsupportedError>();
    }
  });

  test('preserves an unbound neighboring native record when a direct shape is copied', () {
    final String unbound = directShape(30).substring(directShape(30).indexOf('%_/ArtDictionary'));
    final AiNativeDrawing source = _drawing(objectSource('$unbound\n${movementPath(1)}\n${directShape(10)}', setup: ''));
    check(source.liveShapes.first.isBound).isFalse();
    final AiNativeDrawing result = source.duplicatePaths(paths: [source.paths.last]);
    check(result.liveShapes).length.equals(3);
    check(result.liveShapes.first.isBound).isFalse();
    check(latin1.decode(result.records.program.bytes)).contains(unbound);
    check(_parameters(result)).deepEquals([..._parameters(source), _parameters(source).last]);
  });

  test('bounds copies and rejects stale selections without losing the original shape', () {
    final String input = objectSource(directShape(10), setup: '');
    final AiNativeDrawing source = _drawing(input, limits: AiNativeLimits(maxDecodedBytes: input.length + 100));
    check(() => source.duplicatePaths(paths: source.paths)).throws<FormatException>();
    check(() => source.removePaths(paths: _drawing(input).paths)).throws<ArgumentError>();
    check(latin1.decode(source.records.program.bytes)).equals(input);
    final AiNativeDrawing original = _drawing(input);
    final AiNativeDrawing removed = original.removePaths(paths: original.paths);
    check(() => removed.duplicatePaths(paths: original.paths)).throws<ArgumentError>();
  });
}
