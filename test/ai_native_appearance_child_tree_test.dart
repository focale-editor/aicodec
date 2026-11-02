import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentRecords, newDocumentSave;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Authors identified private contours with independently named paints.
AiNativeAppearancePathDefinition _path(String id) => AiNativeAppearancePathDefinition.styled(
  definition: AiNativePathDefinition(
    artwork: AiArtworkPath(
      segments: [
        AiPathSegment(operator: 'm', coordinates: [10, 10]),
        AiPathSegment(operator: 'L', coordinates: [20, 30]),
        AiPathSegment(operator: 'L', coordinates: [30, 10]),
      ],
      closed: true,
    ),
    bounds: _bounds,
    nameBytes: ascii.encode(id),
    identifierBytes: ascii.encode(id),
  ),
  styleNameBytes: ascii.encode('Paint'),
);

/// Host-supplied complete ink bounds, independent of source tree structure.
final AiBoundingBox _bounds = AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100);

/// Complete printing supplied for every child transaction.
List<int> _printing() => ascii.encode('u\n0 0 0 1 k\n10 10 m 70 10 L 70 30 L f\nU');

/// A nested native owner with independent child applications and a child mask.
AiNativeAppearances _model() {
  AiNativeAppearances model = AiNativeAppearances.decode(
    structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: true))),
  );
  model = model.createStyle(
    nameBytes: ascii.encode('Paint'),
    execution: AiNativeAppearancePartDefinition(
      kind: .fill,
      colors: [
        AiColor(space: .rgb, channels: [1, 0, 0]),
      ],
    ),
  );
  model = model.createStyle(
    nameBytes: ascii.encode('Group'),
    execution: AiNativeAppearancePartDefinition(kind: .conduit),
  );
  model = model.createGroupArtwork(
    definition: AiNativeAppearanceGroupDefinition(
      styleNameBytes: ascii.encode('Group'),
      identifierBytes: ascii.encode('tree-root'),
      children: [
        _path('a'),
        AiNativeAppearanceGroupDefinition(styleNameBytes: ascii.encode('Group'), identifierBytes: ascii.encode('inner'), children: [_path('b'), _path('c')]),
      ],
    ),
    printingBytes: _printing(),
    bounds: _bounds,
    layer: model.structure.drawing.records.program.layers.single,
  );
  final AiNativeAppearanceArtwork owner = _owner(model);
  return model.createOpacityMasks(
    masks: [
      AiNativeOpacityMaskAttachment(
        artwork: owner,
        target: owner.group!.children.first,
        settings: const AiNativeOpacityMaskSettings(linked: true, disabled: false, clipping: true, inverted: false),
        artworkBytes: AiNativeOpacityMask.encodeVectorArtwork(records: model.structure.drawing.records, elements: []),
      ),
    ],
    artwork: [_replacement(model)],
  );
}

/// Rebinds the complete source owner after every immutable edit.
AiNativeAppearanceArtwork _owner(AiNativeAppearances model) => model.artworkFor(use: model.uses.singleWhere((use) => !use.instruction.isPrivate));

/// Supplies complete printing rather than replacing only the changed child.
AiNativeAppearanceReplacement _replacement(AiNativeAppearances model) => AiNativeAppearanceReplacement(artwork: _owner(model), bytes: _printing(), bounds: _bounds);

/// Reads exact attached metadata independently of changing source positions.
Map<String, List<int>> _metadata(AiNativeAppearances model) => {
  for (final AiNativeObject object in AiNativeObjects.decode(drawing: model.structure.drawing).objects)
    if (object.identifier != null) latin1.decode(object.identifier!.bytes): model.structure.drawing.records.program.bytes.sublist(object.dictionary!.start, object.dictionary!.end),
};

/// Adds a second independent owner for transfers without regenerating identities.
AiNativeAppearances _twoOwners() {
  final AiNativeAppearances source = _model();
  return source.createGroupArtwork(
    definition: AiNativeAppearanceGroupDefinition(
      styleNameBytes: ascii.encode('Group'),
      identifierBytes: ascii.encode('second-root'),
      children: [_path('d'), _path('e')],
    ),
    printingBytes: _printing(),
    bounds: _bounds,
    layer: source.structure.drawing.records.program.layers.single,
  );
}

/// Current complete owners in source order, excluding child style uses.
List<AiNativeAppearanceArtwork> _owners(AiNativeAppearances model) => [
  for (final AiNativeResourceUse use in model.uses.where((use) => !use.instruction.isPrivate)) model.artworkFor(use: use),
];

/// A complete replacement bound to an independently selected owner.
AiNativeAppearanceReplacement _printOwner(AiNativeAppearanceArtwork owner) => AiNativeAppearanceReplacement(artwork: owner, bytes: _printing(), bounds: _bounds);

