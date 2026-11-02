part of 'package:aicodec/src/model/ai_native_records.dart';

/// Requires the same immediate lexical owner and exact saved version branches.
bool _sameNativeObjectOwner(AiNativeStructureNode first, AiNativeStructureNode second) =>
    first.parentIndex == second.parentIndex &&
    first.versions.length == second.versions.length &&
    first.versions.indexed.every((entry) => identical(entry.$2.block, second.versions[entry.$1].block) && entry.$2.branch == second.versions[entry.$1].branch);

/// Binds only direct metadata with matching lexical/version ownership.
AiNativeObjects _nativeObjects(AiNativeDrawing drawing) {
  final AiNativeStructure structure = AiNativeStructure.decode(drawing: drawing);
  final Map<AiNativeContainer, List<AiNativeObjectIdentifier>> identifiers = {};
  final Map<AiNativeContainer, AiLiveShape> shapes = {for (final AiLiveShape shape in drawing.liveShapes) shape.dictionary: shape};
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
    final AiLiveShape? shape = shapes[dictionary];
    final int preceding = _pathOffset(drawing.items, source.start, (item) => item.start) - 1;
    final AiNativeItem? previous = preceding >= 0 ? drawing.items[preceding] : null;
    final AiNativeInstruction? expansion = source is AiNativeGroup && previous is AiNativeInstruction && previous.operator == 'Ae' ? previous : null;
    final int after = following + (dictionary == null ? 0 : 1);
    final AiNativeItem? postfix = after < drawing.items.length ? drawing.items[after] : null;
    final AiNativeInstruction? style = source is AiNativeGroup && postfix is AiNativeInstruction && postfix.operator == 'XW' ? postfix : null;
    String? issue;
    String? metadataIssue;
    if (shape != null) {
      issue = identical(shape.path, source) ? _directNativeShapeIssue(shape) : 'The live-shape dictionary belongs to a different path.';
    }
    if (expansion != null &&
        (expansion.isPrivate || expansion.numbers?.length != 1 || !const [0, 1].contains(expansion.numbers!.single) || !_sameNativeObjectOwner(node, structure.nodeFor(expansion)))) {
      issue = 'The group panel expansion has unqualified syntax or ownership.';
    }
    if (style != null &&
        (style.isPrivate ||
            style.operands.length != 2 ||
            style.operands.first.number != 9 ||
            !const {AiTokenKind.string, AiTokenKind.hexString}.contains(style.operands.last.kind) ||
            aiStringBytes(style.operands.last).isNotEmpty ||
            !_sameNativeObjectOwner(node, structure.nodeFor(style)))) {
      issue ??= 'The group style application requires a separate appearance contract.';
    }
    if (expansion != null && _nativeObjectMetadataComments(drawing, expansion.start, source.start) ||
        style != null && _nativeObjectMetadataComments(drawing, dictionary?.end ?? source.end, style.end)) {
      issue ??= 'The attached group metadata crosses unresolved native comments or data.';
    }
    if (dictionary != null) {
      final AiNativeStructureNode owner = structure.nodeFor(dictionary);
      if (!_sameNativeObjectOwner(node, owner)) {
        issue ??= 'The object dictionary crosses a lexical owner or version boundary.';
      } else if (dictionary.notRecorded ||
          dictionary.entries.any(
            (field) => !{
              'AI10_ArtUID',
              'AIArtName',
              'Object name',
              'BBAccumRotation',
              if (shape != null) ...['ai::LiveShape', 'PATH_IS_KAPPA_CURVE'],
            }.contains(field.key),
          )) {
        metadataIssue = 'The object dictionary contains unqualified appearance or reference fields.';
      } else if (dictionary.entries.map((field) => field.key).toSet().length != dictionary.entries.length) {
        metadataIssue ??= 'The object dictionary repeats a metadata field.';
      }
      for (final AiNativeEntry field in dictionary.entries) {
        if (field.key == 'PATH_IS_KAPPA_CURVE' && (field.type != 'Bool' || field.boolean == null)) {
          metadataIssue ??= 'The object dictionary has an invalid cubic-curve metadata flag.';
        }
        if (const {'AIArtName', 'Object name', 'BBAccumRotation'}.contains(field.key) &&
            (!const {'String', 'UnicodeString'}.contains(field.type) || field.items.isNotEmpty && field.stringBytes == null)) {
          metadataIssue ??= 'The object dictionary has an unqualified metadata value.';
        }
        if (field.key == 'BBAccumRotation') {
          final double? angle = field.stringBytes == null ? null : double.tryParse(latin1.decode(field.stringBytes!));
          if (field.type != 'String' || angle == null || !angle.isFinite || angle.abs() > 9007199254740991) {
            metadataIssue ??= 'The object dictionary has an invalid accumulated rotation.';
          }
        }
      }
      if (_nativeObjectMetadataComments(drawing, source.end, dictionary.end)) {
        issue ??= 'The object dictionary has unresolved attached metadata.';
      }
    }
    final List<AiNativeObjectIdentifier> saved = identifiers[dictionary] ?? const [];
    objects.add(
      AiNativeObject._(
        start: expansion?.start ?? source.start,
        end: style?.end ?? dictionary?.end ?? source.end,
        source: source,
        node: node,
        dictionary: dictionary,
        liveShape: shape,
        expansion: expansion,
        styleApplication: style,
        identifier: saved.length == 1 ? saved.single : null,
        names: dictionary?.entries.where((field) => const {'AIArtName', 'Object name'}.contains(field.key)).toList() ?? const [],
        bindingIssue: issue ?? metadataIssue,
        ownershipIssue: issue,
      ),
    );
  }
  return AiNativeObjects._(drawing: drawing, structure: structure, objects: objects);
}

/// Refuses structured comments and opaque data inside an attached metadata span.
bool _nativeObjectMetadataComments(AiNativeDrawing drawing, int start, int end) => _pathInterval(drawing.records._projection.tokens, start, end, (token) => token.start).any(
  (token) => token.kind == .data || token.kind == .comment && (token.lexeme.startsWith('%AI') || token.lexeme.startsWith('%%')),
);
