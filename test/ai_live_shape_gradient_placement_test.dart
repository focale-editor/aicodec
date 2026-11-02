import 'dart:convert';
import 'dart:math';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Declared resource with two opaque gray stops and retained printing samples.
String _definition(bool radial) =>
    '''%AI5_BeginGradient: (Ink)
(Ink) ${radial ? 1 : 0} 2 Bd
[ <0080ff> 0 %_Br
[ 0 0 50 0 %_BS
%_0 0 1 6 50 0 Bs
1 0 50 100 %_BS
%_1 0 1 6 50 100 Bs
BD
%AI5_EndGradient
''';

/// Qualified live-shape metadata, independent of any regenerated paint geometry.
String _dictionary({bool redundant = false}) => '''%_/ArtDictionary : /Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_(ai::Rectangle) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary : 10 /Real (ai::Rectangle::CenterX) , -20 /Real (ai::Rectangle::CenterY) ,
%_20 /Real (ai::Rectangle::Width) , 40 /Real (ai::Rectangle::Height) , 0 /Real (ai::Rectangle::Angle) ,
%_; (ai::LiveShape::Params) , ; (ai::LiveShape) , ;
''';

/// A relative identity-matrix note for a shared native style.
String _note(bool radial) => 'Bb ${radial ? '0 0 0 0 Bh' : ''} 2 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB';

/// Linear printing strips and exterior caps enclosing a 20 by 40 rectangle.
const String _linear = '20 0 0 -44 0 42 Xm 100 0 0 -44 -100 42 Bc 20 0 0 -44 0 42 Bm 100 0 0 -44 20 42 Bc';

/// A bound shape with explicit printing geometry and optional shared style.
String _shape({bool radial = false, bool styled = false, String? path, String? matrices, double angle = 0}) {
  final String outline = path ?? '0 0 m 20 0 L 20 40 L 0 40 L';
  final double radius = sqrt(250);
  final String paint = '$outline Bb ${radial ? '0 0 0 0 Bh' : ''} 1 (Ink) 0 0 $angle 1 1 0 0 1 0 0 1 Bg ${matrices ?? (radial ? '$radius 0 0 ${-radius} 10 20 Bm' : _linear)} f 0 BB';
  return styled ? 'u\n$paint\nU\n${_dictionary(redundant: true)}\n6 () XW\n%_${_note(radial)}\n%_$outline n\n${_dictionary()}\n1 (Shared) XW' : '$paint\n${_dictionary()}';
}

