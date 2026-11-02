import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show artboardText, newArtboard;
import 'ai_native_artboard_references_test.dart' show artboardReferenceSource;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource, mixedArtboardSource;
import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_objects_test.dart' show objectDictionary;

/// Provides explicit closed geometry for ordinary and masked compound contours.
const String _rectangle = '0 0 m 20 0 L 20 20 L 0 20 L 0 0 L';

/// Retains nested mask intersections, opposite winding and direct object IDs.
String artboardTopologySource() => artboardReferenceSource(
  body: movementLayer(
    'Hidden',
    '''1 A 1 Xw 0.3 g 0 Ae u
0 Ae q
0 Ae *u
4 As 1 D $_rectangle h W n
${objectDictionary(identifier: 'outer-mask')}
0 D 2 As 3 3 m 4 4 L H W N
*U
${objectDictionary(identifier: 'compound-mask')}
0 Ae u
0.8 g 4 As $_rectangle f
q
4 As $_rectangle h W n
0.5 g 2 As 7 7 m 10 10 L S
Q
U
Q
U
${objectDictionary(identifier: 'retained-group')}
''',
    hidden: true,
  ),
);

/// Preserves every retained drawing token and every setup record outside Document.
void _unchanged(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
}

/// Checks retained topology independently from permission to edit its children.
void main() {
  test('retains nested compound clips hidden owners and exact identities through all board edits', () {
    final String source = artboardTopologySource();
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboards resized = model.resize(artboard: model.artboards.first, bounds: AiBoundingBox(left: -10, bottom: -20, right: 120, top: 140), cropBounds: null);
    final AiNativeArtboards added = resized.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null);
    final AiNativeArtboards reordered = added.reorder(artboards: added.artboards.reversed.toList(), cropBounds: null);
    final AiNativeArtboards removed = reordered.remove(artboards: [reordered.artboards.last], activeArtboard: null, cropBounds: null);
    for (final AiNativeArtboards result in [resized, added, reordered, removed]) {
      _unchanged(model, result);
      final AiNativeDrawing drawing = AiNativeDrawing.decode(records: result.records);
      check(drawing.groups.map((group) => group.opening.operator)).deepEquals(['*u', 'q', 'u', 'q', 'u']);
      check(drawing.paths).length.equals(5);
      check(AiNativeLayers.decode(drawing: drawing).layers.single.source.visible).isFalse();
    }
    check(artboardText(model)).equals(source);
  });

  test('retains ordinary compound groups without requiring independent child ownership', () {
    for (final String body in [
      '*u 0.2 g 4 As $_rectangle f 0 D 4 As $_rectangle f *U',
      '*u u 0.2 g $_rectangle f u $_rectangle f U U *U',
      'q 0.2 g $_rectangle H W F $_rectangle f Q',
    ]) {
      final AiNativeArtboards model = artboardModel(artboardSource(body: body));
      _unchanged(model, model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null));
      final AiNativeDrawing drawing = AiNativeDrawing.decode(records: model.records);
      check(() => drawing.removePaths(paths: [drawing.paths.first])).throws<UnsupportedError>();
      check(() => drawing.removeGroups(groups: [drawing.groups.last])).throws<UnsupportedError>();
    }
  });

  test('preserves complete CC pairs and gradients beside retained ordinary compounds', () {
    final String source = mixedArtboardSource();
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: artboardModel(source).records);
    final int first = AiNativeObjects.decode(drawing: drawing).forSource(drawing.liveShapes.first.appearanceGroup!).start;
    const String compound = '*u 0.2 g $_rectangle f $_rectangle f *U\n';
    for (final String text in [source.replaceFirst('%%Trailer', '$compound%%Trailer'), source.replaceRange(first, first, compound)]) {
      final AiNativeArtboards model = artboardModel(text);
      final AiNativeArtboards result = model.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null);
      _unchanged(model, result);
      check(AiNativeDrawing.decode(records: result.records).liveShapes).length.equals(2);
      check(AiNativeGradientResources.decode(records: result.records).definitions).length.equals(2);
    }
    for (final int position in [first, drawing.liveShapes.last.end]) {
      final AiNativeArtboards model = artboardModel(source.replaceRange(position, position, '\n/Future : (board-0) /Reference , ;\n'));
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('rejects stray private and malformed mask controls without mutating native bytes', () {
    for (final String body in [
      '$_rectangle h W N',
      'q $_rectangle W N Q',
      'q $_rectangle h N Q',
      'q $_rectangle h W W N Q',
      'q $_rectangle h 1 W N Q',
      'q $_rectangle h *W N Q',
      'q $_rectangle h\n%_W\nN Q',
      'q $_rectangle N W Q',
      'q $_rectangle h W n 17 FutureReference Q',
      'q $_rectangle h W n\n/FutureOwner : (board-0) /Ref , ;\nQ',
      'q $_rectangle h W n\n%AI24_FutureReference: board-0\nQ',
      '%_q $_rectangle h W n Q',
      '1 q $_rectangle h W n Q',
    ]) {
      final AiNativeArtboards model = artboardModel(artboardSource(body: body));
      final String source = artboardText(model);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(artboardText(model)).equals(source);
    }
  });

  test('requires contiguous owned geometry instead of accepting interleaved state', () {
    final AiNativeArtboards model = artboardModel(artboardSource(body: '*u 0 0 m 0.5 g 10 10 L N *U'));
    check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
  });

  test('rejects orphaned duplicate fractional and incorrect retained point counts', () {
    for (final String body in [
      '*u 3 As $_rectangle f *U',
      'q 5 As $_rectangle h W N Q',
      '*u 1.5 As $_rectangle f *U',
      '*u -1 As $_rectangle f *U',
      '*u 4 As 4 As $_rectangle f *U',
      '*u $_rectangle f *U 1 As',
    ]) {
      final AiNativeArtboards model = artboardModel(artboardSource(body: body));
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
    for (final String body in ['4 As *u $_rectangle f *U', 'q 4 As Q', '4 As 1 Ae u $_rectangle f U']) {
      final AiNativeArtboards model = artboardModel(artboardSource(body: body));
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('retains version and private-object refusals in compound topology', () {
    for (final String body in [
      '%AI17_Begin_Content_if_version_gt:24 4\n*u $_rectangle f *U\n%AI17_End_Versioned_Content',
      '*u\n%_$_rectangle f\n*U',
      'q $_rectangle h W n Q\n/ArtDictionary : (board-0) /String (FutureReference) , ;',
    ]) {
      final AiNativeArtboards model = artboardModel(artboardSource(body: body));
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
    }
  });

  test('retains input and output budgets across a large collection of nested compounds', () {
    final String source = artboardSource(body: List.filled(250, '*u u $_rectangle f U *U').join('\n'));
    final AiNativeArtboards model = artboardModel(source);
    _unchanged(model, model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null));
    final AiNativeArtboards limited = artboardModel(source, limits: AiNativeLimits(maxDecodedBytes: latin1.encode(source).length));
    check(() => limited.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
    check(artboardText(limited)).equals(source);
  });
}
