import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_brushes_test.dart' show artboardBrush, artboardBrushRaster;
import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_symbols_test.dart' show symbolArtboardSource;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;

/// Native perspective panel fields, independent of artboard identity or geometry.
const List<String> _perspectiveFlags = ['PerspectiveGrid_LockUnlock', 'PerspectiveGrid_LockUnlockGridStationPoint', 'PerspectiveGrid_ShowHideRulers'];

/// Adds saved view flags without changing any global perspective coordinates.
String perspectiveArtboardSource({int flag = 0, int plane = 0}) => artboardSource().replaceFirst(
  '%_67 /Int (LastArtboardID)',
  '${_perspectiveFlags.map((name) => '%_$flag /Bool ($name) ,\n').join()}%_$plane /Int (PerspectiveGrid_ActivePlane) ,\n%_67 /Int (LastArtboardID)',
);

/// A directly attached key-path annotation with the observed local match form.
String blendPathMetadata({String identity = 'B'}) =>
    '%_/ArtDictionary : (K) /String (ShapeBlendPathType) , ($identity) /String (ShapeBlendPathID) , (ALL) /String (ShapeBlendMatchTo${identity == 'A' ? 'After' : 'Before'}) , ;\n';

/// Keeps both endpoint labels and intermediate artwork inside one ordinary group.
String retainedBlendPaths({bool private = false}) {
  final String prefix = private ? '%_' : '';
  return '''u
${prefix}3 As 0 0 m 10 0 L 10 10 L 0 0 L s
${blendPathMetadata()}
${prefix}3 As 5 5 m 15 5 L 15 15 L 5 5 L s
${prefix}3 As 10 10 m 20 10 L 20 20 L 10 10 L s
${blendPathMetadata(identity: 'A')}
U
''';
}

/// Exercises every board operation against the same immutable source snapshot.
List<AiNativeArtboards> _edits(AiNativeArtboards before) => [
  before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
  before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -40, right: 100, top: 200), cropBounds: null),
  before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
  before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
];

/// Checks that all non-Document bytes remain exactly owned and ordered.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
}

/// Requires atomic refusal for unknown or incorrectly attached resource metadata.
void _refused(String art) {
  final String source = artboardSource(extra: artboardBrush(art: art));
  final AiNativeArtboards before = artboardModel(source);
  check(() => before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null)).throws<UnsupportedError>();
  check(latin1.decode(before.records.program.bytes)).equals(source);
}

