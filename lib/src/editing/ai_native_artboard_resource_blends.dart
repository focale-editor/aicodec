part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Retained endpoint annotations whose identities belong to one local group.
const Set<String> _artboardResourceBlendFields = {'ShapeBlendPathType', 'ShapeBlendPathID', 'ShapeBlendMatchToBefore', 'ShapeBlendMatchToAfter'};

/// Qualifies the observed paired key-path annotations without generating blends.
void _artboardResourceBlendPaths(AiNativeDrawing drawing) {
  final Set<AiNativeContainer> records = drawing.items.whereType<AiNativeContainer>().where((record) => record.entries.any((field) => _artboardResourceBlendFields.contains(field.key))).toSet();
  if (records.isEmpty) {
    return;
  }
  final Map<AiNativeInstruction, AiNativePath> paths = {for (final AiNativePath path in drawing.paths) path.paint: path};
  final Map<AiNativeInstruction, AiNativeGroup> openings = {for (final AiNativeGroup group in drawing.groups) group.opening: group};
  final Set<AiNativeInstruction> closings = {for (final AiNativeGroup group in drawing.groups) group.closing};
  final List<AiNativeGroup> parents = [];
  final Map<AiNativeGroup, Map<String, AiNativePath>> pairs = {};
  for (int index = 0; index < drawing.items.length; index++) {
    final AiNativeItem item = drawing.items[index];
    if (openings[item] case final AiNativeGroup group) {
      parents.add(group);
    } else if (closings.contains(item)) {
      if (parents.isEmpty || !identical(parents.last.closing, item)) {
        throw const FormatException('Retained blend annotations cross a group boundary.');
      }
      parents.removeLast();
    } else if (records.contains(item)) {
      final AiNativeContainer record = item as AiNativeContainer;
      final AiNativePath? path = index == 0 ? null : paths[drawing.items[index - 1]];
      if (path == null || parents.isEmpty || parents.last.opening.operator != 'u' || !parents.last.children.contains(path)) {
        throw UnsupportedError('Retained blend annotations require directly owned paths in an ordinary group.');
      }
      final String? identity = record['ShapeBlendPathID']?.text();
      if (record['ShapeBlendPathType']?.text() != 'K' ||
          !const {'A', 'B'}.contains(identity) ||
          record[identity == 'A' ? 'ShapeBlendMatchToAfter' : 'ShapeBlendMatchToBefore']?.text() != 'ALL' ||
          record[identity == 'A' ? 'ShapeBlendMatchToBefore' : 'ShapeBlendMatchToAfter'] != null) {
        throw UnsupportedError('Retained blend annotations require the qualified A/B key-path match layout.');
      }
      final Map<String, AiNativePath> pair = pairs.putIfAbsent(parents.last, () => {});
      if (pair.containsKey(identity)) {
        throw UnsupportedError('Retained blend key-path identities must be unique within their group.');
      }
      pair[identity!] = path;
    }
  }
  for (final Map<String, AiNativePath> pair in pairs.values) {
    if (pair.length != 2 || pair['A']!.isPrivate != pair['B']!.isPrivate) {
      throw UnsupportedError('Retained blend groups require both key paths in the same representation.');
    }
  }
}
