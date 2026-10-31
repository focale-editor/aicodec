import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_reference_resources_test.dart' show referenceResourcesSource;

/// Builds a distinct native rectangle, selection flag and ruler origin per board.
String artboardRecord(int index, {bool selected = false}) =>
    '''%_/Dictionary :
%_(Board $index) /UnicodeString (Name) ,
%_${index * 200} 100 /RealPointRelToROrigin (PositionPoint1) ,
%_${index * 200 + 100} 0 /RealPointRelToROrigin (PositionPoint2) ,
%_${8000 + index * 200} 8100 /RealPoint (RulerOrigin) ,
%_(board-$index) /String (ArtboardUUID) ,
%_${selected ? 1 : 0} /Bool (IsArtboardSelected) ,
%_; ,
''';

/// Keeps active, selected, crop, drawing and creation-history values independent.
String artboardSource({String body = '', String extra = '', bool active = true}) =>
    '''%!PS-Adobe-3.0
%%BoundingBox: 10 -20 30 -10
%AI3_Cropmarks: 400 0 500 100
%%EndComments
%%BeginProlog
%%EndProlog
%%BeginSetup
%_/Document : /Dictionary : /Array :
${artboardRecord(0, selected: true)}${artboardRecord(1)}${artboardRecord(2)}%_; (ArtboardArray) ,
${active ? '%_2 /Int (CropAreaActive) ,\n' : ''}%_; /Recorded ,
%_/Dictionary : /NotRecorded ,
%_67 /Int (LastArtboardID) ,
%_; /NotRecorded , ;
$extra
%%EndSetup
$body
%%Trailer
%%EOF
''';

