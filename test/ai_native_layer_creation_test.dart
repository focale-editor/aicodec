import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath, movementState;

/// Explicit observed CC layer attributes, without an existing source template.
const List<double> createdLayerAttributes = [1, 1, 1, 1, 0, 0, 1, 0, 79, 128, 255, 0, 50, 0];

/// Supplies complete declared sources with zero or more native layers.
String layerCreationSource({String body = '', int count = 0, bool views = false, String setup = ''}) =>
    '%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%%BoundingBox: 0 0 100 100\n'
    '%AI5_NumLayers: $count\n${views ? '%AI5_OpenViewLayers: 3\n%%+ 8\n' : ''}'
    '%%EndComments\n%%BeginProlog\n%%EndProlog\n%%BeginSetup\n$setup\n%%EndSetup\n$movementState\n$body\n%%Trailer\n%%EOF\n';

/// Opens source ownership under the requested original limits.
AiNativeLayers _layers(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeLayers.decode(
  drawing: AiNativeDrawing.decode(
    records: AiNativeRecords.decode(
      program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
    ),
  ),
);

/// Creates a caller-owned definition independently of the input document.
AiNativeLayerDefinition layerDefinition({String name = 'Created', String? identifier = 'Fresh', List<double> attributes = createdLayerAttributes, bool expanded = false}) =>
    AiNativeLayerDefinition(attributes: attributes, nameBytes: latin1.encode(name), identifierBytes: identifier == null ? null : latin1.encode(identifier), expanded: expanded);

/// Checks immutable creation, boundary ownership, source preservation and limits.
void main() {
  test('creates a first identified root without borrowed source artwork or headers', () {
    final String text = layerCreationSource();
    final AiNativeLayers source = _layers(text);
    final AiNativeLayers result = source.create(definition: layerDefinition());
    check(source.layers).isEmpty();
    check(result.layers).length.equals(1);
    check(result.declaredRootCount).equals(1);
    check(result.rootCount).equals(1);
    check(result.layers.single.source.name).equals('Created');
    check(result.layers.single.identifier!.bytes).deepEquals(latin1.encode('Fresh'));
    check(result.layers.single.source.begin.numbers!).deepEquals(createdLayerAttributes);
    check(result.layers.single.bindingIssue).isNull();
    check(result.drawing.paths).isEmpty();
    check(latin1.decode(source.drawing.records.program.bytes)).equals(text);
  });

  test('creates last children in populated and empty parents while retaining siblings', () {
    final String first = movementLayer('Parent', '${movementLayer('Empty', '')}\n${movementPath(10)}');
    final AiNativeLayers source = _layers(layerCreationSource(body: '$first\n${movementLayer('Other', movementPath(20))}', count: 2, views: true));
    for (final int index in [0, 1]) {
      final AiNativeLayers result = source.create(definition: layerDefinition(expanded: true), parent: source.layers[index], discardViewState: true);
      final AiNativeLayer created = result.layers.singleWhere((layer) => layer.source.name == 'Created');
      check(created.parentIndex).equals(index);
      check(created.expanded).equals(true);
      check(result.rootCount).equals(2);
      check(result.declaredRootCount).equals(2);
      check(result.viewComments).isEmpty();
      check(result.childrenOf(result.layers[index]).last).identicalTo(created);
      check(result.drawing.paths.map((path) => path.segments.map((segment) => segment.coordinates).toList()).toList()).deepEquals(
        source.drawing.paths.map((path) => path.segments.map((segment) => segment.coordinates).toList()).toList(),
      );
    }
  });

  test('recreates layers after removing every owner and updates changed-width counts', () {
    final AiNativeLayers source = _layers(layerCreationSource(body: movementLayer('Old', movementPath(10)), count: 1));
    final AiNativeLayers empty = source.remove(layers: source.layers);
    final AiNativeLayers restored = empty.create(definition: layerDefinition());
    check(restored.rootCount).equals(1);
    check(restored.drawing.paths).isEmpty();
    final AiNativeLayers nine = _layers(layerCreationSource(body: [for (int index = 0; index < 9; index++) movementLayer('Layer_$index', '')].join('\n'), count: 9, views: true));
    final AiNativeLayers ten = nine.create(definition: layerDefinition(), discardViewState: true);
    check(ten.declaredRootCount).equals(10);
    check(ten.layers.last.source.name).equals('Created');
  });

  test('freezes names, identities and layouts and supports each qualified header', () {
    final List<double> attributes = [...createdLayerAttributes];
    final List<int> name = latin1.encode('R\u00e9sum\u00e9 (layer)');
    final List<int> identifier = latin1.encode('Fresh');
    final AiNativeLayerDefinition definition = AiNativeLayerDefinition(attributes: attributes, nameBytes: name, identifierBytes: identifier);
    attributes[0] = 0;
    name[0] = 0;
    identifier[0] = 0;
    final AiNativeLayers source = _layers(layerCreationSource());
    final AiNativeLayer created = source.create(definition: definition).layers.single;
    check(created.source.name).equals('R\u00e9sum\u00e9 (layer)');
    check(created.source.visible).isTrue();
    check(created.identifier!.bytes).deepEquals(latin1.encode('Fresh'));
    check(() => definition.attributes[0] = 0).throws<UnsupportedError>();
    check(() => definition.nameBytes[0] = 0).throws<UnsupportedError>();
    check(() => definition.identifierBytes![0] = 0).throws<UnsupportedError>();
    for (final List<double> header in [
      [0, 1, 0, 0, 1, 0, -1, 255, 0, 128],
      [...createdLayerAttributes.take(13)],
      createdLayerAttributes,
    ]) {
      final AiNativeLayer result = source.create(definition: layerDefinition(attributes: header, identifier: null)).layers.single;
      check(result.source.begin.numbers!).deepEquals(header);
      check(result.identifier).isNull();
    }
    final AiNativeLayers carriageReturns = _layers(layerCreationSource().replaceAll('\n', '\r\n'));
    final String saved = latin1.decode(carriageReturns.create(definition: definition).drawing.records.program.bytes);
    check(saved.replaceAll('\r\n', '')).not((value) => value.contains('\n'));
  });

  test('retains opaque root and parent content and refuses captured XML names', () {
    const String setup = '/Dictionary : /XMLUID : (Referenced) ; (Future) , ;';
    const String opaque = '/FutureRecord : (preserved) /String (Value) , ;';
    final AiNativeLayers source = _layers(layerCreationSource(body: movementLayer('Parent', opaque), count: 1, setup: setup));
    for (final AiNativeLayer? parent in [null, source.layers.single]) {
      final AiNativeLayers result = source.create(definition: layerDefinition(), parent: parent);
      check(latin1.decode(result.drawing.records.program.bytes)).contains(opaque);
      check(latin1.decode(result.drawing.records.program.bytes)).contains(setup);
    }
    for (final String identifier in ['Parent', 'Referenced', '', 'bad name', '\u00ff']) {
      check(() => source.create(definition: layerDefinition(identifier: identifier))).throws<ArgumentError>();
    }
  });

  test('rejects stale parents, ambiguous headers and unapproved view invalidation', () {
    final String text = layerCreationSource(body: movementLayer('Parent', ''), count: 1, views: true);
    final AiNativeLayers source = _layers(text);
    check(() => source.create(definition: layerDefinition())).throws<UnsupportedError>();
    check(() => source.create(definition: layerDefinition(), parent: _layers(text).layers.single, discardViewState: true)).throws<ArgumentError>();
    final AiNativeLayers changed = source.create(definition: layerDefinition(), discardViewState: true);
    check(
      () => changed.create(
        definition: layerDefinition(identifier: 'Second'),
        parent: source.layers.single,
      ),
    ).throws<ArgumentError>();
    final AiNativeLayers malformed = _layers(text.replaceFirst('%AI5_NumLayers: 1', '%AI5_NumLayers: 0'));
    check(() => malformed.create(definition: layerDefinition(), discardViewState: true)).throws<FormatException>();
    check(latin1.decode(source.drawing.records.program.bytes)).equals(text);
  });

  test('retains absent declarations and refuses conditional parents and excess depth', () {
    final AiNativeLayers absent = _layers(layerCreationSource().replaceFirst('%AI5_NumLayers: 0\n', ''));
    final AiNativeLayers created = absent.create(definition: layerDefinition());
    check(created.declaredRootCount).isNull();
    check(created.rootCount).equals(1);
    final String conditional = '%AI24_Begin_Content_if_version_gt: 24 0\n${movementLayer('Parent', '')}\n%AI24_End_Versioned_Content';
    final AiNativeLayers versioned = _layers(layerCreationSource(body: conditional, count: 1));
    check(() => versioned.create(definition: layerDefinition(), parent: versioned.layers.single)).throws<UnsupportedError>();
    final String text = layerCreationSource(body: '1 1 1 1 0 0 0 79 128 255 Lb\n(Parent) Ln\nLB', count: 1);
    final AiNativeLayers bounded = _layers(text, limits: const AiNativeLimits(maxDepth: 2));
    check(() => bounded.create(definition: layerDefinition(identifier: null), parent: bounded.layers.single)).throws<FormatException>();
    check(latin1.decode(bounded.drawing.records.program.bytes)).equals(text);
  });

  test('rejects invalid definition layouts and original parser/output ceilings', () {
    for (final List<double> header in [
      [],
      [...createdLayerAttributes.take(12)],
      [...createdLayerAttributes]..[0] = 2,
      [...createdLayerAttributes]..[5] = 1,
      [...createdLayerAttributes]..[6] = 2,
      [...createdLayerAttributes]..[7] = 27,
      [...createdLayerAttributes]..[8] = 0.5,
      [...createdLayerAttributes]..[11] = 2,
      [...createdLayerAttributes]..[12] = 101,
      [...createdLayerAttributes]..[13] = 1,
      [...createdLayerAttributes]..[12] = double.nan,
    ]) {
      check(() => layerDefinition(attributes: header)).throws<ArgumentError>();
    }
    check(() => AiNativeLayerDefinition(attributes: createdLayerAttributes, nameBytes: [256])).throws<ArgumentError>();
    final String text = layerCreationSource();
    final AiNativeLayers source = _layers(text, limits: AiNativeLimits(maxDecodedBytes: text.length));
    check(() => source.create(definition: layerDefinition())).throws<FormatException>();
  });
}
