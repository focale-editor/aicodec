import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentRecords, newDocumentSave;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Explicit adjacent contours with independent names, colors and point counts.
AiNativePathDefinition _path(int index, {bool painted = true}) => AiNativePathDefinition(
  artwork: AiArtworkPath(
    segments: [
      AiPathSegment(operator: 'm', coordinates: [10 + index * 40, 10]),
      AiPathSegment(operator: 'L', coordinates: [30 + index * 40, 10]),
      AiPathSegment(operator: 'L', coordinates: [20 + index * 40, 30]),
    ],
    fill: painted ? AiColor(space: .rgb, channels: [1, 0, 0]) : null,
    closed: true,
  ),
  bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
  nameBytes: ascii.encode('Child $index'),
  identifierBytes: ascii.encode('child_$index'),
);

/// Complete independent printing, deliberately different from child authoring.
List<int> _printing() => ascii.encode('u\n0 0 0 1 k\n10 10 m 70 10 L 70 30 L f\nU');

/// A private group and reusable styles with optional independently styled children.
AiNativeAppearances _model({bool styled = false}) {
  AiNativeAppearances model = AiNativeAppearances.decode(
    structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: true))),
  );
  model = model.createStyle(
    nameBytes: ascii.encode('Root'),
    execution: AiNativeAppearancePartDefinition(
      kind: .chain,
      children: [
        AiNativeAppearanceChild.create(definition: AiNativeAppearancePartDefinition(kind: .conduit)),
        AiNativeAppearanceChild.create(
          definition: AiNativeAppearancePartDefinition(
            kind: .blend,
            transparency: AiNativeTransparency(blendMode: .normal, opacity: .6, isolated: true, knockout: .off, alphaIsShape: false),
          ),
        ),
      ],
    ),
  );
  for (final String name in ['Child', 'Other']) {
    model = model.createStyle(
      nameBytes: ascii.encode(name),
      execution: AiNativeAppearancePartDefinition(
        kind: .fill,
        colors: [
          AiColor(space: .rgb, channels: name == 'Child' ? [0, 1, 0] : [0, 0, 1]),
        ],
      ),
    );
  }
  return model.createGroupArtwork(
    definition: AiNativeAppearanceGroupDefinition(
      children: [
        for (final int index in [0, 1])
          if (styled)
            AiNativeAppearancePathDefinition.styled(definition: _path(index, painted: false), styleNameBytes: ascii.encode('Child'))
          else
            AiNativeAppearancePathDefinition(definition: _path(index)),
      ],
      styleNameBytes: ascii.encode('Root'),
      nameBytes: ascii.encode('Root'),
      identifierBytes: ascii.encode('group'),
    ),
    printingBytes: _printing(),
    bounds: _path(0).bounds,
    layer: model.structure.drawing.records.program.layers.single,
  );
}

/// Selects the complete public body pair after any insertion changes use indices.
AiNativeAppearanceArtwork _owner(AiNativeAppearances model) => model.artworkFor(use: model.uses.singleWhere((use) => !use.instruction.isPrivate));

/// Supplies printing for the complete owner independently of nested applications.
AiNativeAppearanceReplacement _replacement(AiNativeAppearances model) => AiNativeAppearanceReplacement(artwork: _owner(model), bytes: _printing(), bounds: _path(0).bounds);

