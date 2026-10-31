part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Compiles complete printable paths, rejecting unrepresented drawing semantics.
List<_PrintableNode> _readPrintable(AiProgram program) {
  for (final AiToken token in AiPostScript.tokenize(program.bytes, maxBytes: program.limits.maxDecodedBytes, maxTokens: program.limits.maxTokens, maxDepth: program.limits.maxDepth)) {
    if (token.start >= program.bodyStart && token.start < program.bodyEnd && (token.kind == .data || token.kind == .comment && token.lexeme.startsWith('%%BeginDocument'))) {
      throw UnsupportedError('Native PDF export requires a renderer for embedded drawing data.');
    }
  }
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: AiNativeRecords.decode(program: program));
  final _PrintableState state = _PrintableState();
  final List<_PrintableContainer> stack = [_PrintableContainer(end: '')];
  final List<PdfOperation> path = [];
  bool clip = false;

  /// Publishes one paint, retaining compound topology until its group ends.
  void paint(String operator) {
    if (path.isEmpty) {
      throw const FormatException('Native paint has no path.');
    }
    if (const {'n', 'f', 's', 'b'}.contains(operator)) {
      path.add(PdfOperation(operator: 'h'));
    }
    if (stack.last.end == '*U') {
      stack.last.compound.addAll(path);
      stack.last.paint = operator;
      stack.last.clip |= clip;
    } else {
      stack.last.children.add(_printablePath(path, operator, state, clip));
    }
    path.clear();
    clip = false;
  }

  for (final AiInstruction instruction in program.instructions) {
    final String operator = instruction.operator;
    switch (operator) {
      case 'm' || 'l' || 'L' || 'c' || 'C' || 'v' || 'V' || 'y' || 'Y':
        final List<double> values = _printableNumbers(instruction);
        AiPathSegment(operator: operator, coordinates: values);
        if (operator != 'm' && path.isEmpty || operator == 'm' && path.isNotEmpty) {
          throw const FormatException('Invalid printable path boundary.');
        }
        path.add(_pdfNumbers(operator.toLowerCase(), values));
      case 'h' || 'H':
        _printableArity(instruction, 0);
        if (path.isEmpty) {
          throw const FormatException('Native closepath has no geometry.');
        }
        if (operator == 'h') {
          path.add(PdfOperation(operator: 'h'));
        }
      case 'W':
        _printableArity(instruction, 0);
        if (path.isEmpty || clip || !stack.any((container) => container.end == 'Q')) {
          throw const FormatException('Native clip requires a path inside a mask group.');
        }
        clip = true;
      case 'N' || 'n' || 'F' || 'f' || 'S' || 's' || 'B' || 'b':
        _printableArity(instruction, 0);
        paint(operator);
      case 'u' || 'q' || '*u' || 'Lb':
        if (path.isNotEmpty || stack.last.end == '*U') {
          throw UnsupportedError('Nested or interrupted compound artwork requires its own renderer.');
        }
        if (stack.length > program.limits.maxDepth) {
          throw const FormatException('Printable drawing nesting exceeds its limit.');
        }
        bool visible = true;
        if (operator == 'Lb') {
          final AiLayer layer = program.layers.singleWhere((layer) => identical(layer.begin, instruction));
          visible = layer.visible && layer.printing;
        } else {
          _printableArity(instruction, 0);
        }
        stack.add(_PrintableContainer(end: operator == 'Lb' ? 'LB' : operator.toUpperCase(), visible: visible));
      case 'U' || 'Q' || '*U' || 'LB':
        _printableArity(instruction, 0);
        if (stack.length <= 1 || stack.last.end != operator || path.isNotEmpty) {
          throw const FormatException('Invalid printable group boundary.');
        }
        final _PrintableContainer completed = stack.removeLast();
        if (operator == '*U') {
          if (completed.paint == null || completed.compound.isEmpty) {
            throw const FormatException('Empty or unpainted native compound path.');
          }
          stack.last.children.add(_printablePath(completed.compound, completed.paint!, state, completed.clip));
        } else {
          stack.last.children.add(_PrintableNode(children: completed.children, group: operator != 'LB', visible: completed.visible));
        }
      case 'Ln':
        if (instruction.operands.length != 1 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(instruction.operands.single.kind)) {
          throw const FormatException('Invalid printable layer name.');
        }
      case 'g' || 'G' || 'k' || 'K' || 'Xa' || 'XA':
        final List<double> values = _printableNumbers(instruction);
        final bool stroke = operator == 'G' || operator == 'K' || operator == 'XA';
        final bool rgb = operator == 'Xa' || operator == 'XA';
        final int expected = rgb
            ? 3
            : operator == 'g' || operator == 'G'
            ? 1
            : 4;
        if ((values.length != expected && !(rgb && values.length == 7)) || values.any((value) => value < 0 || value > 1)) {
          throw const FormatException('Invalid native process color.');
        }
        state.attributes[stroke ? 'stroke' : 'fill'] = _pdfNumbers(rgb ? (stroke ? 'RG' : 'rg') : operator, rgb ? values.sublist(values.length - 3) : values);
      case 'w' || 'J' || 'j' || 'M':
        final double value = _printableArity(instruction, 1).single;
        if (value < 0 || operator == 'M' && value < 1 || const {'J', 'j'}.contains(operator) && (value > 2 || value % 1 != 0)) {
          throw const FormatException('Invalid native stroke attribute.');
        }
        state.attributes[operator] = PdfOperation(
          operator: operator,
          operands: [
            PdfNumber(value: const {'J', 'j'}.contains(operator) ? value.toInt() : value),
          ],
        );
      case 'd':
        final List<AiToken> operands = instruction.operands;
        if (operands.length < 3 || operands.first.kind != .arrayStart || operands[operands.length - 2].kind != .arrayEnd || operands.last.number == null) {
          throw const FormatException('Invalid native dash pattern.');
        }
        final List<double> dash = operands.skip(1).take(operands.length - 3).map((token) => token.number?.toDouble() ?? (throw const FormatException('Invalid native dash length.'))).toList();
        if (dash.any((value) => value < 0) || dash.isNotEmpty && dash.every((value) => value == 0)) {
          throw const FormatException('Invalid native dash pattern.');
        }
        state.attributes['d'] = PdfOperation(
          operator: 'd',
          operands: [
            _pdfArray(dash),
            PdfNumber(value: operands.last.number!),
          ],
        );
      case 'XR':
        final double value = _printableArity(instruction, 1).single;
        if (value != 0 && value != 1) {
          throw const FormatException('Invalid native fill rule.');
        }
        state.evenOdd = value == 1;
      case 'Xy':
        final List<double> values = _printableArity(instruction, 5);
        if (values.first < 0 ||
            values.first >= _printableBlendModes.length ||
            values.first % 1 != 0 ||
            values[1] < 0 ||
            values[1] > 1 ||
            !const {0, 1}.contains(values[2]) ||
            !const {0, 1}.contains(values[3]) ||
            values[4] != 0) {
          throw UnsupportedError('Unsupported native opacity or blend modifier.');
        }
        state.opacity = values[1];
        state.blend = _printableBlendModes[values.first.toInt()];
        state.isolated = values[2] == 1;
        state.knockout = values[3] == 1;
      case 'XW':
        final List<AiToken> operands = instruction.operands;
        if (operands.length != 2 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands.last.kind)) {
          throw const FormatException('Invalid native appearance marker.');
        }
        if (operands.first.number == 6 && aiStringBytes(operands.last).isEmpty) {
          final _PrintableNode? previous = stack.last.children.lastOrNull;
          if (previous == null || !previous.group) {
            throw const FormatException('Native group opacity has no preceding group.');
          }
          previous.opacity = state.opacity;
          previous.blend = state.blend;
          previous.isolated = state.isolated;
          previous.knockout = state.knockout;
        } else if (operands.first.number != 1 || !drawing.liveShapes.any((shape) => shape.end == instruction.end && shape.isBound && shape.appearancePaths.isNotEmpty)) {
          throw UnsupportedError('Native appearance has no resolved printable expansion.');
        }
      case 'D' || 'A' || 'AE' || 'Ae' || 'Ap' || 'As' || 'Xw' || 'Xd' || 'O' || 'R':
        final List<double> values = _printableArity(instruction, operator == 'Xd' ? 2 : 1);
        final bool valid = switch (operator) {
          'As' => values.single >= 0 && values.single % 1 == 0 && values.single <= program.limits.maxTokens,
          'Xd' => const {0, 1}.contains(values.first) && values.last == 0,
          'O' || 'R' || 'Xw' => values.single == 0,
          _ => const {0, 1}.contains(values.single),
        };
        if (!valid) {
          throw UnsupportedError('Unsupported native $operator drawing state.');
        }
      default:
        throw UnsupportedError('Native PDF export cannot render $operator.');
    }
  }
  if (stack.length != 1 || path.isNotEmpty || clip) {
    throw const FormatException('Unterminated printable drawing.');
  }
  return stack.single.children;
}

