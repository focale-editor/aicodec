import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_identity_lifecycle_test.dart' show identityLifecycleSource;

/// Encodes a native XML node with explicit owned children and attributes.
String referenceXml(String name, {int kind = 1, String value = '() /String', String children = '', String attributes = ''}) =>
    '/XMLNode : $kind /Int (xmlnode-nodetype) , ($name) /String (xmlnode-nodename) , '
    '$value (xmlnode-nodevalue) , /Array : $children ; (xmlnode-children) , '
    '/Dictionary : $attributes ; (xmlnode-attributes) , ;';

/// Provides a bounded ICC-header envelope for the synthetic preservation tests.
String get referenceProfile {
  final Uint8List bytes = Uint8List(132);
  ByteData.sublistView(bytes).setUint32(0, bytes.length);
  bytes.setRange(36, 40, latin1.encode('acsp'));
  final String encoded = latin1.decode(PdfFilters.encodeAscii85(bytes: bytes));
  return '/Binary : /ASCII85Decode ,\n%$encoded\n; (AI12 Document Profile Data) ,\n132 /Int (AI12 Document Profile Size) ,';
}

/// Supplies recorded metadata whose names intentionally equal an artwork ID.
String get referenceDocument {
  final String variables = referenceXml('variableSet', children: '${referenceXml('variables')} , ${referenceXml('v:sampleDataSets')} ,');
  final String variableSets = referenceXml('variableSets', children: '$variables ,');
  final String bounds = referenceXml('sliceSourceBounds', attributes: '${referenceXml('x', kind: 2, value: '0 /Real')} (x) ,');
  final String slices = referenceXml('sfw', children: '${referenceXml('slices')} , $bounds ,');
  final String metadata = referenceXml('metadata', children: '$variableSets , $slices ,');
  final String xml = referenceXml('#document', kind: 9, children: '$metadata ,');
  return '''/Document :
/Dictionary :
16383 /Int (AIDocumentCanvasSize) ,
0 /Int (CropAreaActive) ,
/Array : /Dictionary :
(Board) /UnicodeString (Name) , 1 /Real (PAR) ,
0 0 /RealPoint (RulerOrigin) , 0 0 /RealPointRelToROrigin (PositionPoint1) ,
100 -100 /RealPointRelToROrigin (PositionPoint2) ,
(board-id) /String (ArtboardUUID) , 1 /Bool (IsArtboardSelected) ,
0 /Int (DisplayMark) , 1 /Bool (IsArtboardDefaultName) ,
; , ; (ArtboardArray) ,
/Dictionary : ; (DocumentDict/ExportableAssetsKey) ,
/Dictionary : /Array : ; (SelHatDocLocalNamesArray) , /Array : ; (SelHatDocInterIDsArray) , ; (SelHatDocTableDict) ,
/Dictionary : 4 /Int (colr) , 72 /Int (dpi.) , 0 /Bool (spot) , ; (AI Auto Rasterize) ,
$xml (#document) ,
; /Recorded ,
/Dictionary : /NotRecorded ,
$referenceProfile
1 /Int (LastArtboardID) ,
/Dictionary : /NotRecorded , 0 /Int (/attributes/inklst.count) , ; (AI11 Ink List Dict) ,
/Dictionary : /NotRecorded , (path_a) /UnicodeString (/attributes/AI12PDF_Description) , ; (PDFPresetCollection) ,
/Dictionary : /NotRecorded , () /String (/attributes/job.pagerange) , 1 /Int (/attributes/job.printall) , ; (AI11 Print JobInfo Dict) ,
/Dictionary : /NotRecorded , () /String (/attributes/rdrs.custom) , (path_a) /UnicodeString (/attributes/job.name) , ; (AI11 Print Attribute Dict) ,
; /NotRecorded ,
;''';
}

/// Keeps known document records separate from identified nested artwork.
String get referenceScopeSource => identityLifecycleSource.replaceFirst('%%EndSetup', '%AI9_BeginDocumentData\n$referenceDocument\n%AI9_EndDocumentData\n%%EndSetup');

/// Decodes one immutable document with caller-controlled parsing ceilings.
AiNativeLayers _model(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
    ),
  ),
);

/// Reads an exact document source rather than a normalized reserialization.
List<int> _documentBytes(AiNativeLayers model) {
  final AiNativeContainer document = model.drawing.records.roots.singleWhere((record) => record.type == 'Document');
  return model.drawing.records.program.bytes.sublist(document.start, document.end);
}

