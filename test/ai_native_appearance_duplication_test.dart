import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkSource;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceAuthoring;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceOwners, nestedAppearanceSource;
import 'ai_native_appearance_removal_test.dart' show appearanceRemovalSource;
import 'ai_native_artboard_masks_test.dart' show artboardMaskRaster, artboardOpacityMask;
import 'ai_native_document_creation_test.dart' show newDocumentSave;
import 'ai_native_opacity_masks_test.dart' show opacityMaskSource;
import 'ai_native_path_artwork_test.dart' show artworkStates;
import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;

/// Supplies a fresh identity for every exact identified metadata container.
Map<AiNativeContainer, List<int>> appearanceCopyIdentities(AiNativeAppearances model, List<AiNativeAppearanceArtwork> selected, {String prefix = 'copy'}) => {
  for (final (int, AiNativeObjectIdentifier) entry
      in model.structure.identifiers.where((identity) => selected.any((owner) => identity.field.owner.start >= owner.start && identity.field.owner.end <= owner.end)).indexed)
    entry.$2.field.owner.source as AiNativeContainer: latin1.encode('${prefix}_${entry.$1}'),
};

/// Reads an exact owner without conflating it with its inserted scalar prefix.
List<int> _bytes(AiNativeAppearances model, AiNativeAppearanceArtwork owner) => model.structure.drawing.records.program.bytes.sublist(owner.start, owner.end);

/// Selects all complete public users while retaining their private applications.
List<AiNativeAppearanceArtwork> _owners(AiNativeAppearances model) => nestedAppearanceOwners(model).map((use) => model.artworkFor(use: use)).toList();

