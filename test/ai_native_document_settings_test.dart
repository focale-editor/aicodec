import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Keeps header, setup metadata and body declarations in separate regions.
AiNativeDocumentSettings _settings({String header = '', String setup = '', String body = '', AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDocumentSettings.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n$header\n%%EndComments\n$setup\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'), limits: limits),
  ),
);

/// Independent document metadata with two distinct coordinate origins.
const String _document = '''%_/Document : /Dictionary : /Array :
%_/Dictionary : (First) /String (Name) ,
%_0 100 /RealPointRelToROrigin (PositionPoint1) ,
%_200 0 /RealPointRelToROrigin (PositionPoint2) ,
%_8000 8100 /RealPoint (RulerOrigin) ,
%_(artboard-a) /String (ArtboardUUID) ,
%_1 /Bool (IsArtboardSelected) , ; ,
%_/Dictionary : (Second) /String (Name) ,
%_300 100 /RealPointRelToROrigin (PositionPoint1) ,
%_500 0 /RealPointRelToROrigin (PositionPoint2) , ; ,
%_; (ArtboardArray) , ; /Recorded ,
%_/Dictionary : /NotRecorded , (opaque) /String (Future) , ; /NotRecorded , ;
''';

/// Empty opaque text payload sufficient to carry a separate setup origin.
const String _text = '/AI11TextDocument : /ASCII85Decode ,\n%~>\n8191 8191 /RulerOrigin , ;';

