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

/// Explicit private path writes, actual reads and unrestorable outgoing values.
typedef _NativePrivatePathStateChange = ({Set<String> writes, Set<String> reads, Set<String> unresolved});

/// A complete qualified source interval with its replay and unresolved effects.
typedef _NativeSourceReplacement = ({
  List<AiNativeInstruction> commands,
  Map<int, Set<String>> styles,
  List<_NativeShapeReplay> prefix,
  List<_NativeShapeReplay> suffix,
  Set<String> unresolved,
  Set<String> printingUnresolved,
  bool discard,
});

/// Shares one pair's dependency contract with whole-subtree replacements.
_NativeSourceReplacement _shapeReplacementSource(_NativeShapeReplacement replacement) => (
  commands: replacement.bundle.commands,
  styles: {replacement.bundle.shape.end: replacement.bundle.styleReads},
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
///
/// Appearance callers enable clipping to retain enclosing scopes even while
/// current state is equal; lifecycle callers keep their ordinary-owner boundary.
void _sourceFollowingDependencies(
  AiNativeDrawing drawing,
  Map<_NativeSubtreeSpan, _NativeSourceReplacement> replacements, {
  Map<int, _NativeSourceReplacement> insertions = const {},
  List<AiNativeAppearanceArtwork> retainedArtwork = const [],
  bool clipping = false,
  Map<int, Set<String>> styleChanges = const {},
  Map<AiNativePath, _NativePrivatePathStateChange> pathChanges = const {},
  Map<int, Map<String, AiNativeInstruction>> styleRestorations = const {},
  AiNativeLayers? document,
  AiNativeArtworkResource? resource,
  Set<String> patterns = const {},
}) {
  if (replacements.isEmpty && insertions.isEmpty) {
    return;
  }
  final Set<String> unresolved = {};
  final Set<String> printingUnresolved = {};
  final AiNativeLayers layers = document ?? AiNativeLayers.decode(drawing: drawing);
  final Map<int, AiNativeLayer> headers = _layerHeaderItems(layers);
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.start: path};
  late final Map<int, AiNativeItem> images = {for (final _NativeImageOwner owner in _nativeImageOwners(drawing)) owner.instruction.start: owner.image};
  late final Map<int, AiNativeRaster> printingImages = {
    for (final AiNativeAppearanceArtwork owner in retainedArtwork)
      for (final AiNativeRaster image in owner.printingRasters) image.instruction.start: image,
  };
  final Map<int, AiNativeGroup> endings = {for (final AiNativeGroup group in drawing.groups) group.closing.start: group};
  final List<({Set<String> native, Set<String> printing})?> clips = [];
  int compoundDepth = 0;
  final Map<int, _NativePrivatePathStateChange> pathEndings = {for (final MapEntry<AiNativePath, _NativePrivatePathStateChange> entry in pathChanges.entries) entry.key.end: entry.value};
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
  void command(AiNativeInstruction item, {bool discard = false, Set<String>? styleReads, bool? private}) {
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
      final _NativePrivatePathStateChange? change = pathChanges[path];
      if (change != null) {
        if (!nativeOnly || compoundDepth != 0) {
          throw ArgumentError('Private path state changes require independent authoritative contours.');
        }
        unresolved.removeAll(change.writes);
      }
      read(change?.reads ?? (compoundDepth == 0 ? _shapeCopyReads(drawing, path) : _nativeContourFlags), private: nativeOnly);
    } else if (item.operator == 'aikit:mesh') {
      read(_nativeArtworkStateKeys, private: false);
    } else if (const {'aikit:text', 'aikit:symbol'}.contains(item.operator)) {
      read(_nativeArtworkStateKeys, private: true);
    } else if (const {'XI', '`'}.contains(item.operator)) {
      read(_nativeImageReads(printingImages[item.start] ?? images[item.start] ?? (throw UnsupportedError('Following image reads require qualified raster ownership.'))), private: nativeOnly);
    } else if (const {'u', '*u', 'q'}.contains(item.operator)) {
      read({'A', 'Xw'}, private: nativeOnly);
    } else if (_marker(item, 6)) {
      read({'Xy'}, private: true);
    } else if (_marker(item, 0) || _marker(item, 1)) {
      if (styleReads == null) {
        throw UnsupportedError('Following named artwork has no qualified style dependencies.');
      }
      read(styleReads, private: true);
      // Potential writes are not definite writes: hidden filter parts may not
      // execute. Keep unresolved keys until an explicit assignment replaces them.
      unresolved.addAll(styleChanges[item.end] ?? const {});
      for (final AiNativeInstruction value in styleRestorations[item.end]?.values ?? const []) {
        command(value, private: true);
      }
    }
    switch (item.operator) {
      case '*u':
        compoundDepth++;
      case '*U':
        final AiNativeGroup group = endings[item.start]!;
        if (group.paths.isNotEmpty) {
          read(_shapeCopyReads(drawing, group.paths.last)..removeAll(_nativeContourFlags), private: nativeOnly);
        }
        compoundDepth--;
      case 'q':
        clips.add(compoundDepth == 0 ? (native: unresolved.intersection(_nativeClipStateKeys), printing: printingUnresolved.intersection(_nativeClipStateKeys)) : null);
      case 'Q':
        if (clips.removeLast() case final ({Set<String> native, Set<String> printing}) saved) {
          unresolved
            ..removeAll(_nativeClipStateKeys)
            ..addAll(saved.native);
          if (!nativeOnly) {
            printingUnresolved
              ..removeAll(_nativeClipStateKeys)
              ..addAll(saved.printing);
          }
        }
    }
    unresolved.addAll(pathEndings[item.end]?.unresolved ?? const {});
  }

  /// Qualifies ordinary intervening artwork only while state may still differ.
  void ordinary(int start, int end) {
    if (start == end) {
      return;
    }
    if (clipping) {
      final bool changed = unresolved.isNotEmpty || printingUnresolved.isNotEmpty || clips.any((saved) => saved != null && (saved.native.isNotEmpty || saved.printing.isNotEmpty));
      if (changed) {
        (resource == null ? _nativeAppearanceInterval(layers, start, end, headers) : _nativeResourceAppearanceInterval(drawing, start, end)).forEach(command);
      } else {
        // Even equal local state can precede a later edit inside this scope.
        // Keep its entry snapshot so Q cannot inherit that edit's differences.
        for (final AiNativeInstruction item in _pathInterval(drawing.items, start, end, (item) => item.start).whereType<AiNativeInstruction>()) {
          if (const {'q', 'Q', '*u', '*U'}.contains(item.operator)) {
            command(item);
          }
        }
      }
      return;
    }
    if (unresolved.isEmpty && printingUnresolved.isEmpty) {
      return;
    }
    int position = start;
    for (final AiNativeInstruction item in _pathInterval(drawing.items, start, end, (item) => item.start).whereType<AiNativeInstruction>().where((item) => item.isPrivate)) {
      if (drawing.meshArtwork.any((owner) => item.start >= owner.start && item.end <= owner.end)) {
        continue;
      }
      if (_nativeArtworkStateKey(item) == null) {
        throw UnsupportedError('Following private artwork requires a separate native state contract.');
      }
      _layerInterval(layers, position, item.start, headers, appearanceArtwork: retainedArtwork, retainImages: true).forEach(command);
      command(item);
      position = item.end;
    }
    _layerInterval(layers, position, end, headers, appearanceArtwork: retainedArtwork, retainImages: true).forEach(command);
  }

  /// Checks inserted or replacing artwork before publishing its remaining effects.
  void apply(_NativeSourceReplacement replacement) {
    for (final _NativeShapeReplay replay in replacement.prefix) {
      command(replay.value, private: replay.private);
    }
    for (final AiNativeInstruction item in replacement.commands) {
      command(item, discard: replacement.discard, styleReads: replacement.styles[item.end]);
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
  if (clipping) {
    final List<AiNativeGroup> parents = drawing.groups.where((group) => group.start < position && group.end > position).toList()..sort((first, second) => first.start.compareTo(second.start));
    for (final AiNativeGroup group in parents) {
      command(group.opening);
    }
  }
  final Map<_NativeSubtreeSpan, AiLiveShape> retained = {
    for (final AiLiveShape shape in drawing.liveShapes.where((shape) => shape.isBound && shape.appearanceGroup != null && shape.path?.isPrivate == true && shape.end > position))
      if (!spans.any((span) => shape.start >= span.start && shape.end <= span.end) && !retainedArtwork.any((owner) => identical(owner.liveShape, shape)))
        (start: drawing._objects.forSource(shape.appearanceGroup!).expansion?.start ?? shape.start, end: shape.end): shape,
  };
  final Map<_NativeSubtreeSpan, AiNativeAppearanceArtwork> artwork = {
    for (final AiNativeAppearanceArtwork item in retainedArtwork.where((item) => item.end > position))
      if (!spans.any((span) => item.start >= span.start && item.end <= span.end)) (start: item.start, end: item.end): item,
  };
  final List<_NativeSubtreeSpan> owners = [...spans, ...retained.keys, ...artwork.keys]..sort((first, second) => first.start.compareTo(second.start));
  for (final _NativeSubtreeSpan owner in owners) {
    if (owner.start < position) {
      throw const FormatException('A native replacement splits an owned source interval.');
    }
    interval(position, owner.start);
    if (replacements[owner] case final _NativeSourceReplacement replacement) {
      apply(replacement);
    } else if (unresolved.isNotEmpty || printingUnresolved.isNotEmpty) {
      if (artwork[owner] case final AiNativeAppearanceArtwork item) {
        for (final AiNativeInstruction instruction in item._commands) {
          command(instruction, styleReads: item._styleReads[instruction.end]);
        }
      } else {
        final _NativeShapeBundle bundle = _shapeBundle(
          drawing,
          retained[owner]!,
          resource?._structure ?? layers.structure,
          qualifyNeighbors: !clipping && retainedArtwork.isEmpty,
          clipping: clipping || retainedArtwork.isNotEmpty,
          document: layers.drawing,
          patterns: patterns,
        );
        for (final AiNativeInstruction item in bundle.commands) {
          command(item, styleReads: bundle.styleReads);
        }
      }
    }
    position = owner.end;
  }
  interval(position, resource?.artworkEnd ?? drawing.records.program.bodyEnd);
  if (inserted != positions.length) {
    throw const FormatException('A shape insertion has no owned native body boundary.');
  }
  if (clipping && (clips.isNotEmpty || compoundDepth != 0)) {
    throw const FormatException('Appearance state inspection left an unfinished native group.');
  }
  if (resource != null && (unresolved.isNotEmpty || printingUnresolved.isNotEmpty)) {
    throw UnsupportedError('Resource appearance changes must preserve outgoing state at the declaration boundary.');
  }
}
