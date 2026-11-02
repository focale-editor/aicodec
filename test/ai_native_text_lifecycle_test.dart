import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Independent empty main namespace with fonts, styles, display order and undo.
AiNativeTextDocument lifecycleDocument({bool named = false, String extra = ''}) {
  /// Selects the native field spelling without deriving from the writer.
  String key(String compact, String full) => named ? full : compact;
  final String encoded = latin1.decode(
    PdfFilters.encodeAscii85(
      bytes: latin1.encode('''
/${key('0', 'DocumentResources')} <<
 /${key('1', 'FontSet')} << /${key('0', 'Resources')} [ << /${key('0', 'Resource')} << /${key('0', 'Identifier')} << /${key('0', 'Name')} (Example-Regular) >> >> >> ] >>
 /${key('5', 'StyleSheetSet')} << /${key('0', 'Resources')} [ << /${key('0', 'Resource')} << /${key('0', 'Name')} (Normal) /${key('6', 'Features')} << /${key('0', 'Font')} 0 >> >> >> ] >>
 /${key('6', 'ParagraphSheetSet')} << /${key('0', 'Resources')} [ << /${key('0', 'Resource')} << /${key('0', 'Name')} (Normal) /${key('5', 'Features')} << >> >> >> ] >>
 /${key('8', 'TextFrameSet')} << /${key('0', 'Resources')} [] /${key('1', 'DisplayList')} [] >>
>>
/${key('1', 'DocumentObjects')} << /${key('0', 'DocumentSettings')} << /${key('1', 'NormalStyleSheet')} 0 /${key('2', 'NormalParagraphSheet')} 0 >> /${key('1', 'TextObjects')} [] >>
'''),
    ),
  );
  final String undo = latin1.decode(PdfFilters.encodeAscii85(bytes: latin1.encode('/0 << /8 << /0 [] >> >> /1 << /1 [] >>')));
  return AiNativeTextDocument.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(
        bytes: latin1.encode('''%!PS-Adobe-3.0
%%BoundingBox: 0 0 100 100
%%BeginSetup
/AI11TextDocument : /ASCII85Decode ,
%$encoded
0 0 /RulerOrigin , ;
/AI11UndoFreeTextDocument : /ASCII85Decode ,
%$undo
;
%%EndSetup
1 1 1 1 0 0 1 0 79 128 255 0 50 0 Lb
(Text) Ln
0 AE
0 A
0 Xw
$extra
LB
%%PageTrailer
%%EOF
'''),
      ),
    ),
  );
}

/// Adds one independently positioned point story using public creation inputs.
AiNativeTextDocument addLifecycleStory(AiNativeTextDocument source, String text, {bool named = false}) => source.createStory(
  text: text,
  frames: [AiNativeTextFrameDefinition.point(x: 10, y: 20, named: named)],
  layer: source.records.program.layers.single,
);

/// Reads frame display indices without relying on the lifecycle editor.
List<int> _display(AiNativeTextDocument document, bool named) {
  final PsEngineDictionary root = document.engine.root as PsEngineDictionary;
  final PsEngineDictionary resources = root[named ? 'DocumentResources' : '0']! as PsEngineDictionary;
  final PsEngineDictionary table = resources[named ? 'TextFrameSet' : '8']! as PsEngineDictionary;
  return [for (final PsEngineValue value in (table[named ? 'DisplayList' : '1']! as PsEngineArray).values) ((value as PsEngineDictionary)[named ? 'Resource' : '0']! as PsEngineNumber).value.toInt()];
}

