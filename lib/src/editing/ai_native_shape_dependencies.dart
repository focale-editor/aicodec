part of 'package:aikit/src/model/ai_native_records.dart';

/// Native commands and unresolved differences replacing one original pair slot.
typedef _NativeShapeReplacement = ({
  _NativeShapeBundle bundle,
  List<_NativeShapeReplay> prefix,
  List<_NativeShapeReplay> suffix,
  Set<String> unresolved,
  Set<String> printingUnresolved,
  bool discard,
});

/// A complete qualified source interval with its replay and unresolved effects.
typedef _NativeSourceReplacement = ({
  List<AiNativeInstruction> commands,
  Map<int, _NativeShapeBundle> styles,
  List<_NativeShapeReplay> prefix,
  List<_NativeShapeReplay> suffix,
  Set<String> unresolved,
  Set<String> printingUnresolved,
  bool discard,
});

/// Shares one pair's dependency contract with whole-subtree replacements.
_NativeSourceReplacement _shapeReplacementSource(_NativeShapeReplacement replacement) => (
  commands: replacement.bundle.commands,
  styles: {replacement.bundle.shape.end: replacement.bundle},
  prefix: replacement.prefix,
  suffix: replacement.suffix,
  unresolved: replacement.unresolved,
  printingUnresolved: replacement.printingUnresolved,
  discard: replacement.discard,
);

/// Proves that following objects never consume unresolved replacement effects.
void _shapeFollowingDependencies(
  AiNativeDrawing drawing,
  List<_NativeShapeBundle> slots,
  Map<AiLiveShape, _NativeShapeReplacement> replacements, {
  Map<int, _NativeShapeReplacement> insertions = const {},
}) => _sourceFollowingDependencies(
  drawing,
  {
    for (final _NativeShapeBundle slot in slots)
      if (replacements[slot.shape] case final _NativeShapeReplacement replacement) (start: slot.start, end: slot.shape.end): _shapeReplacementSource(replacement),
  },
  insertions: insertions.map((position, replacement) => MapEntry(position, _shapeReplacementSource(replacement))),
);