/// Checks source-backed child styles, metadata and both scalar interpretations.
void main() {
  test('authors named private children with immutable style names and direct ownership', () {
    final List<int> name = ascii.encode('Child');
    final AiNativeAppearancePathDefinition definition = AiNativeAppearancePathDefinition.styled(definition: _path(0, painted: false), styleNameBytes: name);
    name[0] = 0;
    check(definition.styleNameBytes!).deepEquals(ascii.encode('Child'));
    final AiNativeAppearances model = _model(styled: true);
    final AiNativeAppearanceArtwork owner = _owner(model);
    check(owner.nestedUses).length.equals(2);
    check(owner.nestedUses.map((use) => use.instruction.operands.first.number)).deepEquals([0, 0]);
    for (final AiNativeResourceUse use in owner.nestedUses) {
      check(owner.authoringFor(use: use) is AiNativePath).isTrue();
      check((owner.authoringFor(use: use) as AiNativePath).paint.operator).equals('n');
    }
    check(() => AiNativeAppearancePathDefinition.styled(definition: _path(0), styleNameBytes: ascii.encode('Child'))).throws<ArgumentError>();
    check(() => AiNativeAppearancePathDefinition.styled(definition: _path(0, painted: false), styleNameBytes: [])).throws<ArgumentError>();
  });

  test('attaches the first style and keeps identity masks and following state exact', () {
    final AiNativeAppearances source = _model();
    final AiNativeAppearanceArtwork root = _owner(source);
    final List<int> maskBytes = AiNativeOpacityMask.encodeVectorArtwork(records: source.structure.drawing.records, elements: []);
    final AiNativeAppearances masked = source.createOpacityMasks(
      masks: [
        AiNativeOpacityMaskAttachment(
          artwork: root,
          target: root.group!.paths.first,
          settings: const AiNativeOpacityMaskSettings(linked: true, disabled: false, clipping: true, inverted: false),
          artworkBytes: maskBytes,
        ),
      ],
      artwork: [_replacement(source)],
    );
    final AiNativeAppearanceArtwork before = _owner(masked);
    final AiNativeAppearances result = masked.applyStyleToPaths(
      appearance: masked.styles.singleWhere((style) => latin1.decode(style.resource.nameBytes) == 'Child'),
      paths: [before.group!.paths.first],
      artwork: [_replacement(masked)],
    );
    final AiNativeAppearanceArtwork after = _owner(result);
    check(after.nestedUses).length.equals(1);
    check(after.authoringFor(use: after.nestedUses.single)).identicalTo(after.group!.paths.first);
    check(after.authoringForMask(mask: after.opacityMasks.single)).identicalTo(after.group!.paths.first);
    check(after.opacityMasks.single.artworkBytes).deepEquals(maskBytes);
    check(result.structure.identifiers.map((id) => latin1.decode(id.bytes))).deepEquals(masked.structure.identifiers.map((id) => latin1.decode(id.bytes)));
    for (final bool native in [false, true]) {
      check(artworkStates(result.structure.drawing, native: native).last).deepEquals(artworkStates(masked.structure.drawing, native: native).last);
    }
    final AiPdfDocument saved = newDocumentSave(result.structure.drawing.records, newDocumentPdf(blank: true));
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    check(_owner(reopened).nestedUses).length.equals(1);
    check(_owner(masked).nestedUses).isEmpty();
  });

  test('attaches multiple children then rebinds exactly one named application', () {
    final AiNativeAppearances source = _model();
    final AiNativeAppearances styled = source.applyStyleToPaths(appearance: source.styles[1], paths: _owner(source).group!.paths.toList(), artwork: [_replacement(source)]);
    final AiNativeAppearanceArtwork root = _owner(styled);
    final AiNativeAppearances result = styled.applyStyle(
      appearance: styled.styles[2],
      artwork: [
        AiNativeAppearanceReplacement(artwork: root, uses: [root.nestedUses.first], bytes: _printing(), bounds: _path(0).bounds),
      ],
    );
    check(_owner(result).nestedUses.map((use) => latin1.decode(use.nameBytes))).deepEquals(['Other', 'Child']);
    check(_owner(result).group!.paths.map((path) => path.paint.operator)).deepEquals(['n', 'n']);
  });

  test('changes styled child closure and flags without changing whole printing flags', () {
    final AiNativeAppearances source = _model(styled: true);
    final AiNativeAppearanceArtwork before = _owner(source);
    final AiNativeAppearances result = source.replaceArtworkContours(
      changes: [
        for (final AiNativePath path in before.group!.paths)
          AiNativeAppearanceContourChange(path: path, segments: _path(before.group!.paths.toList().indexOf(path)).artwork.segments, closed: false, hidden: true, locked: true),
      ],
      artwork: [_replacement(source)],
    );
    final AiNativeAppearanceArtwork after = _owner(result);
    check(after.group!.paths.map((path) => path.paint.operator)).deepEquals(['N', 'N']);
    check(after.nestedUses.map((use) => latin1.decode(use.nameBytes))).deepEquals(['Child', 'Child']);
    final List<Map<String, List<Object>>> printing = artworkStates(result.structure.drawing, native: false);
    check(printing).deepEquals(artworkStates(source.structure.drawing, native: false));
    final List<Map<String, List<Object>>> native = artworkStates(result.structure.drawing, native: true);
    check(native.skip(1).map((state) => state['Xw'])).deepEquals([
      ['Xw', 1],
      ['Xw', 1],
    ]);
    check(native.skip(1).map((state) => state['A'])).deepEquals([
      ['A', 1],
      ['A', 1],
    ]);
    check(result.structure.identifiers.map((id) => latin1.decode(id.bytes))).deepEquals(source.structure.identifiers.map((id) => latin1.decode(id.bytes)));
  });

  test('retains clipping roles and enforces the complete native byte budget', () {
    final AiNativeAppearances clipped = appearanceEditingModel(source: clippingAppearanceSource());
    final AiNativeAppearanceArtwork owner = clipped.artworkFor(use: clipped.uses.first);
    final AiNativePath mask = owner.groupContours.firstWhere((contour) => contour.mask != .none).path;
    check(
      () => clipped.applyStyleToPaths(
        appearance: clipped.styles.first,
        paths: [mask],
        artwork: [AiNativeAppearanceReplacement(artwork: owner, bytes: _printing(), bounds: _path(0).bounds)],
      ),
    ).throws<UnsupportedError>();
    final List<int> bytes = _model().structure.drawing.records.program.bytes;
    final AiNativeAppearances limited = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(
            program: AiProgram.decode(
              bytes: bytes,
              limits: AiNativeLimits(maxDecodedBytes: bytes.length + 16),
            ),
          ),
        ),
      ),
    );
    check(() => limited.applyStyleToPaths(appearance: limited.styles[1], paths: [_owner(limited).group!.paths.first], artwork: [_replacement(limited)])).throws<FormatException>();
    check(limited.structure.drawing.records.program.bytes).deepEquals(bytes);
  });

  test('rejects stale and repeated handles missing coverage and duplicate applications atomically', () {
    final AiNativeAppearances source = _model();
    final List<int> bytes = source.structure.drawing.records.program.bytes.toList();
    final AiNativePath path = _owner(source).group!.paths.first;
    check(() => source.applyStyleToPaths(appearance: _model().styles[1], paths: [path], artwork: [_replacement(source)])).throws<ArgumentError>();
    check(() => source.applyStyleToPaths(appearance: source.styles[1], paths: [path, path], artwork: [_replacement(source)])).throws<ArgumentError>();
    check(() => source.applyStyleToPaths(appearance: source.styles[1], paths: [_owner(_model()).group!.paths.first], artwork: [_replacement(source)])).throws<ArgumentError>();
    check(() => source.applyStyleToPaths(appearance: source.styles[1], paths: [path], artwork: [])).throws<ArgumentError>();
    final AiNativeAppearances styled = _model(styled: true);
    check(() => styled.applyStyleToPaths(appearance: styled.styles[1], paths: [_owner(styled).group!.paths.first], artwork: [_replacement(styled)])).throws<UnsupportedError>();
    check(source.structure.drawing.records.program.bytes).deepEquals(bytes);
  });
}
