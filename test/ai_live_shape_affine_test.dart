import 'dart:convert';
import 'dart:math';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// A native rectangular contour with independently authored dimensions.
const String affineRectangle = '0 0 m 20 0 L 20 10 L 0 10 L 0 0 L';

/// Native shape metadata; all values are specified independently of the editor.
String affineDictionary({String handler = 'ai::Rectangle', bool redundant = false, String extra = '', bool frame = true}) {
  final String dimensions = switch (handler) {
    'ai::Rectangle' || 'ai::Ellipse' => '20 /Real ($handler::Width) , 10 /Real ($handler::Height) ,',
    'ai::Polygon' => '4 /Int ($handler::NumSides) , 10 /Real ($handler::Radius) , 1 /Bool ($handler::IsRegular) ,',
    'ai::Star' => '5 /Int ($handler::NumPoints) , 10 /Real ($handler::Radius1) , 5 /Real ($handler::Radius2) , 1 /Bool ($handler::IsRegular) ,',
    _ => '20 /Real ($handler::Length) ,',
  };
  final String dictionary =
      '''/ArtDictionary :
${frame ? '(0.000000) /String (BBAccumRotation) ,' : ''}
/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
($handler) /UnicodeString (ai::LiveShape::HandlerName) ,
/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
1010 /Real ($handler::CenterX) , 1995 /Real ($handler::CenterY) ,
0 /Real ($handler::${handler == 'ai::Rectangle' ? 'Angle' : 'RotationAngle'}) ,
${handler == 'ai::Line' ? '' : '0 /Bool ($handler::Clockwise) ,'}
$dimensions
$extra
; (ai::LiveShape::Params) , ; (ai::LiveShape) , ;''';
  return dictionary.split('\n').map((line) => '%_$line').join('\n');
}

/// A qualified direct shape or a complete private/printing CC pair.
AiNativeDrawing affineDrawing({String handler = 'ai::Rectangle', bool pair = false, String extra = '', bool peer = true, int? limit}) {
  final String body = pair
      ? 'u\n4 As $affineRectangle f\nU\n${affineDictionary(handler: handler, redundant: true, extra: extra)}\n0 0 Xd\n6 () XW\n%_4 As\n%_${affineRectangle.split(' ').join(' ')} n\n${affineDictionary(handler: handler, extra: extra)}\n1 (Shared) XW'
      : '4 As $affineRectangle f\n${affineDictionary(handler: handler, extra: extra)}';
  final String style = pair
      ? '/KnownStyle : (Shared) /Name , /ActiveStyle : /CompoundFilter : (Chain Style Filter) 0 0 /Filter , 1 /Visible , /BasicFilter : (Fill Style Filter) 0 0 /Filter , /Dictionary : /FillStyle : 0 g /Def ; (FillStyle) , ; /Dict ; /Part ; /Execution ; /Def ;'
      : '';
  return AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(
        bytes: latin1.encode('''%!PS-Adobe-3.0
%%BoundingBox: 0 0 100 100
%%BeginSetup
/AI11TextDocument : /ASCII85Decode ,
%~>
1000 2000 /RulerOrigin , ;
$style
%%EndSetup
$body
${peer ? '50 0 m 60 10 L s' : ''}
%%Trailer
%%EOF
'''),
        limits: AiNativeLimits(maxDecodedBytes: limit ?? 128 * 1024 * 1024),
      ),
    ),
  );
}

/// Explicit host-computed ink bounds for these small synthetic examples.
AiBoundingBox get affineBounds => AiBoundingBox(left: -100, bottom: -100, right: 100, top: 100);

/// A host-composed fill expansion with unchanged outgoing graphics state.
List<int> affinePrinting(List<AiPathSegment> geometry) =>
    latin1.encode('u\n${geometry.length - 1} As ${geometry.map((segment) => '${segment.coordinates.join(' ')} ${segment.operator}').join(' ')} f\nU');

