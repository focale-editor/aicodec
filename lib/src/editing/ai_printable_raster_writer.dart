part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Writes process samples and a separate alpha plane without color conversion.
extension on _PrintablePdfWriter {
  /// Maps the native upper-left pixel origin to PDF's unit image rectangle.
  _PrintableChunk _raster(_PrintableNode node) {
    final AiNativeRaster image = node.raster!;
    final Uint8List color = image.colorSamples;
    final Uint8List? alpha = image.alphaSamples;
    bytes += color.length + (alpha?.length ?? 0);
    if (bytes > document.limits.maxDecodedBytes) {
      throw const FormatException('Printable raster samples exceed the decoded byte limit.');
    }
    final Map<String, PdfValue> dictionary = {
      'Type': PdfName(value: 'XObject'),
      'Subtype': PdfName(value: 'Image'),
      'Width': PdfNumber(value: image.width),
      'Height': PdfNumber(value: image.height),
      'BitsPerComponent': PdfNumber(value: image.bitsPerComponent),
    };
    final PdfReference? mask = alpha == null
        ? null
        : _add(
            PdfStreams.encode(
              bytes: alpha,
              limits: document.limits,
              dictionary: PdfDictionary(
                values: {
                  ...dictionary,
                  'ColorSpace': PdfName(value: 'DeviceGray'),
                },
              ),
            ),
          );
    final PdfReference reference = _add(
      PdfStreams.encode(
        bytes: color,
        limits: document.limits,
        dictionary: PdfDictionary(
          values: {
            ...dictionary,
            if (image.imageMask)
              'ImageMask': const PdfBoolean(value: true)
            else
              'ColorSpace': PdfName(
                value: switch (image.components) {
                  1 => 'DeviceGray',
                  3 => 'DeviceRGB',
                  _ => 'DeviceCMYK',
                },
              ),
            'SMask': ?mask,
          },
        ),
      ),
    );
    final List<double> matrix = image.matrix;
    final List<double> bounds = image.bounds;
    final double width = bounds[2] - bounds[0];
    final double height = bounds[3] - bounds[1];
    final List<double> transform = [
      matrix[0] * width,
      matrix[1] * width,
      matrix[2] * height,
      matrix[3] * height,
      matrix[4] + matrix[0] * bounds[0] - matrix[2] * bounds[3],
      matrix[5] + matrix[1] * bounds[0] - matrix[3] * bounds[3],
    ];
    if (transform.any((number) => !number.isFinite)) {
      throw const FormatException('Native raster placement exceeds finite PDF coordinates.');
    }
    final String name = _name('AiNativeImage');
    return _PrintableChunk()
      ..resources['XObject'] = {name: reference}
      ..operations.addAll([
        ...node.operations,
        _pdfNumbers('cm', transform),
        // Match the image-edge clip emitted by Illustrator's PDF exporter.
        // Image painting alone does not antialias rotated/sheared boundaries.
        _pdfNumbers('re', [0, 0, 1, 1]),
        PdfOperation(operator: 'W'),
        PdfOperation(operator: 'n'),
        PdfOperation(
          operator: 'Do',
          operands: [PdfName(value: name)],
        ),
      ]);
  }
}
