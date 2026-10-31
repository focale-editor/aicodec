part of 'ai_native_data.dart';

/// Resolves every indirect page once and rejects duplicate or direct identities.
Map<PdfReference, int> _nativePageIndices(List<PdfPage> pages) {
  final Map<PdfReference, int> result = {};
  for (final (int, PdfPage) page in pages.indexed) {
    final PdfReference? reference = page.$2.reference;
    if (reference == null || result.containsKey(reference)) {
      throw ArgumentError('Native page remapping requires unique indirect PDF pages.');
    }
    result[reference] = page.$1;
  }
  return result;
}

/// Validates all source owners before planning explicit page metadata attachments.
List<List<_NativeSaveTarget>> _mappedNativeTargets(
  List<AiNativePageReplacement> replacements,
  List<_NativeOwner> owners,
  PdfDocument original,
  PdfDocument synchronized,
  AiNativeLimits limits,
  AiNativePageLabelsPolicy pageLabels,
) {
  final PdfValue? root = original.trailer['Root'];
  if (root is! PdfReference || root != synchronized.trailer['Root']) {
    throw ArgumentError('Mapped native saving requires the original catalog identity.');
  }
  final List<PdfPage> before = original.pages;
  final List<PdfPage> after = synchronized.pages;
  final Map<PdfReference, int> oldIndices = _nativePageIndices(before);
  final Map<PdfReference, int> newIndices = _nativePageIndices(after);
  final Set<int?> selected = {};
  for (final AiNativePageReplacement entry in replacements) {
    for (final int? owner in entry.replacement.source.owners) {
      if (!selected.add(owner)) {
        throw ArgumentError('Mapped native replacements overlap source owners.');
      }
    }
  }
  final Set<PdfReference> removed = oldIndices.keys.where((reference) => !newIndices.containsKey(reference)).toSet();
  for (final PdfReference reference in removed) {
    if (!selected.contains(oldIndices[reference]) || synchronized.objects[reference] is! PdfDictionary) {
      throw ArgumentError('Removed pages must belong to selected native programs and retain their unreachable page objects.');
    }
  }
  final Map<PdfReference, List<_NativeOwner>> previous = {};
  for (final _NativeOwner owner in owners) {
    final PdfReference reference = owner.pageIndex == null ? root : before[owner.pageIndex!].reference!;
    previous.putIfAbsent(reference, () => []).add(owner);
  }
  for (final PdfReference reference in removed) {
    final PdfDictionary page = synchronized.dictionary(reference);
    final PdfValue? pieces = page['PieceInfo'];
    final PdfValue? illustratorValue = pieces == null || pieces is PdfNull ? null : synchronized.dictionary(pieces)['Illustrator'];
    if (illustratorValue == null || illustratorValue is PdfNull) {
      throw ArgumentError('Removed source pages must retain their original native metadata.');
    }
    final PdfDictionary illustrator = synchronized.dictionary(illustratorValue);
    final PdfValue? private = illustrator['Private'];
    if (private == null || previous[reference]!.any((owner) => !identical(owner.illustrator, illustrator) || !identical(owner.data, synchronized.dictionary(private)))) {
      throw ArgumentError('Removed source pages must retain their original native metadata.');
    }
  }
  final Map<PdfReference, List<_NativeOwner>> current = {};
  for (final _NativeOwner owner in _owners(synchronized)) {
    final PdfReference reference = owner.pageIndex == null ? root : after[owner.pageIndex!].reference!;
    current.putIfAbsent(reference, () => []).add(owner);
    if (!(previous[reference]?.any((old) => old.prefix == owner.prefix && identical(old.illustrator, owner.illustrator) && identical(old.data, owner.data)) ?? false)) {
      throw ArgumentError('Mapped saving requires unchanged original Illustrator owners; new attachments are made by the kit.');
    }
  }
  for (final MapEntry<PdfReference, List<_NativeOwner>> entry in previous.entries) {
    if (removed.contains(entry.key)) {
      continue;
    }
    if (current[entry.key]?.length != entry.value.length) {
      throw ArgumentError('Retained native pages and catalog aliases must preserve their original metadata.');
    }
  }
  final Set<PdfReference> bound = {};
  final List<List<_NativeSaveTarget>> targets = [];
  for (final AiNativePageReplacement entry in replacements) {
    final AiNativeSource source = entry.replacement.source;
    final List<_NativeSaveTarget> group = [];
    targets.add(group);
    int previousIndex = -1;
    for (final AiNativePageBinding binding in entry.pages) {
      final int? index = newIndices[binding.page];
      if (index == null || index <= previousIndex || !bound.add(binding.page) || !source.owners.contains(binding.metadataOwner)) {
        throw ArgumentError('Native mappings require distinct current pages in declared order and explicitly owned metadata templates.');
      }
      previousIndex = index;
      final List<_NativeOwner> existing = previous[binding.page] ?? [];
      if (existing.isNotEmpty) {
        if (existing.length != 1 || existing.single.pageIndex != binding.metadataOwner || existing.single.prefix != source._prefix) {
          throw ArgumentError('A retained native page must keep its own source metadata owner.');
        }
      } else {
        final PdfValue? pieces = after[index].dictionary['PieceInfo'];
        final PdfValue? illustrator = pieces == null || pieces is PdfNull ? null : synchronized.dictionary(pieces)['Illustrator'];
        if (illustrator != null && illustrator is! PdfNull) {
          throw ArgumentError('A new native attachment cannot overwrite existing Illustrator metadata.');
        }
      }
      final _NativeOwner owner = owners.firstWhere((owner) => owner.pageIndex == binding.metadataOwner && owner.prefix == source._prefix);
      group.add((owner: owner, reference: binding.page));
    }
    if (source.owners.contains(null)) {
      group.add((owner: owners.firstWhere((owner) => owner.pageIndex == null && owner.prefix == source._prefix), reference: root));
    }
    if (group.isEmpty) {
      throw ArgumentError('A mapped replacement must retain at least one native owner.');
    }
    for (final int index in source.owners.whereType<int>()) {
      final PdfReference reference = before[index].reference!;
      if (!removed.contains(reference) && !entry.pages.any((binding) => binding.page == reference)) {
        throw ArgumentError('Every retained page of a selected program requires an explicit binding.');
      }
    }
  }
  final Set<PdfReference> added = newIndices.keys.where((reference) => !oldIndices.containsKey(reference)).toSet();
  if (added.any((reference) => !bound.contains(reference))) {
    throw ArgumentError('Every added PDF page requires an explicit native binding.');
  }
  final List<PdfReference> untouched = oldIndices.keys.where((reference) => !bound.contains(reference) && !removed.contains(reference)).toList();
  final List<PdfReference> retained = newIndices.keys.where((reference) => !bound.contains(reference)).toList();
  if (untouched.length != retained.length || untouched.indexed.any((entry) => entry.$2 != retained[entry.$1])) {
    throw ArgumentError('Mapped saving must retain the relative order of unselected pages.');
  }
  final Set<_NativeOwner> retainedOwners = {
    for (final _NativeOwner owner in owners)
      if (owner.pageIndex == null || newIndices.containsKey(before[owner.pageIndex!].reference)) owner,
    for (final List<_NativeSaveTarget> group in targets) ...group.map((target) => target.owner),
  };
  _validateNativeMetadata(retainedOwners.toList(), original, synchronized, limits, removedPages: removed);
  _mappedPdfReferences(original, synchronized, added, removed, limits);
  final bool reordered = before.length != after.length || before.indexed.any((entry) => entry.$2.reference != after[entry.$1].reference);
  _mappedPageLabels(original, synchronized, after.length, reordered, pageLabels, limits);
  return targets;
}

