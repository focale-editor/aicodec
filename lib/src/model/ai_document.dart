import 'dart:typed_data';

import 'package:pdfcore/pdfcore.dart';

/// The two historically distinct Adobe Illustrator container families.
enum AiContainerKind {
  /// Illustrator 9 and later PDF-based containers.
  pdf,

  /// Illustrator's earlier PostScript-based interchange files.
  postscript,
}

/// A portable Illustrator container without a proprietary graphics interpreter.
sealed class AiDocument {
  /// Allows immutable format-specific document variants.
  const AiDocument();

  /// Physical container family, detected from bytes rather than extension.
  AiContainerKind get kind;
}

/// An Illustrator PDF object graph retaining native authoring resources.
///
/// PDF appearance and native Illustrator data are separate representations.
/// [forPdfInterchange] removes native authoring records when replacing PDF
/// artwork so Illustrator does not silently reopen a stale native drawing.
final class AiPdfDocument extends AiDocument {
  /// PDF graph, including page resources and optional Illustrator private data.
  final PdfDocument pdf;

  /// Creates a container from a coherent PDF graph.
  ///
  /// Callers retaining Illustrator private data are responsible for its
  /// consistency with page artwork. Use [AiPdfDocument.forPdfInterchange] for
  /// changed PDF content without synchronized proprietary authoring data.
  const AiPdfDocument({required this.pdf});

  /// Creates PDF interchange artwork with stale Illustrator records removed.
  factory AiPdfDocument.forPdfInterchange({required PdfDocument pdf}) {
    final Map<PdfReference, PdfValue> objects = {...pdf.objects};

    /// Removes native authoring links from direct values without following cycles.
    PdfValue cleanValue(PdfValue value, int depth) {
      if (depth > pdf.limits.maxDepth) {
        throw const FormatException('AI interchange dictionary nesting exceeds the limit.');
      }
      if (value is PdfArray) {
        return PdfArray(values: value.values.map((item) => cleanValue(item, depth + 1)));
      }
      if (value is PdfStream) {
        return PdfStream(dictionary: cleanValue(value.dictionary, depth + 1) as PdfDictionary, data: value.data);
      }
      if (value is! PdfDictionary) {
        return value;
      }
      PdfDictionary dictionary = value;
      final PdfValue? pieceInfo = dictionary['PieceInfo'];
      if (pieceInfo != null && pieceInfo is! PdfNull) {
        final PdfDictionary pieces = pdf.dictionary(pieceInfo).copyWith(remove: {'Illustrator'});
        dictionary = pieces.values.isEmpty ? dictionary.copyWith(remove: {'PieceInfo'}) : dictionary.copyWith(values: {'PieceInfo': pieces});
      }
      return PdfDictionary(values: {for (final MapEntry<String, PdfValue> entry in dictionary.values.entries) entry.key: cleanValue(entry.value, depth + 1)});
    }

    for (final MapEntry<PdfReference, PdfValue> entry in pdf.objects.entries) {
      objects[entry.key] = cleanValue(entry.value, 0);
    }
    return AiPdfDocument(pdf: pdf.copyWith(objects: objects));
  }

  @override
  AiContainerKind get kind => AiContainerKind.pdf;

  /// Ordered native-data blocks collected from all pages and the catalog.
  ///
  /// Data stays encoded as stored; PDF filters can be decoded separately with
  /// [PdfDocument.decodeStream]. Internal Illustrator compression (including
  /// Zstandard in recent versions) is decoded separately by `AiNativeData`.
  List<AiPrivateBlock> get privateBlocks {
    final List<AiPrivateBlock> blocks = [];
    final Set<PdfReference> seen = {};
    final List<PdfDictionary> owners = [pdf.catalog, ...pdf.pages.map((page) => page.dictionary)];
    for (int owner = 0; owner < owners.length; owner++) {
      final PdfValue? piecesValue = owners[owner]['PieceInfo'];
      if (piecesValue == null || piecesValue is PdfNull) {
        continue;
      }
      final PdfValue? illustratorValue = pdf.dictionary(piecesValue)['Illustrator'];
      if (illustratorValue == null || illustratorValue is PdfNull) {
        continue;
      }
      final PdfValue? privateValue = pdf.dictionary(illustratorValue)['Private'];
      if (privateValue == null || privateValue is PdfNull) {
        continue;
      }
      final PdfDictionary data = pdf.dictionary(privateValue);
      final List<({int number, PdfValue value})> entries = [];
      for (final MapEntry<String, PdfValue> entry in data.values.entries) {
        final RegExpMatch? match = RegExp(r'^(?:AIPrivateData|AIPDFPrivateData)(\d+)$').firstMatch(entry.key);
        if (match != null) {
          final int? number = int.tryParse(match[1]!);
          if (number == null || number <= 0) {
            throw const FormatException('Invalid Illustrator private-data block number.');
          }
          entries.add((number: number, value: entry.value));
        }
      }
      entries.sort((a, b) => a.number.compareTo(b.number));
      for (final ({int number, PdfValue value}) entry in entries) {
        if (entry.value is PdfReference && !seen.add(entry.value as PdfReference)) {
          continue;
        }
        final PdfValue stream = pdf.resolve(entry.value);
        if (stream is! PdfStream) {
          throw const FormatException('Illustrator private-data block must be a PDF stream.');
        }
        blocks.add(AiPrivateBlock(pageIndex: owner == 0 ? null : owner - 1, number: entry.number, stream: stream));
      }
    }
    return List.unmodifiable(blocks);
  }
}

