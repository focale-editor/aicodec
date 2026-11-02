import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkPair, appearanceArtworkSource, appearanceArtworkState;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceAuthoring;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_nested_styles_test.dart' show nestedAppearanceOwners, nestedAppearanceSource;
import 'ai_native_artboard_masks_test.dart' show artboardOpacityMask;
import 'ai_native_document_creation_test.dart' show newDocumentPdf, newDocumentRecords, newDocumentSave;
import 'ai_native_opacity_masks_test.dart' show opacityMaskSource;
import 'ai_native_path_artwork_test.dart' show artworkStates;
import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;

/// Supplies a known final native gray independently of the printing black fill.
String appearanceRemovalSource({String? pair, String tail = '', bool visible = true}) {
  final AiNativeAppearances model =
      AiNativeAppearances.decode(
        structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: true))),
      ).createStyle(
        nameBytes: latin1.encode('Shared'),
        execution: AiNativeAppearancePartDefinition(
          kind: .fill,
          visible: visible,
          colors: [
            AiColor(space: .gray, channels: [.25]),
          ],
        ),
      );
  return latin1.decode(model.structure.drawing.records.program.bytes).replaceFirst('%%PageTrailer', '${pair ?? appearanceArtworkPair(metadata: true)}\n$tail\n%%PageTrailer');
}

/// Reads exact bytes rather than normalizing retained source geometry or metadata.
List<int> _bytes(AiNativeAppearances model, int start, int end) => model.structure.drawing.records.program.bytes.sublist(start, end);

/// Deletes every complete public owner against the same immutable snapshot.
AiNativeAppearances _removeAll(AiNativeAppearances model) => model.removeArtwork(artwork: nestedAppearanceOwners(model).map((use) => model.artworkFor(use: use)).toList());

