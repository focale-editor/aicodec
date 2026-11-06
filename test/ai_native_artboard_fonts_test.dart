import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;
import 'ai_native_objects_test.dart' show objectDictionary;

/// A font and gradient deliberately sharing an artboard's independent name.
const String artboardFontSetup = '''[39/quotesingle 96/grave 254/last/lastest TE
%AI55J_Tsume: None
%AI3_BeginEncoding: _board-0 board-0
[/_board-0/board-0 0 0 1 TZ
%AI3_EndEncoding AdobeType
1 Bn
%AI5_BeginGradient: (board-0)
(board-0) 0 2 Bd
[
1 0 50 100 Bs
0 0 50 0 Bs
BD
%AI5_EndGradient
''';

/// Adds font inventories without interpreting their names as artwork identifiers.
String artboardFontSource({String setup = artboardFontSetup, String body = ''}) => artboardSource(extra: setup, body: body).replaceFirst(
  '%%EndComments',
  '%%DocumentFonts: board-0\n%%DocumentNeededFonts: board-0\n%%EndComments',
);

/// Requires every byte outside the selected Document record to remain unchanged.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.sublist(0, after.document.start)).deepEquals(before.records.program.bytes.sublist(0, before.document.start));
  check(after.records.program.bytes.sublist(after.document.end)).deepEquals(before.records.program.bytes.sublist(before.document.end));
}

/// Checks mark-based font ownership independently from artboard and gradient IDs.
void main() {
  test('retains font encodings and counted gradients through all artboard edits', () {
    final AiNativeArtboards before = artboardModel(artboardFontSource());
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -10, bottom: -20, right: 500, top: 800), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
      check(AiNativeGradientResources.decode(records: after.records).definitions).length.equals(1);
    }
  });

  test('retains explicit glyph runs direction script and multiple-master weights', () {
    for (final String operands in [
      '/_board-0/board-0 0 1',
      '12/a/b 19/c /_board-0/board-0 0 0 1',
      '/_board-0/board-0 1 25 0',
      '/_board-0/board-0 0 0 1 [0.25 0.75]',
      '12/a/b /_board-0/board-0 0 1 [0.25 0.75]',
    ]) {
      final String source = artboardFontSource(setup: artboardFontSetup.replaceFirst('/_board-0/board-0 0 0 1', operands));
      final AiNativeArtboards before = artboardModel(source);
      _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    }
  });

  test('retains standalone font marks without a gradient bank', () {
    for (final String setup in ['[ TE', artboardFontSetup.substring(0, artboardFontSetup.indexOf('1 Bn')).replaceFirst('AdobeType', 'TrueType')]) {
      final AiNativeArtboards before = artboardModel(artboardFontSource(setup: setup));
      _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    }
  });

  test('rejects malformed encoding runs flags weights and immediate name lookup', () {
    final String source = artboardFontSource();
    for (final String changed in [
      for (final String glyphs in ['256/a', '-1/a', '1.5/a', '255/a/b', '1 2/a', '1/a 3', '/a', '1//lookup', '1/']) source.replaceFirst('39/quotesingle 96/grave 254/last/lastest', glyphs),
      for (final String flags in ['0', '0 0 0 1', '2 0 1', '0 99 1', '0 0 2', '0 0.5 1', '0 0 1 []', '0 0 1 [1.1]', '0 0 1 [/lookup]']) source.replaceFirst('0 0 1 TZ', '$flags TZ'),
      source.replaceFirst('/_board-0/board-0', '//_board-0/board-0'),
    ]) {
      final AiNativeArtboards before = artboardModel(changed);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
      check(latin1.decode(before.records.program.bytes)).equals(changed);
    }
  });

  test('refuses unknown wrappers conditional ownership and hidden metadata', () {
    final String source = artboardFontSource();
    for (final String changed in [
      source.replaceFirst('%AI3_BeginEncoding: _board-0 board-0', '%AI3_BeginEncoding: _other board-0'),
      source.replaceFirst('%AI3_EndEncoding AdobeType', ''),
      source.replaceFirst('%AI3_EndEncoding AdobeType', '%AI3_EndEncoding FutureType'),
      source.replaceFirst('[/_board-0', '%AI17_Begin_Content_if_version_gt:24 4\n[/_board-0').replaceFirst('TZ', 'TZ\n%AI17_End_Versioned_Content'),
      source.replaceFirst('96/grave', '96/grave\n%AI24_Unknown: board-0\n'),
      source.replaceFirst('[/_board-0/board-0 0 0 1 TZ', '%_[/_board-0/board-0 0 0 1 TZ'),
      source.replaceFirst('%AI55J_Tsume: None', '%AI55J_Tsume: board-0'),
      source.replaceFirst('%%DocumentFonts: board-0', '%%DocumentFonts: (atend)'),
    ]) {
      final AiNativeArtboards before = artboardModel(changed);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(changed);
    }
  });

  test('does not treat arrays procedures and executable setup as font declarations', () {
    final String source = artboardFontSource();
    for (final String changed in [
      source.replaceFirst('[39/quotesingle 96/grave 254/last/lastest TE', '[39/quotesingle] TE'),
      source.replaceFirst('39/quotesingle', '39/quotesingle load'),
      source.replaceFirst('[39/quotesingle', '{ [39/quotesingle').replaceFirst('TE\n', 'TE } exec\n'),
      source.replaceFirst('1 Bn', '[1 Bn').replaceFirst('%AI5_EndGradient', '%AI5_EndGradient\n] pop'),
    ]) {
      final AiNativeArtboards before = artboardModel(changed);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(changed);
    }
  });

  test('keeps font and gradient names separate from deleted artwork identities', () {
    final String source = artboardFontSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f\n${objectDictionary(identifier: 'board-0')}');
    final AiNativeArtboards before = artboardModel(source);
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: before.records);
    final AiNativeDrawing removed = drawing.removePaths(paths: drawing.paths);
    check(removed.paths).isEmpty();
    check(removed.records.program.bytes.take(removed.records.program.bodyStart)).deepEquals(drawing.records.program.bytes.take(drawing.records.program.bodyStart));
    final AiNativeDrawing unknown = AiNativeDrawing.decode(records: artboardModel(source.replaceFirst('96/grave', '96/grave\n%AI99_Reference: board-0\n')).records);
    check(() => unknown.removePaths(paths: unknown.paths)).throws<UnsupportedError>();
  });
}
