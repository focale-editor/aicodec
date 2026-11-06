import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentRecords, newDocumentSave;

/// Keeps the package independent of host payload schemas and hash dependencies.
void main() {
  test('round trips host data without changing native or PDF binding bytes', () {
    final AiPdfDocument source = newDocumentSave(newDocumentRecords(blank: true), newDocumentPdf(blank: true));
    final List<int> binding = List.filled(32, 7);
    final List<int> data = [1, 2, 3];
    final AiHostSnapshot snapshot = AiHostSnapshot(data: data, binding: binding);
    data[0] = 9;
    AiPdfDocument current = snapshot.attach(document: source, application: 'FocaleEffects');
    for (int revision = 0; revision < 3; revision++) {
      current = const AiCodec().decode(const AiCodec().encode(current)) as AiPdfDocument;
      final AiHostSnapshot restored = AiHostSnapshot.read(document: current, application: 'FocaleEffects')!;
      check(restored.data).deepEquals([1, 2, 3]);
      check(restored.binding).deepEquals(binding);
      check(current.pdf.objects.length).equals(source.pdf.objects.length + 1);
      check(AiHostSnapshot.bindingBytes(document: current, application: 'FocaleEffects')).deepEquals(AiHostSnapshot.bindingBytes(document: source, application: 'FocaleEffects'));
      check(AiNativeData.extract(current).single.bytes).deepEquals(AiNativeData.extract(source).single.bytes);
      current = snapshot.attach(document: current, application: 'FocaleEffects');
    }
  });
  test('binding includes compatibility resources and native authoring', () {
    final AiPdfDocument source = newDocumentSave(newDocumentRecords(blank: true), newDocumentPdf(blank: true));
    final PdfEditor editor = PdfEditor(document: source.pdf)..setPageAttributes(pageIndex: 0, values: {'Rotate': PdfNumber(value: 90)});
    check(
      AiHostSnapshot.bindingBytes(document: source, application: 'FocaleEffects').toString() ==
          AiHostSnapshot.bindingBytes(
            document: AiPdfDocument(pdf: editor.document),
            application: 'FocaleEffects',
          ).toString(),
    ).isFalse();
  });
  test('rejects shared snapshot streams and unknown versions', () {
    final AiPdfDocument source = newDocumentSave(newDocumentRecords(blank: true), newDocumentPdf(blank: true));
    final AiPdfDocument saved = AiHostSnapshot(data: [1], binding: List.filled(32, 0)).attach(document: source, application: 'FocaleEffects');
    final PdfReference reference = saved.pdf.catalog['AiKitHost_FocaleEffects']! as PdfReference;
    final PdfEditor editor = PdfEditor(document: saved.pdf)..setCatalogEntries(values: {'UnrelatedAlias': reference});
    check(
      () => AiHostSnapshot.without(
        document: AiPdfDocument(pdf: editor.document),
        application: 'FocaleEffects',
      ),
    ).throws<FormatException>();
    final PdfStream stream = saved.pdf.resolve(reference) as PdfStream;
    final AiPdfDocument future = AiPdfDocument(
      pdf: saved.pdf.copyWith(
        objects: {
          ...saved.pdf.objects,
          reference: PdfStream(
            dictionary: stream.dictionary.copyWith(values: {'Version': PdfNumber(value: 2)}),
            data: stream.data,
          ),
        },
      ),
    );
    check(() => AiHostSnapshot.read(document: future, application: 'FocaleEffects')).throws<FormatException>();
    check(() => AiHostSnapshot.without(document: future, application: 'FocaleEffects')).throws<FormatException>();
    check(() => AiHostSnapshot(data: [], binding: [])).throws<ArgumentError>();
    check(() => AiHostSnapshot.bindingBytes(document: source, application: '../Other')).throws<ArgumentError>();
  });
}