/// One native Illustrator authoring block in a PDF container.
final class AiPrivateBlock {
  /// Zero-based owning page, or null for catalog-level data.
  final int? pageIndex;

  /// Numeric suffix of AIPrivateData, sorted numerically rather than lexically.
  final int number;

  /// Encoded payload and PDF filter dictionary.
  final PdfStream stream;

  /// Creates a native-data view without interpreting proprietary operators.
  const AiPrivateBlock({required this.pageIndex, required this.number, required this.stream});
}

/// A preserved legacy Illustrator PostScript program and its DSC metadata.
///
/// The program is never executed. Encoding retains every source byte, including
/// binary blocks and platform EPS previews. Metadata does not assert that the
/// contained PostScript program renders successfully.
final class AiPostScriptDocument extends AiDocument {
  /// Owned complete source container.
  final Uint8List _bytes;

  /// Byte offset at which the PostScript program starts.
  final int postScriptOffset;

  /// Length of the PostScript section, excluding optional EPS previews.
  final int postScriptLength;

  /// Top-level DSC comments, preserving repeated declarations.
  final Map<String, List<String>> comments;

  /// Creates a snapshot with metadata already extracted by the decoder.
  AiPostScriptDocument({required List<int> bytes, required this.postScriptOffset, required this.postScriptLength, required Map<String, List<String>> comments})
    : _bytes = Uint8List.fromList(bytes),
      comments = Map.unmodifiable(comments.map((key, value) => MapEntry(key, List<String>.unmodifiable(value)))) {
    if (postScriptOffset < 0 || postScriptLength < 0 || postScriptOffset + postScriptLength > _bytes.length) {
      throw const FormatException('Invalid Illustrator PostScript section bounds.');
    }
  }

  @override
  AiContainerKind get kind => AiContainerKind.postscript;

  /// Exact source bytes for lossless container preservation.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  /// Read-only PostScript section, excluding an EPS preview envelope.
  Uint8List get postScriptBytes => Uint8List.sublistView(_bytes, postScriptOffset, postScriptOffset + postScriptLength).asUnmodifiableView();

  /// Last declared title, including a trailer replacement for `(atend)`.
  String? get title => _comment('Title');

  /// Producer recorded by the top-level DSC header.
  String? get creator => _comment('Creator');

  /// Parsed high-resolution bounds, falling back to integer BoundingBox.
  AiBoundingBox? get boundingBox {
    final String? value = _comment('HiResBoundingBox') ?? _comment('BoundingBox');
    return value == null ? null : AiBoundingBox.parse(value: value);
  }

  /// Finds the final concrete declaration of a DSC property.
  String? _comment(String name) {
    final List<String>? values = comments[name];
    if (values != null) {
      for (final String value in values.reversed) {
        if (value != '(atend)') {
          return value;
        }
      }
    }
    return null;
  }
}

/// Bounding rectangle in PostScript points, preserving the source origin.
final class AiBoundingBox {
  /// Left edge in source coordinates.
  final double left;

  /// Bottom edge in source coordinates.
  final double bottom;

  /// Right edge in source coordinates.
  final double right;

  /// Top edge in source coordinates.
  final double top;

  /// Creates a finite ordered rectangle.
  AiBoundingBox({required this.left, required this.bottom, required this.right, required this.top}) {
    if (![left, bottom, right, top].every((value) => value.isFinite) || right < left || top < bottom) {
      throw const FormatException('Invalid Illustrator bounding box.');
    }
  }

  /// Parses a four-number DSC BoundingBox or HiResBoundingBox value.
  factory AiBoundingBox.parse({required String value}) {
    final List<String> numbers = value.trim().split(RegExp(r'\s+'));
    if (numbers.length != 4) {
      throw const FormatException('Expected four Illustrator bounding-box numbers.');
    }
    return AiBoundingBox(left: double.parse(numbers[0]), bottom: double.parse(numbers[1]), right: double.parse(numbers[2]), top: double.parse(numbers[3]));
  }
}