/// Exercises source-preserving private topology and its atomic rejection rules.
void main() {
  test('transfers masked paths and nested groups atomically between complete owners', () {
    final AiNativeAppearances source = _twoOwners();
    final List<AiNativeAppearanceArtwork> owners = _owners(source);
    final AiNativeGroup first = owners[0].group!;
    final AiNativeGroup second = owners[1].group!;
    final AiNativeAppearances after = source.replaceArtworkTrees(
      changes: [
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners[1]),
          children: [
            AiNativeAppearanceTreeChild.retain(source: first.children.last),
            AiNativeAppearanceTreeChild.retain(source: first.children.first),
            AiNativeAppearanceTreeChild.retain(source: second.children.last),
          ],
        ),
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners[0]),
          children: [AiNativeAppearanceTreeChild.retain(source: second.children.first)],
        ),
      ],
    );
    final List<AiNativeAppearanceArtwork> revised = _owners(after);
    check(revised.first.group!.children).length.equals(1);
    check(revised.first.opacityMasks).isEmpty();
    check(revised.last.group!.children).length.equals(3);
    check(revised.last.opacityMasks).length.equals(1);
    check(revised.last.authoringForMask(mask: revised.last.opacityMasks.single)).identicalTo(revised.last.group!.children[1]);
    check(_metadata(after)).deepEquals(_metadata(source));
    check(after.styles).length.equals(source.styles.length);
    final AiPdfDocument saved = newDocumentSave(after.structure.drawing.records, newDocumentPdf(blank: true));
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    check(_metadata(reopened)).deepEquals(_metadata(source));
    // Move the mask back while emptying its old owner, retaining the same UID.
    final AiNativeAppearances returned = after.replaceArtworkTrees(
      changes: [
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(revised.first),
          children: [
            ...revised.first.group!.children.map((child) => AiNativeAppearanceTreeChild.retain(source: child)),
            ...revised.last.group!.children.map((child) => AiNativeAppearanceTreeChild.retain(source: child)),
          ],
        ),
        AiNativeAppearanceTreeChange(artwork: _printOwner(revised.last), children: []),
      ],
    );
    check(_owners(returned).last.group!.children).isEmpty();
    check(_owners(returned).first.opacityMasks).length.equals(1);
    check(_metadata(returned)).deepEquals(_metadata(source));
  });

  test('transfers referenced identities while rejecting actual unsafe deletions', () {
    const String reference = '/Dictionary : /XMLUID : (a) ; (FutureReference) , ;\n';
    final String text = latin1.decode(_twoOwners().structure.drawing.records.program.bytes).replaceFirst('%%EndSetup', '$reference%%EndSetup');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final List<AiNativeAppearanceArtwork> owners = _owners(source);
    final AiNativeAppearances after = source.replaceArtworkTrees(
      changes: [
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners.first),
          children: [AiNativeAppearanceTreeChild.retain(source: owners.first.group!.children.last)],
        ),
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners.last),
          children: [
            AiNativeAppearanceTreeChild.retain(source: owners.first.group!.children.first),
            ...owners.last.group!.children.map((child) => AiNativeAppearanceTreeChild.retain(source: child)),
          ],
        ),
      ],
    );
    check(latin1.decode(after.structure.drawing.records.program.bytes)).contains(reference);
    check(_metadata(after)).deepEquals(_metadata(source));
    check(
      () => source.replaceArtworkTrees(
        changes: [
          for (final AiNativeAppearanceArtwork owner in owners) AiNativeAppearanceTreeChange(artwork: _printOwner(owner), children: []),
        ],
      ),
    ).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('rejects unselected sources duplicated children and duplicated or nested roots atomically', () {
    final AiNativeAppearances source = _twoOwners();
    final List<int> bytes = source.structure.drawing.records.program.bytes.toList();
    final List<AiNativeAppearanceArtwork> owners = _owners(source);
    final AiNativeAppearanceTreeChange keepFirst = AiNativeAppearanceTreeChange(
      artwork: _printOwner(owners.first),
      children: [
        ...owners.first.group!.children.map((child) => AiNativeAppearanceTreeChild.retain(source: child)),
      ],
    );
    for (final List<AiNativeAppearanceTreeChange> plan in [
      <AiNativeAppearanceTreeChange>[],
      [keepFirst, keepFirst],
      [
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners.last),
          children: [AiNativeAppearanceTreeChild.retain(source: owners.first.group!.children.first)],
        ),
      ],
      [
        keepFirst,
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners.last),
          children: [AiNativeAppearanceTreeChild.retain(source: owners.first.group!.children.first)],
        ),
      ],
      [
        keepFirst,
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners.last),
          children: [AiNativeAppearanceTreeChild.retain(source: owners.first.group!)],
        ),
      ],
    ]) {
      check(() => source.replaceArtworkTrees(changes: plan)).throws<Object>();
      check(source.structure.drawing.records.program.bytes).deepEquals(bytes);
    }
  });

  test('restores both outgoing states across transfers and untouched following artwork', () {
    final String text = latin1.decode(_twoOwners().structure.drawing.records.program.bytes).replaceFirst('%%PageTrailer', '0 0 m 5 0 L 5 5 L f\n%%PageTrailer');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final List<AiNativeAppearanceArtwork> owners = _owners(source);
    final AiNativeAppearances after = source.replaceArtworkTrees(
      changes: [
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners.first),
          children: owners.last.group!.children.map((child) => AiNativeAppearanceTreeChild.retain(source: child)).toList(),
        ),
        AiNativeAppearanceTreeChange(
          artwork: _printOwner(owners.last),
          children: owners.first.group!.children.map((child) => AiNativeAppearanceTreeChild.retain(source: child)).toList(),
        ),
      ],
    );
    for (final bool native in [false, true]) {
      check(artworkStates(after.structure.drawing, native: native).last).deepEquals(artworkStates(source.structure.drawing, native: native).last);
    }
  });

  test('inserts removes reparents and reorders children while retaining masks and metadata', () {
    final AiNativeAppearances source = _model();
    final AiNativeAppearanceArtwork owner = _owner(source);
    final AiNativeGroup inner = owner.group!.children.last as AiNativeGroup;
    final AiNativeAppearances changed = source.replaceArtworkChildren(
      artwork: _replacement(source),
      children: [
        AiNativeAppearanceTreeChild.retain(
          source: inner,
          children: [
            AiNativeAppearanceTreeChild.retain(source: owner.group!.children.first),
            AiNativeAppearanceTreeChild.retain(source: inner.children.last),
            AiNativeAppearanceTreeChild.create(definition: _path('new')),
          ],
        ),
      ],
    );
    final AiNativeAppearanceArtwork after = _owner(changed);
    check(after.group!.children).length.equals(1);
    check((after.group!.children.single as AiNativeGroup).children).length.equals(3);
    check(after.opacityMasks).length.equals(1);
    check(_metadata(changed).keys.toSet()).deepEquals({'tree-root', 'inner', 'a', 'c', 'new'});
    for (final String id in ['tree-root', 'inner', 'a', 'c']) {
      check(_metadata(changed)[id]!).deepEquals(_metadata(source)[id]!);
    }
    check(_metadata(source)).containsKey('b');
    final AiPdfDocument saved = newDocumentSave(changed.structure.drawing.records, newDocumentPdf(blank: true));
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    check(_metadata(reopened)).deepEquals(_metadata(changed));
  });

  test('creates a fresh group around retained children without cloning their identities', () {
    final AiNativeAppearances source = _model();
    final AiNativeGroup root = _owner(source).group!;
    final AiNativeAppearances after = source.replaceArtworkChildren(
      artwork: _replacement(source),
      children: [
        AiNativeAppearanceTreeChild.group(
          definition: AiNativeAppearanceGroupDefinition(children: [], styleNameBytes: ascii.encode('Group'), identifierBytes: ascii.encode('wrapper')),
          children: [AiNativeAppearanceTreeChild.retain(source: root.children.first)],
        ),
        AiNativeAppearanceTreeChild.retain(source: root.children.last),
      ],
    );
    final AiNativeGroup wrapper = _owner(after).group!.children.first as AiNativeGroup;
    check(wrapper.children).length.equals(1);
    check(_owner(after).authoringForMask(mask: _owner(after).opacityMasks.single)).identicalTo(wrapper.children.single);
    for (final MapEntry<String, List<int>> entry in _metadata(source).entries) {
      check(_metadata(after)[entry.key]!).deepEquals(entry.value);
    }
    check(_metadata(after).keys.toSet()).deepEquals({..._metadata(source).keys, 'wrapper'});
  });

  test('removes a masked subtree together with its identity and private application', () {
    final AiNativeAppearances source = _model();
    final AiNativeAppearanceArtwork before = _owner(source);
    final AiNativeAppearances after = source.replaceArtworkChildren(
      artwork: _replacement(source),
      children: [AiNativeAppearanceTreeChild.retain(source: before.group!.children.last)],
    );
    check(_owner(after).opacityMasks).isEmpty();
    check(after.styles).length.equals(source.styles.length);
    check(_owner(after).nestedUses).length.equals(before.nestedUses.length - 1);
    check(_metadata(after).keys.toSet()).deepEquals({'tree-root', 'inner', 'b', 'c'});
  });

  test('keeps clipping contours with their groups while replacing ordinary children', () {
    final AiNativeAppearances source = appearanceEditingModel(source: clippingAppearanceSource());
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativePathTopology clip = owner.groupContours.firstWhere((value) => value.mask != .none);
    final AiNativeAppearances after = source.replaceArtworkChildren(
      artwork: AiNativeAppearanceReplacement(artwork: owner, bytes: source.structure.drawing.records.program.bytes.sublist(owner.printingGroup.start, owner.printingGroup.end), bounds: _bounds),
      children: [for (final AiNativeItem child in owner.group!.children.where((item) => !identical(item, clip.path)).toList().reversed) AiNativeAppearanceTreeChild.retain(source: child)],
    );
    check(after.artworkFor(use: after.uses.first).groupContours.where((value) => value.mask != .none)).length.equals(1);
    check(
      () => source.replaceArtworkChildren(
        artwork: AiNativeAppearanceReplacement(artwork: owner, bytes: source.structure.drawing.records.program.bytes.sublist(owner.printingGroup.start, owner.printingGroup.end), bounds: _bounds),
        children: [AiNativeAppearanceTreeChild.retain(source: clip.path)],
      ),
    ).throws<UnsupportedError>();
  });

  test('preserves following native and printing consumers of inherited state', () {
    final String text = latin1.decode(_model().structure.drawing.records.program.bytes).replaceFirst('%%PageTrailer', '0 0 m 5 0 L 5 5 L f\n%%PageTrailer');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances after = source.replaceArtworkChildren(
      artwork: _replacement(source),
      children: [AiNativeAppearanceTreeChild.retain(source: _owner(source).group!.children.last)],
    );
    for (final bool native in [false, true]) {
      check(artworkStates(after.structure.drawing, native: native).last).deepEquals(artworkStates(source.structure.drawing, native: native).last);
    }
  });

  test('preserves opaque setup on reordering and rejects reference-unsafe deletion', () {
    const String opaque = '/Dictionary : /XMLUID : (a) ; (FutureReference) , ;\n';
    final String text = latin1.decode(_model().structure.drawing.records.program.bytes).replaceFirst('%%EndSetup', '$opaque%%EndSetup');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances after = source.replaceArtworkChildren(
      artwork: _replacement(source),
      children: [for (final AiNativeItem child in _owner(source).group!.children.reversed) AiNativeAppearanceTreeChild.retain(source: child)],
    );
    check(latin1.decode(after.structure.drawing.records.program.bytes)).contains(opaque);
    check(
      () => source.replaceArtworkChildren(
        artwork: _replacement(source),
        children: [AiNativeAppearanceTreeChild.retain(source: _owner(source).group!.children.last)],
      ),
    ).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('retains an empty group and bounds aggregate topology output atomically', () {
    final AiNativeAppearances source = _model();
    final AiNativeAppearances empty = source.replaceArtworkChildren(artwork: _replacement(source), children: []);
    check(_owner(empty).group!.children).isEmpty();
    check(_owner(empty).nestedUses).isEmpty();
    check(_owner(empty).opacityMasks).isEmpty();
    check(_metadata(empty).keys.toSet()).deepEquals({'tree-root'});
    final List<int> bytes = source.structure.drawing.records.program.bytes;
    final AiNativeAppearances limited = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(
            program: AiProgram.decode(
              bytes: bytes,
              limits: AiNativeLimits(maxDecodedBytes: bytes.length + 64),
            ),
          ),
        ),
      ),
    );
    check(
      () => limited.replaceArtworkChildren(
        artwork: _replacement(limited),
        children: [
          for (final AiNativeItem child in _owner(limited).group!.children) AiNativeAppearanceTreeChild.retain(source: child),
          AiNativeAppearanceTreeChild.create(definition: _path('new')),
        ],
      ),
    ).throws<FormatException>();
    check(limited.structure.drawing.records.program.bytes).deepEquals(bytes);
  });

  test('rejects repeated foreign cyclic and reused-identity children without changing source', () {
    final AiNativeAppearances source = _model();
    final List<int> bytes = source.structure.drawing.records.program.bytes.toList();
    final AiNativeGroup root = _owner(source).group!;
    for (final List<AiNativeAppearanceTreeChild> plan in [
      [AiNativeAppearanceTreeChild.retain(source: root.children.first), AiNativeAppearanceTreeChild.retain(source: root.children.first)],
      [AiNativeAppearanceTreeChild.retain(source: _owner(_model()).group!.children.first)],
      [AiNativeAppearanceTreeChild.retain(source: root)],
      [AiNativeAppearanceTreeChild.create(definition: _path('a'))],
    ]) {
      check(() => source.replaceArtworkChildren(artwork: _replacement(source), children: plan)).throws<Object>();
      check(source.structure.drawing.records.program.bytes).deepEquals(bytes);
    }
  });
}
