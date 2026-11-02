import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Native shape dimensions independent of the miniature path used in each test.
String _dictionary({String handler = 'ai::Rectangle', String extra = '', bool redundant = false}) {
  final Map<String, double> dimensions = switch (handler) {
    'ai::Rectangle' => {'Width': 20, 'Height': 40, 'CornerRadius::0': 3},
    'ai::Ellipse' => {'Width': 20, 'Height': 40},
    'ai::Polygon' => {'Radius': 20, 'CornerRadius': 3},
    'ai::Star' => {'Radius1': 20, 'Radius2': 10, 'Corner1Radius': 3, 'Corner2Radius': 2},
    _ => {'Length': 20},
  };
  return '''%_/ArtDictionary :
%_(0.250000) /String (BBAccumRotation) ,
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_($handler) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_1020 /Real ($handler::CenterX) , 1970 /Real ($handler::CenterY) ,
%_0.25 /Real ($handler::${handler == 'ai::Rectangle' ? 'Angle' : 'RotationAngle'}) ,
${dimensions.entries.map((entry) => '%_${entry.value.toStringAsFixed(1)} /Real ($handler::${entry.key}) ,').join('\n')}
%_$extra
%_; (ai::LiveShape::Params) , ; (ai::LiveShape) , ;
''';
}

/// A printable path and its adjacent authoring dictionary.
String _shape({String handler = 'ai::Rectangle', String paint = 's'}) => '10 20 m 30 40 L $paint\n${_dictionary(handler: handler)}';

