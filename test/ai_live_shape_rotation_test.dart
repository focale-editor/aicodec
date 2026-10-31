import 'dart:convert';
import 'dart:math';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Native metadata with independently specified canvas coordinates and angle.
String _dictionary({String handler = 'ai::Rectangle', bool redundant = false, String extra = ''}) =>
    '''%_/ArtDictionary :
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_($handler) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary :
%_1020 /Real ($handler::CenterX) ,
%_1970 /Real ($handler::CenterY) ,
%_0 /Real ($handler::${handler == 'ai::Rectangle' ? 'Angle' : 'RotationAngle'}) ,
%_; (ai::LiveShape::Params) ,
%_; (ai::LiveShape) ,
%_$extra
%_;
''';

/// Printable rectangle with an optional radial gradient appearance.
String _path({bool gradient = false}) =>
    '''10 20 m 30 20 L 30 40 L 10 40 L
${gradient ? 'Bb\n5 0 0 0.25 Bh\n1 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg\n20 0 0 -30 10 20 Bm' : ''}
f
${gradient ? '0 BB' : ''}''';

/// Builds a bounded source with a setup origin independent of the artboard.
AiNativeDrawing _drawing(String body, {String setup = '', String origin = '/AI11TextDocument : /ASCII85Decode ,\n%~>\n1000 2000 /RulerOrigin , ;', int? limit}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('%!PS-Adobe-3.0\n%%BoundingBox: 0 0 100 100\n%%HiResBoundingBox: 0 0 100 100\n%%BeginSetup\n$origin\n$setup\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'),
      limits: AiNativeLimits(maxDecodedBytes: limit ?? 128 * 1024 * 1024),
    ),
  ),
);

/// Applies a counterclockwise quarter-turn to the whole live selection.
AiNativeDrawing _rotate(AiNativeDrawing drawing, {double radians = pi / 2, double pivotX = 0, double pivotY = 0}) =>
    drawing.rotateLiveShapes(shapes: drawing.liveShapes, radians: radians, pivotX: pivotX, pivotY: pivotY);

