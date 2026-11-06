import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentRecords;
import 'ai_native_image_creation_test.dart' show createdImageDefinition;

/// Starts from explicit process styles, without borrowing private source syntax.
AiNativeAppearances _model() =>
    AiNativeAppearances.decode(
          structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: true))),
        )
        .createStyle(
          nameBytes: ascii.encode('Outer'),
          execution: AiNativeAppearancePartDefinition(kind: .conduit),
        )
        .createStyle(
          nameBytes: ascii.encode('Inner'),
          execution: AiNativeAppearancePartDefinition(
            kind: .blend,
            transparency: AiNativeTransparency(blendMode: .multiply, opacity: 0.4, isolated: true, knockout: .off, alphaIsShape: false),
          ),
        );

/// Independent child identities, process paints and a private nested style use.
AiNativeAppearanceGroupDefinition _tree({bool duplicate = false}) => AiNativeAppearanceGroupDefinition(
  styleNameBytes: ascii.encode('Outer'),
  identifierBytes: ascii.encode('outer'),
  nameBytes: utf8.encode('Groupe (été)'),
  locked: true,
  children: [
    AiNativeAppearancePathDefinition(definition: newDocumentPath(0)),
    AiNativeAppearanceGroupDefinition(
      styleNameBytes: ascii.encode('Inner'),
      identifierBytes: ascii.encode('inner'),
      hidden: true,
      children: [AiNativeAppearancePathDefinition(definition: newDocumentPath(duplicate ? 0 : 1))],
    ),
  ],
);

/// Host-authored printing remains separate from both native child geometries.
AiNativeAppearances _create(AiNativeAppearances model, AiNativeAppearanceGroupDefinition definition) => model.createGroupArtwork(
  definition: definition,
  printingBytes: ascii.encode('u\n0 g\n0 0 m 10 0 L 10 10 L f\nU'),
  bounds: AiBoundingBox(left: 0, bottom: 0, right: 240, top: 50),
  layer: model.structure.drawing.records.program.layers.single,
);

