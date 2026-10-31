part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Writes exact tensor geometry with bounded bilinear process-color error.
extension on _PrintablePdfWriter {
  /// Compiles one native mesh into a type-seven shading and constant opacity.
  _PrintableChunk _mesh(_PrintableNode node) {
    final AiNativeMeshInterpolation mesh = node.mesh!;
    final List<({double x, double y})> points = [for (final AiNativeMeshSurface surface in mesh.surfaces) ...surface.controlPoints];
    final double left = points.map((point) => point.x).reduce(math.min);
    final double bottom = points.map((point) => point.y).reduce(math.min);
    final double right = points.map((point) => point.x).reduce(math.max);
    final double top = points.map((point) => point.y).reduce(math.max);
    final double width = right - left;
    final double height = top - bottom;
    if (width <= 0 || height <= 0 || width / 4294967295 > 0.0001 || height / 4294967295 > 0.0001) {
      throw UnsupportedError('Mesh geometry exceeds the qualified PDF coordinate precision.');
    }
    final int components = mesh.space.componentCount;
    final int patchBytes = 129 + 8 * components;
    final BytesBuilder output = BytesBuilder(copy: false);
    final Map<AiNativeMeshPatch, List<List<double>>> colorGrids = {};
    for (final AiNativeMeshSurface surface in mesh.surfaces) {
      final List<List<double>> colors = colorGrids.putIfAbsent(surface.patch, () => mesh.colorControlPoints(patch: surface.patch));
      final List<_MeshPdfPatch> pending = [
        _MeshPdfPatch(
          geometry: surface.controlPoints.map((point) => [point.x, point.y]).toList(),
          colors: _meshPdfRestrict(colors, surface.bounds.firstStart, surface.bounds.firstEnd, surface.bounds.secondStart, surface.bounds.secondEnd),
          depth: 0,
        ),
      ];
      while (pending.isNotEmpty) {
        final _MeshPdfPatch patch = pending.removeLast();
        _charge(1);
        if (_meshPdfColorError(patch.colors) > 1 / 1024) {
          if (patch.depth >= math.min(20, document.limits.maxDepth)) {
            throw const FormatException('Mesh color subdivision exceeds the PDF depth limit.');
          }
          final List<List<List<double>>> firstColors = [
            _meshPdfRestrict(patch.colors, 0, 0.5, 0, 1),
            _meshPdfRestrict(patch.colors, 0.5, 1, 0, 1),
          ];
          final List<List<List<double>>> secondColors = [
            _meshPdfRestrict(patch.colors, 0, 1, 0, 0.5),
            _meshPdfRestrict(patch.colors, 0, 1, 0.5, 1),
          ];
          final bool firstAxis = firstColors.map(_meshPdfColorError).reduce(math.max) <= secondColors.map(_meshPdfColorError).reduce(math.max);
          for (final int half in const [1, 0]) {
            final double start = half / 2;
            pending.add(
              _MeshPdfPatch(
                geometry: firstAxis ? _meshPdfRestrict(patch.geometry, start, start + 0.5, 0, 1) : _meshPdfRestrict(patch.geometry, 0, 1, start, start + 0.5),
                colors: (firstAxis ? firstColors : secondColors)[half],
                depth: patch.depth + 1,
              ),
            );
          }
          continue;
        }
        bytes += patchBytes;
        if (bytes > document.limits.maxDecodedBytes || output.length + patchBytes > document.limits.maxStreamBytes) {
          throw const FormatException('Mesh shading exceeds the PDF stream or decoded byte limit.');
        }
        final ByteData data = ByteData(patchBytes);
        int offset = 1; // Flag zero declares all sixteen controls and four colors.
        for (final int index in _meshPdfOrder) {
          final List<double> point = patch.geometry[index];
          data.setUint32(offset, ((point[0] - left) / width * 4294967295).round().clamp(0, 4294967295));
          data.setUint32(offset + 4, ((point[1] - bottom) / height * 4294967295).round().clamp(0, 4294967295));
          offset += 8;
        }
        for (final int index in const [0, 12, 15, 3]) {
          for (final double component in patch.colors[index]) {
            data.setUint16(offset, (component.clamp(0.0, 1.0) * 65535).round());
            offset += 2;
          }
        }
        output.add(data.buffer.asUint8List());
      }
    }
    final String name = _name('AiNativeMesh');
    final PdfReference shading = _add(
      PdfStreams.encode(
        bytes: output.takeBytes(),
        limits: document.limits,
        dictionary: PdfDictionary(
          values: {
            'ShadingType': PdfNumber(value: 7),
            'ColorSpace': PdfName(value: mesh.space.nativeName),
            'BitsPerCoordinate': PdfNumber(value: 32),
            'BitsPerComponent': PdfNumber(value: 16),
            'BitsPerFlag': PdfNumber(value: 8),
            'Decode': _pdfArray([
              left,
              right,
              bottom,
              top,
              for (int index = 0; index < components; index++) ...[0, 1],
            ]),
          },
        ),
      ),
    );
    final _PrintableChunk result = _PrintableChunk()..resources['Shading'] = {name: shading};
    result.operations.addAll(node.operations);
    result.operations.add(
      PdfOperation(
        operator: 'sh',
        operands: [PdfName(value: name)],
      ),
    );
    if (mesh.opacity != 1) {
      final String alpha = _name('AiNativeMeshAlpha');
      final String form = _name('AiNativeMeshForm');
      _charge(result.operations.length);
      // Applying ca to sh exposes overlapping tessellation edges in renderers.
      // Composite the opaque mesh once before applying its constant alpha.
      return _PrintableChunk()
        ..resources['XObject'] = {
          form: _form(
            content: result,
            group: PdfDictionary(
              values: {
                'S': PdfName(value: 'Transparency'),
                'I': const PdfBoolean(value: true),
              },
            ),
          ),
        }
        ..resources['ExtGState'] = {
          alpha: _add(
            PdfDictionary(
              values: {
                'Type': PdfName(value: 'ExtGState'),
                'ca': PdfNumber(value: mesh.opacity),
              },
            ),
          ),
        }
        ..operations.addAll([
          PdfOperation(
            operator: 'gs',
            operands: [PdfName(value: alpha)],
          ),
          PdfOperation(
            operator: 'Do',
            operands: [PdfName(value: form)],
          ),
        ]);
    }
    return result;
  }
}

