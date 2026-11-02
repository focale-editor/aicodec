import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart';

/// Changes only the first host page dictionary, keeping its indirect identity.
PdfDocument documentPageValues(PdfDocument pdf, Map<String, PdfValue> values) {
  final PdfPage page = pdf.pages.first;
  return (PdfEditor(document: pdf)..replaceObject(
        reference: page.reference!,
        value: page.dictionary.copyWith(values: values),
      ))
      .document;
}

/// Supplies an explicit PDF rectangle, including nonzero coordinate origins.
PdfArray documentBox(List<num> values) => PdfArray(values: values.map((value) => PdfNumber(value: value)).toList());

/// Reparses a changed immutable native source for validation boundary tests.
AiNativeRecords documentSource(AiNativeRecords source, String before, String after) => AiNativeRecords.decode(
  program: AiProgram.decode(bytes: latin1.encode(latin1.decode(source.program.bytes).replaceFirst(before, after))),
);

/// Covers first-container ownership, graph preservation and rejection policies.
void main() {
  test('requires every current board and page in matching order', () {
    final AiNativeRecords records = newDocumentRecords();
    final PdfDocument pdf = newDocumentPdf();
    final List<AiNativeDocumentPage> bindings = newDocumentBindings(records, pdf);
    final List<AiNativeDocumentPage> foreign = newDocumentBindings(newDocumentRecords(), pdf);
    for (final List<AiNativeDocumentPage> invalid in [
      [],
      bindings.reversed.toList(),
      [bindings.first, bindings.first],
      foreign,
      [bindings.first, AiNativeDocumentPage(artboard: bindings.last.artboard, page: bindings.first.page)],
    ]) {
      check(() => AiNativeDocument.createPdf(records: records, compatibilityPdf: pdf, pages: invalid, modifiedAt: DateTime.utc(2026))).throws<ArgumentError>();
    }
    check(() => AiNativeDocument.createPdf(records: records, compatibilityPdf: newDocumentPdf(blank: true), pages: bindings, modifiedAt: DateTime.utc(2026))).throws<ArgumentError>();
  });

  test('retains bleed and nonzero origins and rejects incompatible page geometry', () {
    final AiNativeRecords records = newDocumentRecords(blank: true);
    final PdfDocument pdf = newDocumentPdf(blank: true);
    final PdfDocument bleed = documentPageValues(pdf, {
      'MediaBox': documentBox([-20, -30, 100, 90]),
      'CropBox': documentBox([-15, -25, 95, 85]),
      'TrimBox': documentBox([-10, -20, 90, 80]),
    });
    final AiPdfDocument saved = newDocumentSave(records, bleed);
    for (final String key in ['MediaBox', 'CropBox', 'TrimBox']) {
      check((saved.pdf.pages.single.dictionary[key]! as PdfArray).values.map((value) => (value as PdfNumber).value))
          .deepEquals((bleed.pages.single.dictionary[key]! as PdfArray).values.map((value) => (value as PdfNumber).value));
    }
    for (final Map<String, PdfValue> invalid in [
      {
        'MediaBox': documentBox([0, 0, 101, 100]),
      },
      {
        'CropBox': documentBox([-1, 0, 100, 100]),
      },
      {
        'TrimBox': documentBox([0, 0, 100, 101]),
      },
    ]) {
      check(() => newDocumentSave(records, documentPageValues(pdf, invalid))).throws<ArgumentError>();
    }
    for (final Map<String, PdfValue> invalid in [
      {'Rotate': PdfNumber(value: 90)},
      {'UserUnit': PdfNumber(value: 2)},
    ]) {
      check(() => newDocumentSave(records, documentPageValues(pdf, invalid))).throws<UnsupportedError>();
    }
  });

  test('preserves host metadata resources and unknown operators without rendering', () {
    final AiNativeRecords records = documentSource(newDocumentRecords(blank: true), '%%PageTrailer', '42 HostNativeExtension\n%%PageTrailer');
    final PdfDocument pdf = newDocumentPdf(blank: true);
    final PdfEditor host = PdfEditor(document: pdf);
    final PdfReference metadata = host.addObject(
      value: PdfStream(
        dictionary: PdfDictionary(
          values: {
            'Type': PdfName(value: 'Metadata'),
            'Subtype': PdfName(value: 'XML'),
          },
        ),
        data: utf8.encode('<host/>'),
      ),
    );
    host.replaceObject(
      reference: pdf.trailer['Root']! as PdfReference,
      value: pdf.catalog.copyWith(values: {'Metadata': metadata}),
    );
    final PdfDictionary extra = PdfDictionary(
      values: {
        'Host': PdfDictionary(values: {'Private': PdfString.text(text: 'retained')}),
      },
    );
    final PdfDocument decorated = documentPageValues(host.document, {
      'PieceInfo': extra,
      'Resources': PdfDictionary(values: {'Host': metadata}),
    });
    final AiPdfDocument saved = newDocumentSave(records, decorated);
    check(AiNativeData.extract(saved).single.bytes).deepEquals(records.program.bytes);
    check(saved.pdf.decodeStream(saved.pdf.resolve(saved.pdf.catalog['Metadata']!) as PdfStream)).deepEquals(utf8.encode('<host/>'));
    final PdfDictionary retained = saved.pdf.dictionary(saved.pdf.dictionary(saved.pdf.pages.single.dictionary['PieceInfo']!)['Host']!);
    check((retained['Private']! as PdfString).bytes).deepEquals((decorated.dictionary(extra['Host']!)['Private']! as PdfString).bytes);
    check(saved.pdf.dictionary(saved.pdf.pages.single.dictionary['Resources']!)['Host']).equals(metadata);
    check(decorated.pages.single.dictionary['PieceInfo']).equals(extra);
  });

  test('rejects existing and partial Illustrator attachments and unresolved graphs', () {
    final AiNativeRecords records = newDocumentRecords(blank: true);
    final PdfDocument pdf = newDocumentPdf(blank: true);
    final PdfDictionary attached = PdfDictionary(values: {'Illustrator': PdfDictionary()});
    check(() => newDocumentSave(records, documentPageValues(pdf, {'PieceInfo': attached}))).throws<ArgumentError>();
    final PdfEditor catalog = PdfEditor(document: pdf)
      ..replaceObject(
        reference: pdf.trailer['Root']! as PdfReference,
        value: pdf.catalog.copyWith(values: {'PieceInfo': attached}),
      );
    check(() => newDocumentSave(records, catalog.document)).throws<ArgumentError>();
    check(() => newDocumentSave(records, newDocumentSave(records, pdf).pdf)).throws<ArgumentError>();
    final PdfDocument dangling = documentPageValues(pdf, {'Metadata': const PdfReference(objectNumber: 12345)});
    check(() => newDocumentSave(records, dangling)).throws<FormatException>();
    final PdfDocument encrypted = pdf.copyWith(trailer: pdf.trailer.copyWith(values: {'Encrypt': PdfDictionary()}));
    check(() => newDocumentSave(records, encrypted)).throws<UnsupportedError>();
  });

  test('rejects unsupported profiles and dangling named native resources', () {
    final AiNativeRecords records = newDocumentRecords(blank: true);
    final PdfDocument pdf = newDocumentPdf(blank: true);
    for (final AiNativeRecords invalid in [
      documentSource(records, '%%AI8_CreatorVersion: 24.0.0', '%%AI8_CreatorVersion: 17.0.0'),
      documentSource(records, '%AI9_ColorModel: 1', '%AI9_ColorModel: 2'),
      documentSource(records, '%%PageTrailer', '1 (Missing) XW\n%%PageTrailer'),
    ]) {
      check(() => newDocumentSave(invalid, pdf)).throws<UnsupportedError>();
    }
  });

  test('bounds metadata dates block sizes and host stream/object budgets', () {
    final AiNativeRecords records = newDocumentRecords(blank: true);
    final PdfDocument pdf = newDocumentPdf(blank: true);
    check(() => newDocumentSave(records, pdf, blockBytes: 0)).throws<ArgumentError>();
    check(() => AiNativeDocument.createPdf(records: records, compatibilityPdf: pdf, pages: newDocumentBindings(records, pdf), modifiedAt: DateTime.utc(10000))).throws<ArgumentError>();
    for (final PdfLimits limits in [const PdfLimits(maxStreamBytes: 1), const PdfLimits(maxObjects: 4)]) {
      final PdfDocument limited = PdfDocument(objects: pdf.objects, trailer: pdf.trailer, limits: limits);
      check(() => newDocumentSave(records, limited)).throws<AiLimitException>();
    }
  });
}
