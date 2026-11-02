part of 'package:aicodec/src/model/ai_native_records.dart';

/// Inspects local contours without granting independent edits to derived data.
///
/// Retained ordinary compounds can supply outermost-first ancestors so mask
/// ownership includes a clipping scope outside the inspected subtree.
List<AiNativePathTopology> _nativeGroupContours(AiNativeDrawing drawing, AiNativeGroup root, {Set<AiNativeInstruction> retainedCommands = const {}, List<AiNativeGroup> ancestors = const []}) {
  final Map<int, AiNativeGroup> groups = {for (final AiNativeGroup group in drawing.groups.where((group) => group.start >= root.start && group.end <= root.end)) group.start: group};
  final Map<int, AiNativePath> paths = {for (final AiNativePath path in root.paths) path.start: path};
  final List<AiNativeItem> items = _pathInterval(drawing.items, root.start, root.end, (item) => item.start).toList();
  final List<AiNativeGroup> stack = [...ancestors];
  final List<AiNativePathTopology> result = [];
  AiNativeInstruction? count;
  for (int index = 0; index < items.length; index++) {
    final AiNativeItem item = items[index];
    if (groups[item.start] case final AiNativeGroup group) {
      if (count != null || group.opening.isPrivate != root.opening.isPrivate || group.opening.operands.isNotEmpty) {
        throw UnsupportedError('Group contours require matching representations and owned point counts.');
      }
      stack.add(group);
    } else if (stack.isNotEmpty && identical(stack.last.closing, item)) {
      if (count != null || (item as AiNativeInstruction).operands.isNotEmpty) {
        throw UnsupportedError('Group boundaries cannot consume pending point counts or operands.');
      }
      stack.removeLast();
    } else if (paths[item.start] case final AiNativePath path) {
      final int first = index;
      while (index + 1 < items.length && items[index + 1].start < path.end) {
        index++;
      }
      final List<AiNativeItem> commands = items.sublist(first, index + 1).where((item) => !retainedCommands.contains(item) || identical(item, path.paint)).toList();
      final List<AiNativeInstruction> controls = commands.whereType<AiNativeInstruction>().where((command) => const {'h', 'H', 'W'}.contains(command.operator)).toList();
      final AiNativePathTopology topology = AiNativePathTopology._(path: path, groups: stack, pointCount: count, maskControls: controls);
      if (path.isPrivate != root.opening.isPrivate) {
        throw UnsupportedError('Group contours cannot mix private and printing geometry.');
      }
      _nativeRetainedPath(path, commands, null, clipping: topology.clippingGroup != null);
      result.add(topology);
      count = null;
    } else if (item is AiNativeInstruction && item.operator == 'As') {
      if (count != null || item.numbers?.length != 1 || item.numbers!.single < 0 || item.numbers!.single % 1 != 0 || item.isPrivate != root.opening.isPrivate) {
        throw UnsupportedError('Group contours require one literal point count per path.');
      }
      count = item;
    } else if (count != null && item is! AiNativeInstruction) {
      throw UnsupportedError('A group point count cannot cross an object dictionary.');
    }
  }
  if (count != null || stack.length != ancestors.length) {
    throw UnsupportedError('Group contours require complete boundaries and point-count ownership.');
  }
  for (final AiNativeGroup compound in groups.values.where((group) => group.compound)) {
    final List<AiNativePathTopology> children = result.where((path) => path.groups.contains(compound)).toList();
    if (!children.any((path) => path.mask != .none)) {
      continue;
    }
    if (children.any((path) => path.mask == .none || path.groups.where((group) => group.compound).length != 1) || children.map((path) => path.path.paint.operator.toUpperCase()).toSet().length != 1) {
      throw UnsupportedError('Compound masks require one complete compound with consistent mask and paint roles.');
    }
    for (final AiNativeGroup group in groups.values.where((group) => group.start > compound.start && group.end < compound.end)) {
      final bool clipping = group.opening.operator == 'q';
      if (group.children.isEmpty || group.children.any((child) => clipping ? child is! AiNativePath : child is! AiNativeGroup)) {
        throw UnsupportedError('Compound masks require path-only clipping leaves and group-only ordinary branches.');
      }
    }
  }
  return result;
}
