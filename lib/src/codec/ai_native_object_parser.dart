part of 'package:aikit/src/model/ai_native_records.dart';

/// Binds only direct postfix records with matching lexical/version ownership.
AiNativeObjects _nativeObjects(AiNativeDrawing drawing) {
  final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
  final Map<AiNativeContainer, List<AiNativeObjectIdentifier>> identifiers = {};
  for (final AiNativeObjectIdentifier identifier in structure.identifiers.where((identifier) => identifier.kind == .xmlArt)) {
    (identifiers[identifier.field.owner.source as AiNativeContainer] ??= []).add(identifier);
  }
  final List<AiNativeItem> sources = [...drawing.paths, ...drawing.groups]..sort((first, second) => first.start.compareTo(second.start));
  final List<AiNativeObject> objects = [];
  for (final AiNativeItem source in sources) {
    final AiNativeStructureNode node = structure.nodeFor(source);
    final int following = _pathOffset(drawing.items, source.end, (item) => item.start);
    final AiNativeItem? next = following < drawing.items.length ? drawing.items[following] : null;
    final AiNativeContainer? dictionary = next is AiNativeContainer && next.type == 'ArtDictionary' ? next : null;
    String? issue;
    if (dictionary != null) {
      final AiNativeStructureNode owner = structure.nodeFor(dictionary);
      if (node.parentIndex != owner.parentIndex ||
          node.versions.length != owner.versions.length ||
          node.versions.indexed.any((entry) => !identical(entry.$2.block, owner.versions[entry.$1].block) || entry.$2.branch != owner.versions[entry.$1].branch)) {
        issue = 'The object dictionary crosses a lexical owner or version boundary.';
      } else if (dictionary.notRecorded || dictionary.entries.any((field) => !const {'AI10_ArtUID', 'AIArtName', 'Object name', 'BBAccumRotation'}.contains(field.key))) {
        issue = 'The object dictionary contains unqualified appearance or reference fields.';
      } else if (dictionary.entries.map((field) => field.key).toSet().length != dictionary.entries.length) {
        issue = 'The object dictionary repeats a metadata field.';
      }
      for (final AiNativeEntry field in dictionary.entries) {
        if (const {'AIArtName', 'Object name', 'BBAccumRotation'}.contains(field.key) &&
            (!const {'String', 'UnicodeString'}.contains(field.type) || field.items.isNotEmpty && field.stringBytes == null)) {
          issue ??= 'The object dictionary has an unqualified metadata value.';
        }
        if (field.key == 'BBAccumRotation') {
          final double? angle = field.stringBytes == null ? null : double.tryParse(latin1.decode(field.stringBytes!));
          if (field.type != 'String' || angle == null || !angle.isFinite || angle.abs() > 9007199254740991) {
            issue ??= 'The object dictionary has an invalid accumulated rotation.';
          }
        }
      }
      if (_pathInterval(drawing.records._projection.tokens, source.end, dictionary.end, (token) => token.start).any(
        (token) => token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')),
      )) {
        issue ??= 'The object dictionary has unresolved attached metadata.';
      }
    }
    final List<AiNativeObjectIdentifier> saved = identifiers[dictionary] ?? const [];
    objects.add(
      AiNativeObject._(
        start: source.start,
        end: dictionary?.end ?? source.end,
        source: source,
        node: node,
        dictionary: dictionary,
        identifier: saved.length == 1 ? saved.single : null,
        names: dictionary?.entries.where((field) => const {'AIArtName', 'Object name'}.contains(field.key)).toList() ?? const [],
        bindingIssue: issue,
      ),
    );
  }
  return AiNativeObjects._(drawing: drawing, structure: structure, objects: objects);
}