/// Verifies canvas, frame, authoring and printing geometry remain synchronized.
void main() {
  test('rotates five native shape families and leaves dimensions and corners intact', () {
    for (final String handler in ['ai::Rectangle', 'ai::Ellipse', 'ai::Polygon', 'ai::Star', 'ai::Line']) {
      final AiNativeDrawing source = _drawing('${_path()}\n${_dictionary(handler: handler)}');
      final AiNativeDrawing changed = _rotate(source);
      final AiLiveShape shape = changed.liveShapes.single;
      check(shape.parameters['$handler::CenterX']!.number).equals(970);
      check(shape.parameters['$handler::CenterY']!.number).equals(1980);
      check(shape.parameters['$handler::${handler == 'ai::Rectangle' ? 'Angle' : 'RotationAngle'}']!.number).equals(pi / 2);
      check(double.parse(shape.dictionary['BBAccumRotation']!.text()!)).isCloseTo(pi / 2, 0.0000005);
      check(shape.path!.segments.first.coordinates).deepEquals([-20, 10]);
      check(source.paths.single.segments.first.coordinates).deepEquals([10, 20]);
      check(latin1.decode(changed.records.program.bytes)).contains('%%BoundingBox: -100 0 100 100');
    }
  });

  test('uses a drawing pivot and preserves exact full-turn and zero no-ops', () {
    final AiNativeDrawing source = _drawing('${_path()}\n${_dictionary()}');
    final AiNativeDrawing changed = _rotate(source, pivotX: 20, pivotY: 30, radians: -pi / 2);
    check(changed.paths.single.segments.first.coordinates).deepEquals([10, 40]);
    check(changed.liveShapes.single.parameters['ai::Rectangle::CenterX']!.number).equals(1020);
    check(changed.liveShapes.single.parameters['ai::Rectangle::Angle']!.number).equals(3 * pi / 2);
    for (final double angle in [0, 2 * pi, -2 * pi]) {
      check(identical(_rotate(source, radians: angle), source)).isTrue();
    }
  });

  test('rotates cubic controls and shorthand while retaining operators', () {
    final AiNativeDrawing source = _drawing('10 20 m 15 20 30 25 30 40 C 35 40 40 45 v 45 50 10 20 Y f\n${_dictionary(extra: '1 /Bool (PATH_IS_KAPPA_CURVE) ,')}');
    final AiNativeDrawing changed = _rotate(source);
    check(changed.paths.single.segments.map((segment) => segment.operator).toList()).deepEquals(['m', 'C', 'v', 'Y']);
    check(changed.paths.single.segments[1].coordinates).deepEquals([-20, 15, -25, 30, -40, 30]);
    check(changed.liveShapes.single.dictionary['PATH_IS_KAPPA_CURVE']!.boolean).equals(true);
  });

  test('composes CC matrices in their own frames and preserves radial polar focus', () {
    final AiNativeDrawing source = _drawing('${_path(gradient: true)}\n${_dictionary()}');
    final AiNativeDrawing changed = _rotate(source);
    final AiNativeGradient gradient = changed.gradients.single;
    check(gradient.geometry.matrix).deepEquals([0, -1, 1, 0, -1000, 3000]);
    check(gradient.imagingMatrices.single.numbers!).deepEquals([0, 20, 30, 0, -20, 10]);
    check(gradient.highlight!.numbers!).deepEquals([0, 5, 0, 0.25]);
    final AiNativeContainer metadata = changed.liveShapes.single.dictionary['Adobe_AI9_ArtStyle_Dictionary']!.container!;
    check(metadata.notRecorded).isTrue();
    check(metadata['CAIGradientTformMatrix']!.numbers!).deepEquals(gradient.geometry.matrix);
    final AiNativeDrawing twice = _rotate(changed);
    check(twice.gradients.single.geometry.matrix).deepEquals([-1, 0, 0, -1, 2000, 4000]);
    final AiNativeDrawing moved = twice.translateLiveShapes(shapes: twice.liveShapes, deltaX: 7, deltaY: -3);
    check(moved.gradients.single.geometry.matrix).deepEquals(twice.gradients.single.geometry.matrix);
    check(moved.gradients.single.imagingMatrices.single.numbers!.skip(4).toList()).deepEquals([-3, -23]);
  });

  test('updates private and redundant copies while leaving shared styles and unselected art intact', () {
    const String style =
        '/KnownStyle : (Shared) /Name , /ActiveStyle : /BasicFilter : (Fill Style Filter) 0 0 /Filter , /Dictionary : /FillStyle : Bb 0 0 0 0.25 Bh 2 (Ink) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB /Def ; (FillStyle) , ; /Dict ; /Execution ; /Def ;';
    final String object = 'u\n${_path(gradient: true)}\nU\n${_dictionary(redundant: true)}\n0 0 Xd\n6 () XW\n%_10 20 m 30 20 L 30 40 L 10 40 L n\n${_dictionary()}\n1 (Shared) XW';
    final AiNativeDrawing source = _drawing('$object\n$object', setup: style);
    final AiNativeDrawing changed = source.rotateLiveShapes(shapes: [source.liveShapes.first], radians: pi / 2, pivotX: 0, pivotY: 0);
    check(changed.liveShapes.first.path!.segments.first.coordinates).deepEquals([-20, 10]);
    check(changed.liveShapes.first.appearancePaths.single.segments.first.coordinates).deepEquals([-20, 10]);
    check(changed.liveShapes.last.path!.segments.first.coordinates).deepEquals([10, 20]);
    check(changed.liveShapes.last.dictionary['BBAccumRotation']).isNull();
    check(changed.liveShapes.first.appearanceDictionary!['Adobe_AI9_ArtStyle_Dictionary']).isNotNull();
    check(changed.liveShapes.first.styleName).equals('Shared');
    check(changed.records.roots.where((record) => record.type == 'KnownStyle')).length.equals(1);
    check(latin1.decode(changed.records.program.bytes)).contains(style);
  });

  test('rejects missing or ambiguous origins, foreign selections and excessive numbers', () {
    final String body = '${_path()}\n${_dictionary()}';
    final AiNativeDrawing source = _drawing(body);
    for (final String origin in [
      '',
      '/AI11TextDocument : /ASCII85Decode ,\n%~>\n0 /RulerOrigin , ;',
      '/AI11TextDocument : /ASCII85Decode ,\n%~>\n0 0 /RulerOrigin , ; /AI11TextDocument : /ASCII85Decode ,\n%~>\n0 0 /RulerOrigin , ;',
    ]) {
      check(() => _rotate(_drawing(body, origin: origin))).throws<UnsupportedError>();
    }
    check(() => source.rotateLiveShapes(shapes: _drawing(body).liveShapes, radians: 1, pivotX: 0, pivotY: 0)).throws<ArgumentError>();
    for (final double angle in [double.nan, double.infinity, 7]) {
      check(() => _rotate(source, radians: angle)).throws<ArgumentError>();
    }
    check(() => _rotate(source, pivotX: double.nan)).throws<ArgumentError>();
    check(() => _rotate(source, pivotX: 9007199254740991)).throws<ArgumentError>();
  });

  test('rejects stale gradient metadata and unknown dependencies without partial changes', () {
    final AiNativeDrawing stale = _drawing(
      '${_path(gradient: true)}\n${_dictionary(extra: '/Dictionary : /NotRecorded , 1 0 0 1 9 9 /RealMatrix (CAIGradientTformMatrix) , ; (Adobe_AI9_ArtStyle_Dictionary) ,')}',
    );
    check(() => _rotate(stale)).throws<UnsupportedError>();
    final AiNativeDrawing legacy = _drawing('${_path(gradient: true).replaceFirst('0 0 1 Bg', '0 0 Bg')}\n${_dictionary()}');
    check(() => _rotate(legacy)).throws<UnsupportedError>();
    final AiNativeDrawing unknown = _drawing('${_path()}\n${_dictionary(extra: '1 /Real (FutureRotation) ,')}');
    check(() => _rotate(unknown)).throws<UnsupportedError>();
    check(() => _rotate(_drawing('${_path()}\n${_dictionary(extra: '1 /Real (PATH_IS_KAPPA_CURVE) ,')}'))).throws<UnsupportedError>();
    final String body = '${_path(gradient: true)}\n${_dictionary()}';
    final AiNativeDrawing limited = _drawing(body, limit: _drawing(body).records.program.bytes.length);
    final List<int> bytes = limited.records.program.bytes.toList();
    check(() => _rotate(limited)).throws<FormatException>();
    check(limited.records.program.bytes).deepEquals(bytes);
  });

  test('preserves split frame syntax and bounds deferred DSC without touching nested documents', () {
    final String body = '${_path()}\n${_dictionary(extra: '(0.) (25) /UnicodeString (BBAccumRotation) ,')}';
    final AiNativeDrawing changed = _rotate(_drawing(body), radians: 0.5);
    check(changed.liveShapes.single.dictionary['BBAccumRotation']!.type).equals('UnicodeString');
    check(double.parse(changed.liveShapes.single.dictionary['BBAccumRotation']!.text()!)).equals(0.75);
    final AiProgram source = AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%BoundingBox: (atend)
%%BeginSetup
%%BeginDocument: nested
%%BoundingBox: 0 0 1 1
%%EndDocument
%%EndSetup
0 0 m 1 1 L S
%%Trailer
%%BoundingBox: 10 20 30 40
%%EOF
'''),
    );
    final AiProgram bounded = AiNativeEditor.apply(
      program: source,
      edits: AiNativeEditor.affineBoundsEdits(program: source, matrix: [0, 1, -1, 0, 0, 0]),
    );
    final String text = latin1.decode(bounded.bytes);
    check(text).contains('%%BoundingBox: (atend)');
    check(text).contains('%%BoundingBox: 0 0 1 1');
    check(text).contains('%%BoundingBox: -40 10 30 40');
    for (final List<double> matrix in [
      <double>[],
      [1, 0, 0, 1, double.nan, 0],
      [1e15, 0, 0, 1, 0, 0],
    ]) {
      check(() => AiNativeEditor.affineBoundsEdits(program: source, matrix: matrix)).throws<ArgumentError>();
    }
  });
}