/// Covers local annotations and independent view settings retained during editing.
void main() {
  test('preserves independent perspective flags and active plane across all board operations', () {
    for (final int flag in [0, 1]) {
      for (final int plane in [0, 1, 2, 3]) {
        final AiNativeArtboards before = artboardModel(perspectiveArtboardSource(flag: flag, plane: plane));
        for (final AiNativeArtboards after in _edits(before)) {
          _retained(before, after);
          for (final String name in [..._perspectiveFlags, 'PerspectiveGrid_ActivePlane']) {
            final AiNativeEntry original = before.document['NotRecorded']!.container![name]!;
            final AiNativeEntry changed = after.document['NotRecorded']!.container![name]!;
            check(changed.number).equals(original.number);
            check(changed.type).equals(original.type);
          }
        }
      }
    }
  });

  test('rejects wrong perspective types and unknown identity-bearing document settings', () {
    final String source = perspectiveArtboardSource();
    for (final String changed in [
      source.replaceFirst('/Bool (PerspectiveGrid_LockUnlock)', '/Int (PerspectiveGrid_LockUnlock)'),
      source.replaceFirst('/Int (PerspectiveGrid_ActivePlane)', '/Real (PerspectiveGrid_ActivePlane)'),
      source.replaceFirst('(PerspectiveGrid_ActivePlane)', '(PerspectiveGrid_ArtboardIndex)'),
    ]) {
      final AiNativeArtboards before = artboardModel(changed);
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(latin1.decode(before.records.program.bytes)).equals(changed);
    }
    check(() => artboardModel(source.replaceFirst('0 /Bool (PerspectiveGrid_LockUnlock)', '2 /Bool (PerspectiveGrid_LockUnlock)'))).throws<FormatException>();
  });

  test('retains both blend endpoints and all intermediate paths in symbols and brushes', () {
    for (final bool private in [false, true]) {
      final String art = retainedBlendPaths(private: private);
      for (final String resource in [artboardBrush(art: art), '%AI14_BeginSymbol\n(board-0)\n0 A 0 Xw $art%AI10_EndSymbol\n']) {
        final AiNativeArtboards before = artboardModel(artboardSource(extra: resource).replaceFirst('(board-0) /String (ArtboardUUID)', '(A) /String (ArtboardUUID)'));
        for (final AiNativeArtboards after in _edits(before)) {
          _retained(before, after);
        }
      }
    }
  });

  test('keeps pair identities local across sibling and nested resource groups', () {
    final String art = retainedBlendPaths();
    final AiNativeArtboards before = artboardModel(artboardSource(extra: artboardBrush(art: '$art u $art $art U')));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
    _refused(art.replaceFirst(blendPathMetadata(), '') + art.replaceFirst(blendPathMetadata(identity: 'A'), ''));
  });

  test('rejects incomplete duplicate unknown or cross-representation endpoint matches', () {
    final String art = retainedBlendPaths();
    final List<String> variants = [
      art.replaceFirst(blendPathMetadata(), ''),
      art.replaceFirst('(A) /String (ShapeBlendPathID)', '(B) /String (ShapeBlendPathID)').replaceFirst('ShapeBlendMatchToAfter', 'ShapeBlendMatchToBefore'),
      art.replaceFirst('(K) /String', '(Unknown) /String'),
      art.replaceFirst('(B) /String (ShapeBlendPathID)', '(board-0) /String (ShapeBlendPathID)'),
      art.replaceFirst('(ALL) /String', '(board-0) /String'),
      art.replaceFirst('ShapeBlendMatchToBefore', 'ShapeBlendMatchToAfter'),
      art.replaceFirst('(ALL) /String', '(ALL) /UnicodeString').replaceFirst('(ShapeBlendMatchToBefore)', '(UnknownMatch)'),
      art.replaceFirst('3 As 0 0 m 10 0 L 10 10 L 0 0 L s', '%_3 As 0 0 m 10 0 L 10 10 L 0 0 L s'),
    ];
    variants.forEach(_refused);
  });

  test('requires immediate path ownership instead of group raster or loose annotations', () {
    final String art = retainedBlendPaths();
    final List<String> variants = [
      '${blendPathMetadata()}$art',
      '$art${blendPathMetadata()}',
      art.replaceFirst(blendPathMetadata(), '1 w\n${blendPathMetadata()}'),
      art.replaceFirst('u\n', '*u\n').replaceFirst('U\n', '*U\n'),
      '${artboardBrushRaster()}${blendPathMetadata()}$art',
      '${artboardBrushRaster().replaceFirst('0.24 /Real (Raster Art Original Scale)', '(K) /String (ShapeBlendPathType) , (B) /String (ShapeBlendPathID) , (ALL) /String (ShapeBlendMatchToBefore) , 0.24 /Real (Raster Art Original Scale)')}$art',
    ];
    variants.forEach(_refused);
  });

  test('retains existing annotation and source-limit refusals for paired paths', () {
    final String art = retainedBlendPaths();
    _refused(art.replaceFirst('(K) /String', '(K) /String\n%AI24_ArtboardRef: board-0\n'));
    final String source = symbolArtboardSource(symbol: '%AI14_BeginSymbol\n(board-0)\n$art%AI10_EndSymbol\n');
    final AiNativeArtboards before = artboardModel(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
  });
}
