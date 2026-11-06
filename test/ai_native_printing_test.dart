import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Declares a shared native style independently of its printing paths.
const String _style = '''/KnownStyle : (Shared) /Name ,
/ActiveStyle : /BasicFilter :
(Fill Style Filter) 0 0 /Filter ,
/Dictionary : /FillStyle : 0 0 0 k /Def ; (FillStyle) , ; /Dict ; /Execution ; /Def ;
''';

/// Authors the corresponding redundant or authoritative live-shape dictionary.
String _dictionary({bool redundant = false}) =>
    '''%_/ArtDictionary :
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_(ai::Rectangle) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary : ${redundant ? '/NotRecorded ,' : ''}
%_8000 /Real (ai::Rectangle::CenterX) ,
%_8100 /Real (ai::Rectangle::CenterY) ,
%_; (ai::LiveShape::Params) , ; (ai::LiveShape) , ;
''';

/// Independent nested compound expansion and a private outline with alternatives.
String _shape({String extra = ''}) =>
    '''u
$extra
0 0 0 1 k
10 20 m 30 20 L % retained contour comment
30 40 L 10 40 L f
*u
9 19 m 31 19 L 31 41 L 9 41 L f
11 21 m 11 39 L 29 39 L 29 21 L f
*U
U
${_dictionary(redundant: true)}
0 0 Xd
6 () XW
%_10 20 m 30 20 L 30 40 L 10 40 L n
%AI17_Begin_Content_if_version_gt:17 4
${_dictionary()}
%AI17_Alternate_Content
%_/ArtDictionary : (0) /String (BBAccumRotation) , ;
%AI17_End_Versioned_Content
1 (Shared) XW
''';

