part of 'ai_native_data.dart';

/// Validates a batch before allocating any replacement streams in a local graph.
AiPdfDocument _replaceNativePrograms({
  required List<AiNativeReplacement> replacements,
  required PdfDocument synchronizedPdf,
  required AiNativeLimits limits,
  required int blockBytes,
  List<AiNativePageReplacement>? pageReplacements,
  AiNativePageLabelsPolicy pageLabels = .requireUpdated,
}) {
  limits.validate();
  if (replacements.isEmpty) {
    throw ArgumentError('Native replacement requires at least one program.');
  }
  if (blockBytes <= 0 || blockBytes > limits.maxEncodedBytes) {
    throw ArgumentError.value(blockBytes, 'blockBytes');
  }
  final AiDocument document = replacements.first.source.document;
  if (document is! AiPdfDocument || replacements.any((replacement) => !identical(replacement.source.document, document) || replacement.source.owners.isEmpty)) {
    throw ArgumentError('Native replacements must share one PDF extraction document.');
  }
  final List<_NativeOwner> owners = pageReplacements == null ? _validateNativeSaveGraph(document.pdf, synchronizedPdf, limits) : _owners(document.pdf);
  final List<List<_NativeSaveTarget>> targets = pageReplacements == null
      ? [
          for (final AiNativeReplacement replacement in replacements)
            [
              for (final int? index in replacement.source.owners)
                (
                  owner: owners.firstWhere((owner) => owner.pageIndex == index && owner.prefix == replacement.source._prefix),
                  reference: (index == null ? synchronizedPdf.trailer['Root'] : synchronizedPdf.pages[index].reference)! as PdfReference,
                ),
            ],
        ]
      : _mappedNativeTargets(pageReplacements, owners, document.pdf, synchronizedPdf, limits, pageLabels);
  final Set<int?> selected = {};
  final List<Uint8List> envelopes = [];
  int decodedTotal = 0;
  int encodedTotal = 0;
  for (final AiNativeReplacement replacement in replacements) {
    final AiNativeSource source = replacement.source;
    for (final int? index in source.owners) {
      if (!selected.add(index)) {
        throw ArgumentError('Native replacement owners overlap.');
      }
      if (owners.any((owner) => owner.pageIndex == index && owner.prefix != source._prefix)) {
        throw const FormatException('Cannot synchronize mixed Illustrator private-data families on one owner.');
      }
    }
    decodedTotal += replacement.program.length;
    if (decodedTotal > limits.maxDecodedBytes) {
      throw const FormatException('Native replacements exceed the aggregate decoded byte limit.');
    }
    final Uint8List envelope = AiNativeData.encodeEnvelope(replacement.program, compression: source.compression, limits: limits);
    encodedTotal += envelope.length;
    if (encodedTotal > limits.maxEncodedBytes) {
      throw const FormatException('Native replacements exceed the aggregate encoded byte limit.');
    }
    envelopes.add(envelope);
  }
  final List<Map<int?, PdfStream>> headers = _nativeMetadataHeaders(replacements, targets.expand((targets) => targets.map((target) => target.owner)).toSet().toList(), document.pdf, limits);
  final PdfEditor editor = PdfEditor(document: synchronizedPdf);
  final Map<PdfStream, PdfReference> headerReferences = HashMap.identity();
  for (final (int, AiNativeReplacement) entry in replacements.indexed) {
    final AiNativeSource source = entry.$2.source;
    final Uint8List envelope = envelopes[entry.$1];
    final Map<String, PdfValue> blocks = {};
    for (int offset = 0; offset < envelope.length; offset += blockBytes) {
      final int end = offset + blockBytes < envelope.length ? offset + blockBytes : envelope.length;
      blocks['${source._prefix}${blocks.length + 1}'] = editor.addObject(
        value: PdfStream(dictionary: PdfDictionary(), data: Uint8List.sublistView(envelope, offset, end)),
      );
    }
    for (final _NativeSaveTarget target in targets[entry.$1]) {
      final _NativeOwner owner = target.owner;
      final PdfReference reference = target.reference;
      final PdfDictionary dictionary = editor.document.dictionary(reference);
      final PdfDictionary pieces = dictionary['PieceInfo'] == null || dictionary['PieceInfo'] is PdfNull ? PdfDictionary() : editor.document.dictionary(dictionary['PieceInfo']!);
      final PdfDictionary data = owner.data.copyWith(
        remove: owner.data.values.keys.where(_blockPattern.hasMatch).toSet(),
        values: {
          ...blocks,
          'NumBlock': PdfNumber(value: blocks.length),
          if (headers[entry.$1][owner.pageIndex] case final PdfStream header) 'AIMetaData': headerReferences.putIfAbsent(header, () => editor.addObject(value: header)),
        },
      );
      editor.replaceObject(
        reference: reference,
        value: dictionary.copyWith(
          values: {
            'PieceInfo': pieces.copyWith(
              values: {
                'Illustrator': owner.illustrator.copyWith(values: {'Private': data}),
              },
            ),
          },
        ),
      );
    }
  }
  return AiPdfDocument(pdf: editor.document);
}

