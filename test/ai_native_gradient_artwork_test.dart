import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_color_resources_test.dart' show colorStop;
import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentRecords;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Adds an explicit host-composed resource to a complete ordinary CC document.
AiNativeDrawing gradientArtworkSource() {
  final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: newDocumentRecords()).create(
    nameBytes: latin1.encode('Focale gradient'),
    radial: false,
    stops: [colorStop(0, 0), colorStop(100, 1)],
    ramps: [
      AiNativeGradientRamp(
        kind: .gray,
        channels: [
          AiNativeGradientChannel.samples(values: [0, 255]),
        ],
      ),
    ],
  );
  return AiNativeDrawing.decode(records: resources.records);
}

/// Supplies complete host geometry and fallback paint, optionally with new metadata.
AiNativePathDefinition gradientPath({bool fresh = true, double opacity = 1, bool hidden = false}) {
  final AiNativePathDefinition source = newDocumentPath(0);
  return AiNativePathDefinition(
    artwork: source.artwork,
    bounds: source.bounds,
    opacity: opacity,
    hidden: hidden,
    nameBytes: fresh ? latin1.encode('Gradient object') : null,
    identifierBytes: fresh ? latin1.encode('gradient-object') : null,
  );
}

/// Absolute native axis data, independent of its shared sampled resource.
AiNativeGradientFillDefinition gradientFill({double length = 20}) => AiNativeGradientFillDefinition(
  nameBytes: latin1.encode('Focale gradient'),
  origin: [10, 10],
  angle: 0,
  length: length,
  matrix: [1, 0, 0, 1, 0, 0],
);

/// Authors one identified gradient in the first layer beside ordinary paths.
AiNativeDrawing gradientArtworkDocument() {
  final AiNativeDrawing source = gradientArtworkSource();
  return source.createGradientArtwork(definition: gradientPath(), gradient: gradientFill(), layer: source.records.program.layers.first);
}