/// Rejects captured identities and reachable references to removed PDF pages.
void _mappedPdfReferences(PdfDocument original, PdfDocument synchronized, Set<PdfReference> added, Set<PdfReference> removed, AiNativeLimits limits) {
  final Set<PdfReference> oldReferences = {...original.objects.keys};
  final Set<PdfValue> seen = HashSet.identity();
  int count = 0;

  /// Traverses dictionaries and reference edges, never opaque stream payloads.
  void visit(PdfValue value, int depth, {required bool follow}) {
    if (++count > limits.maxTokens || depth > limits.maxDepth) {
      throw const FormatException('Mapped PDF references exceed the inspection limit.');
    }
    if (!seen.add(value)) {
      return;
    }
    switch (value) {
      case final PdfReference reference:
        if (!follow) {
          oldReferences.add(reference);
        } else {
          if (removed.contains(reference)) {
            throw UnsupportedError('The supplied PDF still references a removed page.');
          }
          final PdfValue? target = synchronized.objects[reference];
          if (target != null) {
            visit(target, depth + 1, follow: true);
          } else if (original.objects.containsKey(reference) || !oldReferences.contains(reference)) {
            throw const FormatException('The supplied PDF introduces a dangling reference.');
          }
        }
      case final PdfDictionary dictionary:
        for (final PdfValue child in dictionary.values.values) {
          visit(child, depth + 1, follow: follow);
        }
      case final PdfArray array:
        for (final PdfValue child in array.values) {
          visit(child, depth + 1, follow: follow);
        }
      case final PdfStream stream:
        visit(stream.dictionary, depth + 1, follow: follow);
      case PdfNull() || PdfBoolean() || PdfNumber() || PdfName() || PdfString():
        return;
    }
  }

  visit(original.trailer, 0, follow: false);
  for (final PdfValue value in original.objects.values) {
    visit(value, 0, follow: false);
  }
  final Set<int> reserved = oldReferences.map((reference) => reference.objectNumber).toSet();
  if (added.any((reference) => reserved.contains(reference.objectNumber))) {
    throw ArgumentError('New mapped pages cannot reuse existing or dangling PDF identities.');
  }
  seen.clear();
  count = 0;
  visit(synchronized.trailer, 0, follow: true);
}