/// Covers complete removal, reference safety and both streams' observable outputs.
void main() {
  test('removes both representations and identity then saves a blank native document', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceRemovalSource());
    final AiNativeAppearances result = _removeAll(source);
    check(result.uses).isEmpty();
    check(result.structure.drawing.paths).isEmpty();
    check(result.structure.drawing.groups).isEmpty();
    check(result.styles).length.equals(1);
    check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => latin1.decode(identity.bytes))).deepEquals(['root']);
    final AiPdfDocument saved = newDocumentSave(result.structure.drawing.records, newDocumentPdf(blank: true));
    final AiNativeAppearances reopened = appearanceEditingModel(source: latin1.decode(AiNativeData.extract(saved).single.bytes));
    check(reopened.structure.drawing.paths).isEmpty();
    check(reopened.removeStyles(styles: reopened.styles).styles).isEmpty();
    check(source.uses).length.equals(1);
  });

  test('removes nested applications with their owner and keeps the other pair exact', () {
    for (final bool compound in [false, true]) {
      final AiNativeAppearances source = appearanceEditingModel(source: nestedAppearanceSource(compound: compound));
      final List<AiNativeResourceUse> uses = nestedAppearanceOwners(source);
      final AiNativeAppearanceArtwork removed = source.artworkFor(use: uses.first);
      final AiNativeAppearanceArtwork neighbor = source.artworkFor(use: uses.last);
      final AiNativeAppearances result = source.removeArtwork(artwork: [removed]);
      final AiNativeAppearanceArtwork retained = result.artworkFor(use: nestedAppearanceOwners(result).single);
      check(result.uses).length.equals(neighbor.nestedUses.length + 1);
      check(result.styles).length.equals(source.styles.length);
      check(_bytes(result, retained.start, retained.end)).deepEquals(_bytes(source, neighbor.start, neighbor.end));
      check(_removeAll(result).uses).isEmpty();
    }
  });

  test('restores different native and printing colors before an inherited fill', () {
    const String tail = '50 0 m 60 0 L 60 10 L f';
    final String text = appearanceRemovalSource(tail: tail);
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances result = _removeAll(source);
    check(result.structure.drawing.paths).length.equals(1);
    check(artworkStates(result.structure.drawing, native: true).single['fill']!).deepEquals(['g', .25]);
    check(artworkStates(result.structure.drawing, native: false).single['fill']!).deepEquals(['k', 0, 0, 0, 1]);
    final AiNativePath path = result.structure.drawing.paths.single;
    check(latin1.decode(_bytes(result, path.start, path.end))).equals(tail);
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('retains clipping boundary outputs rather than replaying transient widths', () {
    final String authoring = clippingAppearanceAuthoring('closed').replaceFirst('%_q\n', '%_q\n%_19 w\n');
    final String pair = appearanceArtworkPair().replaceFirst('%_0 D', '%_7 w\n%_0 D').replaceFirst('%_0 0 m 10 0 L 10 10 L 0 0 L n', authoring);
    final AiNativeAppearances source = appearanceEditingModel(
      source: appearanceRemovalSource(pair: pair, tail: '50 0 m 60 0 L s'),
    );
    final AiNativeAppearances result = _removeAll(source);
    check(artworkStates(result.structure.drawing, native: true).single['w']!).deepEquals(['w', 7]);
    check(artworkStates(result.structure.drawing, native: false).single['w']!).deepEquals(['w', 1]);
    check(result.structure.drawing.groups).isEmpty();
  });

  test('refuses unknown style outputs consumed by a neighbor but accepts explicit resets', () {
    final String text = appearanceRemovalSource(pair: appearanceArtworkPair(), visible: false, tail: '50 0 m 60 0 L 60 10 L f');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    check(() => _removeAll(source)).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    final AiNativeAppearances reset = appearanceEditingModel(source: text.replaceFirst('50 0 m', '$appearanceArtworkState\n50 0 m'));
    check(_removeAll(reset).structure.drawing.paths).length.equals(1);
    final AiNativeAppearances terminal = appearanceEditingModel(source: appearanceRemovalSource(pair: appearanceArtworkPair(), visible: false));
    check(_removeAll(terminal).structure.drawing.paths).isEmpty();
  });

  test('removes attached masks and child geometry while preserving the neighbor', () {
    for (final (bool, bool) selection in [(false, false), (true, false), (true, true)]) {
      final AiNativeAppearances source = appearanceEditingModel(
        source: opacityMaskSource(grouped: selection.$1, child: selection.$2),
      );
      final AiNativeAppearanceArtwork neighbor = source.artworkFor(use: source.uses.last);
      final AiNativeAppearances result = source.removeArtwork(artwork: [source.artworkFor(use: source.uses.first)]);
      final AiNativeAppearanceArtwork retained = result.artworkFor(use: result.uses.single);
      check(result.structure.drawing.records.containers.where((record) => record.type == 'Mask')).isEmpty();
      check(_bytes(result, retained.start, retained.end)).deepEquals(_bytes(source, neighbor.start, neighbor.end));
    }
  });

  test('retains a masked live-shape neighbor while deleting identified alternatives', () {
    final String text = identifiedShapeLifecycleSource();
    final AiNativeAppearances initial = appearanceEditingModel(source: text);
    final AiNativeAppearanceArtwork last = initial.artworkFor(use: initial.uses.last);
    final int position = last.dictionary!.start + '/ArtDictionary :'.length;
    final String mask = '\n${artboardOpacityMask(art: '%_0.3 g 0 0 m 10 0 L 10 10 L f\n')}%_(AI9_Mask) ,\n%_';
    final AiNativeAppearances source = appearanceEditingModel(source: text.replaceRange(position, position, mask));
    final AiNativeAppearanceArtwork neighbor = source.artworkFor(use: source.uses.last);
    final AiNativeAppearances result = source.removeArtwork(artwork: [source.artworkFor(use: source.uses.first)]);
    final AiNativeAppearanceArtwork retained = result.artworkFor(use: result.uses.single);
    check(result.structure.drawing.liveShapes).length.equals(1);
    check(result.structure.identifiers).isEmpty();
    check(retained.opacityMasks.single.artworkBytes).deepEquals(neighbor.opacityMasks.single.artworkBytes);
    check(_bytes(result, retained.start, retained.end)).deepEquals(_bytes(source, neighbor.start, neighbor.end));
    check(_removeAll(result).structure.drawing.liveShapes).isEmpty();
  });

  test('keeps opaque unrelated setup but refuses deleting identities beside unknown references', () {
    const String opaque = '/Dictionary : /XMLUID : (author) ; (FutureReference) , ;\n';
    for (final bool identified in [false, true]) {
      final String text = appearanceRemovalSource(pair: appearanceArtworkPair(metadata: identified)).replaceFirst('%%EndSetup', '$opaque%%EndSetup');
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      if (identified) {
        check(() => _removeAll(source)).throws<UnsupportedError>();
      } else {
        final AiNativeAppearances result = _removeAll(source);
        check(latin1.decode(result.structure.drawing.records.program.bytes)).contains(opaque);
      }
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('requires current distinct handles and unambiguous deleted identities', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceArtworkSource(metadata: true));
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    check(() => source.removeArtwork(artwork: [])).throws<ArgumentError>();
    check(
      () => source.removeArtwork(
        artwork: [
          owner,
          source.artworkFor(use: source.uses.first),
        ],
      ),
    ).throws<ArgumentError>();
    final AiNativeAppearances result = source.removeArtwork(artwork: [owner]);
    check(() => result.removeArtwork(artwork: [owner])).throws<ArgumentError>();
    final AiNativeAppearances foreign = appearanceEditingModel(source: appearanceArtworkSource(metadata: true));
    check(() => source.removeArtwork(artwork: [foreign.artworkFor(use: foreign.uses.first)])).throws<ArgumentError>();
    final AiNativeAppearances duplicate = appearanceEditingModel(source: appearanceRemovalSource(pair: '${appearanceArtworkPair(metadata: true)}${appearanceArtworkPair(metadata: true)}'));
    check(() => _removeAll(duplicate)).throws<UnsupportedError>();
    final AiNativeAppearances identifiedMask = appearanceEditingModel(
      source: opacityMaskSource(mask: artboardOpacityMask(art: '%_0.3 g 0 0 m 10 0 L 10 10 L f\n%_/ArtDictionary : /XMLUID : (mask-art) ; (AI10_ArtUID) , ;\n')),
    );
    check(_removeAll(identifiedMask).structure.identifiers).isEmpty();
  });

  test('deletes a reversed batch with original limits and no orphaned style applications', () {
    final String text = appearanceRemovalSource(pair: '${appearanceArtworkPair()}${appearanceArtworkPair()}');
    final AiNativeAppearances source = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length),
    );
    final AiNativeAppearances result = source.removeArtwork(artwork: source.uses.reversed.map((use) => source.artworkFor(use: use)).toList());
    check(result.uses).isEmpty();
    check(result.structure.drawing.paths).isEmpty();
    check(result.structure.drawing.groups).isEmpty();
    check(result.structure.drawing.records.program.limits).identicalTo(source.structure.drawing.records.program.limits);
    check(result.styles.single.uses).isEmpty();
  });
}
