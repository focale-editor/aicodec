import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aicodec/src/codec/ai_postscript.dart';
import 'package:aicodec/src/model/ai_document.dart';
import 'package:pdfcore/pdfcore.dart';

/// Resource policy for AI containers and legacy DSC inspection.
final class AiLimits {
  /// Maximum complete AI file size and PDF parsing policy.
  final PdfLimits pdf;

  /// Maximum individual DSC comment length.
  final int maxCommentBytes;

  /// Maximum number of retained DSC comments.
  final int maxComments;

  /// Creates bounded AI decoding defaults.
  const AiLimits({this.pdf = const PdfLimits(), this.maxCommentBytes = 1024 * 1024, this.maxComments = 100000});
}

/// Reads PDF-compatible and legacy PostScript Illustrator containers.
final class AiCodec extends Codec<AiDocument, List<int>> {
  /// Input and output resource policy.
  final AiLimits limits;

  /// Whether a generic PDF or EPS may be used without Illustrator markers.
  final bool allowGeneric;

  /// Creates a codec requiring Illustrator provenance by default.
  const AiCodec({this.limits = const AiLimits(), this.allowGeneric = false});

  @override
  AiDecoder get decoder => AiDecoder(limits: limits, allowGeneric: allowGeneric);

  @override
  AiEncoder get encoder => AiEncoder(limits: limits);

  @override
  Uint8List encode(AiDocument input) => encoder.convert(input);
}

/// Detects the physical container before parsing its document data.
final class AiDecoder extends Converter<List<int>, AiDocument> {
  /// Parsing resource policy.
  final AiLimits limits;

  /// Whether files without Illustrator authoring markers are accepted.
  final bool allowGeneric;

  /// Creates a bounded container decoder.
  const AiDecoder({this.limits = const AiLimits(), this.allowGeneric = false});

  @override
  AiDocument convert(List<int> input) {
    limits.pdf.validate();
    if (limits.maxCommentBytes <= 0 || limits.maxComments <= 0) {
      throw ArgumentError('AI comment limits must be positive.');
    }
    if (input.length > limits.pdf.maxFileBytes || input.length < 8) {
      throw const FormatException('Invalid or excessive Illustrator file size.');
    }
    if (input.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Input contains values outside the byte range.');
    }
    final Uint8List bytes = Uint8List.fromList(input);
    if (latin1.decode(bytes.sublist(0, 5)) == '%PDF-') {
      final PdfDocument pdf = PdfDecoder(limits: limits.pdf).convert(bytes);
      final AiPdfDocument document = AiPdfDocument(pdf: pdf);
      if (!allowGeneric && !_illustratorPdf(pdf, document)) {
        throw const FormatException('PDF has no Illustrator authoring markers.');
      }
      return document;
    }
    int start = 0;
    int length = bytes.length;
    if (bytes[0] == 0xc5 && bytes[1] == 0xd0 && bytes[2] == 0xd3 && bytes[3] == 0xc6) {
      if (bytes.length < 30) {
        throw const FormatException('Truncated binary EPS header.');
      }
      final ByteData header = ByteData.sublistView(bytes);
      start = header.getUint32(4, Endian.little);
      length = header.getUint32(8, Endian.little);
      if (start < 30 || length < 8 || start + length > bytes.length) {
        throw const FormatException('Invalid binary EPS PostScript section.');
      }
      for (final int offset in [12, 20]) {
        final int previewStart = header.getUint32(offset, Endian.little);
        final int previewLength = header.getUint32(offset + 4, Endian.little);
        if (previewLength > 0 && (previewStart < 30 || previewStart + previewLength > bytes.length)) {
          throw const FormatException('Invalid binary EPS preview section.');
        }
      }
    }
    final Uint8List program = Uint8List.sublistView(bytes, start, start + length);
    if (!latin1.decode(program.sublist(0, math.min(32, program.length))).startsWith('%!PS-Adobe-')) {
      throw const FormatException('Unsupported Illustrator container signature.');
    }
    final ({Map<String, List<String>> comments, AiDscIssue? issue}) inspection = _comments(program, limits);
    final AiPostScriptDocument document = AiPostScriptDocument(bytes: bytes, postScriptOffset: start, postScriptLength: length, comments: inspection.comments, dscIssue: inspection.issue);
    if (!allowGeneric && !(document.creator?.contains('Illustrator') ?? false) && !document.comments.keys.any((key) => RegExp(r'^AI\d+_').hasMatch(key))) {
      throw const FormatException('PostScript has no Illustrator authoring markers.');
    }
    return document;
  }
}

/// Writes PDF graphs or returns exact legacy program bytes.
final class AiEncoder extends Converter<AiDocument, List<int>> {
  /// Output resource policy.
  final AiLimits limits;

  /// Creates an AI container encoder.
  const AiEncoder({this.limits = const AiLimits()});

  @override
  Uint8List convert(AiDocument input) {
    limits.pdf.validate();
    return switch (input) {
      AiPdfDocument(:final pdf) => PdfEncoder(limits: limits.pdf).convert(pdf),
      AiPostScriptDocument(:final bytes) => bytes.length > limits.pdf.maxFileBytes ? throw const FormatException('AI output exceeds the byte limit.') : Uint8List.fromList(bytes),
    };
  }
}

/// Checks documented Illustrator markers without treating arbitrary PDF as AI.
bool _illustratorPdf(PdfDocument pdf, AiPdfDocument document) {
  if (document.privateBlocks.isNotEmpty) {
    return true;
  }
  final PdfValue? info = pdf.trailer['Info'];
  if (info != null && info is! PdfNull) {
    final PdfDictionary metadata = pdf.dictionary(info);
    for (final String key in ['Creator', 'Producer']) {
      final PdfValue? value = metadata[key];
      if (value != null && pdf.resolve(value) is PdfString) {
        if ((pdf.resolve(value) as PdfString).text.contains('Illustrator')) {
          return true;
        }
      }
    }
  }
  return false;
}

