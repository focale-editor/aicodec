import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aicodec/aicodec.dart';

/// Exercises required native extraction and editing against the pinned corpus.
Future<void> main() async {
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/manifest.json').readAsString()) as Map).cast<String, Object?>();
  final Directory output = await Directory('test/corpus/output/native').create(recursive: true);
  final List<Map<String, Object?>> results = [];
  int failures = 0;
  for (final Object? raw in manifest['files']! as List) {
    final Map<String, Object?> entry = (raw! as Map).cast<String, Object?>();
    final String name = entry['file']! as String;
    try {
      final Uint8List bytes = await File('test/corpus/files/$name').readAsBytes();
      final AiDocument document = const AiCodec().decode(bytes);
      final List<AiNativeSource> sources = AiNativeData.extract(document);
      if (sources.length != 1) {
        throw StateError('This pinned corpus expects one native program per fixture.');
      }
      final AiNativeSource source = sources.single;
      final AiProgram program = AiProgram.decode(bytes: source.bytes);
      final AiNativeRecords records = AiNativeRecords.decode(program: program);
      final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
      int textDocuments = 0;
      int textStories = 0;
      int composedStories = 0;
      int rejectedPathLayouts = 0;
      int translatedTextFrames = 0;
      for (final AiNativeContainer container in records.containers.where((record) => record.type == 'AI11TextDocument')) {
        final AiNativeTextDocument text = AiNativeTextDocument.decode(records: records, container: container);
        if (text.referenceIssues.isNotEmpty) {
          throw StateError('Native text resources or references differ from the pinned fixture.');
        }
        final AiNativeTextDocument renamed = text.characterStyles.isEmpty
            ? AiNativeTextDocument.decode(
                records: records.replaceBinary(container: container, bytes: text.engine.bytes),
              )
            : text.renameStyle(style: text.characterStyles.first, name: 'AiCodec corpus style 🖋');
        if (renamed.characterStyles.isNotEmpty && renamed.characterStyles.first.name != 'AiCodec corpus style 🖋' || renamed.referenceIssues.isNotEmpty) {
          throw StateError('Native text style rename failed to retain valid references.');
        }
        textDocuments++;
        textStories += text.stories.length;
        await File('${output.path}/$name.text-model.json').writeAsString(const JsonEncoder.withIndent('  ').convert(_textModel(text)));
        await File('${output.path}/$name.text-renamed.ps').writeAsBytes(renamed.records.program.bytes);
        await File('${output.path}/$name.ate').writeAsBytes(text.engine.bytes);
        await File('${output.path}/$name.renamed.ate').writeAsBytes(renamed.engine.bytes);
        final AiNativeTextDocument fonts = text
            .addFont(
              font: AiNativeFontDefinition(postScriptName: 'FocaleCorpus-Regular', technology: .postScript, version: 'Version 1.000'),
            )
            .addFont(
              font: AiNativeFontDefinition(postScriptName: 'FocaleCorpusVariable_500wght', technology: .trueType, axisCoordinates: [500 * 65536, -10 * 65536]),
            );
        if (fonts.referenceIssues.isNotEmpty || fonts.fonts.length != text.fonts.length + 2) {
          throw StateError('Native font registration changed existing references.');
        }
        await File('${output.path}/$name.fonts.ate').writeAsBytes(fonts.engine.bytes);
        await File('${output.path}/$name.fonts.ps').writeAsBytes(fonts.records.program.bytes);
        if (text.frames.isNotEmpty) {
          final AiNativeTextDocument moved = text.translateFrames(frames: text.frames, deltaX: 37.25, deltaY: -19.5);
          if (moved.referenceIssues.isNotEmpty) {
            throw StateError('Text frame translation changed native references.');
          }
          await File('${output.path}/$name.frames.ate').writeAsBytes(moved.engine.bytes);
          await File('${output.path}/$name.frames.ps').writeAsBytes(moved.records.program.bytes);
          translatedTextFrames += text.frames.length;
          if (name == 'text_transforms.ai') {
            final AiNativeTextDocument partial = text.translateFrames(frames: [text.frames.first], deltaX: 37.25, deltaY: -19.5);
            await File('${output.path}/$name.frame-0.ate').writeAsBytes(partial.engine.bytes);
            await File('${output.path}/$name.frame-0.ps').writeAsBytes(partial.records.program.bytes);
          }
        }
        for (final AiNativeTextStory story in text.stories) {
          final AiNativeTextDocument invalidated = text.withoutTextLayout(story: story);
          await File('${output.path}/$name.story-${story.index}.invalidated.ate').writeAsBytes(invalidated.engine.bytes);
          await File('${output.path}/$name.story-${story.index}.invalidated.ps').writeAsBytes(invalidated.records.program.bytes);
          final AiNativeTextDocument edited = text.replaceText(story: story, start: 0, end: story.text.length < 5 ? story.text.length : 5, text: 'Édité 🖋\u0003suite\r');
          if (edited.referenceIssues.isNotEmpty || edited.stories[story.index].strikes.isNotEmpty) {
            throw StateError('Native content edit retained stale layout or invalid references.');
          }
          await File('${output.path}/$name.story-${story.index}.edited.ate').writeAsBytes(edited.engine.bytes);
          await File('${output.path}/$name.story-${story.index}.edited.ps').writeAsBytes(edited.records.program.bytes);
          final AiNativeTextDocument characters = text.setCharacterFeatures(
            story: story,
            start: 1,
            end: story.modelText.length < 4 ? story.modelText.length : 4,
            changes: AiNativeCharacterChanges(fontSize: 24, tracking: 35, leading: 29, ligatures: false),
          );
          final AiNativeTextDocument paragraphs = text.setParagraphFeatures(
            story: story,
            start: 2,
            end: 3,
            changes: AiNativeParagraphChanges(justification: 2, firstLineIndent: -4, spaceAfter: 6, direction: 0, composer: 1, hyphenate: false),
          );
          final AiNativeTextDocument forcedBreaks = edited.setParagraphFeatures(
            story: edited.stories[story.index],
            start: 10,
            end: 11,
            changes: AiNativeParagraphChanges(justification: 2, firstLineIndent: -4, spaceAfter: 6, direction: 0, composer: 1, hyphenate: false),
          );
          for (final (String suffix, AiNativeTextDocument formatted) in [('characters', characters), ('paragraphs', paragraphs), ('forced-breaks', forcedBreaks)]) {
            if (formatted.referenceIssues.isNotEmpty || formatted.stories[story.index].strikes.isNotEmpty) {
              throw StateError('Native feature edit retained stale layout or invalid references.');
            }
            await File('${output.path}/$name.story-${story.index}.$suffix.ate').writeAsBytes(formatted.engine.bytes);
            await File('${output.path}/$name.story-${story.index}.$suffix.ps').writeAsBytes(formatted.records.program.bytes);
          }
          if (story.frameIndices.any((index) => text.frames[index].kind == .path)) {
            try {
              text.withTextLayout(
                story: story,
                frames: [for (final int index in story.frameIndices) AiNativeTextFrameLayout(frame: text.frames[index], x: 0, y: 0, lines: [])],
                overflowStart: 0,
              );
              throw StateError('Path composition was accepted without per-glyph geometry.');
            } on UnsupportedError {
              rejectedPathLayouts++;
            }
          } else {
            final List<AiNativeTextFrameLayout> frames = _retainedTextLayout(text, story);
            int visibleEnd = 0;
            for (final AiNativeTextFrameLayout frame in frames) {
              for (final AiNativeTextLineLayout line in frame.lines) {
                for (final AiNativeTextSegmentLayout segment in line.segments) {
                  if (segment.end > visibleEnd) {
                    visibleEnd = segment.end;
                  }
                }
              }
            }
            final AiNativeTextDocument composed = text.withTextLayout(story: story, frames: frames, overflowStart: visibleEnd);
            await File('${output.path}/$name.story-${story.index}.layout.ate').writeAsBytes(composed.engine.bytes);
            await File('${output.path}/$name.story-${story.index}.layout.ps').writeAsBytes(composed.records.program.bytes);
            composedStories++;
          }
        }
      }
      if (name == 'flowtext.ai' && (textDocuments != 1 || textStories != 1)) {
        throw StateError('The native area-text fixture lost its story.');
      }
      int binaryBytes = 0;
      for (final AiNativeContainer record in records.containers.where((record) => record.hasBinary)) {
        binaryBytes += record.decodeBinary(maxOutputBytes: program.limits.maxDecodedBytes).length;
      }
      if (name == 'layers_and_sublayers.ai') {
        final List<String?> expected = ['Layer 1', 'Sublayer 1_1', 'Sublayer 1_2', 'Layer 2', 'Sublayer 2_1', 'Sublayer 2_1_1'];
        if (program.layers.map((layer) => layer.name).join('|') != expected.join('|') || program.layers[2].visible || !program.layers[1].locked) {
          throw StateError('Nested layer structure or flags differ from the authored fixture.');
        }
      }
      if (name == 'cmyk_rectangle.ai' || name == 'rgb_rectangle.ai') {
        final AiNativeArtboard artboard = records.artboards.single;
        final AiNativeContainer rectangle = records.roots.where((record) => record.type == 'ArtDictionary' && record['ai::LiveShape'] != null).single['ai::LiveShape']!.container!;
        final AiNativeContainer parameters = rectangle['ai::LiveShape::Params']!.container!;
        if (latin1.decode(artboard.nameBytes) != 'Artboard 1' ||
            !artboard.selected ||
            artboard.bounds.left != 0 ||
            artboard.bounds.bottom != 0 ||
            (artboard.bounds.right - 595.275573730469).abs() > 1e-9 ||
            (artboard.bounds.top - 841.889770507813).abs() > 1e-9 ||
            rectangle['ai::LiveShape::HandlerName']!.text() != 'ai::Rectangle' ||
            parameters['ai::Rectangle::Width']!.number != 180 ||
            parameters['ai::Rectangle::Height']!.number != 211) {
          throw StateError('Native artboard or live-shape parameters differ from the authored fixture.');
        }
      }
      await File('${output.path}/$name.native.ps').writeAsBytes(source.bytes);
      final int? expectedShapes = _translatedFixtures[name];
      if (expectedShapes != null) {
        if (drawing.liveShapes.length != expectedShapes || drawing.liveShapes.any((shape) => !shape.isBound)) {
          throw StateError('Native live-shape associations differ from the pinned fixture.');
        }
        final AiNativeDrawing translated = drawing.translateLiveShapes(shapes: drawing.liveShapes, deltaX: 37, deltaY: -19);
        final Set<AiNativePath> moved = {
          for (final AiLiveShape shape in drawing.liveShapes) ...[shape.path!, ...shape.appearancePaths],
        };
        if (translated.paths.length != drawing.paths.length || translated.liveShapes.length != expectedShapes) {
          throw StateError('Native translation changed drawing topology.');
        }
        for (int index = 0; index < drawing.paths.length; index++) {
          final AiNativePath original = drawing.paths[index];
          final AiNativePath changed = translated.paths[index];
          for (int segment = 0; segment < original.segments.length; segment++) {
            final AiPathSegment before = original.segments[segment];
            final AiPathSegment after = changed.segments[segment];
            if (before.operator != after.operator || before.coordinates.length != after.coordinates.length) {
              throw StateError('Native translation changed path semantics.');
            }
            for (int coordinate = 0; coordinate < before.coordinates.length; coordinate++) {
              final double expected = before.coordinates[coordinate] + (moved.contains(original) ? (coordinate.isEven ? 37 : -19) : 0);
              if ((after.coordinates[coordinate] - expected).abs() > 1e-9) {
                throw StateError('Native translation failed to synchronize a path coordinate.');
              }
            }
          }
        }
        // Keep native geometry edits separate from PDF rewrites until the host
        // supplies a regenerated compatibility view for the moved artwork.
        await File('${output.path}/$name.translated.ps').writeAsBytes(translated.records.program.bytes);
      }
      if (document is AiPdfDocument) {
        await File('${output.path}/$name.envelope').writeAsBytes(_envelope(document));
      }
      AiProgram edited = program.layers.isEmpty ? program : AiNativeEditor.updateLayer(program: program, layer: program.layers.first, name: 'AiCodec corpus layer');
      final AiNativeRecords editedRecords = AiNativeRecords.decode(program: edited);
      if (editedRecords.artboards.isNotEmpty) {
        edited = editedRecords.replaceString(entry: editedRecords.artboards.first.record['Name']!, bytes: latin1.encode('AiCodec corpus artboard')).program;
      }
      if (document is AiPdfDocument) {
        // Renaming native layers/artboards changes no painted geometry; the original
        // compatibility appearance is therefore still valid for this edit.
        final AiPdfDocument changed = AiNativeData.replace(source: source, program: edited.bytes, synchronizedPdf: document.pdf);
        final Uint8List encoded = const AiCodec().encode(changed);
        final AiPdfDocument reopenedDocument = const AiCodec().decode(encoded) as AiPdfDocument;
        final AiNativeSource reopened = AiNativeData.extract(reopenedDocument).single;
        if (!_equal(edited.bytes, reopened.bytes)) {
          throw StateError('Reopened authoring data differs from the edited program.');
        }
        await File('${output.path}/$name.edited.pdf').writeAsBytes(encoded);
        await File('${output.path}/$name.edited.envelope').writeAsBytes(_envelope(reopenedDocument));
      }
      await File('${output.path}/$name.edited.ps').writeAsBytes(edited.bytes);
      results.add({
        'file': name,
        'status': 'passed',
        'container': document.kind.name,
        'compression': source.compression.name,
        'nativeBytes': source.bytes.length,
        'layers': program.layers.length,
        'paths': program.paths.length,
        'nativeRecords': records.containers.length,
        'nativeBinaryBytes': binaryBytes,
        'textDocuments': textDocuments,
        'textStories': textStories,
        'composedStories': composedStories,
        'rejectedPathLayouts': rejectedPathLayouts,
        'translatedTextFrames': translatedTextFrames,
        'artboards': records.artboards.length,
        'nativePaths': drawing.paths.length,
        'liveShapes': drawing.liveShapes.length,
        'boundLiveShapes': drawing.liveShapes.where((shape) => shape.isBound).length,
        'translatedLiveShapes': expectedShapes ?? 0,
        'unhandledOperators': program.unhandledOperators.toList()..sort(),
        'privateExtensions': program.hasPrivateExtensions,
        'editedLayer': program.layers.isNotEmpty,
        'editedArtboard': records.artboards.isNotEmpty,
      });
    } on Object catch (error) {
      failures++;
      results.add({'file': name, 'status': 'failed', 'error': error.toString()});
      stderr.writeln('$name: $error');
    }
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('Native Illustrator: ${results.length - failures}/${results.length} required outcomes');
  if (failures != 0) {
    exitCode = 1;
  }
}

/// Reauthors observed positions as host data without retaining old glyph caches.
List<AiNativeTextFrameLayout> _retainedTextLayout(AiNativeTextDocument document, AiNativeTextStory story) {
  final List<AiNativeTextStrike> nodes = story.strikes.expand((node) => node.descendants).toList();
  for (final AiNativeTextStrike root in story.strikes) {
    if (root.kind != .story || root.origin != null && root.origin!.any((value) => value != 0)) {
      throw StateError('The corpus projection requires unshifted story roots.');
    }
  }
  final List<AiNativeTextFrameLayout> frames = [];
  for (final int index in story.frameIndices) {
    final AiNativeTextStrike source = nodes.singleWhere((node) => node.kind == .frame && node.frameIndex == index);
    final List<AiNativeTextLineLayout> lines = [];

    /// Accumulates row origins while retaining the source line/segment order.
    void visit(AiNativeTextStrike node, double parentX, double parentY) {
      final double x = parentX + (node.origin?[0] ?? 0);
      final double y = parentY + (node.origin?[1] ?? 0);
      if (node.kind == .line) {
        final List<AiNativeTextSegmentLayout> segments = [];

        /// Keeps source indices and segment origins without claiming glyph parity.
        void segment(AiNativeTextStrike child, double parentX, double parentY) {
          final double x = parentX + (child.origin?[0] ?? 0);
          final double y = parentY + (child.origin?[1] ?? 0);
          if (child.kind == .segment) {
            final int start = child.firstCharacterIndex ?? 0;
            segments.add(
              AiNativeTextSegmentLayout(start: start, end: start + child.characterCount!, x: x, y: y, rightToLeft: child.wordReorderValid ?? false, automaticHyphen: child.hasTerminalHyphenInsertion),
            );
          } else {
            for (final AiNativeTextStrike nested in child.children) {
              segment(nested, x, y);
            }
          }
        }

        for (final AiNativeTextStrike child in node.children) {
          segment(child, 0, 0);
        }
        lines.add(AiNativeTextLineLayout(x: x, y: y, ascent: node.selectionAscent == null ? null : -node.selectionAscent!, descent: node.selectionDescent, bounds: node.bounds, segments: segments));
      } else {
        for (final AiNativeTextStrike child in node.children) {
          visit(child, x, y);
        }
      }
    }

    for (final AiNativeTextStrike child in source.children) {
      visit(child, 0, 0);
    }
    frames.add(AiNativeTextFrameLayout(frame: document.frames[index], x: source.origin?[0] ?? 0, y: source.origin?[1] ?? 0, lines: lines));
  }
  return frames;
}

/// Exports typed text projections for comparison with an independent ATE reader.
Map<String, Object?> _textModel(AiNativeTextDocument document) => {
  'fonts': [
    for (final AiNativeTextFont font in document.fonts) {'name': font.postScriptName, 'version': font.version},
  ],
  'frames': [
    for (final AiNativeTextFrame frame in document.frames) {'kind': frame.kind.name, 'position': frame.position, 'matrix': frame.matrix, 'path': frame.pathCoordinates},
  ],
  'stories': [
    for (final AiNativeTextStory story in document.stories)
      {
        'text': story.modelText,
        'frames': story.frameIndices,
        'characterRuns': [for (final AiNativeTextRun run in story.characterRuns) run.length],
        'paragraphRuns': [for (final AiNativeTextRun run in story.paragraphRuns) run.length],
        'ranges': [
          for (final AiNativeStyledTextRange range in document.styledRanges(story: story))
            {
              'start': range.start,
              'end': range.end,
              'font': range.characterStyle.font?.postScriptName,
              'fontSize': range.characterStyle.fontSize,
              'horizontalScale': range.characterStyle.horizontalScale,
              'verticalScale': range.characterStyle.verticalScale,
              'tracking': range.characterStyle.tracking,
              'baselineShift': range.characterStyle.baselineShift,
              'rotation': range.characterStyle.rotation,
              'justification': range.paragraphStyle.justification,
            },
        ],
        'strikes': [
          for (final AiNativeTextStrike root in story.strikes)
            for (final AiNativeTextStrike node in root.descendants)
              {
                'tag': node.tag,
                'origin': node.origin,
                'bounds': node.bounds,
                'frame': node.frameIndex,
                'start': node.firstCharacterIndex,
                'characters': node.characterCount,
                'glyphs': node.glyphIds,
                'visualBounds': node.visualBounds,
              },
        ],
      },
  ],
};

/// Pinned files whose live-shape sets support solid/gradient translation.
const Map<String, int> _translatedFixtures = {
  'cmyk_rectangle.ai': 1,
  'rgb_rectangle.ai': 1,
  'circle.ai': 1,
  'simple_shapes.ai': 5,
  'simple_shapes_cc.ai': 5,
  'opacity.ai': 2,
  'gradient_linear.ai': 15,
  'gradient_radial.ai': 9,
};

/// Collects the known single-program corpus envelopes for independent decoding.
Uint8List _envelope(AiPdfDocument document) {
  final BytesBuilder envelope = BytesBuilder(copy: false);
  bool started = false;
  for (final AiPrivateBlock block in document.privateBlocks) {
    final Uint8List data = document.pdf.decodeStream(block.stream);
    final String prefix = latin1.decode(data.take(32).toList());
    started |= prefix.startsWith('%!PS-Adobe-') || prefix.startsWith('%AI12_CompressedData') || prefix.startsWith('%AI24_ZStandard_Data');
    if (started) {
      envelope.add(data);
    }
  }
  if (!started) {
    throw StateError('The corpus envelope was not found.');
  }
  return envelope.takeBytes();
}

/// Compares program bytes without depending on model equality or checksums.
bool _equal(List<int> first, List<int> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