void main() {
  test('retains an explicit process stroke when moving a complete gradient owner', () {
    final AiNativeDrawing source = gradientArtworkSource();
    final AiNativePathDefinition path = gradientPath();
    final AiNativeDrawing created = source.createGradientArtwork(
      definition: AiNativePathDefinition(
        artwork: AiArtworkPath(
          segments: path.artwork.segments,
          fill: path.artwork.fill,
          stroke: AiColor(space: .rgb, channels: [0, 1, 0]),
          closed: true,
          strokeWidth: 3,
          dash: [4, 2],
          dashPhase: 1,
          lineCap: 1,
          lineJoin: 2,
        ),
        bounds: path.bounds,
        identifierBytes: path.identifierBytes,
        strokeOverprint: true,
      ),
      gradient: gradientFill(),
      layer: source.records.program.layers.first,
    );
    check(created.gradientArtwork.single.gradient.closing.numbers!.single).equals(2);
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: created);
    final AiNativeDrawing moved = layers.moveArtwork(artwork: created.gradientArtwork.single, parent: layers.layers[1], inheritParentFlags: true).drawing;
    final int selected = moved.paths.indexOf(moved.gradientArtwork.single.path);
    for (final bool native in [false, true]) {
      final Map<String, List<Object>> state = artworkStates(moved, native: native)[selected];
      check(state['stroke']!).deepEquals(['XA', 0.0, 1.0, 0.0]);
      check(state['w']!).deepEquals(['w', 3.0]);
      check(state['R']!).deepEquals(['R', 1.0]);
    }
  });

  test('creates one complete gradient path with its count, name and identity', () {
    final AiNativeDrawing source = gradientArtworkSource();
    final List<int> original = List.of(source.records.program.bytes);
    final AiNativeDrawing created = source.createGradientArtwork(definition: gradientPath(), gradient: gradientFill(), layer: source.records.program.layers.first);
    final AiNativeGradientArtwork owner = created.gradientArtwork.single;
    check(owner.pointCount).isNotNull();
    check(owner.pointCount!.start).equals(owner.start);
    check(owner.path.geometry.last.end).isLessOrEqual(owner.gradient.start);
    check(owner.gradient.geometry.nameBytes).deepEquals(latin1.encode('Focale gradient'));
    check(owner.gradient.geometry.length).equals(20);
    check(owner.identifierBytes!).deepEquals(latin1.encode('gradient-object'));
    check(owner.nameBytes!).deepEquals(latin1.encode('Gradient object'));
    check(owner.dictionary!.start).isGreaterOrEqual(owner.gradient.end);
    check(source.records.program.bytes).deepEquals(original);
    check(created.paths.length).equals(source.paths.length + 1);
  });

  test('duplicates native geometry with a fresh ID and retains the shared resource', () {
    final AiNativeDrawing source = gradientArtworkDocument();
    final AiNativeGradientArtwork owner = source.gradientArtwork.single;
    check(() => source.duplicateGradientArtwork(artwork: [owner])).throws<ArgumentError>();
    final AiNativeDrawing copied = source.duplicateGradientArtwork(artwork: [owner], identifiers: {owner: latin1.encode('gradient-copy')});
    check(copied.gradientArtwork.length).equals(2);
    check(copied.gradientArtwork.last.identifierBytes!).deepEquals(latin1.encode('gradient-copy'));
    check(copied.gradientArtwork.last.path.segments.map((segment) => segment.coordinates)).deepEquals(owner.path.segments.map((segment) => segment.coordinates));
    check(AiNativeGradientResources.decode(records: copied.records).definitions.length).equals(1);
    check(() => copied.replaceGradientArtwork(artwork: owner, definition: gradientPath(fresh: false), gradient: gradientFill())).throws<ArgumentError>();
  });

  test('reorders mixed paths and moves a gradient without detaching its metadata', () {
    final AiNativeLayers source = AiNativeLayers.decode(drawing: gradientArtworkDocument());
    final AiNativeGradientArtwork owner = source.drawing.gradientArtwork.single;
    final AiNativeLayers reordered = source.reorderArtwork(artwork: [owner, source.drawing.paths.first]);
    check(reordered.drawing.gradientArtwork.single.start).isLessThan(reordered.drawing.paths.last.start);
    final AiNativeLayers moved = reordered.moveArtwork(artwork: reordered.drawing.gradientArtwork.single, parent: reordered.layers[1], inheritParentFlags: true);
    final AiNativeGradientArtwork retained = moved.drawing.gradientArtwork.single;
    check(moved.structure.parentOf(moved.structure.nodeFor(retained.path))!.source).identicalTo(moved.layers[1].source);
    check(retained.identifierBytes!).deepEquals(owner.identifierBytes!);
    check(retained.nameBytes!).deepEquals(owner.nameBytes!);
  });

  test('replaces geometry and attributes without changing neighboring path state', () {
    final AiNativeDrawing source = gradientArtworkDocument();
    final AiNativeDrawing changed = source.replaceGradientArtwork(
      artwork: source.gradientArtwork.single,
      definition: gradientPath(fresh: false, opacity: .25, hidden: true),
      gradient: gradientFill(length: 40),
    );
    check(changed.gradientArtwork.single.gradient.geometry.length).equals(40);
    check(changed.gradientArtwork.single.identifierBytes!).deepEquals(source.gradientArtwork.single.identifierBytes!);
    for (final bool native in [false, true]) {
      final List<Map<String, List<Object>>> before = artworkStates(source, native: native);
      final List<Map<String, List<Object>>> after = artworkStates(changed, native: native);
      for (int index = 0; index < source.paths.length; index++) {
        if (!identical(source.paths[index], source.gradientArtwork.single.path)) {
          check(after[index]).deepEquals(before[index]);
        }
      }
    }
  });

  test('converts an identified path to a gradient and back without rebuilding identity', () {
    final AiNativeDrawing source = gradientArtworkSource();
    final AiNativeDrawing converted = source.setPathGradient(path: source.paths.first, definition: gradientPath(fresh: false), gradient: gradientFill());
    check(converted.gradientArtwork.single.identifierBytes!).deepEquals(latin1.encode('path_0'));
    final AiNativeDrawing cleared = converted.clearGradientArtwork(artwork: converted.gradientArtwork.single, definition: gradientPath(fresh: false));
    check(cleared.gradientArtwork).isEmpty();
    check(cleared.gradients).isEmpty();
    check(AiNativeObjects.decode(drawing: cleared).forSource(cleared.paths.first).identifier!.bytes).deepEquals(latin1.encode('path_0'));
    final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: cleared.records);
    check(resources.remove(definition: resources.definitions.single).definitions).isEmpty();
  });

  test('removes complete gradients before deleting their now-unused resources', () {
    final AiNativeLayers source = AiNativeLayers.decode(drawing: gradientArtworkDocument());
    final AiNativeGradientResources used = AiNativeGradientResources.decode(records: source.drawing.records);
    check(() => used.remove(definition: used.definitions.single)).throws<UnsupportedError>();
    final AiNativeLayers removed = source.removeArtwork(artwork: [source.drawing.gradientArtwork.single]);
    check(removed.drawing.paths.length).equals(source.drawing.paths.length - 1);
    check(removed.drawing.gradients).isEmpty();
    final AiNativeGradientResources unused = AiNativeGradientResources.decode(records: removed.drawing.records);
    check(unused.remove(definition: unused.definitions.single).definitions).isEmpty();
  });

  test('copies and removes containing layers without reusing gradient identities', () {
    final AiNativeLayers source = AiNativeLayers.decode(drawing: gradientArtworkDocument());
    final AiNativeGradientArtwork owner = source.drawing.gradientArtwork.single;
    final AiNativeLayers copied = source.duplicate(
      layers: [source.layers.first],
      identifiers: {for (final AiNativeLayer layer in source.layers) layer: latin1.encode('layer-copy-${layer.index}')},
      artworkIdentifiers: {
        for (final (int, AiNativePath) entry in source.drawing.paths.indexed)
          if (!identical(entry.$2, owner.path)) entry.$2: latin1.encode('path-copy-${entry.$1}'),
        owner: latin1.encode('gradient-in-layer-copy'),
      },
    );
    check(copied.drawing.gradientArtwork.length).equals(2);
    check(copied.drawing.gradientArtwork.last.identifierBytes!).deepEquals(latin1.encode('gradient-in-layer-copy'));
    final AiNativeLayers removed = copied.remove(layers: [copied.layers.first]);
    check(removed.drawing.gradientArtwork.length).equals(1);
    check(removed.drawing.gradientArtwork.single.identifierBytes!).deepEquals(latin1.encode('gradient-in-layer-copy'));
  });

  test('creates and copies a gradient inside an ordinary group', () {
    final AiNativeDrawing source = gradientArtworkSource().createGroup(identifierBytes: latin1.encode('gradient-group'));
    final AiNativeDrawing filled = source.createGradientArtwork(definition: gradientPath(), gradient: gradientFill(), parent: source.groups.single);
    final AiNativeDrawing copied = filled.duplicateGroups(
      groups: filled.groups,
      identifiers: {
        filled.groups.single: latin1.encode('group-copy'),
        filled.gradientArtwork.single: latin1.encode('group-gradient-copy'),
      },
    );
    check(copied.groups.length).equals(2);
    check(copied.gradientArtwork.length).equals(2);
    final AiNativeDrawing removed = copied.removeGroups(groups: [copied.groups.first]);
    check(removed.gradientArtwork.single.identifierBytes!).deepEquals(latin1.encode('group-gradient-copy'));
  });

  test('keeps direct gradient dependencies during resource creation and artboard reordering', () {
    final AiNativeDrawing source = gradientArtworkDocument();
    final AiNativeGradientResources resources = AiNativeGradientResources.decode(records: source.records).create(
      nameBytes: latin1.encode('Another gradient'),
      radial: false,
      stops: [colorStop(0, 1), colorStop(100, 0)],
      ramps: [
        AiNativeGradientRamp(
          kind: .gray,
          channels: [
            AiNativeGradientChannel.samples(values: [255, 0]),
          ],
        ),
      ],
    );
    check(resources.definitions.length).equals(2);
    final AiNativeArtboards boards = AiNativeArtboards.decode(records: resources.records);
    final AiNativeArtboards reordered = boards.reorder(artboards: boards.artboards.reversed.toList(), cropBounds: null);
    final AiNativeDrawing retained = AiNativeDrawing.decode(records: reordered.records);
    check(retained.gradientArtwork.single.identifierBytes!).deepEquals(source.gradientArtwork.single.identifierBytes!);
    check(retained.records.program.bytes.sublist(retained.gradientArtwork.single.start, retained.gradientArtwork.single.end)).deepEquals(
      source.records.program.bytes.sublist(source.gradientArtwork.single.start, source.gradientArtwork.single.end),
    );
  });

  test('does not expose interleaved state or unknown attached metadata as editable', () {
    final AiNativeDrawing source = gradientArtworkDocument();
    for (final String modified in [
      latin1.decode(source.records.program.bytes).replaceFirst('Bb\n', 'Bb\n.5 g\n'),
      latin1.decode(source.records.program.bytes).replaceFirst('(AIArtName)', '(FutureGradientDependency)', source.gradientArtwork.single.dictionary!.start),
    ]) {
      final AiNativeDrawing opaque = AiNativeDrawing.decode(
        records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(modified))),
      );
      check(opaque.gradientArtwork).isEmpty();
      check(opaque.gradients.length).equals(1);
    }
  });
}
