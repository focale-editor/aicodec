import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_document_creation_test.dart' show newDocumentPath, newDocumentRecords, newDocumentSave;

/// Supplies explicit process paints independently of the unpainted native path.
AiNativeAppearances _model() =>
    AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(drawing: AiNativeDrawing.decode(records: newDocumentRecords(blank: true))),
    ).createStyle(
      nameBytes: latin1.encode('Paint (standalone)'),
      execution: AiNativeAppearancePartDefinition(
        kind: .fill,
        colors: [
          AiColor(space: .rgb, channels: [1, 0, 0]),
        ],
      ),
    );

/// Retains geometry and metadata while assigning paints through the named style.
AiNativePathDefinition _contour({bool closed = true, bool counted = true, String identity = 'standalone'}) => AiNativePathDefinition(
  artwork: AiArtworkPath(segments: newDocumentPath(0).artwork.segments, closed: closed, locked: true),
  bounds: newDocumentPath(0).bounds,
  counted: counted,
  nameBytes: utf8.encode('Contour (été)'),
  identifierBytes: ascii.encode(identity),
);

/// Distinct host printing whose ownership must remain separate from authoring.
List<int> _printing() => ascii.encode('u\n1 0 0 Xa\n10 10 m 30 10 L 30 30 L f\nU');

/// Inserts one typed contour in the current root layer without a group wrapper.
AiNativeAppearances _create(AiNativeAppearances model, {AiNativePathDefinition? definition}) => model.createPathArtwork(
  definition: definition ?? _contour(),
  styleNameBytes: latin1.encode('Paint (standalone)'),
  printingBytes: _printing(),
  layer: model.structure.drawing.records.program.layers.single,
);