/// Builds a bounded immutable snapshot with one optional native appearance style.
AiNativeDrawing _drawing(String body, {bool radial = false, bool styled = false, int? limit}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%BoundingBox: 0 0 20 40
%%BeginSetup
1 Bn
${_definition(radial)}
${styled ? '/KnownStyle : (Shared) /Name , /ActiveStyle : /BasicFilter : (Fill Style Filter) 0 0 /Filter , /Dictionary : /FillStyle : ${_note(radial)} /Def ; (FillStyle) , ; /Dict ; /Execution ; /Def ;' : ''}
%%EndSetup
$body
%%Trailer
%%EOF
'''),
      limits: AiNativeLimits(maxDecodedBytes: limit ?? 128 * 1024 * 1024),
    ),
  ),
);

/// Places the selected gradient with explicit relative authoring parameters.
AiNativeDrawing _place(AiNativeDrawing source, {List<AiLiveShape>? shapes, double x = 0.2, double y = 0, double angle = 90, double length = 0.8, double aspect = 1}) =>
    source.setLiveShapeGradientPlacement(
      shapes: shapes ?? [source.liveShapes.first],
      nameBytes: latin1.encode('Ink'),
      originX: x,
      originY: y,
      angle: angle,
      length: length,
      aspectRatio: aspect,
    );

/// Checks redundant native matrix values with bounded decimal tolerance.
void _close(List<double> actual, List<double> expected) {
  check(actual).length.equals(expected.length);
  for (int index = 0; index < actual.length; index++) {
    check(actual[index]).isCloseTo(expected[index], 1e-8);
  }
}

/// Captures an entire object independently of rewritten source offsets.
List<int> _object(AiNativeDrawing source, int index) => source.records.program.bytes.sublist(source.liveShapes[index].start, source.liveShapes[index].end);

/// Exercises relative placement, cubic bounds, shared resources and atomic failure.
void main() {
  test('moves and rotates a linear field while retaining paths, bounds and other users', () {
    final AiNativeDrawing source = _drawing('${_shape()}\n${_shape()}');
    final AiNativeDrawing changed = _place(source);
    final AiNativeGradient gradient = changed.gradients.first;
    check(gradient.geometry.origin).deepEquals([0.2, 0]);
    check(gradient.geometry.angle).equals(90);
    check(gradient.geometry.length).equals(0.8);
    final List<double> matrix = gradient.imagingMatrices.first.numbers!;
    _close(matrix.take(2).toList(), [0, 32]);
    check(matrix[5]).isCloseTo(8, 1e-8);
    check(gradient.imagingMatrices.map((matrix) => matrix.operator).toList()).deepEquals(['Xm', 'Bc', 'Bm', 'Bc']);
    check(changed.paths.first.segments.map((segment) => segment.coordinates).toList()).deepEquals(source.paths.first.segments.map((segment) => segment.coordinates).toList());
    check(_object(changed, 1)).deepEquals(_object(source, 1));
    check(latin1.decode(changed.records.program.bytes)).contains(_definition(false));
    check(latin1.decode(changed.records.program.bytes)).contains('%%BoundingBox: 0 0 20 40');
    check(identical(_place(changed), changed)).isTrue();
  });

  test('updates radial center, radius, ellipse and Cartesian focus together', () {
    final double initial = sqrt(250);
    final String shape = _shape(radial: true).replaceFirst('0 0 0 0 Bh', '${initial / 2} 0 0 0.5 Bh');
    final AiNativeDrawing source = _drawing('$shape\n$shape', radial: true);
    final AiNativeDrawing changed = _place(source, x: 0.25, y: -0.25, angle: 90, length: 2, aspect: 0.5);
    final double radius = sqrt(1850);
    _close(changed.gradients.first.imagingMatrices.single.numbers!, [0, radius, radius / 2, 0, 15, 30]);
    _close(changed.gradients.first.highlight!.numbers!, [0, radius / 2, 0, 0.5]);
    check(_object(changed, 1)).deepEquals(_object(source, 1));
    check(identical(_place(changed, x: 0.25, y: -0.25, angle: 90, length: 2, aspect: 0.5), changed)).isTrue();
  });

  test('copies shared styles once and synchronizes private notes without changing original styles', () {
    final String object = _shape(styled: true);
    final AiNativeDrawing source = _drawing('$object\n$object\n$object', styled: true);
    final AiNativeDrawing changed = _place(source, shapes: source.liveShapes.take(2).toList());
    check(changed.liveShapes.first.styleName).equals(changed.liveShapes[1].styleName);
    check(changed.liveShapes.last.styleName).equals('Shared');
    check(changed.records.roots.where((record) => record.type == 'KnownStyle')).length.equals(2);
    check(_object(changed, 2)).deepEquals(_object(source, 2));
    check(changed.gradients.take(4).every((gradient) => gradient.geometry.angle == 90 && gradient.geometry.origin[0] == 0.2)).isTrue();
    final AiNativeContainer style = changed.liveShapes.first.style!;
    final AiNativeContainer paint = changed.records.containers.singleWhere((record) => record.type == 'FillStyle' && record.start > style.start && record.end < style.end);
    check(AiNativePaintStyle.decode(records: changed.records, record: paint).gradients.single.geometry.length).equals(0.8);
    final AiNativeContainer original = source.liveShapes.first.style!;
    check(latin1.decode(changed.records.program.bytes)).contains(latin1.decode(source.records.program.bytes.sublist(original.start, original.end)));
  });

  test('uses tight cubic bounds including both native shorthand layouts', () {
    for (final (String, double) curve in [('0 0 m 0 40 20 40 20 0 C', 30.0), ('0 0 m 0 40 20 0 v', 160 / 9), ('0 0 m 0 40 20 0 y', 160 / 9)]) {
      final double height = curve.$2;
      final AiNativeDrawing source = _drawing(_shape(path: curve.$1, angle: 90, matrices: '0 $height 24 0 -2 0 Xm 0 100 24 0 -2 -100 Bc 0 $height 24 0 -2 0 Bm 0 100 24 0 -2 $height Bc'));
      final AiNativeDrawing changed = _place(source, x: 0, angle: 90, length: 2);
      _close(changed.gradients.single.imagingMatrices.first.numbers!.take(2).toList(), [0, 2 * height]);
    }
  });

  test('keeps printing coverage bounded during repeated rotations and inherited stroke edits', () {
    final String stroke = _shape().replaceFirst('Bb', '1 Bb').replaceFirst('f 0 BB', 'S 1 BB');
    AiNativeDrawing drawing = _drawing('q 40 w 20 M Q 4 w 3 M\n$stroke');
    for (int index = 0; index < 40; index++) {
      drawing = _place(drawing, angle: index.isEven ? 45 : 0);
      check(drawing.gradients.single.imagingMatrices.expand((matrix) => matrix.numbers!).every((value) => value.abs() < 1000)).isTrue();
    }
    final List<double> matrix = drawing.gradients.single.imagingMatrices.first.numbers!;
    // The final horizontal field covers the 40-unit path height, both
    // inherited 12-unit miter reaches and the antialiasing margins.
    check(matrix[3].abs() >= 68).isTrue();
    check(latin1.decode(drawing.records.program.bytes)).contains('q 40 w 20 M Q 4 w 3 M');
  });

  test('repartitions multiple intervals after placement and permits further placement edits', () {
    final AiNativeDrawing placed = _place(_drawing(_shape()));
    final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: placed.records);
    final AiNativeGradientResources recolored = resources.replaceStops(
      definition: resources.definitions.single,
      stops: [
        for (final double position in [10.0, 50.0, 90.0])
          AiNativeGradientStop(
            color: AiNativeGradientColor(kind: .gray, components: [position / 100]),
            position: position,
          ),
      ],
      ramps: [
        for (final List<int> samples in [
          [26, 128],
          [128, 230],
        ])
          AiNativeGradientRamp(
            kind: .gray,
            channels: [AiNativeGradientChannel.samples(values: samples)],
          ),
      ],
    );
    final AiNativeDrawing changed = _place(AiNativeDrawing.decode(records: recolored.records), angle: 37);
    final List<AiNativeInstruction> matrices = changed.gradients.single.imagingMatrices;
    check(matrices.map((matrix) => matrix.operator).toList()).deepEquals(['Xm', 'Bc', 'Bm', 'Bm', 'Bc']);
    final List<double> axis = matrices.first.numbers!;
    for (final AiNativeInstruction strip in matrices.where((matrix) => matrix.operator == 'Bm')) {
      _close(strip.numbers!.take(2).toList(), [axis[0] * 0.4, axis[1] * 0.4]);
    }
  });

  test('rejects invalid inputs, foreign handles, degenerate geometry and stale caches atomically', () {
    final AiNativeDrawing source = _drawing(_shape());
    for (final double value in [0.0, -1.0, double.infinity, double.nan]) {
      check(() => _place(source, length: value)).throws<ArgumentError>();
    }
    check(() => _place(source, y: 0.1)).throws<ArgumentError>();
    check(() => _place(source, aspect: 2)).throws<ArgumentError>();
    check(() => _place(source, angle: 361)).throws<ArgumentError>();
    check(() => _place(source, shapes: _drawing(_shape()).liveShapes)).throws<ArgumentError>();
    check(() => _place(_drawing(_shape(matrices: _linear.replaceFirst('20 0', '21 0'))))).throws<UnsupportedError>();
    final AiNativeDrawing radial = _drawing(_shape(radial: true), radial: true);
    check(() => _place(radial, x: 0.5, y: 0.5)).throws<FormatException>();
    check(() => _place(_drawing(_shape(radial: true).replaceFirst('0 0 0 0 Bh', '1 0 0 0 Bh'), radial: true))).throws<UnsupportedError>();
    final AiNativeDrawing limited = _drawing(_shape(), limit: source.records.program.bytes.length + 10);
    final List<int> bytes = limited.records.program.bytes.toList();
    check(() => _place(limited)).throws<FormatException>();
    check(limited.records.program.bytes).deepEquals(bytes);
  });
}
