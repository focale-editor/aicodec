import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart';
import 'ai_native_image_creation_test.dart' show createdImageDocument;

/// Initializes typography with real host-supplied font identification fields.
AiNativeTextDocument newDocumentText({AiNativeRecords? records, PsEngineLimits limits = const PsEngineLimits()}) => AiNativeTextDocument.create(
  records: records ?? newDocumentRecords(blank: true),
  font: AiNativeFontDefinition(postScriptName: 'DejaVuSans', technology: .trueType, version: 'Version 2.37'),
  fontSize: 14,
  fillColor: AiNativeTextProcessColor(space: .rgb, components: [0.1, 0.2, 0.3]),
  rulerOrigin: [0, 100],
  characterStyleName: 'Corps 🖋',
  paragraphStyleName: 'Paragraphe',
  characterStyle: AiNativeCharacterChanges(tracking: 12),
  paragraphStyle: AiNativeParagraphChanges(spaceAfter: 5),
  limits: limits,
);

/// Verifies initial ATE resources and their interaction with existing documents.
void main() {
  test('retains literal process and named palettes through text initialization and story lifecycle', () {
    final AiNativeSwatches named = AiNativeSwatches.decode(records: newDocumentRecords(blank: true)).createNamed(
      nameBytes: ascii.encode('Spot'),
      color: AiNativeNamedColor(kind: .legacyCmyk, components: [.1, .2, .3, .4], nameBytes: ascii.encode('Ink'), tint: 0),
    );
    final AiNativeSwatches palette = named.createProcess(
      nameBytes: ascii.encode('Process'),
      color: AiColor(space: .rgb, channels: [.3, .4, .5]),
    );
    final AiNativePalette original = palette.palettes.single;
    final List<int> bytes = palette.records.program.bytes.sublist(original.start, original.end);
    final AiNativeTextDocument initialized = newDocumentText(records: palette.records);
    final AiNativeTextDocument created = initialized.createStory(text: 'Palette and text', frames: [AiNativeTextFrameDefinition.point(x: 10, y: 20)], layer: initialized.records.program.layers.single);
    final AiNativeTextDocument removed = created.removeStory(story: created.stories.single);
    for (final AiNativeTextDocument document in [initialized, created, removed]) {
      final AiNativePalette retained = AiNativeSwatches.decode(records: document.records).palettes.single;
      check(document.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(bytes);
    }
    final String unsupported = latin1.decode(palette.records.program.bytes).replaceFirst('0.3 0.4 0.5 Xa', '1 /Font CustomPaletteCommand');
    final AiNativeRecords unknown = AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(unsupported)));
    check(() => newDocumentText(records: unknown)).throws<UnsupportedError>();
  });

  test('initializes and edits text while retaining ordinary embedded and linked images', () {
    final AiNativeDrawing original = createdImageDocument();
    final AiNativeRasters images = AiNativeRasters.decode(records: original.records);
    final AiNativePlacements links = AiNativePlacements.decode(records: original.records);
    final AiNativeTextDocument initialized = newDocumentText(records: original.records);
    final AiNativeTextDocument created = initialized.createStory(text: 'Text and images', frames: [AiNativeTextFrameDefinition.point(x: 10, y: 20)], layer: initialized.records.program.layers.single);
    final AiNativeRasters retained = AiNativeRasters.decode(records: created.records);
    final AiNativePlacements references = AiNativePlacements.decode(records: created.records);
    check(retained.images.single.colorSamples).deepEquals(images.images.single.colorSamples);
    check(references.objects.single.pathBytes).deepEquals(links.objects.single.pathBytes);
    check(references.objects.single.preview!.bytes).deepEquals(links.objects.single.preview!.bytes);
    final AiNativeTextDocument removed = created.removeStory(story: created.stories.single);
    check(AiNativeRasters.decode(records: removed.records).images.single.colorSamples).deepEquals(images.images.single.colorSamples);
    check(AiNativePlacements.decode(records: removed.records).objects.single.preview!.bytes).deepEquals(links.objects.single.preview!.bytes);
  });

  test('initializes typography and creates editable stories without an AI template', () {
    final AiNativeRecords native = newDocumentRecords(blank: true);
    final AiNativeTextDocument initial = newDocumentText(records: native);
    check(initial.stories).isEmpty();
    check(initial.frames).isEmpty();
    check(initial.referenceIssues).isEmpty();
    check(initial.fonts.single.postScriptName).equals('DejaVuSans');
    check(initial.fonts.single.technology).equals(AiNativeFontTechnology.trueType);
    check(initial.fonts.single.version).equals('Version 2.37');
    check(initial.characterStyles.single.name).equals('Corps 🖋');
    check(initial.paragraphStyles.single.name).equals('Paragraphe');
    check(initial.normalCharacterStyleIndex).equals(0);
    check(initial.normalParagraphStyleIndex).equals(0);
    check(initial.container['RulerOrigin']!.numbers!).deepEquals([0.0, 100.0]);
    check(initial.records.containers.singleWhere((record) => record.type == 'AI11UndoFreeTextDocument').decodeBinary()).deepEquals(initial.engine.bytes);
    check(native.containers.where((record) => record.type == 'AI11TextDocument')).isEmpty();
    final AiNativeTextDocument created = initial.createStory(text: 'Bonjour 🖋\rSuite', frames: [AiNativeTextFrameDefinition.point(x: 10, y: 20)], layer: initial.records.program.layers.single);
    final AiNativeStyledTextRange style = created.styledRanges(story: created.stories.single).first;
    check(style.characterStyle.font!.postScriptName).equals('DejaVuSans');
    check(style.characterStyle.fontSize).equals(14);
    check(style.characterStyle.fillPaint!.color!.components).deepEquals([0.1, 0.2, 0.3]);
    check(style.characterStyle.tracking).equals(12);
    check(style.paragraphStyle.spaceAfter).equals(5);
    check(created.referenceIssues).isEmpty();
    check(created.duplicateStory(story: created.stories.single).stories).length.equals(2);
    final AiNativeTextDocument removed = created.removeStory(story: created.stories.single);
    check(removed.stories).isEmpty();
    check(removed.frames).isEmpty();
    check(latin1.decode(removed.records.program.bytes)).contains('%%DocumentFonts: DejaVuSans');
  });

  test('retains unrelated identified paths and expanded nested layers', () {
    final AiNativeRecords records = newDocumentRecords();
    final List<List<int>> paths = [for (final AiPath path in records.program.paths) records.program.bytes.sublist(path.geometry.first.start, path.paint.end)];
    final AiNativeTextDocument initial = newDocumentText(records: records);
    final AiNativeTextDocument created = initial.createStory(text: 'Text', frames: [AiNativeTextFrameDefinition.point(x: 0, y: 0)], layer: initial.records.program.layers.last);
    final AiNativeTextDocument changed = created.replaceText(story: created.stories.single, start: 0, end: 4, text: 'Edited');
    final AiNativeTextDocument cleared = changed.removeStory(story: changed.stories.single);
    check(cleared.records.program.paths).length.equals(paths.length);
    for (final (int, AiPath) entry in cleared.records.program.paths.indexed) {
      check(cleared.records.program.bytes.sublist(entry.$2.geometry.first.start, entry.$2.paint.end)).deepEquals(paths[entry.$1]);
    }
    check(AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: cleared.records)).layers.map((layer) => layer.identifier!.bytes)).deepEquals(
      AiNativeLayers.decode(drawing: AiNativeDrawing.decode(records: records)).layers.map((layer) => layer.identifier!.bytes),
    );
  });

  test('first save and later edits retain the initialized font/header cache', () {
    final AiNativeTextDocument initial = newDocumentText();
    final AiPdfDocument first = newDocumentSave(initial.records, newDocumentPdf(blank: true));
    final AiNativeSource source = AiNativeData.extract(first).single;
    final AiNativeTextDocument reopened = AiNativeTextDocument.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final AiNativeTextDocument created = reopened.createStory(text: 'Later', frames: [AiNativeTextFrameDefinition.point(x: 10, y: 20)]);
    // Removing the uncomposed story leaves a genuinely empty matching host PDF.
    final AiNativeTextDocument cleared = created.removeStory(story: created.stories.single);
    final AiPdfDocument saved =
        const AiCodec().decode(const AiCodec().encode(AiNativeData.replace(source: source, program: cleared.records.program.bytes, synchronizedPdf: first.pdf))) as AiPdfDocument;
    final AiNativeTextDocument result = AiNativeTextDocument.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
    );
    check(result.fonts.single.postScriptName).equals('DejaVuSans');
    check(result.stories).isEmpty();
    check(latin1.decode(saved.pdf.decodeStream(saved.pdf.resolve(newDocumentPrivate(saved.pdf, 0)['AIMetaData']!) as PdfStream))).contains('%%DocumentNeededFonts: DejaVuSans');
  });

  test('rejects duplicate namespaces and unsafe owners without changing the source', () {
    final AiNativeTextDocument initial = newDocumentText();
    check(() => newDocumentText(records: initial.records)).throws<ArgumentError>();
    final AiNativeRecords source = newDocumentRecords(blank: true);
    final AiNativeRecords unknown = AiNativeRecords.decode(
      program: AiProgram.decode(bytes: latin1.encode(latin1.decode(source.program.bytes).replaceFirst('%%EndSetup', '/FutureReferences : 0 /Story , ;\n%%EndSetup'))),
    );
    check(() => newDocumentText(records: unknown)).throws<UnsupportedError>();
    check(() => newDocumentText(limits: const PsEngineLimits(maxBytes: 200))).throws<Exception>();
    check(() => newDocumentText(limits: const PsEngineLimits(maxNodes: 12))).throws<Exception>();
    check(() => newDocumentText(limits: const PsEngineLimits(maxStringBytes: 3))).throws<ArgumentError>();
    check(source.containers.where((record) => record.type == 'AI11TextDocument')).isEmpty();
  });

  test('initializes text in a saved fontless AI and updates its full header cache', () {
    final AiPdfDocument original = newDocumentSave(newDocumentRecords(blank: true), newDocumentPdf(blank: true));
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeTextDocument initialized = newDocumentText(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: source.bytes)),
    );
    final AiPdfDocument saved =
        const AiCodec().decode(const AiCodec().encode(AiNativeData.replace(source: source, program: initialized.records.program.bytes, synchronizedPdf: original.pdf))) as AiPdfDocument;
    final List<int> header = saved.pdf.decodeStream(saved.pdf.resolve(newDocumentPrivate(saved.pdf, 0)['AIMetaData']!) as PdfStream);
    check(latin1.decode(header)).contains('%%DocumentFonts: DejaVuSans');
    check(latin1.decode(header).contains('%%DocumentFonts: (none)')).isFalse();
    check(
      AiNativeTextDocument.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
      ).fonts.single.postScriptName,
    ).equals('DejaVuSans');
  });
}