/// Reads top-level DSC comments while skipping binary data and nested EPS files.
({Map<String, List<String>> comments, AiDscIssue? issue}) _comments(Uint8List bytes, AiLimits limits) {
  final Map<String, List<String>> result = {};
  int position = 0;
  int nested = 0;
  int count = 0;
  int? rasterStart;
  String? lastKey;
  while (position < bytes.length) {
    final int start = position;
    while (position < bytes.length && bytes[position] != 10 && bytes[position] != 13) {
      position++;
    }
    final int end = position;
    if (position < bytes.length && bytes[position++] == 13 && position < bytes.length && bytes[position] == 10) {
      position++;
    }
    if (end == start || bytes[start] != 37) {
      lastKey = null;
      continue;
    }
    if (end - start > limits.maxCommentBytes) {
      throw const FormatException('AI comment exceeds the byte limit.');
    }
    final String line = latin1.decode(Uint8List.sublistView(bytes, start, end));
    if (const {'%AI26_BeginPlacedObjectPreview', '%_%AI26_BeginPlacedObjectPreview'}.contains(line)) {
      try {
        position = readAiPlacedPreview(bytes: bytes, start: position, privateData: line.startsWith('%_')).end;
      } on FormatException catch (error) {
        return (comments: result, issue: AiDscIssue(offset: start, message: error.message));
      }
      lastKey = null;
      continue;
    }
    if (const {'%AI5_BeginRaster', '%_%AI5_BeginRaster'}.contains(line)) {
      if (rasterStart != null) {
        return (comments: result, issue: AiDscIssue(offset: start, message: 'Nested native raster section.'));
      }
      rasterStart = position;
      lastKey = null;
      continue;
    }
    if (const {'%AI5_EndRaster', '%_%AI5_EndRaster'}.contains(line)) {
      rasterStart = null;
    }
    final bool privateData = rasterStart != null && line.startsWith('%_%%BeginData:');
    if (line.startsWith('%%BeginBinary:') || line.startsWith('%%BeginData:') || privateData) {
      final List<String> fields = line.substring(line.indexOf(':') + 1).trim().split(RegExp(r'\s+'));
      final int? size = int.tryParse(fields.first);
      if (size == null || size < 0 || size > bytes.length) {
        throw const FormatException('Invalid AI DSC data-block size.');
      }
      if (rasterStart != null && (line.startsWith('%%BeginData:') || privateData) && fields.last.toLowerCase() != 'lines') {
        try {
          final List<AiToken> header = AiPostScript.tokenize(
            Uint8List.sublistView(bytes, rasterStart, start),
            maxBytes: limits.maxCommentBytes,
            maxTokens: limits.pdf.maxObjects,
            maxDepth: limits.pdf.maxDepth,
          );
          final ({int samples, int end})? image = readAiRasterData(
            bytes: bytes,
            start: position,
            declared: size,
            tokens: [
              ...header,
              AiToken(kind: .comment, start: start, end: end, lexeme: line),
            ],
            privateData: privateData,
          );
          if (image != null) {
            position = image.end;
            lastKey = null;
            continue;
          }
          return (comments: result, issue: AiDscIssue(offset: start, message: 'Native raster data requires a qualified binary XI invocation.'));
        } on FormatException catch (error) {
          return (comments: result, issue: AiDscIssue(offset: start, message: error.message));
        } on UnsupportedError catch (error) {
          return (comments: result, issue: AiDscIssue(offset: start, message: error.message ?? 'Unsupported native raster boundary.'));
        }
      }
      if (fields.last.toLowerCase() == 'lines') {
        for (int index = 0; index < size; index++) {
          if (position >= bytes.length) {
            throw const FormatException('Truncated AI DSC data lines.');
          }
          while (position < bytes.length && bytes[position] != 10 && bytes[position] != 13) {
            position++;
          }
          if (position < bytes.length && bytes[position++] == 13 && position < bytes.length && bytes[position] == 10) {
            position++;
          }
        }
      } else {
        if (position + size > bytes.length) {
          throw const FormatException('Truncated AI DSC binary data.');
        }
        position += size;
      }
      lastKey = null;
      continue;
    }
    if (line.startsWith('%%BeginDocument')) {
      if (++nested > limits.pdf.maxDepth) {
        throw const FormatException('AI embedded document nesting exceeds the limit.');
      }
      continue;
    }
    if (line == '%%EndDocument') {
      if (--nested < 0) {
        throw const FormatException('Unmatched AI EndDocument.');
      }
      continue;
    }
    if (nested != 0) {
      continue;
    }
    if (line.startsWith('%%+') && lastKey != null) {
      final List<String> values = result[lastKey]!;
      final String joined = '${values.last}\n${line.substring(3).trim()}';
      if (joined.length > limits.maxCommentBytes) {
        throw const FormatException('AI continued comment exceeds the limit.');
      }
      values[values.length - 1] = joined;
      continue;
    }
    final RegExpMatch? match = RegExp(r'^%%?([A-Za-z][A-Za-z0-9_]*):\s*(.*)$').firstMatch(line);
    if (match != null) {
      if (++count > limits.maxComments) {
        throw const FormatException('AI comment count exceeds the limit.');
      }
      lastKey = match[1]!;
      result.putIfAbsent(lastKey, () => []).add(match[2]!);
    } else {
      lastKey = null;
    }
  }
  if (nested != 0) {
    throw const FormatException('Unterminated AI embedded document.');
  }
  return (comments: result, issue: null);
}
