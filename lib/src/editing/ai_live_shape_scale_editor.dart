part of 'package:aicodec/src/model/ai_native_records.dart';

/// Scales a native distance without silently overflowing or collapsing it.
double _scaleNativeLength(double value, double factor) {
  final double changed = value * factor;
  if (!changed.isFinite || changed.abs() > 9007199254740991 || value != 0 && changed == 0) {
    throw ArgumentError('Scaled native geometry exceeds finite source-coordinate limits.');
  }
  return changed;
}

/// Updates dimensional parameters while preserving angles and corner modes.
List<AiSourceEdit> _scaleShapeParameters(AiLiveShape shape, AiNativeContainer parameters, double factor) {
  final Set<String> required = switch (shape.handler) {
    'ai::Rectangle' || 'ai::Ellipse' => {'Width', 'Height'},
    'ai::Polygon' => {'Radius'},
    'ai::Star' => {'Radius1', 'Radius2'},
    'ai::Line' => {'Length'},
    _ => throw UnsupportedError('Unsupported native scaling handler.'),
  };
  if (required.any((name) => parameters['${shape.handler}::$name'] == null)) {
    throw const FormatException('Native scaling requires complete shape dimensions.');
  }
  final List<AiSourceEdit> edits = [];
  for (final AiNativeEntry entry in parameters.entries) {
    final String? key = entry.key;
    if (key == null || !key.startsWith('${shape.handler}::')) {
      continue;
    }
    final String name = key.substring(shape.handler.length + 2);
    if (!required.contains(name) && !const {'CornerRadius', 'Corner1Radius', 'Corner2Radius'}.contains(name) && !name.startsWith('CornerRadius::')) {
      continue;
    }
    // Observed irregular polygons retain -11 as an unavailable regular radius;
    // their editable outline, rather than this sentinel, carries the geometry.
    if (shape.handler == 'ai::Polygon' && name == 'Radius' && entry.type == 'Real' && entry.number == -11 && parameters['ai::Polygon::IsRegular']?.boolean == false) {
      continue;
    }
    if (entry.type != 'Real' || entry.number == null || entry.number! < 0) {
      throw const FormatException('Native scaling requires nonnegative real dimensions and corner radii.');
    }
    edits.add(_numberEdit(entry.items.single, _scaleNativeLength(entry.number!, factor)));
  }
  return edits;
}

/// Retains the inherited stroke distances in one native representation.
final class _ShapeStrokeDistances {
  /// Native line width, whose default is one drawing unit.
  final double width;

  /// Alternating dash and gap lengths, empty for a continuous line.
  final List<double> dashes;

  /// Offset into the dash cycle.
  final double phase;

  /// Creates an immutable default or source-decoded stroke state.
  const _ShapeStrokeDistances({this.width = 1, this.dashes = const [], this.phase = 0});

  /// Reads only the bounded distance-bearing stroke commands.
  _ShapeStrokeDistances read(AiNativeInstruction instruction) {
    if (instruction.operator == 'w') {
      final List<double>? numbers = instruction.numbers;
      if (numbers?.length != 1 || numbers!.single < 0) {
        throw const FormatException('Invalid native stroke width.');
      }
      return _ShapeStrokeDistances(width: numbers.single, dashes: dashes, phase: phase);
    }
    if (instruction.operator != 'd') {
      return this;
    }
    final List<AiToken> operands = instruction.operands;
    if (operands.length < 3 || operands.first.kind != .arrayStart || operands[operands.length - 2].kind != .arrayEnd || operands.last.number == null) {
      throw const FormatException('Invalid native dash operands.');
    }
    final List<AiToken> lengths = operands.sublist(1, operands.length - 2);
    if (lengths.any((token) => token.number == null || token.number! < 0) || lengths.isNotEmpty && lengths.every((token) => token.number == 0)) {
      throw const FormatException('Invalid native dash lengths.');
    }
    return _ShapeStrokeDistances(width: width, dashes: List.unmodifiable(lengths.map((token) => token.number!.toDouble())), phase: operands.last.number!.toDouble());
  }

  /// Emits explicit distances so a selection cannot alter later inherited state.
  String commands(double factor) => '${_scaleNativeLength(width, factor)} w [${dashes.map((value) => _scaleNativeLength(value, factor)).join(' ')}] ${_scaleNativeLength(phase, factor)} d';
}

/// Scales distances within one command without replacing unrelated source bytes.
List<AiSourceEdit> _scaleStrokeCommand(AiNativeInstruction instruction, double factor) {
  if (!const {'w', 'd'}.contains(instruction.operator)) {
    return [];
  }
  const _ShapeStrokeDistances().read(instruction);
  return [
    for (final AiToken token in instruction.operands)
      if (token.number != null) _numberEdit(AiNativeToken._(token: token), _scaleNativeLength(token.number!.toDouble(), factor)),
  ];
}

/// Copies only selected style distances, including inside/outside stroke widths.
List<AiSourceEdit> _scaleKnownStyleStrokes(AiNativeRecords records, AiNativeContainer style, double factor) => [
  for (final AiNativeContainer record in records.containers.where(
    (record) => record.start > style.start && record.end < style.end && const {'FillStyle', 'StrokeStyle', 'BlendStyle'}.contains(record.type),
  ))
    for (final AiNativeInstruction instruction in AiNativePaintStyle.decode(records: records, record: record).instructions) ..._scaleStrokeCommand(instruction, factor),
];

/// Isolates body stroke changes, retaining both printable and authoring state.
List<AiSourceEdit> _scaleLiveShapeStrokes(AiNativeDrawing drawing, List<AiLiveShape> shapes, double factor) {
  final List<AiLiveShape> ordered = shapes.toList()..sort((first, second) => first.start.compareTo(second.start));
  for (int index = 1; index < ordered.length; index++) {
    if (ordered[index].start < ordered[index - 1].end) {
      throw UnsupportedError('Native scaling requires disjoint live-shape appearances.');
    }
  }
  final List<AiSourceEdit> edits = [];
  _ShapeStrokeDistances printable = const _ShapeStrokeDistances();
  _ShapeStrokeDistances authoring = printable;
  int index = 0;
  bool selected = false;

  /// Inserts both views only when their inherited distances differ.
  void insert(int offset, double scale) {
    final String printing = printable.commands(scale);
    final String native = authoring.commands(scale);
    edits.add(AiSourceEdit(start: offset, end: offset, bytes: latin1.encode('\n$printing\n${native == printing ? '' : '%_$native\n'}')));
  }

  for (final AiNativeItem item in drawing.items) {
    if (index < ordered.length && item.start == ordered[index].start) {
      if (drawing.records._projection.isPrivate(item.start)) {
        throw UnsupportedError('Native scaling requires a printable appearance boundary.');
      }
      insert(item.start, factor);
      selected = true;
    }
    if (item is AiNativeInstruction) {
      authoring = authoring.read(item);
      if (!item.isPrivate) {
        printable = printable.read(item);
      }
      if (selected) {
        edits.addAll(_scaleStrokeCommand(item, factor));
      }
    }
    if (selected && item.end == ordered[index].end) {
      insert(item.end, 1);
      selected = false;
      index++;
    }
  }
  if (selected || index != ordered.length) {
    throw UnsupportedError('Native scaling requires complete source-backed appearance boundaries.');
  }
  return edits;
}
