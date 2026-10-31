part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Compiles before publishing any page or private-data changes.
PdfDocument _writePrintablePdf(AiProgram program, PdfDocument document, List<AiBoundingBox> bounds) {
  document.limits.validate();
  final List<PdfPage> pages = document.pages;
  if (pages.isEmpty || pages.length != bounds.length) {
    throw ArgumentError('Every PDF page requires an explicit native drawing rectangle.');
  }
  final List<List<double>> boxes = [];
  for (int index = 0; index < pages.length; index++) {
    final PdfValue? value = pages[index].inherited['MediaBox'];
    final PdfValue? unit = pages[index].dictionary['UserUnit'];
    if (value == null || unit != null && document.resolve(unit) is! PdfNull && (document.resolve(unit) is! PdfNumber || (document.resolve(unit) as PdfNumber).value != 1)) {
      throw UnsupportedError('Native PDF synchronization requires ordinary page units and a MediaBox.');
    }
    final PdfValue resolved = document.resolve(value);
    PdfResources.validateBox(resolved);
    final List<double> box = (resolved as PdfArray).values.map((number) => (number as PdfNumber).value.toDouble()).toList();
    if ((box[2] - box[0] - (bounds[index].right - bounds[index].left)).abs() > 1e-8 || (box[3] - box[1] - (bounds[index].top - bounds[index].bottom)).abs() > 1e-8) {
      throw ArgumentError('Native drawing rectangles must match the existing PDF page dimensions.');
    }
    boxes.add(box);
  }
  final List<_PrintableNode> nodes = _readPrintable(program);
  final _PrintablePdfWriter writer = _PrintablePdfWriter(document: document, bounds: bounds);
  final _PrintableChunk content = writer.nodes(nodes);
  final PdfEditor editor = PdfEditor(document: document.copyWith(objects: writer.objects));
  for (int index = 0; index < pages.length; index++) {
    final PdfDictionary original = editor.pageResources(pageIndex: index);
    final Map<String, PdfValue> resources = {...original.values};
    for (final MapEntry<String, Map<String, PdfValue>> category in content.resources.entries) {
      final PdfDictionary previous = original[category.key] == null || document.resolve(original[category.key]!) is PdfNull ? PdfDictionary() : document.dictionary(original[category.key]!);
      resources[category.key] = previous.copyWith(values: category.value);
    }
    final List<PdfOperation> operations = [
      PdfOperation(operator: 'q'),
      _pdfNumbers('cm', [1, 0, 0, 1, boxes[index][0] - bounds[index].left, boxes[index][1] - bounds[index].bottom]),
      ...content.operations,
      PdfOperation(operator: 'Q'),
    ];
    editor.setPageProgram(
      pageIndex: index,
      program: PdfProgram(
        operations: operations,
        resources: PdfDictionary(values: resources),
        document: editor.document,
      ),
    );
    editor.setPageAttributes(pageIndex: index, remove: {'Thumb'});
  }
  return editor.document;
}

/// Operations with only the resources referenced in their local scope.
final class _PrintableChunk {
  /// Ordered scoped PDF drawing instructions.
  final List<PdfOperation> operations = [];

  /// Resource bindings separated by PDF resource category.
  final Map<String, Map<String, PdfValue>> resources = {};

  /// Combines a child without creating recursive resource dictionaries.
  void add(_PrintableChunk child) {
    operations.addAll(child.operations);
    for (final MapEntry<String, Map<String, PdfValue>> category in child.resources.entries) {
      (resources[category.key] ??= {}).addAll(category.value);
    }
  }

  /// The direct dictionary used by a page or Form XObject.
  PdfDictionary get dictionary => PdfDictionary(values: {for (final MapEntry<String, Map<String, PdfValue>> category in resources.entries) category.key: PdfDictionary(values: category.value)});
}

/// Builds private graph additions before committing immutable PDF snapshots.
final class _PrintablePdfWriter {
  /// Source document and shared graph/resource policy.
  final PdfDocument document;

  /// Shared PdfCore allocator, including dangling-reference reservation.
  final PdfEditor editor;

  /// Original objects plus newly generated forms and graphics states.
  Map<PdfReference, PdfValue> get objects => editor.document.objects;

  /// Union of output pages in native drawing coordinates, used by opacity forms.
  final PdfArray formBounds;

  /// Names already used by any original page, preventing annotation collisions.
  final Set<String> names = {};

  /// Reused opacity resources, never applied directly to a fill/stroke pair.
  final Map<(double, String), (String, PdfReference)> opacities = {};

  /// Gradient functions shared by instances without sharing positional matrices.
  final Map<AiNativeGradientDefinition, (PdfReference, PdfReference?)> gradientFunctions = {};

  /// Aggregate generated content bytes before compression.
  int bytes = 0;

