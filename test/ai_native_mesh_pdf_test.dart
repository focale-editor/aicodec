import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'support/native_mesh_fixture.dart';

/// Wraps independent mesh packets in ordinary native body artwork.
AiProgram _program(String body) => AiProgram.decode(bytes: latin1.encode('%!PS-Adobe-3.0\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'));

/// Provides a page larger than the independent six-point mesh fixture.
AiBoundingBox _bounds() => AiBoundingBox(left: 0, bottom: 0, right: 10, top: 10);

/// Compiles source-native drawing without a reference PDF appearance.
PdfDocument _render(String body, {PdfLimits limits = const PdfLimits(), AiNativeMeshColorResolver? resolveColor}) =>
    AiNativePdf.render(program: _program(body), bounds: _bounds(), limits: limits, resolveMeshColor: resolveColor);

/// Selects actual tensor shading streams rather than source private data.
List<PdfStream> _shadings(PdfDocument document) => document.objects.values.whereType<PdfStream>().where((stream) => stream.dictionary.integer('ShadingType') == 7).toList();

/// Decodes complete type-seven records independently of the mesh writer.
List<({List<List<double>> points, List<List<double>> colors})> _patches(PdfDocument document) {
  final PdfStream stream = _shadings(document).single;
  final List<double> decode = (stream.dictionary['Decode']! as PdfArray).values.map((value) => (value as PdfNumber).value.toDouble()).toList();
  final int components = (decode.length - 4) ~/ 2;
  final int stride = 129 + components * 8;
  final Uint8List bytes = document.decodeStream(stream);
  final ByteData data = ByteData.sublistView(bytes);
  check(bytes.length % stride).equals(0);
  return [
    for (int offset = 0; offset < bytes.length; offset += stride)
      (
        points: [
          for (int index = 0; index < 16; index++)
            [for (int axis = 0; axis < 2; axis++) decode[axis * 2] + data.getUint32(offset + 1 + index * 8 + axis * 4) / 4294967295 * (decode[axis * 2 + 1] - decode[axis * 2])],
        ],
        colors: [
          for (int corner = 0; corner < 4; corner++) [for (int component = 0; component < components; component++) data.getUint16(offset + 129 + 2 * (corner * components + component)) / 65535],
        ],
      ),
  ];
}

/// Builds an independent PDF carrier with native data and unrelated metadata.
AiPdfDocument _carrier(AiProgram program) {
  final PdfDocument blank = PdfDocument.fromPages(pages: [PdfPageSource(width: 10, height: 10, content: [])]);
  const PdfReference native = PdfReference(objectNumber: 90);
  final PdfPage page = blank.pages.single;
  return AiPdfDocument(
    pdf: blank.copyWith(
      objects: {
        ...blank.objects,
        native: PdfStream(
          dictionary: PdfDictionary(),
          data: AiNativeData.encodeEnvelope(program.bytes, compression: .zstandard),
        ),
        page.reference!: page.dictionary.copyWith(
          values: {
            'PieceInfo': PdfDictionary(
              values: {
                'Illustrator': PdfDictionary(
                  values: {
                    'Private': PdfDictionary(values: {'AIPrivateData1': native}),
                  },
                ),
                'Keep': PdfNumber(value: 42),
              },
            ),
          },
        ),
      },
    ),
  );
}

