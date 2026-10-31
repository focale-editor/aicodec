part of 'package:aikit/src/model/ai_native_pdf.dart';

/// Compiles complete printable paths, rejecting unrepresented drawing semantics.
List<_PrintableNode> _readPrintable(AiProgram program, AiNativePlacementResolver? resolvePlacement) {
  final AiNativeRecords records = AiNativeRecords.decode(program: program);
  final List<AiNativeRaster> rasters = AiNativeRasters.decode(records: records, bodyOnly: true).images;
  final Set<int> rasterData = {
    for (final AiNativeRaster image in rasters)
      if (image.instruction.isPrivate) image.instruction.token.start else image.data.start,
  };
  final Map<int, AiNativeRaster> rasterCommands = {
    for (final AiNativeRaster image in rasters.where((image) => image.isPrintable(program: program)))
      for (final AiNativeInstruction command in image.commands) command.end: image,
  };
  for (final AiNativeRaster image in rasters) {
    image.validateProcessLayout();
  }
  final List<AiNativePlacedObject> placements = AiNativePlacements.decode(records: records, bodyOnly: true).objects;
  final Map<int, AiNativePlacedObject> placedCommands = {
    for (final AiNativePlacedObject object in placements.where((object) => object.isPrintable(program: program))) ...{
      object.instruction.end: object,
      object.closing.end: object,
    },
  };
  for (final AiNativePlacedObject object in placements) {
    if (object.isPrintable(program: program)) {
      object.validateRasterLayout();
    }
  }
  int colorModel = 1;
  int placementIndex = 0;
  for (final AiToken token in AiPostScript.tokenize(program.bytes, maxBytes: program.limits.maxDecodedBytes, maxTokens: program.limits.maxTokens, maxDepth: program.limits.maxDepth)) {
    if (token.start < program.bodyStart && token.kind == .comment && token.lexeme.startsWith('%AI9_ColorModel:')) {
      colorModel = int.tryParse(token.lexeme.substring('%AI9_ColorModel:'.length).trim()) ?? 0;
    }
    while (placementIndex < placements.length && placements[placementIndex].end <= token.start) {
      placementIndex++;
    }
    final AiNativePlacedPreview? preview = placementIndex < placements.length ? placements[placementIndex].preview : null;
    final bool previewData = preview != null && token.start > preview.start && token.end < preview.end;
    if (token.start >= program.bodyStart &&
        token.start < program.bodyEnd &&
        (token.kind == .data && !rasterData.contains(token.start) && !previewData || token.kind == .comment && token.lexeme.startsWith('%%BeginDocument'))) {
      throw UnsupportedError('Native PDF export requires a renderer for embedded drawing data.');
    }
  }
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final Map<int, AiNativeGradient> gradients = {for (final AiNativeGradient gradient in drawing.gradients.where((gradient) => !gradient.opening.isPrivate)) gradient.opening.end: gradient};
  final Map<String, AiNativeGradientDefinition> definitions = {
    if (gradients.values.any((gradient) => gradient.paths.isNotEmpty))
      for (final AiNativeGradientDefinition definition in AiNativeGradientResources.decode(records: drawing.records).definitions) latin1.decode(definition.nameBytes): definition,
  };
  _PrintableGradient? gradient;
  AiNativeGradient? gradientInstance;
  final _PrintableState state = _PrintableState();
  _PrintableState? appearanceState;
  final List<_PrintableContainer> stack = [_PrintableContainer(end: '')];
  _PrintableContainer? compound;
  bool compoundGroupClosed = false;
  final List<PdfOperation> path = [];
  bool clip = false;
  bool rasterClosed = false;

  /// Publishes one paint, retaining compound topology until its group ends.
  void paint(String operator) {
    if (path.isEmpty) {
      throw const FormatException('Native paint has no path.');
    }
    if (const {'n', 'f', 's', 'b'}.contains(operator)) {
      path.add(PdfOperation(operator: 'h'));
    }
    if (compound case final _PrintableContainer owner) {
      owner.compound.addAll(path);
      owner.paint = operator;
      owner.paintState = _PrintableState.copy(source: state);
      owner.gradient = gradient;
      owner.clip |= clip;
      compoundGroupClosed = false;
    } else {
      stack.last.children.add(_printablePath(path, operator, state, clip, gradient: gradient));
    }
    path.clear();
    clip = false;
    appearanceState = null;
  }

  for (final AiInstruction instruction in program.instructions) {
    final String operator = instruction.operator;
    final AiNativeRaster? image = rasterCommands[instruction.end];
    if (image != null) {
      if (path.isNotEmpty || compound != null || gradientInstance != null || clip) {
        throw UnsupportedError('A raster cannot interrupt a native path or gradient.');
      }
      if (operator == 'XI') {
        stack.last.children.add(
          _PrintableNode(
            operations: state.attributes.values.toList(),
            raster: _PrintableRaster.embedded(image: image),
            opacity: state.opacity,
            blend: state.blend,
            isolated: state.isolated,
            knockout: state.knockout,
          ),
        );
        appearanceState = null;
      }
      rasterClosed = operator == 'XH';
      continue;
    }
    final AiNativePlacedObject? placed = placedCommands[instruction.end];
    if (placed != null) {
      if (path.isNotEmpty || compound != null || gradientInstance != null || clip) {
        throw UnsupportedError('A linked image cannot interrupt a native path or gradient.');
      }
      if (operator == '`') {
        final AiNativeRasterSamples? samples = resolvePlacement?.call(placed);
        if (samples == null) {
          throw UnsupportedError('Native PDF export requires explicit pixels for every printable linked image.');
        }
        stack.last.children.add(
          _PrintableNode(
            operations: state.attributes.values.toList(),
            raster: _PrintableRaster.placed(object: placed, samples: samples),
            opacity: state.opacity,
            blend: state.blend,
            isolated: state.isolated,
            knockout: state.knockout,
          ),
        );
        appearanceState = null;
      }
      rasterClosed = operator == '~';
      continue;
    }
    if (rasterClosed && operator == 'N') {
      _printableArity(instruction, 0);
      rasterClosed = false;
      continue;
    }
    rasterClosed = false;
    switch (operator) {
      case 'Bb':
        if (gradientInstance != null) {
          throw const FormatException('Nested printable gradient.');
        }
        final AiNativeGradient native = gradients[instruction.end] ?? (throw const FormatException('Missing printable gradient instance.'));
        gradientInstance = native;
        if (native.paths.isNotEmpty) {
          if (colorModel != 1 && colorModel != 2) {
            throw UnsupportedError('Unknown native gradient document color model.');
          }
          final AiNativeGradientDefinition definition = definitions[latin1.decode(native.geometry.nameBytes)] ?? (throw const FormatException('Missing native gradient definition.'));
          gradient = _PrintableGradient(native: native, definition: definition, cmyk: colorModel == 2);
        }
      case 'Bg' || 'Bh' || 'Xm' || 'Bm' || 'Bc':
        if (gradientInstance == null || instruction.end > gradientInstance.closing.start) {
          throw const FormatException('Gradient command outside its printable instance.');
        }
      case 'BB':
        if (gradientInstance == null || instruction.end != gradientInstance.end || path.isNotEmpty) {
          throw const FormatException('Invalid printable gradient termination.');
        }
        gradient = null;
        gradientInstance = null;
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
        if (path.isNotEmpty || compound != null && operator != 'u') {
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
        if (operator == '*u') {
          compound = stack.last;
        }
        compoundGroupClosed = false;
        appearanceState = null;
      case 'U' || 'Q' || '*U' || 'LB':
        _printableArity(instruction, 0);
        if (stack.length <= 1 || stack.last.end != operator || path.isNotEmpty) {
          throw const FormatException('Invalid printable group boundary.');
        }
        final _PrintableContainer completed = stack.removeLast();
        appearanceState = null;
        if (operator == '*U') {
          if (completed.paint == null || completed.compound.isEmpty) {
            throw const FormatException('Empty or unpainted native compound path.');
          }
          stack.last.children.add(_printablePath(completed.compound, completed.paint!, completed.paintState!, completed.clip, gradient: completed.gradient));
          compound = null;
          compoundGroupClosed = false;
        } else if (compound != null) {
          compoundGroupClosed = true;
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
        if (operands.first.number == 9 &&
            aiStringBytes(operands.last).isEmpty &&
            (compound != null ? compoundGroupClosed : stack.last.children.lastOrNull?.group == true || stack.last.children.lastOrNull?.raster != null)) {
          // A plain group marker carries no independent appearance state.
          compoundGroupClosed = false;
        } else if (operands.first.number == 6 && aiStringBytes(operands.last).isEmpty) {
          final _PrintableNode? previous = stack.last.children.lastOrNull;
          if (previous == null || previous.clip || !previous.group && (previous.operations.isEmpty || appearanceState == null)) {
            throw const FormatException('Native appearance state has no preceding drawable object.');
          }
          final _PrintableState appearance = appearanceState ?? state;
          previous.opacity = appearance.opacity;
          previous.blend = appearance.blend;
          previous.isolated = appearance.isolated;
          previous.knockout = appearance.knockout;
        } else if (operands.first.number != 1 || !drawing.liveShapes.any((shape) => shape.end == instruction.end && shape.isBound && shape.appearancePaths.isNotEmpty)) {
          throw UnsupportedError('Native appearance has no resolved printable expansion.');
        }
        appearanceState = null;
      case 'D' || 'A' || 'AE' || 'Ae' || 'Ap' || 'As' || 'Xw' || 'Xd' || 'O' || 'R':
        final List<double> values = _printableArity(instruction, operator == 'Xd' ? 2 : 1);
        final bool valid = switch (operator) {
          'As' => values.single >= 0 && values.single % 1 == 0 && values.single <= program.limits.maxTokens,
          'Xd' => values.every((value) => const {0, 1}.contains(value)),
          'O' || 'R' || 'Xw' => values.single == 0,
          _ => const {0, 1}.contains(values.single),
        };
        if (!valid) {
          throw UnsupportedError('Unsupported native $operator drawing state.');
        }
        if (operator == 'Xd') {
          appearanceState = _PrintableState.copy(source: state);
        }
      default:
        throw UnsupportedError('Native PDF export cannot render $operator.');
    }
  }
  if (stack.length != 1 || path.isNotEmpty || clip || gradientInstance != null) {
    throw const FormatException('Unterminated printable drawing.');
  }
  return stack.single.children;
}

/// Combines subpaths with their final paint while keeping clip scope explicit.
_PrintableNode _printablePath(List<PdfOperation> geometry, String paint, _PrintableState state, bool clip, {_PrintableGradient? gradient}) {
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
  if (gradient != null && (clip || !(gradient.native.onStroke ? const {'S'} : const {'F', 'B'}).contains(paint.toUpperCase()))) {
    throw UnsupportedError('Native gradient rendering requires its own non-clipping fill or stroke appearance.');
  }
  return _PrintableNode(
    operations: [
      ...state.attributes.values,
      ...geometry,
      if (clip) PdfOperation(operator: state.evenOdd ? 'W*' : 'W'),
      if (gradient == null) PdfOperation(operator: operator),
    ],
    gradient: gradient,
    gradientStroke: gradient != null && !gradient.native.onStroke && (gradient.native.closing.numbers!.single > 0 || paint.toUpperCase() == 'B')
        ? [...state.attributes.values, ...geometry, if (gradient.native.closing.numbers!.single == 2) PdfOperation(operator: 'h'), PdfOperation(operator: 'S')]
        : const [],
    evenOdd: state.evenOdd,
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
