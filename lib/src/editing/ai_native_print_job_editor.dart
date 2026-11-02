part of 'package:aicodec/src/model/ai_native_records.dart';

/// Binds the selected Document's existing print-job dictionary only.
AiNativePrintJob? _nativeArtboardPrintJob(AiNativeArtboards model) {
  final AiNativeEntry? entry = model.document['NotRecorded']?.container?['AI11 Print JobInfo Dict'];
  if (entry == null) {
    return null;
  }
  final AiNativeContainer record = _referenceRecord(entry, 'Dictionary');
  return AiNativePrintJob._(records: model.records, document: model.document, record: record, artboardCount: model.artboards.length);
}

/// Reads an explicit integer boolean without treating malformed flags as false.
bool? _nativePrintFlag(AiNativeEntry? entry) {
  if (entry == null) {
    return null;
  }
  if (entry.type != 'Int' || entry.number != 0 && entry.number != 1) {
    throw const FormatException('Native print flags require zero or one integer values.');
  }
  return entry.number == 1;
}

/// Decodes ASCII range syntax, retaining explicit UTF-16 byte order when present.
({String text, Endian? encoding}) _nativePrintText(AiNativeEntry entry) {
  final Uint8List? bytes = entry.stringBytes;
  if (!const {'String', 'UnicodeString'}.contains(entry.type) || bytes == null) {
    throw const FormatException('Native print ranges require typed strings.');
  }
  final Endian? encoding = bytes.length >= 2 && bytes[0] == 254 && bytes[1] == 255
      ? Endian.big
      : bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 254
      ? Endian.little
      : null;
  final List<int> characters;
  if (encoding == null) {
    characters = bytes;
  } else {
    if (bytes.length.isOdd) {
      throw const FormatException('A native UTF-16 print range has an incomplete code unit.');
    }
    final ByteData data = ByteData.sublistView(bytes);
    characters = [for (int offset = 2; offset < bytes.length; offset += 2) data.getUint16(offset, encoding)];
  }
  if (characters.any((character) => character == 0 || character > 127)) {
    throw UnsupportedError('Native print ranges require ASCII syntax or explicitly marked UTF-16.');
  }
  return (text: String.fromCharCodes(characters), encoding: encoding);
}

/// Expands qualified one-based ranges under a separate aggregate selection bound.
List<int>? _nativePrintIndices(AiNativeEntry? entry, int count, AiNativeLimits limits) {
  if (entry == null) {
    return null;
  }
  final String text = _nativePrintText(entry).text.trim();
  if (text.isEmpty) {
    return const [];
  }
  final Set<int> indices = {};
  final RegExp syntax = RegExp(r'^\s*([0-9]+)\s*(?:-\s*([0-9]*)\s*)?$');
  int inspected = 0;
  int offset = 0;
  while (offset <= text.length) {
    final int separator = text.indexOf(',', offset);
    final int end = separator < 0 ? text.length : separator;
    final RegExpMatch? match = syntax.firstMatch(text.substring(offset, end));
    offset = end + 1;
    if (match == null) {
      throw UnsupportedError('Unqualified native print-range syntax.');
    }
    final int? first = int.tryParse(match[1]!);
    final String? lastText = match[2];
    final int? last = lastText == null
        ? first
        : lastText.isEmpty
        ? count
        : int.tryParse(lastText);
    if (first == null || last == null || first < 1 || last < first || last > count) {
      throw const FormatException('Native print-range endpoints are outside their declared sequence.');
    }
    inspected += last - first + 1;
    if (inspected > limits.maxTokens) {
      throw const AiLimitException(message: 'Native print selections exceed the inspection limit.');
    }
    for (int index = first - 1; index < last; index++) {
      indices.add(index);
    }
  }
  return List.unmodifiable(indices.toList()..sort());
}

/// Emits compact one-based ranges in the resulting document's natural order.
String _nativePrintRangeText(List<int> indices) {
  final List<String> parts = [];
  int position = 0;
  while (position < indices.length) {
    final int first = indices[position++];
    int last = first;
    while (position < indices.length && indices[position] == last + 1) {
      last = indices[position++];
    }
    parts.add(first == last ? '${first + 1}' : '${first + 1}-${last + 1}');
  }
  return parts.join(',');
}

