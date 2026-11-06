import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_references_test.dart' show artboardReferenceSource, artboardTextOwner, emptyArtboardTextEngine;
import 'ai_native_artboard_svg_filters_test.dart' show artboardSvgElement, artboardSvgFilter;
import 'ai_native_artwork_movement_test.dart' show movementState;
import 'ai_native_contour_metadata_test.dart' show contourMetadataSource;
import 'ai_native_group_creation_test.dart' show groupCreationDrawing;
import 'ai_native_objects_test.dart' show objectDictionary, objectSource;
import 'ai_native_path_topology_test.dart' show topologyBounds, topologyRectangle;
import 'ai_native_reference_scope_test.dart' show referenceXml;

/// Reads the original source without normalizing native records or whitespace.
String _source(AiNativeDrawing drawing) => latin1.decode(drawing.records.program.bytes);

/// Dissolves the complete imported compound and explicitly discards its metadata.
AiNativeDrawing _release(AiNativeDrawing drawing) => drawing.releaseCompounds(
  groups: drawing.groups.where((group) => group.compound).toList(),
  bounds: topologyBounds,
  discardMetadata: true,
);

/// Resolves an identified group without relying on postorder inventory indices.
AiNativeGroup _group(AiNativeDrawing drawing, String identifier) =>
    AiNativeObjects.decode(drawing: drawing).objects.singleWhere((object) => object.identifier != null && latin1.decode(object.identifier!.bytes) == identifier).source as AiNativeGroup;

/// Makes unknown incoming contour attributes explicit in the test's source.
String _unknownState(String body) => objectSource(body, setup: '').replaceFirst(movementState, '0 A 0 Xw 0.1 g 0 G 0 D 0 Ap');

/// Builds document provenance with literal text and separate rights resources.
String _provenance({String about = 'artwork.svg', String resource = 'https://creativecommons.org/licenses/by-sa/3.0/', String text = 'Compound'}) => referenceXml(
  'rdf:RDF',
  children:
      '${referenceXml(
        'cc:Work',
        attributes: '${referenceXml('rdf:about', kind: 2, value: '($about) /String')} (rdf:about) ,',
        children: '${referenceXml('dc:title', children: '${referenceXml('#text', kind: 3, value: '($text) /String')} ,')} , ${referenceXml('cc:license', attributes: '${referenceXml('rdf:resource', kind: 2, value: '($resource) /String')} (rdf:resource) ,')} ,',
      )} ,',
);

/// Attaches a qualified producer setup to an identified ordinary compound.
String _setupSource({String extra = '', String? provenance}) {
  final String source = artboardReferenceSource(body: '$movementState *u $topologyRectangle f *U\n${objectDictionary(identifier: 'Compound')}');
  final String metadata = referenceXml('metadata', children: '${provenance ?? _provenance()} ,');
  final String document = '${referenceXml('#document', kind: 9, children: '$metadata ,')} (#document) ,';
  return source.replaceFirst('%%EndSetup', '$extra\n%%EndSetup').replaceFirst('/Dictionary :', '/Dictionary : $document');
}

