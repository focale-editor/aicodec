import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_live_shape_affine_test.dart';
import 'ai_native_test.dart' as fixtures;

/// Reopens independent source spelling after a local fixture mutation.
AiNativeDrawing _read(String source, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(source), limits: limits),
  ),
);

/// Supplies a complete native/printing transaction from explicit half-edges.
AiNativeLiveShapeReplacement parallelogramReplacement(AiLiveShape shape, AiNativeParallelogram geometry, {double rotationRadians = 0}) => AiNativeLiveShapeReplacement(
  shape: shape,
  parameters: geometry.parameters(rulerOriginX: 1000, rulerOriginY: 2000),
  segments: geometry.segments,
  printing: shape.appearanceGroup == null ? null : affinePrinting(geometry.segments),
  rotationRadians: rotationRadians,
  bounds: affineBounds,
);

/// Saves the host PDF and native source through compressed aliased AI streams.
AiPdfDocument affineSave(AiPdfDocument original, AiNativeSource source, AiNativeDrawing drawing, String pdfCommands) {
  final PdfEditor host = PdfEditor(document: original.pdf);
  for (int index = 0; index < host.document.pages.length; index++) {
    host.setPageContent(pageIndex: index, bytes: latin1.encode(pdfCommands));
  }
  final AiPdfDocument saved = AiNativeData.replace(source: source, program: drawing.records.program.bytes, synchronizedPdf: host.document, blockBytes: 53);
  return const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
}

