part of 'package:aikit/src/model/ai_native_records.dart';

/// An explicit all-or-selected print choice within a host-declared page count.
///
/// Indices are zero-based. Null selects all; an empty selected list is invalid.
/// Artboard updates require the resulting native count. Printed-page updates
/// require the host's output count, independent of artboards and PDF pages.
final class AiNativePrintSelection {
  /// Number of items in the resulting artboard or printed-page sequence.
  final int count;

  /// Sorted immutable selected indices, or null for all items.
  final List<int>? indices;

  /// Freezes a complete print choice without inferring an empty selection.
  factory AiNativePrintSelection({required int count, required List<int>? indices}) {
    if (count < 1 || count > 9007199254740991 || indices != null && (indices.isEmpty || indices.any((index) => index < 0 || index >= count) || indices.toSet().length != indices.length)) {
      throw ArgumentError('Print selections require a positive portable count and distinct in-range indices, or null for all.');
    }
    final List<int>? sorted = indices == null ? null : (indices.toList()..sort());
    return AiNativePrintSelection._(count: count, indices: sorted == null ? null : List.unmodifiable(sorted));
  }

  /// Retains a validated complete selection.
  const AiNativePrintSelection._({required this.count, required this.indices});
}

/// Source-owned print choices with independent artboard and printed-page ranges.
///
/// Empty stored ranges are distinct from absent fields and from the all flags.
/// A stored range may be dormant while its all flag is true. Reading never
/// normalizes source bytes or derives physical printed pages from artboards.
final class AiNativePrintJob {
  /// Immutable source containing the print-job record.
  final AiNativeRecords records;

  /// Native Document owning these print settings.
  final AiNativeContainer document;

  /// Existing AI11 Print JobInfo Dict, including unrelated saved settings.
  final AiNativeContainer record;

  /// Number of artboards in this source snapshot.
  final int artboardCount;

  /// Binds an existing job without inventing absent fields.
  const AiNativePrintJob._({required this.records, required this.document, required this.record, required this.artboardCount});

  /// Saved all-artboards flag, or null when absent.
  bool? get allArtboards => _nativePrintFlag(record['/attributes/job.printallartboards']);

  /// Saved all-printed-pages flag, or null when absent.
  bool? get allPages => _nativePrintFlag(record['/attributes/job.printall']);

  /// Exact decoded native artboard-range bytes, including any encoding marker.
  Uint8List? get artboardRangeBytes => record['/attributes/job.artboardrange']?.stringBytes;

  /// Exact decoded printed-page range bytes, independent of PDF page numbers.
  Uint8List? get pageRangeBytes => record['/attributes/job.pagerange']?.stringBytes;

  /// Stored zero-based artboard selection, empty for an empty range, null if absent.
  List<int>? get artboardIndices => _nativePrintIndices(record['/attributes/job.artboardrange'], artboardCount, records.program.limits);

  /// Reads a stored printed-page selection using the host's actual output count.
  List<int>? pageIndices({required int pageCount}) {
    if (pageCount < 1 || pageCount > 9007199254740991) {
      throw ArgumentError.value(pageCount, 'pageCount');
    }
    return _nativePrintIndices(record['/attributes/job.pagerange'], pageCount, records.program.limits);
  }
}
