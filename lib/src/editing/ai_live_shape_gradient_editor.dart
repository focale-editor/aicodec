part of 'package:aikit/src/model/ai_native_records.dart';

/// Plans selected appearance edits without changing native shape geometry.
abstract interface class _LiveShapeGradientEdit {
  /// Checks caller inputs and source resources before planning source edits.
  void validate();

  /// Requires coherent printable and known-style ownership for this selection.
  void validateShape(AiLiveShape shape);

  /// Plans any setup resource changes in the same source transaction.
  List<AiSourceEdit> resourceEdits();

  /// Changes an owned printable instance or a copied shared-style instance.
  List<AiSourceEdit> instanceEdits(AiNativeGradient gradient);
}

/// Isolates one named gradient across selected native and printable appearances.
final class _LiveShapeGradientIsolation implements _LiveShapeGradientEdit {
  /// Snapshot supplying exact shape ownership and native resource boundaries.
  final AiNativeDrawing drawing;

  /// Original byte name, independent of any host text encoding.
  final List<int> sourceNameBytes;

  /// Caller-selected unused byte name for the isolated resource.
  final List<int> nameBytes;

  /// Validated setup resources, initialized before any edits are planned.
  late final AiNativeGradientResources resources;

  /// Bounded escaped name reused for declarations and references.
  late final Uint8List encodedName;

  /// Remaining output capacity for resource copies and unique name edits.
  late int remaining;

  /// Reuses source edits when several selected objects share one known style.
  final Map<int, AiSourceEdit> _references = {};

  /// Captures input names before planning against an immutable snapshot.
  _LiveShapeGradientIsolation({required this.drawing, required List<int> sourceNameBytes, required List<int> nameBytes})
    : sourceNameBytes = List.unmodifiable(sourceNameBytes),
      nameBytes = List.unmodifiable(nameBytes);

  /// Requires a declared source and a name unused even by unresolved instances.
  @override
  void validate() {
    if ([sourceNameBytes, nameBytes].any((name) => name.isEmpty || name.any((byte) => byte < 0 || byte > 255)) || _gradientBytesEqual(sourceNameBytes, nameBytes)) {
      throw ArgumentError('Gradient isolation requires distinct nonempty byte names.');
    }
    resources = AiNativeGradientResources.decode(records: drawing.records);
    final List<AiNativeGradientDefinition> sources = resources.definitions.where((definition) => _gradientBytesEqual(definition.nameBytes, sourceNameBytes)).toList();
    if (sources.isEmpty || resources.definitions.any((definition) => _gradientBytesEqual(definition.nameBytes, nameBytes))) {
      throw ArgumentError('Gradient isolation requires an existing source and an unused new resource name.');
    }
    if (sources.any((definition) => definition.radial != sources.first.radial)) {
      throw const FormatException('Same-name native gradients have ambiguous linear/radial kinds.');
    }
    if (_readGradientInstances(drawing.records).any((gradient) => _gradientBytesEqual(gradient.geometry.nameBytes, nameBytes))) {
      throw ArgumentError('The new gradient name already has native instance references.');
    }
    remaining = drawing.records.program.limits.maxDecodedBytes - drawing.records.program.bytes.length;
    final _GradientResourceWriter writer = _GradientResourceWriter(limit: remaining);
    writer.string(nameBytes);
    encodedName = writer.output.takeBytes();
  }

  /// Requires the selected gradient in both views instead of guessing ownership.
  @override
  void validateShape(AiLiveShape shape) => _validateLiveShapeGradient(drawing, shape, sourceNameBytes);

  /// Matches raw resource names without interpreting string encodings.
  bool _matches(AiNativeGradient gradient) => _gradientBytesEqual(gradient.geometry.nameBytes, sourceNameBytes);

  /// Copies every matching setup bank while retaining all original resources.
  @override
  List<AiSourceEdit> resourceEdits() => _copyNativeGradientResources(this);

  /// Rebinds only the name operand, preserving geometry, focus and paint flags.
  @override
  List<AiSourceEdit> instanceEdits(AiNativeGradient gradient) {
    if (!_matches(gradient)) {
      return [];
    }
    final AiToken name = gradient.geometry.instruction.operands[gradient.geometry.nameIndex];
    return [
      _references.putIfAbsent(name.start, () {
        reserve(encodedName.length - (name.end - name.start));
        return AiSourceEdit(start: name.start, end: name.end, bytes: encodedName);
      }),
    ];
  }

  /// Checks growth before allocating resource copies or repeated escaped names.
  void reserve(int growth) {
    if (growth > remaining) {
      throw const FormatException('Gradient isolation exceeds the native output limit.');
    }
    remaining -= growth;
  }
}

/// Requires the selected gradient in both views instead of guessing ownership.
void _validateLiveShapeGradient(AiNativeDrawing drawing, AiLiveShape shape, List<int> name) {
  /// Matches raw byte names independently of their string encoding.
  bool matches(AiNativeGradient gradient) => _gradientBytesEqual(gradient.geometry.nameBytes, name);

  final bool printable = drawing.gradients.any(
    (gradient) => matches(gradient) && gradient.paths.isNotEmpty && !gradient.opening.isPrivate && gradient.paths.every(shape.appearancePaths.contains),
  );
  final AiNativeContainer? style = shape.style;
  final bool styled =
      style == null ||
      drawing.records.containers
          .where((record) => record.start > style.start && record.end < style.end && const {'FillStyle', 'StrokeStyle'}.contains(record.type))
          .any((record) => AiNativePaintStyle.decode(records: drawing.records, record: record).gradients.any(matches));
  if (!printable || !styled) {
    throw UnsupportedError('Each selected shape requires a matching printable gradient and its corresponding known style.');
  }
}