/// Parses native data directly, without supplying or generating a PDF preview.
AiNativeArtboards artboardModel(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeArtboards.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Adds separate artboard metadata beside complete CC pairs and shared resources.
String mixedArtboardSource() {
  final String text = artboardSource();
  final String document = text.substring(text.indexOf('%_/Document'), text.indexOf('%%EndSetup'));
  return referenceResourcesSource().replaceFirst('%%EndComments', '%AI3_Cropmarks: 400 0 500 100\n%%EndComments').replaceFirst('%%EndSetup', '$document\n%%EndSetup');
}

/// Checks source ownership and explicit geometry edits before structural saves.
void main() {
  test('distinguishes active selection crop and creation history without defaults', () {
    final AiNativeArtboards model = artboardModel(artboardSource());
    check(model.artboards).length.equals(3);
    check(model.activeIndex).equals(2);
    check(model.activeArtboard).identicalTo(model.artboards.last);
    check(model.selectedArtboards).deepEquals([model.artboards.first]);
    check(model.lastArtboardId).equals(67);
    check(model.cropBounds!.left).equals(400);
    check(model.artboards.first.bounds.left).equals(0);
    check(model.artboards.clear).throws<UnsupportedError>();
    check(() => model.selectedArtboards.clear()).throws<UnsupportedError>();
    final AiNativeArtboards absent = artboardModel(artboardSource(active: false).replaceFirst('%AI3_Cropmarks: 400 0 500 100', ''));
    check(absent.activeIndex).isNull();
    check(absent.activeArtboard).isNull();
    check(absent.cropBounds).isNull();
    check(absent.selectedArtboards).length.equals(1);
  });

  test('requires explicit document ownership when several arrays coexist', () {
    final String text = artboardSource();
    final String document = text.substring(text.indexOf('%_/Document'), text.indexOf('%%EndSetup'));
    final AiNativeRecords records = AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(text.replaceFirst('%%EndSetup', '$document\n%%EndSetup'))));
    check(() => AiNativeArtboards.decode(records: records)).throws<ArgumentError>();
    final AiNativeArtboards second = AiNativeArtboards.decode(records: records, document: records.roots.last);
    check(second.document).identicalTo(records.roots.last);
    check(second.artboards.every((board) => identical(board.document, records.roots.last))).isTrue();
    check(() => AiNativeArtboards.decode(records: records, document: artboardModel(text).document)).throws<ArgumentError>();
  });

  test('resizes one native rectangle while retaining exact other source bytes', () {
    final String source = artboardSource();
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboards result = model.resize(artboard: model.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -40, right: 150, top: 120), cropBounds: null);
    check(
      latin1.decode(result.records.program.bytes),
    ).equals(source.replaceFirst('0 100 /RealPointRelToROrigin', '${-20.0} ${120.0} /RealPointRelToROrigin').replaceFirst('100 0 /RealPointRelToROrigin', '${150.0} ${-40.0} /RealPointRelToROrigin'));
    check(latin1.decode(model.records.program.bytes)).equals(source);
    check(result.activeIndex).equals(2);
    check(result.selectedArtboards.single.index).equals(0);
    check(result.lastArtboardId).equals(67);
    check(result.cropBounds!.left).equals(400);
    check(result.artboards.first.rulerOrigin!).deepEquals([8000.0, 8100.0]);
    check(result.resize(artboard: result.artboards.first, bounds: result.artboards.first.bounds, cropBounds: null)).identicalTo(result);
  });

  test('accepts explicit independent crop and ruler coordinates without moving artwork', () {
    final AiNativeArtboards model = artboardModel(artboardSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f'));
    final AiNativeArtboards result = model.resize(
      artboard: model.artboards[1],
      bounds: AiBoundingBox(left: 220, bottom: -30, right: 350, top: 130),
      cropBounds: AiBoundingBox(left: 1, bottom: 2, right: 3, top: 4),
      rulerOrigin: [8220, 8070],
    );
    final String text = latin1.decode(result.records.program.bytes);
    check(text).contains('%AI3_Cropmarks: ${1.0} ${2.0} ${3.0} ${4.0}');
    check(text).contains('%%BoundingBox: 10 -20 30 -10');
    check(text).contains('0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f');
    check(result.artboards[1].rulerOrigin!).deepEquals([8220.0, 8070.0]);
    check(result.activeIndex).equals(2);
  });

  test('rejects stale and foreign boards and undefined coordinate policies atomically', () {
    final String text = artboardSource();
    final AiNativeArtboards model = artboardModel(text);
    final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: 0, right: 200, top: 200);
    final AiNativeArtboards changed = model.resize(artboard: model.artboards.first, bounds: bounds, cropBounds: null);
    check(() => changed.resize(artboard: model.artboards.first, bounds: bounds, cropBounds: null)).throws<ArgumentError>();
    check(() => model.resize(artboard: artboardModel(text).artboards.first, bounds: bounds, cropBounds: null)).throws<ArgumentError>();
    for (final List<double> origin in [
      [1.0],
      [1, double.nan],
      [1, 1e20],
    ]) {
      check(() => model.resize(artboard: model.artboards.first, bounds: bounds, cropBounds: null, rulerOrigin: origin)).throws<ArgumentError>();
    }
    for (final AiBoundingBox invalid in [AiBoundingBox(left: 0, bottom: 0, right: 0, top: 2), AiBoundingBox(left: 0, bottom: 0, right: 1e20, top: 2)]) {
      check(() => model.resize(artboard: model.artboards.first, bounds: invalid, cropBounds: null)).throws<ArgumentError>();
    }
    check(latin1.decode(model.records.program.bytes)).equals(text);
  });

  test('rejects malformed active indices creation history and conditional crop state', () {
    final String text = artboardSource();
    for (final String replacement in ['-1 /Int', '3 /Int', '1.5 /Int', '1 /Real']) {
      check(() => artboardModel(text.replaceFirst('2 /Int (CropAreaActive)', '$replacement (CropAreaActive)'))).throws<FormatException>();
    }
    check(() => artboardModel(text.replaceFirst('67 /Int (LastArtboardID)', '-1 /Int (LastArtboardID)'))).throws<FormatException>();
    for (final String crop in ['%AI3_Cropmarks: 1 2 3', '%AI3_Cropmarks: 4 2 3 1', '%AI3_Cropmarks: 0 0 NaN 100']) {
      check(() => artboardModel(text.replaceFirst('%AI3_Cropmarks: 400 0 500 100', crop))).throws<FormatException>();
    }
    for (final String crop in ['%AI3_Cropmarks: 0 0 100 100\n%AI3_Cropmarks: 0 0 200 200', '%AI17_Begin_Content_if_version_gt:24 4\n%AI3_Cropmarks: 0 0 100 100\n%AI17_End_Versioned_Content']) {
      check(() => artboardModel(text.replaceFirst('%AI3_Cropmarks: 400 0 500 100', crop))).throws<UnsupportedError>();
    }
  });

  test('refuses unknown native dependencies and missing optional fields when requested', () {
    final AiBoundingBox bounds = AiBoundingBox(left: 0, bottom: 0, right: 200, top: 200);
    for (final String text in [
      artboardSource(extra: '%_/FutureReference : (board-0) /Ref , ;'),
      artboardSource().replaceFirst('%_; /Recorded', '%_(cached) /String (FutureBounds) ,\n%_; /Recorded'),
    ]) {
      final AiNativeArtboards model = artboardModel(text);
      check(() => model.resize(artboard: model.artboards.first, bounds: bounds, cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(model.records.program.bytes)).equals(text);
    }
    final AiNativeArtboards absent = artboardModel(artboardSource().replaceFirst('%AI3_Cropmarks: 400 0 500 100', '').replaceFirst('%_8000 8100 /RealPoint (RulerOrigin) ,', ''));
    check(() => absent.resize(artboard: absent.artboards.first, bounds: bounds, cropBounds: bounds)).throws<UnsupportedError>();
    check(() => absent.resize(artboard: absent.artboards.first, bounds: bounds, cropBounds: null, rulerOrigin: [1, 2])).throws<UnsupportedError>();
  });

  test('retains original byte limits and rejects conditional document ownership', () {
    final String text = artboardSource();
    final AiNativeArtboards limited = artboardModel(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    final AiBoundingBox bounds = AiBoundingBox(left: -1000, bottom: -1000, right: 1000, top: 1000);
    check(() => limited.resize(artboard: limited.artboards.first, bounds: bounds, cropBounds: null)).throws<FormatException>();
    final AiNativeArtboards conditional = artboardModel(
      text.replaceFirst('%_/Document', '%AI17_Begin_Content_if_version_gt:24 4\n%_/Document').replaceFirst('%%EndSetup', '%AI17_End_Versioned_Content\n%%EndSetup'),
    );
    check(() => conditional.resize(artboard: conditional.artboards.first, bounds: bounds, cropBounds: null)).throws<UnsupportedError>();
  });

  test('retains complete CC pairs layers and shared resources during a board resize', () {
    final AiNativeArtboards model = artboardModel(mixedArtboardSource());
    final AiNativeArtboards result = model.resize(artboard: model.artboards[1], bounds: AiBoundingBox(left: 190, bottom: -20, right: 350, top: 120), cropBounds: null);
    final AiProgram before = model.records.program;
    final AiProgram after = result.records.program;
    check(after.bytes.sublist(after.bodyStart)).deepEquals(before.bytes.sublist(before.bodyStart));
    check(after.bytes.sublist(0, result.document.start)).deepEquals(before.bytes.sublist(0, model.document.start));
    check(AiNativeDrawing.decode(records: result.records).liveShapes).length.equals(2);
    check(AiNativeGradientResources.decode(records: result.records).definitions).length.equals(2);
  });
}