/// Checks native carrier identity across typed creation and subsequent mutations.
void main() {
  test('authors open and closed standalone contours without introducing native groups', () {
    for (final bool closed in [false, true]) {
      for (final bool counted in [false, true]) {
        final AiNativeAppearances source = _model();
        final AiNativeAppearances result = _create(
          source,
          definition: _contour(closed: closed, counted: counted),
        );
        final AiNativeAppearanceArtwork owner = result.artworkFor(use: result.uses.single);
        check(owner.group).isNull();
        check(owner.path!.isPrivate).isTrue();
        check(owner.path!.paint.operator).equals(closed ? 'n' : 'N');
        check(owner.path!.geometry).length.equals(closed && counted ? 4 : 3);
        check(owner.printingGroup.paths.single.paint.operator).equals('f');
        check(result.structure.drawing.groups.where((group) => group.opening.isPrivate)).isEmpty();
        check(result.structure.drawing.items.whereType<AiNativeInstruction>().where((item) => item.isPrivate && item.operator == 'As')).length.equals(counted ? 1 : 0);
        check(utf8.decode(owner.dictionary!['AIArtName']!.stringBytes!)).equals('Contour (été)');
        check(result.structure.identifiers.where((identifier) => identifier.kind == .xmlArt).map((identity) => ascii.decode(identity.bytes)).toSet()).deepEquals({'root', 'standalone'});
        check(result.resolve(use: owner.use)).identicalTo(result.styles.single);
        check(owner.nestedUses).isEmpty();
        check(source.uses).isEmpty();
      }
    }
  });

  test('attaches a mask to the exact path and retains it through geometry edits and a save', () {
    final AiNativeAppearances source = _create(_model());
    final AiNativeAppearanceArtwork before = source.artworkFor(use: source.uses.single);
    final List<int> maskBytes = AiNativeOpacityMask.encodeVectorArtwork(
      records: source.structure.drawing.records,
      elements: [],
    );
    final AiNativeAppearances masked = source.createOpacityMasks(
      masks: [
        AiNativeOpacityMaskAttachment(
          artwork: before,
          target: before.path,
          settings: const AiNativeOpacityMaskSettings(linked: false, disabled: true, clipping: false, inverted: true),
          artworkBytes: maskBytes,
        ),
      ],
      artwork: [AiNativeAppearanceReplacement(artwork: before, bytes: _printing(), bounds: _contour().bounds)],
    );
    final AiNativeAppearanceArtwork owner = masked.artworkFor(use: masked.uses.single);
    check(owner.authoringForMask(mask: owner.opacityMasks.single)).identicalTo(owner.path!);
    final List<AiPathSegment> geometry = [
      AiPathSegment(operator: 'm', coordinates: [11, 10]),
      AiPathSegment(operator: 'L', coordinates: [30, 10]),
      AiPathSegment(operator: 'L', coordinates: [30, 30]),
    ];
    final List<int> printing = ascii.encode('u\n1 0 0 Xa\n11 10 m 30 10 L 30 30 L f\nU');
    final AiNativeAppearances edited = masked.editArtworkPaths(
      edits: [AiNativePathEdit(path: owner.path!, segments: geometry)],
      artwork: [AiNativeAppearanceReplacement(artwork: owner, bytes: printing, bounds: _contour().bounds)],
    );
    final PdfDocument pdf = PdfDocument.fromPages(
      pages: [PdfPageSource(width: 100, height: 100, content: ascii.encode('q 1 0 0 1 10 20 cm 1 0 0 rg 11 10 m 30 10 l 30 30 l h f Q'))],
    );
    final AiPdfDocument saved = newDocumentSave(edited.structure.drawing.records, pdf);
    final AiNativeAppearances reopened = AiNativeAppearances.decode(
      structure: AiNativeStructure.decode(
        drawing: AiNativeDrawing.decode(
          records: AiNativeRecords.decode(program: AiProgram.decode(bytes: AiNativeData.extract(saved).single.bytes)),
        ),
      ),
    );
    final AiNativeAppearanceArtwork after = reopened.artworkFor(use: reopened.uses.single);
    check(after.path!.geometry.first.numbers).isNotNull().deepEquals([11.0, 10.0]);
    check(after.group).isNull();
    check(after.authoringForMask(mask: after.opacityMasks.single)).identicalTo(after.path!);
    check(after.opacityMasks.single.artworkBytes).deepEquals(maskBytes);
    check(after.opacityMasks.single.settings.linked).isFalse();
    check(after.opacityMasks.single.settings.disabled).isTrue();
    check(after.opacityMasks.single.settings.clipping).isFalse();
    check(after.opacityMasks.single.settings.inverted).isTrue();
    check(saved.pdf.pageContent(saved.pdf.pages.single)).deepEquals(pdf.pageContent(pdf.pages.single));
    check(before.opacityMasks).isEmpty();
  });

  test('preserves a complete standalone pair when ordinary artwork follows it', () {
    final AiNativeAppearances source = _create(_model());
    final AiNativeAppearanceArtwork before = source.artworkFor(use: source.uses.single);
    final List<int> retained = source.structure.drawing.records.program.bytes.sublist(before.start, before.end);
    final AiNativeDrawing drawing = source.structure.drawing.createPath(definition: newDocumentPath(1), layer: source.structure.drawing.records.program.layers.single);
    final AiNativeAppearances result = AiNativeAppearances.decode(structure: AiNativeStructure.decode(drawing: drawing));
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.single);
    check(drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(retained);
    check(drawing.paths.last.isPrivate).isFalse();
    check(drawing.paths.last.start > after.end).isTrue();
  });

  test('rejects ambiguous paint ownership missing styles and duplicate identities atomically', () {
    final AiNativeAppearances source = _model();
    final List<int> original = source.structure.drawing.records.program.bytes.toList();
    check(() => _create(source, definition: newDocumentPath(0))).throws<ArgumentError>();
    for (final List<int> name in [
      <int>[],
      [256],
    ]) {
      check(() => source.createPathArtwork(definition: _contour(), styleNameBytes: name, printingBytes: _printing())).throws<ArgumentError>();
    }
    check(() => source.createPathArtwork(definition: _contour(), styleNameBytes: ascii.encode('Missing'), printingBytes: _printing())).throws<UnsupportedError>();
    check(() => _create(source, definition: _contour(identity: 'root'))).throws<ArgumentError>();
    final AiNativeAppearances first = _create(source);
    check(() => _create(first)).throws<ArgumentError>();
    check(source.structure.drawing.records.program.bytes).deepEquals(original);
  });
}
