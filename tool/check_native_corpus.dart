import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';

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
      AiProgram edited = program.layers.isEmpty ? program : AiNativeEditor.updateLayer(program: program, layer: program.layers.first, name: 'AiKit corpus layer');
      final AiNativeRecords editedRecords = AiNativeRecords.decode(program: edited);
      if (editedRecords.artboards.isNotEmpty) {
        edited = editedRecords.replaceString(entry: editedRecords.artboards.first.record['Name']!, bytes: latin1.encode('AiKit corpus artboard')).program;
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
