part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Writes vector shadings and matching opacity masks into the shared PDF graph.
extension on _PrintablePdfWriter {
  /// Paints a bounded fill or native stroke with a matching stop-opacity field.
  _PrintableChunk _gradient(_PrintableNode node) {
    final _PrintableGradient gradient = node.gradient!;
    if (!gradientFunctions.containsKey(gradient.definition)) {
      _charge(gradient.stops.length * 4);
    }
    final (PdfReference, PdfReference?) functions = gradientFunctions.putIfAbsent(
      gradient.definition,
      () => (
        _add(_gradientFunction(gradient.stops, gradient.colors)),
        gradient.stops.every((stop) => stop.opacity == 1) ? null : _add(_gradientFunction(gradient.stops, gradient.stops.map((stop) => [stop.opacity]).toList())),
      ),
    );
    final String shade = _name('AiNativeShade');
    final PdfReference shading = _add(_gradientShading(gradient, functions.$1, gradient.colorSpace));
    final _PrintableChunk result = _PrintableChunk();
    if (!gradient.native.onStroke) {
      result.resources['Shading'] = {shade: shading};
    }
    result.operations.addAll([
      PdfOperation(operator: 'q'),
      ...node.operations,
      if (!gradient.native.onStroke) ...[
        if (gradient.native.geometry.flag == 1) PdfOperation(operator: node.evenOdd ? 'W*' : 'W'),
        PdfOperation(operator: 'n'),
      ],
    ]);
    final PdfReference? opacity = functions.$2;
    if (opacity != null) {
      final String maskShade = _name('AiNativeMaskShade');
      final PdfReference maskShading = _add(_gradientShading(gradient, opacity, 'DeviceGray'));
      final List<PdfOperation> operations = [
        _pdfNumbers('cm', gradient.matrix),
        PdfOperation(
          operator: 'sh',
          operands: [PdfName(value: maskShade)],
        ),
      ];
      _charge(operations.length);
      final Uint8List data = PdfContent.encode(operations, limits: document.limits);
      bytes += data.length;
      if (bytes > document.limits.maxDecodedBytes) {
        throw const FormatException('Printable gradient masks exceed the decoded byte limit.');
      }
      final PdfReference form = _add(
        PdfStreams.encode(
          bytes: data,
          limits: document.limits,
          dictionary: PdfDictionary(
            values: {
              'Type': PdfName(value: 'XObject'),
              'Subtype': PdfName(value: 'Form'),
              'BBox': formBounds,
              'Resources': PdfDictionary(
                values: {
                  'Shading': PdfDictionary(values: {maskShade: maskShading}),
                },
              ),
              'Group': PdfDictionary(
                values: {
                  'S': PdfName(value: 'Transparency'),
                  'CS': PdfName(value: 'DeviceGray'),
                  'I': const PdfBoolean(value: true),
                },
              ),
            },
          ),
        ),
      );
      final String mask = _name('AiNativeGradientAlpha');
      result.resources['ExtGState'] = {
        mask: _add(
          PdfDictionary(
            values: {
              'Type': PdfName(value: 'ExtGState'),
              'SMask': PdfDictionary(
                values: {
                  'S': PdfName(value: 'Luminosity'),
                  'G': form,
                  'BC': _pdfArray([0]),
                },
              ),
            },
          ),
        ),
      };
      result.operations.add(
        PdfOperation(
          operator: 'gs',
          operands: [PdfName(value: mask)],
        ),
      );
    }
    if (gradient.native.onStroke) {
      final String pattern = _name('AiNativeStrokePattern');
      result.resources['Pattern'] = {
        pattern: _add(
          PdfDictionary(
            values: {
              'Type': PdfName(value: 'Pattern'),
              'PatternType': PdfNumber(value: 2),
              'Shading': shading,
              'Matrix': _pdfArray(gradient.matrix),
            },
          ),
        ),
      };
      result.operations.addAll([
        PdfOperation(
          operator: 'CS',
          operands: [PdfName(value: 'Pattern')],
        ),
        PdfOperation(
          operator: 'SCN',
          operands: [PdfName(value: pattern)],
        ),
        if (gradient.native.closing.numbers!.single == 2) PdfOperation(operator: 'h'),
        PdfOperation(operator: 'S'),
        PdfOperation(operator: 'Q'),
      ]);
      _charge(result.operations.length);
      // Pattern matrices use a stream's initial space, not its current matrix.
      // A local form keeps the pattern aligned through page and group placement.
      final String name = _name('AiNativeStroke');
      return _PrintableChunk()
        ..resources['XObject'] = {name: _form(content: result)}
        ..operations.add(
          PdfOperation(
            operator: 'Do',
            operands: [PdfName(value: name)],
          ),
        );
    }
    result.operations.addAll([
      _pdfNumbers('cm', gradient.matrix),
      PdfOperation(
        operator: 'sh',
        operands: [PdfName(value: shade)],
      ),
      PdfOperation(operator: 'Q'),
      ...node.gradientStroke,
    ]);
    return result;
  }
}

/// Builds a reusable classic interpolation function with explicit endpoint caps.
PdfDictionary _gradientFunction(List<AiNativeGradientStop> stops, List<List<double>> values) {
  final List<PdfValue> functions = [];
  final List<double> bounds = [];
  final List<double> encode = [];

  /// Appends one nonempty interval with a power curve or constant paint.
  void interval(List<double> first, List<double> last, double midpoint, double end) {
    final bool mirrored = midpoint < 50;
    final double fraction = (mirrored ? 100 - midpoint : midpoint) / 100;
    functions.add(
      PdfDictionary(
        values: {
          'FunctionType': PdfNumber(value: 2),
          'Domain': _pdfArray([0, 1]),
          'C0': _pdfArray(mirrored ? last : first),
          'C1': _pdfArray(mirrored ? first : last),
          'N': PdfNumber(value: math.log(0.5) / math.log(fraction)),
        },
      ),
    );
    encode.addAll(mirrored ? [1, 0] : [0, 1]);
    bounds.add(end);
  }

  if (stops.first.position > 0) {
    interval(values.first, values.first, 50, stops.first.position / 100);
  }
  for (int index = 0; index < stops.length - 1; index++) {
    interval(values[index], values[index + 1], stops[index].midpoint, stops[index + 1].position / 100);
  }
  if (stops.last.position < 100) {
    interval(values.last, values.last, 50, 1);
  }
  bounds.removeLast();
  return PdfDictionary(
    values: {
      'FunctionType': PdfNumber(value: 3),
      'Domain': _pdfArray([0, 1]),
      'Functions': PdfArray(values: functions),
      'Bounds': _pdfArray(bounds),
      'Encode': _pdfArray(encode),
    },
  );
}

/// Describes an axial or focal radial field in unit gradient coordinates.
PdfDictionary _gradientShading(_PrintableGradient gradient, PdfReference function, String colorSpace) => PdfDictionary(
  values: {
    'ShadingType': PdfNumber(value: gradient.definition.radial ? 3 : 2),
    'ColorSpace': PdfName(value: colorSpace),
    'Coords': _pdfArray(gradient.coordinates),
    'Domain': _pdfArray([0, 1]),
    'Function': function,
    'Extend': PdfArray(values: [const PdfBoolean(value: true), const PdfBoolean(value: true)]),
  },
);
