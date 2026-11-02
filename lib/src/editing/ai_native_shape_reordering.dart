part of 'package:aicodec/src/model/ai_native_records.dart';

/// One source-derived scalar assignment and its output projection.
typedef _NativeShapeReplay = ({AiNativeInstruction value, bool private});

/// Compares known assignments or the same unchanged unknown source origin.
bool _sameShapeAttribute(
  Map<String, AiNativeInstruction> first,
  Map<String, int> firstOrigins,
  Map<String, AiNativeInstruction> second,
  Map<String, int> secondOrigins,
  String key,
) => first[key] == null && second[key] == null ? firstOrigins[key] == secondOrigins[key] : _sameNativeArtworkState(first[key], second[key]);

/// Places one complete source pair between qualified input and output states.
({List<int> bytes, _NativeShapeReplacement replacement}) _placedNativeShape(
  AiNativeDrawing drawing,
  _NativeShapeBundle bundle,
  _NativeShapeInputs source,
  _NativeShapeInputs sourceOutput,
  _NativeShapeInputs incoming,
  _NativeShapeInputs outgoing, {
  required int maxBytes,
}) {
  final ({List<int> bytes, _NativeSourceReplacement replacement}) placed = _placedNativeSource(
    drawing,
    (start: bundle.start, end: bundle.shape.end),
    bundle.commands,
    {bundle.shape.end: bundle},
    _shapeAccess(drawing, bundle),
    source,
    sourceOutput,
    incoming,
    outgoing,
    maxBytes: maxBytes,
  );
  return (
    bytes: placed.bytes,
    replacement: (
      bundle: bundle,
      prefix: placed.replacement.prefix,
      suffix: placed.replacement.suffix,
      unresolved: placed.replacement.unresolved,
      printingUnresolved: placed.replacement.printingUnresolved,
      discard: false,
    ),
  );
}

/// Reorders qualified complete sibling pairs without rewriting their identities.
AiNativeDrawing _reorderNativeShapes(AiNativeDrawing drawing, List<AiLiveShape> shapes) {
  final List<_NativeShapeBundle> slots = _selectedShapeBundles(drawing, shapes);
  final AiNativeStructure structure = drawing._objects.structure;
  final int? parent = structure.nodeFor(slots.first.shape.appearanceGroup!).parentIndex;
  if (slots.any((bundle) => structure.nodeFor(bundle.shape.appearanceGroup!).parentIndex != parent)) {
    throw ArgumentError('Reordering shapes requires one immediate native parent.');
  }
  if (slots.indexed.every((entry) => identical(entry.$2.shape, shapes[entry.$1]))) {
    return drawing;
  }
  final Map<AiLiveShape, _NativeShapeBundle> bundles = {for (final _NativeShapeBundle bundle in slots) bundle.shape: bundle};
  final Map<int, _NativeShapeInputs> states = _shapeCopyInputs(drawing, slots.expand((bundle) => [bundle.start, bundle.shape.end]));
  final List<AiSourceEdit> edits = [];
  final Map<AiLiveShape, _NativeShapeReplacement> replacements = {};
  int remaining = drawing.records.program.limits.maxDecodedBytes;
  for (final (int, _NativeShapeBundle) entry in slots.indexed) {
    final _NativeShapeBundle slot = entry.$2;
    final _NativeShapeBundle source = bundles[shapes[entry.$1]]!;
    if (identical(slot, source)) {
      continue;
    }
    final ({List<int> bytes, _NativeShapeReplacement replacement}) placed = _placedNativeShape(
      drawing,
      source,
      states[source.start]!,
      states[source.shape.end]!,
      states[slot.start]!,
      states[slot.shape.end]!,
      maxBytes: remaining,
    );
    edits.add(AiSourceEdit(start: slot.start, end: slot.shape.end, bytes: placed.bytes));
    replacements[slot.shape] = placed.replacement;
    remaining -= placed.bytes.length;
  }
  _shapeFollowingDependencies(drawing, slots, replacements);
  return _groupLifecycleResult(drawing, edits, paths: drawing.paths.length, groups: drawing.groups.length);
}