/// Checks explicit page-label policy and the supplied positional number tree.
void _mappedPageLabels(PdfDocument original, PdfDocument synchronized, int pageCount, bool reordered, AiNativePageLabelsPolicy policy, AiNativeLimits limits) {
  final PdfValue? labelValue = synchronized.catalog['PageLabels'];
  if (labelValue == null || labelValue is PdfNull) {
    return;
  }
  final PdfValue labels = synchronized.resolve(labelValue);
  final PdfValue? previous = original.catalog['PageLabels'];
  if (reordered && policy == .requireUpdated && previous != null && identical(original.resolve(previous), labels)) {
    throw UnsupportedError('Remapping requires supplied page labels or an explicit retainPositions policy.');
  }
  final Set<PdfValue> seen = HashSet.identity();
  int count = 0;
  int lastIndex = -1;

  /// Requires unique ascending label starts within the resulting page sequence.
  ({int first, int last}) visit(PdfValue value, int depth) {
    final PdfDictionary node = synchronized.dictionary(value);
    if (++count > limits.maxTokens || depth > limits.maxDepth || !seen.add(node)) {
      throw const FormatException('Invalid or excessive PDF page-label tree.');
    }
    final PdfValue? children = node['Kids'];
    final PdfValue? entries = node['Nums'];
    if ((children == null) == (entries == null)) {
      throw const FormatException('Page labels require either Kids or Nums.');
    }
    final PdfValue items = synchronized.resolve((children ?? entries)!);
    if (items is! PdfArray || items.values.isEmpty) {
      throw const FormatException('Invalid PDF page-label array.');
    }
    int? firstIndex;
    if (children != null) {
      for (final PdfValue child in items.values) {
        final ({int first, int last}) bounds = visit(child, depth + 1);
        firstIndex ??= bounds.first;
      }
    } else {
      if (items.values.length.isOdd) {
        throw const FormatException('PDF page-label keys need matching dictionaries.');
      }
      for (int index = 0; index < items.values.length; index += 2) {
        if (++count > limits.maxTokens) {
          throw const FormatException('PDF page labels exceed the inspection limit.');
        }
        final PdfValue key = synchronized.resolve(items.values[index]);
        if (key is! PdfNumber || !key.value.isFinite || key.value != key.value.truncate() || key.value <= lastIndex || key.value >= pageCount || lastIndex < 0 && key.value != 0) {
          throw const FormatException('PDF page-label starts must be ordered and within current pages.');
        }
        lastIndex = key.value.toInt();
        firstIndex ??= lastIndex;
        final PdfDictionary label = synchronized.dictionary(items.values[index + 1]);
        final PdfValue? style = label['S'] == null ? null : synchronized.resolve(label['S']!);
        final PdfValue? prefix = label['P'] == null ? null : synchronized.resolve(label['P']!);
        final PdfValue? start = label['St'] == null ? null : synchronized.resolve(label['St']!);
        if (style != null && (style is! PdfName || !const {'D', 'R', 'r', 'A', 'a'}.contains(style.value)) ||
            prefix != null && prefix is! PdfString ||
            start != null && (start is! PdfNumber || start.value != start.value.truncate() || start.value < 1)) {
          throw const FormatException('Invalid PDF page-label style, prefix or counter.');
        }
      }
    }
    if (node['Limits'] case final PdfValue interval) {
      final PdfValue bounds = synchronized.resolve(interval);
      if (bounds is! PdfArray ||
          bounds.values.length != 2 ||
          bounds.values[0] is! PdfNumber ||
          bounds.values[1] is! PdfNumber ||
          (bounds.values[0] as PdfNumber).value != firstIndex ||
          (bounds.values[1] as PdfNumber).value != lastIndex) {
        throw const FormatException('PDF page-label limits disagree with their entries.');
      }
    }
    return (first: firstIndex!, last: lastIndex);
  }

  visit(labels, 0);
  if (lastIndex < 0) {
    throw const FormatException('PDF page labels require an initial label.');
  }
}
