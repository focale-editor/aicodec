part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Qualifies unchanged geometry without granting its children independent edits.
void _artboardArtworkInterval(
  AiNativeLayers layers,
  int start,
  int end,
  Map<int, AiNativeLayer> headers, {
  required Set<AiNativeContainer> textOwners,
  required Map<AiNativeInstruction, AiNativeResourceUse> styles,
  Set<AiNativeContainer> retainedMetadata = const {},
  Set<AiNativeInstruction> retainedGradients = const {},
  bool retainTransparency = false,
  List<_NativeSubtreeSpan> retainedImages = const [],
}) {
  final AiNativeDrawing drawing = layers.drawing;
  final List<_NativeSubtreeSpan> retainedArtwork = {
    ...retainedImages,
    for (final AiNativeGradientArtwork owner in drawing.gradientArtwork) (start: owner.start, end: owner.end),
    for (final AiNativeMeshArtwork owner in drawing.meshArtwork) (start: owner.start, end: owner.end),
  }.toList()..sort((first, second) => first.start.compareTo(second.start));
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in _pathInterval(drawing.paths, start, end, (path) => path.start)) path.start: path};
  final Map<int, AiNativeGroup> groups = {for (final AiNativeGroup group in drawing.groups.where((group) => group.start >= start && group.start < end)) group.start: group};
  final Set<AiNativeInstruction> endings = {for (final AiNativeGroup group in drawing.groups) group.closing};
  final List<AiNativeItem> items = _pathInterval(drawing.items, start, end, (item) => item.start).toList();
  AiNativeInstruction? count;
  int imageIndex = 0;
  for (int index = 0; index < items.length; index++) {
    final AiNativeItem item = items[index];
    if (item.end > end) {
      throw UnsupportedError('Artboard dependency inspection crosses an unfinished native object.');
    }
    while (imageIndex < retainedArtwork.length && retainedArtwork[imageIndex].end <= item.start) {
      imageIndex++;
    }
    if (imageIndex < retainedArtwork.length && retainedArtwork[imageIndex].start <= item.start) {
      final _NativeSubtreeSpan image = retainedArtwork[imageIndex];
      if (count != null || image.start < start || image.end > end || item.end > image.end) {
        throw UnsupportedError('Retained images require complete boundaries without pending point counts.');
      }
      continue;
    }
    if (paths[item.start] case final AiNativePath path) {
      if (path.isPrivate || path.end > end || layers.structure.nodeFor(path).versions.isNotEmpty) {
        throw UnsupportedError('Retained paths require ordinary unconditional ownership.');
      }
      _ordinaryObject(drawing, path);
      final int first = index;
      while (index + 1 < items.length && items[index + 1].start < path.end) {
        index++;
      }
      _artboardRetainedPath(layers, path, items.sublist(first, index + 1).where((command) => !retainedGradients.contains(command)).toList(), count);
      count = null;
      continue;
    }
    if (retainedGradients.contains(item)) {
      if (count != null && (item as AiNativeInstruction).operator == 'BB') {
        throw const FormatException('A retained gradient cannot leave an unconsumed point count.');
      }
      continue;
    }
    if (headers[item.start] case final AiNativeLayer layer) {
      if (count != null || layer.bindingIssue != null && !retainedMetadata.contains(layer.dictionary)) {
        throw UnsupportedError('A retained layer has unresolved metadata or point-count ownership.');
      }
      continue;
    }
    if (_ordinaryObjectAttachment(drawing, item) || textOwners.contains(item) || retainedMetadata.contains(item) || retainedMetadata.contains(drawing._objects._attachments[item.start]?.dictionary)) {
      if (count != null) {
        throw UnsupportedError('A retained point count crosses object metadata.');
      }
      continue;
    }
    if (item is! AiNativeInstruction) {
      throw UnsupportedError('Artboard dependencies include an unresolved artwork owner.');
    }
    if (groups[item.start] case final AiNativeGroup group) {
      if (!retainedMetadata.contains(drawing._objects.forSource(group).dictionary)) {
        _ordinaryObject(drawing, group);
      }
      if (layers.structure.nodeFor(group).versions.isNotEmpty) {
        throw UnsupportedError('Retained group topology requires unconditional ownership.');
      }
    }
    if (groups.containsKey(item.start) || endings.contains(item)) {
      if (count != null || item.isPrivate || item.operands.isNotEmpty) {
        throw UnsupportedError('Retained group boundaries require ordinary syntax and no pending point count.');
      }
    } else if (item.operator == 'As') {
      if (count != null || item.isPrivate || item.numbers?.length != 1 || item.numbers!.single < 0 || item.numbers!.single != item.numbers!.single.truncateToDouble()) {
        throw const FormatException('Invalid retained native point count.');
      }
      count = item;
    } else if (item.operator == 'XW') {
      _artboardRetainedStyleUse(item, styles[item]);
    } else if (item.operator == 'Xd') {
      if (item.isPrivate || item.numbers?.length != 2 || item.numbers!.any((value) => value != 0 && value != 1)) {
        throw UnsupportedError('Retained fill/stroke flags require ordinary literal Booleans.');
      }
    } else if (item.operator == 'Xy' && retainTransparency && !item.isPrivate) {
      _artboardRetainedOpacity(item);
    } else if (_nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('Artboard dependency inspection does not cover ${item.operator}.');
    }
  }
  if (count != null) {
    throw const FormatException('A retained native point count has no path.');
  }
  final Set<int> wrappers = {
    for (final AiNativeLayer layer in layers.layers) ...[
      if (layer.openingComment != null) layer.openingComment!.start,
      if (layer.closingComment != null) layer.closingComment!.start,
    ],
  };
  imageIndex = 0;
  if (_pathInterval(drawing.records._projection.tokens, start, end, (token) => token.start).any((token) {
    while (imageIndex < retainedArtwork.length && retainedArtwork[imageIndex].end <= token.start) {
      imageIndex++;
    }
    if (imageIndex < retainedArtwork.length && retainedArtwork[imageIndex].start <= token.start && token.end <= retainedArtwork[imageIndex].end) {
      return false;
    }
    return token.kind == .data || token.kind == .comment && !wrappers.contains(token.start) && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%'));
  })) {
    throw UnsupportedError('Retained artwork contains unresolved annotations or opaque payloads.');
  }
}

