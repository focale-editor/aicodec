part of 'package:aikit/src/model/ai_native_records.dart';

/// Qualifies an immutable private group tree without expanding its appearance.
({List<AiNativeContainer> metadata, Map<AiNativeResourceUse, AiNativeItem> owners, List<AiNativePathTopology> contours}) _nativeAppearanceGroup(
  AiNativeAppearances model,
  AiNativeStructure structure,
  AiNativeGroup group,
) {
  if (!group.opening.isPrivate || !const {'u', '*u', 'q'}.contains(group.opening.operator) || group.paths.isEmpty && group.opening.operator != 'u') {
    throw UnsupportedError('Grouped appearances require private ordinary groups or nonempty compound/clipping groups.');
  }
  final AiNativeDrawing drawing = structure.drawing;
  final List<AiNativePathTopology> contours = _nativeGroupContours(drawing, group);
  final Map<AiNativePath, AiNativePathTopology> topology = {for (final AiNativePathTopology contour in contours) contour.path: contour};
  final List<AiNativeItem> items = _pathInterval(drawing.items, group.start, group.end, (item) => item.start).toList();
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in group.paths) path.start: path};
  final Map<int, AiNativeItem> endings = {
    for (final AiNativePath path in group.paths) path.end: path,
    for (final AiNativeGroup child in drawing.groups.where((child) => child.start >= group.start && child.end <= group.end)) child.end: child,
  };
  final List<AiNativeContainer> metadata = [];
  final Map<AiNativeContainer, AiNativeItem> metadataOwners = {};
  final Map<int, AiNativeResourceUse> references = {for (final AiNativeResourceUse use in model.uses) use.instruction.start: use};
  final Map<AiNativeResourceUse, AiNativeItem> owners = {};
  final List<AiNativeAppearanceLeaf> leaves = [
    for (final AiNativeGroup child in drawing.groups.where((child) => child.start >= group.start && child.end <= group.end))
      if (_readNativeAppearanceLeaf(drawing, child) case final AiNativeAppearanceLeaf leaf) leaf,
  ];
  AiNativeInstruction? count;
  bool panel = false;
  for (int index = 0; index < items.length; index++) {
    final AiNativeItem item = items[index];
    if (leaves.any((leaf) => item.start >= leaf.group.opening.end && item.end <= leaf.group.closing.start)) {
      continue;
    }
    if (item is AiNativeContainer) {
      final AiNativeItem? owner = index == 0 ? null : endings[items[index - 1].end];
      if (owner == null || count != null || panel || !drawing.records._projection.isPrivate(item.start) || !_sameNativeObjectOwner(structure.nodeFor(owner), structure.nodeFor(item))) {
        throw UnsupportedError('Grouped appearance metadata requires direct private ownership.');
      }
      _nativeAppearanceDictionary(item, appearances: model);
      metadata.add(item);
      metadataOwners[item] = owner;
      continue;
    }
    if (item is! AiNativeInstruction || !item.isPrivate) {
      throw UnsupportedError('Grouped authoring artwork cannot mix private and printing commands.');
    }
    final String operator = item.operator;
    if (panel && !const {'u', '*u', 'q'}.contains(operator)) {
      throw UnsupportedError('A private group panel flag must immediately precede its group.');
    }
    if (const {'u', 'U', '*u', '*U', 'q', 'Q'}.contains(operator)) {
      if (item.operands.isNotEmpty || count != null) {
        throw UnsupportedError('Private group boundaries cannot consume operands or point counts.');
      }
      panel = false;
    } else if (paths[item.start] case final AiNativePath path) {
      final Set<AiNativeInstruction> geometry = {...path.geometry, ...topology[path]!.maskControls, path.paint};
      final int first = index;
      while (index + 1 < items.length && items[index + 1].start < path.end) {
        index++;
      }
      if (!path.isPrivate ||
          path.geometry.skip(1).any((command) => command.operator == 'm') ||
          path.geometry.any((command) => command.numbers!.any((value) => value.abs() > 9007199254740991)) ||
          items.sublist(first, index + 1).any((command) => !geometry.contains(command))) {
        throw UnsupportedError('Private group paths require contiguous portable geometry.');
      }
      if (count != null) {
        _nativeAppearanceCount(path, count, closed: path.closed || topology[path]!.mask == .closed);
      }
      count = null;
    } else if (operator == 'As') {
      if (count != null || item.numbers?.length != 1 || item.numbers!.single < 0 || item.numbers!.single != item.numbers!.single.truncateToDouble()) {
        throw UnsupportedError('Private point counts must precede one complete contour.');
      }
      count = item;
    } else if (operator == 'Ae') {
      if (count != null || item.numbers?.length != 1 || !const {0, 1}.contains(item.numbers!.single)) {
        throw UnsupportedError('Private group panel flags require one Boolean value.');
      }
      panel = true;
    } else if (operator == 'Xd') {
      if (item.numbers?.length != 2 || item.numbers!.any((value) => value != 0 && value != 1)) {
        throw UnsupportedError('Private paint flags require two Boolean values.');
      }
    } else if (operator == 'XW') {
      final AiNativeItem? previous = index == 0 ? null : items[index - 1];
      final AiNativeItem? owner = previous == null ? null : endings[previous.end] ?? metadataOwners[previous];
      final AiNativeResourceUse? reference = references[item.start];
      final AiNativeAppearance? style = reference == null ? null : model.resolve(use: reference);
      if (count != null ||
          owner == null ||
          reference == null ||
          style == null ||
          reference.versions.isNotEmpty ||
          style.resource.versions.isNotEmpty ||
          !_sameNativeObjectOwner(structure.nodeFor(owner), structure.nodeFor(item))) {
        throw UnsupportedError('Nested appearances require one unconditional named style and a direct private artwork owner.');
      }
      owners[reference] = owner;
    } else if (_nativeArtworkStateKey(item) == null) {
      throw UnsupportedError('Grouped appearances have no qualified local contract for $operator.');
    }
  }
  if (count != null || panel) {
    throw UnsupportedError('Grouped appearances cannot leave unfinished counts or panel flags.');
  }
  return (metadata: metadata, owners: owners, contours: contours);
}

/// Requires the saved point count and closure to describe exactly one contour.
void _nativeAppearanceCount(AiNativePath path, AiNativeInstruction count, {bool? closed}) {
  final bool closure = closed ?? path.closed;
  final List<double> first = path.geometry.first.numbers!;
  final List<double> last = path.geometry.last.numbers!;
  if (count.numbers?.length != 1 || count.numbers!.single != path.geometry.length - (closure ? 1 : 0) || closure && (first[0] != last[last.length - 2] || first[1] != last.last)) {
    throw UnsupportedError('The authoring point count disagrees with its contour.');
  }
}
