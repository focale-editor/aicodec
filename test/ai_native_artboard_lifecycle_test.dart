import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboards_test.dart';

/// Supplies geometry, an independent ruler origin and a host-allocated UUID.
AiNativeArtboardDefinition newArtboard({bool selected = false}) => AiNativeArtboardDefinition(
  nameBytes: latin1.encode('New (board)\\'),
  identifierBytes: latin1.encode('b9ef2db5-64d8-49a5-b02e-b455c61a1f27'),
  bounds: AiBoundingBox(left: -300, bottom: -20, right: -100, top: 180),
  rulerOrigin: [7650, 8000],
  selected: selected,
);

/// Reads exact source text for structural preservation assertions.
String artboardText(AiNativeArtboards model) => latin1.decode(model.records.program.bytes);

/// Verifies native artboard lifecycle independently of host PDF serialization.
void main() {
  test('reorders exact dictionaries and follows the active identity independently of selection', () {
    final String source = artboardSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f');
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboards result = model.reorder(artboards: [model.artboards[2], model.artboards[0], model.artboards[1]], cropBounds: null);
    check(artboardText(result)).equals(
      source
          .replaceFirst('${artboardRecord(0, selected: true)}${artboardRecord(1)}${artboardRecord(2)}', '${artboardRecord(2)}${artboardRecord(0, selected: true)}${artboardRecord(1)}')
          .replaceFirst('2 /Int (CropAreaActive)', '0 /Int (CropAreaActive)'),
    );
    check(result.activeArtboard!.identifier).equals('board-2');
    check(result.selectedArtboards.single.identifier).equals('board-0');
    check(result.lastArtboardId).equals(67);
    check(result.cropBounds!.left).equals(400);
    check(artboardText(model)).equals(source);
    check(result.reorder(artboards: result.artboards, cropBounds: null)).identicalTo(result);
  });

  test('removes several boards with an explicit retained active replacement', () {
    final String source = artboardSource();
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboards result = model.remove(artboards: [model.artboards[2], model.artboards[0]], activeArtboard: model.artboards[1], cropBounds: null);
    check(artboardText(result))
        .equals(source.replaceFirst(artboardRecord(0, selected: true), '').replaceFirst(artboardRecord(2), '').replaceFirst('2 /Int (CropAreaActive)', '0 /Int (CropAreaActive)'));
    check(result.activeArtboard!.identifier).equals('board-1');
    check(result.selectedArtboards).isEmpty();
    check(result.lastArtboardId).equals(67);
    check(result.cropBounds!.left).equals(400);
    final AiNativeArtboards shifted = model.remove(artboards: [model.artboards.first], activeArtboard: null, cropBounds: null);
    check(shifted.activeIndex).equals(1);
    check(shifted.activeArtboard!.identifier).equals('board-2');
    check(model.remove(artboards: [], activeArtboard: null, cropBounds: null)).identicalTo(model);
  });

  test('creates fresh metadata and updates only an explicitly supplied creation counter', () {
    final AiNativeArtboards model = artboardModel(artboardSource());
    final AiNativeArtboardDefinition definition = newArtboard(selected: true);
    for (final int index in [0, 1, 3]) {
      final AiNativeArtboards result = model.create(definition: definition, index: index, lastArtboardId: 72, cropBounds: null);
      check(result.artboards).length.equals(4);
      check(result.lastArtboardId).equals(72);
      check(result.activeArtboard!.identifier).equals('board-2');
      check(result.selectedArtboards.map((board) => board.identifier).toSet()).deepEquals({'board-0', latin1.decode(definition.identifierBytes)});
      final AiNativeArtboard added = result.artboards[index];
      check(added.nameBytes).deepEquals(definition.nameBytes);
      check(added.identifier).equals(latin1.decode(definition.identifierBytes));
      check(added.bounds.left).equals(-300);
      check(added.bounds.top).equals(180);
      check(added.rulerOrigin!).deepEquals([7650.0, 8000.0]);
      check(added.record['PAR']!.number).equals(1);
      check(added.record['DisplayMark']!.number).equals(0);
      check(added.record['IsArtboardDefaultName']!.boolean).equals(false);
      for (final AiNativeArtboard old in model.artboards) {
        final AiNativeArtboard retained = result.artboards.singleWhere((board) => board.identifier == old.identifier);
        check(result.records.program.bytes.sublist(retained.record.start, retained.record.end)).deepEquals(model.records.program.bytes.sublist(old.record.start, old.record.end));
      }
    }
  });

  test('activation and explicit crop changes never imply selection or drawing changes', () {
    final AiNativeArtboards model = artboardModel(artboardSource());
    final AiNativeArtboards result = model.create(
      definition: newArtboard(),
      index: 1,
      lastArtboardId: 68,
      cropBounds: AiBoundingBox(left: -10, bottom: -20, right: 30, top: 40),
      activate: true,
    );
    check(result.activeIndex).equals(1);
    check(result.activeArtboard!.selected).isFalse();
    check(result.selectedArtboards.single.identifier).equals('board-0');
    check(result.cropBounds!.left).equals(-10);
    check(artboardText(result)).contains('%%BoundingBox: 10 -20 30 -10');
  });

  test('keeps absent optional state and can insert the first board into an empty array', () {
    final String source = artboardSource(active: false).replaceFirst('%_67 /Int (LastArtboardID) ,', '');
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboards added = model.create(definition: newArtboard(), index: 3, lastArtboardId: null, cropBounds: null);
    final AiNativeArtboards moved = added.reorder(artboards: added.artboards.reversed.toList(), cropBounds: null);
    final AiNativeArtboards removed = moved.remove(artboards: [moved.artboards.first], activeArtboard: null, cropBounds: null);
    check(removed.activeIndex).isNull();
    check(removed.lastArtboardId).isNull();
    final AiNativeArtboards empty = artboardModel(source.replaceFirst('${artboardRecord(0, selected: true)}${artboardRecord(1)}${artboardRecord(2)}', ''));
    final AiNativeArtboards first = empty.create(definition: newArtboard(), index: 0, lastArtboardId: null, cropBounds: null);
    check(first.artboards).length.equals(1);
    check(first.activeIndex).isNull();
    check(() => model.create(definition: newArtboard(), index: 0, lastArtboardId: null, cropBounds: null, activate: true)).throws<UnsupportedError>();
    check(() => model.create(definition: newArtboard(), index: 0, lastArtboardId: 1, cropBounds: null)).throws<ArgumentError>();
  });

  test('preserves private syntax with inline entries CR CRLF and omitted final comma', () {
    for (final String newline in ['\n', '\r', '\r\n']) {
      final String source = artboardSource()
          .replaceFirst('${artboardRecord(2)}%_; (ArtboardArray)', '${artboardRecord(2).replaceFirst('%_; ,\n', '%_;\n')}%_; (ArtboardArray)')
          .replaceAll('\n', newline);
      final AiNativeArtboards model = artboardModel(source);
      final AiNativeArtboards reordered = model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null);
      check(reordered.artboards.map((board) => board.identifier)).deepEquals(['board-2', 'board-1', 'board-0']);
      final AiNativeArtboards result = reordered.create(definition: newArtboard(), index: 2, lastArtboardId: 68, cropBounds: null);
      final String text = artboardText(result);
      check(text.replaceAll(newline, '').contains('\r')).isFalse();
      check(text.replaceAll(newline, '').contains('\n')).isFalse();
      check(result.artboards[2].nameBytes).deepEquals(newArtboard().nameBytes);
    }
    final String source = artboardSource();
    final String document = source.substring(source.indexOf('%_/Document'), source.indexOf('%%EndSetup'));
    final AiNativeArtboards inline = artboardModel(source.replaceFirst(document, document.replaceAll('\n%_', ' ')));
    check(inline.reorder(artboards: inline.artboards.reversed.toList(), cropBounds: null).activeIndex).equals(0);
  });

  test('rejects foreign stale duplicated and incomplete structural selections atomically', () {
    final String source = artboardSource();
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboard foreign = artboardModel(source).artboards.first;
    for (final List<AiNativeArtboard> invalid in [
      [model.artboards.first],
      [model.artboards.first, model.artboards.first, model.artboards.last],
      [foreign, model.artboards[1], model.artboards[2]],
    ]) {
      check(() => model.reorder(artboards: invalid, cropBounds: null)).throws<ArgumentError>();
    }
    final AiNativeArtboards changed = model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null);
    check(() => changed.remove(artboards: [model.artboards.first], activeArtboard: null, cropBounds: null)).throws<ArgumentError>();
    check(() => model.remove(artboards: [foreign], activeArtboard: null, cropBounds: null)).throws<ArgumentError>();
    check(() => model.remove(artboards: [model.artboards.first, model.artboards.first], activeArtboard: null, cropBounds: null)).throws<ArgumentError>();
    check(() => model.remove(artboards: model.artboards, activeArtboard: null, cropBounds: null)).throws<ArgumentError>();
    check(artboardText(model)).equals(source);
  });

  test('requires an active replacement only when the active source board is removed', () {
    final AiNativeArtboards model = artboardModel(artboardSource());
    check(() => model.remove(artboards: [model.artboards.last], activeArtboard: null, cropBounds: null)).throws<ArgumentError>();
    check(() => model.remove(artboards: [model.artboards.last], activeArtboard: model.artboards.last, cropBounds: null)).throws<ArgumentError>();
    check(() => model.remove(artboards: [model.artboards.first], activeArtboard: model.artboards[1], cropBounds: null)).throws<ArgumentError>();
    final AiNativeArtboards absent = artboardModel(artboardSource(active: false));
    check(() => absent.remove(artboards: [absent.artboards.first], activeArtboard: absent.artboards[1], cropBounds: null)).throws<ArgumentError>();
  });

  test('checks UUID freshness explicit creation history and input ownership', () {
    final AiNativeArtboards model = artboardModel(artboardSource());
    for (final int? invalid in [null, -1, 0, 3, 67, 9007199254740992]) {
      check(() => model.create(definition: newArtboard(), index: 1, lastArtboardId: invalid, cropBounds: null)).throws<ArgumentError>();
    }
    for (final int index in [-1, 4]) {
      check(() => model.create(definition: newArtboard(), index: index, lastArtboardId: 68, cropBounds: null)).throws<RangeError>();
    }
    final AiNativeArtboards added = model.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null);
    check(() => added.create(definition: newArtboard(), index: 0, lastArtboardId: 69, cropBounds: null)).throws<ArgumentError>();
    final AiNativeArtboards duplicate = artboardModel(artboardSource().replaceFirst('(board-1)', '(BOARD-0)'));
    check(() => duplicate.reorder(artboards: duplicate.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    for (final String identity in ['()', '(\\000b\\000o\\000a\\000r\\000d)', '<feff0062>']) {
      final AiNativeArtboards ambiguous = artboardModel(artboardSource().replaceFirst('(board-1)', identity));
      check(() => ambiguous.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('freezes definitions and rejects invalid bytes geometry UUIDs and aspect ratios', () {
    final List<int> name = [65];
    final List<int> identifier = newArtboard().identifierBytes.toList();
    final List<double> origin = [1, 2];
    final AiNativeArtboardDefinition definition = AiNativeArtboardDefinition(nameBytes: name, identifierBytes: identifier, bounds: newArtboard().bounds, rulerOrigin: origin);
    name[0] = 66;
    identifier[0] = 97;
    origin[0] = 3;
    check(definition.nameBytes).deepEquals([65]);
    check(definition.identifierBytes).deepEquals(newArtboard().identifierBytes);
    check(definition.rulerOrigin).deepEquals([1.0, 2.0]);
    check(() => definition.nameBytes[0] = 0).throws<UnsupportedError>();
    check(() => definition.rulerOrigin[0] = 0).throws<UnsupportedError>();
    for (final List<int> invalid in [
      [-1],
      [256],
    ]) {
      check(() => AiNativeArtboardDefinition(nameBytes: invalid, identifierBytes: identifier, bounds: definition.bounds, rulerOrigin: origin)).throws<ArgumentError>();
    }
    check(() => AiNativeArtboardDefinition(nameBytes: name, identifierBytes: [65], bounds: definition.bounds, rulerOrigin: origin)).throws<ArgumentError>();
    for (final double invalid in [0, -1, double.nan, double.infinity]) {
      check(() => AiNativeArtboardDefinition(nameBytes: name, identifierBytes: definition.identifierBytes, bounds: definition.bounds, rulerOrigin: origin, pixelAspectRatio: invalid))
          .throws<ArgumentError>();
    }
    check(() => AiNativeArtboardDefinition(nameBytes: name, identifierBytes: definition.identifierBytes, bounds: definition.bounds, rulerOrigin: [1])).throws<ArgumentError>();
  });

  test('refuses nonempty print ranges unknown dependencies and conditional owners', () {
    final String source = artboardSource();
    for (final String text in [
      artboardSource(extra: '%_/FutureReference : (board-0) /Ref , ;'),
      source.replaceFirst(
        '%_/Dictionary : /NotRecorded ,',
        '%_/Dictionary : /NotRecorded ,\n%_/Dictionary : /NotRecorded ,\n%_(1-3) /String (/attributes/job.artboardrange) ,\n%_; (AI11 Print JobInfo Dict) ,',
      ),
      source.replaceFirst(
        '%_/Dictionary : /NotRecorded ,',
        '%_/Dictionary : /NotRecorded ,\n%_/Dictionary : /NotRecorded ,\n%_(1) /String (/attributes/job.pagerange) ,\n%_; (AI11 Print JobInfo Dict) ,',
      ),
      source.replaceFirst('%_/Document', '%AI17_Begin_Content_if_version_gt:24 4\n%_/Document').replaceFirst('%%EndSetup', '%AI17_End_Versioned_Content\n%%EndSetup'),
      source.replaceFirst('%_0 100 /RealPointRelToROrigin', '0 100 /RealPointRelToROrigin'),
    ]) {
      final AiNativeArtboards model = artboardModel(text);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(() => model.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null)).throws<UnsupportedError>();
      check(artboardText(model)).equals(text);
    }
  });

  test('preserves mixed CC objects resources and unrelated document state', () {
    final AiNativeArtboards model = artboardModel(mixedArtboardSource());
    final AiNativeArtboards inserted = model.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null);
    final AiNativeArtboards ordered = inserted.reorder(artboards: inserted.artboards.reversed.toList(), cropBounds: null);
    final AiNativeArtboards result = ordered.remove(artboards: [ordered.artboards[2]], activeArtboard: null, cropBounds: null);
    check(result.artboards.map((board) => board.identifier)).deepEquals(['board-2', 'board-1', 'board-0']);
    check(result.records.program.bytes.sublist(result.records.program.bodyStart)).deepEquals(model.records.program.bytes.sublist(model.records.program.bodyStart));
    check(result.records.program.bytes.sublist(0, result.document.start)).deepEquals(model.records.program.bytes.sublist(0, model.document.start));
    check(AiNativeDrawing.decode(records: result.records).liveShapes).length.equals(2);
    check(AiNativeGradientResources.decode(records: result.records).definitions).length.equals(2);
  });

  test('retains aggregate byte and token budgets during creation and reparsing', () {
    final String source = artboardSource();
    final AiNativeArtboards limited = artboardModel(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => limited.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
    final int tokenCount = AiPostScript.tokenize(latin1.encode(source.replaceAll('%_', ''))).length;
    final AiNativeArtboards tokens = artboardModel(source, limits: AiNativeLimits(maxTokens: tokenCount));
    check(() => tokens.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
    check(artboardText(limited)).equals(source);
  });
}
