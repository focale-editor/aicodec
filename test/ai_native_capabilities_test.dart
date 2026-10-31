import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_test.dart' as fixtures;

/// Creates an independently authored legacy source with explicit body bounds.
AiNativeSource _source(String body) => AiNativeData.extract(const AiCodec().decode(latin1.encode('%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'))).single;

/// Checks capability scope, opaque neighbors, diagnostic ownership and budgets.
void main() {
  test('qualifies layer headers and plain paths without claiming the whole program', () {
    final AiPdfDocument original = fixtures.nativePdf(compression: .zstandard, alias: true);
    final PdfReference catalog = original.pdf.trailer['Root']! as PdfReference;
    final AiPdfDocument carrier = AiPdfDocument(
      pdf: original.pdf.copyWith(
        objects: {
          ...original.pdf.objects,
          catalog: original.pdf.catalog.copyWith(values: {'PieceInfo': original.pdf.pages.first.dictionary['PieceInfo']!}),
        },
      ),
    );
    final AiNativeSource source = AiNativeData.extract(carrier).single;
    final List<int> before = const AiCodec().encode(carrier);

    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);

    check(report.complete).isTrue();
    final AiNativeCapability layer = report.findings.singleWhere((finding) => finding.feature == .layer);
    final AiNativeCapability path = report.findings.singleWhere((finding) => finding.feature == .path);
    check(layer.editable).isTrue();
    check(layer.end < path.start).isTrue();
    check(path.editable).isTrue();
    check(layer.owners).deepEquals([null, 0, 1]);
    check(layer.source).identicalTo(source);
    check(report.findings.first.support).equals(AiNativeDataSupport.preserved);
    check(report.findings.first.editable).isFalse();
    check(report.findings.clear).throws<UnsupportedError>();
    check(layer.edits.clear).throws<UnsupportedError>();
    check(() => layer.owners.clear()).throws<UnsupportedError>();
    check(const AiCodec().encode(carrier)).deepEquals(before);
  });

  test('preserves opaque neighbors without granting them a layer capability', () {
    const String opaque = '%_/FutureObject :\n%_7 /Int (Secret) ,\n%_;';
    final AiPdfDocument carrier = fixtures.nativePdf(compression: .plain, nativeProgram: fixtures.programText.replaceFirst('LB\n', '17 FuturePaint\n$opaque\nLB\n'));
    final AiNativeSource source = AiNativeData.extract(carrier).single;
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final AiNativeCapability layer = report.findings.singleWhere((finding) => finding.feature == .layer);
    final AiNativeCapability path = report.findings.singleWhere((finding) => finding.feature == .path);
    final AiNativeCapability unknown = report.findings.singleWhere((finding) => finding.feature == .instruction && finding.message.contains('FuturePaint'));
    final AiNativeCapability record = report.findings.singleWhere((finding) => finding.feature == .record && finding.message.contains('FutureObject'));
    check(layer.editable).isTrue();
    check(path.support).equals(AiNativeDataSupport.typed);
    check(path.edits.single.support).equals(AiNativeEditSupport.unsupported);
    check(path.editable).isFalse();
    check(unknown.support).equals(AiNativeDataSupport.preserved);
    check(latin1.decode(source.bytes.sublist(unknown.start, unknown.end))).equals('17 FuturePaint');
    check(record.editable).isFalse();
    check(latin1.decode(source.bytes.sublist(record.start, record.end))).contains('FutureObject');
  });

  test('reports malformed structures separately from bounded inspection', () {
    final AiNativeCapabilityReport malformed = AiNativeCapabilityReport.inspect(source: _source('0 m 1 1 L S'));
    check(malformed.complete).isFalse();
    check(malformed.findings.single.support).equals(AiNativeDataSupport.malformed);
    for (final AiNativeLimits limits in [const AiNativeLimits(maxDecodedBytes: 10), const AiNativeLimits(maxTokens: 1), const AiNativeLimits(maxDepth: 1)]) {
      final AiNativeCapabilityReport bounded = AiNativeCapabilityReport.inspect(source: _source('[[1]] FutureArray'), limits: limits);
      check(bounded.complete).isFalse();
      check(bounded.findings.single.support).equals(AiNativeDataSupport.uninspected);
      check(bounded.findings.single.owners).isEmpty();
    }
  });

  test('bounds output without silently omitting diagnostics', () {
    final AiNativeSource source = _source('1 FutureOne 2 FutureTwo');
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source, maxFindings: 2);
    check(report.findings).length.equals(2);
    check(report.complete).isFalse();
    check(report.findings.last.selector).equals('inspection-limit');
    check(report.findings.last.support).equals(AiNativeDataSupport.uninspected);
    check(() => AiNativeCapabilityReport.inspect(source: source, maxFindings: 0)).throws<ArgumentError>();
  });

  test('reports unknown mesh layouts while retaining independent findings', () {
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: _source('/Mesh X!\n%_9 /Version X#\n%_/Cartesian /Type X#\n%_[1 1] /Size X#\n%_/Data X#\n%_/E X#\n/End X!'));
    check(report.findings.where((finding) => finding.feature == .mesh).single.support).equals(AiNativeDataSupport.unsupported);
    check(report.findings.first.support).equals(AiNativeDataSupport.preserved);
  });

  test('retains typed lookup ambiguity without labeling repeated fields malformed', () {
    final AiNativeSource source = _source('%_/Document :\n%_/Dictionary : ; /Recorded ,\n%_/Dictionary : ; /Recorded ,\n%_;');
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final AiNativeCapability issue = report.findings.singleWhere((finding) => finding.feature == .artboard);
    check(issue.support).equals(AiNativeDataSupport.unsupported);
    check(issue.message).contains('Recorded');
    check(issue.start > 0).isTrue();
    check(report.findings.where((finding) => finding.support == .malformed)).isEmpty();
  });

  test('keeps known missing live-shape dependencies unavailable', () {
    final AiNativeSource source = _source('''%_/ArtDictionary :
%_/Dictionary :
%_(ai::Rectangle) /UnicodeString (ai::LiveShape::HandlerName) ,
%_/Dictionary :
%_10 /Real (ai::Rectangle::CenterX) ,
%_20 /Real (ai::Rectangle::CenterY) ,
%_; (ai::LiveShape::Params) ,
%_; (ai::LiveShape) ,
%_;
''');
    final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source);
    final AiNativeCapability shape = report.findings.singleWhere((finding) => finding.feature == .liveShape && finding.support == .typed);
    final AiNativeCapability issue = report.findings.singleWhere((finding) => finding.feature == .liveShape && finding.support == .unsupported);
    check(shape.editable).isFalse();
    check(shape.edits.map((edit) => edit.support)).every((support) => support.equals(AiNativeEditSupport.unsupported));
    check(shape.edits.map((edit) => edit.reason)).every((reason) => reason.equals(issue.message));
  });

  test('retains earlier findings when a native hierarchy is malformed or limited', () {
    for (final bool malformed in [true, false]) {
      final AiNativeSource source = _source('${fixtures.programText}\n%_/Future : ${malformed ? '' : '/Child : ; ;'}');
      final AiNativeCapabilityReport report = AiNativeCapabilityReport.inspect(source: source, limits: const AiNativeLimits(maxDepth: 1));
      check(report.findings.where((finding) => finding.feature == .layer).single.editable).isTrue();
      check(report.findings.where((finding) => finding.feature == .record).last.support).equals(malformed ? AiNativeDataSupport.malformed : AiNativeDataSupport.uninspected);
      check(report.complete).isFalse();
    }
  });
}
