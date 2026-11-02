import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_ancestors_test.dart' show appearanceAncestorMask;
import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkState;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceOwners, nestedAppearanceSource;
import 'ai_native_appearance_removal_test.dart' show appearanceRemovalSource;
import 'ai_native_artboard_masks_test.dart' show artboardMaskRaster, artboardOpacityMask;
import 'ai_native_artwork_movement_test.dart' show movementLayer;
import 'ai_native_opacity_masks_test.dart' show opacityMaskSource;
import 'ai_native_path_artwork_test.dart' show artworkStates;
import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;

/// Gives each source pair a distinct identity and a convenient literal name.
String _pair(String name) => appearanceArtworkPair(metadata: true).replaceFirst('(author)', '($name)').replaceFirst('(Native)', '($name)');

/// Supplies one identified public group whose header remains outside moved art.
String _group(String name, String content, {bool clip = false}) =>
    '$appearanceArtworkState\n${clip ? 'q\n$appearanceAncestorMask' : 'u\n'}$content\n${clip ? 'Q' : 'U'}\n%_/ArtDictionary : /XMLUID : ($name) ; (AI10_ArtUID) , ($name) /String (AIArtName) , ;\n';

/// Supplies host ink bounds after any changed clipping or stacking.
AiBoundingBox _bounds() => AiBoundingBox(left: -100, bottom: -100, right: 100, top: 100);

/// Selects complete public applications, including their private child users.
List<AiNativeAppearanceArtwork> _owners(AiNativeAppearances model) => nestedAppearanceOwners(model).map((use) => model.artworkFor(use: use)).toList();

/// Locates a current complete owner through its preserved native object name.
AiNativeAppearanceArtwork _owner(AiNativeAppearances model, String name) => _owners(model).singleWhere((owner) => owner.dictionary?['AIArtName']?.text() == name);

/// Locates an ordinary target through its exact source object identity.
AiNativeGroup _parent(AiNativeAppearances model, String name) =>
    AiNativeObjects.decode(drawing: model.structure.drawing).objects.singleWhere((object) => latin1.decode(object.identifier?.bytes ?? []) == name).source as AiNativeGroup;

/// Reads the complete source pair independently of surrounding replay bytes.
List<int> _bytes(AiNativeAppearances model, AiNativeAppearanceArtwork owner) => model.structure.drawing.records.program.bytes.sublist(owner.start, owner.end);