/// Wraps two native objects and an opaque neighbor in immutable source bounds.
AiNativeDrawing _drawing({String? first, String setup = '', AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%%EndComments
%%BeginSetup
$_style
$setup
%%EndSetup
${first ?? _shape()}
17 FutureNeighbor
%_/FutureRecord : 42 /Int (Opaque) , ;
${_shape()}
%%Trailer
%%EOF
'''),
      limits: limits,
    ),
  ),
);

/// Shares independently authored native ownership fixtures with group tests.
AiNativeDrawing printingFixture({String? group, String setup = '', AiNativeLimits limits = const AiNativeLimits()}) {
  final String shape = _shape();
  return _drawing(first: group == null ? null : '$group\n${shape.substring(shape.indexOf('%_/ArtDictionary'))}', setup: setup, limits: limits);
}

/// Supplies host-authored contours without changing native style or parameters.
AiNativePrintingReplacement _replacement(AiLiveShape shape, {bool multiple = false}) => AiNativePrintingReplacement(
  shape: shape,
  paths: [
    for (final AiNativePath path in shape.appearancePaths)
      AiNativePrintingContours(
        path: path,
        contours: [
          [
            AiPathSegment(operator: 'm', coordinates: [1, 2]),
            AiPathSegment(operator: 'C', coordinates: [3, 4, 5, 6, 7, 8]),
            AiPathSegment(operator: 'L', coordinates: [9, 10]),
          ],
          if (multiple)
            [
              AiPathSegment(operator: 'm', coordinates: [20, 20]),
              AiPathSegment(operator: 'v', coordinates: [22, 24, 26, 28]),
              AiPathSegment(operator: 'Y', coordinates: [30, 32, 34, 36]),
            ],
        ],
      ),
  ],
  bounds: AiBoundingBox(left: -5, bottom: -10, right: 120, top: 130),
);

/// Compares raw owned ranges without normalizing opaque metadata.
List<int> _bytes(AiNativeDrawing drawing, int start, int end) => drawing.records.program.bytes.sublist(start, end);

/// Verifies host geometry attachment, source preservation and refusal policies.
void main() {
  test('attaches multiple contours while retaining private data, compounds and opaque neighbors', () {
    final AiNativeDrawing source = _drawing();
    final AiLiveShape shape = source.liveShapes.first;
    final List<int> before = source.records.program.bytes.toList();
    final AiNativeDrawing saved = source.withPrintingContours(replacements: [_replacement(shape, multiple: true)]);
    final AiLiveShape changed = saved.liveShapes.first;
    check(changed.isBound).isTrue();
    check(changed.appearancePaths).length.equals(6);
    check(saved.groups.where((group) => group.compound).first.paths).length.equals(4);
    check(changed.appearancePaths.map((path) => path.paint.operator)).deepEquals(List.filled(6, 'f'));
    check(changed.appearancePaths.first.segments.map((segment) => segment.operator)).deepEquals(['m', 'C', 'L']);
    check(changed.appearancePaths[1].segments.map((segment) => segment.operator)).deepEquals(['m', 'v', 'Y']);
    check(saved.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As')).isEmpty();
    check(_bytes(saved, changed.path!.start, changed.end)).deepEquals(_bytes(source, shape.path!.start, shape.end));
    check(_bytes(saved, changed.style!.start, changed.style!.end)).deepEquals(_bytes(source, shape.style!.start, shape.style!.end));
    check(_bytes(saved, changed.appearanceGroup!.end, changed.path!.start)).deepEquals(_bytes(source, shape.appearanceGroup!.end, shape.path!.start));
    check(_bytes(saved, changed.end, saved.records.program.bytes.length)).deepEquals(_bytes(source, shape.end, source.records.program.bytes.length));
    check(latin1.decode(saved.records.program.bytes)).contains('% retained contour comment');
    check(latin1.decode(saved.records.program.bytes)).contains('%%BoundingBox: -5 -10 120 130');
    check(source.records.program.bytes).deepEquals(before);
    final AiNativeDrawing reopened = AiNativeDrawing.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: saved.records.program.bytes)),
    );
    check(reopened.liveShapes.first.appearancePaths).length.equals(6);
    check(reopened.liveShapes.last.appearancePaths).length.equals(3);
  });

  test('writes a batch against original offsets without losing shared style identity', () {
    final AiNativeDrawing source = _drawing();
    final AiNativeDrawing changed = source.withPrintingContours(replacements: source.liveShapes.map(_replacement).toList());
    check(changed.liveShapes).every((shape) => shape.has((shape) => shape.isBound, 'isBound').isTrue());
    check(changed.liveShapes.first.style).identicalTo(changed.liveShapes.last.style);
    check(changed.liveShapes.first.path!.segments.map((segment) => segment.coordinates)).deepEquals(source.liveShapes.first.path!.segments.map((segment) => segment.coordinates));
  });

  test('rejects stale, foreign, duplicate and incomplete selections atomically', () {
    final AiNativeDrawing source = _drawing();
    final AiNativePrintingReplacement valid = _replacement(source.liveShapes.first);
    final AiNativeDrawing saved = source.withPrintingContours(replacements: [valid]);
    check(() => saved.withPrintingContours(replacements: [valid])).throws<ArgumentError>();
    for (final List<AiNativePrintingReplacement> selection in [
      <AiNativePrintingReplacement>[],
      [valid, valid],
      [_replacement(_drawing().liveShapes.first)],
      [AiNativePrintingReplacement(shape: valid.shape, paths: valid.paths.take(2).toList(), bounds: valid.bounds)],
      [
        AiNativePrintingReplacement(shape: valid.shape, paths: [valid.paths.first, valid.paths.first, valid.paths.last], bounds: valid.bounds),
      ],
      [AiNativePrintingReplacement(shape: valid.shape, paths: _replacement(source.liveShapes.last).paths, bounds: valid.bounds)],
    ]) {
      check(() => source.withPrintingContours(replacements: selection)).throws<ArgumentError>();
    }
  });

  test('rejects local unknown state, nested metadata and interleaved path controls', () {
    for (final String body in [
      _shape(extra: '17 FuturePaint'),
      _shape(extra: '%_/ArtDictionary : (opaque) /String (Unknown) , ;'),
      _shape(extra: '%%BeginDocument: unknown.eps\n17 FuturePaint\n%%EndDocument'),
      _shape(extra: '%%BeginData: 1 ASCII Lines\n17 FuturePaint\n%%EndData'),
      _shape(extra: '%AI99_FutureConditional: 1'),
      _shape().replaceFirst('30 20 L', '30 20 L 0 1 0 0 k'),
    ]) {
      final AiNativeDrawing source = _drawing(first: body);
      final List<int> before = source.records.program.bytes.toList();
      check(() => source.withPrintingContours(replacements: [_replacement(source.liveShapes.first)])).throws<UnsupportedError>();
      check(source.records.program.bytes).deepEquals(before);
    }
  });

  test('does not treat an authoritative direct path or unbound object as a derived slot', () {
    for (final String body in ['10 20 m 30 40 L S\n${_dictionary()}', _shape().replaceFirst('1 (Shared) XW', '1 (Missing) XW')]) {
      final AiNativeDrawing source = _drawing(first: body);
      check(() => source.withPrintingContours(replacements: [_replacement(source.liveShapes.first)])).throws<UnsupportedError>();
    }
  });

  test('retains trailing paint controls and refuses to repeat their wrapped path', () {
    final AiNativeDrawing source = _drawing(first: _shape().replaceFirst('30 40 L 10 40 L f', '30 40 L 10 40 L 0 1 0 0 k f'));
    final AiNativeDrawing changed = source.withPrintingContours(replacements: [_replacement(source.liveShapes.first)]);
    check(latin1.decode(changed.records.program.bytes)).contains('0 1 0 0 k f');
    check(changed.liveShapes.first.appearancePaths).length.equals(3);
    check(() => source.withPrintingContours(replacements: [_replacement(source.liveShapes.first, multiple: true)])).throws<UnsupportedError>();
  });

  test('updates counted CC paths and gives additional contours their own counts', () {
    for (final bool closed in [true, false]) {
      final String body = _shape().replaceFirst('10 20 m', '4 As\n10 20 m').replaceFirst('30 40 L 10 40 L f', closed ? '30 40 L 10 40 L 10 20 L f' : '30 40 L 10 40 L F');
      final AiNativeDrawing source = _drawing(first: body);
      final AiNativeDrawing saved = source.withPrintingContours(replacements: [_replacement(source.liveShapes.first, multiple: true)]);
      final AiLiveShape shape = saved.liveShapes.first;
      final List<AiNativeInstruction> counts = saved.items.whereType<AiNativeInstruction>().where((item) => item.operator == 'As' && item.end <= shape.appearanceGroup!.end).toList();
      check(counts.map((count) => count.numbers!.single)).deepEquals([3, 3]);
      for (final AiNativePath path in shape.appearancePaths.take(2)) {
        check(path.segments).length.equals(closed ? 4 : 3);
        if (closed) {
          check(path.segments.last.operator).equals('L');
          check(path.segments.last.coordinates).deepEquals(path.segments.first.coordinates);
        }
      }
      check(_bytes(saved, shape.appearanceGroup!.end, saved.records.program.bytes.length)).deepEquals(
        _bytes(source, source.liveShapes.first.appearanceGroup!.end, source.records.program.bytes.length),
      );
      final AiNativePrintingReplacement original = _replacement(source.liveShapes.first);
      final AiNativeDrawing point = source.withPrintingContours(
        replacements: [
          AiNativePrintingReplacement(
            shape: original.shape,
            bounds: original.bounds,
            paths: [
              for (final AiNativePrintingContours path in original.paths)
                AiNativePrintingContours(
                  path: path.path,
                  contours: [
                    [path.contours.first.first],
                  ],
                ),
            ],
          ),
        ],
      );
      check(point.items.whereType<AiNativeInstruction>().singleWhere((item) => item.operator == 'As').numbers).isNotNull().deepEquals([1]);
    }
  });

  test('rejects ambiguous, stale or unsupported native point-count ownership', () {
    final String counted = _shape().replaceFirst('10 20 m', '4 As\n10 20 m').replaceFirst('30 40 L 10 40 L f', '30 40 L 10 40 L 10 20 L f');
    for (final String body in [
      for (final String count in ['5 As', '1.5 As', '(4) As', '4 4 As', '4 As\n4 As']) counted.replaceFirst('4 As', count),
      _shape().replaceFirst('10 20 m', '3 As\n10 20 m'),
      counted.replaceFirst('4 As\n', '').replaceFirst('10 20 L f', '10 20 L 4 As f'),
      _shape().replaceFirst('*u', '4 As\n*u'),
      '4 As\n${_shape()}',
    ]) {
      final AiNativeDrawing source = _drawing(first: body);
      final List<int> before = source.records.program.bytes.toList();
      check(() => source.withPrintingContours(replacements: [_replacement(source.liveShapes.first)])).throws<UnsupportedError>();
      check(source.records.program.bytes).deepEquals(before);
    }
  });

  test('freezes supplied contours and bounds expansion before allocating full output', () {
    final AiNativeDrawing source = _drawing();
    final AiNativePath path = source.liveShapes.first.appearancePaths.first;
    final List<AiPathSegment> contour = path.segments.toList();
    final List<List<AiPathSegment>> contours = [contour];
    final AiNativePrintingContours supplied = AiNativePrintingContours(path: path, contours: contours);
    contour.clear();
    contours.clear();
    check(supplied.contours.single).length.equals(4);
    check(supplied.contours.clear).throws<UnsupportedError>();
    check(supplied.contours.single.clear).throws<UnsupportedError>();
    check(() => AiNativePrintingContours(path: path, contours: [])).throws<ArgumentError>();
    check(() => AiNativePrintingContours(path: path, contours: [<AiPathSegment>[]])).throws<ArgumentError>();
    check(() => AiNativePrintingContours(path: path, contours: [path.segments.skip(1).toList()])).throws<ArgumentError>();
    final AiNativeDrawing bounded = _drawing(limits: AiNativeLimits(maxDecodedBytes: source.records.program.bytes.length + 10));
    final AiNativePrintingReplacement original = _replacement(bounded.liveShapes.first);
    final List<AiNativePrintingContours> excessive = [
      for (final AiNativePrintingContours part in original.paths) AiNativePrintingContours(path: part.path, contours: List.filled(500, part.contours.first)),
    ];
    check(
      () => bounded.withPrintingContours(
        replacements: [AiNativePrintingReplacement(shape: original.shape, paths: excessive, bounds: original.bounds)],
      ),
    ).throws<AiLimitException>();
    check(
      () => AiNativePrintingReplacement(shape: original.shape, paths: original.paths, bounds: AiBoundingBox(left: 0, bottom: 0, right: 1e308, top: 1e308)),
    ).throws<ArgumentError>();
    final AiNativeDrawing tokenBounded = _drawing(limits: const AiNativeLimits(maxTokens: 2000));
    final AiNativePrintingReplacement tokenOriginal = _replacement(tokenBounded.liveShapes.first);
    check(
      () => tokenBounded.withPrintingContours(
        replacements: [
          AiNativePrintingReplacement(
            shape: tokenOriginal.shape,
            paths: [for (final AiNativePrintingContours part in tokenOriginal.paths) AiNativePrintingContours(path: part.path, contours: List.filled(500, part.contours.first))],
            bounds: tokenOriginal.bounds,
          ),
        ],
      ),
    ).throws<AiLimitException>();
  });
}
