import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Encodes a complete synthetic ATE document with one styled UTF-16 story.
List<int> _engine({String text = 'Été 🖋\r', List<int>? lengths, int frame = 0}) {
  final PsEngineDictionary root = PsEngineDictionary(
    values: {
      '0': PsEngineDictionary(
        values: {
          '1': PsEngineDictionary(
            values: {
              '0': PsEngineArray(
                values: [
                  PsEngineDictionary(
                    values: {
                      '0': PsEngineDictionary(
                        values: {
                          '0': PsEngineDictionary(values: {'0': PsEngineString.fromText(text: 'Example-Regular')}),
                        },
                      ),
                    },
                  ),
                ],
              ),
            },
          ),
          for (final String key in ['5', '6'])
            key: PsEngineDictionary(
              values: {
                '0': PsEngineArray(
                  values: [
                    PsEngineDictionary(
                      values: {
                        '0': PsEngineDictionary(
                          values: {
                            '0': PsEngineString.fromText(text: 'Original'),
                            '97': PsEngineString(bytes: latin1.encode('identifier')),
                            key == '5' ? '6' : '5': PsEngineDictionary(values: {}),
                          },
                        ),
                      },
                    ),
                  ],
                ),
              },
            ),
          '8': PsEngineDictionary(
            values: {
              '0': PsEngineArray(
                values: [
                  PsEngineDictionary(
                    values: {
                      '0': PsEngineDictionary(values: {'97': PsEngineString(bytes: latin1.encode('frame'))}),
                    },
                  ),
                ],
              ),
            },
          ),
        },
      ),
      '1': PsEngineDictionary(
        values: {
          '1': PsEngineArray(
            values: [
              PsEngineDictionary(
                values: {
                  '0': PsEngineDictionary(
                    values: {
                      '0': PsEngineString.fromText(text: text),
                      for (final String key in ['5', '6'])
                        key: PsEngineDictionary(
                          values: {
                            '0': PsEngineArray(
                              values: [
                                for (final int length in lengths ?? [text.length])
                                  PsEngineDictionary(
                                    values: {
                                      '0': PsEngineDictionary(values: {'0': PsEngineNumber(value: 0)}),
                                      '1': PsEngineNumber(value: length),
                                    },
                                  ),
                              ],
                            ),
                          },
                        ),
                    },
                  ),
                  '1': PsEngineDictionary(
                    values: {
                      '0': PsEngineArray(
                        values: [
                          PsEngineDictionary(values: {'0': PsEngineNumber(value: frame)}),
                        ],
                      ),
                      '2': PsEngineArray(values: [const PsEngineToken(value: 'futureLayout')]),
                    },
                  ),
                },
              ),
            ],
          ),
        },
      ),
      'Future': const PsEngineToken(value: 'preserve'),
    },
  );
  return PsEngineCodec.encode(value: root, bareDictionary: true);
}

