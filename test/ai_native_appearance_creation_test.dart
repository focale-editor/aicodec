import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkState;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceAuthoring;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupAuthoring;
import 'ai_native_artboard_masks_test.dart' show artboardOpacityMask;
import 'ai_native_document_creation_test.dart' show newDocumentRecords, newDocumentSave;
import 'ai_native_path_artwork_test.dart' show artworkStates;

/// Authors the first named paint without borrowing an existing document's style.
AiNativeAppearances _new({bool blank = true}) =>
    AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: blank)),
      ),
    ).createStyle(
      nameBytes: latin1.encode('Shared'),
      execution: AiNativeAppearancePartDefinition(
        kind: .fill,
        colors: [
          AiColor(space: .cmyk, channels: [0, 0, 0, 1]),
        ],
      ),
    );

/// Declares explicit host ink bounds for the authored triangle and group fixtures.
AiBoundingBox _bounds() => AiBoundingBox(left: 0, bottom: 0, right: 30, top: 10);

/// Inserts complete host bytes in the only root layer of a blank document.
AiNativeAppearances _insert(AiNativeAppearances model, String bytes) => model.createArtwork(
  bytes: latin1.encode(bytes),
  bounds: _bounds(),
  layer: model.structure.drawing.records.program.layers.first,
);

/// Reads an exact source-owned interval for preservation assertions.
List<int> _bytes(AiNativeAppearances model, int start, int end) => model.structure.drawing.records.program.bytes.sublist(start, end);