  /// Aggregate drawing operations, including group wrappers and form contents.
  int operations = 0;

  /// Initializes bounded graph construction without mutating the source.
  _PrintablePdfWriter({required this.document, required List<AiBoundingBox> bounds})
    : editor = PdfEditor(document: document),
      formBounds = _pdfArray([
        bounds.map((box) => box.left).reduce((a, b) => a < b ? a : b),
        bounds.map((box) => box.bottom).reduce((a, b) => a < b ? a : b),
        bounds.map((box) => box.right).reduce((a, b) => a > b ? a : b),
        bounds.map((box) => box.top).reduce((a, b) => a > b ? a : b),
      ]) {
    final int pageCount = document.pages.length;
    for (int index = 0; index < pageCount; index++) {
      for (final String category in ['XObject', 'ExtGState', 'Shading', 'Pattern']) {
        final PdfValue? value = editor.pageResources(pageIndex: index)[category];
        if (value != null && document.resolve(value) is! PdfNull) {
          names.addAll(document.dictionary(value).values.keys);
        }
      }
    }
  }

  /// Emits a list of nodes, preserving graphics and clipping scopes.
  _PrintableChunk nodes(List<_PrintableNode> nodes) {
    final _PrintableChunk result = _PrintableChunk();
    for (final _PrintableNode node in nodes) {
      if (!node.visible) {
        continue;
      }
      if (node.clip) {
        _charge(node.operations.length);
        result.operations.addAll(node.operations);
        continue;
      }
      final _PrintableChunk child = this.nodes(node.children);
      final _PrintableChunk paint = node.raster != null
          ? _raster(node)
          : node.gradient == null
          ? (_PrintableChunk()..operations.addAll(node.operations))
          : _gradient(node);
      _charge(paint.operations.length + 2);
      child.add(paint);
      child.operations.insert(0, PdfOperation(operator: 'q'));
      child.operations.add(PdfOperation(operator: 'Q'));
      if (node.opacity == 1 && node.blend == 'Normal' && !node.isolated && !node.knockout) {
        result.add(child);
        continue;
      }
      final String name = _name('AiNativeForm');
      final PdfReference form = _form(
        content: child,
        group: PdfDictionary(
          values: {
            'S': PdfName(value: 'Transparency'),
            'I': PdfBoolean(value: !node.group || node.isolated),
            'K': PdfBoolean(value: node.knockout),
          },
        ),
      );
      final (String, PdfReference) alpha = opacities.putIfAbsent(
        (node.opacity, node.blend),
        () => (
          _name('AiNativeAlpha'),
          _add(
            PdfDictionary(
              values: {
                'Type': PdfName(value: 'ExtGState'),
                'ca': PdfNumber(value: node.opacity),
                'CA': PdfNumber(value: node.opacity),
                'BM': PdfName(value: node.blend),
              },
            ),
          ),
        ),
      );
      (result.resources['XObject'] ??= {})[name] = form;
      (result.resources['ExtGState'] ??= {})[alpha.$1] = alpha.$2;
      _charge(4);
      result.operations.addAll([
        PdfOperation(operator: 'q'),
        PdfOperation(
          operator: 'gs',
          operands: [PdfName(value: alpha.$1)],
        ),
        PdfOperation(
          operator: 'Do',
          operands: [PdfName(value: name)],
        ),
        PdfOperation(operator: 'Q'),
      ]);
    }
    return result;
  }

  /// Encapsulates local coordinates and resources under the shared byte budget.
  PdfReference _form({required _PrintableChunk content, PdfDictionary? group}) {
    final Uint8List data = PdfContent.encode(content.operations, limits: document.limits);
    bytes += data.length;
    if (bytes > document.limits.maxDecodedBytes) {
      throw const FormatException('Printable forms exceed the decoded byte limit.');
    }
    return _add(
      PdfStreams.encode(
        bytes: data,
        limits: document.limits,
        dictionary: PdfDictionary(
          values: {
            'Type': PdfName(value: 'XObject'),
            'Subtype': PdfName(value: 'Form'),
            'BBox': formBounds,
            'Resources': content.dictionary,
            'Group': ?group,
          },
        ),
      ),
    );
  }

  /// Enforces an aggregate operation budget before extending output buffers.
  void _charge(int count) {
    operations += count;
    if (operations > document.limits.maxObjects) {
      throw const FormatException('Printable PDF operation count exceeds its limit.');
    }
  }

  /// Allocates one indirect resource under the source graph's object limit.
  PdfReference _add(PdfValue value) => editor.addObject(value: value);

  /// Chooses a resource name that does not shadow original page resources.
  String _name(String prefix) {
    int suffix = objects.length;
    while (!names.add('$prefix$suffix')) {
      suffix++;
    }
    return '$prefix$suffix';
  }
}