/// Checks declared settings and ownership without deriving or rewriting artwork.
void main() {
  test('retains source headers and distinguishes display units and canvas scale', () {
    final AiNativeDocumentSettings settings = _settings(
      header: '%AI5_RulerUnits: 1\n%AI24_RulerUnitsLarge: 8\n%AI24_LargeCanvasScale: 10\n%%Canvassize: 16383\n%AI3_TemplateBox: 0 -2 20 30\n%%PageOrigin: 4 5',
    );
    check(settings.rulerUnitCode).equals(1);
    check(settings.largeRulerUnitCode).equals(8);
    check(settings.rulerUnit).equals(AiNativeRulerUnit.meters);
    check(settings.largeCanvasScale).equals(10);
    check(settings.canvasSize!).deepEquals([16383]);
    check(settings.templateBox!).deepEquals([0, -2, 20, 30]);
    check(settings.pageOrigin!).deepEquals([4, 5]);
    for (final AiNativeHeaderField field in settings.header.values) {
      check(latin1.decode(settings.records.program.bytes.sublist(field.token.start, field.token.end))).equals(field.token.lexeme);
    }
    check(settings.header.clear).throws<UnsupportedError>();
    check(settings.templateBox!.clear).throws<UnsupportedError>();
  });

  test('preserves absent and unknown unit values without guessing defaults', () {
    for (final (int, AiNativeRulerUnit) entry in [
      (0, AiNativeRulerUnit.inches),
      (1, AiNativeRulerUnit.millimeters),
      (2, AiNativeRulerUnit.points),
      (3, AiNativeRulerUnit.picas),
      (4, AiNativeRulerUnit.centimeters),
      (6, AiNativeRulerUnit.pixels),
    ]) {
      check(_settings(header: '%AI5_RulerUnits: ${entry.$1}').rulerUnit).equals(entry.$2);
    }
    for (final (int, AiNativeRulerUnit) entry in [(7, AiNativeRulerUnit.feetAndInches), (8, AiNativeRulerUnit.meters), (9, AiNativeRulerUnit.yards), (10, AiNativeRulerUnit.feet)]) {
      check(_settings(header: '%AI5_RulerUnits: 2\n%AI24_RulerUnitsLarge: ${entry.$1}').rulerUnit).equals(entry.$2);
    }
    check(_settings(header: '%AI5_RulerUnits: 5').rulerUnitCode).equals(5);
    check(_settings(header: '%AI5_RulerUnits: 5').rulerUnit).isNull();
    final AiNativeDocumentSettings unknown = _settings(header: '%AI5_RulerUnits: 1\n%AI24_RulerUnitsLarge: 42');
    check(unknown.largeRulerUnitCode).equals(42);
    check(unknown.rulerUnit).isNull();
    final AiNativeDocumentSettings absent = _settings();
    check(absent.rulerUnit).isNull();
    check(absent.largeCanvasScale).isNull();
    check(absent.templateBox).isNull();
    check(absent.artboards).isEmpty();
    check(absent.textRulerOrigins).isEmpty();
  });

  test('retains artboard order, owning documents and independent ruler origins', () {
    final AiNativeDocumentSettings settings = _settings(setup: '$_document\n$_text\n$_document', body: _text);
    check(settings.documents).length.equals(2);
    check(settings.artboards.map((board) => board.index)).deepEquals([0, 1, 0, 1]);
    check(settings.artboards[0].document).identicalTo(settings.documents[0]);
    check(settings.artboards[2].document).identicalTo(settings.documents[1]);
    check(settings.artboards.first.identifier).equals('artboard-a');
    check(settings.artboards.first.rulerOrigin!).deepEquals([8000, 8100]);
    check(settings.artboards[1].rulerOrigin).isNull();
    check(settings.artboards.first.bounds.top).equals(100);
    check(settings.textRulerOrigins).length.equals(1);
    check(settings.textRulerOrigins.single.coordinates).deepEquals([8191, 8191]);
    check(settings.textRulerOrigins.single.entry).identicalTo(settings.textRulerOrigins.single.document['RulerOrigin']!);
    check(settings.artboards.clear).throws<UnsupportedError>();
    check(settings.textRulerOrigins.single.coordinates.clear).throws<UnsupportedError>();
    check(settings.documents.first['NotRecorded']!.container!['Future']!.text()).equals('opaque');
  });

  test('ignores embedded and non-header declarations and does not select branches', () {
    final AiNativeDocumentSettings settings = _settings(
      header: '%%BeginDocument: foreign.eps\n%AI5_RulerUnits: 42\n%%EndComments\n{\n%%EndDocument\n%AI5_RulerUnits: 99\n}\n0 0 m N\n%%EndDocument\n%AI5_RulerUnits: 2',
      setup: '%AI5_RulerUnits: 3',
      body: '%AI5_RulerUnits: 4',
    );
    check(settings.rulerUnitCode).equals(2);
    check(_settings(header: '%AI5_RulerUnits: 2\n%%Page: 1 1\n%AI5_RulerUnits: 3').rulerUnitCode).equals(2);
    for (final String header in [
      '%AI5_RulerUnits: 2\n%AI5_RulerUnits: 2',
      '%AI17_Begin_Content_if_version_gt:24 4\n%AI5_RulerUnits: 1\n%AI17_End_Versioned_Content',
    ]) {
      check(() => _settings(header: header)).throws<UnsupportedError>();
    }
    check(() => _settings(header: '%AI17_Begin_Content_if_version_gt:24 4')).throws<FormatException>();
    check(() => _settings(header: '%AI17_End_Versioned_Content')).throws<FormatException>();
    check(() => _settings(header: '%AI17_Begin_Content_if_version_gt:24 4\n%AI18_End_Versioned_Content\n%AI5_RulerUnits: 1')).throws<FormatException>();
    check(() => _settings(header: '%AI17_Alternate_Content\n%AI5_RulerUnits: 1')).throws<FormatException>();
    check(
      () => _settings(header: '%AI17_Begin_Content_if_version_gt:24 4\n%AI17_Alternate_Content\n%AI17_Alternate_Content\n%AI17_End_Versioned_Content'),
    ).throws<FormatException>();
  });

  test('rejects malformed settings and optional artboard metadata explicitly', () {
    for (final String header in [
      '%AI5_RulerUnits: -1',
      '%AI5_RulerUnits: 0.5',
      '%AI5_RulerUnits:',
      '%AI24_LargeCanvasScale: 0',
      '%AI24_LargeCanvasScale: NaN',
      '%AI24_LargeCanvasScale: 1e99',
      '%%Canvassize: -1',
      '%%PageOrigin: 1',
      '%AI3_TemplateBox: 1 2 3',
    ]) {
      check(() => _settings(header: header)).throws<FormatException>();
    }
    for (final String setup in [
      _document.replaceFirst('8000 8100 /RealPoint', '8000 /RealPoint'),
      _document.replaceFirst('1 /Bool (IsArtboardSelected)', '2 /Bool (IsArtboardSelected)'),
      _document.replaceFirst('(artboard-a) /String (ArtboardUUID)', '2 /Int (ArtboardUUID)'),
      '%_/Document : 2 /Recorded , ;',
      _text.replaceFirst('8191 8191', '8191'),
    ]) {
      check(() => _settings(setup: setup)).throws<FormatException>();
    }
    check(() => _settings(setup: _document, limits: const AiNativeLimits(maxTokens: 10))).throws<AiLimitException>();
    check(
      () => _settings(
        header: '%AI17_Begin_Content_if_version_gt:24 4\n%AI17_Begin_Content_if_version_gt:24 4\n%AI17_End_Versioned_Content\n%AI17_End_Versioned_Content',
        limits: const AiNativeLimits(maxDepth: 1),
      ),
    ).throws<AiLimitException>();
  });
}