/// Exercises producer metadata, identity references and released scalar scopes.
void main() {
  test('recreates imported compounds while retaining surviving metadata exactly', () {
    final AiNativeDrawing before = groupCreationDrawing(contourMetadataSource());
    final AiNativeDrawing released = _release(before);
    final AiNativeDrawing rebuilt = released.compoundArtwork(paths: released.paths, bounds: topologyBounds);
    check(rebuilt.paths.map((path) => path.geometry.map((command) => command.numbers).toList())).deepEquals(before.paths.map((path) => path.geometry.map((command) => command.numbers).toList()));
    for (final String identifier in ['View', 'Current']) {
      final AiNativeObject original = AiNativeObjects.decode(drawing: before).forSource(_group(before, identifier));
      final AiNativeObject result = AiNativeObjects.decode(drawing: rebuilt).forSource(_group(rebuilt, identifier));
      check(rebuilt.records.program.bytes.sublist(result.dictionary!.start, result.dictionary!.end))
          .deepEquals(before.records.program.bytes.sublist(original.dictionary!.start, original.dictionary!.end));
    }
    check(rebuilt.groups.where((group) => group.compound)).length.equals(1);
    check(_source(rebuilt)).not((source) => source.contains('(Compound)'));
    check(_source(before)).equals(contourMetadataSource());
  });

  test('wraps and releases imported mask owners while preserving literal transparency', () {
    final AiNativeDrawing before = groupCreationDrawing(contourMetadataSource(state: '3 0.25 1 2 1 Xy'));
    final AiNativeDrawing clipped = before.clipArtwork(
      groups: [_group(before, 'Compound')],
      masks: [for (final AiNativePath path in before.paths) AiNativePathEdit(path: path, mask: .closed)],
      bounds: topologyBounds,
    );
    final AiNativeGroup selected = clipped.pathTopology(path: clipped.paths.first).clippingGroup!;
    final AiNativeDrawing released = clipped.releaseClippingGroups(groups: [selected], bounds: topologyBounds);
    check(released.paths.every((path) => released.pathTopology(path: path).mask == .none)).isTrue();
    check(_source(released)).contains('3 0.25 1 2 1 Xy');
    check(released.groups.map((group) => group.opening.operator)).deepEquals(before.groups.map((group) => group.opening.operator));
  });

  test('refuses missing ambiguous or removed named-view targets atomically', () {
    for (final String source in [
      contourMetadataSource().replaceFirst('(Current) /String (xmlnode-nodevalue)', '(Compound) /String (xmlnode-nodevalue)'),
      contourMetadataSource().replaceFirst('(Current) /String (xmlnode-nodevalue)', '(Missing) /String (xmlnode-nodevalue)'),
      contourMetadataSource().replaceFirst('%%Trailer', 'u U\n${objectDictionary(identifier: 'Current')}\n%%Trailer'),
    ]) {
      final AiNativeDrawing before = groupCreationDrawing(source);
      check(() => _release(before)).throws<UnsupportedError>();
      check(_source(before)).equals(source);
    }
  });

  test('never drops an imported coordinate basis through metadata disposal', () {
    final String source = contourMetadataSource().replaceFirst('u *u', 'q *u').replaceFirst('\nU\n', '\nQ\n');
    final AiNativeDrawing before = groupCreationDrawing(source);
    check(() => before.releaseClippingGroups(groups: [_group(before, 'Current')], bounds: topologyBounds, discardMetadata: true)).throws<UnsupportedError>();
    check(_source(before)).equals(source);
  });

  test('qualifies local setup resources and provenance separately from deleted identities', () {
    final String source = _setupSource(extra: artboardSvgFilter().replaceAll('board-0', 'Compound'));
    final AiNativeDrawing before = groupCreationDrawing(source);
    final AiNativeDrawing after = _release(before);
    check(_source(after).substring(_source(after).indexOf('%%BeginSetup'), after.records.program.bodyStart)).equals(
      _source(before).substring(_source(before).indexOf('%%BeginSetup'), before.records.program.bodyStart),
    );
    check(after.groups).isEmpty();
    check(_source(after)).contains('(Compound) /String (xmlnode-nodevalue)');
  });

  test('rejects provenance artwork fragments unknown nodes and external filter bindings', () {
    for (final String source in [
      _setupSource(provenance: _provenance(about: '#Compound')),
      _setupSource(provenance: _provenance(resource: '#Compound')),
      _setupSource(provenance: _provenance(resource: 'https://example.test/artwork.svg#Compound')),
      _setupSource(provenance: _provenance().replaceFirst('(dc:title)', '(foreign:target)')),
      _setupSource(
        extra: artboardSvgFilter(
          root: artboardSvgElement(name: 'filter', attributes: {'href': '#Compound'}),
        ),
      ),
      _setupSource(extra: artboardSvgFilter().replaceFirst('%AI10_EndSVGFilter', '%AI99_Reference: Compound\n%AI10_EndSVGFilter')),
    ]) {
      final AiNativeDrawing before = groupCreationDrawing(source);
      check(() => _release(before)).throws<UnsupportedError>();
      check(_source(before)).equals(source);
    }
  });

  test('qualifies numeric SVG canvas preferences without admitting reference strings', () {
    for (final String value in ['0 0', 'Compound', '0 NaN', '0 0 0']) {
      final String source = _setupSource().replaceFirst('/Dictionary :', '/Dictionary : ($value) /String (SVG_ViewBoxXY) , (128) /String (SVG_CropBoxWidth) , (128) /String (SVG_CropBoxHeight) ,');
      final AiNativeDrawing before = groupCreationDrawing(source);
      if (value == '0 0') {
        check(_release(before).groups).isEmpty();
      } else {
        check(() => _release(before)).throws<UnsupportedError>();
      }
    }
  });

  test('rejects unknown text roots and keeps the original aggregate decoding limit', () {
    for (final PsEngineDictionary engine in [
      emptyArtboardTextEngine(extra: {'99': PsEngineString.fromText(text: 'Compound')}),
      emptyArtboardTextEngine(
        resources: {
          '8': PsEngineDictionary(
            values: {
              '0': PsEngineArray(
                values: [
                  PsEngineDictionary(
                    values: {
                      '0': PsEngineDictionary(
                        values: {
                          '0': PsEngineArray(values: [PsEngineNumber(value: 0), PsEngineNumber(value: 0)]),
                        },
                      ),
                    },
                  ),
                ],
              ),
            },
          ),
        },
      ),
    ]) {
      final String source = _setupSource().replaceFirst(artboardTextOwner('AI11UndoFreeTextDocument', emptyArtboardTextEngine()), artboardTextOwner('AI11UndoFreeTextDocument', engine));
      final AiNativeDrawing before = groupCreationDrawing(source);
      check(() => _release(before)).throws<UnsupportedError>();
      check(_source(before)).equals(source);
    }
    final String limitedSource = _unknownState('q 9 w $topologyRectangle h W n Q 2 w');
    final AiNativeDrawing limited = groupCreationDrawing(limitedSource, limits: AiNativeLimits(maxDecodedBytes: limitedSource.length));
    check(limited.releaseClippingGroups(groups: limited.groups, bounds: topologyBounds).records.program.limits.maxDecodedBytes).equals(limitedSource.length);
  });

  test('accepts unknown restored values only before a proved overwrite in both streams', () {
    for (final String suffix in ['2 w', 'q $topologyRectangle f Q 2 w', '2 w q 3 w $topologyRectangle s Q']) {
      final AiNativeDrawing before = groupCreationDrawing(_unknownState('q 7 w\n%_9 w\n$topologyRectangle h W n Q $suffix'));
      final AiNativeGroup selected = before.groups.first;
      final AiNativeDrawing after = before.releaseClippingGroups(groups: [selected], bounds: topologyBounds);
      check(after.groups.length).equals(before.groups.length - 1);
      check(_source(after)).contains(suffix);
    }
    for (final String suffix in ['$topologyRectangle s 2 w', 'q 2 w Q $topologyRectangle s 2 w', '%_2 w\n$topologyRectangle s 2 w', '']) {
      final String source = _unknownState('q 7 w $topologyRectangle h W n Q $suffix');
      final AiNativeDrawing before = groupCreationDrawing(source);
      check(() => before.releaseClippingGroups(groups: [before.groups.first], bounds: topologyBounds)).throws<UnsupportedError>();
      check(_source(before)).equals(source);
    }
  });

  test('accounts for every removed boundary before proving batch continuations', () {
    final String source = _unknownState('q 7 w $topologyRectangle h W n Q q 3 w $topologyRectangle h W n Q 2 w $topologyRectangle s');
    final AiNativeDrawing before = groupCreationDrawing(source);
    final AiNativeDrawing after = before.releaseClippingGroups(groups: before.groups.reversed.toList(), bounds: topologyBounds);
    check(after.groups).isEmpty();
    check(after.paths).length.equals(3);
    final AiNativeDrawing unsafe = groupCreationDrawing(source.replaceFirst('q 3 w', 'q $topologyRectangle s 3 w'));
    check(() => unsafe.releaseClippingGroups(groups: unsafe.groups, bounds: topologyBounds)).throws<UnsupportedError>();
    check(_source(before)).equals(source);
  });
}