/// Exercises shading serialization, bounded approximation and synchronized edits.
void main() {
  test('writes exact planar tensors and sixteen-bit process endpoints', () {
    final PdfDocument document = _render(meshGrid());
    final PdfStream stream = _shadings(document).single;
    check(stream.dictionary.integer('BitsPerCoordinate')).equals(32);
    check(stream.dictionary.integer('BitsPerComponent')).equals(16);
    check(stream.dictionary.integer('BitsPerFlag')).equals(8);
    check(stream.dictionary.name('ColorSpace')).equals('DeviceGray');
    final List<({List<List<double>> points, List<List<double>> colors})> patches = _patches(document);
    check(patches.length).equals(4);
    for (final patch in patches) {
      for (final (int, int) corner in const [(0, 0), (3, 1), (6, 2), (9, 3)]) {
        final List<double> point = patch.points[corner.$1];
        check((patch.colors[corner.$2].single - (point[0] + point[1]) / 12).abs()).isLessThan(0.5 / 65535 + 1e-8);
      }
    }
    final PdfDocument reopened = const PdfDecoder().convert(const PdfEncoder().convert(document));
    check(reopened.decodeStream(_shadings(reopened).single)).deepEquals(document.decodeStream(stream));
  });

  test('subdivides nonlinear colors with a whole-patch error bound', () {
    final List<({List<List<double>> points, List<List<double>> colors})> patches = _patches(_render(meshGrid(color: (first, second) => first == 1 ? 1 : 0)));
    check(patches.length).isGreaterThan(4);
    for (final patch in patches) {
      for (final double first in [0.0, 0.2, 0.5, 0.8, 1.0]) {
        final double horizontal = (patch.points[0][0] * (1 - first) + patch.points[3][0] * first) / 3;
        final double expected = horizontal <= 1 ? 2 * horizontal - horizontal * horizontal : 1 - (horizontal - 1) * (horizontal - 1);
        final double actual = patch.colors[0].single * (1 - first) + patch.colors[1].single * first;
        check((actual - expected).abs()).isLessThan(1 / 1024 + 0.5 / 65535 + 1e-8);
      }
    }
  });

  test('retains clipping, separate mesh alpha and following object appearance', () {
    final PdfDocument document = _render('q\n0 0 m 3 0 L 3 6 L 0 6 L W n\n${meshGrid(opacity: 0.5)}\n0 0.4 0 0 0 Xy\n0 0 Xd\n6 () XW\nQ');
    final List<PdfDictionary> states = document.objects.values.whereType<PdfDictionary>().where((value) => value.name('Type') == 'ExtGState').toList();
    check(states.map((state) => state['ca']).whereType<PdfNumber>().map((value) => value.value)).contains(0.5);
    check(states.map((state) => state['ca']).whereType<PdfNumber>().map((value) => value.value)).contains(0.4);
    final PdfProgram page = PdfProgram.fromPage(document: document, pageIndex: 0);
    check(page.operations.any((operation) => operation.operator == 'W')).isTrue();
    check(_shadings(document).length).equals(1);
    final PdfStream opaque = document.objects.values.whereType<PdfStream>().singleWhere(
      (stream) => stream.dictionary.name('Subtype') == 'Form' && PdfContent.decode(document.decodeStream(stream)).any((operation) => operation.operator == 'sh'),
    );
    check(((opaque.dictionary['Group']! as PdfDictionary)['I']! as PdfBoolean).value).isTrue();
    check(PdfContent.decode(document.decodeStream(opaque)).any((operation) => operation.operator == 'gs')).isFalse();
  });

  test('saves an edited native mesh with its changed PDF samples', () {
    final AiProgram program = _program(meshGrid());
    final AiNativeMeshes meshes = AiNativeMeshes.decode(records: AiNativeRecords.decode(program: program));
    final AiNativeMesh mesh = meshes.meshes.single;
    final AiNativeMeshes changed = meshes.paintVertices(
      mesh: mesh,
      changes: [
        for (final AiNativeMeshVertex vertex in mesh.vertices)
          AiNativeMeshVertexPaint(
            vertex: vertex,
            color: AiNativeMeshProcessColor(space: .gray, components: [0.75]),
          ),
      ],
    );
    final AiPdfDocument carrier = _carrier(program);
    final AiPdfDocument saved = AiNativePdf.save(source: AiNativeData.extract(carrier).single, program: changed.records.program, pageBounds: [_bounds()]);
    final AiPdfDocument reopened = const AiCodec().decode(const AiCodec().encode(saved)) as AiPdfDocument;
    check(AiNativeData.extract(reopened).single.bytes).deepEquals(changed.records.program.bytes);
    check((reopened.pdf.pages.single.dictionary['PieceInfo']! as PdfDictionary).integer('Keep')).equals(42);
    for (final ({List<List<double>> colors, List<List<double>> points}) patch in _patches(reopened.pdf)) {
      for (final List<double> color in patch.colors) {
        check((color.single - 0.75).abs()).isLessThan(0.5 / 65535);
      }
    }
    check(carrier.pdf.objects.values.whereType<PdfStream>().any((stream) => stream.dictionary.integer('ShadingType') == 7)).isFalse();
  });

  test('resolves hidden meshes but does not paint them or private packets', () {
    int calls = 0;
    final PdfDocument hidden = _render(
      '0 1 1 1 0 0 0 0 0 0 Lb\n(Hidden) Ln\n${meshGrid()}\nLB',
      resolveColor: (corner) {
        calls++;
        return AiNativeMeshProcessColor(space: .gray, components: corner.color);
      },
    );
    check(calls).equals(16);
    check(_shadings(hidden)).isEmpty();
    final String private = meshGrid().replaceFirst('/Mesh X!', '%_/Mesh X!').replaceFirst('/End X!', '%_/End X!');
    check(_shadings(_render(private))).isEmpty();
  });

  test('rejects unsupported appearance and exhausted subdivision budgets', () {
    for (final String source in [
      '0 0 m\n${meshGrid()}\nN',
      '${meshGrid()}\n1 (Unknown) XW',
      '${meshGrid()}\n%_/ArtDictionary :\n%_1 /Integer (Unknown effect) ,\n%_;',
      meshGrid(weight: 0.5),
    ]) {
      check(() => _render(source)).throws<UnsupportedError>();
    }
    check(() => _render(meshGrid(), limits: const PdfLimits(maxStreamBytes: 136))).throws<FormatException>();
    check(() => _render('${meshGrid()}\n${meshGrid()}', limits: const PdfLimits(maxDecodedBytes: 600))).throws<FormatException>();
    check(() => _render(meshGrid(color: (first, second) => first == 1 ? 1 : 0), limits: const PdfLimits(maxObjects: 40))).throws<FormatException>();
  });
}
