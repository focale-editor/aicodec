part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Checks reachable PDF references without inspecting rendering operators.
void _newDocumentPdfGraph(PdfDocument pdf, AiNativeLimits limits) {
  if (pdf.trailer['Encrypt'] != null && pdf.trailer['Encrypt'] is! PdfNull) {
    throw UnsupportedError('New native AI containers require an unencrypted host PDF.');
  }
  if (pdf.objects.length > limits.maxTokens) {
    throw const AiLimitException(message: 'New AI PDF graph exceeds the native inspection budget.');
  }
  final Set<PdfValue> seen = Set.identity();
  final Set<PdfReference> references = {};
  int count = 0;

  /// Follows graph edges once, including cycles through page parents/resources.
  void visit(PdfValue value, int depth) {
    if (depth > limits.maxDepth || ++count > limits.maxTokens) {
      throw const AiLimitException(message: 'New AI PDF dependencies exceed native inspection limits.');
    }
    if (!seen.add(value)) {
      return;
    }
    switch (value) {
      case final PdfReference reference:
        if (!references.add(reference)) {
          return;
        }
        final PdfValue? target = pdf.objects[reference];
        if (target == null) {
          throw const FormatException('New AI PDF graph contains a dangling reference.');
        }
        visit(target, depth + 1);
      case final PdfDictionary dictionary:
        for (final PdfValue child in dictionary.values.values) {
          visit(child, depth + 1);
        }
      case final PdfArray array:
        for (final PdfValue child in array.values) {
          visit(child, depth + 1);
        }
      case final PdfStream stream:
        visit(stream.dictionary, depth + 1);
      case PdfNull() || PdfBoolean() || PdfNumber() || PdfName() || PdfString():
        return;
    }
  }

  visit(pdf.trailer, 0);
}

/// Reads one finite positive PDF rectangle without converting its coordinate basis.
AiBoundingBox _newDocumentPdfBox(PdfDocument pdf, PdfValue? value) {
  final PdfValue? resolved = value == null ? null : pdf.resolve(value);
  if (resolved is! PdfArray || resolved.values.length != 4) {
    throw const FormatException('New AI PDF pages require a four-coordinate page box.');
  }
  final List<double> numbers = [];
  for (final PdfValue item in resolved.values) {
    final PdfValue number = pdf.resolve(item);
    if (number is! PdfNumber || !number.value.isFinite || number.value.abs() > 9007199254740991) {
      throw const FormatException('New AI page boxes require finite portable coordinates.');
    }
    numbers.add(number.value.toDouble());
  }
  final AiBoundingBox box = AiBoundingBox(left: numbers[0], bottom: numbers[1], right: numbers[2], top: numbers[3]);
  if (box.left == box.right || box.bottom == box.top) {
    throw const FormatException('New AI PDF pages require positive dimensions.');
  }
  return box;
}

/// Checks physical board/page size while retaining host bleed and coordinate origins.
void _newDocumentPageGeometry(PdfDocument pdf, PdfPage page, AiNativeArtboard board) {
  for (final (PdfValue?, double) setting in [(page.inherited['Rotate'], 0), (page.dictionary['UserUnit'], 1)]) {
    final PdfValue? value = setting.$1 == null ? null : pdf.resolve(setting.$1!);
    if (value != null && value is! PdfNull && (value is! PdfNumber || value.value != setting.$2)) {
      throw UnsupportedError('New AI pages require unrotated unit-scale PDF coordinates.');
    }
  }
  final AiBoundingBox media = _newDocumentPdfBox(pdf, page.inherited['MediaBox']);
  final PdfValue? cropValue = page.inherited['CropBox'];
  final AiBoundingBox crop = cropValue == null || cropValue is PdfNull ? media : _newDocumentPdfBox(pdf, cropValue);
  final PdfValue? trimValue = page.dictionary['TrimBox'];
  final AiBoundingBox trim = trimValue == null || trimValue is PdfNull ? crop : _newDocumentPdfBox(pdf, trimValue);
  if (crop.left < media.left ||
      crop.bottom < media.bottom ||
      crop.right > media.right ||
      crop.top > media.top ||
      trim.left < crop.left ||
      trim.bottom < crop.bottom ||
      trim.right > crop.right ||
      trim.top > crop.top) {
    throw ArgumentError('New AI trim/crop boxes must lie inside the supplied media box.');
  }
  final AiBoundingBox bounds = board.bounds;
  if ((trim.right - trim.left - (bounds.right - bounds.left)).abs() > 0.000001 || (trim.top - trim.bottom - (bounds.top - bounds.bottom)).abs() > 0.000001) {
    throw ArgumentError('The supplied PDF page dimensions disagree with its native artboard.');
  }
}