/// Checks visual data and identities while moving source ownership and stacking.
void main() {
  test('moves around counted ordinary paths with metadata and independent stream state', () {
    const String ordinary = '3 As\n50 0 m 60 0 L 60 10 L 50 0 L f\n%_/ArtDictionary : (Anchor) /String (AIArtName) , ;';
    final String text = appearanceRemovalSource(pair: _pair('First'), tail: '%_0.25 g\n$ordinary');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final List<int> original = _bytes(source, _owner(source, 'First'));

    /// Selects the ordinary authoring contour independently of printing paths.
    AiNativePath anchor(AiNativeAppearances model) => model.structure.drawing.paths.singleWhere((path) => !path.isPrivate && path.geometry.first.numbers!.first == 50);

    /// Reads the actual scalar inputs to the unchanged neighboring contour.
    Map<String, List<Object>> state(AiNativeAppearances model, bool native) {
      final AiNativeDrawing drawing = model.structure.drawing;
      final List<AiNativePath> paths = drawing.paths.where((path) => native || !path.isPrivate).toList();
      if (!native) {
        return artworkStates(drawing, native: false)[paths.indexOf(anchor(model))];
      }
      // This fixture has one visible scalar fill. Expand its native XW effects
      // independently before using the literal-state test reader.
      final AiNativeAppearances expanded = AiNativeAppearances.decode(
        structure: AiNativeStructure.decode(
          drawing: AiNativeDrawing.decode(
            records: AiNativeRecords.decode(
              program: AiNativeEditor.apply(
                program: drawing.records.program,
                edits: [
                  for (final AiNativeResourceUse use in model.uses)
                    AiSourceEdit(start: use.instruction.end, end: use.instruction.end, bytes: latin1.encode('\n%_0.25 g\n%_0 O\n%_0 1 0 0 0 Xy\n%_0 XR\n')),
                ],
              ),
            ),
          ),
        ),
      );
      return artworkStates(expanded.structure.drawing, native: true)[paths.indexOf(anchor(model))];
    }

    AiNativeAppearances result = source;
    for (final bool after in [true, false, true, false]) {
      result = result.moveArtwork(
        artwork: _owner(result, 'First'),
        bounds: _bounds(),
        beforeObject: after ? null : anchor(result),
        afterObject: after ? anchor(result) : null,
      );
      check(_bytes(result, _owner(result, 'First'))).deepEquals(original);
      check(latin1.decode(result.structure.drawing.records.program.bytes)).contains(ordinary);
      check(_owner(result, 'First').start > anchor(result).start).equals(after);
      for (final bool native in [false, true]) {
        check(state(result, native)).deepEquals(state(source, native));
      }
    }
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('anchors at complete ordinary groups and layer wrappers from the same drawing', () {
    final AiNativeAppearances source = appearanceEditingModel(
      source: appearanceRemovalSource(pair: _pair('First'), tail: '${_group('Target', '')}\n${movementLayer('AnchorLayer', '')}').replaceFirst('%AI5_NumLayers: 1', '%AI5_NumLayers: 2'),
    );
    final AiNativeAppearances grouped = source.moveArtwork(artwork: _owner(source, 'First'), bounds: _bounds(), afterObject: _parent(source, 'Target'));
    final AiNativeObject group = AiNativeObjects.decode(drawing: grouped.structure.drawing).forSource(_parent(grouped, 'Target'));
    check(_owner(grouped, 'First').start > group.end).isTrue();
    final AiNativeLayer layer = AiNativeLayers.decode(drawing: grouped.structure.drawing).layers.singleWhere((layer) => layer.source.name == 'AnchorLayer');
    final AiNativeAppearances result = grouped.moveArtwork(artwork: _owner(grouped, 'First'), bounds: _bounds(), afterObject: layer);
    final AiNativeLayer retained = AiNativeLayers.decode(drawing: result.structure.drawing).layers.singleWhere((layer) => layer.source.name == 'AnchorLayer');
    check(_owner(result, 'First').start > retained.end).isTrue();
    check(_bytes(result, _owner(result, 'First'))).deepEquals(_bytes(source, _owner(source, 'First')));
  });

  test('rejects foreign, private, printing and conflicting ordinary anchors', () {
    final String text = appearanceRemovalSource(pair: '${_pair('First')}${_pair('Second')}', tail: '50 0 m 60 0 L S');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances foreign = appearanceEditingModel(source: text);
    final AiNativeAppearanceArtwork first = _owner(source, 'First');
    final AiNativeAppearanceArtwork second = _owner(source, 'Second');
    final AiNativePath ordinary = source.structure.drawing.paths.last;
    check(() => source.moveArtwork(artwork: first, bounds: _bounds(), afterObject: foreign.structure.drawing.paths.last)).throws<ArgumentError>();
    check(() => source.moveArtwork(artwork: first, bounds: _bounds(), beforeObject: second.path)).throws<UnsupportedError>();
    check(() => source.moveArtwork(artwork: first, bounds: _bounds(), beforeObject: second.printingGroup)).throws<UnsupportedError>();
    check(() => source.moveArtwork(artwork: first, bounds: _bounds(), beforeObject: second.printingGroup.paths.first)).throws<UnsupportedError>();
    check(() => source.moveArtwork(artwork: first, bounds: _bounds(), before: second, afterObject: ordinary)).throws<ArgumentError>();
    check(() => source.moveArtwork(artwork: first, bounds: _bounds(), beforeObject: ordinary, afterObject: ordinary)).throws<ArgumentError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('moves complete owners before and after siblings with exact source retention', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceRemovalSource(pair: '${_pair('First')}${_pair('Second')}${_pair('Third')}'));
    final Map<String, List<int>> originals = {
      for (final String name in ['First', 'Second', 'Third']) name: _bytes(source, _owner(source, name)),
    };
    final AiNativeAppearances first = source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'Third'), before: _owner(source, 'First'));
    check(_owners(first).map((owner) => owner.dictionary!['AIArtName']!.text())).deepEquals(['Third', 'First', 'Second']);
    final AiNativeAppearances result = first.moveArtwork(bounds: _bounds(), artwork: _owner(first, 'Third'), after: _owner(first, 'Second'));
    check(_owners(result).map((owner) => owner.dictionary!['AIArtName']!.text())).deepEquals(['First', 'Second', 'Third']);
    for (final String name in originals.keys) {
      check(_bytes(result, _owner(result, name))).deepEquals(originals[name]!);
    }
    check(result.styles).length.equals(1);
    check(result.structure.identifiers.map((identity) => latin1.decode(identity.bytes)).toSet()).deepEquals(source.structure.identifiers.map((identity) => latin1.decode(identity.bytes)).toSet());
  });

  test('permutes ordinary sibling slots while retaining interleaved complete appearances', () {
    const String first = '0.2 g 2 As 50 0 m 60 0 L S';
    const String last = '0.7 g 2 As 70 0 m 80 0 L S';
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceRemovalSource(pair: '$appearanceArtworkState\n$first\n${_pair('First')}\n$last'));
    final AiNativeDrawing drawing = source.structure.drawing;
    final AiNativePath before = drawing.paths.singleWhere((path) => path.geometry.first.numbers!.first == 50);
    final AiNativePath after = drawing.paths.singleWhere((path) => path.geometry.first.numbers!.first == 70);
    final AiNativeLayers changed = AiNativeLayers.decode(drawing: drawing).reorderArtwork(artwork: [after, before]);
    final AiNativeAppearances result = AiNativeAppearances.decode(structure: changed.structure);
    check(result.structure.drawing.paths.where((path) => !path.isPrivate && path.geometry.first.numbers!.first >= 50).map((path) => path.geometry.first.numbers!.first)).deepEquals([70, 50]);
    check(_bytes(result, _owner(result, 'First'))).deepEquals(_bytes(source, _owner(source, 'First')));
    check(result.structure.identifiers.map((identity) => latin1.decode(identity.bytes))).deepEquals(source.structure.identifiers.map((identity) => latin1.decode(identity.bytes)));
  });

  test('repaints an ordinary neighbor without editing complete appearance descendants', () {
    final AiNativeAppearances source = appearanceEditingModel(
      source: appearanceRemovalSource(pair: _pair('First'), tail: '50 0 m 60 0 L 60 10 L 50 0 L f'),
    );
    final AiNativeDrawing drawing = source.structure.drawing;
    final AiNativePath path = drawing.paths.last;
    final AiArtworkPath paint = AiArtworkPath(
      segments: path.segments,
      closed: true,
      fill: AiColor(space: .rgb, channels: [0, 0, 1]),
    );
    final AiNativeDrawing changed = drawing.replacePathArtwork(path: path, artwork: paint, bounds: _bounds());
    final AiNativeAppearances result = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: changed));
    check(_bytes(result, _owner(result, 'First'))).deepEquals(_bytes(source, _owner(source, 'First')));
    for (final bool native in [false, true]) {
      check(artworkStates(changed, native: native).last['fill']!).deepEquals(['Xa', 0, 0, 1]);
    }
    check(() => drawing.replacePathArtwork(path: _owner(source, 'First').printingGroup.paths.first, artwork: paint, bounds: _bounds())).throws<UnsupportedError>();
  });

  test('reparents into and out of an ordinary group only with explicit inheritance', () {
    final AiNativeAppearances source = appearanceEditingModel(
      source: appearanceRemovalSource(pair: '${_pair('First')}${_pair('Second')}', tail: _group('Target', '')),
    );
    check(() => source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'First'), parent: _parent(source, 'Target'))).throws<UnsupportedError>();
    final AiNativeAppearances grouped = source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'First'), parent: _parent(source, 'Target'), inheritParentAppearance: true);
    final AiNativeAppearanceArtwork moved = _owner(grouped, 'First');
    check(grouped.structure.parentOf(grouped.structure.nodeFor(moved.printingGroup))!.source).identicalTo(_parent(grouped, 'Target'));
    check(_bytes(grouped, moved)).deepEquals(_bytes(source, _owner(source, 'First')));
    final AiNativeAppearances root = grouped.moveArtwork(bounds: _bounds(), artwork: moved, inheritParentAppearance: true);
    check(root.structure.parentOf(root.structure.nodeFor(_owner(root, 'First').printingGroup))).isNull();
    check(_parent(root, 'Target').paths).isEmpty();
    check(_bytes(root, _owner(root, 'Second'))).deepEquals(_bytes(source, _owner(source, 'Second')));
  });

  test('moves between qualified layers without changing layer headers or identities', () {
    final String text = appearanceRemovalSource(pair: '${movementLayer('A', _pair('First'))}\n${movementLayer('B', _pair('Second'), hidden: true)}')
        .replaceFirst('%AI5_NumLayers: 1', '%AI5_NumLayers: 3');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiLayer target = source.structure.drawing.records.program.layers.singleWhere((layer) => layer.name == 'B');
    check(() => source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'First'), layer: target)).throws<UnsupportedError>();
    final AiNativeAppearances result = source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'First'), layer: target, inheritParentAppearance: true);
    final AiNativeAppearanceArtwork moved = _owner(result, 'First');
    final AiLayer after = result.structure.drawing.records.program.layers.singleWhere((layer) => layer.name == 'B');
    check(result.structure.parentOf(result.structure.nodeFor(moved.printingGroup))!.source).identicalTo(after);
    check(after.begin.operands.map((token) => token.lexeme)).deepEquals(target.begin.operands.map((token) => token.lexeme));
    check(_bytes(result, moved)).deepEquals(_bytes(source, _owner(source, 'First')));
    check(result.structure.drawing.records.program.layers.map((layer) => layer.name)).deepEquals(source.structure.drawing.records.program.layers.map((layer) => layer.name));
  });

  test('changes clipping ancestry explicitly and keeps the original mask contours', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceRemovalSource(pair: '${_group('ClipA', _pair('First'), clip: true)}${_group('ClipB', _pair('Second'), clip: true)}'));
    final AiNativeGroup target = _parent(source, 'ClipB');
    check(() => source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'First'), parent: target)).throws<UnsupportedError>();
    final AiNativeAppearances result = source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'First'), parent: target, inheritParentAppearance: true);
    check(latin1.decode(result.structure.drawing.records.program.bytes)).contains('%%BoundingBox: -100 -100 100 100');
    check(result.structure.parentOf(result.structure.nodeFor(_owner(result, 'First').printingGroup))!.source).identicalTo(_parent(result, 'ClipB'));
    for (final String name in ['ClipA', 'ClipB']) {
      final AiNativePath oldMask = _parent(source, name).paths.first;
      final AiNativePath newMask = _parent(result, name).paths.first;
      check(newMask.geometry.map((command) => command.numbers)).deepEquals(oldMask.geometry.map((command) => command.numbers));
      check(newMask.paint.operator).equals('N');
    }
    check(_bytes(result, _owner(result, 'First'))).deepEquals(_bytes(source, _owner(source, 'First')));
  });

  test('reorders siblings inside the same clipping owner without changing inheritance', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceRemovalSource(pair: _group('Clip', '${_pair('First')}${_pair('Second')}', clip: true)));
    final AiNativeAppearances result = source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'Second'), before: _owner(source, 'First'));
    check(_owners(result).map((owner) => owner.dictionary!['AIArtName']!.text())).deepEquals(['Second', 'First']);
    for (final AiNativeAppearanceArtwork owner in _owners(result)) {
      check(result.structure.parentOf(result.structure.nodeFor(owner.printingGroup))!.source).identicalTo(_parent(result, 'Clip'));
    }
  });

  test('moves nested applications and live-shape alternatives together', () {
    for (final String text in [nestedAppearanceSource(), identifiedShapeLifecycleSource()]) {
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      final List<AiNativeAppearanceArtwork> owners = _owners(source);
      final AiNativeAppearances result = source.moveArtwork(bounds: _bounds(), artwork: owners.first, after: owners.last);
      final List<AiNativeAppearanceArtwork> after = _owners(result);
      check(_bytes(result, after.last)).deepEquals(_bytes(source, owners.first));
      check(_bytes(result, after.first)).deepEquals(_bytes(source, owners.last));
      check(result.uses).length.equals(source.uses.length);
      check(after.last.nestedUses).length.equals(owners.first.nestedUses.length);
      check(result.structure.drawing.liveShapes).length.equals(source.structure.drawing.liveShapes.length);
    }
  });

  test('moves mask images without renewing cache identities or changing samples', () {
    final List<int> samples = latin1.encode('X+\n%%EndData\u0000');
    final AiNativeAppearances source = appearanceEditingModel(
      source: opacityMaskSource(
        mask: artboardOpacityMask(art: artboardMaskRaster(pixels: samples)),
      ),
    );
    final List<AiNativeAppearanceArtwork> owners = _owners(source);
    final AiNativeAppearances result = source.moveArtwork(bounds: _bounds(), artwork: owners.first, after: owners.last);
    final AiNativeAppearanceArtwork moved = _owners(result).last;
    check(moved.opacityMasks.single.artworkBytes).deepEquals(owners.first.opacityMasks.single.artworkBytes);
    check(moved.opacityMasks.single.artworkDrawing.items.whereType<AiNativeRaster>().single.colorSamples).deepEquals(samples);
    check(_bytes(result, moved)).deepEquals(_bytes(source, owners.first));
  });

  test('rejects unknown changed inputs and unsafe following state atomically', () {
    final String text = appearanceRemovalSource(pair: '${_pair('First')}${_pair('Second')}', visible: false, tail: '50 0 m 60 0 L 60 10 L f');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    check(() => source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'Second'), before: _owner(source, 'First'))).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('rejects foreign ambiguous self and derived destinations', () {
    final String text = appearanceRemovalSource(pair: '${_pair('First')}${_pair('Second')}');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances foreign = appearanceEditingModel(source: text);
    final AiNativeAppearanceArtwork first = _owner(source, 'First');
    final AiNativeAppearanceArtwork second = _owner(source, 'Second');
    check(() => source.moveArtwork(bounds: _bounds(), artwork: first, before: first)).throws<ArgumentError>();
    check(() => source.moveArtwork(bounds: _bounds(), artwork: first, after: _owner(foreign, 'Second'))).throws<ArgumentError>();
    check(() => source.moveArtwork(bounds: _bounds(), artwork: first, before: second, after: second)).throws<ArgumentError>();
    check(() => source.moveArtwork(bounds: _bounds(), artwork: first, parent: first.printingGroup, inheritParentAppearance: true)).throws<ArgumentError>();
    check(() => source.moveArtwork(bounds: _bounds(), artwork: first, parent: second.printingGroup, inheritParentAppearance: true)).throws<UnsupportedError>();
    check(() => source.moveArtwork(bounds: _bounds(), artwork: first, layer: foreign.structure.drawing.records.program.layers.single, inheritParentAppearance: true)).throws<ArgumentError>();
  });

  test('keeps opaque external references and bounds additional state replay', () {
    const String opaque = '/Dictionary : /XMLUID : (First) ; (FutureReference) , ;\n';
    final String text = appearanceRemovalSource(pair: '${_pair('First')}${_pair('Second')}').replaceFirst('%%EndSetup', '$opaque%%EndSetup');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances result = source.moveArtwork(bounds: _bounds(), artwork: _owner(source, 'First'), after: _owner(source, 'Second'));
    check(latin1.decode(result.structure.drawing.records.program.bytes)).contains(opaque);
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length),
    );
    check(() => bounded.moveArtwork(bounds: _bounds(), artwork: _owner(bounded, 'First'), after: _owner(bounded, 'Second'))).throws<AiLimitException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(text);
  });
}