/// Visits whole replacement owners and retained pairs in original source order.
void _sourceFollowingDependencies(
  AiNativeDrawing drawing,
  Map<_NativeSubtreeSpan, _NativeSourceReplacement> replacements, {
  Map<int, _NativeSourceReplacement> insertions = const {},
}) {
  if (replacements.isEmpty && insertions.isEmpty) {
    return;
  }
  final Set<String> unresolved = {};
  final Set<String> printingUnresolved = {};
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  final List<int> positions = insertions.keys.toList()..sort();
  int inserted = 0;

  /// Requires identical incoming attributes wherever retained artwork reads them.
  void read(Set<String> keys, {required bool private}) {
    final Set<String> missing = unresolved.intersection(keys);
    if (missing.isNotEmpty) {
      throw UnsupportedError('Following artwork depends on unresolved native style state: ${missing.join(', ')}.');
    }
    if (!private && printingUnresolved.intersection(keys).isNotEmpty) {
      throw UnsupportedError('Following artwork depends on unresolved printing state: ${printingUnresolved.intersection(keys).join(', ')}.');
    }
  }

  /// Accounts for retained assignments before each path or group observes state.
  void command(AiNativeInstruction item, {bool discard = false, _NativeShapeBundle? bundle, bool? private}) {
    final bool nativeOnly = private ?? item.isPrivate;
    final String? key = _nativeArtworkStateKey(item);
    if (key != null) {
      unresolved.remove(key);
      if (!nativeOnly) {
        printingUnresolved.remove(key);
      }
      return;
    }
    if (discard) {
      return;
    }
    if (paths[item.start] case final AiNativePath path) {
      read(_shapeCopyReads(drawing, path), private: nativeOnly);
    } else if (const {'u', '*u'}.contains(item.operator)) {
      read({'A', 'Xw'}, private: nativeOnly);
    } else if (_marker(item, 6)) {
      read({'Xy'}, private: true);
    } else if (_marker(item, 1)) {
      read(bundle!.styleReads, private: true);
      // Potential writes are not definite writes: hidden filter parts may not
      // execute. Keep unresolved keys until an explicit assignment replaces them.
    }
  }

  /// Qualifies ordinary intervening artwork only while state may still differ.
  void ordinary(int start, int end) {
    if (unresolved.isEmpty && printingUnresolved.isEmpty || start == end) {
      return;
    }
    int position = start;
    for (final AiNativeInstruction item in _pathInterval(drawing.items, start, end, (item) => item.start).whereType<AiNativeInstruction>().where((item) => item.isPrivate)) {
      if (_nativeArtworkStateKey(item) == null) {
        throw UnsupportedError('Following private artwork requires a separate native state contract.');
      }
      _layerInterval(layers, position, item.start, headers).forEach(command);
      command(item);
      position = item.end;
    }
    _layerInterval(layers, position, end, headers).forEach(command);
  }

  /// Checks inserted or replacing artwork before publishing its remaining effects.
  void apply(_NativeSourceReplacement replacement) {
    for (final _NativeShapeReplay replay in replacement.prefix) {
      command(replay.value, private: replay.private);
    }
    for (final AiNativeInstruction item in replacement.commands) {
      command(item, discard: replacement.discard, bundle: replacement.styles[item.end]);
    }
    for (final _NativeShapeReplay replay in replacement.suffix) {
      command(replay.value, private: replay.private);
    }
    unresolved.addAll(replacement.unresolved);
    printingUnresolved.addAll(replacement.printingUnresolved);
  }

  /// Visits insertion boundaries even when the preceding source state is unchanged.
  void interval(int start, int end) {
    int position = start;
    while (inserted < positions.length && positions[inserted] <= end) {
      final int boundary = positions[inserted++];
      if (boundary < position) {
        throw const FormatException('A shape insertion crosses an unfinished native owner.');
      }
      ordinary(position, boundary);
      apply(insertions[boundary]!);
      position = boundary;
    }
    ordinary(position, end);
  }

  final List<_NativeSubtreeSpan> spans = replacements.keys.toList()..sort((first, second) => first.start.compareTo(second.start));
  int position = spans.isEmpty
      ? positions.first
      : positions.isEmpty
      ? spans.first.start
      : min(spans.first.start, positions.first);
  final Map<_NativeSubtreeSpan, AiLiveShape> retained = {
    for (final AiLiveShape shape in drawing.liveShapes.where((shape) => shape.isBound && shape.appearanceGroup != null && shape.path?.isPrivate == true && shape.end > position))
      if (!spans.any((span) => shape.start >= span.start && shape.end <= span.end)) (start: drawing._objects.forSource(shape.appearanceGroup!).expansion?.start ?? shape.start, end: shape.end): shape,
  };
  final List<_NativeSubtreeSpan> owners = [...spans, ...retained.keys]..sort((first, second) => first.start.compareTo(second.start));
  for (final _NativeSubtreeSpan owner in owners) {
    if (owner.start < position) {
      throw const FormatException('A native replacement splits an owned source interval.');
    }
    interval(position, owner.start);
    if (replacements[owner] case final _NativeSourceReplacement replacement) {
      apply(replacement);
    } else if (unresolved.isNotEmpty || printingUnresolved.isNotEmpty) {
      final _NativeShapeBundle bundle = _shapeBundle(drawing, retained[owner]!, layers.structure);
      for (final AiNativeInstruction item in bundle.commands) {
        command(item, bundle: bundle);
      }
    }
    position = owner.end;
  }
  interval(position, drawing.records.program.bodyEnd);
  if (inserted != positions.length) {
    throw const FormatException('A shape insertion has no owned native body boundary.');
  }
}
