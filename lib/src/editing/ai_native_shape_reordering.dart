part of 'package:aikit/src/model/ai_native_records.dart';

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
  final Map<String, AiNativeInstruction> printing = Map.of(incoming.printing);
  final Map<String, AiNativeInstruction> native = Map.of(incoming.native);
  final Map<String, int> printingOrigins = Map.of(incoming.printingOrigins);
  final Map<String, int> nativeOrigins = Map.of(incoming.nativeOrigins);
  final List<_NativeShapeReplay> prefix = [];
  final List<_NativeShapeReplay> suffix = [];
  final Set<String> unresolved = {};
  final Set<String> printingUnresolved = {};
  final _NativeShapeAccess access = _shapeAccess(drawing, bundle);

  /// Applies a literal in both interpretations or only the private native stream.
  void assign(AiNativeInstruction value, {required bool private}) {
    final String key = _nativeArtworkStateKey(value)!;
    native[key] = value;
    if (!private) {
      printing[key] = value;
    }
  }

  for (final String key in access.printingReads) {
    if (!_sameShapeAttribute(source.printing, source.printingOrigins, printing, printingOrigins, key)) {
      final AiNativeInstruction? value = source.printing[key];
      if (value == null) {
        throw UnsupportedError('The placed shape requires an unknown inherited printing $key value.');
      }
      prefix.add((value: value, private: false));
      assign(value, private: false);
    }
  }
  for (final String key in access.nativeReads) {
    if (!_sameShapeAttribute(source.native, source.nativeOrigins, native, nativeOrigins, key)) {
      final AiNativeInstruction? value = source.native[key];
      if (value == null) {
        throw UnsupportedError('The placed shape requires an unknown inherited native $key value.');
      }
      prefix.add((value: value, private: true));
      assign(value, private: true);
    }
  }
  for (final AiNativeInstruction command in bundle.commands) {
    if (_nativeArtworkStateKey(command) != null) {
      assign(command, private: command.isPrivate);
    }
  }
  for (final String key in bundle.styleWrites) {
    if (sourceOutput.native[key] case final AiNativeInstruction value) {
      native[key] = value;
    } else {
      native.remove(key);
      nativeOrigins[key] = sourceOutput.nativeOrigins[key]!;
    }
  }
  for (final String key in _nativeArtworkStateKeys) {
    if (!_sameShapeAttribute(printing, printingOrigins, outgoing.printing, outgoing.printingOrigins, key)) {
      final AiNativeInstruction? value = outgoing.printing[key];
      if (value == null) {
        printingUnresolved.add(key);
        continue;
      }
      suffix.add((value: value, private: false));
      assign(value, private: false);
    }
  }
  for (final String key in _nativeArtworkStateKeys) {
    if (!_sameShapeAttribute(native, nativeOrigins, outgoing.native, outgoing.nativeOrigins, key)) {
      final AiNativeInstruction? value = outgoing.native[key];
      if (value == null) {
        unresolved.add(key);
      } else {
        suffix.add((value: value, private: true));
        assign(value, private: true);
      }
    }
  }
  final BytesBuilder bytes = BytesBuilder(copy: false);

  /// Bounds complete source slices and replay instructions under one byte budget.
  void append(List<int> value) {
    if (bytes.length + value.length > maxBytes) {
      throw const AiLimitException(message: 'Placed native shapes exceed the native byte limit.');
    }
    bytes.add(value);
  }

  append([10]);
  for (final _NativeShapeReplay replay in prefix) {
    append(latin1.encode(_shapeStateText(replay.value, private: replay.private)));
  }
  append(Uint8List.sublistView(drawing.records.program.bytes, bundle.start, bundle.shape.end));
  append([10]);
  for (final _NativeShapeReplay replay in suffix) {
    append(latin1.encode(_shapeStateText(replay.value, private: replay.private)));
  }
  return (
    bytes: bytes.takeBytes(),
    replacement: (
      bundle: bundle,
      prefix: prefix,
      suffix: suffix,
      unresolved: unresolved,
      printingUnresolved: printingUnresolved,
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
