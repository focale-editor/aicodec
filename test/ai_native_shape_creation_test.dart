import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectSource;

/// Complete scalar parameters for a sharp host-composed rectangle.
AiNativeShapeParameters authoredRectangle({double width = 20, double height = 10, double x = 0, double y = 0}) => AiNativeShapeParameters(
  handler: 'ai::Rectangle',
  numbers: {
    'CenterX': x + width / 2,
    'CenterY': -y - height / 2,
    'Width': width,
    'Height': height,
    'Angle': 0,
    'InitialQuadrant': 2,
    for (int index = 0; index < 4; index++) 'CornerRadius::$index': 0,
  },
  flags: {'Clockwise': false},
  choices: {
    for (int index = 0; index < 4; index++) ...{'CornerType::$index': 'Normal', 'RoundingType::$index': 'Absolute'},
  },
);

/// Supplies the exact same contour to native authoring and printable data.
AiNativePathDefinition authoredShape({double width = 20, double height = 10, double x = 0, double y = 0, bool metadata = true, double opacity = .8, bool closed = true}) => AiNativePathDefinition(
  artwork: AiArtworkPath(
    segments: [
      AiPathSegment(operator: 'm', coordinates: [x, y]),
      AiPathSegment(operator: 'L', coordinates: [x + width, y]),
      if (closed) ...[
        AiPathSegment(operator: 'L', coordinates: [x + width, y + height]),
        AiPathSegment(operator: 'L', coordinates: [x, y + height]),
        AiPathSegment(operator: 'L', coordinates: [x, y]),
      ],
    ],
    fill: AiColor(space: .rgb, channels: [.125, .25, .75]),
    stroke: AiColor(space: .gray, channels: [.2]),
    strokeWidth: 2,
    closed: closed,
  ),
  bounds: AiBoundingBox(left: x - 2, bottom: y - 2, right: x + width + 2, top: y + height + 2),
  opacity: opacity,
  nameBytes: metadata ? utf8.encode('Rectangle créé') : null,
  identifierBytes: metadata ? ascii.encode('new_shape') : null,
);