/// Exercises adjacent copies with exact source preservation and fresh identities.
void main() {
  test('copies an identified new-document object and saves both editable owners', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceRemovalSource());
    final AiNativeAppearanceArtwork owner = _owners(source).single;
    final AiNativeAppearances result = source.duplicateArtwork(artwork: [owner], identifiers: appearanceCopyIdentities(source, [owner]));
    final List<AiNativeAppearanceArtwork> copies = _owners(result);
    check(copies).length.equals(2);
    check(result.styles).length.equals(1);
    check(result.styles.single.uses).length.equals(2);
    check(_bytes(result, copies.first)).deepEquals(_bytes(source, owner));
    check(copies.last.path!.geometry.map((command) => command.numbers)).deepEquals(owner.path!.geometry.map((command) => command.numbers));
    check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes))).deepEquals(['root', 'author', 'copy_0']);
    final PdfDocument pdf = PdfDocument.fromPages(
      pages: [PdfPageSource(width: 100, height: 100, content: latin1.encode('q 1 0 0 1 10 20 cm 0 0 0 1 k 0 0 m 10 0 l 10 10 l h f 0 0 m 10 0 l 10 10 l h f Q'))],
    );
    final AiPdfDocument saved = newDocumentSave(result.structure.drawing.records, pdf);
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    check(_owners(reopened)).length.equals(2);
    check(saved.pdf.pageContent(saved.pdf.pages.single)).deepEquals(pdf.pageContent(pdf.pages.single));
    check(source.uses).length.equals(1);
  });

  test('copies nested and compound owners without cloning their shared child styles', () {
    for (final bool compound in [false, true]) {
      final String text = nestedAppearanceSource(compound: compound).replaceFirst('(First contour) /String (AIArtName)', '/XMLUID : (child) ; (AI10_ArtUID) , (First contour) /String (AIArtName)');
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      final List<AiNativeAppearanceArtwork> before = _owners(source);
      final AiNativeAppearances result = source.duplicateArtwork(artwork: [before.first], identifiers: appearanceCopyIdentities(source, [before.first]));
      final List<AiNativeAppearanceArtwork> after = _owners(result);
      check(after).length.equals(3);
      check(after[1].group!.paths).length.equals(before.first.group!.paths.length);
      check(after[1].nestedUses).length.equals(before.first.nestedUses.length);
      check(result.styles).length.equals(source.styles.length);
      check(after[1].nestedUses.every((use) => result.resolve(use: use) == result.styles.last)).isTrue();
      check(_bytes(result, after.first)).deepEquals(_bytes(source, before.first));
      check(_bytes(result, after.last)).deepEquals(_bytes(source, before.last));
      check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes))).deepEquals(['child', 'copy_0']);
    }
  });

  test('copies live-shape printing and both identified metadata alternatives', () {
    final AiNativeAppearances source = appearanceEditingModel(source: identifiedShapeLifecycleSource());
    final List<AiNativeAppearanceArtwork> before = _owners(source);
    final AiNativeAppearances result = source.duplicateArtwork(artwork: [before.first], identifiers: appearanceCopyIdentities(source, [before.first]));
    final List<AiNativeAppearanceArtwork> after = _owners(result);
    check(result.structure.drawing.liveShapes).length.equals(3);
    check(Map.fromEntries(after[1].liveShape!.parameters.entries.map((field) => MapEntry(field.key, field.number))))
        .deepEquals(Map.fromEntries(before.first.liveShape!.parameters.entries.map((field) => MapEntry(field.key, field.number))));
    check(after[1].liveShape!.alternativeDictionaries).length.equals(before.first.liveShape!.alternativeDictionaries.length);
    check(_bytes(result, after.first)).deepEquals(_bytes(source, before.first));
    check(_bytes(result, after.last)).deepEquals(_bytes(source, before.last));
    check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes)).toSet()).deepEquals({'author', 'older', 'copy_0', 'copy_1'});
  });

  test('copies identified mask descendants with explicit fresh identities', () {
    final AiNativeAppearances source = appearanceEditingModel(
      source: opacityMaskSource(mask: artboardOpacityMask(art: '%_0.3 g 0 0 m 10 0 L 10 10 L f\n%_/ArtDictionary : /XMLUID : (mask-art) ; (AI10_ArtUID) , ;\n')),
    );
    final AiNativeAppearanceArtwork owner = _owners(source).first;
    final Map<AiNativeContainer, List<int>> identities = appearanceCopyIdentities(source, [owner]);
    check(identities).length.equals(2);
    final AiNativeAppearances result = source.duplicateArtwork(artwork: [owner], identifiers: identities);
    final List<AiNativeAppearanceArtwork> after = _owners(result);
    check(after[1].opacityMasks.single.settings.linked).equals(owner.opacityMasks.single.settings.linked);
    check(after[1].opacityMasks.single.artworkDrawing.paths.single.geometry.map((command) => command.numbers))
        .deepEquals(owner.opacityMasks.single.artworkDrawing.paths.single.geometry.map((command) => command.numbers));
    check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes)).toSet())
        .deepEquals({'author', 'mask-art', 'copy_0', 'copy_1'});
    check(_bytes(result, after.first)).deepEquals(_bytes(source, owner));
    final AiNativeAppearances removed = result.removeArtwork(artwork: [after[1]]);
    check(removed.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes)).toSet()).deepEquals({'author', 'mask-art'});
    check(_bytes(removed, _owners(removed).first)).deepEquals(_bytes(source, owner));
  });

  test('renews mask image cache identities while preserving hostile binary samples', () {
    final List<int> pixels = latin1.encode('X+\n%_/Mask : ; %%EndData\u0000');
    final AiNativeAppearances source = appearanceEditingModel(
      source: opacityMaskSource(
        mask: artboardOpacityMask(art: artboardMaskRaster(pixels: pixels)),
      ),
    );
    final AiNativeAppearanceArtwork owner = _owners(source).first;
    final AiNativeAppearances result = source.duplicateArtwork(artwork: [owner], identifiers: appearanceCopyIdentities(source, [owner]));
    final List<AiNativeAppearanceArtwork> after = _owners(result);
    final AiNativeRaster original = after.first.opacityMasks.single.artworkDrawing.items.whereType<AiNativeRaster>().single;
    final AiNativeRaster copy = after[1].opacityMasks.single.artworkDrawing.items.whereType<AiNativeRaster>().single;
    check(copy.colorSamples).deepEquals(pixels);
    check(original.colorSamples).deepEquals(pixels);
    final Set<String> caches = {};
    for (final String key in ['AI24 ImageRawDataUUID', 'AI24 ImageAlphaRawDataUUID']) {
      final String value = copy.dictionary![key]!.text()!;
      check(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(value)).isTrue();
      check(value == original.dictionary![key]!.text()).isFalse();
      check(caches.add(value)).isTrue();
    }
    check(_bytes(result, after.first)).deepEquals(_bytes(source, owner));
  });

  test('restores distinct native and printing inputs before each copied contour', () {
    final String pair = appearanceArtworkPair().replaceFirst('0 D 0 XR', '1 D 0 XR');
    final AiNativeAppearances source = appearanceEditingModel(
      source: appearanceRemovalSource(pair: pair, tail: '50 0 m 60 0 L 60 10 L f'),
    );
    final AiNativeAppearances result = source.duplicateArtwork(artwork: _owners(source));
    final List<Map<String, List<Object>>> native = artworkStates(result.structure.drawing, native: true);
    final List<Map<String, List<Object>>> printing = artworkStates(result.structure.drawing, native: false);
    check(native[0]['D']!).deepEquals(['D', 1]);
    check(native[2]['D']!).deepEquals(['D', 1]);
    check(native[1]['D']!).deepEquals(['D', 0]);
    check(native[3]['D']!).deepEquals(['D', 0]);
    check(native.last['D']!).deepEquals(['D', 0]);
    check(printing.every((state) => state['D']!.last == 1)).isTrue();
    final AiNativePath tail = result.structure.drawing.paths.last;
    check(latin1.decode(result.structure.drawing.records.program.bytes.sublist(tail.start, tail.end))).equals('50 0 m 60 0 L 60 10 L f');
  });

  test('refuses changed unknown inherited inputs instead of inventing defaults', () {
    final String pair = appearanceArtworkPair().replaceFirst('0 D 0 XR', '0 XR');
    final String text = appearanceRemovalSource(pair: pair).replaceFirst('0 D 0 XR', '0 XR');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    check(() => source.duplicateArtwork(artwork: _owners(source))).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('copies private clipping scopes without turning transient widths into inherited state', () {
    for (final String variant in ['closed', 'open', 'compound', 'nested', 'leaves']) {
      final String authoring = clippingAppearanceAuthoring(variant).replaceFirst('%_q\n', '%_q\n%_19 w\n');
      final String pair = appearanceArtworkPair().replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', authoring);
      final AiNativeAppearances source = appearanceEditingModel(
        source: appearanceRemovalSource(pair: pair, tail: '50 0 m 60 0 L s'),
      );
      final AiNativeAppearanceArtwork owner = _owners(source).single;
      final AiNativeAppearances result = source.duplicateArtwork(artwork: [owner]);
      final List<AiNativeAppearanceArtwork> after = _owners(result);
      check(_bytes(result, after.first)).deepEquals(_bytes(source, owner));
      check(_bytes(result, after.last)).deepEquals(_bytes(source, owner));
      check(after.last.groupContours.map((contour) => contour.mask)).deepEquals(owner.groupContours.map((contour) => contour.mask));
      final AiNativeAppearances cleared = result.removeArtwork(artwork: after);
      check(artworkStates(cleared.structure.drawing, native: true).single['w']!).deepEquals(['w', 1]);
      check(artworkStates(cleared.structure.drawing, native: false).single['w']!).deepEquals(['w', 1]);
    }
  });

  test('copies reversed selections in source order and supports a subsequent copy', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource(metadata: true));
    final List<AiNativeAppearanceArtwork> before = _owners(source);
    final AiNativeAppearances result = source.duplicateArtwork(artwork: before.reversed.toList(), identifiers: appearanceCopyIdentities(source, before));
    final List<AiNativeAppearanceArtwork> after = _owners(result);
    check(after).length.equals(4);
    check(_bytes(result, after[0])).deepEquals(_bytes(source, before[0]));
    check(_bytes(result, after[2])).deepEquals(_bytes(source, before[1]));
    final AiNativeAppearances again = result.duplicateArtwork(
      artwork: [after[1]],
      identifiers: appearanceCopyIdentities(result, [after[1]], prefix: 'again'),
    );
    check(_owners(again)).length.equals(5);
    check(again.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes)).toSet()).deepEquals({'author', 'copy_0', 'again_0'});
  });

  test('requires exact fresh identity coverage and distinct current owners', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceRemovalSource());
    final AiNativeAppearanceArtwork owner = _owners(source).single;
    check(() => source.duplicateArtwork(artwork: [])).throws<ArgumentError>();
    check(
      () => source.duplicateArtwork(
        artwork: [
          owner,
          source.artworkFor(use: owner.use),
        ],
      ),
    ).throws<ArgumentError>();
    check(() => source.duplicateArtwork(artwork: [owner])).throws<ArgumentError>();
    check(() => source.duplicateArtwork(artwork: [owner], identifiers: {owner.dictionary!: latin1.encode('author')})).throws<ArgumentError>();
    check(() => source.duplicateArtwork(artwork: [owner], identifiers: {owner.dictionary!: latin1.encode('not an xml name')})).throws<ArgumentError>();
    final AiNativeAppearances foreign = appearanceEditingModel(source: appearanceRemovalSource());
    check(() => source.duplicateArtwork(artwork: _owners(foreign))).throws<ArgumentError>();
    check(() => source.duplicateArtwork(artwork: [owner], identifiers: {_owners(foreign).single.dictionary!: latin1.encode('copy')})).throws<ArgumentError>();
    final AiNativeAppearances result = source.duplicateArtwork(artwork: [owner], identifiers: appearanceCopyIdentities(source, [owner]));
    check(() => result.duplicateArtwork(artwork: [owner], identifiers: appearanceCopyIdentities(source, [owner]))).throws<ArgumentError>();
  });

  test('retains opaque unrelated references and enforces aggregate output limits', () {
    const String opaque = '/Dictionary : /XMLUID : (author) ; (FutureReference) , ;\n';
    final String text = appearanceRemovalSource().replaceFirst('%%EndSetup', '$opaque%%EndSetup');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final List<AiNativeAppearanceArtwork> owners = _owners(source);
    final AiNativeAppearances result = source.duplicateArtwork(artwork: owners, identifiers: appearanceCopyIdentities(source, owners));
    check(latin1.decode(result.structure.drawing.records.program.bytes)).contains(opaque);
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length + 16),
    );
    final List<AiNativeAppearanceArtwork> limited = _owners(bounded);
    check(() => bounded.duplicateArtwork(artwork: limited, identifiers: appearanceCopyIdentities(bounded, limited))).throws<AiLimitException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(text);
  });
}