/// Creates all initial private streams and owner links in an immutable PDF graph.
AiPdfDocument _createNativeDocumentPdf(AiNativeRecords records, PdfDocument pdf, List<AiNativeDocumentPage> bindings, DateTime modifiedAt, int blockBytes) {
  final AiNativeLimits limits = records.program.limits;
  limits.validate();
  final DateTime date = _newDocumentDate(modifiedAt);
  if (blockBytes <= 0 || blockBytes > limits.maxEncodedBytes) {
    throw ArgumentError.value(blockBytes, 'blockBytes');
  }
  final AiNativeArtboards boards = AiNativeArtboards.decode(records: records);
  final AiNativeDocumentSettings settings = AiNativeDocumentSettings.decode(records: records);
  final List<PdfPage> pages = pdf.pages;
  if (boards.artboards.isEmpty ||
      boards.activeIndex == null ||
      boards.lastArtboardId == null ||
      pages.length != boards.artboards.length ||
      bindings.length != pages.length ||
      settings.largeCanvasScale != 1 ||
      records.roots.where((record) => record.type == 'Document').length != 1) {
    throw ArgumentError('Initial AI packaging requires one unit-scale native document and every current board/page.');
  }
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final AiNativeLayers layers = AiNativeLayers.decode(drawing: drawing);
  if (!layers.rootCountMatches) {
    throw const FormatException('Initial AI packaging requires consistent native layer counts.');
  }
  final Set<String> identities = {};
  for (final AiNativeArtboard board in boards.artboards) {
    final String? identity = board.record['ArtboardUUID']?.text();
    if (identity == null || !_rasterIdentifier.hasMatch(identity) || !identities.add(identity.toLowerCase())) {
      throw ArgumentError('Initial AI artboards require distinct canonical UUIDs.');
    }
  }
  final AiNativeStructure structure = layers.structure;
  if (structure.resourceUses.any((use) => use.resolution == .missing || use.resolution == .ambiguous)) {
    throw UnsupportedError('New AI documents cannot contain unresolved named style or gradient references.');
  }
  final Set<PdfReference> references = {};
  for (final (int, AiNativeDocumentPage) entry in bindings.indexed) {
    final AiNativeDocumentPage binding = entry.$2;
    final AiNativeArtboard board = boards.artboards[entry.$1];
    if (!identical(binding.artboard.record, board.record) || !identical(binding.artboard.document, boards.document) || binding.page != pages[entry.$1].reference || !references.add(binding.page)) {
      throw ArgumentError('Initial AI bindings require current native boards and PDF pages in matching order.');
    }
    _newDocumentPageGeometry(pdf, pages[entry.$1], board);
  }
  final List<AiToken> header = records._projection.tokens.takeWhile((token) => token.lexeme != '%%EndComments').toList();
  final AiToken? end = records._projection.tokens.where((token) => token.lexeme == '%%EndComments').firstOrNull;
  final List<AiToken> versions = header.where((token) => token.lexeme.startsWith('%%AI8_CreatorVersion:')).toList();
  final Map<String, AiNativeHeaderField> fields = _nativeNumericHeader(records, {'AI9_ColorModel'});
  if (end == null ||
      header.any((token) => token.kind != .comment) ||
      versions.length != 1 ||
      !RegExp(r'^%%AI8_CreatorVersion:\s*24\.0\.0\s*$').hasMatch(versions.single.lexeme) ||
      fields['AI9_ColorModel']?.values.length != 1 ||
      !const {0, 1}.contains(fields['AI9_ColorModel']!.values.single)) {
    throw UnsupportedError('Initial AI packaging requires a complete version-24 native header and explicit document color mode.');
  }
  int headerEnd = end.end;
  if (headerEnd < records.program.bytes.length && records.program.bytes[headerEnd] == 13) {
    headerEnd++;
  }
  if (headerEnd < records.program.bytes.length && records.program.bytes[headerEnd] == 10) {
    headerEnd++;
  }
  _newDocumentPdfGraph(pdf, limits);
  for (final PdfDictionary owner in [pdf.catalog, ...pages.map((page) => page.dictionary)]) {
    final PdfValue? pieces = owner['PieceInfo'];
    final PdfValue? illustrator = pieces == null || pieces is PdfNull ? null : pdf.dictionary(pieces)['Illustrator'];
    if (illustrator != null && illustrator is! PdfNull) {
      throw ArgumentError('Initial AI creation cannot overwrite existing Illustrator metadata; use native replacement for edits.');
    }
  }
  final Uint8List envelope = AiNativeData.encodeEnvelope(records.program.bytes, compression: .zstandard, limits: limits);
  final int count = (envelope.length + blockBytes - 1) ~/ blockBytes;
  if (count + pdf.objects.length + 2 > min(limits.maxTokens, pdf.limits.maxObjects) ||
      envelope.length + headerEnd > limits.maxEncodedBytes ||
      headerEnd > pdf.limits.maxStreamBytes ||
      min(blockBytes, envelope.length) > pdf.limits.maxStreamBytes) {
    throw const AiLimitException(message: 'New AI private blocks and header exceed container limits.');
  }
  final PdfEditor editor = PdfEditor(document: pdf);
  final Map<String, PdfValue> blocks = {};
  for (int offset = 0; offset < envelope.length; offset += blockBytes) {
    blocks['AIPrivateData${blocks.length + 1}'] = editor.addObject(
      value: PdfStream(
        dictionary: PdfDictionary(),
        data: Uint8List.sublistView(envelope, offset, min(offset + blockBytes, envelope.length)),
      ),
    );
  }
  final PdfReference cache = editor.addObject(
    value: PdfStream(dictionary: PdfDictionary(), data: Uint8List.sublistView(records.program.bytes, 0, headerEnd)),
  );
  final PdfReference private = editor.addObject(
    value: PdfDictionary(
      values: {
        'ContainerVersion': PdfNumber(value: 12),
        'CreatorVersion': PdfNumber(value: 24),
        'RoundtripStreamType': PdfNumber(value: 2),
        'RoundtripVersion': PdfNumber(value: 24),
        'NumBlock': PdfNumber(value: blocks.length),
        'AIMetaData': cache,
        ...blocks,
      },
    ),
  );
  final String stamp = 'D:${date.year.toString().padLeft(4, '0')}${[date.month, date.day, date.hour, date.minute, date.second].map((value) => value.toString().padLeft(2, '0')).join()}Z';
  final PdfDictionary illustrator = PdfDictionary(
    values: {
      'Private': private,
      'LastModified': PdfString(bytes: latin1.encode(stamp)),
    },
  );
  for (final PdfPage page in pages) {
    final PdfValue? source = page.dictionary['PieceInfo'];
    final PdfDictionary pieces = source == null || source is PdfNull ? PdfDictionary() : pdf.dictionary(source);
    editor.replaceObject(
      reference: page.reference!,
      value: page.dictionary.copyWith(
        values: {
          'PieceInfo': pieces.copyWith(values: {'Illustrator': illustrator}),
        },
      ),
    );
  }
  return AiPdfDocument(pdf: editor.document);
}
