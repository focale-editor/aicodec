part of 'package:aikit/src/model/ai_native_records.dart';

/// Places a complete source owner with separate native and printing state replay.
({List<int> bytes, _NativeSourceReplacement replacement}) _placedNativeSource(
  AiNativeDrawing drawing,
  _NativeSubtreeSpan span,
  List<AiNativeInstruction> commands,
  Map<int, _NativeShapeBundle> styles,
  _NativeShapeAccess access,
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
        throw UnsupportedError('The placed artwork requires an unknown inherited printing $key value.');
      }
      prefix.add((value: value, private: false));
      assign(value, private: false);
    }
  }
  for (final String key in access.nativeReads) {
    if (!_sameShapeAttribute(source.native, source.nativeOrigins, native, nativeOrigins, key)) {
      final AiNativeInstruction? value = source.native[key];
      if (value == null) {
        throw UnsupportedError('The placed artwork requires an unknown inherited native $key value.');
      }
      prefix.add((value: value, private: true));
      assign(value, private: true);
    }
  }
  for (final String key in access.printingWrites) {
    if (sourceOutput.printing[key] case final AiNativeInstruction value) {
      printing[key] = value;
    } else {
      printing.remove(key);
      printingOrigins[key] = sourceOutput.printingOrigins[key]!;
    }
  }
  for (final String key in access.nativeWrites) {
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
      throw const AiLimitException(message: 'Placed native artwork exceeds the native byte limit.');
    }
    bytes.add(value);
  }

  append([10]);
  for (final _NativeShapeReplay replay in prefix) {
    append(latin1.encode(_shapeStateText(replay.value, private: replay.private)));
  }
  append(Uint8List.sublistView(drawing.records.program.bytes, span.start, span.end));
  append([10]);
  for (final _NativeShapeReplay replay in suffix) {
    append(latin1.encode(_shapeStateText(replay.value, private: replay.private)));
  }
  return (
    bytes: bytes.takeBytes(),
    replacement: (
      commands: commands,
      styles: styles,
      prefix: prefix,
      suffix: suffix,
      unresolved: unresolved,
      printingUnresolved: printingUnresolved,
      discard: false,
    ),
  );
}