/// PDF tensor order: twelve cyclic boundary controls, then four interior ones.
const List<int> _meshPdfOrder = [0, 4, 8, 12, 13, 14, 15, 11, 7, 3, 2, 1, 5, 9, 10, 6];

/// One bounded subdivision work item with geometry and unclamped color tensors.
final class _MeshPdfPatch {
  /// Sixteen two-component native geometry controls.
  final List<List<double>> geometry;

  /// Sixteen process-component Bernstein coefficients.
  final List<List<double>> colors;

  /// Number of dyadic subdivisions below the source surface.
  final int depth;

  /// Captures one independently owned work item.
  const _MeshPdfPatch({
    required this.geometry,
    required this.colors,
    required this.depth,
  });
}

/// Bounds the clamped cubic field against its bilinear corner approximation.
double _meshPdfColorError(List<List<double>> grid) {
  double error = 0;
  for (int component = 0; component < grid.first.length; component++) {
    final double minimum = grid.map((point) => point[component]).reduce(math.min);
    final double maximum = grid.map((point) => point[component]).reduce(math.max);
    if (maximum <= 0 || minimum >= 1) {
      continue;
    }
    final List<double> corners = [
      for (final int index in const [0, 12, 3, 15]) grid[index][component].clamp(0.0, 1.0),
    ];
    for (int first = 0; first < 4; first++) {
      for (int second = 0; second < 4; second++) {
        final double horizontal = first / 3;
        final double vertical = second / 3;
        final double bilinear =
            corners[0] * (1 - horizontal) * (1 - vertical) + corners[1] * horizontal * (1 - vertical) + corners[2] * (1 - horizontal) * vertical + corners[3] * horizontal * vertical;
        // Bernstein coefficients bound the entire polynomial difference.
        // Clamping the cubic cannot increase its distance to this in-range
        // bilinear field. Sixteen-bit endpoint rounding adds at most 0.5/65535.
        error = math.max(error, (grid[first * 4 + second][component] - bilinear).abs());
      }
    }
  }
  return error;
}

/// Restricts both tensor axes using exact cubic control subdivision.
List<List<double>> _meshPdfRestrict(List<List<double>> grid, double firstStart, double firstEnd, double secondStart, double secondEnd) {
  final List<List<double>> horizontal = List.filled(16, const []);
  for (int second = 0; second < 4; second++) {
    final List<List<double>> curve = _meshPdfCurveInterval([for (int first = 0; first < 4; first++) grid[first * 4 + second]], firstStart, firstEnd);
    for (int first = 0; first < 4; first++) {
      horizontal[first * 4 + second] = curve[first];
    }
  }
  return [for (int first = 0; first < 4; first++) ..._meshPdfCurveInterval(horizontal.sublist(first * 4, first * 4 + 4), secondStart, secondEnd)];
}

/// Restricts one cubic to a nonempty parameter interval.
List<List<double>> _meshPdfCurveInterval(List<List<double>> curve, double start, double end) {
  if (start == 0 && end == 1) {
    return curve;
  }
  final List<List<double>> suffix = start == 0 ? curve : _meshPdfSplit(curve, start).$2;
  return end == 1 ? suffix : _meshPdfSplit(suffix, (end - start) / (1 - start)).$1;
}

/// Splits a cubic using de Casteljau interpolation, for any component count.
(List<List<double>>, List<List<double>>) _meshPdfSplit(List<List<double>> curve, double parameter) {
  /// Interpolates one control vector without changing either input.
  List<double> blend(List<double> first, List<double> second) => [for (int component = 0; component < first.length; component++) first[component] * (1 - parameter) + second[component] * parameter];
  final List<double> first = blend(curve[0], curve[1]);
  final List<double> middle = blend(curve[1], curve[2]);
  final List<double> last = blend(curve[2], curve[3]);
  final List<double> before = blend(first, middle);
  final List<double> after = blend(middle, last);
  final List<double> center = blend(before, after);
  return ([curve[0], first, before, center], [center, after, last, curve[3]]);
}
