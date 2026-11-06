part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Associates bounded literal symbol references without interpreting artwork.
AiNativeSymbols _nativeSymbols(AiNativeArtworkResources resources) {
  final AiNativeStructure structure = resources.structure;
  final AiNativeLimits limits = structure.drawing.records.program.limits;
  final Map<String, List<AiNativeArtworkResource>> named = {};
  for (final AiNativeArtworkResource resource in resources.resources.where((resource) => resource.kind == .symbol)) {
    (named[latin1.decode(resource.nameBytes)] ??= []).add(resource);
  }
  final List<AiNativeSymbolInstance> instances = [];
  int work = 0;
  for (final AiNativeStructureNode node in structure.nodes) {
    final Object source = node.source;
    if (source is! AiNativeContainer || source.type != 'SymbolInstance') {
      continue;
    }
    final List<AiNativeEntry> references = source.values('SymbolRef');
    final AiNativeEntry? reference = references.singleOrNull;
    final Uint8List? name = reference != null && reference.type == null && reference.items.length == 1 ? reference.stringBytes : null;
    final Uint8List? literal = name?.isNotEmpty == true ? name : null;
    final List<AiNativeEntry> transforms = source.values('RTransformMatrix');
    final AiNativeEntry? transform = transforms.singleOrNull;
    final List<double>? numbers = transform?.type == null ? transform?.numbers : null;
    final List<double>? matrix = numbers?.length == 6 && numbers!.every((value) => value.isFinite) ? numbers : null;
    final List<AiNativeArtworkResource> declarations = literal == null ? const [] : named[latin1.decode(literal)] ?? const [];
    work += 1 + source.entries.length + node.versions.length + declarations.fold<int>(0, (sum, value) => sum + 1 + value.versions.length);
    if (work > limits.maxTokens) {
      throw const AiLimitException(message: 'Symbol reference associations exceed the inspection limit.');
    }
    final Map<AiNativeVersionBlock, AiNativeVersionBranch> selected = {for (final AiNativeVersionMembership version in node.versions) version.block: version.branch};
    final List<AiNativeArtworkResource> candidates = declarations
        .where((declaration) => declaration.versions.every((version) => selected[version.block] == null || selected[version.block] == version.branch))
        .toList();
    final List<AiNativeArtworkResource> available = candidates.where((declaration) => declaration.versions.every((version) => selected[version.block] == version.branch)).toList();
    final AiNativeResourceResolution? resolution = literal == null
        ? null
        : candidates.isEmpty
        ? .missing
        : candidates.length == 1 && available.length == 1
        ? .resolved
        : available.length > 1
        ? .ambiguous
        : .conditional;
    final int index = _pathOffset(resources.resources, source.start + 1, (resource) => resource.start) - 1;
    final AiNativeArtworkResource? enclosing = index < 0 ? null : resources.resources[index];
    instances.add(
      AiNativeSymbolInstance._(
        record: source,
        node: node,
        resource: enclosing != null && source.start >= enclosing.artworkStart && source.end <= enclosing.artworkEnd ? enclosing : null,
        nameBytes: literal,
        relativeTransform: matrix,
        otherEntries: source.entries.where((entry) => entry.isQualifier || !const {'SymbolRef', 'RTransformMatrix'}.contains(entry.key)).toList(),
        candidates: candidates,
        resolution: resolution,
      ),
    );
  }
  return AiNativeSymbols._(artworkResources: resources, instances: instances);
}
