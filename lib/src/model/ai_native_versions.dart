part of 'package:aikit/src/model/ai_native_records.dart';

/// Saved side of a native version condition, without selecting a target version.
enum AiNativeVersionBranch {
  /// Content following the greater-than condition.
  newer,

  /// Content following an explicit alternate marker.
  older,
}

/// One bounded native version condition retaining both source representations.
final class AiNativeVersionBlock extends AiNativeItem {
  /// Original opening comment, including the producer marker and version pair.
  final AiToken opening;

  /// Explicit alternate marker, absent for a newer-only addition.
  final AiToken? alternate;

  /// Matching closing comment.
  final AiToken closing;

  /// Marker family such as AI17; unknown families are retained as syntax.
  final String family;

  /// Major version in the saved greater-than condition.
  final int major;

  /// Minor version in the saved greater-than condition.
  final int minor;

  /// Captures checked boundaries without executing or dropping either branch.
  AiNativeVersionBlock._({required this.opening, required this.alternate, required this.closing, required this.family, required this.major, required this.minor})
    : super(start: opening.start, end: closing.end);

  /// Exact newer-content interval, excluding its surrounding comments.
  ({int start, int end}) get newerRange => (start: opening.end, end: alternate?.start ?? closing.start);

  /// Exact older-content interval, or null when no alternate was stored.
  ({int start, int end})? get olderRange => alternate == null ? null : (start: alternate!.end, end: closing.start);
}

/// Ownership of a source interval by one side of a version block.
final class AiNativeVersionMembership {
  /// Source condition enclosing the interval.
  final AiNativeVersionBlock block;

  /// Saved branch containing the complete interval.
  final AiNativeVersionBranch branch;

  /// Records membership without treating an alternate as a separate live object.
  const AiNativeVersionMembership._({required this.block, required this.branch});
}

/// Complete lexical version boundaries in one immutable native source.
final class AiNativeVersions {
  /// Source owning all comments and byte intervals.
  final AiNativeRecords records;

  /// Blocks in opening-source order, including nested and empty branches.
  final List<AiNativeVersionBlock> blocks;

  /// Reads bounded version syntax outside executable and opaque payloads.
  factory AiNativeVersions.decode({required AiNativeRecords records}) => AiNativeVersions._(records: records, blocks: _nativeVersionBlocks(records));

  /// Freezes a checked source inventory.
  AiNativeVersions._({required this.records, required List<AiNativeVersionBlock> blocks}) : blocks = List.unmodifiable(blocks);

  /// Finds complete branch owners without guessing across a version boundary.
  ///
  /// A span enclosing an entire block has no membership in that block. A span
  /// cutting one of its boundaries rejects; it cannot be moved independently.
  List<AiNativeVersionMembership> memberships({required int start, required int end}) {
    if (start < 0 || end <= start || end > records.program.bytes.length) {
      throw ArgumentError('Version membership requires a nonempty owned source interval.');
    }
    final List<AiNativeVersionMembership> result = [];
    for (final AiNativeVersionBlock block in blocks) {
      if (end <= block.start || start >= block.end || start <= block.start && end >= block.end) {
        continue;
      }
      final ({int start, int end}) newer = block.newerRange;
      final ({int start, int end})? older = block.olderRange;
      if (start >= newer.start && end <= newer.end) {
        result.add(AiNativeVersionMembership._(block: block, branch: .newer));
      } else if (older != null && start >= older.start && end <= older.end) {
        result.add(AiNativeVersionMembership._(block: block, branch: .older));
      } else {
        throw UnsupportedError('The source interval crosses a native version boundary.');
      }
    }
    return List.unmodifiable(result);
  }
}