/// Independent snapshots verify lifecycle, reference compaction and rejection.
void main() {
  for (final bool named in [false, true]) {
    test('creates, duplicates and deletes ${named ? 'CS' : 'CC'} stories', () {
      final AiNativeTextDocument empty = lifecycleDocument(named: named);
      final AiNativeTextDocument first = addLifecycleStory(empty, 'Été 🖋\rSuite', named: named);
      check(first.stories.single.text).equals('Été 🖋\rSuite');
      check(first.stories.single.paragraphRuns.map((run) => run.length)).deepEquals([7, 6]);
      check(first.stories.single.characterRuns.single.length).equals(13);
      check(first.frames.single.position!).deepEquals([10.0, 20.0]);
      check(first.stories.single.strikes).isEmpty();
      final AiNativeTextDocument second = first.duplicateStory(story: first.stories.single);
      check(second.stories.map((story) => story.text)).deepEquals(['Été 🖋\rSuite', 'Été 🖋\rSuite']);
      check(second.objects.map((object) => (object.storyIndex, object.frameIndex))).deepEquals([(0, 0), (1, 0)]);
      check(_display(second, named)).deepEquals([0, 1]);
      final String key = named ? 'UUID' : '97';
      check((second.frames.first.record[key]! as PsEngineString).text() == (second.frames.last.record[key]! as PsEngineString).text()).isFalse();
      final AiNativeTextDocument removed = second.removeStory(story: second.stories.first);
      check(removed.stories.single.frameIndices).deepEquals([0]);
      check(removed.objects.single.storyIndex).equals(0);
      check(_display(removed, named)).deepEquals([0]);
      final AiNativeTextDocument cleared = removed.removeStory(story: removed.stories.single);
      check(cleared.stories).isEmpty();
      check(cleared.frames).isEmpty();
      check(cleared.objects).isEmpty();
      check(cleared.referenceIssues).isEmpty();
      check(cleared.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary())
          .deepEquals(empty.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary());
      check(empty.stories).isEmpty();
    });

    test('inserts, duplicates and removes linked frames with ${named ? 'named' : 'compact'} indices', () {
      final AiNativeTextDocument first = addLifecycleStory(lifecycleDocument(named: named), 'ABC', named: named);
      final AiNativeTextDocument second = addLifecycleStory(first, 'Other', named: named);
      final AiNativeTextDocument linked = second.insertFrame(
        story: second.stories.first,
        index: 0,
        frame: AiNativeTextFrameDefinition.point(x: 70, y: 80, named: named),
      );
      check(linked.stories.first.frameIndices).deepEquals([2, 0]);
      check(linked.objects.map((object) => (object.storyIndex, object.frameIndex))).deepEquals([(0, 1), (0, 0), (1, 0)]);
      final AiNativeTextDocument duplicate = linked.duplicateFrame(frame: linked.frames.last);
      check(duplicate.stories.first.frameIndices).deepEquals([2, 3, 0]);
      final AiNativeTextDocument removed = duplicate.removeFrame(frame: duplicate.frames[2]);
      check(removed.stories.first.frameIndices).deepEquals([2, 0]);
      check(removed.stories.last.frameIndices).deepEquals([1]);
      check(removed.referenceIssues).isEmpty();
      check(_display(removed, named)).deepEquals([0, 1, 2]);
      check(() => removed.removeFrame(frame: removed.frames[1])).throws<ArgumentError>();
      check(() => removed.duplicateStory(story: first.stories.single)).throws<ArgumentError>();
      check(() => removed.duplicateFrame(frame: first.frames.single)).throws<ArgumentError>();
    });

    test('replaces ${named ? 'named' : 'compact'} frame geometry without renumbering owners', () {
      final AiNativeTextDocument first = addLifecycleStory(lifecycleDocument(named: named), 'First', named: named);
      final AiNativeTextDocument source = addLifecycleStory(first, 'Neighbor', named: named);
      final String identityKey = named ? 'UUID' : '97';
      final PsEngineValue identity = source.frames.first.record[identityKey]!;
      final List<int> neighbor = PsEngineCodec.encode(value: source.frames.last.record);
      final AiNativeTextDocument changed = source.replaceFrame(
        frame: source.frames.first,
        definition: AiNativeTextFrameDefinition.point(x: 75, y: -40, named: named),
      );
      check(changed.frames.first.position!).deepEquals([75.0, -40.0]);
      check(PsEngineCodec.encode(value: changed.frames.first.record[identityKey]!)).deepEquals(PsEngineCodec.encode(value: identity));
      check(PsEngineCodec.encode(value: changed.frames.last.record)).deepEquals(neighbor);
      check(changed.stories.map((story) => story.text)).deepEquals(['First', 'Neighbor']);
      check(changed.stories.map((story) => story.frameIndices.single)).deepEquals([0, 1]);
      check(changed.objects.map((object) => (object.storyIndex, object.frameIndex))).deepEquals([(0, 0), (1, 0)]);
      check(_display(changed, named)).deepEquals([0, 1]);
      check(changed.referenceIssues).isEmpty();
      check(
        () => changed.replaceFrame(
          frame: source.frames.first,
          definition: AiNativeTextFrameDefinition.point(x: 0, y: 0, named: named),
        ),
      ).throws<ArgumentError>();
    });
  }

  test('creates and duplicates an area frame with its complete confinement', () {
    final AiNativeTextDocument empty = lifecycleDocument();
    final AiNativeTextFrameDefinition area = AiNativeTextFrameDefinition(
      resource: PsEngineDictionary(
        values: {
          '1': PsEngineDictionary(
            values: {
              '0': PsEngineArray(
                values: [
                  for (final int coordinate in [0, 0, 10, 0, 10, 10, 0, 10]) PsEngineNumber(value: coordinate),
                ],
              ),
            },
          ),
          '2': PsEngineDictionary(values: {'0': PsEngineNumber(value: 1)}),
        },
      ),
      confinement: latin1.encode('X= 0 0 m 10 0 L 10 -10 L 0 -10 L 0 0 L n X+'),
    );
    final AiNativeTextDocument first = empty.createStory(text: 'Area', frames: [area]);
    final AiNativeTextDocument second = first.duplicateFrame(frame: first.frames.single);
    check(second.frames.map((frame) => frame.kind)).deepEquals([AiNativeTextFrameKind.area, AiNativeTextFrameKind.area]);
    check(second.objects.every((object) => object.record['ConfiningPath']?.container?.type == 'Art')).isTrue();
    check(second.removeFrame(frame: second.frames.first).frames.single.kind).equals(AiNativeTextFrameKind.area);
    final AiNativeTextDocument point = second.replaceFrame(frame: second.frames.first, definition: AiNativeTextFrameDefinition.point(x: 50, y: 60));
    check(point.frames.first.kind).equals(AiNativeTextFrameKind.point);
    check(point.objects.first.record['ConfiningPath']).isNull();
    final AiNativeTextDocument restored = point.replaceFrame(frame: point.frames.first, definition: area);
    check(restored.frames.first.kind).equals(AiNativeTextFrameKind.area);
    check(restored.objects.first.record['ConfiningPath']!.container!.type).equals('Art');
    check(
      () => empty.createStory(
        text: 'Invalid',
        frames: [AiNativeTextFrameDefinition(resource: area.resource)],
      ),
    ).throws<FormatException>();
  });

  test('rejects unknown owners, stale references, invalid text and limits atomically', () {
    final AiNativeTextDocument empty = lifecycleDocument();
    check(() => addLifecycleStory(empty, '\n')).throws<ArgumentError>();
    check(() => addLifecycleStory(empty, '\ud800')).throws<ArgumentError>();
    check(() => empty.createStory(text: '', frames: [])).throws<ArgumentError>();
    final AiNativeTextDocument unknown = lifecycleDocument(extra: '/FutureReferences : 0 /Story , ;');
    check(() => addLifecycleStory(unknown, 'Unsafe')).throws<UnsupportedError>();
    final AiNativeTextDocument bounded = AiNativeTextDocument.decode(
      records: empty.records,
      limits: PsEngineLimits(maxNodes: empty.engine.values.length),
    );
    check(() => addLifecycleStory(bounded, 'Too large')).throws<Exception>().has((error) => error.toString(), 'limit failure').contains('limit');
    check(empty.stories).isEmpty();
  });
  test('preserves duplicate frame rotation and antialiasing without copying raw cache identities', () {
    final AiNativeTextDocument first = addLifecycleStory(lifecycleDocument(), 'AB');
    final AiNativeTextObject object = first.objects.single;
    final AiNativeRecords records = AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: first.records.program,
        edits: [
          AiSourceEdit(
            start: object.record.end,
            end: object.record.end,
            bytes: latin1.encode('\n%_/ArtDictionary :\n%_(old-raw) /UnicodeString (AI24 TextStoryRawDataUUID) ,\n%_(0.7) /String (BBAccumRotation) ,\n%_;\n'),
          ),
        ],
      ),
    );
    final AiNativeTextDocument tagged = AiNativeTextDocument.decode(
      records: records.replaceNumbers(entry: records.containers.singleWhere((record) => record.type == 'AI11Text')['TextAntialiasing']!, values: [4]),
    );
    final AiNativeTextDocument cloned = tagged.duplicateStory(story: tagged.stories.single);
    check(cloned.objects.map((object) => object.record['TextAntialiasing']!.number)).deepEquals([4.0, 4.0]);
    check(cloned.records.containers.where((record) => record.type == 'ArtDictionary').map((record) => record['BBAccumRotation']!.text())).deepEquals(['0.7', '0.7']);
    check(cloned.records.containers.where((record) => record['AI24 TextStoryRawDataUUID'] != null)).length.equals(1);
    final AiNativeTextDocument removed = cloned.removeStory(story: cloned.stories.first);
    check(removed.records.containers.where((record) => record['AI24 TextStoryRawDataUUID'] != null)).isEmpty();
    check(removed.records.containers.singleWhere((record) => record.type == 'ArtDictionary')['BBAccumRotation']!.text()).equals('0.7');
  });

  test('rejects missing, duplicate, undo-free and private drawing ownership', () {
    final AiNativeTextDocument source = addLifecycleStory(lifecycleDocument(), 'AB');
    final String original = latin1.decode(source.records.program.bytes);
    final AiNativeContainer object = source.objects.single.record;
    final String record = original.substring(object.start, object.end);
    for (final String unsafe in [
      original.replaceRange(object.start, object.end, ''),
      original.replaceRange(object.end, object.end, '\n$record\n'),
      original.replaceFirst('0 /FreeUndo', '1 /FreeUndo'),
      original.replaceFirst('/AI11Text :', '%_/AI11Text :'),
    ]) {
      final AiNativeTextDocument invalid = AiNativeTextDocument.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(unsafe))),
      );
      expect(() => invalid.removeStory(story: invalid.stories.single), throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())));
    }
    check(source.referenceIssues).isEmpty();
    check(source.stories.single.text).equals('AB');
  });

  test('rejects confinement injection and nonempty auxiliary text runs', () {
    final AiNativeTextDocument empty = lifecycleDocument();
    for (final String confinement in ['X= 0 0 m 1 1 L n X+ ; /ConfiningPath , ; 99 FutureCommand /Art : X= 0 0 m 1 1 L n X+', 'X= 0 0 m 1 1 L f X+']) {
      final AiNativeTextFrameDefinition definition = AiNativeTextFrameDefinition(resource: AiNativeTextFrameDefinition.point(x: 0, y: 0).resource, confinement: latin1.encode(confinement));
      expect(() => empty.createStory(text: 'AB', frames: [definition]), throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())));
    }
    final AiNativeTextDocument source = addLifecycleStory(empty, 'AB');
    final PsEngineDictionary model = source.stories.single.record['0']! as PsEngineDictionary;
    final PsEngineDocument engine = source.engine.replaceValues(
      replacements: {
        model: PsEngineDictionary(
          values: {
            ...model.values,
            'HyperlinkRun': PsEngineDictionary(
              values: {
                '0': PsEngineArray(
                  values: [
                    PsEngineDictionary(
                      values: {
                        '0': PsEngineDictionary(values: {'Target': PsEngineString.fromText(text: 'Other story')}),
                        '1': PsEngineNumber(value: 3),
                      },
                    ),
                  ],
                ),
              },
            ),
          },
        ),
      },
    );
    final AiNativeTextDocument linked = AiNativeTextDocument.decode(
      records: source.records.replaceBinary(container: source.container, bytes: engine.bytes),
    );
    check(() => linked.duplicateStory(story: linked.stories.single)).throws<UnsupportedError>();
  });

  test('retains qualified Document metadata and rejects external reference owners', () {
    final AiNativeTextDocument empty = lifecycleDocument();
    final String program = latin1.decode(empty.records.program.bytes);
    for (final bool safe in [true, false]) {
      final String document = safe ? '/Document : /Dictionary : ; /Recorded , ;' : '/Document : /Dictionary : /Array : 1 /Int , ; (Constraint Data) , ; /Recorded , ;';
      final AiNativeTextDocument source = AiNativeTextDocument.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(program.replaceFirst('%%EndSetup', '$document\n%%EndSetup')))),
      );
      if (safe) {
        final AiNativeTextDocument changed = addLifecycleStory(source, 'AB');
        check(latin1.decode(changed.records.program.bytes)).contains(document);
      } else {
        check(() => addLifecycleStory(source, 'AB')).throws<UnsupportedError>();
      }
    }
    for (final String unknown in ['0 FutureStoryIndex\n%%EndSetup', '%%EndSetup\n%AI3_Note: (story link)']) {
      final AiNativeTextDocument source = AiNativeTextDocument.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(program.replaceFirst('%%EndSetup', unknown)))),
      );
      check(() => addLifecycleStory(source, 'AB')).throws<UnsupportedError>();
    }
  });
}
