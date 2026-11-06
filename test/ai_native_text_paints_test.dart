import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:pscore/pscore.dart' show PsWriteException;
import 'package:test/test.dart';

/// Writes a fixture paint independently of the production color serializer.
String textPaint({bool named = false, int type = 1, String values = '1 .2 .3 .4', String extra = ''}) =>
    '<< /${named ? 'StreamTag' : '99'} /SimplePaint /${named ? 'Color' : '0'} << /${named ? 'Type' : '0'} $type /${named ? 'Values' : '1'} [ $values ] >> $extra >>';

/// Retains two stories, one inherited paint, local extensions and an undo snapshot.
AiNativeTextDocument textPaintDocument({bool named = false, String? paint, String local = '', PsEngineLimits limits = const PsEngineLimits()}) {
  /// Keeps named and compact fixture spellings independent of the kit writer.
  String key(String compact, String name) => named ? name : compact;
  final String content = latin1.decode(PsEngineCodec.encode(value: PsEngineString.fromText(text: 'A🖋B\r')));
  final String story =
      '''<< /${key('0', 'Model')} << /${key('0', 'Text')} $content
/${key('6', 'StyleRun')} << /${key('0', 'RunArray')} [ << /${key('1', 'Length')} 5 /${key('0', 'RunData')} <<
/${key('0', 'StyleSheet')} << /${key('5', 'Parent')} 0 /${key('97', 'UUID')} (source-style)
/${key('6', 'Features')} << /Future (retained) $local >> >> >> >> ] >> >>
/${key('1', 'View')} << /${key('0', 'Frames')} [ ] /${key('1', 'RenderedData')} << /Keep (cached) >>
/${key('2', 'Strikes')} [ ] >> >>''';
  final List<int> engine = latin1.encode('''/${key('0', 'DocumentResources')} <<
/${key('5', 'StyleSheetSet')} << /${key('0', 'Resources')} [ << /${key('0', 'Resource')} <<
/${key('0', 'Name')} (Normal) /${key('6', 'Features')} << /${key('53', 'FillColor')} ${paint ?? textPaint(named: named)}
/${key('56', 'FillFlag')} true /${key('63', 'LineWidth')} 2 >> >> >> ] >> >>
/${key('1', 'DocumentObjects')} << /${key('0', 'DocumentSettings')} << /${key('1', 'NormalStyleSheet')} 0 >>
/${key('1', 'TextObjects')} [ $story $story ] >>''');
  final String encoded = latin1.decode(PdfFilters.encodeAscii85(bytes: engine));
  return AiNativeTextDocument.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(
        bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%BoundingBox: 0 0 100 100
/AI11TextDocument : /ASCII85Decode ,
%$encoded
0 0 /RulerOrigin , ;
/AI11UndoFreeTextDocument : /ASCII85Decode ,
%$encoded
;
%%EndSetup
0 0 m 10 10 L S
%%Trailer
%%EOF
'''),
      ),
    ),
    limits: limits,
  );
}

/// Returns one exact engine-owned value for byte preservation assertions.
List<int> textPaintBytes(AiNativeTextDocument document, PsEngineValue value) => document.engine.bytes.sublist(value.start!, value.end);

/// Supplies explicit process colors and all supported text stroke settings.
AiNativeCharacterChanges textPaintChanges() => AiNativeCharacterChanges(
  fillColor: AiNativeTextProcessColor(space: .cmyk, components: [0.1, 0.2, 0.3, 0.4]),
  strokeColor: AiNativeTextProcessColor(space: .rgb, components: [0.7, 0.6, 0.5]),
  backgroundColor: AiNativeTextProcessColor(space: .gray, components: [0.9]),
  fillEnabled: false,
  strokeEnabled: true,
  fillFirst: false,
  fillOverprint: true,
  strokeOverprint: true,
  lineCap: 1,
  lineJoin: 2,
  lineWidth: 3,
  miterLimit: 8,
  dashOffset: -2,
  dashArray: [3, 0, 1],
  fillVisible: false,
  strokeVisible: true,
  backgroundEnabled: true,
);

/// Applies a complete explicit paint change to the surrogate-pair selection.
AiNativeTextDocument editTextPaint(AiNativeTextDocument source) => source.setCharacterFeatures(
  story: source.stories.first,
  start: 1,
  end: 3,
  changes: textPaintChanges(),
);

/// Verifies native text paints without composing text, glyphs or compatibility art.
void main() {
  for (final bool named in [false, true]) {
    test('edits ${named ? 'named' : 'compact'} paints and strokes without flattening inheritance', () {
      final AiNativeTextDocument source = textPaintDocument(named: named);
      final AiNativeTextDocument changed = editTextPaint(source);
      final AiNativeTextStory story = changed.stories.first;
      final AiNativeCharacterStyle style = changed.characterStyleAt(story: story, offset: 1);
      check(style.fillPaint!.color!.space).equals(AiNativeTextColorSpace.cmyk);
      check(style.fillPaint!.color!.components).deepEquals([0.1, 0.2, 0.3, 0.4]);
      check(style.strokePaint!.color!.components).deepEquals([0.7, 0.6, 0.5]);
      check(style.backgroundPaint!.color!.components).deepEquals([0.9]);
      check([style.fillEnabled, style.strokeEnabled, style.fillFirst, style.fillOverprint, style.strokeOverprint, style.fillVisible, style.strokeVisible, style.backgroundEnabled])
          .deepEquals([false, true, false, true, true, false, true, true]);
      check([style.lineCap, style.lineJoin, style.lineWidth, style.miterLimit, style.dashOffset]).deepEquals([1, 2, 3, 8, -2]);
      check(style.dashArray!).deepEquals([3, 0, 1]);
      check(style.dashArray!.clear).throws<UnsupportedError>();
      check(style.fillPaint!.color!.components.clear).throws<UnsupportedError>();
      check(story.characterRuns.map((run) => run.length)).deepEquals([1, 2, 2]);
      for (final int offset in [0, 3]) {
        final AiNativeCharacterStyle retained = changed.characterStyleAt(story: story, offset: offset);
        check(retained.fillPaint!.color!.components).deepEquals([0.2, 0.3, 0.4]);
        check(retained.strokeEnabled).isNull();
        check(retained.lineWidth).equals(2);
      }
      check(style.value(compactKey: 'Future', namedKey: 'Future') is PsEngineString).isTrue();
      check(textPaintBytes(changed, changed.characterStyles.single.record)).deepEquals(textPaintBytes(source, source.characterStyles.single.record));
      check(textPaintBytes(changed, changed.stories.last.record)).deepEquals(textPaintBytes(source, source.stories.last.record));
      check(changed.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary())
          .deepEquals(source.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary());
      final PsEngineDictionary view = story.record[named ? 'View' : '1']! as PsEngineDictionary;
      check(view.values.keys).deepEquals([if (named) 'Frames' else '0']);
      check(style.fillPaint!.record.values.keys).deepEquals([if (named) 'StreamTag' else '99', if (named) 'Color' else '0']);
      check(story.characterRuns[1].overrides![named ? 'UUID' : '97']).not((it) => it.identicalTo(source.stories.first.characterRuns.single.overrides![named ? 'UUID' : '97']));
    });

    test('inherits ${named ? 'named' : 'compact'} paints independently of visibility and enablement', () {
      final AiNativeTextDocument source = editTextPaint(textPaintDocument(named: named));
      final AiNativeTextDocument changed = source.setCharacterFeatures(
        story: source.stories.first,
        start: 1,
        end: 3,
        changes: AiNativeCharacterChanges(inherit: {.fillColor, .strokeColor, .backgroundColor, .dashArray, .lineWidth}),
      );
      final AiNativeCharacterStyle style = changed.characterStyleAt(story: changed.stories.first, offset: 1);
      check(style.fillPaint!.color!.space).equals(AiNativeTextColorSpace.rgb);
      check(style.fillPaint!.color!.components).deepEquals([0.2, 0.3, 0.4]);
      check(style.strokePaint).isNull();
      check(style.backgroundPaint).isNull();
      check(style.dashArray).isNull();
      check(style.lineWidth).equals(2);
      check(style.fillEnabled).equals(false);
      check(style.fillVisible).equals(false);
      check(style.strokeEnabled).equals(true);
    });
  }

  test('reads all process tuples and preserves unsupported paint payloads', () {
    for (final (int, String, AiNativeTextColorSpace) color in [(0, '1 .5', .gray), (1, '1 .1 .2 .3', .rgb), (2, '1 .1 .2 .3 .4', .cmyk), (3, '1 50 -128 127', .lab)]) {
      final AiNativeTextDocument source = textPaintDocument(
        paint: textPaint(type: color.$1, values: color.$2),
      );
      check(source.characterStyleAt(story: source.stories.first, offset: 0).fillPaint!.color!.space).equals(color.$3);
    }
    for (final String paint in [textPaint(extra: '/Future (kept)'), textPaint(type: 19), textPaint(values: '0 .1 .2 .3'), textPaint().replaceFirst('/SimplePaint', '/PatternPaint')]) {
      final AiNativeTextDocument source = textPaintDocument(paint: paint);
      final AiNativeTextPaint retained = source.characterStyleAt(story: source.stories.first, offset: 0).fillPaint!;
      check(retained.color).isNull();
      check(() => editTextPaint(source)).throws<UnsupportedError>();
      check(
        () => source.setCharacterFeatures(
          story: source.stories.first,
          start: 1,
          end: 3,
          changes: AiNativeCharacterChanges(inherit: {.fillColor}),
        ),
      ).throws<UnsupportedError>();
      check(latin1.decode(PsEngineCodec.encode(value: retained.record))).contains('<<');
    }
  });

  test('writes explicit gray RGB CMYK and Lab tuples without changing paint enablement', () {
    final AiNativeTextDocument source = textPaintDocument();
    for (final AiNativeTextProcessColor color in [
      AiNativeTextProcessColor(space: .gray, components: [0.4]),
      AiNativeTextProcessColor(space: .rgb, components: [0.1, 0.2, 0.3]),
      AiNativeTextProcessColor(space: .cmyk, components: [0.1, 0.2, 0.3, 0.4]),
      AiNativeTextProcessColor(space: .lab, components: [50, -128, 127]),
    ]) {
      final AiNativeTextDocument changed = source.setCharacterFeatures(
        story: source.stories.first,
        start: 1,
        end: 3,
        changes: AiNativeCharacterChanges(fillColor: color, dashArray: []),
      );
      final AiNativeCharacterStyle style = changed.characterStyleAt(story: changed.stories.first, offset: 1);
      check(style.fillPaint!.color!.space).equals(color.space);
      check(style.fillPaint!.color!.components).deepEquals(color.components);
      check(style.fillEnabled).equals(true);
      check(style.fillVisible).isNull();
      check(style.dashArray!).isEmpty();
    }
  });

  test('rejects malformed known color tuples and ambiguous aliases', () {
    for (final String paint in [textPaint(values: '1 .2 .3'), textPaint(values: '1 .2 .3 2'), textPaint(type: 3, values: '1 101 0 0'), textPaint().replaceFirst('/0 1', '/0 1 /Type 1')]) {
      final AiNativeTextDocument source = textPaintDocument(paint: paint);
      check(() => source.characterStyleAt(story: source.stories.first, offset: 0).fillPaint!.color).throws<FormatException>();
      check(() => editTextPaint(source)).throws<FormatException>();
    }
  });

  test('preserves exact aliases and caches for equal local paint and dash assignments', () {
    final AiNativeTextDocument source = textPaintDocument(local: '/FillColor ${textPaint(named: true)} /LineDashArray [3.000 1e0]');
    final AiNativeTextDocument equal = source.setCharacterFeatures(
      story: source.stories.first,
      start: 0,
      end: 5,
      changes: AiNativeCharacterChanges(
        fillColor: AiNativeTextProcessColor(space: .rgb, components: [0.2, 0.3, 0.4]),
        dashArray: [3, 1],
      ),
    );
    check(equal).identicalTo(source);
    final AiNativeTextDocument changed = editTextPaint(source);
    final AiNativeTextPaint paint = changed.characterStyleAt(story: changed.stories.first, offset: 1).fillPaint!;
    check(paint.record.values.keys).deepEquals(['StreamTag', 'Color']);
    check((paint.record['Color']! as PsEngineDictionary).values.keys).deepEquals(['Type', 'Values']);
  });

  test('validates portable stroke inputs and freezes caller-owned component and dash lists', () {
    for (final Object Function() create in [
      () => AiNativeTextProcessColor(space: .rgb, components: [0, 1]),
      () => AiNativeTextProcessColor(space: .gray, components: [double.nan]),
      () => AiNativeTextProcessColor(space: .lab, components: [50, 128, 0]),
      () => AiNativeCharacterChanges(lineWidth: -1),
      () => AiNativeCharacterChanges(lineCap: 3),
      () => AiNativeCharacterChanges(lineJoin: -1),
      () => AiNativeCharacterChanges(miterLimit: 0.5),
      () => AiNativeCharacterChanges(dashOffset: 9007199254740992),
      () => AiNativeCharacterChanges(dashArray: [0, 0]),
      () => AiNativeCharacterChanges(dashArray: [1, -1]),
      () => AiNativeCharacterChanges(dashArray: [double.infinity]),
      () => AiNativeCharacterChanges(
        fillColor: AiNativeTextProcessColor(space: .gray, components: [0]),
        inherit: {.fillColor},
      ),
    ]) {
      check(create).throws<ArgumentError>();
    }
    final List<double> components = [0.1, 0.2, 0.3];
    final List<double> dashes = [2, 1];
    final AiNativeCharacterChanges changes = AiNativeCharacterChanges(
      fillColor: AiNativeTextProcessColor(space: .rgb, components: components),
      dashArray: dashes,
    );
    components.clear();
    dashes.clear();
    final AiNativeTextDocument source = textPaintDocument();
    final AiNativeTextDocument changed = source.setCharacterFeatures(story: source.stories.first, start: 1, end: 3, changes: changes);
    final AiNativeCharacterStyle style = changed.characterStyleAt(story: changed.stories.first, offset: 1);
    check(style.fillPaint!.color!.components).deepEquals([0.1, 0.2, 0.3]);
    check(style.dashArray!).deepEquals([2, 1]);
  });

  test('rejects split surrogate selections stale stories and bounded output growth atomically', () {
    final AiNativeTextDocument source = textPaintDocument();
    final AiNativeCharacterChanges changes = AiNativeCharacterChanges(lineWidth: 3);
    check(() => source.setCharacterFeatures(story: source.stories.first, start: 1, end: 2, changes: changes)).throws<ArgumentError>();
    final AiNativeTextDocument foreign = textPaintDocument();
    check(() => source.setCharacterFeatures(story: foreign.stories.first, start: 1, end: 3, changes: changes)).throws<ArgumentError>();
    final AiNativeTextDocument bounded = AiNativeTextDocument.decode(
      records: source.records,
      limits: PsEngineLimits(maxBytes: source.engine.bytes.length),
    );
    check(() => editTextPaint(bounded)).throws<PsWriteException>();
    check(source.stories.first.characterRuns).length.equals(1);
  });
}
