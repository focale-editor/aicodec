import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Builds independently specified point and curved-area frames in one story.
AiNativeTextDocument _document({bool named = false, String? areaPath, bool missingPath = false, bool missingReference = false, bool unusedFrame = false, int areaType = 1, double translation = 100}) {
  /// Uses the fixture's chosen ATE field spelling.
  String key(String compact, String full) => named ? full : compact;
  final String text = latin1.decode(PsEngineCodec.encode(value: PsEngineString.fromText(text: 'AB\r')));
  final List<int> engine = latin1.encode('''
/${key('0', 'DocumentResources')} <<
 /${key('8', 'TextFrameSet')} << /${key('0', 'Resources')} [
  << /${key('0', 'Resource')} << /${key('0', 'Position')} [10 20] /${key('2', 'Data')} << >> >> >>
  << /${key('0', 'Resource')} << /${key('1', 'Bezier')} << /${key('0', 'Points')} [0 0 2 3 7 8 10 10] >>
   /${key('2', 'Data')} << /${key('0', 'Type')} $areaType /${key('2', 'FrameMatrix')} [0.8 0.6 -0.6 0.8 $translation -50] >> >> >>
 ] >> >>
/${key('1', 'DocumentObjects')} << /${key('1', 'TextObjects')} [ <<
 /${key('0', 'Model')} << /${key('0', 'Text')} $text >>
 /${key('1', 'View')} << /${key('0', 'Frames')} [ << /${key('0', 'Resource')} 0 >> ${unusedFrame ? '' : '<< /${key('0', 'Resource')} 1 >>'} ]
  /${key('2', 'Strikes')} [ << /${key('99', 'StreamTag')} /${named ? 'FrameStrike' : 'F'} /${key('10', 'Frame')} 1
   /${key('0', 'Transform')} << /${key('0', 'Origin')} [10 20] >> /${key('6', 'Children')} [
    << /${key('99', 'StreamTag')} /${named ? 'GlyphStrike' : 'G'} /${key('5', 'Glyphs')} [41 42 1] /${key('8', 'VisualBounds')} [10 15 30 22] >> ] >> ]
 >> >> ] >>
''');
  final String encoded = latin1.decode(PdfFilters.encodeAscii85(bytes: engine));
  final String path = areaPath ?? 'X= 1 Ap 1 As 0 0 m 2 3 7 8 10 10 c n /ArtDictionary : (0.4) /String (BBAccumRotation) , ; X+';
  return AiNativeTextDocument.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(
        bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
%%HiResBoundingBox: 0.25 0.5 99.25 99.5
/AI11TextDocument : /ASCII85Decode ,
%$encoded
0 0 /RulerOrigin , ;
%%EndSetup
/AI11Text : 0 /FreeUndo , 0 /StoryIndex , 0 /FrameIndex , ;
${missingReference || unusedFrame ? '' : '/AI11Text : 0 /FreeUndo , 0 /StoryIndex , 1 /FrameIndex , ${missingPath ? '' : '/Art : $path ; /ConfiningPath ,'} ;'}
%%Trailer
%%EOF
'''),
      ),
    ),
  );
}

/// Reads a confinement's geometry through the public command view.
List<List<double>> _coordinates(AiNativeTextDocument document) {
  final AiNativeContainer path = document.objects.last.record['ConfiningPath']!.container!;
  return [
    for (final AiNativeInstruction item in AiNativeArt.decode(records: document.records, record: path).items.whereType<AiNativeInstruction>())
      if (const {'m', 'l', 'L', 'c', 'C', 'v', 'V', 'y', 'Y'}.contains(item.operator)) item.numbers!,
  ];
}

/// Checks frame transforms, local caches and dependent source paths together.
void main() {
  for (final bool named in [false, true]) {
    test('translates ${named ? 'named CS' : 'compact CC'} frames and retains all local caches', () {
      final AiNativeTextDocument source = _document(named: named);
      final AiNativeTextDocument changed = source.translateFrames(frames: source.frames, deltaX: 7.25, deltaY: -4.5);
      check(changed.frames[0].matrix!).deepEquals([1.0, 0.0, 0.0, 1.0, 7.25, 4.5]);
      check(changed.frames[1].matrix!).deepEquals([0.8, 0.6, -0.6, 0.8, 107.25, -45.5]);
      check(changed.frames[0].position!).deepEquals(source.frames[0].position!);
      check(changed.frames[1].pathCoordinates!).deepEquals(source.frames[1].pathCoordinates!);
      check(_coordinates(changed)).deepEquals([
        [7.25, -4.5],
        [9.25, -1.5, 14.25, 3.5, 17.25, 5.5],
      ]);
      final PsEngineValue before = (source.engine.root as PsEngineDictionary)[named ? 'DocumentObjects' : '1']!;
      final PsEngineValue after = (changed.engine.root as PsEngineDictionary)[named ? 'DocumentObjects' : '1']!;
      check(source.engine.bytes.sublist(before.start!, before.end)).deepEquals(changed.engine.bytes.sublist(after.start!, after.end));
      final String program = latin1.decode(changed.records.program.bytes);
      check(program).contains('%%BoundingBox: 0 -5 108 100');
      final AiBoundingBox precise = AiBoundingBox.parse(value: RegExp(r'%%HiResBoundingBox: ([^\r\n]+)').firstMatch(program)![1]!);
      check([precise.left, precise.bottom, precise.right, precise.top]).deepEquals([0.25, -4.0, 106.5, 99.5]);
      check(program).contains('(0.4) /String (BBAccumRotation)');
      check(changed.referenceIssues).isEmpty();
      check(identical(source, source.translateFrames(frames: source.frames, deltaX: 0, deltaY: 0))).isTrue();
    });
  }

  test('moves one linked frame and keeps other frame resources and paths intact', () {
    final AiNativeTextDocument source = _document();
    final AiNativeTextDocument point = source.translateFrames(frames: [source.frames.first], deltaX: -2, deltaY: 3);
    check(point.frames.last.matrix!).deepEquals(source.frames.last.matrix!);
    check(_coordinates(point)).deepEquals(_coordinates(source));
    final AiNativeTextDocument area = source.translateFrames(frames: [source.frames.last], deltaX: -2, deltaY: 3);
    check(area.frames.first.matrix).isNull();
    check(area.stories.single.frameIndices).deepEquals([0, 1]);
    final AiNativeTextDocument restored = area.translateFrames(frames: [area.frames.last], deltaX: 2, deltaY: -3);
    check(restored.frames.last.matrix!).deepEquals(source.frames.last.matrix!);
    check(_coordinates(restored)).deepEquals(_coordinates(source));
  });

  test('moves path text without changing its local curve or source mapping', () {
    final AiNativeTextDocument source = _document(areaType: 2);
    final AiNativeTextDocument moved = source.translateFrames(frames: [source.frames.last], deltaX: 5, deltaY: 6);
    check(moved.frames.last.kind).equals(AiNativeTextFrameKind.path);
    check(moved.frames.last.pathCoordinates!).deepEquals(source.frames.last.pathCoordinates!);
    check(moved.stories.single.modelText).equals(source.stories.single.modelText);
    check(moved.stories.single.strikes.single.children.single.glyphIds).deepEquals([41, 42, 1]);
  });

  test('preserves curve shorthand and explicit path closure', () {
    final AiNativeTextDocument source = _document(areaPath: 'X= 0 0 m 2 3 4 5 v 6 7 8 9 Y h N X+');
    final AiNativeTextDocument moved = source.translateFrames(frames: [source.frames.last], deltaX: 1, deltaY: -2);
    check(_coordinates(moved)).deepEquals([
      [1.0, -2.0],
      [3.0, 1.0, 5.0, 3.0],
      [7.0, 5.0, 9.0, 7.0],
    ]);
    check(latin1.decode(moved.records.program.bytes)).contains('h N X+');
  });

  test('rejects foreign, duplicate, unused and incomplete frame selections atomically', () {
    final AiNativeTextDocument source = _document();
    final AiNativeTextDocument foreign = _document();
    for (final List<AiNativeTextFrame> frames in [
      <AiNativeTextFrame>[],
      [foreign.frames.first],
      [source.frames.first, source.frames.first],
    ]) {
      check(() => source.translateFrames(frames: frames, deltaX: 1, deltaY: 1)).throws<ArgumentError>();
    }
    check(() => source.translateFrames(frames: source.frames, deltaX: double.infinity, deltaY: 1)).throws<ArgumentError>();
    for (final AiNativeTextDocument invalid in [_document(missingPath: true), _document(missingReference: true)]) {
      check(() => invalid.translateFrames(frames: invalid.frames, deltaX: 1, deltaY: 1)).throws<FormatException>();
      check(invalid.frames.last.matrix!).deepEquals([0.8, 0.6, -0.6, 0.8, 100.0, -50.0]);
    }
    final AiNativeTextDocument unknown = _document(areaType: 7);
    check(() => unknown.translateFrames(frames: unknown.frames, deltaX: 1, deltaY: 1)).throws<UnsupportedError>();
    final AiNativeTextDocument unused = _document(unusedFrame: true);
    check(() => unused.translateFrames(frames: [unused.frames.last], deltaX: 1, deltaY: 1)).throws<ArgumentError>();
    final AiNativeTextDocument overflow = _document(translation: 1.7e308);
    check(() => overflow.translateFrames(frames: overflow.frames, deltaX: 1.7e308, deltaY: 1)).throws<ArgumentError>();
    check(_coordinates(source)).deepEquals([
      [0.0, 0.0],
      [2.0, 3.0, 7.0, 8.0, 10.0, 10.0],
    ]);
  });

  test('rejects unmodeled confinement transforms, paint, metadata and topology', () {
    for (final String path in [
      'X= 1 0 0 1 5 6 cm 0 0 m 1 1 L n X+',
      'X= 0 0 m 1 1 L f X+',
      'X= 0 0 m 1 1 L n /ArtDictionary : /Dictionary : 3 /Real (CenterX) , ; (ai::LiveShape) , ; X+',
      'X= 0 0 m 1 1 L n 3 3 m 4 4 L n X+',
    ]) {
      final AiNativeTextDocument source = _document(areaPath: path);
      check(() => source.translateFrames(frames: source.frames, deltaX: 1, deltaY: 1)).throws<UnsupportedError>();
    }
    for (final String path in ['0 0 m 1 1 L n X+', 'X= 0 0 m 1 1 L n', 'X= 0 0 m X+']) {
      check(() {
        final AiNativeTextDocument source = _document(areaPath: path);
        source.translateFrames(frames: source.frames, deltaX: 1, deltaY: 1);
      }).throws<FormatException>();
    }
  });

  test('bounds matrix expansion and refuses unmodeled layout fields', () {
    final AiNativeTextDocument source = _document();
    final AiNativeTextDocument bounded = AiNativeTextDocument.decode(
      records: source.records,
      limits: PsEngineLimits(maxNodes: source.engine.values.length),
    );
    check(() => bounded.translateFrames(frames: bounded.frames, deltaX: 1, deltaY: 1)).throws<FormatException>();
    final PsEngineDictionary view = source.stories.single.view!;
    final PsEngineDocument future = source.engine.replaceValues(
      replacements: {
        view: PsEngineDictionary(values: {...view.values, 'FutureCache': const PsEngineBoolean(value: true)}),
      },
    );
    final AiNativeTextDocument unknown = AiNativeTextDocument.decode(
      records: source.records.replaceBinary(container: source.container, bytes: future.bytes),
    );
    check(() => unknown.translateFrames(frames: unknown.frames, deltaX: 1, deltaY: 1)).throws<UnsupportedError>();
    check(source.frames.first.matrix).isNull();
  });

  test('retains bounded Art metadata and rejects unowned or partial command lists', () {
    final AiNativeTextDocument source = _document();
    final AiNativeContainer path = source.objects.last.record['ConfiningPath']!.container!;
    final AiNativeArt art = AiNativeArt.decode(records: source.records, record: path);
    check(art.items.whereType<AiNativeContainer>().single.type).equals('ArtDictionary');
    check(art.items.clear).throws<UnsupportedError>();
    check(() => AiNativeArt.decode(records: _document().records, record: path)).throws<ArgumentError>();
    check(() => AiNativeArt.decode(records: source.records, record: source.container)).throws<ArgumentError>();
    final AiNativeTextDocument truncated = _document(areaPath: 'X= 1 2');
    check(() => AiNativeArt.decode(records: truncated.records, record: truncated.objects.last.record['ConfiningPath']!.container!)).throws<FormatException>();
  });
}
