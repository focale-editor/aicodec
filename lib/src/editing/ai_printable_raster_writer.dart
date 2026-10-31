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
        PdfOperation(
          operator: 'Do',
          operands: [PdfName(value: name)],
        ),
      ]);
  }
}

/// Rejects positional or color metadata that cannot be reproduced faithfully.
void _validatePrintableRaster(AiNativeRaster image) {
  final List<double> matrix = image.matrix;
  final double determinant = matrix[0] * matrix[3] - matrix[1] * matrix[2];
  if (!determinant.isFinite || determinant == 0 || image.bounds[2] <= image.bounds[0] || image.bounds[3] <= image.bounds[1]) {
    throw const FormatException('Degenerate native raster placement.');
  }
  if (image.bounds[0] != 0 || image.bounds[1] != 0 || image.bounds[2] != image.width || image.bounds[3] != image.height) {
    throw UnsupportedError('Native raster cropping requires qualified image-bound semantics.');
  }
  final int colorFlag = switch (image.components) {
    1 => 0,
    3 => 1,
    _ => 2,
  };
  if (image.flags != 0 && image.flags != colorFlag + (image.hasAlpha ? 16 : 0) ||
      image.extensions.isNotEmpty && (image.extensions.length < 3 || image.extensions[0] != 4 || image.extensions[1] != 4 || image.extensions.skip(2).any((flag) => flag != 0))) {
    throw UnsupportedError('Unsupported native raster producer flags.');
  }
  final Set<String> seen = {};
  for (final AiNativeInstruction command in image.commands) {
    if (!seen.add(command.operator)) {
      throw const FormatException('Repeated native raster metadata.');
    }
    final List<AiToken> operands = command.operands;
    switch (command.operator) {
      case 'XG':
        if (operands.length != 2 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands.first.kind) || !const {0, 1}.contains(operands.last.number)) {
          throw const FormatException('Invalid native raster source metadata.');
        }
      case 'XN':
        if (operands.length != 1 ||
            operands.single.lexeme !=
                switch (image.components) {
                  1 => '/DeviceGray',
                  3 => '/DeviceRGB',
                  _ => '/DeviceCMYK',
                }) {
          throw UnsupportedError('Native raster color spaces require an explicit color policy.');
        }
      case 'Xh':
        if (operands.length != 11 ||
            operands.first.kind != .arrayStart ||
            operands[7].kind != .arrayEnd ||
            operands.skip(1).take(6).indexed.any((item) => item.$2.number != matrix[item.$1]) ||
            operands[8].number != image.width ||
            operands[9].number != image.height ||
            operands[10].number != 0) {
          throw UnsupportedError('Native raster placement metadata disagrees with its samples.');
        }
      case 'XI':
        continue;
      case 'XH':
        if (operands.isNotEmpty || command != image.commands.last) {
          throw const FormatException('Invalid native raster termination.');
        }
      default:
        throw UnsupportedError('Native raster export cannot render ${command.operator}.');
    }
  }
}