/// Resolves unchanged style uses without applying their paints or effects.
void _artboardRetainedStyleUse(AiNativeInstruction command, AiNativeResourceUse? reference) {
  if (command.isPrivate || command.operands.length != 2 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(command.operands.last.kind)) {
    throw UnsupportedError('Retained styles require ordinary literal references.');
  }
  final num? mode = command.operands.first.number;
  if (const {0, 1, 6, 9}.contains(mode) && aiStringBytes(command.operands.last).isEmpty) {
    return;
  }
  if (!const {0, 1}.contains(mode) || reference?.resolution != .resolved) {
    throw UnsupportedError('Retained style assignments require one resolved setup definition.');
  }
}

/// Keeps compound and clipping geometry in its recorded coordinate basis.
void _artboardRetainedPath(AiNativeLayers layers, AiNativePath path, List<AiNativeItem> items, AiNativeInstruction? count, {bool? clipping}) {
  final bool inClip =
      clipping ?? (items.length > path.geometry.length + 1 && _artworkParents(layers.structure, layers.structure.parentOf(layers.structure.nodeFor(path))).any((parent) => parent.kind == .clip));
  _nativeRetainedPath(path, items, count, clipping: inClip);
}

/// Shares contiguous contour and mask validation across retained native owners.
void _nativeRetainedPath(AiNativePath path, List<AiNativeItem> items, AiNativeInstruction? count, {required bool clipping}) {
  if (path.geometry.skip(1).any((command) => command.operator == 'm') ||
      path.geometry.any((command) => command.numbers!.any((value) => value.abs() > 9007199254740991)) ||
      items.length < path.geometry.length + 1 ||
      path.geometry.indexed.any((entry) => !identical(entry.$2, items[entry.$1])) ||
      !identical(items.last, path.paint)) {
    throw UnsupportedError('Retained paths require contiguous portable geometry and one owned paint.');
  }
  final List<AiNativeItem> controls = items.sublist(path.geometry.length, items.length - 1);
  bool closed = path.closed;
  if (controls.isNotEmpty) {
    if (controls.length != 2 ||
        controls.first is! AiNativeInstruction ||
        controls.last is! AiNativeInstruction ||
        !const {'h', 'H'}.contains((controls.first as AiNativeInstruction).operator) ||
        (controls.last as AiNativeInstruction).operator != 'W' ||
        controls.cast<AiNativeInstruction>().any((command) => command.isPrivate != path.isPrivate || command.operands.isNotEmpty) ||
        !clipping) {
      throw UnsupportedError('Retained path masks require h/H W before paint inside an owned clipping group.');
    }
    closed |= (controls.first as AiNativeInstruction).operator == 'h';
  }
  if (count != null) {
    final List<double> first = path.geometry.first.numbers!;
    final List<double> last = path.geometry.last.numbers!;
    if (count.numbers!.single != path.geometry.length - (closed ? 1 : 0) || closed && (path.geometry.length == 1 || first[0] != last[last.length - 2] || first[1] != last.last)) {
      throw const FormatException('Retained native point count disagrees with its path.');
    }
  }
}