/// Exercises initial appearance ownership and independent native/printing state.
void main() {
  test('creates an identified pair in a fresh document and saves both representations', () {
    final AiNativeAppearances source = _new();
    final List<int> input = latin1.encode(appearanceArtworkPair(counted: true, metadata: true));
    final AiNativeAppearances created = source.createArtwork(bytes: input, bounds: _bounds(), layer: source.structure.drawing.records.program.layers.single);
    input.fillRange(0, input.length, 0);
    final AiNativeAppearanceArtwork owner = created.artworkFor(use: created.uses.single);
    check(owner.path!.paint.operator).equals('n');
    check(owner.path!.isPrivate).isTrue();
    check(owner.printingGroup.paths.single.paint.operator).equals('f');
    check(owner.printingDictionary).isNotNull();
    check(created.resolve(use: owner.use)).identicalTo(created.styles.single);
    check(created.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes))).deepEquals(['root', 'author']);
    check(source.uses).isEmpty();
    final PdfDocument pdf = PdfDocument.fromPages(
      pages: [PdfPageSource(width: 100, height: 100, content: latin1.encode('q 1 0 0 1 10 20 cm 0 0 0 1 k 0 0 m 10 0 l 10 10 l h f Q'))],
    );
    final AiPdfDocument saved = newDocumentSave(created.structure.drawing.records, pdf);
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    check(reopened.artworkFor(use: reopened.uses.single).path!.geometry.map((instruction) => instruction.numbers)).deepEquals(owner.path!.geometry.map((instruction) => instruction.numbers));
    check(saved.pdf.pageContent(saved.pdf.pages.single)).deepEquals(pdf.pageContent(pdf.pages.single));
  });

  test('creates compound and nested groups with independently resolved child styles', () {
    for (final bool compound in [false, true]) {
      final AiNativeAppearances source = _new().createStyle(
        nameBytes: latin1.encode('Child'),
        execution: AiNativeAppearancePartDefinition(kind: .conduit),
      );
      final String authoring = appearanceGroupAuthoring(compound: compound).replaceFirst(
        '(First contour) /String (AIArtName) , ;',
        '(First contour) /String (AIArtName) , /XMLUID : (child) ; (AI10_ArtUID) , ;\n%_0 (Child) XW',
      );
      final AiNativeAppearances result = _insert(source, appearanceArtworkPair().replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', authoring));
      final AiNativeAppearanceArtwork owner = result.artworkFor(use: result.uses.singleWhere((use) => !use.instruction.isPrivate));
      check(owner.group!.paths).length.equals(2);
      check(owner.nestedUses).length.equals(1);
      check(result.resolve(use: owner.nestedUses.single)).identicalTo(result.styles.last);
      check(owner.authoringFor(use: owner.nestedUses.single)).identicalTo(owner.group!.paths.first);
      check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes))).deepEquals(['root', 'child']);
    }
  });

  test('creates private clipping owners without leaking their scoped attributes', () {
    for (final String variant in ['closed', 'open', 'compound', 'nested', 'leaves']) {
      final AiNativeAppearances source = _new();
      final String pair = appearanceArtworkPair().replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', clippingAppearanceAuthoring(variant));
      final AiNativeAppearances first = _insert(source, pair);
      final AiNativeAppearanceArtwork owner = first.artworkFor(use: first.uses.single);
      check(owner.group).isNotNull();
      check(owner.groupContours).isNotEmpty();
      final AiNativeAppearances second = _insert(first, appearanceArtworkPair(metadata: true));
      final AiNativeAppearanceArtwork retained = second.artworkFor(use: second.uses.first);
      check(_bytes(second, retained.start, retained.end)).deepEquals(_bytes(first, owner.start, owner.end));
      check(second.uses).length.equals(2);
    }
  });

  test('restores separate printing and private values before unchanged following paths', () {
    final AiNativeAppearances blank = _new();
    final String text = latin1
        .decode(blank.structure.drawing.records.program.bytes)
        .replaceFirst(
          '%%PageTrailer',
          '$appearanceArtworkState\n%_0.7 g\nu U\n0 0 m 10 0 L 10 10 L f\n%%PageTrailer',
        );
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances result = source.createArtwork(bytes: latin1.encode(appearanceArtworkPair()), bounds: _bounds(), parent: source.structure.drawing.groups.single);
    for (final bool native in [false, true]) {
      check(artworkStates(result.structure.drawing, native: native).last).deepEquals(artworkStates(source.structure.drawing, native: native).last);
    }
    final AiNativePath following = result.structure.drawing.paths.last;
    final AiNativePath original = source.structure.drawing.paths.single;
    check(_bytes(result, following.start, following.end)).deepEquals(_bytes(source, original.start, original.end));
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('creates a mask with its native owner and retains it on a second insertion', () {
    final String mask = artboardOpacityMask(art: '%_0.3 g 0 0 m 10 0 L 10 10 L f\n');
    final String pair = appearanceArtworkPair(metadata: true).replaceFirst('(Native) /String (AIArtName)', '(Native) /String (AIArtName) ,\n$mask%_(AI9_Mask)');
    final AiNativeAppearances first = _insert(_new(), pair);
    final AiNativeAppearanceArtwork owner = first.artworkFor(use: first.uses.single);
    check(owner.opacityMasks.single.artworkDrawing.paths).length.equals(1);
    check(owner.opacityMasks.single.settings.linked).isTrue();
    final AiNativeAppearances second = _insert(first, appearanceArtworkPair());
    final AiNativeAppearanceArtwork retained = second.artworkFor(use: second.uses.first);
    check(retained.opacityMasks.single.artworkBytes).deepEquals(owner.opacityMasks.single.artworkBytes);
    check(_bytes(second, retained.start, retained.end)).deepEquals(_bytes(first, owner.start, owner.end));
  });

  test('rejects captured identifiers and multiple owners without mutating the source', () {
    final AiNativeAppearances source = _new();
    check(() => _insert(source, appearanceArtworkPair(metadata: true).replaceFirst('(author)', '(root)'))).throws<ArgumentError>();
    final AiNativeAppearances first = _insert(source, appearanceArtworkPair(metadata: true));
    check(() => _insert(first, appearanceArtworkPair(metadata: true))).throws<ArgumentError>();
    check(() => _insert(source, '${appearanceArtworkPair()}${appearanceArtworkPair()}')).throws<FormatException>();
    check(() => _insert(source, appearanceArtworkPair().replaceFirst('(Shared)', '(Missing)'))).throws<UnsupportedError>();
    check(source.uses).isEmpty();
    check(first.uses).length.equals(1);
  });

  test('rejects opaque prefixes detached content and unknown inherited inputs', () {
    final AiNativeAppearances source = _new();
    for (final String bytes in [
      '17 FutureState\n${appearanceArtworkPair()}',
      '${appearanceArtworkPair()}\n0 0 m 1 0 L 1 1 L f',
      '${appearanceArtworkPair()}\n0 g',
      '%%UnresolvedArtworkMetadata: value\n${appearanceArtworkPair()}',
    ]) {
      check(() => _insert(source, bytes)).throws<UnsupportedError>();
    }
    final String inherited = appearanceArtworkPair().replaceFirst(appearanceArtworkState, '');
    check(_insert(source, inherited).uses).length.equals(1);
    final AiNativeAppearances unknown = appearanceEditingModel(
      source: latin1.decode(source.structure.drawing.records.program.bytes).replaceAll(RegExp(r'0(?:\.0)? 1(?:\.0)? 0(?:\.0)? 0(?:\.0)? 0(?:\.0)? Xy'), ''),
    );
    check(() => _insert(unknown, inherited)).throws<UnsupportedError>();
    check(source.uses).isEmpty();
  });

  test('requires current placement handles and bounds aggregate output', () {
    final AiNativeAppearances source = _new();
    final AiNativeAppearances foreign = _new();
    check(() => source.createArtwork(bytes: latin1.encode(appearanceArtworkPair()), bounds: _bounds(), layer: foreign.structure.drawing.records.program.layers.single)).throws<ArgumentError>();
    final String text = latin1.decode(source.structure.drawing.records.program.bytes);
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length + 16),
    );
    check(() => _insert(bounded, appearanceArtworkPair())).throws<AiLimitException>();
    check(() => source.createArtwork(bytes: [256], bounds: _bounds())).throws<ArgumentError>();
    check(() => source.createArtwork(bytes: [], bounds: _bounds())).throws<ArgumentError>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(text);
  });
}