/// Exercises explicit shape authoring without an Illustrator template.
void main() {
  test('creates direct shape parameters with named identity and printable path', () {
    final AiNativeDrawing empty = groupCreationDrawing(objectSource('', setup: ''));
    final AiNativeDrawing result = empty.createLiveShape(definition: authoredShape(), parameters: authoredRectangle(), rotationRadians: 0);
    check(result.paths).length.equals(1);
    check(result.liveShapes).length.equals(1);
    final AiLiveShape shape = result.liveShapes.single;
    check(shape.isBound).isTrue();
    check(shape.appearancePaths.single).identicalTo(shape.path!);
    check(AiNativeShapeParameters.fromShape(shape: shape).numbers).deepEquals(authoredRectangle().numbers);
    final AiNativeObject owner = AiNativeObjects.decode(drawing: result).forSource(result.paths.single);
    check(owner.identifier!.bytes).deepEquals(ascii.encode('new_shape'));
    check(utf8.decode(owner.names.single.stringBytes!)).equals('Rectangle créé');
    check(double.parse(owner.dictionary!['BBAccumRotation']!.text()!)).equals(0);
    check(empty.paths).isEmpty();
  });

  test('promotes a metadata-free path without changing its source geometry', () {
    final AiNativeDrawing empty = groupCreationDrawing(objectSource('', setup: ''));
    final AiNativeDrawing source = empty.createPath(definition: authoredShape(metadata: false));
    final List<int> geometry = source.records.program.bytes.sublist(source.paths.single.start, source.paths.single.end);
    final AiNativeDrawing result = source.setPathLiveShape(path: source.paths.single, parameters: authoredRectangle());
    check(result.records.program.bytes.sublist(result.paths.single.start, result.paths.single.end)).deepEquals(geometry);
    check(AiNativeObjects.decode(drawing: result).forSource(result.paths.single).identifier).isNull();
    check(result.liveShapes).length.equals(1);
  });

  test('replaces parameters, contour and appearance while retaining object identity', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('', setup: '')).createLiveShape(definition: authoredShape(), parameters: authoredRectangle(), rotationRadians: 0);
    final AiNativeDrawing result = source.replaceDirectLiveShape(
      shape: source.liveShapes.single,
      definition: authoredShape(width: 37, height: 19, x: 5, y: -3, metadata: false, opacity: .4),
      parameters: authoredRectangle(width: 37, height: 19, x: 5, y: -3),
      rotationRadians: .3,
    );
    check(result.liveShapes.single.parameters['ai::Rectangle::Width']!.number).equals(37);
    check(result.paths.single.segments.first.coordinates).deepEquals([5, -3]);
    final AiNativeObject owner = AiNativeObjects.decode(drawing: result).forSource(result.paths.single);
    check(owner.identifier!.bytes).deepEquals(ascii.encode('new_shape'));
    check(utf8.decode(owner.names.single.stringBytes!)).equals('Rectangle créé');
    check(owner.dictionary!['BBAccumRotation']!.text()).equals('0.300000');
    check(latin1.decode(result.records.program.bytes)).contains('0 0.4 0 0 0 Xy');
    check(source.liveShapes.single.parameters['ai::Rectangle::Width']!.number).equals(20);
  });

  test('requires the matching open or closed family and current owned handles', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('', setup: ''));
    check(() => source.createLiveShape(definition: authoredShape(closed: false), parameters: authoredRectangle())).throws<ArgumentError>();
    final AiNativeDrawing result = source.createLiveShape(definition: authoredShape(), parameters: authoredRectangle());
    check(() => source.replaceDirectLiveShape(shape: result.liveShapes.single, definition: authoredShape(metadata: false), parameters: authoredRectangle())).throws<ArgumentError>();
    check(() => result.replaceDirectLiveShape(shape: result.liveShapes.single, definition: authoredShape(), parameters: authoredRectangle())).throws<ArgumentError>();
    check(() => result.replacePathArtwork(path: result.paths.single, artwork: authoredShape().artwork, bounds: authoredShape().bounds)).throws<UnsupportedError>();
  });

  test('retains separate center-display flags inside the replaced counted span', () {
    final AiNativeDrawing initial = groupCreationDrawing(objectSource('', setup: '')).createLiveShape(definition: authoredShape(), parameters: authoredRectangle());
    final AiNativeDrawing source = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(
        program: AiNativeEditor.apply(
          program: initial.records.program,
          edits: [AiSourceEdit(start: initial.paths.single.start, end: initial.paths.single.start, bytes: latin1.encode('1 Ap\n%_0 Ap\n'))],
        ),
      ),
    );
    final AiNativeDrawing result = source.replaceDirectLiveShape(shape: source.liveShapes.single, definition: authoredShape(width: 30, metadata: false), parameters: authoredRectangle(width: 30));
    final List<AiNativeInstruction> flags = result.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'Ap' && item.start < result.paths.single.start).toList();
    check(flags.where((item) => !item.isPrivate).last.numbers).isNotNull().deepEquals([1]);
    check(flags.last.numbers).isNotNull().deepEquals([0]);
    check(flags.last.isPrivate).isTrue();
  });

  test('replaces a sharp rectangle by an explicit native parallelogram', () {
    final AiNativeDrawing source = groupCreationDrawing(objectSource('', setup: '')).createLiveShape(definition: authoredShape(), parameters: authoredRectangle());
    final AiNativeParallelogram shape = AiNativeParallelogram(centerX: 10, centerY: 5, ux: 10, uy: 0, vx: 4, vy: 5);
    final AiNativeDrawing result = source.replaceDirectLiveShape(
      shape: source.liveShapes.single,
      definition: AiNativePathDefinition(
        artwork: AiArtworkPath(
          segments: shape.segments,
          fill: AiColor(space: .gray, channels: [.6]),
          closed: true,
        ),
        bounds: AiBoundingBox(left: -4, bottom: 0, right: 24, top: 10),
      ),
      parameters: shape.parameters(rulerOriginX: 0, rulerOriginY: 0),
      rotationRadians: null,
    );
    check(result.liveShapes.single.handler).equals('ai::Polygon');
    check(result.liveShapes.single.parallelogram).isNotNull();
    check(AiNativeObjects.decode(drawing: result).forSource(result.paths.single).identifier!.bytes).deepEquals(ascii.encode('new_shape'));
  });
}