/// Deferred native tree creation and mixed following-owner regressions.
void main() {
  test('authors nested private paths flags names identities and style applications', () {
    final AiNativeAppearances source = _model();
    final AiNativeAppearances result = _create(source, _tree());
    final AiNativeAppearanceArtwork owner = result.artworkFor(use: result.uses.singleWhere((use) => !use.instruction.isPrivate));
    check(owner.group!.paths).length.equals(2);
    check(owner.group!.paths.every((path) => path.isPrivate)).isTrue();
    check(owner.nestedUses).length.equals(1);
    check(latin1.decode(owner.nestedUses.single.nameBytes)).equals('Inner');
    check(utf8.decode(owner.dictionary!['AIArtName']!.stringBytes!)).equals('Groupe (été)');
    check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes)).toSet())
        .deepEquals({'root', 'outer', 'inner', 'path_0', 'path_1'});
    check(owner.printingGroup.paths).length.equals(1);
    check(source.uses).isEmpty();
  });

  test('authors open and closed prefix clips with owned counts metadata and content', () {
    for (final AiNativePathMask mask in [AiNativePathMask.open, AiNativePathMask.closed]) {
      for (final bool counted in [false, true]) {
        final AiNativeAppearances source = _model();
        final AiNativeAppearances result = _create(
          source,
          AiNativeAppearanceGroupDefinition(
            styleNameBytes: ascii.encode('Outer'),
            identifierBytes: ascii.encode('clipped'),
            clip: AiNativeAppearanceClipDefinition(
              segments: [
                AiPathSegment(operator: 'm', coordinates: [0, 0]),
                AiPathSegment(operator: 'L', coordinates: [20, 0]),
                AiPathSegment(operator: 'L', coordinates: [10, 20]),
              ],
              mask: mask,
              counted: counted,
              evenOdd: true,
              nameBytes: utf8.encode('Découpe'),
              identifierBytes: ascii.encode('clip'),
            ),
            children: [AiNativeAppearancePathDefinition(definition: newDocumentPath(0))],
          ),
        );
        final AiNativeAppearanceArtwork owner = result.artworkFor(use: result.uses.singleWhere((use) => !use.instruction.isPrivate));
        check(owner.group!.opening.operator).equals('q');
        check(owner.group!.closing.operator).equals('Q');
        check(owner.groupContours).length.equals(2);
        final AiNativePathTopology clip = owner.groupContours.first;
        check(clip.mask).equals(mask);
        check(clip.clippingGroup).identicalTo(owner.group);
        check(clip.path.paint.operator).equals('N');
        check(clip.pointCount?.numbers?.single).equals(counted ? 3.0 : null);
        check(clip.path.geometry).length.equals(counted && mask == .closed ? 4 : 3);
        final AiNativeObject metadata = AiNativeObjects.decode(drawing: result.structure.drawing).forSource(clip.path);
        check(utf8.decode(metadata.dictionary!['AIArtName']!.stringBytes!)).equals('Découpe');
        check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes)).toSet())
            .deepEquals({'root', 'clipped', 'clip', 'path_0'});
        check(owner.groupContours.last.mask).equals(AiNativePathMask.none);
        check(owner.groupContours.last.path.paint.operator).equals(newDocumentPath(0).artwork.closed ? 'f' : 'F');
        check(source.uses).isEmpty();
      }
    }
  });

  test('creates nested clipping scopes and preserves the complete pair before following paths', () {
    final AiNativeAppearanceClipDefinition clip = AiNativeAppearanceClipDefinition(segments: newDocumentPath(0).artwork.segments);
    final AiNativeAppearances source = _create(
      _model(),
      AiNativeAppearanceGroupDefinition(
        styleNameBytes: ascii.encode('Outer'),
        clip: clip,
        children: [
          AiNativeAppearanceGroupDefinition(
            styleNameBytes: ascii.encode('Inner'),
            clip: clip,
            children: [AiNativeAppearancePathDefinition(definition: newDocumentPath(0))],
          ),
        ],
      ),
    );
    final AiNativeAppearanceArtwork before = source.artworkFor(use: source.uses.singleWhere((use) => !use.instruction.isPrivate));
    check(before.groupContours.where((contour) => contour.mask != .none)).length.equals(2);
    final AiNativeDrawing drawing = source.structure.drawing.createPath(definition: newDocumentPath(1), layer: source.structure.drawing.records.program.layers.single);
    final AiNativeAppearances result = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing));
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.singleWhere((use) => !use.instruction.isPrivate));
    check(drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(before.start, before.end));
    check(after.groupContours.map((contour) => contour.clippingGroup?.start).toSet()).length.equals(2);
    check(drawing.paths.last.isPrivate).isFalse();
  });

  test('rejects missing mask roles invalid contours and duplicate mask identities', () {
    check(() => AiNativeAppearanceClipDefinition(segments: [])).throws<ArgumentError>();
    check(() => AiNativeAppearanceClipDefinition(segments: newDocumentPath(0).artwork.segments, mask: .none)).throws<ArgumentError>();
    check(() => AiNativeAppearanceClipDefinition(segments: newDocumentPath(0).artwork.segments, nameBytes: [256])).throws<ArgumentError>();
    final AiNativeAppearances source = _model();
    final List<int> original = source.structure.drawing.records.program.bytes.toList();
    check(
      () => _create(
        source,
        AiNativeAppearanceGroupDefinition(
          styleNameBytes: ascii.encode('Outer'),
          clip: AiNativeAppearanceClipDefinition(segments: newDocumentPath(0).artwork.segments, identifierBytes: ascii.encode('path_0')),
          children: [AiNativeAppearancePathDefinition(definition: newDocumentPath(0))],
        ),
      ),
    ).throws<ArgumentError>();
    check(source.structure.drawing.records.program.bytes).deepEquals(original);
  });

  test('rejects duplicate child identities and unresolved named children atomically', () {
    final AiNativeAppearances model = _model();
    final List<int> before = model.structure.drawing.records.program.bytes.toList();
    check(() => _create(model, _tree(duplicate: true))).throws<ArgumentError>();
    check(
      () => _create(
        model,
        AiNativeAppearanceGroupDefinition(
          styleNameBytes: ascii.encode('Missing'),
          children: [AiNativeAppearancePathDefinition(definition: newDocumentPath(0))],
        ),
      ),
    ).throws<UnsupportedError>();
    check(model.structure.drawing.records.program.bytes).deepEquals(before);
  });

  test('retains empty ordinary groups and requires a root style', () {
    final AiNativeAppearances empty = _create(_model(), AiNativeAppearanceGroupDefinition(children: [], styleNameBytes: ascii.encode('Outer')));
    check(empty.artworkFor(use: empty.uses.single).group!.children).isEmpty();
    check(() => _create(_model(), AiNativeAppearanceGroupDefinition(children: [AiNativeAppearancePathDefinition(definition: newDocumentPath(0))]))).throws<ArgumentError>();
  });

  test('inserts independent ordinary paths images and groups after an appearance', () {
    final AiNativeAppearances model = _create(_model(), _tree());
    final AiNativeAppearanceArtwork before = model.artworkFor(use: model.uses.singleWhere((use) => !use.instruction.isPrivate));
    final List<int> retained = model.structure.drawing.records.program.bytes.sublist(before.start, before.end);
    AiNativeDrawing drawing = model.structure.drawing;
    drawing = drawing.createPath(definition: newDocumentPath(2), layer: drawing.records.program.layers.single);
    drawing = drawing.createRaster(definition: createdImageDefinition(), layer: drawing.records.program.layers.single);
    drawing = drawing.createGroup(identifierBytes: ascii.encode('following'), hidden: false, locked: false, inheritParentFlags: true, layer: drawing.records.program.layers.single);
    final AiNativeAppearances result = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing));
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.singleWhere((use) => !use.instruction.isPrivate));
    check(drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(retained);
    check(drawing.paths.where((path) => !path.isPrivate && path.start > after.end)).length.equals(1);
    check(AiNativeRasters.decode(records: drawing.records).images).length.equals(1);
  });
}