/// One source metadata owner attached to an explicitly validated PDF object.
typedef _NativeSaveTarget = ({_NativeOwner owner, PdfReference reference});

/// Rejects page remapping, stale native handles and foreign private graphs.
List<_NativeOwner> _validateNativeSaveGraph(PdfDocument original, PdfDocument synchronized, AiNativeLimits limits) {
  final PdfValue? root = original.trailer['Root'];
  final List<PdfPage> before = original.pages;
  final List<PdfPage> after = synchronized.pages;
  if (root is! PdfReference ||
      root != synchronized.trailer['Root'] ||
      before.length != after.length ||
      before.indexed.any((entry) => entry.$2.reference == null || entry.$2.reference != after[entry.$1].reference)) {
    throw ArgumentError('Native saving requires unchanged catalog and ordered page identities.');
  }
  final List<_NativeOwner> owners = _owners(original);
  final List<_NativeOwner> current = _owners(synchronized);
  if (owners.length != current.length ||
      owners.indexed.any(
        (entry) =>
            entry.$2.pageIndex != current[entry.$1].pageIndex ||
            entry.$2.prefix != current[entry.$1].prefix ||
            !identical(entry.$2.illustrator, current[entry.$1].illustrator) ||
            !identical(entry.$2.data, current[entry.$1].data),
      )) {
    throw ArgumentError('Native saving requires current source owners and unchanged Illustrator metadata.');
  }
  _validateNativeMetadata(owners, original, synchronized, limits);
  return owners;
}

/// Retains every original metadata dependency, including unselected programs.
void _validateNativeMetadata(List<_NativeOwner> owners, PdfDocument original, PdfDocument synchronized, AiNativeLimits limits, {Set<PdfReference> removedPages = const {}}) {
  final Set<PdfValue> seen = HashSet.identity();
  final Set<PdfReference> references = {};
  int count = 0;

  /// Follows only native metadata dependencies, never page artwork implicitly.
  void visit(PdfValue value, int depth) {
    if (depth > limits.maxDepth || ++count > limits.maxTokens) {
      throw const FormatException('Native save metadata exceeds the inspection limit.');
    }
    if (!seen.add(value)) {
      return;
    }
    switch (value) {
      case final PdfReference reference:
        if (removedPages.contains(reference)) {
          throw UnsupportedError('Native metadata still references a removed PDF page.');
        }
        if (!references.add(reference)) {
          return;
        }
        final PdfValue? target = original.objects[reference];
        if (!identical(target, synchronized.objects[reference])) {
          throw ArgumentError('Native metadata references a replaced or foreign PDF object: $reference.');
        }
        if (target != null) {
          visit(target, depth + 1);
        }
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

  for (final _NativeOwner owner in owners) {
    visit(owner.illustrator, 0);
  }
}