/// Combines subpaths with their final paint while keeping clip scope explicit.
_PrintableNode _printablePath(List<PdfOperation> geometry, String paint, _PrintableState state, bool clip) {
  final String operator = switch (paint.toUpperCase()) {
    'N' => 'n',
    'F' => state.evenOdd ? 'f*' : 'f',
    'S' => 'S',
    'B' => state.evenOdd ? 'B*' : 'B',
    _ => throw const FormatException('Invalid native path paint.'),
  };
  if (clip && operator != 'n' && (state.opacity != 1 || state.blend != 'Normal' || state.isolated || state.knockout)) {
    throw UnsupportedError('Painting a translucent clipping path requires separate appearances.');
  }
  return _PrintableNode(
    operations: [
      ...state.attributes.values,
      ...geometry,
      if (clip) PdfOperation(operator: state.evenOdd ? 'W*' : 'W'),
      PdfOperation(operator: operator),
    ],
    clip: clip,
    opacity: clip ? 1 : state.opacity,
    blend: state.blend,
    isolated: state.isolated,
    knockout: state.knockout,
  );
}

/// Requires finite numeric operands before interpreting native drawing state.
List<double> _printableNumbers(AiInstruction instruction) => instruction.numbers ?? (throw FormatException('Expected numeric ${instruction.operator} operands.'));

/// Validates exact operator arity without silently ignoring extra operands.
List<double> _printableArity(AiInstruction instruction, int length) {
  final List<double> values = _printableNumbers(instruction);
  if (values.length != length) {
    throw FormatException('Invalid ${instruction.operator} operand count.');
  }
  return values;
}

/// Creates finite PDF numeric operands through the shared PdfCore model.
PdfOperation _pdfNumbers(String operator, List<double> values) => PdfOperation(
  operator: operator,
  operands: values.map((value) => PdfNumber(value: value)),
);

/// Creates a direct PDF numeric array for geometry and stroke resources.
PdfArray _pdfArray(List<double> values) => PdfArray(values: values.map((value) => PdfNumber(value: value)).toList());

/// Illustrator's native blend-mode order, mapped to standard PDF names.
const List<String> _printableBlendModes = [
  'Normal',
  'Multiply',
  'Screen',
  'Overlay',
  'SoftLight',
  'HardLight',
  'ColorDodge',
  'ColorBurn',
  'Darken',
  'Lighten',
  'Difference',
  'Exclusion',
  'Hue',
  'Saturation',
  'Color',
  'Luminosity',
];
