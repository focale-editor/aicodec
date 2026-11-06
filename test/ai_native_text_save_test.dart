import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_test.dart' as fixtures;
import 'ai_native_text_lifecycle_test.dart' show addLifecycleStory, lifecycleDocument;

/// Explicit host fixture: one line of glyphs in the first frame, other frames empty.
///
/// Glyph identifiers are deliberately synthetic; this tests attachment and file
/// ownership, not font shaping or Adobe's rendering of a particular font.
PsEngineDictionary composedTextView(AiNativeTextStory story, {bool named = false, bool glyphs = true, int? end, int? frame, int start = 0}) {
  /// Keeps independent CS and CC fixture spellings.
  String key(String compact, String full) => named ? full : compact;
  final int count = end ?? story.modelText.length;
  return PsEngineDocument.decode(
        bytes: latin1.encode('''<<
 /${key('0', 'Frames')} [ ${story.frameIndices.map((index) => '<< /${key('0', 'Resource')} $index >>').join(' ')} ]
 /${key('2', 'Strikes')} [ << /${key('99', 'StreamTag')} /${named ? 'PathSelectGroupCharacter' : 'PC'} /${key('6', 'Children')} [
 ${story.frameIndices.indexed.map((entry) => '''<< /${key('99', 'StreamTag')} /${named ? 'FrameStrike' : 'F'} /${key('10', 'Frame')} ${frame ?? entry.$2}
 /${key('0', 'Transform')} << /${key('0', 'Origin')} [10 20] >>
 /${key('6', 'Children')} [ ${entry.$1 != 0 || count == 0 ? '' : '''
 << /${key('99', 'StreamTag')} /${named ? 'LineStrike' : 'L'} /${key('6', 'Children')} [
 << /${key('99', 'StreamTag')} /${named ? 'Segment' : 'S'} /${key('20', 'FirstCharacterIndexInSegment')} $start /${key('15', 'Mapping')} << /${key('0', 'CharacterCount')} $count >>
 /${key('6', 'Children')} [ ${glyphs ? '<< /${key('99', 'StreamTag')} /${named ? 'GlyphStrike' : 'G'} /${key('5', 'Glyphs')} [${List.generate(count, (index) => index + 1).join(' ')}] >>' : ''} ] >> ] >>
 '''} ] >>''').join(' ')}
 ] >> ] >>'''),
      ).root
      as PsEngineDictionary;
}

/// Supplies the host-composed native view and explicit ink bounds.
AiNativeTextDocument _compose(AiNativeTextDocument document, {int index = 0, bool named = false}) => document.withComposedText(
  story: document.stories[index],
  view: composedTextView(document.stories[index], named: named),
  bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
);

