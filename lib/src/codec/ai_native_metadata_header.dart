part of 'ai_native_data.dart';

/// Compares preserved byte sequences without decoding or normalizing text.
bool _nativeBytesEqual(List<int> first, List<int> second) => first.length == second.length && first.indexed.every((entry) => entry.$2 == second[entry.$1]);

/// Reads complete initial comment lines without parsing native artwork operators.
List<String> _nativeHeaderLines(List<int> program, AiNativeLimits limits) {
  final List<String> lines = [];
  int position = 0;
  while (position < program.length) {
    if (lines.length >= limits.maxTokens) {
      throw const FormatException('Native metadata headers exceed the inspection limit.');
    }
    final int start = position;
    while (position < program.length && program[position] != 10 && program[position] != 13) {
      if (position >= limits.maxDecodedBytes) {
        throw const FormatException('Native metadata headers exceed the inspection limit.');
      }
      position++;
    }
    final int end = position;
    if (position < program.length && program[position++] == 13 && position < program.length && program[position] == 10) {
      position++;
    }
    if (position > limits.maxDecodedBytes) {
      throw const FormatException('Native metadata headers exceed the inspection limit.');
    }
    final String content = latin1.decode(program.sublist(start, end));
    if (lines.isEmpty ? !content.startsWith('%!PS-Adobe-') : !content.startsWith('%') && content.trim().isNotEmpty) {
      throw UnsupportedError('Native metadata synchronization requires a complete initial comment header.');
    }
    lines.add(latin1.decode(program.sublist(start, position)));
    if (content.trimRight() == '%%EndComments') {
      return lines;
    }
  }
  throw UnsupportedError('Native metadata synchronization requires an initial EndComments marker.');
}

/// Retains the observed CC cache profile omitting font declarations and continuations.
Uint8List _nativeHeaderBytes(List<String> lines, {required bool omitFonts}) {
  final BytesBuilder result = BytesBuilder(copy: false);
  bool skip = false;
  for (final String line in lines) {
    if (!line.startsWith('%%+')) {
      skip = omitFonts && (line.startsWith('%%DocumentFonts:') || line.startsWith('%%DocumentNeededFonts:'));
    }
    if (!skip) {
      result.add(latin1.encode(line));
    }
  }
  return result.takeBytes();
}

/// Plans cache replacements before touching the local PDF graph.
///
/// Only two exact source profiles are qualified: the complete initial header,
/// and that header without font declarations. Unchanged headers preserve every
/// existing cache, including unknown data. Native drawing is never interpreted.
List<Map<int?, PdfStream>> _nativeMetadataHeaders(List<AiNativeReplacement> replacements, List<_NativeOwner> owners, PdfDocument pdf, AiNativeLimits limits) {
  final List<Map<int?, PdfStream>> result = [];
  int encodedBytes = 0;
  int decodedBytes = 0;
  int outputBytes = 0;
  for (final AiNativeReplacement replacement in replacements) {
    final Map<int?, PdfStream> updates = {};
    result.add(updates);
    final List<_NativeOwner> selected = owners
        .where((owner) => replacement.source.owners.contains(owner.pageIndex) && owner.data['AIMetaData'] != null && owner.data['AIMetaData'] is! PdfNull)
        .toList();
    if (selected.isEmpty || _nativeBytesEqual(replacement.source.bytes, replacement.program)) {
      continue;
    }
    final List<String> original = _nativeHeaderLines(replacement.source.bytes, limits);
    final List<String> changed = _nativeHeaderLines(replacement.program, limits);
    final Uint8List full = _nativeHeaderBytes(original, omitFonts: false);
    final Uint8List nextFull = _nativeHeaderBytes(changed, omitFonts: false);
    if (_nativeBytesEqual(full, nextFull)) {
      continue;
    }
    final Uint8List filtered = _nativeHeaderBytes(original, omitFonts: true);
    final Uint8List nextFiltered = _nativeHeaderBytes(changed, omitFonts: true);
    final Map<PdfStream, PdfStream?> shared = HashMap.identity();
    for (final _NativeOwner owner in selected) {
      final PdfValue cache = pdf.resolve(owner.data['AIMetaData']!);
      if (cache is! PdfStream) {
        throw UnsupportedError('Changed native headers require a qualified AIMetaData stream.');
      }
      if (shared.containsKey(cache)) {
        if (shared[cache] case final PdfStream updated) {
          updates[owner.pageIndex] = updated;
        }
        continue;
      }
      encodedBytes += cache.data.length;
      if (encodedBytes > limits.maxEncodedBytes || decodedBytes >= limits.maxDecodedBytes) {
        throw const FormatException('Native metadata caches exceed the aggregate input limit.');
      }
      final Uint8List bytes = PdfFilters.decode(
        cache,
        resolve: pdf.resolve,
        limits: PdfLimits(maxStreamBytes: limits.maxDecodedBytes - decodedBytes),
      );
      decodedBytes += bytes.length;
      final bool omitFonts;
      if (_nativeBytesEqual(bytes, filtered)) {
        if (_nativeBytesEqual(full, filtered) && !_nativeBytesEqual(nextFull, nextFiltered)) {
          throw UnsupportedError('AIMetaData font inclusion is ambiguous when the original header declares no fonts.');
        }
        omitFonts = true;
      } else if (_nativeBytesEqual(bytes, full)) {
        omitFonts = false;
      } else {
        throw UnsupportedError('Changed native headers require an exact full or font-filtered AIMetaData source profile.');
      }
      final Uint8List output = omitFonts ? nextFiltered : nextFull;
      outputBytes += output.length;
      if (outputBytes > limits.maxDecodedBytes || outputBytes > limits.maxEncodedBytes) {
        throw const FormatException('Native metadata caches exceed the aggregate output limit.');
      }
      if (_nativeBytesEqual(bytes, output)) {
        shared[cache] = null;
        continue;
      }
      final PdfStream updated = PdfStream(
        dictionary: cache.dictionary.copyWith(remove: {'Filter', 'DecodeParms', 'Length'}),
        data: output,
      );
      shared[cache] = updated;
      updates[owner.pageIndex] = updated;
    }
  }
  return result;
}