/// Decodes a source with a canvas origin unrelated to its page bounds.
AiNativeDrawing _drawing(String body, {String setup = '', int? limit}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%BoundingBox: 0 0 100 100
%%BeginSetup
/AI11TextDocument : /ASCII85Decode ,
%~>
1000 2000 /RulerOrigin , ;
$setup
%%EndSetup
$body
%%Trailer
%%EOF
'''),
      limits: AiNativeLimits(maxDecodedBytes: limit ?? 128 * 1024 * 1024),
    ),
  ),
);

/// Scales every bound native shape about a nonzero drawing-space pivot.
AiNativeDrawing _scale(AiNativeDrawing source, {double factor = 2}) => source.scaleLiveShapes(shapes: source.liveShapes, factor: factor, pivotX: 10, pivotY: 20);

/// Captures effective printable widths at each paint without consulting editors.
List<double> _widths(AiNativeDrawing drawing) {
  double width = 1;
  final List<double> result = [];
  for (final AiInstruction instruction in drawing.records.program.instructions) {
    if (instruction.operator == 'w') {
      width = instruction.numbers!.single;
    } else if (const {'s', 'S', 'b', 'B', 'f', 'F'}.contains(instruction.operator)) {
      result.add(width);
    }
  }
  return result;
}

/// Exercises native dimensions, inherited state, shared styles and atomic limits.
void main() {
  test('scales all five families, centers and corners without changing angles', () {
    for (final String handler in ['ai::Rectangle', 'ai::Ellipse', 'ai::Polygon', 'ai::Star', 'ai::Line']) {
      final AiNativeDrawing source = _drawing(_shape(handler: handler));
      final AiNativeDrawing changed = _scale(source);
      final AiLiveShape shape = changed.liveShapes.single;
      check(shape.parameters['$handler::CenterX']!.number).equals(1030);
      check(shape.parameters['$handler::CenterY']!.number).equals(1960);
      check(shape.parameters['$handler::${handler == 'ai::Rectangle' ? 'Angle' : 'RotationAngle'}']!.number).equals(0.25);
      check(shape.dictionary['BBAccumRotation']!.text()).equals('0.250000');
      for (final AiNativeEntry original in source.liveShapes.single.parameters.entries) {
        final String name = original.key!;
        if (name.contains('Radius') || name.endsWith('Width') || name.endsWith('Height') || name.endsWith('Length')) {
          check(shape.parameters[name]!.number).equals(original.number! * 2);
        }
      }
      check(shape.path!.segments.last.coordinates).deepEquals([50, 60]);
      check(_widths(changed)).deepEquals([2]);
      check(latin1.decode(changed.records.program.bytes)).contains('%%BoundingBox: -10 -20 190 180');
      check(identical(_scale(source, factor: 1), source)).isTrue();
    }
  });

  test('restores inherited widths and dashes outside a partial selection', () {
    final AiNativeDrawing source = _drawing('4 w [2 3] 1 d\n${_shape()}\n${_shape()}');
    final AiNativeDrawing changed = source.scaleLiveShapes(shapes: [source.liveShapes.first], factor: 0.5, pivotX: 0, pivotY: 0);
    check(_widths(changed)).deepEquals([2, 4]);
    check(changed.liveShapes.last.path!.segments.first.coordinates).deepEquals([10, 20]);
    final List<AiInstruction> dash = changed.records.program.instructions.where((instruction) => instruction.operator == 'd').toList();
    check(dash[dash.length - 2].operands.where((token) => token.number != null).map((token) => token.number).toList()).deepEquals([1, 1.5, 0.5]);
    check(dash.last.operands.where((token) => token.number != null).map((token) => token.number).toList()).deepEquals([2, 3, 1]);
    final AiNativeDrawing twice = _scale(_scale(source, factor: 0.5));
    check(_widths(twice)).deepEquals([4, 4]);
  });

  test('copies shared stroke styles once and retains redundant authoring parameters', () {
    const String style =
        '/KnownStyle : (Shared) /Name , /ActiveStyle : /BasicFilter : (Stroke Style Filter) 0 0 /Filter , /Dictionary : /StrokeStyle : 4 w [2 3] 1 d /Def ; (StrokeStyle) , ; /Dict ; /Execution ; /Def ;';
    final String object = 'u\n4 w 10 20 m 30 40 L S\nU\n${_dictionary(redundant: true)}\n6 () XW\n%_10 20 m 30 40 L n\n${_dictionary()}\n1 (Shared) XW';
    final AiNativeDrawing source = _drawing('$object\n$object\n$object', setup: style);
    final AiNativeDrawing changed = source.scaleLiveShapes(shapes: source.liveShapes.take(2).toList(), factor: 2, pivotX: 0, pivotY: 0);
    check(_widths(changed)).deepEquals([8, 8, 4]);
    check(changed.liveShapes.first.styleName).equals(changed.liveShapes[1].styleName);
    check(changed.liveShapes.last.styleName).equals('Shared');
    check(changed.records.roots.where((root) => root.type == 'KnownStyle')).length.equals(2);
    check(latin1.decode(changed.records.program.bytes)).contains(style);
    check(changed.liveShapes.first.appearanceDictionary!['ai::LiveShape']!.container!['ai::LiveShape::Params']!.container!['ai::Rectangle::Width']!.number).equals(40);
    final AiNativeContainer copied = changed.records.containers.firstWhere((record) => record.type == 'StrokeStyle' && record.start > changed.liveShapes.first.style!.start);
    final AiNativePaintStyle paint = AiNativePaintStyle.decode(records: changed.records, record: copied);
    check(paint.instructions.first.numbers!).deepEquals([8]);
  });

  test('scales accumulated gradients, printing matrices and Cartesian focus together', () {
    final AiNativeDrawing source = _drawing('10 20 m 30 40 L Bb\n5 0 0 0.25 Bh\n1 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg\n20 0 0 -30 10 20 Bm f 0 BB\n${_dictionary()}');
    final AiNativeDrawing changed = _scale(source);
    check(changed.gradients.single.geometry.matrix).deepEquals([2, 0, 0, 2, -1010, -1980]);
    check(changed.gradients.single.imagingMatrices.single.numbers!).deepEquals([40, 0, 0, -60, 10, 20]);
    check(changed.gradients.single.highlight!.numbers!).deepEquals([10, 0, 0, 0.25]);
    final AiNativeDrawing translated = changed.translateLiveShapes(shapes: changed.liveShapes, deltaX: 5, deltaY: 7);
    check(translated.gradients.single.geometry.matrix).deepEquals(changed.gradients.single.geometry.matrix);
    check(_scale(changed, factor: 0.5).gradients.single.geometry.matrix).deepEquals([1, 0, 0, 1, 0, 0]);
  });

  test('retains separate inherited private and printable stroke distances', () {
    final AiNativeDrawing source = _drawing('4 w [2 3] 1 d\n%_6 w [5 7] 3 d\n${_shape()}\n${_shape()}');
    final AiNativeDrawing changed = source.scaleLiveShapes(shapes: [source.liveShapes.first], factor: 2, pivotX: 0, pivotY: 0);
    check(_widths(changed)).deepEquals([8, 4]);
    final List<AiNativeInstruction> private = changed.items.whereType<AiNativeInstruction>().where((instruction) => instruction.isPrivate && instruction.operator == 'd').toList();
    check(private[1].operands.where((token) => token.number != null).map((token) => token.number).toList()).deepEquals([10, 14, 6]);
    check(private.last.operands.where((token) => token.number != null).map((token) => token.number).toList()).deepEquals([5, 7, 3]);
    check(changed.liveShapes.every((shape) => shape.isBound)).isTrue();
  });

  test('retains the observed unavailable-radius sentinel for irregular polygons', () {
    final String object = _shape(handler: 'ai::Polygon').replaceFirst('20.0 /Real (ai::Polygon::Radius)', '-11 /Real (ai::Polygon::Radius)');
    check(() => _scale(_drawing(object))).throws<FormatException>();
    final AiNativeDrawing source = _drawing(object.replaceFirst('%_0.25 /Real', '%_0 /Bool (ai::Polygon::IsRegular) ,\n%_0.25 /Real'));
    final AiNativeDrawing changed = _scale(source);
    check(changed.liveShapes.single.parameters['ai::Polygon::Radius']!.number).equals(-11);
    check(changed.liveShapes.single.path!.segments.last.coordinates).deepEquals([50, 60]);
  });

  test('rejects invalid dimensions, scale, strokes and output growth atomically', () {
    final AiNativeDrawing source = _drawing(_shape());
    for (final double factor in [0, -1, double.nan, double.infinity, 1e16, 5e-324, 1e-100]) {
      check(() => _scale(source, factor: factor)).throws<ArgumentError>();
    }
    for (final String prefix in ['-1 w', '[] d', '[0 0] 0 d', '[2 -1] 0 d']) {
      check(() => _scale(_drawing('$prefix\n${_shape()}'))).throws<FormatException>();
    }
    check(() => _scale(_drawing(_shape().replaceFirst('20.0 /Real (ai::Rectangle::Width)', '-20 /Real (ai::Rectangle::Width)')))).throws<FormatException>();
    final AiNativeDrawing tiny = _drawing('10 20 m 30 40 L Bb 1 (Ink) 0 0 0 1 1e-160 0 0 1e-160 0 0 1 Bg 20 0 0 -30 10 20 Bm f 0 BB\n${_dictionary()}');
    check(() => _scale(tiny, factor: 0.0001)).throws<ArgumentError>();
    final AiNativeDrawing limited = _drawing(_shape(), limit: source.records.program.bytes.length);
    final List<int> original = limited.records.program.bytes.toList();
    check(() => _scale(limited)).throws<FormatException>();
    check(limited.records.program.bytes).deepEquals(original);
  });

  test('orders insertions before replacements and preserves equal-position insertion order', () {
    final AiProgram source = _drawing(_shape()).records.program;
    final int offset = latin1.decode(source.bytes).indexOf('10 20 m');
    final AiProgram changed = AiNativeEditor.apply(
      program: source,
      edits: [
        AiSourceEdit(start: offset, end: offset + 2, bytes: latin1.encode('99')),
        for (int index = 0; index < 40; index++) AiSourceEdit(start: offset, end: offset, bytes: latin1.encode('% Insert $index\n')),
      ],
    );
    final String result = latin1.decode(changed.bytes);
    check(result).contains('${List.generate(40, (index) => '% Insert $index\n').join()}99 20 m');
  });
}