/// Structural save acceptance keeps native, printable PDF and auxiliary data together.
void main() {
  for (final bool named in [false, true]) {
    test('attaches ${named ? 'named' : 'compact'} printable layout and validates complete coverage', () {
      final AiNativeTextDocument source = addLifecycleStory(lifecycleDocument(named: named), 'AB', named: named);
      check(source.validateTextForSave).throws<FormatException>();
      final AiNativeTextDocument composed = _compose(source, named: named);
      composed.validateTextForSave();
      check(composed.stories.single.strikes.single.descendants.last.glyphIds).deepEquals([1, 2, 3]);
      final AiNativeTextDocument changed = composed.replaceText(story: composed.stories.single, start: 0, end: 1, text: 'CD');
      check(changed.validateTextForSave).throws<FormatException>();
      final AiNativeTextDocument refreshed = _compose(changed, named: named);
      refreshed.validateTextForSave();
      check(refreshed.stories.single.text).equals('CDB');
      check(source.stories.single.strikes).isEmpty();
    });
  }

  test('remaps retained composed frames and preserves unaffected glyphs', () {
    final AiNativeTextDocument first = addLifecycleStory(lifecycleDocument(), 'A');
    final AiNativeTextDocument both = addLifecycleStory(first, 'B');
    final AiNativeTextDocument composed = _compose(_compose(both), index: 1);
    final AiNativeTextDocument removed = composed.removeStory(story: composed.stories.first);
    removed.validateTextForSave();
    check(removed.stories.single.strikes.single.children.single.frameIndex).equals(0);
    check(removed.stories.single.strikes.single.descendants.last.glyphIds).deepEquals([1, 2]);
    final AiNativeTextDocument linked = removed.duplicateFrame(frame: removed.frames.single);
    check(linked.validateTextForSave).throws<FormatException>();
    final AiNativeTextDocument recomposed = _compose(linked);
    recomposed.validateTextForSave();
    check(recomposed.stories.single.strikes.single.children.map((strike) => strike.frameIndex)).deepEquals([0, 1]);
  });

  test('rejects missing glyphs, wrong resources, gaps, unknown caches and surrogate boundaries', () {
    final AiNativeTextDocument source = addLifecycleStory(lifecycleDocument(), 'A🖋B');
    final AiNativeTextStory story = source.stories.single;
    for (final PsEngineDictionary view in [
      composedTextView(story, glyphs: false),
      composedTextView(story, frame: 100),
      composedTextView(story, start: 1, end: story.modelText.length - 1),
    ]) {
      check(() => source.withComposedText(story: story, view: view, bounds: AiBoundingBox(left: 0, bottom: 0, right: 1, top: 1))).throws<FormatException>();
    }
    final PsEngineDictionary view = composedTextView(story);
    check(
      () => source.withComposedText(
        story: story,
        view: PsEngineDictionary(
          values: {
            ...view.values,
            '1': PsEngineDictionary(values: {}),
          },
        ),
        bounds: AiBoundingBox(left: 0, bottom: 0, right: 1, top: 1),
      ),
    ).throws<UnsupportedError>();
    check(() => source.withComposedText(story: story, view: composedTextView(story, end: 2), overflowStart: 2, bounds: AiBoundingBox(left: 0, bottom: 0, right: 1, top: 1))).throws<ArgumentError>();
    final AiNativeTextDocument overset = source.withComposedText(story: story, view: composedTextView(story, end: 0), overflowStart: 0, bounds: AiBoundingBox(left: 0, bottom: 0, right: 1, top: 1));
    check(overset.validateTextForSave).throws<FormatException>();
    overset.validateTextForSave(overflowStarts: {overset.stories.single: 0});
    check(() => overset.validateTextForSave(overflowStarts: {story: 0})).throws<ArgumentError>();
  });

  test('full compressed AI save reopens edited text, references, glyphs, PDF and auxiliary data', () {
    final AiNativeTextDocument initial = addLifecycleStory(lifecycleDocument(), 'Old');
    final AiNativeTextObject object = initial.objects.single;
    final AiProgram tagged = AiNativeEditor.apply(
      program: initial.records.program,
      edits: [
        AiSourceEdit(start: object.record.end, end: object.record.end, bytes: latin1.encode('\n%_/ArtDictionary :\n%_(obsolete-raw-data) /UnicodeString (AI24 TextStoryRawDataUUID) ,\n%_;\n')),
      ],
    );
    final AiPdfDocument original = fixtures.nativePdf(compression: .zstandard, alias: true, thumbnail: true, nativeProgram: latin1.decode(tagged.bytes));
    final AiNativeSource native = AiNativeData.extract(original).single;
    final AiNativeTextDocument source = AiNativeTextDocument.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: native.bytes)),
    );
    final AiNativeTextDocument edited = source.replaceText(story: source.stories.single, start: 0, end: 3, text: 'New');
    final AiNativeTextDocument styled = edited.setCharacterFeatures(
      story: edited.stories.single,
      start: 0,
      end: edited.stories.single.modelText.length,
      changes: AiNativeCharacterChanges(fontSize: 12),
    );
    final AiNativeTextDocument copied = styled.duplicateStory(story: styled.stories.single);
    final AiNativeTextDocument linked = copied.duplicateFrame(frame: copied.frames.last);
    final AiNativeTextDocument unlinked = linked.removeFrame(frame: linked.frames.last);
    final AiNativeTextDocument removed = unlinked.removeStory(story: unlinked.stories.last);
    final AiNativeTextDocument composed = _compose(removed);
    composed.validateTextForSave();
    check(latin1.decode(composed.records.program.bytes)).not((it) => it.contains('obsolete-raw-data'));
    final PdfEditor host = PdfEditor(document: original.pdf);
    for (int index = 0; index < host.document.pages.length; index++) {
      final String font = host.setPageResource(
        pageIndex: index,
        category: 'Font',
        prefix: 'Text',
        value: PdfDictionary(
          values: {
            'Type': PdfName(value: 'Font'),
            'Subtype': PdfName(value: 'Type1'),
            'BaseFont': PdfName(value: 'Helvetica'),
          },
        ),
      );
      host.setPageContent(pageIndex: index, bytes: latin1.encode('BT /$font 12 Tf 10 80 Td (New) Tj ET'));
    }
    final AiPdfDocument saved = AiNativeData.replace(source: native, program: composed.records.program.bytes, synchronizedPdf: host.document, blockBytes: 53);
    final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
    final AiNativeSource newNative = AiNativeData.extract(reopened).single;
    final AiNativeTextDocument text = AiNativeTextDocument.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: newNative.bytes)),
    );
    text.validateTextForSave();
    check(text.stories.single.text).equals('New');
    check(text.styledRanges(story: text.stories.single).first.characterStyle.fontSize).equals(12.0);
    check(text.stories.single.frameIndices).deepEquals([0]);
    check(text.objects.single.storyIndex).equals(0);
    check(text.referenceIssues).isEmpty();
    check(text.stories.single.strikes.single.descendants.last.glyphIds).deepEquals([1, 2, 3, 4]);
    check(newNative.owners).deepEquals(native.owners);
    check(latin1.decode(newNative.bytes)).not((it) => it.contains('obsolete-raw-data'));
    check(text.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary())
        .deepEquals(source.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary());
    for (final PdfPage page in reopened.pdf.pages) {
      check(latin1.decode(reopened.pdf.pageContent(page))).contains('(New) Tj');
      check(reopened.pdf.dictionary(page.dictionary['Resources']!)['Font']).isNotNull();
    }
    // The saved native source remains writable after reacquiring ownership.
    final AiNativeTextDocument deleted = text.removeStory(story: text.stories.single);
    deleted.validateTextForSave();
    final PdfEditor blank = PdfEditor(document: reopened.pdf);
    for (int index = 0; index < blank.document.pages.length; index++) {
      blank.setPageContent(pageIndex: index, bytes: latin1.encode('q Q'));
    }
    final AiPdfDocument cleared = AiNativeData.replace(source: newNative, program: deleted.records.program.bytes, synchronizedPdf: blank.document);
    final AiDocument finalFile = const AiCodec().decode(const AiCodec().encode(cleared));
    final AiNativeTextDocument finalText = AiNativeTextDocument.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(finalFile).single.bytes)),
    );
    check(finalText.stories).isEmpty();
    check(finalText.objects).isEmpty();
    finalText.validateTextForSave();
  });
}