/// Replaces only string values, retaining source type, encoding and fragment trivia.
List<AiSourceEdit> _nativePrintStringEdits(AiNativeEntry entry, String text, AiNativeLimits limits) {
  final ({String text, Endian? encoding}) original = _nativePrintText(entry);
  if (original.text == text) {
    return const [];
  }
  final List<int> bytes = original.encoding == null
      ? text.codeUnits
      : [
          if (original.encoding == Endian.big) ...[254, 255] else ...[255, 254],
          for (final int character in text.codeUnits)
            if (original.encoding == Endian.big) ...[0, character] else ...[character, 0],
        ];
  final List<int> encoded = _nativeLiteralString(bytes, limits.maxDecodedBytes);
  return entry.items.isEmpty
      ? [
          AiSourceEdit(start: entry.typeToken!.start, end: entry.typeToken!.start, bytes: [...encoded, 32]),
        ]
      : [
          AiSourceEdit(start: entry.items.first.start, end: entry.items.first.end, bytes: encoded),
          for (final AiNativeItem item in entry.items.skip(1)) AiSourceEdit(start: item.start, end: item.end, bytes: []),
        ];
}

/// Remaps board identities and attaches explicitly supplied physical print choices.
List<AiSourceEdit> _nativeArtboardPrintEdits(
  AiNativeArtboards model, {
  required List<int?> order,
  required bool changed,
  required AiNativePrintSelection? artboardPrinting,
  required AiNativePrintSelection? pagePrinting,
}) {
  final AiNativePrintJob? job = model.printJob;
  if (job == null) {
    if (artboardPrinting != null || pagePrinting != null) {
      throw UnsupportedError('Print choices require an existing native print-job dictionary.');
    }
    return const [];
  }
  final AiNativeLimits limits = model.records.program.limits;
  final List<AiSourceEdit> edits = [];

  /// Updates an existing all flag and its range as one part of the native edit.
  void supplied(AiNativePrintSelection selection, String flagKey, String rangeKey) {
    final AiNativeEntry? flag = job.record[flagKey];
    final AiNativeEntry? range = job.record[rangeKey];
    if (flag == null || range == null) {
      throw UnsupportedError('Supplied print choices require existing flag and range fields.');
    }
    final bool all = selection.indices == null;
    if (_nativePrintFlag(flag) != all) {
      edits.add(AiSourceEdit(start: flag.items.single.start, end: flag.items.single.end, bytes: [if (all) 49 else 48]));
    }
    if ((selection.indices?.length ?? 0) > limits.maxTokens) {
      throw const AiLimitException(message: 'Supplied print choices exceed the inspection limit.');
    }
    edits.addAll(_nativePrintStringEdits(range, all ? '' : _nativePrintRangeText(selection.indices!), limits));
  }

  if (artboardPrinting != null) {
    if (artboardPrinting.count != order.length) {
      throw ArgumentError('The supplied print selection must use the resulting native artboard count.');
    }
    supplied(artboardPrinting, '/attributes/job.printallartboards', '/attributes/job.artboardrange');
  } else {
    final List<int>? original = job.artboardIndices;
    final bool? all = job.allArtboards;
    if (original != null && original.isNotEmpty) {
      final Set<int> selected = original.toSet();
      final List<int> mapped = [
        for (int index = 0; index < order.length; index++)
          if (selected.contains(order[index])) index,
      ];
      if (mapped.isEmpty && all != true) {
        throw UnsupportedError('Removing every printed artboard requires an explicit replacement print selection.');
      }
      if (mapped.length != original.length || mapped.indexed.any((entry) => entry.$2 != original[entry.$1])) {
        edits.addAll(_nativePrintStringEdits(job.record['/attributes/job.artboardrange']!, _nativePrintRangeText(mapped), limits));
      }
    }
  }
  if (pagePrinting != null) {
    supplied(pagePrinting, '/attributes/job.printall', '/attributes/job.pagerange');
  } else {
    _nativePrintFlag(job.record['/attributes/job.printall']);
    final AiNativeEntry? range = job.record['/attributes/job.pagerange'];
    if ((changed || edits.isNotEmpty) && range != null && _nativePrintText(range).text.trim().isNotEmpty) {
      throw UnsupportedError('Changed artboards require a host-supplied selection for the saved physical print-page range.');
    }
  }
  return edits;
}
