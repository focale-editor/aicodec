import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_opacity_masks_test.dart' show editOpacityMask, opacityMaskSource;
import 'ai_native_test.dart' as fixtures;
import 'ai_native_transparency_creation_test.dart' show createTransparency;
import 'ai_native_transparency_test.dart' show transparencyPrinting;

/// Independently authored host PDF appearance for the selected owner.
const String opacityPdfCommands = 'q /Host1 gs 0 0 0 rg 0 0 m 10 0 l 10 10 l h f Q';

/// Explicit grayscale host form, independently authored from the native parser.
const String opacityPdfMaskCommands = '0.3 g 0 0 m 10 0 l 10 10 l h f';

/// Saves all native owners and matching host PDF transparency without rendering.
AiPdfDocument opacitySave(AiNativeAppearances model, {required String originalSource, bool activeMask = false}) {
  final AiPdfDocument original = fixtures.nativePdf(compression: .zstandard, alias: true, thumbnail: true, nativeProgram: originalSource);
  final AiNativeSource source = AiNativeData.extract(original).single;
  final PdfEditor host = PdfEditor(document: original.pdf);
  final PdfReference? maskForm = activeMask
      ? host.addObject(
          value: PdfStream(
            dictionary: PdfDictionary(
              values: {
                'Type': PdfName(value: 'XObject'),
                'Subtype': PdfName(value: 'Form'),
                'BBox': PdfArray(
                  values: [
                    for (final int coordinate in [0, 0, 100, 100]) PdfNumber(value: coordinate),
                  ],
                ),
                'Resources': PdfDictionary(),
                'Group': PdfDictionary(
                  values: {
                    'S': PdfName(value: 'Transparency'),
                    'CS': PdfName(value: 'DeviceGray'),
                    'I': const PdfBoolean(value: true),
                  },
                ),
              },
            ),
            data: latin1.encode(opacityPdfMaskCommands),
          ),
        )
      : null;
  for (int index = 0; index < host.document.pages.length; index++) {
    host.setPageResource(
      pageIndex: index,
      category: 'ExtGState',
      prefix: 'Host',
      value: PdfDictionary(
        values: {
          'Type': PdfName(value: 'ExtGState'),
          'ca': PdfNumber(value: 0.25),
          'CA': PdfNumber(value: 0.25),
          'BM': PdfName(value: 'Multiply'),
          'SMask': maskForm == null
              ? PdfName(value: 'None')
              : PdfDictionary(
                  values: {
                    'S': PdfName(value: 'Luminosity'),
                    'G': maskForm,
                    'BC': PdfArray(values: [PdfNumber(value: 0)]),
                  },
                ),
        },
      ),
    );
    host.setPageContent(pageIndex: index, bytes: latin1.encode(opacityPdfCommands));
  }
  return const AiCodec().decode(const AiCodec().encode(AiNativeData.replace(source: source, program: model.structure.drawing.records.program.bytes, synchronizedPdf: host.document, blockBytes: 71)))
      as AiPdfDocument;
}

/// Saves an active native grayscale mask with explicit flattened printing/PDF data.
AiPdfDocument activeOpacitySave() {
  final String text = opacityMaskSource();
  final AiNativeAppearances transparent = createTransparency(appearanceEditingModel(source: text));
  final AiNativeAppearances masked = editOpacityMask(
    transparent,
    settings: const AiNativeOpacityMaskSettings(linked: true, disabled: false, clipping: true, inverted: false),
    printing: transparencyPrinting.replaceFirst('1 0.25', '1 0.075'),
  );
  return opacitySave(masked, originalSource: text, activeMask: true);
}

/// Verifies complete serialization, PDF resources and re-editable native owners.
void main() {
  test('reopens mask flags artwork and host PDF transparency across shared owners', () {
    final String text = opacityMaskSource(grouped: true, child: true);
    final AiNativeAppearances before = appearanceEditingModel(source: text);
    final AiNativeAppearances changed = createTransparency(editOpacityMask(before));
    final AiPdfDocument saved = opacitySave(changed, originalSource: text);
    final AiNativeSource native = AiNativeData.extract(saved).single;
    check(native.owners).length.equals(2);
    check(native.bytes).deepEquals(changed.structure.drawing.records.program.bytes);
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(native.bytes));
    final AiNativeOpacityMask mask = reopened.artworkFor(use: reopened.uses.first).opacityMasks.single;
    check(mask.settings.disabled).isTrue();
    check(mask.settings.inverted).isTrue();
    check(mask.artworkBytes).deepEquals(before.artworkFor(use: before.uses.first).opacityMasks.single.artworkBytes);
    check(reopened.styles.last.parts.last.paints.single.style.assignments.single.transparency!.opacity).equals(0.25);
    for (int index = 0; index < saved.pdf.pages.length; index++) {
      check(latin1.decode(saved.pdf.pageContent(saved.pdf.pages[index]))).equals(opacityPdfCommands);
      final PdfDictionary state = PdfEditor(document: saved.pdf).pageResource(pageIndex: index, category: 'ExtGState', name: 'Host1') as PdfDictionary;
      check((state['ca']! as PdfNumber).value).equals(0.25);
      check(state.name('BM')).equals('Multiply');
      check(state.name('SMask')).equals('None');
    }
    final AiNativeAppearances editedAgain = editOpacityMask(reopened);
    check(editedAgain.artworkFor(use: editedAgain.uses.first).opacityMasks.single.settings.disabled).isTrue();
  });

  test('saves an active grayscale mask and its independent PDF soft-mask form', () {
    final AiPdfDocument saved = activeOpacitySave();
    final AiNativeAppearances native = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    final AiNativeOpacityMask mask = native.artworkFor(use: native.uses.first).opacityMasks.single;
    check(mask.settings.disabled).isFalse();
    check(mask.settings.clipping).isTrue();
    for (int index = 0; index < saved.pdf.pages.length; index++) {
      final PdfDictionary state = PdfEditor(document: saved.pdf).pageResource(pageIndex: index, category: 'ExtGState', name: 'Host1') as PdfDictionary;
      final PdfDictionary softMask = state['SMask']! as PdfDictionary;
      check(softMask.name('S')).equals('Luminosity');
      final PdfStream form = saved.pdf.resolve(softMask['G']!) as PdfStream;
      check(latin1.decode(form.data)).equals(opacityPdfMaskCommands);
      check((form.dictionary['Group']! as PdfDictionary).name('CS')).equals('DeviceGray');
    }
  });

  test('reports mask fields independently from conditional edit coverage', () {
    final String text = opacityMaskSource();
    final AiNativeSource native = AiNativeData.extract(opacitySave(editOpacityMask(appearanceEditingModel(source: text)), originalSource: text)).single;
    final AiNativeCapability mask = AiNativeCapabilityReport.inspect(source: native).findings.singleWhere((finding) => finding.feature == .opacityMask);
    check(mask.support).equals(AiNativeDataSupport.typed);
    check(mask.edits.map((edit) => edit.operation)).deepEquals([AiNativeEditOperation.opacityMaskSettings, AiNativeEditOperation.opacityMaskArtwork]);
    check(mask.edits.every((edit) => edit.support == .requiresValidation)).isTrue();
  });
}
