part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Source-backed commands and metadata inside one native `/Art` record.
final class AiNativeArt {
  /// Owning native container, including unrecognized metadata.
  final AiNativeContainer record;

  /// Commands and nested records in their original order.
  final List<AiNativeItem> items;

  /// Reads bounded command syntax without executing transforms or plug-ins.
  factory AiNativeArt.decode({required AiNativeRecords records, required AiNativeContainer record}) {
    if (!records._ownedContainers.contains(record) || record.type != 'Art') {
      throw ArgumentError('Expected an Art record owned by this native snapshot.');
    }
    final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
    final _NativeRecordProjection projection = records._projection;
    final List<AiNativeItem> items = [];
    for (final AiNativeEntry entry in record.entries) {
      if (entry.key != null || entry.isQualifier) {
        throw const FormatException('Expected unkeyed native Art commands.');
      }
      for (final AiNativeItem item in entry.items) {
        if (item is AiNativeContainer) {
          reader.finish();
          items.add(item);
        } else if (item is AiNativeToken) {
          final AiNativeInstruction? instruction = reader.add(item.token, isPrivate: projection.isPrivate(item.start));
          if (instruction != null) {
            items.add(instruction);
          }
        } else {
          throw const FormatException('Unexpected native Art item.');
        }
      }
    }
    reader.finish();
    return AiNativeArt._(record: record, items: items);
  }

  /// Owns an immutable syntax view while preserving original token positions.
  AiNativeArt._({required this.record, required List<AiNativeItem> items}) : items = List.unmodifiable(items);
}