/// Verifies transforms and parameter changes with both native source layouts.
void main() {
  test('nonuniform resize retains a rectangle and fixed stroke state', () {
    final AiNativeDrawing source = affineDrawing();
    final AiNativeDrawing changed = source.transformLiveShapes(shapes: source.liveShapes, transform: AiNativeAffineTransform.scale(scaleX: 2, scaleY: 3, pivotX: 0, pivotY: 0), bounds: affineBounds);
    final AiLiveShape shape = changed.liveShapes.single;
    check(shape.handler).equals('ai::Rectangle');
    check(shape.parameters['ai::Rectangle::Width']!.number).equals(40);
    check(shape.parameters['ai::Rectangle::Height']!.number).equals(30);
    check(shape.parameters['ai::Rectangle::CenterX']!.number).equals(1020);
    check(shape.parameters['ai::Rectangle::CenterY']!.number).equals(1985);
    check(shape.path!.segments[2].coordinates).deepEquals([40.0, 30.0]);
    check(changed.paths.last.segments.map((segment) => segment.coordinates)).deepEquals(source.paths.last.segments.map((segment) => segment.coordinates));
  });

  for (final bool pair in [false, true]) {
    test('shears ${pair ? 'paired CC' : 'direct'} rectangle into an editable native parallelogram', () {
      final AiNativeDrawing source = affineDrawing(pair: pair);
      final AiNativeAffineTransform shear = AiNativeAffineTransform.shear(horizontal: 1, vertical: 0, pivotX: 0, pivotY: 0);
      final List<AiPathSegment> expected = [
        AiPathSegment(operator: 'm', coordinates: [0, 0]),
        AiPathSegment(operator: 'L', coordinates: [20, 0]),
        AiPathSegment(operator: 'L', coordinates: [30, 10]),
        AiPathSegment(operator: 'L', coordinates: [10, 10]),
        AiPathSegment(operator: 'L', coordinates: [0, 0]),
      ];
      final AiNativeDrawing changed = source.transformLiveShapes(
        shapes: source.liveShapes,
        transform: shear,
        bounds: affineBounds,
        printing: {if (pair) source.liveShapes.single: affinePrinting(expected)},
      );
      final AiLiveShape shape = changed.liveShapes.single;
      check(shape.isBound).isTrue();
      check(shape.handler).equals('ai::Polygon');
      check(shape.parameters['ai::Polygon::NumSides']!.number).equals(4);
      check(shape.parameters['ai::Polygon::Radius']!.number).equals(-11);
      check(shape.parameters['ai::Polygon::IsRegular']!.boolean).equals(false);
      check(shape.path!.segments.map((segment) => segment.coordinates)).deepEquals(expected.map((segment) => segment.coordinates));
      final AiNativeParallelogram geometry = shape.parallelogram!;
      check([geometry.centerX, geometry.centerY, geometry.ux, geometry.uy, geometry.vx, geometry.vy]).deepEquals([15.0, 5.0, 10.0, 0.0, 5.0, 5.0]);
      check(geometry.segments.map((segment) => segment.coordinates)).deepEquals(expected.map((segment) => segment.coordinates));
      if (pair) {
        check(shape.appearancePaths.single.segments.map((segment) => segment.coordinates)).deepEquals(expected.map((segment) => segment.coordinates));
        final AiNativeContainer redundant = shape.appearanceDictionary!['ai::LiveShape']!.container!;
        check(redundant['ai::LiveShape::HandlerName']!.text()).equals('ai::Polygon');
        check(redundant['ai::LiveShape::Params']!.container!['ai::Polygon::NumSides']!.number).equals(4);
      }
      final AiNativeDrawing reflected = changed.transformLiveShapes(
        shapes: changed.liveShapes,
        transform: AiNativeAffineTransform.reflection(axisRadians: 0, pivotX: 0, pivotY: 0),
        bounds: affineBounds,
        printing: {
          if (pair)
            shape: affinePrinting([
              for (final AiPathSegment segment in expected)
                AiPathSegment(
                  operator: segment.operator,
                  coordinates: [
                    for (final (int index, double value) in segment.coordinates.indexed)
                      if (index.isEven) value else -value,
                  ],
                ),
            ]),
        },
      );
      check(reflected.liveShapes.single.parameters['ai::Polygon::Clockwise']!.boolean).equals(true);
      check(reflected.liveShapes.single.parallelogram!.centerY).equals(-5);
    });
  }

  test('reflection preserves regular families and reverses explicit winding', () {
    for (final String handler in ['ai::Rectangle', 'ai::Ellipse', 'ai::Polygon', 'ai::Star', 'ai::Line']) {
      final AiNativeDrawing source = affineDrawing(handler: handler);
      final AiNativeDrawing changed = source.transformLiveShapes(
        shapes: source.liveShapes,
        transform: AiNativeAffineTransform.reflection(axisRadians: pi / 2, pivotX: 0, pivotY: 0),
        bounds: affineBounds,
      );
      check(changed.liveShapes.single.handler).equals(handler);
      check(changed.liveShapes.single.path!.segments[1].coordinates).deepEquals([-20.0, 0.0]);
      if (handler != 'ai::Line') {
        check(changed.liveShapes.single.parameters['$handler::Clockwise']!.boolean).equals(true);
      }
      final AiNativeDrawing restored = changed.transformLiveShapes(
        shapes: changed.liveShapes,
        transform: AiNativeAffineTransform.reflection(axisRadians: pi / 2, pivotX: 0, pivotY: 0),
        bounds: affineBounds,
      );
      check(restored.liveShapes.single.path!.segments.map((segment) => segment.coordinates)).deepEquals(source.liveShapes.single.path!.segments.map((segment) => segment.coordinates));
    }
  });

  test('parameter replacement accepts host geometry for all five families', () {
    for (final String handler in ['ai::Rectangle', 'ai::Ellipse', 'ai::Polygon', 'ai::Star', 'ai::Line']) {
      final AiNativeDrawing source = affineDrawing(handler: handler);
      final AiLiveShape shape = source.liveShapes.single;
      final Map<String, double> numbers = switch (handler) {
        'ai::Rectangle' => {'Width': 40, 'CornerRadius::0': 2},
        'ai::Ellipse' => {'Width': 40, 'PieStartAngle': 0.5, 'PieEndAngle': 3},
        'ai::Polygon' => {'NumSides': 6, 'Radius': 30},
        'ai::Star' => {'NumPoints': 7, 'Radius1': 30, 'Radius2': 12},
        _ => {'Length': 40},
      };
      final List<AiPathSegment> geometry = [
        AiPathSegment(operator: 'm', coordinates: [5, 5]),
        AiPathSegment(operator: 'C', coordinates: [8, 0, 22, 0, 25, 5]),
        AiPathSegment(operator: 'L', coordinates: [25, 25]),
      ];
      final AiNativeDrawing changed = source.replaceLiveShapes(
        replacements: [
          AiNativeLiveShapeReplacement(
            shape: shape,
            parameters: AiNativeShapeParameters.fromShape(shape: shape).copyWith(numbers: numbers),
            segments: geometry,
            bounds: affineBounds,
            rotationRadians: 0,
          ),
        ],
      );
      for (final MapEntry<String, double> value in numbers.entries) {
        check(changed.liveShapes.single.parameters['$handler::${value.key}']!.number).equals(value.value);
      }
      check(changed.liveShapes.single.path!.segments[1].operator).equals('C');
      check(changed.liveShapes.single.path!.segments).length.equals(4);
      check(changed.liveShapes.single.path!.segments.last.coordinates).deepEquals([5.0, 5.0]);
    }
  });

  test('refuses incomplete printing, unknown dimensions, invalid input and unsupported families atomically', () {
    final AiNativeDrawing source = affineDrawing(pair: true);
    final AiNativeAffineTransform shear = AiNativeAffineTransform.shear(horizontal: 1, vertical: 0, pivotX: 0, pivotY: 0);
    check(() => source.transformLiveShapes(shapes: source.liveShapes, transform: shear, bounds: affineBounds)).throws<ArgumentError>();
    check(() => AiNativeShapeParameters.fromShape(shape: source.liveShapes.single).copyWith(numbers: {'Width': -1})).throws<ArgumentError>();
    check(() => AiNativeShapeParameters.fromShape(shape: source.liveShapes.single).copyWith(numbers: {'Future': 1})).throws<ArgumentError>();
    check(() => AiNativeParallelogram(centerX: 0, centerY: 0, ux: 1, uy: 1, vx: 2, vy: 2)).throws<ArgumentError>();
    for (final String handler in ['ai::Ellipse', 'ai::Star']) {
      final AiNativeDrawing unsupported = affineDrawing(handler: handler);
      check(() => unsupported.transformLiveShapes(shapes: unsupported.liveShapes, transform: shear, bounds: affineBounds)).throws<UnsupportedError>();
    }
    final AiNativeDrawing rounded = affineDrawing(extra: '2 /Real (ai::Rectangle::CornerRadius::0) ,');
    check(() => rounded.transformLiveShapes(shapes: rounded.liveShapes, transform: shear, bounds: affineBounds)).throws<UnsupportedError>();
    check(source.liveShapes.single.handler).equals('ai::Rectangle');
  });
}