/// Exercises ordinary metadata, rejected references, section ownership and limits.
void main() {
  test('deletes identified paths, groups and layers beside qualified document settings', () {
    final AiNativeLayers model = _model(referenceScopeSource);
    for (final AiNativeLayers result in [
      AiNativeLayers.decode(drawing: model.drawing.removePaths(paths: [model.drawing.paths.first])),
      AiNativeLayers.decode(drawing: model.drawing.removeGroups(groups: model.drawing.groups)),
      model.remove(layers: [model.layers.first], discardViewState: true),
    ]) {
      check(_documentBytes(result)).deepEquals(_documentBytes(model));
      check(result.drawing.records.artboards.single.nameBytes).deepEquals(latin1.encode('Board'));
      check(latin1.decode(result.drawing.records.program.bytes)).contains('(path_a) /UnicodeString (/attributes/AI12PDF_Description)');
    }
    check(latin1.decode(model.drawing.records.program.bytes)).equals(referenceScopeSource);
  });

  test('preserves an empty document and independent multiple document owners', () {
    final AiNativeLayers empty = _model(identityLifecycleSource.replaceFirst('%%EndSetup', '/Document : ;\n%%EndSetup'));
    check(empty.remove(layers: [empty.layers.first], discardViewState: true).layers).length.equals(2);
    final AiNativeLayers multiple = _model(referenceScopeSource.replaceFirst('%%EndSetup', '/Document : /Dictionary : 1 /Bool (AI9 paper simulation) , ; /Recorded , ;\n%%EndSetup'));
    final AiNativeDrawing result = multiple.drawing.removePaths(paths: [multiple.drawing.paths.first]);
    check(result.records.roots.where((record) => record.type == 'Document')).length.equals(2);
  });

  test('rejects unknown scalar, nested, binary and misplaced document fields', () {
    for (final String payload in [
      '/Dictionary : 0 /Int (FutureOwner) , ; /Recorded ,',
      '/Dictionary : (path_a) /String (FutureReference) , ; /Recorded ,',
      '/Dictionary : /XMLUID : (path_a) ; (FutureReference) , ; /Recorded ,',
      '/Dictionary : (path_a) /String (AIDocumentCanvasSize) , ; /Recorded ,',
      '/Dictionary : $referenceProfile ; /Recorded ,',
      '/Dictionary : 1 /Int (AIDocumentCanvasSize) , ; /NotRecorded ,',
      '/Dictionary : /Dictionary : (path_a) /String (/attributes/FutureReference) , ; (PDFPresetCollection) , ; /NotRecorded ,',
    ]) {
      final String input = referenceScopeSource.replaceFirst(referenceDocument, '/Document : $payload ;');
      final AiNativeLayers source = _model(input);
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<UnsupportedError>();
      check(latin1.decode(source.drawing.records.program.bytes)).equals(input);
    }
  });

  test('rejects nonempty asset, selection and ink reference tables atomically', () {
    for (final String input in [
      referenceScopeSource.replaceFirst('/Dictionary : ; (DocumentDict/ExportableAssetsKey)', '/Dictionary : (path_a) /String (Target) , ; (DocumentDict/ExportableAssetsKey)'),
      referenceScopeSource.replaceFirst('/Array : ; (SelHatDocLocalNamesArray)', '/Array : (path_a) /String , ; (SelHatDocLocalNamesArray)'),
      referenceScopeSource.replaceFirst('/Array : ; (SelHatDocInterIDsArray)', '/Array : 1 /Int , ; (SelHatDocInterIDsArray)'),
      referenceScopeSource.replaceFirst('0 /Int (/attributes/inklst.count)', '1 /Int (/attributes/inklst.count)'),
    ]) {
      final AiNativeLayers source = _model(input);
      check(() => source.remove(layers: [source.layers.first, source.layers[2]], discardViewState: true)).throws<UnsupportedError>();
      check(latin1.decode(source.drawing.records.program.bytes)).equals(input);
    }
  });

  test('rejects variables, data sets, slices, unknown XML and implicit textual links', () {
    for (final String name in ['variables', 'v:sampleDataSets', 'slices']) {
      final String original = referenceXml(name);
      for (final String replacement in [referenceXml(name, children: '${referenceXml('reference')} ,'), referenceXml(name, value: '(path_a) /String')]) {
        final AiNativeLayers source = _model(referenceScopeSource.replaceFirst(original, replacement));
        check(() => source.drawing.removeGroups(groups: source.drawing.groups)).throws<UnsupportedError>();
      }
    }
    for (final String replacement in [
      referenceXml('unknown'),
      referenceXml('variables', kind: 2),
      referenceXml('variables', attributes: '${referenceXml('target', kind: 2, value: '(path_a) /String')} (target) ,'),
    ]) {
      final AiNativeLayers source = _model(referenceScopeSource.replaceFirst(referenceXml('variables'), replacement));
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<UnsupportedError>();
    }
  });

  test('rejects repeated fields and additional source ownership at every level', () {
    check(() => _model(referenceScopeSource.replaceFirst('16383 /Int (AIDocumentCanvasSize)', '10 /Int (AIDocumentCanvasSize) , 16383 /Int (AIDocumentCanvasSize)'))).throws<FormatException>();
    for (final String input in [
      referenceScopeSource.replaceFirst('1 /Int (LastArtboardID)', '/NotRecorded , 1 /Int (LastArtboardID)'),
      referenceScopeSource.replaceFirst('(board-id) /String (ArtboardUUID)', '(path_a) /String (Target) , (board-id) /String (ArtboardUUID)'),
      referenceScopeSource.replaceFirst(referenceXml('variables'), '${referenceXml('variables')} , ${referenceXml('variables')}'),
    ]) {
      final AiNativeLayers source = _model(input);
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<UnsupportedError>();
    }
  });

  test('rejects malformed profile ownership, size and ICC signatures', () {
    for (final String profile in [
      '132 /Int (AI12 Document Profile Size) ,',
      referenceProfile.replaceFirst('132 /Int (AI12 Document Profile Size) ,', ''),
      referenceProfile.replaceFirst('132 /Int', '131 /Int'),
      '/Binary : /ASCII85Decode ,\n%z~>\n; (AI12 Document Profile Data) , 4 /Int (AI12 Document Profile Size) ,',
    ]) {
      final AiNativeLayers source = _model(referenceScopeSource.replaceFirst(referenceProfile, profile));
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<FormatException>();
    }
  });

  test('rejects opaque comments, conditional records and executable custom screening', () {
    for (final String input in [
      referenceScopeSource.replaceFirst('16383 /Int', '%AI99_Reference: path_a\n16383 /Int'),
      referenceScopeSource.replaceFirst('; (AI12 Document Profile Data)', '%AI99_Reference: path_a\n; (AI12 Document Profile Data)'),
      referenceScopeSource.replaceFirst(referenceDocument, '%AI17_Begin_Content_if_version_gt:24 4\n$referenceDocument\n%AI17_End_Versioned_Content'),
      referenceScopeSource.replaceFirst('() /String (/attributes/rdrs.custom)', '(path_a load) /String (/attributes/rdrs.custom)'),
    ]) {
      final AiNativeLayers source = _model(input);
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<UnsupportedError>();
    }
  });

  test('qualifies known header alternatives and the exact standard page trailer', () {
    final String input = referenceScopeSource
        .replaceFirst('%%EndComments', '%AI17_Begin_Content_if_version_gt:24 4\n%AI24_LargeCanvasScale: 1\n%AI17_Alternate_Content\n%AI5_RulerUnits: 2\n%AI17_End_Versioned_Content\n%%EndComments')
        .replaceFirst('%%Trailer', '%%PageTrailer\ngsave annotatepage grestore showpage\n%%Trailer');
    final AiNativeLayers source = _model(input);
    final AiNativeDrawing result = source.drawing.removePaths(paths: [source.drawing.paths.first]);
    check(latin1.decode(result.records.program.bytes)).contains('gsave annotatepage grestore showpage');
    check(AiNativeVersions.decode(records: result.records).blocks).length.equals(1);
  });

  test('rejects unknown metadata and executable source outside the qualified records', () {
    for (final String input in [
      referenceScopeSource.replaceFirst('%%EndComments', '%AI99_Ref: path_a\n%%EndComments'),
      referenceScopeSource.replaceFirst('%%EndSetup', '(path_a) load\n%%EndSetup'),
      referenceScopeSource.replaceFirst('%%EOF', 'gsave path_a grestore showpage\n%%EOF'),
      referenceScopeSource.replaceFirst('%%EOF', 'gsave annotatepage grestore showpage showpage\n%%EOF'),
      referenceScopeSource.replaceFirst('%%EndSetup', '%AI5_RulerUnits: 2\n%%EndSetup'),
      referenceScopeSource.replaceFirst('%%EndComments', '%AI17_Begin_Content_if_version_gt:24 4\n%AI99_Ref: path_a\n%AI17_End_Versioned_Content\n%%EndComments'),
    ]) {
      final AiNativeLayers source = _model(input);
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<UnsupportedError>();
    }
  });

  test('bounds header retokenization and rejects malformed known declarations', () {
    final String input = referenceScopeSource.replaceFirst('%%EndComments', '%%RGBProcessColor: ${List.filled(2000, '0').join(' ')}\n%%EndComments');
    final AiNativeLayers source = _model(input, limits: const AiNativeLimits(maxTokens: 1500));
    check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<AiLimitException>();
    for (final String header in ['%AI5_ArtSize: 1', '%AI7_GridSettings: nan', '%AI10_OpenToVie: 1 2']) {
      final AiNativeLayers source = _model(referenceScopeSource.replaceFirst('%%EndComments', '$header\n%%EndComments'));
      check(() => source.drawing.removePaths(paths: [source.drawing.paths.first])).throws<FormatException>();
    }
  });
}
