import 'dart:convert';
import 'dart:io';

import 'package:aikit/aikit.dart';

/// Replaces real embedded planes and resolutions for independent verification.
Future<void> main() async {
  final Directory output = await Directory('test/corpus/output/native-raster-edits').create(recursive: true);
  final List<Map<String, Object?>> report = [];
  for (final String name in ['raster_ai8.ai', 'raster_v2020.ai', 'empty_cs.ai', 'empty_cs2.ai', 'simple_shapes_cc.ai']) {
    final AiDocument document = const AiCodec().decode(await File('test/corpus/files/$name').readAsBytes());
    final AiNativeSource source = AiNativeData.extract(document).single;
    final AiProgram program = AiProgram.decode(bytes: source.bytes);
    final AiNativeRasters original = AiNativeRasters.decode(records: AiNativeRecords.decode(program: program));
    await File('${output.path}/$name.native.ps').writeAsBytes(program.bytes);
    final List<Map<String, Object?>> variants = [];
    for (final String variant in ['colors', 'alpha', 'resolution']) {
      AiNativeRasters edited = original;
      for (int index = 0; index < original.images.length; index++) {
        final AiNativeRaster image = edited.images[index];
        if (image.bitsPerComponent != 8 || image.imageMask) {
          throw StateError('Expected eight-bit process fixture samples.');
        }
        final int width = variant == 'resolution' ? (image.width + 1) ~/ 2 : image.width;
        final int height = variant == 'resolution' ? (image.height + 1) ~/ 2 : image.height;
        final List<int> sourceColors = image.colorSamples;
        final List<int>? sourceAlpha = image.alphaSamples;

        /// Nearest source pixel selected by integer pixel-edge coordinates.
        int pixel(int index) => (index ~/ width * image.height ~/ height) * image.width + (index % width * image.width ~/ width);

        final List<int> color = List.generate(width * height * image.components, (offset) {
          final int value = sourceColors[pixel(offset ~/ image.components) * image.components + offset % image.components];
          return variant == 'colors' ? 255 - value : value;
        });
        final List<int>? alpha = variant == 'alpha'
            ? List.generate(width * height, (offset) => offset % width < width ~/ 2 ? (offset ~/ width < height ~/ 2 ? 0 : 128) : 255)
            : sourceAlpha == null
            ? null
            : List.generate(width * height, (offset) => sourceAlpha[pixel(offset)]);
        edited = edited.replacePixels(
          image: image,
          samples: AiNativeRasterSamples(width: width, height: height, bitsPerComponent: 8, components: image.components, colorSamples: color, alphaSamples: alpha),
        );
      }
      await File('${output.path}/$name.$variant.ps').writeAsBytes(edited.records.program.bytes);
      variants.add({
        'variant': variant,
        'images': [for (final AiNativeRaster image in edited.images) _identities(image)],
      });
    }
    report.add({
      'file': name,
      'images': [
        for (final AiNativeRaster image in original.images) {..._identities(image), 'printable': image.isPrintable(program: program)},
      ],
      'variants': variants,
    });
    stdout.writeln('$name: ${original.images.length} images replaced in three variants');
  }
  await File('${output.path}/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
}

/// Exposes sample identities without conflating them with stable object metadata.
Map<String, Object?> _identities(AiNativeRaster image) => {
  'colorIdentity': image.dictionary?['AI24 ImageRawDataUUID']?.text(),
  'alphaIdentity': image.dictionary?['AI24 ImageAlphaRawDataUUID']?.text(),
  'originalScale': image.dictionary?['Raster Art Original Scale']?.number,
  'name': image.dictionary?['Object name']?.text(),
};