/// Wraps binary text plus unrelated native records in a source snapshot.
AiNativeRecords _records(List<int> bytes) {
  final String encoded = latin1.decode(PdfFilters.encodeAscii85(bytes: bytes));
  return AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%EndSetup
/AI11TextDocument : /ASCII85Decode ,
%$encoded
10 20 /RulerOrigin , ;
/AI11UndoFreeTextDocument : /ASCII85Decode ,
%z~>
;
/AI11Text : 0 /FreeUndo , 0 /StoryIndex , 0 /FrameIndex , ;
%%Trailer
%%EOF
'''),
    ),
  );
}

/// Checks native text decoding, source-preserving edits and dependency failures.
void main() {
  test('splices UTF-16 content and styles while invalidating only the selected layout', () {
    final AiNativeTextDocument document = _editDocument(text: 'AB\rCD\r', lengths: [3, 3]);
    final AiNativeTextDocument edited = document.replaceText(story: document.stories.single, start: 1, end: 4, text: '🖋\rZ');
    final AiNativeTextStory story = edited.stories.single;
    check(story.modelText).equals('A🖋\rZD\r');
    check(story.characterRuns.map((run) => run.length)).deepEquals([5, 2]);
    check(story.paragraphRuns.map((run) => run.length)).deepEquals([4, 3]);
    check(story.paragraphRuns.map((run) => (run.record['Marker']! as PsEngineNumber).value)).deepEquals([0, 0]);
    check(story.strikes).isEmpty();
    check(story.frameIndices).deepEquals([0]);
    check(document.stories.single.modelText).equals('AB\rCD\r');
    check(document.records.containers.firstWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary()).deepEquals(
      edited.records.containers.firstWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary(),
    );
    check((edited.engine.root as PsEngineDictionary)['Future']! is PsEngineToken).isTrue();
    check(() => edited.replaceText(story: document.stories.single, start: 0, end: 1, text: 'X')).throws<ArgumentError>();
  });

  test('preserves character ownership at every edit boundary', () {
    final AiNativeTextDocument document = _editDocument(text: 'abcde\r', lengths: [2, 2, 2]);
    final List<int> source = [0, 0, 1, 1, 2, 2];
    for (int start = 0; start <= 5; start++) {
      for (int end = start; end <= 5; end++) {
        for (final String inserted in ['', 'X', '🖋', '\r\r']) {
          final AiNativeTextDocument edited = document.replaceText(story: document.stories.single, start: start, end: end, text: inserted);
          final AiNativeTextStory story = edited.stories.single;
          check(story.modelText).equals('abcde\r'.replaceRange(start, end, inserted));
          check([
            for (final AiNativeTextRun run in story.characterRuns) ...List.filled(run.length, (run.record['Marker']! as PsEngineNumber).value),
          ]).deepEquals([...source.take(start), ...List.filled(inserted.length, source[start]), ...source.skip(end)]);
          check(story.paragraphRuns.fold(0, (length, run) => length + run.length)).equals(story.modelText.length);
        }
      }
    }
  });

  test('rejects invalid boundaries, malformed UTF-16 and implicit newline conversion', () {
    final AiNativeTextDocument document = _editDocument(text: 'A🖋B\r', lengths: [5]);
    for (final (int start, int end, String text) in [(-1, 0, ''), (0, 5, ''), (3, 2, ''), (2, 2, 'x'), (0, 2, ''), (0, 0, '\n'), (0, 0, '\ud800'), (0, 0, '\udc00')]) {
      check(() => document.replaceText(story: document.stories.single, start: start, end: end, text: text)).throws<ArgumentError>();
    }
    check(identical(document, document.replaceText(story: document.stories.single, start: 1, end: 3, text: '🖋'))).isTrue();
    final AiNativeTextDocument emptied = document.replaceText(story: document.stories.single, start: 0, end: 4, text: '');
    check(emptied.stories.single.modelText).equals('\r');
    check(emptied.stories.single.characterRuns.single.length).equals(1);
  });

  test('refuses unknown model offsets and active auxiliary features atomically', () {
    for (final Map<String, PsEngineValue> extra in [
      {'FutureOffsets': PsEngineArray(values: [])},
      {
        'KernRun': PsEngineDictionary(
          values: {
            'RunArray': PsEngineArray(
              values: [
                PsEngineDictionary(
                  values: {
                    'RunData': PsEngineDictionary(values: {'Amount': PsEngineNumber(value: 50)}),
                    'Length': PsEngineNumber(value: 4),
                  },
                ),
              ],
            ),
          },
        ),
      },
    ]) {
      final AiNativeTextDocument document = _editDocument(text: 'ABC\r', lengths: [4], extra: extra);
      check(() => document.replaceText(story: document.stories.single, start: 0, end: 1, text: 'X')).throws<UnsupportedError>();
      check(document.stories.single.text).equals('ABC');
    }
  });

  test('bounds replacement strings and paragraph expansion before retaining all output', () {
    final AiNativeTextDocument source = _editDocument(text: 'ABC\r', lengths: [4]);
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: source.records, limits: const PsEngineLimits(maxNodes: 150, maxStringBytes: 1024));
    check(() => document.replaceText(story: document.stories.single, start: 0, end: 0, text: 'X' * 512)).throws<FormatException>();
    check(() => document.replaceText(story: document.stories.single, start: 0, end: 0, text: '\r' * 100)).throws<FormatException>();
  });

  for (final bool named in [false, true]) {
    test('appends and assigns a ${named ? 'named' : 'compact'} font without changing existing resources', () {
      final AiNativeTextDocument source = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final List<int> axes = [400 * 65536, -12 * 65536];
      final AiNativeFontDefinition definition = AiNativeFontDefinition(postScriptName: 'ExampleVariable_400wght', technology: .trueType, version: 'Version 2.000', axisCoordinates: axes);
      axes[0] = 0;
      final AiNativeTextDocument added = source.addFont(font: definition);
      check(added.fonts.length).equals(source.fonts.length + 1);
      final AiNativeTextFont font = added.fonts.last;
      check(font.postScriptName).equals('ExampleVariable_400wght');
      check(font.technology).equals(AiNativeFontTechnology.trueType);
      check(font.version).equals('Version 2.000');
      check(font.axisCoordinates).deepEquals([400 * 65536, -12 * 65536]);
      check(font.axisCoordinates.clear).throws<UnsupportedError>();
      check(definition.axisCoordinates.clear).throws<UnsupportedError>();
      check(PsEngineCodec.encode(value: added.fonts.first.record)).deepEquals(PsEngineCodec.encode(value: source.fonts.first.record));
      final PsEngineValue oldObjects = (source.engine.root as PsEngineDictionary)[named ? 'DocumentObjects' : '1']!;
      final PsEngineValue newObjects = (added.engine.root as PsEngineDictionary)[named ? 'DocumentObjects' : '1']!;
      check(source.engine.bytes.sublist(oldObjects.start!, oldObjects.end)).deepEquals(added.engine.bytes.sublist(newObjects.start!, newObjects.end));
      final AiNativeTextDocument assigned = added.setCharacterFeatures(
        story: added.stories.single,
        start: 0,
        end: 1,
        changes: AiNativeCharacterChanges(font: font),
      );
      check(assigned.characterStyleAt(story: assigned.stories.single, offset: 0).font!.postScriptName).equals(font.postScriptName);
      check(assigned.characterStyleAt(story: assigned.stories.single, offset: 1).font!.index).equals(0);
      check(assigned.stories.single.strikes).isEmpty();
      check(assigned.referenceIssues).isEmpty();
      check(
        () => source.setCharacterFeatures(
          story: source.stories.single,
          start: 0,
          end: 1,
          changes: AiNativeCharacterChanges(font: font),
        ),
      ).throws<ArgumentError>();
      final AiNativeTextDocument duplicate = added.addFont(font: definition);
      check(duplicate.fonts.length).equals(3);
      check((duplicate.fonts.last.record[named ? 'UUID' : '97']! as PsEngineString).text()).not((it) => it.equals((font.record[named ? 'UUID' : '97']! as PsEngineString).text()));
    });

    test('retains ${named ? 'named' : 'compact'} forced-break spans during paragraph edits', () {
      final AiNativeTextDocument source = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final AiNativeTextDocument edited = source.replaceText(story: source.stories.single, start: 0, end: 2, text: 'A\u0003B\rC\u0003D');
      check(edited.stories.single.modelText).equals('A\u0003B\rC\u0003D\r');
      check(edited.stories.single.paragraphRuns.map((run) => run.length)).deepEquals([2, 2, 2, 2]);
      final AiNativeTextDocument formatted = edited.setParagraphFeatures(
        story: edited.stories.single,
        start: 2,
        end: 4,
        changes: AiNativeParagraphChanges(justification: 1),
      );
      check(formatted.stories.single.paragraphRuns.map((run) => run.length)).deepEquals([2, 2, 2, 2]);
      check([
        for (final int offset in [0, 2, 4, 6]) formatted.paragraphStyleAt(story: formatted.stories.single, offset: offset).justification,
      ]).deepEquals([1, 1, 2, 2]);
      final AiNativeTextDocument caret = formatted.setParagraphFeatures(
        story: formatted.stories.single,
        start: 4,
        end: 4,
        changes: AiNativeParagraphChanges(justification: 0),
      );
      check([
        for (final int offset in [0, 2, 4, 6]) caret.paragraphStyleAt(story: caret.stories.single, offset: offset).justification,
      ]).deepEquals([1, 1, 0, 0]);
      check(caret.referenceIssues).isEmpty();
      check(caret.stories.single.strikes).isEmpty();
      check(
        identical(caret, caret.setParagraphFeatures(story: caret.stories.single, start: 2, end: 3, changes: AiNativeParagraphChanges(justification: 1))),
      ).isTrue();
    });

    test('materializes ${named ? 'named' : 'compact'} inherited spans for consecutive forced breaks', () {
      final AiNativeTextDocument original = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final PsEngineDictionary model = original.stories.single.record[named ? 'Model' : '0']! as PsEngineDictionary;
      final PsEngineDocument inherited = original.engine.replaceValues(
        replacements: {
          model: PsEngineDictionary(values: {...model.values}..remove(named ? 'ParagraphRun' : '5')),
        },
      );
      final AiNativeTextDocument source = AiNativeTextDocument.decode(records: _records(inherited.bytes));
      final AiNativeTextDocument edited = source.replaceText(story: source.stories.single, start: 0, end: 2, text: 'A\u0003\u0003B');
      check(edited.stories.single.modelText).equals('A\u0003\u0003B\r');
      check(edited.stories.single.paragraphRuns.map((run) => run.length)).deepEquals([2, 1, 2]);
      check(edited.stories.single.paragraphRuns.map((run) => run.styleIndex)).deepEquals([0, 0, 0]);
      check(edited.referenceIssues).isEmpty();
    });

    test('writes ${named ? 'named CS' : 'compact CC'} composed lines without altering the source model', () {
      final AiNativeTextDocument initial = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final AiNativeTextDocument document = initial.replaceText(story: initial.stories.single, start: 0, end: 2, text: 'A🖋\rB\u0003C');
      final AiNativeTextStory story = document.stories.single;
      final AiNativeTextFrameLayout frame = AiNativeTextFrameLayout(
        frame: document.frames.single,
        x: 100,
        y: 200,
        lines: [
          AiNativeTextLineLayout(
            x: 5,
            ascent: 10,
            descent: 3,
            bounds: [0, -10, 50, 3],
            segments: [AiNativeTextSegmentLayout(start: 0, end: 1), AiNativeTextSegmentLayout(start: 1, end: 4, x: 8)],
          ),
          AiNativeTextLineLayout(y: 20, segments: [AiNativeTextSegmentLayout(start: 4, end: 6)]),
          AiNativeTextLineLayout(y: 40, segments: [AiNativeTextSegmentLayout(start: 6, end: 8)]),
        ],
      );
      final AiNativeTextDocument composed = document.withTextLayout(story: story, frames: [frame]);
      final List<AiNativeTextStrike> nodes = composed.stories.single.strikes.single.descendants.toList();
      check(nodes.where((node) => node.kind == .segment).map((node) => node.firstCharacterIndex)).deepEquals([0, 1, 4, 6]);
      check(nodes.where((node) => node.kind == .segment).map((node) => node.characterCount)).deepEquals([1, 3, 2, 2]);
      check(nodes.where((node) => node.kind == .glyphs)).isEmpty();
      final AiNativeTextStrike line = nodes.firstWhere((node) => node.kind == .line);
      check(line.origin!).deepEquals([5.0, 0.0]);
      check(line.bounds!).deepEquals([0.0, -10.0, 50.0, 3.0]);
      check(line.selectionAscent).equals(-10);
      check(line.selectionDescent).equals(3);
      check(nodes.firstWhere((node) => node.kind == .frame).origin!).deepEquals([100.0, 200.0]);
      final PsEngineValue oldModel = story.record[named ? 'Model' : '0']!;
      final PsEngineValue newModel = composed.stories.single.record[named ? 'Model' : '0']!;
      check(document.engine.bytes.sublist(oldModel.start!, oldModel.end)).deepEquals(composed.engine.bytes.sublist(newModel.start!, newModel.end));
      check(composed.referenceIssues).isEmpty();
      check(frame.lines.clear).throws<UnsupportedError>();
      check(frame.lines.first.segments.clear).throws<UnsupportedError>();
      check(frame.lines.first.bounds!.clear).throws<UnsupportedError>();
      check(() => composed.withTextLayout(story: composed.stories.single, frames: [frame])).throws<ArgumentError>();
    });

    test('edits ${named ? 'named' : 'compact'} character features without flattening inherited styles', () {
      final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final AiNativeCharacterChanges changes = AiNativeCharacterChanges(fontSize: 22, tracking: 50, ligatures: false, stylisticSets: 5, leading: 26, font: document.fonts.single);
      final AiNativeTextDocument edited = document.setCharacterFeatures(story: document.stories.single, start: 1, end: 2, changes: changes);
      final AiNativeTextStory story = edited.stories.single;
      check(story.characterRuns.map((run) => run.length)).deepEquals([1, 1, 1]);
      check(edited.characterStyleAt(story: story, offset: 0).fontSize).equals(18);
      check(edited.characterStyleAt(story: story, offset: 2).fontSize).equals(18);
      final AiNativeCharacterStyle middle = edited.characterStyleAt(story: story, offset: 1);
      check(middle.fontSize).equals(22);
      check(middle.number(compactKey: '89', namedKey: 'RefFontSize')).equals(22);
      check(middle.tracking).equals(50);
      check(middle.openTypeFeatures['liga']).equals(0);
      check(middle.openTypeFeatures['ss01']).equals(1);
      check(middle.openTypeFeatures['ss03']).equals(1);
      check(middle.boolean(compactKey: '4', namedKey: 'AutoLeading')).equals(false);
      check(middle.number(compactKey: '5', namedKey: 'Leading')).equals(26);
      check(story.strikes).isEmpty();
      final AiNativeTextDocument repeated = edited.setCharacterFeatures(story: story, start: 1, end: 2, changes: AiNativeCharacterChanges(fontSize: 22, tracking: 50));
      check(identical(repeated, edited)).isTrue();
      final AiNativeTextDocument inherited = edited.setCharacterFeatures(
        story: story,
        start: 1,
        end: 2,
        changes: AiNativeCharacterChanges(inherit: {.fontSize, .tracking, .ligatures, .stylisticSets}),
      );
      final AiNativeCharacterStyle restored = inherited.characterStyleAt(story: inherited.stories.single, offset: 1);
      check(restored.fontSize).equals(18);
      check(restored.tracking).isNull();
      check(restored.openTypeFeatures['liga']).equals(1);
      check(restored.openTypeFeatures['ss01']).equals(0);
      check(restored.openTypeFeatures['ss03']).equals(1);
      check(restored.number(compactKey: '5', namedKey: 'Leading')).equals(26);
      check(inherited.referenceIssues).isEmpty();
      final PsEngineDictionary root = document.engine.root as PsEngineDictionary;
      final PsEngineDictionary newRoot = inherited.engine.root as PsEngineDictionary;
      final PsEngineValue resources = root[named ? 'DocumentResources' : '0']!;
      final PsEngineValue retained = newRoot[named ? 'DocumentResources' : '0']!;
      check(document.engine.bytes.sublist(resources.start!, resources.end)).deepEquals(inherited.engine.bytes.sublist(retained.start!, retained.end));
      check(() => inherited.setCharacterFeatures(story: inherited.stories.single, start: 0, end: 1, changes: changes)).throws<ArgumentError>();
    });

    test('edits ${named ? 'named' : 'compact'} paragraph features with independent direction and composer', () {
      final AiNativeTextDocument initial = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final AiNativeTextDocument document = initial.replaceText(story: initial.stories.single, start: 1, end: 1, text: '\rC');
      final AiNativeTextDocument edited = document.setParagraphFeatures(
        story: document.stories.single,
        start: 1,
        end: 2,
        changes: AiNativeParagraphChanges(justification: 1, firstLineIndent: -6, spaceAfter: 10, direction: 1, composer: 0),
      );
      final AiNativeTextStory story = edited.stories.single;
      check(story.paragraphRuns.map((run) => run.length)).deepEquals([2, 3]);
      final AiNativeParagraphStyle paragraph = edited.paragraphStyleAt(story: story, offset: 0);
      check(paragraph.justification).equals(1);
      check(paragraph.direction).equals(1);
      check(paragraph.number(compactKey: '35', namedKey: 'ComposerEngine')).equals(0);
      check(paragraph.number(compactKey: '1', namedKey: 'FirstLineIndent')).equals(-6);
      check(paragraph.number(compactKey: '5', namedKey: 'SpaceAfter')).equals(10);
      check(edited.paragraphStyleAt(story: story, offset: 2).justification).equals(2);
      check(edited.characterStyleAt(story: story, offset: 0).fontSize).equals(18);
      final AiNativeTextDocument caret = edited.setParagraphFeatures(story: story, start: 2, end: 2, changes: AiNativeParagraphChanges(justification: 0));
      check(caret.paragraphStyleAt(story: caret.stories.single, offset: 2).justification).equals(0);
      final AiNativeTextDocument inherited = caret.setParagraphFeatures(
        story: caret.stories.single,
        start: 0,
        end: 5,
        changes: AiNativeParagraphChanges(inherit: {.justification}),
      );
      check(inherited.paragraphStyleAt(story: inherited.stories.single, offset: 0).justification).equals(2);
      check(inherited.paragraphStyleAt(story: inherited.stories.single, offset: 2).justification).equals(2);
      check(inherited.paragraphStyleAt(story: inherited.stories.single, offset: 0).direction).equals(1);
    });

    test('edits ${named ? 'named' : 'compact'} inherited text and creates separate normal paragraphs', () {
      final AiNativeTextDocument original = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final PsEngineDictionary model = original.stories.single.record[named ? 'Model' : '0']! as PsEngineDictionary;
      final PsEngineDocument noParagraphs = original.engine.replaceValues(
        replacements: {
          model: PsEngineDictionary(values: {...model.values}..remove(named ? 'ParagraphRun' : '5')),
        },
      );
      final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(noParagraphs.bytes));
      final AiNativeTextDocument edited = document.replaceText(story: document.stories.single, start: 1, end: 1, text: '\r🖋');
      final AiNativeTextStory story = edited.stories.single;
      check(story.modelText).equals('A\r🖋B\r');
      check(story.paragraphRuns.map((run) => run.length)).deepEquals([2, 4]);
      check(story.paragraphRuns.map((run) => run.styleIndex)).deepEquals([0, 0]);
      check(story.characterRuns).isEmpty();
      check(story.strikes).isEmpty();
      check(edited.characterStyleAt(story: story, offset: 2).fontSize).equals(18);
      check(edited.referenceIssues).isEmpty();
    });

    test('resolves ${named ? 'named CS' : 'compact CC'} styles and missing character runs', () {
      final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final AiNativeTextStory story = document.stories.single;
      check(story.characterRuns).isEmpty();
      final AiNativeCharacterStyle style = document.characterStyleAt(story: story, offset: 1);
      check(style.font!.postScriptName).equals('Example-Regular');
      check(style.fontSize).equals(18);
      check(style.horizontalScale).equals(1);
      check(style.number(compactKey: named ? 'HorizontalScale' : '6', namedKey: named ? 'HorizontalScale' : '6')).equals(1);
      check(style.openTypeFeatures['liga']).equals(1);
      check(style.openTypeFeatures['ss03']).equals(1);
      check(style.openTypeFeatures['ss01']).equals(0);
      check(document.paragraphStyleAt(story: story, offset: 0).justification).equals(2);
      check(document.styledRanges(story: story).map((range) => (range.start, range.end))).deepEquals([(0, 3)]);
      check(document.referenceIssues).isEmpty();
      final AiNativeTextDocument renamed = document.renameStyle(style: document.characterStyles.first, name: 'Renamed');
      check(renamed.characterStyles.first.name).equals('Renamed');
      check(() => renamed.characterStyleAt(story: story, offset: 0)).throws<ArgumentError>();
      check(() => document.characterStyleAt(story: story, offset: 3)).throws<RangeError>();
      check(style.layers.clear).throws<UnsupportedError>();
    });

    test('reads ${named ? 'named' : 'compact'} cached layout without losing source indices', () {
      final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(_styleEngine(named: named)));
      final List<AiNativeTextStrike> nodes = document.stories.single.strikes.single.descendants.toList();
      check(nodes.map((node) => node.kind)).deepEquals([AiNativeTextStrikeKind.frame, AiNativeTextStrikeKind.segment, AiNativeTextStrikeKind.glyphs, AiNativeTextStrikeKind.unknown]);
      check(nodes.first.frameIndex).equals(0);
      check(nodes.first.origin!).deepEquals([10.0, 20.0]);
      check(nodes[1].firstCharacterIndex).equals(0);
      check(nodes[1].characterCount).equals(3);
      check(nodes[2].glyphIds).deepEquals([41, 42, 1]);
      check(nodes[2].visualBounds!).deepEquals([10.0, 15.0, 30.0, 22.0]);
      check(nodes[2].shadowStyles).isNotNull();
      check(nodes[3].tag).equals('FutureStrike');
      check(document.frames.single.kind).equals(AiNativeTextFrameKind.area);
      check(document.frames.single.matrix!).deepEquals([1.0, 0.0, 0.0, 1.0, 5.0, 6.0]);
      check(nodes.first.children.clear).throws<UnsupportedError>();
    });
  }

  test('requires explicit overflow and keeps visual segment order independent of UTF-16 order', () {
    final AiNativeTextDocument document = _editDocument(text: 'אבA\r', lengths: [4]);
    final AiNativeTextFrameLayout frame = AiNativeTextFrameLayout(
      frame: document.frames.single,
      x: 0,
      y: 0,
      lines: [
        AiNativeTextLineLayout(segments: [AiNativeTextSegmentLayout(start: 2, end: 4), AiNativeTextSegmentLayout(start: 0, end: 2, x: 20, rightToLeft: true)]),
      ],
    );
    final AiNativeTextDocument composed = document.withTextLayout(story: document.stories.single, frames: [frame]);
    final List<AiNativeTextStrike> segments = composed.stories.single.strikes.single.descendants.where((node) => node.kind == .segment).toList();
    check(segments.map((segment) => segment.firstCharacterIndex)).deepEquals([2, 0]);
    check(segments.map((segment) => segment.wordReorderValid)).deepEquals([false, true]);
    final PsEngineDictionary mapping = segments.last.record['15']! as PsEngineDictionary;
    check(((mapping['7']! as PsEngineDictionary)['0']! as PsEngineNumber).value).equals(2);
    final AiNativeTextFrameLayout clipped = AiNativeTextFrameLayout(
      frame: document.frames.single,
      x: 0,
      y: 0,
      lines: [
        AiNativeTextLineLayout(segments: [AiNativeTextSegmentLayout(start: 0, end: 2, rightToLeft: true)]),
      ],
    );
    check(() => document.withTextLayout(story: document.stories.single, frames: [clipped])).throws<ArgumentError>();
    final AiNativeTextDocument overflow = document.withTextLayout(story: document.stories.single, frames: [clipped], overflowStart: 2);
    check(overflow.stories.single.modelText).equals('אבA\r');
    final AiNativeTextDocument hidden = document.withTextLayout(
      story: document.stories.single,
      frames: [AiNativeTextFrameLayout(frame: document.frames.single, x: 0, y: 0, lines: [])],
      overflowStart: 0,
    );
    check(hidden.stories.single.strikes.single.descendants.where((node) => node.kind == .segment)).isEmpty();
  });

  test('inherits forced-break span styles through insertion and deletion', () {
    final AiNativeTextDocument source = _editDocument(text: 'A\u0003B\rC\r', lengths: [2, 2, 2]);
    final AiNativeTextDocument joined = source.replaceText(story: source.stories.single, start: 1, end: 2, text: '');
    check(joined.stories.single.modelText).equals('AB\rC\r');
    check(joined.stories.single.paragraphRuns.map((run) => run.length)).deepEquals([3, 2]);
    check(joined.stories.single.paragraphRuns.map((run) => (run.record['Marker']! as PsEngineNumber).value)).deepEquals([0, 2]);
    final AiNativeTextDocument inserted = source.replaceText(story: source.stories.single, start: 2, end: 2, text: 'X\u0003');
    check(inserted.stories.single.modelText).equals('A\u0003X\u0003B\rC\r');
    check(inserted.stories.single.paragraphRuns.map((run) => run.length)).deepEquals([2, 2, 2, 2]);
    check(inserted.stories.single.paragraphRuns.map((run) => (run.record['Marker']! as PsEngineNumber).value)).deepEquals([0, 1, 1, 2]);
  });

  test('appends font display references and preserves unknown font-set metadata', () {
    final AiNativeTextDocument original = AiNativeTextDocument.decode(records: _records(_styleEngine(named: false)));
    final PsEngineDictionary resources = (original.engine.root as PsEngineDictionary)['0']! as PsEngineDictionary;
    final PsEngineDictionary fonts = resources['1']! as PsEngineDictionary;
    final PsEngineDocument engine = original.engine.replaceValues(
      replacements: {
        fonts: PsEngineDictionary(
          values: {
            ...fonts.values,
            'Future': const PsEngineBoolean(value: true),
            '1': PsEngineArray(
              values: [
                PsEngineDictionary(
                  values: {
                    '0': PsEngineNumber(value: 0),
                    'Label': PsEngineString.fromText(text: 'Original'),
                  },
                ),
              ],
            ),
          },
        ),
      },
    );
    final AiNativeTextDocument source = AiNativeTextDocument.decode(records: _records(engine.bytes));
    final AiNativeTextDocument added = source.addFont(
      font: AiNativeFontDefinition(postScriptName: 'Other-Regular', technology: .postScript),
    );
    final PsEngineDictionary table = ((added.engine.root as PsEngineDictionary)['0']! as PsEngineDictionary)['1']! as PsEngineDictionary;
    final List<PsEngineValue> display = (table['1']! as PsEngineArray).values;
    check(display.map((value) => ((value as PsEngineDictionary)['0']! as PsEngineNumber).value)).deepEquals([0, 1]);
    check(((display.first as PsEngineDictionary)['Label']! as PsEngineString).text()).equals('Original');
    check((table['Future']! as PsEngineBoolean).value).isTrue();
    check(added.fonts.last.technology).equals(AiNativeFontTechnology.postScript);
    check(added.fonts.last.axisCoordinates).isEmpty();
    check(added.fonts.last.version).isNull();
    final PsEngineDocument missing = original.engine.replaceValues(
      replacements: {
        resources: PsEngineDictionary(values: {...resources.values}..remove('1')),
      },
    );
    final AiNativeTextDocument noFonts = AiNativeTextDocument.decode(records: _records(missing.bytes));
    final AiNativeTextDocument created = noFonts.addFont(
      font: AiNativeFontDefinition(postScriptName: 'Example-Regular', technology: .postScript),
    );
    check(created.fonts.single.index).equals(0);
    check(created.referenceIssues).isEmpty();
  });

  test('rejects malformed or oversized font definitions and bad display references', () {
    for (final String name in ['', 'Two Words', '/Name', 'Name\u0000', 'Name🖋', 'Name[Axis]']) {
      check(() => AiNativeFontDefinition(postScriptName: name, technology: .postScript)).throws<ArgumentError>();
    }
    for (final int coordinate in [-0x80000001, 0x80000000]) {
      check(() => AiNativeFontDefinition(postScriptName: 'Example', technology: .trueType, axisCoordinates: [coordinate])).throws<ArgumentError>();
    }
    check(() => AiNativeFontDefinition(postScriptName: 'Example', technology: .postScript, version: 'bad\rversion')).throws<ArgumentError>();
    final AiNativeTextDocument source = AiNativeTextDocument.decode(records: _records(_styleEngine(named: false)), limits: const PsEngineLimits(maxStringBytes: 64, maxNodes: 1000));
    check(
      () => source.addFont(
        font: AiNativeFontDefinition(postScriptName: 'X' * 40, technology: .trueType),
      ),
    ).throws<FormatException>();
    check(
      () => source.addFont(
        font: AiNativeFontDefinition(postScriptName: 'Example', technology: .trueType, axisCoordinates: List.filled(1000, 0)),
      ),
    ).throws<FormatException>();
    final PsEngineDictionary fonts = ((source.engine.root as PsEngineDictionary)['0']! as PsEngineDictionary)['1']! as PsEngineDictionary;
    final PsEngineDocument invalid = source.engine.replaceValues(
      replacements: {
        fonts: PsEngineDictionary(
          values: {
            ...fonts.values,
            '1': PsEngineArray(
              values: [
                PsEngineDictionary(values: {'0': PsEngineNumber(value: 1)}),
              ],
            ),
          },
        ),
      },
    );
    final AiNativeTextDocument malformed = AiNativeTextDocument.decode(records: _records(invalid.bytes));
    check(
      () => malformed.addFont(
        font: AiNativeFontDefinition(postScriptName: 'Example', technology: .postScript),
      ),
    ).throws<FormatException>();
  });

  test('retains generated hyphens without inserting them in editable text', () {
    final AiNativeTextDocument document = _editDocument(text: 'hyphen\r', lengths: [7]);
    final AiNativeTextDocument composed = document.withTextLayout(
      story: document.stories.single,
      frames: [
        AiNativeTextFrameLayout(
          frame: document.frames.single,
          x: 0,
          y: 0,
          lines: [
            AiNativeTextLineLayout(segments: [AiNativeTextSegmentLayout(start: 0, end: 2, automaticHyphen: true)]),
            AiNativeTextLineLayout(y: 15, segments: [AiNativeTextSegmentLayout(start: 2, end: 7)]),
          ],
        ),
      ],
    );
    final List<AiNativeTextStrike> segments = composed.stories.single.strikes.single.descendants.where((node) => node.kind == .segment).toList();
    check(segments.map((segment) => segment.hasTerminalHyphenInsertion)).deepEquals([true, false]);
    check(composed.stories.single.modelText).equals('hyphen\r');
    final PsEngineDictionary mapping = segments.first.record['15']! as PsEngineDictionary;
    check((mapping['2']! as PsEngineNumber).value).equals(1);
    final PsEngineDictionary insertion = (mapping['1']! as PsEngineArray).values.single as PsEngineDictionary;
    check(insertion.values.values.map((value) => (value as PsEngineNumber).value)).deepEquals([2, 1, 2]);
  });

  test('preserves linked frame order and rejects missing or reordered resources', () {
    final AiNativeTextDocument initial = _editDocument(text: 'ABCD\r', lengths: [5]);
    final PsEngineDictionary root = initial.engine.root as PsEngineDictionary;
    final PsEngineDictionary resources = root['0']! as PsEngineDictionary;
    final PsEngineArray frames = (resources['8']! as PsEngineDictionary)['0']! as PsEngineArray;
    final PsEngineArray references = initial.stories.single.view!['0']! as PsEngineArray;
    final PsEngineDocument expanded = initial.engine.replaceValues(
      replacements: {
        frames: PsEngineArray(
          values: [
            ...frames.values,
            PsEngineDictionary(values: {'0': PsEngineDictionary(values: {})}),
          ],
        ),
        references: PsEngineArray(
          values: [
            ...references.values,
            PsEngineDictionary(values: {'0': PsEngineNumber(value: 1)}),
          ],
        ),
      },
    );
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(expanded.bytes));
    final List<AiNativeTextFrameLayout> layout = [
      AiNativeTextFrameLayout(
        frame: document.frames[0],
        x: 100,
        y: 200,
        lines: [
          AiNativeTextLineLayout(segments: [AiNativeTextSegmentLayout(start: 0, end: 2)]),
        ],
      ),
      AiNativeTextFrameLayout(
        frame: document.frames[1],
        x: 300,
        y: 400,
        lines: [
          AiNativeTextLineLayout(segments: [AiNativeTextSegmentLayout(start: 2, end: 5)]),
        ],
      ),
    ];
    final AiNativeTextDocument composed = document.withTextLayout(story: document.stories.single, frames: layout);
    check(composed.stories.single.strikes.single.descendants.where((node) => node.kind == .frame).map((node) => node.frameIndex)).deepEquals([0, 1]);
    check(() => document.withTextLayout(story: document.stories.single, frames: layout.reversed.toList())).throws<ArgumentError>();
    check(() => document.withTextLayout(story: document.stories.single, frames: layout.take(1).toList())).throws<ArgumentError>();
  });

  test('rejects unmapped path geometry and named CS word-reorder output', () {
    final AiNativeTextDocument named = AiNativeTextDocument.decode(records: _records(_styleEngine(named: true)));
    check(
      () => named.withTextLayout(
        story: named.stories.single,
        frames: [
          AiNativeTextFrameLayout(
            frame: named.frames.single,
            x: 0,
            y: 0,
            lines: [
              AiNativeTextLineLayout(segments: [AiNativeTextSegmentLayout(start: 0, end: 3, rightToLeft: true)]),
            ],
          ),
        ],
      ),
    ).throws<UnsupportedError>();
    final AiNativeTextDocument initial = _editDocument(text: 'AB\r', lengths: [3]);
    final PsEngineDictionary frame = initial.frames.single.record;
    final PsEngineDocument changed = initial.engine.replaceValues(
      replacements: {
        frame: PsEngineDictionary(
          values: {
            ...frame.values,
            '2': PsEngineDictionary(values: {'0': PsEngineNumber(value: 2)}),
          },
        ),
      },
    );
    final AiNativeTextDocument path = AiNativeTextDocument.decode(records: _records(changed.bytes));
    check(
      () => path.withTextLayout(
        story: path.stories.single,
        frames: [AiNativeTextFrameLayout(frame: path.frames.single, x: 0, y: 0, lines: [])],
        overflowStart: 0,
      ),
    ).throws<UnsupportedError>();
  });

  test('rejects invalid composition coverage, surrogate boundaries, breaks and limits', () {
    final AiNativeTextDocument document = _editDocument(text: 'A🖋\rB\r', lengths: [6]);
    for (final List<(int, int)> ranges in [
      [(1, 6)],
      [(0, 4), (3, 6)],
      [(0, 2), (2, 6)],
      [(0, 7)],
      [(0, 6)],
    ]) {
      final AiNativeTextFrameLayout frame = AiNativeTextFrameLayout(
        frame: document.frames.single,
        x: 0,
        y: 0,
        lines: [
          AiNativeTextLineLayout(
            segments: [for (final (int start, int end) in ranges) AiNativeTextSegmentLayout(start: start, end: end)],
          ),
        ],
      );
      check(() => document.withTextLayout(story: document.stories.single, frames: [frame])).throws<ArgumentError>();
    }
    for (final Object Function() create in [
      () => AiNativeTextSegmentLayout(start: 1, end: 1),
      () => AiNativeTextSegmentLayout(start: 0, end: 1, x: double.nan),
      () => AiNativeTextLineLayout(segments: []),
      () => AiNativeTextLineLayout(ascent: -1, segments: [AiNativeTextSegmentLayout(start: 0, end: 1)]),
      () => AiNativeTextLineLayout(bounds: [2, 0, 1, 0], segments: [AiNativeTextSegmentLayout(start: 0, end: 1)]),
    ]) {
      check(create).throws<ArgumentError>();
    }
    final AiNativeTextDocument source = _editDocument(text: 'abcdefghi\r', lengths: [10]);
    final AiNativeTextDocument bounded = AiNativeTextDocument.decode(records: source.records, limits: const PsEngineLimits(maxNodes: 150));
    check(
      () => bounded.withTextLayout(
        story: bounded.stories.single,
        frames: [
          AiNativeTextFrameLayout(
            frame: bounded.frames.single,
            x: 0,
            y: 0,
            lines: [
              AiNativeTextLineLayout(
                segments: [for (int index = 0; index < 10; index++) AiNativeTextSegmentLayout(start: index, end: index + 1)],
              ),
            ],
          ),
        ],
      ),
    ).throws<FormatException>();
  });

  test('refuses invalid feature values and font-metric-dependent size edits', () {
    for (final Object Function() create in [
      () => AiNativeCharacterChanges(fontSize: 0),
      () => AiNativeCharacterChanges(fontSize: double.nan),
      () => AiNativeCharacterChanges(horizontalScale: -1),
      () => AiNativeCharacterChanges(tracking: double.infinity),
      () => AiNativeCharacterChanges(kerning: 4),
      () => AiNativeCharacterChanges(stylisticSets: 1 << 20),
      () => AiNativeCharacterChanges(fontSize: 12, inherit: {.fontSize}),
      () => AiNativeCharacterChanges(leading: 12, inherit: {.automaticLeading}),
      () => AiNativeParagraphChanges(justification: 7),
      () => AiNativeParagraphChanges(direction: 2),
      () => AiNativeParagraphChanges(composer: 2),
      () => AiNativeParagraphChanges(spaceAfter: -1),
      () => AiNativeParagraphChanges(justification: 1, inherit: {.justification}),
    ]) {
      check(create).throws<ArgumentError>();
    }
    final AiNativeTextDocument initial = AiNativeTextDocument.decode(records: _records(_styleEngine(named: false)));
    final AiNativeTextDocument sized = initial.setCharacterFeatures(story: initial.stories.single, start: 0, end: 3, changes: AiNativeCharacterChanges(fontSize: 20));
    final PsEngineDictionary local = sized.stories.single.characterRuns.single.overrides!['6']! as PsEngineDictionary;
    final PsEngineDocument changed = sized.engine.replaceValues(
      replacements: {
        local: PsEngineDictionary(
          values: {
            ...local.values,
            '90': PsEngineNumber(value: 1),
            'Future': const PsEngineToken(value: 'keep'),
          },
        ),
      },
    );
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(changed.bytes));
    check(() => document.setCharacterFeatures(story: document.stories.single, start: 0, end: 1, changes: AiNativeCharacterChanges(fontSize: 30))).throws<UnsupportedError>();
    final AiNativeTextDocument inherited = document.setCharacterFeatures(
      story: document.stories.single,
      start: 0,
      end: 3,
      changes: AiNativeCharacterChanges(inherit: {.fontSize}),
    );
    check(inherited.characterStyleAt(story: inherited.stories.single, offset: 0).fontSize).equals(18);
    check(inherited.characterStyleAt(story: inherited.stories.single, offset: 0).value(compactKey: 'Future', namedKey: 'Future')! is PsEngineToken).isTrue();
    check(() => inherited.setCharacterFeatures(story: document.stories.single, start: 0, end: 1, changes: AiNativeCharacterChanges(tracking: 20))).throws<ArgumentError>();
  });

  test('assigns a fresh identity to modified inline styles while retaining source identities', () {
    final AiNativeTextDocument initial = AiNativeTextDocument.decode(records: _records(_styleEngine(named: false)));
    final AiNativeTextDocument sized = initial.setCharacterFeatures(story: initial.stories.single, start: 0, end: 3, changes: AiNativeCharacterChanges(fontSize: 20));
    final PsEngineDictionary local = sized.stories.single.characterRuns.single.overrides!;
    const String identifier = '01234567-89ab-4def-8123-456789abcdef';
    final PsEngineDocument authored = sized.engine.replaceValues(
      replacements: {
        local: PsEngineDictionary(
          values: {
            ...local.values,
            '97': PsEngineString.fromText(text: identifier),
          },
        ),
      },
    );
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(authored.bytes));
    final AiNativeTextDocument edited = document.setCharacterFeatures(story: document.stories.single, start: 1, end: 2, changes: AiNativeCharacterChanges(tracking: 40));
    final List<String> ids = [for (final AiNativeTextRun run in edited.stories.single.characterRuns) (run.overrides!['97']! as PsEngineString).text()];
    check(ids.first).equals(identifier);
    check(ids.last).equals(identifier);
    check(ids[1] == identifier).isFalse();
    check(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(ids[1])).isTrue();
    final AiNativeTextDocument repeated = edited.setCharacterFeatures(story: edited.stories.single, start: 1, end: 2, changes: AiNativeCharacterChanges(tracking: 40));
    check(identical(edited, repeated)).isTrue();
  });

  test('retains run metadata and unselected character features at every boundary', () {
    final AiNativeTextDocument document = _editDocument(text: 'abcde\r', lengths: [2, 2, 2]);
    for (int start = 0; start < 6; start++) {
      for (int end = start; end <= 6; end++) {
        final AiNativeTextDocument edited = document.setCharacterFeatures(story: document.stories.single, start: start, end: end, changes: AiNativeCharacterChanges(fontSize: 20, leading: 0));
        final AiNativeTextStory story = edited.stories.single;
        check(story.modelText).equals('abcde\r');
        check([
          for (final AiNativeTextRun run in story.characterRuns) ...List.filled(run.length, (run.record['Marker']! as PsEngineNumber).value),
        ]).deepEquals([0, 0, 1, 1, 2, 2]);
        for (int position = 0; position < 6; position++) {
          final AiNativeCharacterStyle style = edited.characterStyleAt(story: story, offset: position);
          check(style.fontSize).equals(position >= start && position < end ? 20 : null);
          check(style.leading).equals(position >= start && position < end ? 0 : null);
        }
      }
    }
    final AiNativeTextDocument unicode = _editDocument(text: 'A🖋\r', lengths: [4]);
    check(() => unicode.setCharacterFeatures(story: unicode.stories.single, start: 2, end: 3, changes: AiNativeCharacterChanges(tracking: 1))).throws<ArgumentError>();
    check(() => unicode.setParagraphFeatures(story: unicode.stories.single, start: 0, end: 2, changes: AiNativeParagraphChanges(direction: 1))).throws<ArgumentError>();
  });

  test('splits effective ranges at both tables and resolves explicit parent chains', () {
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(_styleEngine(named: false)));
    final PsEngineDictionary root = document.engine.root as PsEngineDictionary;
    final PsEngineDictionary objects = root['1']! as PsEngineDictionary;
    final PsEngineDictionary story = (objects['1']! as PsEngineArray).values.single as PsEngineDictionary;
    final PsEngineDictionary model = story['0']! as PsEngineDictionary;
    final PsEngineDictionary characterTable = PsEngineDictionary(
      values: {
        '0': PsEngineArray(
          values: [
            PsEngineDictionary(
              values: {
                '0': PsEngineDictionary(values: {'0': PsEngineNumber(value: 0)}),
                '1': PsEngineNumber(value: 1),
              },
            ),
            PsEngineDictionary(
              values: {
                '0': PsEngineDictionary(values: {'0': PsEngineNumber(value: 1)}),
                '1': PsEngineNumber(value: 3),
              },
            ),
          ],
        ),
      },
    );
    final PsEngineDictionary paragraphs = model['5']! as PsEngineDictionary;
    final PsEngineDictionary run = (paragraphs['0']! as PsEngineArray).values.single as PsEngineDictionary;
    final PsEngineDocument changed = document.engine.replaceValues(
      replacements: {
        model: PsEngineDictionary(
          values: {
            ...model.values,
            '0': PsEngineString.fromText(text: 'A\rB\r'),
            '6': characterTable,
            '5': PsEngineDictionary(
              values: {
                '0': PsEngineArray(
                  values: [
                    PsEngineDictionary(values: {...run.values, '1': PsEngineNumber(value: 2)}),
                    PsEngineDictionary(values: {...run.values, '1': PsEngineNumber(value: 2)}),
                  ],
                ),
              },
            ),
          },
        ),
      },
    );
    final AiNativeTextDocument result = AiNativeTextDocument.decode(records: _records(changed.bytes));
    final List<AiNativeStyledTextRange> ranges = result.styledRanges(story: result.stories.single);
    check(ranges.map((range) => (range.start, range.end))).deepEquals([(0, 1), (1, 2), (2, 4)]);
    check(ranges.map((range) => range.characterStyle.fontSize)).deepEquals([18.0, 24.0, 24.0]);
    check(ranges.last.characterStyle.font!.postScriptName).equals('Example-Regular');
    check(ranges.last.characterStyle.tracking).equals(20);
  });

  test('rejects ambiguous keys, broken references and cyclic style inheritance', () {
    final String source = latin1.decode(_styleEngine(named: false));
    check(() => AiNativeTextDocument.decode(records: _records(latin1.encode(source.replaceFirst('/0 << /1', '/DocumentResources << >> /0 << /1'))))).throws<FormatException>();
    final AiNativeTextDocument cyclic = AiNativeTextDocument.decode(records: _records(latin1.encode(source.replaceFirst('/0 (Normal)', '/5 1 /0 (Normal)'))));
    check(() => cyclic.characterStyleAt(story: cyclic.stories.single, offset: 0)).throws<FormatException>();
    check(cyclic.referenceIssues).isNotEmpty();
    final AiNativeTextDocument missingFont = AiNativeTextDocument.decode(records: _records(latin1.encode(source.replaceFirst('/0 0 /1 12', '/0 99 /1 12'))));
    check(() => missingFont.characterStyleAt(story: missingFont.stories.single, offset: 0).font).throws<FormatException>();
    check(missingFont.referenceIssues).isNotEmpty();
    final AiNativeTextDocument ambiguousFont = AiNativeTextDocument.decode(records: _records(latin1.encode(source.replaceFirst('/0 0 /1 12', '/Font 0 /0 0 /1 12'))));
    check(() => ambiguousFont.characterStyleAt(story: ambiguousFont.stories.single, offset: 0).font).throws<FormatException>();
    final AiNativeTextDocument badMatrix = AiNativeTextDocument.decode(records: _records(latin1.encode(source.replaceFirst('[1 0 0 1 5 6]', '[1 0]'))));
    check(() => badMatrix.frames.single.matrix).throws<FormatException>();
  });

  test('bounds style inheritance independently of dictionary nesting', () {
    final PsEngineDocument source = PsEngineDocument.decode(bytes: _styleEngine(named: false));
    final PsEngineDictionary root = source.root as PsEngineDictionary;
    final PsEngineDictionary resources = root['0']! as PsEngineDictionary;
    final PsEngineDictionary table = resources['5']! as PsEngineDictionary;
    final PsEngineArray styles = table['0']! as PsEngineArray;
    final PsEngineDictionary objects = root['1']! as PsEngineDictionary;
    final PsEngineDictionary story = (objects['1']! as PsEngineArray).values.single as PsEngineDictionary;
    final PsEngineDictionary model = story['0']! as PsEngineDictionary;
    final PsEngineDocument edited = source.replaceValues(
      replacements: {
        styles: PsEngineArray(
          values: [
            styles.values.first,
            for (int index = 1; index <= 20; index++)
              PsEngineDictionary(
                values: {
                  '0': PsEngineDictionary(values: {'5': PsEngineNumber(value: index - 1)}),
                },
              ),
          ],
        ),
        model: PsEngineDictionary(
          values: {
            ...model.values,
            '6': PsEngineDictionary(
              values: {
                '0': PsEngineArray(
                  values: [
                    PsEngineDictionary(
                      values: {
                        '0': PsEngineDictionary(values: {'0': PsEngineNumber(value: 20)}),
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
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(edited.bytes), limits: const PsEngineLimits(maxDepth: 16));
    check(() => document.characterStyleAt(story: document.stories.single, offset: 0)).throws<FormatException>();
    check(document.referenceIssues).isNotEmpty();
  });

  test('retains parent paragraph character defaults under partial local overrides', () {
    final PsEngineDocument source = PsEngineDocument.decode(bytes: _styleEngine(named: false));
    final PsEngineDictionary root = source.root as PsEngineDictionary;
    final PsEngineDictionary objects = root['1']! as PsEngineDictionary;
    final PsEngineDictionary story = (objects['1']! as PsEngineArray).values.single as PsEngineDictionary;
    final PsEngineDictionary model = story['0']! as PsEngineDictionary;
    final PsEngineDictionary table = model['5']! as PsEngineDictionary;
    final PsEngineDictionary run = (table['0']! as PsEngineArray).values.single as PsEngineDictionary;
    final PsEngineDictionary data = run['0']! as PsEngineDictionary;
    final PsEngineDocument edited = source.replaceValues(
      replacements: {
        data['0']!: PsEngineDictionary(
          values: {
            '6': PsEngineNumber(value: 0),
            '5': PsEngineDictionary(
              values: {
                '32': PsEngineDictionary(values: {'8': PsEngineNumber(value: 7)}),
              },
            ),
          },
        ),
      },
    );
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(edited.bytes));
    final AiNativeCharacterStyle style = document.characterStyleAt(story: document.stories.single, offset: 0);
    check(style.fontSize).equals(18);
    check(style.tracking).equals(7);
    check(style.font!.postScriptName).equals('Example-Regular');
    check(document.paragraphStyleAt(story: document.stories.single, offset: 0).defaultCharacterLayers.length).equals(2);
  });

  test('models UTF-16 story runs, resources, frames and drawing references', () {
    final AiNativeTextDocument document = AiNativeTextDocument.decode(records: _records(_engine()));
    final AiNativeTextStory story = document.stories.single;
    check(story.text).equals('Été 🖋');
    check(story.modelText.length).equals(7);
    check(story.characterRuns.single.end).equals(7);
    check(story.characterRuns.single.styleIndex).equals(0);
    check(story.paragraphRuns.single.length).equals(7);
    check(document.fonts.single.postScriptName).equals('Example-Regular');
    check(story.frameIndices).deepEquals([0]);
    check(document.objects.single.storyIndex).equals(0);
    check(document.referenceIssues).isEmpty();
    check(document.stories.clear).throws<UnsupportedError>();
  });

  test('renames only the selected style while preserving text, layout and other records', () {
    final AiNativeTextDocument original = AiNativeTextDocument.decode(records: _records(_engine()));
    final AiNativeTextDocument changed = original.renameStyle(style: original.characterStyles.single, name: 'Titre 🖋');
    check(changed.characterStyles.single.name).equals('Titre 🖋');
    check(changed.paragraphStyles.single.name).equals('Original');
    check(original.characterStyles.single.name).equals('Original');
    check(changed.engine.bytes).deepEquals(original.engine.replaceValues(replacements: {original.characterStyles.single.record['0']!: PsEngineString.fromText(text: 'Titre 🖋')}).bytes);
    check(changed.stories.single.modelText).equals(original.stories.single.modelText);
    check(changed.referenceIssues).isEmpty();
    check(changed.container['RulerOrigin']!.numbers!).deepEquals([10.0, 20.0]);
    final String before = latin1.decode(original.records.program.bytes);
    final String after = latin1.decode(changed.records.program.bytes);
    check(after.substring(after.indexOf('/AI11UndoFreeTextDocument'))).equals(before.substring(before.indexOf('/AI11UndoFreeTextDocument')));
    check(() => changed.renameStyle(style: original.characterStyles.single, name: 'stale')).throws<ArgumentError>();
    check(() => changed.records.replaceBinary(container: original.container, bytes: [])).throws<ArgumentError>();
  });

  test('rejects invalid run coverage, missing paragraph marks and split surrogate pairs', () {
    for (final List<int> bytes in [
      _engine(lengths: []),
      _engine(lengths: [6]),
      _engine(lengths: [0, 7]),
      _engine(lengths: [5, 2]),
      _engine(text: 'missing mark'),
    ]) {
      check(() => AiNativeTextDocument.decode(records: _records(bytes))).throws<FormatException>();
    }
    final AiNativeTextDocument unresolved = AiNativeTextDocument.decode(records: _records(_engine(frame: 5)));
    check(unresolved.referenceIssues).deepEquals(['Story 0 references missing frame 5.']);
    check(() => AiNativeTextDocument.decode(records: _records(_engine()), limits: const PsEngineLimits(maxBytes: 100))).throws<FormatException>();
  });

  test('replaces empty and arbitrary binary bodies without splitting their terminator', () {
    final AiNativeRecords original = _records(_engine());
    final AiNativeContainer record = original.containers.firstWhere((record) => record.type == 'AI11TextDocument');
    for (final int length in [0, 1, 2, 3, 4, 63, 64, 65, 256]) {
      final List<int> bytes = List.generate(length, (index) => index % 256);
      final AiNativeRecords edited = original.replaceBinary(container: record, bytes: bytes);
      check(edited.containers.firstWhere((record) => record.type == 'AI11TextDocument').decodeBinary()).deepEquals(bytes);
    }
  });
}

/// Builds distinct source run markers to check edits without mirroring the splice.
AiNativeTextDocument _editDocument({required String text, required List<int> lengths, Map<String, PsEngineValue> extra = const {}}) {
  final PsEngineDocument engine = PsEngineDocument.decode(
    bytes: _engine(text: text, lengths: lengths),
  );
  final PsEngineDictionary root = engine.root as PsEngineDictionary;
  final PsEngineDictionary objects = root['1']! as PsEngineDictionary;
  final PsEngineDictionary story = (objects['1']! as PsEngineArray).values.single as PsEngineDictionary;
  final PsEngineDictionary model = story['0']! as PsEngineDictionary;
  final Map<String, PsEngineValue> changed = {...model.values, ...extra};
  for (final String key in ['5', '6']) {
    final PsEngineDictionary table = model[key]! as PsEngineDictionary;
    final List<PsEngineValue> runs = (table['0']! as PsEngineArray).values;
    changed[key] = PsEngineDictionary(
      values: {
        '0': PsEngineArray(
          values: [
            for (int index = 0; index < runs.length; index++)
              PsEngineDictionary(
                values: {
                  ...(runs[index] as PsEngineDictionary).values,
                  'Marker': PsEngineNumber(value: index),
                },
              ),
          ],
        ),
      },
    );
  }
  return AiNativeTextDocument.decode(
    records: _records(engine.replaceValues(replacements: {model: PsEngineDictionary(values: changed)}).bytes),
  );
}

/// Builds matching named/compact structures independently of the production reader.
List<int> _styleEngine({required bool named}) {
  /// Selects the literal key spelling for this synthetic format variant.
  String key(String compact, String name) => named ? name : compact;
  final String text = latin1.decode(PsEngineCodec.encode(value: PsEngineString.fromText(text: 'AB\r')));
  return latin1.encode('''
/${key('0', 'DocumentResources')} << /${key('1', 'FontSet')} << /${key('0', 'Resources')} [ << /${key('0', 'Resource')} <<
 /${key('0', 'Identifier')} << /${key('0', 'Name')} (Example-Regular) >> >> >> ] >>
 /${key('5', 'StyleSheetSet')} << /${key('0', 'Resources')} [
 << /${key('0', 'Resource')} << /${key('0', 'Name')} (Normal) /${key('6', 'Features')} <<
 /${key('0', 'Font')} 0 /${key('1', 'FontSize')} 12 /${key('6', 'HorizontalScale')} 1
 /${key('18', 'Ligatures')} true /${key('85', 'StylisticSets')} 4 >> >> >>
 << /${key('0', 'Resource')} << /${key('0', 'Name')} (Child) /${key('5', 'Parent')} 0 /${key('6', 'Features')} <<
 /${key('1', 'FontSize')} 24 /${key('8', 'Tracking')} 20 >> >> >> ] >>
 /${key('6', 'ParagraphSheetSet')} << /${key('0', 'Resources')} [ << /${key('0', 'Resource')} <<
 /${key('0', 'Name')} (Paragraph) /${key('5', 'Features')} << /${key('0', 'Justification')} 2
 /${key('32', 'DefaultStyle')} << /${key('1', 'FontSize')} 18 >> >> >> >> ] >>
 /${key('8', 'TextFrameSet')} << /${key('0', 'Resources')} [ << /${key('0', 'Resource')} <<
 /${key('2', 'Data')} << /${key('0', 'Type')} 1 /${key('2', 'FrameMatrix')} [1 0 0 1 5 6] >> >> >> ] >> >>
/${key('1', 'DocumentObjects')} << /${key('0', 'DocumentSettings')} << /${key('1', 'NormalStyleSheet')} 0 /${key('2', 'NormalParagraphSheet')} 0 >>
 /${key('1', 'TextObjects')} [ << /${key('0', 'Model')} << /${key('0', 'Text')} $text
 /${key('5', 'ParagraphRun')} << /${key('0', 'RunArray')} [ << /${key('0', 'RunData')} << /${key('0', 'ParagraphSheet')} 0 >> /${key('1', 'Length')} 3 >> ] >> >>
 /${key('1', 'View')} << /${key('0', 'Frames')} [ << /${key('0', 'Resource')} 0 >> ] /${key('2', 'Strikes')} [ <<
 /${key('99', 'StreamTag')} /${named ? 'FrameStrike' : 'F'} /${key('10', 'Frame')} 0
 /${key('0', 'Transform')} << /${key('0', 'Origin')} [10 20] >> /${key('6', 'Children')} [ <<
 /${key('99', 'StreamTag')} /${named ? 'Segment' : 'S'} /${key('20', 'FirstCharacterIndexInSegment')} 0
 /${key('15', 'Mapping')} << /${key('0', 'CharacterCount')} 3 >> /${key('6', 'Children')} [ <<
 /${key('99', 'StreamTag')} /${named ? 'GlyphStrike' : 'G'} /${key('5', 'Glyphs')} [41 42 1]
 /${key('8', 'VisualBounds')} [10 15 30 22] /${key('10', 'ShadowStylesRun')} << >> >>
 << /${key('99', 'StreamTag')} /FutureStrike /unknown true >> ] >> ] >> ] >> >> ] >>
''');
}