/// Covers redundant metadata, atomic failure and complete file persistence.
void main() {
  test('updates parameters, contour, printing and older frame alternative together', () {
    final String text = latin1
        .decode(affineDrawing(pair: true).records.program.bytes)
        .replaceFirst(
          '${affineDictionary()}\n1 (Shared) XW',
          '%AI17_Begin_Content_if_version_gt:17 4\n${affineDictionary()}\n%AI17_Alternate_Content\n%_/ArtDictionary : (0) /String (BBAccumRotation) , ;\n%AI17_End_Versioned_Content\n1 (Shared) XW',
        );
    final AiNativeDrawing source = _read(text);
    final AiNativeParallelogram geometry = AiNativeParallelogram(centerX: 15, centerY: 5, ux: 10, uy: 0, vx: 5, vy: 5);
    final AiNativeDrawing changed = source.replaceLiveShapes(replacements: [parallelogramReplacement(source.liveShapes.single, geometry, rotationRadians: 0.5)]);
    check(changed.liveShapes.single.alternativeDictionaries).length.equals(1);
    check(changed.liveShapes.single.alternativeDictionaries.single['BBAccumRotation']!.text()).equals('0.500000');
    check(changed.liveShapes.single.parallelogram!.vx).equals(5);
    check(changed.paths.last.segments.map((segment) => segment.coordinates)).deepEquals(source.paths.last.segments.map((segment) => segment.coordinates));
  });

  test('batch replacements union bounds once and retain distinct native ownership', () {
    final String text = latin1.decode(affineDrawing(peer: false).records.program.bytes);
    final String body = text.split('%%EndSetup').last.split('%%Trailer').first;
    final AiNativeDrawing source = _read(text.replaceFirst('%%Trailer', '$body\n%%Trailer'));
    final AiNativeDrawing changed = source.replaceLiveShapes(
      replacements: [
        for (final (int index, AiLiveShape shape) in source.liveShapes.indexed)
          parallelogramReplacement(shape, AiNativeParallelogram(centerX: 15 + index * 50, centerY: 5, ux: 10, uy: 0, vx: 5, vy: 5)),
      ],
    );
    check(changed.liveShapes.map((shape) => shape.parallelogram!.centerX)).deepEquals([15.0, 65.0]);
    check(changed.liveShapes.every((shape) => shape.isBound)).isTrue();
    check(latin1.decode(changed.records.program.bytes).split('%%BoundingBox:')).length.equals(2);
  });

  test('preserves private classification for multiline geometry and inline paint', () {
    final String text = latin1.decode(affineDrawing(pair: true).records.program.bytes).replaceFirst('%_$affineRectangle n', '%_0 0 m\n%_20 0 L % retained\n%_20 10 L\n%_0 10 L\n%_0 0 L n');
    final AiNativeDrawing source = _read(text);
    final AiNativeDrawing changed = source.replaceLiveShapes(
      replacements: [parallelogramReplacement(source.liveShapes.single, AiNativeParallelogram(centerX: 15, centerY: 5, ux: 10, uy: 0, vx: 5, vy: 5))],
    );
    check(changed.liveShapes.single.path!.isPrivate).isTrue();
    check(changed.liveShapes.single.path!.geometry.every((command) => command.isPrivate)).isTrue();
    check(latin1.decode(changed.records.program.bytes)).contains('% retained');
  });

  test('rejects inconsistent copies, state leakage, stale handles and byte limits atomically', () {
    final AiNativeDrawing source = affineDrawing(pair: true);
    final AiNativeParallelogram geometry = AiNativeParallelogram(centerX: 15, centerY: 5, ux: 10, uy: 0, vx: 5, vy: 5);
    final AiNativeLiveShapeReplacement replacement = parallelogramReplacement(source.liveShapes.single, geometry);
    final String before = latin1.decode(source.records.program.bytes);
    final AiNativeDrawing mismatch = _read(before.replaceFirst('20 /Real (ai::Rectangle::Width)', '21 /Real (ai::Rectangle::Width)'));
    check(() => mismatch.replaceLiveShapes(replacements: [parallelogramReplacement(mismatch.liveShapes.single, geometry)])).throws<UnsupportedError>();
    check(() => source.replaceLiveShapes(replacements: [replacement, replacement])).throws<ArgumentError>();
    check(() => affineDrawing(pair: true).replaceLiveShapes(replacements: [replacement])).throws<ArgumentError>();
    check(
      () => source.replaceLiveShapes(
        replacements: [
          AiNativeLiveShapeReplacement(
            shape: replacement.shape,
            parameters: replacement.parameters,
            segments: replacement.segments,
            printing: latin1.encode(latin1.decode(replacement.printing!).replaceFirst('u\n', 'u\n1 g\n')),
            bounds: affineBounds,
            rotationRadians: 0,
          ),
        ],
      ),
    ).throws<UnsupportedError>();
    final AiNativeDrawing bounded = _read(before, limits: AiNativeLimits(maxDecodedBytes: before.length));
    check(() => bounded.replaceLiveShapes(replacements: [parallelogramReplacement(bounded.liveShapes.single, geometry)])).throws<FormatException>();
    check(latin1.decode(source.records.program.bytes)).equals(before);
  });

  test('only recognizes actual nondegenerate parallelograms', () {
    final AiNativeDrawing source = affineDrawing(handler: 'ai::Polygon');
    final AiNativeDrawing irregular = _read(latin1.decode(source.records.program.bytes).replaceAll('1 /Bool (ai::Polygon::IsRegular)', '0 /Bool (ai::Polygon::IsRegular)'));
    check(irregular.liveShapes.single.parallelogram).isNotNull();
    final AiNativeDrawing trapezoid = _read(latin1.decode(irregular.records.program.bytes).replaceFirst('20 10 L', '15 10 L'));
    check(trapezoid.liveShapes.single.parallelogram).isNull();
    check(() => AiNativeParallelogram(centerX: 1e15, centerY: 0, ux: 0.001, uy: 0, vx: 0, vy: 1)).throws<ArgumentError>();
  });

  test('complete AI save reopens native parallelogram, printing, PDF and references for another edit', () {
    final AiPdfDocument original = fixtures.nativePdf(compression: .zstandard, alias: true, thumbnail: true, nativeProgram: latin1.decode(affineDrawing(pair: true).records.program.bytes));
    final AiNativeSource source = AiNativeData.extract(original).single;
    final AiNativeDrawing drawing = _read(latin1.decode(source.bytes));
    final AiNativeParallelogram geometry = AiNativeParallelogram(centerX: 15, centerY: 5, ux: 10, uy: 0, vx: 5, vy: 5);
    final AiNativeDrawing changed = drawing.replaceLiveShapes(replacements: [parallelogramReplacement(drawing.liveShapes.single, geometry)]);
    const String commands = '0 g 0 0 m 20 0 l 30 10 l 10 10 l h f 50 0 m 60 10 l S';
    final AiPdfDocument reopened = affineSave(original, source, changed, commands);
    final AiNativeSource updatedSource = AiNativeData.extract(reopened).single;
    final AiNativeDrawing updated = _read(latin1.decode(updatedSource.bytes));
    check(updatedSource.owners).deepEquals(source.owners);
    check(updated.liveShapes.single.parallelogram!.vx).equals(5);
    check(updated.liveShapes.single.appearancePaths.single.segments.map((segment) => segment.coordinates)).deepEquals(geometry.segments.map((segment) => segment.coordinates));
    for (final PdfPage page in reopened.pdf.pages) {
      check(latin1.decode(reopened.pdf.pageContent(page))).equals(commands);
    }
    final AiNativeParallelogram resized = AiNativeParallelogram(centerX: 20, centerY: 10, ux: 15, uy: 0, vx: 5, vy: 10);
    final AiNativeDrawing again = updated.replaceLiveShapes(replacements: [parallelogramReplacement(updated.liveShapes.single, resized)]);
    final AiPdfDocument finalFile = affineSave(reopened, updatedSource, again, '0 g 0 0 m 30 0 l 40 20 l 10 20 l h f 50 0 m 60 10 l S');
    check(_read(latin1.decode(AiNativeData.extract(finalFile).single.bytes)).liveShapes.single.parallelogram!.ux).equals(15);
  });
}
