part of 'package:aikit/src/model/ai_native_records.dart';

/// Source structure, distinct from authoring semantics or rendering support.
enum AiNativeStructureKind {
  /// Layer including its header and complete child interval.
  layer,

  /// Ordinary native group.
  group,

  /// Compound path grouping.
  compound,

  /// Native clipping group; interpreting its clip is a separate contract.
  clip,

  /// Complete printable or private path.
  path,

  /// Hierarchical record, including opaque future record types.
  record,

  /// A source version condition with both saved branches.
  version,

  /// Named global gradient declaration.
  gradientResource,

  /// Remaining body command, including state and unsupported instructions.
  instruction,
}

/// Immutable identity and lexical owner of one source-backed structure.
///
/// Identity belongs to this snapshot only. It is not a generated Illustrator
/// UUID, and does not imply that this span can be moved or deleted independently.
final class AiNativeStructureNode {
  /// Position in the owning structure's source-ordered node list.
  final int index;

  /// Structural category, without granting editing support.
  final AiNativeStructureKind kind;

  /// Original AiLayer or AiNativeItem handle owned by this snapshot.
  final Object source;

  /// Inclusive byte position in the complete native program.
  final int start;

  /// Exclusive source boundary.
  final int end;

  /// Immediate lexical owner index, or null at the program root.
  final int? parentIndex;

  /// Direct children in source order, including preserved opaque records.
  final List<int> childIndices;

  /// Enclosing version branches, from outermost to innermost.
  final List<AiNativeVersionMembership> versions;

  /// Freezes a source identity and its completed owner/child associations.
  AiNativeStructureNode._({
    required this.index,
    required this.kind,
    required this.source,
    required this.start,
    required this.end,
    required this.parentIndex,
    required List<int> childIndices,
    required List<AiNativeVersionMembership> versions,
  }) : childIndices = List.unmodifiable(childIndices),
       versions = List.unmodifiable(versions);
}

/// One ordered field of a source-owned record, including repeated/opaque fields.
final class AiNativeStructureEntry {
  /// Exact field handle in the immutable native snapshot.
  final AiNativeEntry entry;

  /// Record node whose entry list contains this field.
  final AiNativeStructureNode owner;

  /// Local position, independent of a potentially repeated or absent key.
  final int index;

  /// Retains field identity without inventing a source span for delimiters.
  const AiNativeStructureEntry._({required this.entry, required this.owner, required this.index});
}

/// Saved identifier namespaces whose native ownership is established.
enum AiNativeIdentifierKind {
  /// ArtboardUUID in a recorded Document artboard dictionary.
  artboard,

  /// AI10_ArtUID containing a native XMLUID record in an ArtDictionary.
  xmlArt,
}

/// A saved identifier and its exact field owner, without assuming uniqueness.
///
/// Equal identifiers do not merge source objects or prove shared asset identity.
/// A dictionary identifier does not by itself identify an adjacent drawing path.
final class AiNativeObjectIdentifier {
  /// Native namespace used to distinguish unrelated identifier families.
  final AiNativeIdentifierKind kind;

  /// Source-owned dictionary field carrying this identifier.
  final AiNativeStructureEntry field;

  /// Exact decoded source bytes, without locale or UUID normalization.
  final Uint8List _bytes;

  /// Owns the saved identifier without allocating replacement identities.
  AiNativeObjectIdentifier._({required this.kind, required this.field, required List<int> bytes}) : _bytes = Uint8List.fromList(bytes);

  /// Immutable native bytes; decoding into display text is the host's decision.
  Uint8List get bytes => _bytes.asUnmodifiableView();
}

/// Named resource families with qualified reference syntax.
enum AiNativeStructureResourceKind {
  /// KnownStyle declaration referenced by mode-one XW commands.
  knownStyle,

  /// Global Bd declaration referenced by complete Bg gradient instances.
  gradient,
}

/// A named resource declaration retaining its exact structural owner.
final class AiNativeStructureResource {
  /// Resource namespace, preventing accidental cross-family name matches.
  final AiNativeStructureResourceKind kind;

  /// Source node containing this definition, including its version memberships.
  final AiNativeStructureNode definition;

  /// Branches owning the name declaration, including conditions inside a record.
  final List<AiNativeVersionMembership> versions;

  /// Owned resource-name bytes without guessing a text encoding.
  final Uint8List _nameBytes;

  /// Retains declarations separately even when their names coincide.
  AiNativeStructureResource._({required this.kind, required this.definition, required List<AiNativeVersionMembership> versions, required List<int> nameBytes})
    : versions = List.unmodifiable(versions),
      _nameBytes = Uint8List.fromList(nameBytes);

  /// Exact immutable native name used to match references.
  Uint8List get nameBytes => _nameBytes.asUnmodifiableView();
}

/// Resolution of one resource use, separate from preserving its source bytes.
enum AiNativeResourceResolution {
  /// Exactly one unconditional or same-branch declaration is available.
  resolved,

  /// No compatible named declaration was found.
  missing,

  /// Several declarations may apply without a unique owner.
  ambiguous,

  /// Availability depends on an additional version branch not selected here.
  conditional,
}

/// Explicit XW or Bg reference with retained ambiguity and branch ownership.
final class AiNativeResourceUse {
  /// Resource namespace of this use.
  final AiNativeStructureResourceKind kind;

  /// Exact parsed native instruction, not a string or executable procedure.
  final AiNativeInstruction instruction;

  /// Smallest structural node containing the whole instruction, if any.
  final AiNativeStructureNode? owner;

  /// Original resource-name string operand.
  final AiToken name;

  /// Enclosing version branches of the instruction.
  final List<AiNativeVersionMembership> versions;

  /// Potential declarations after excluding mutually exclusive saved branches.
  final List<AiNativeStructureResource> candidates;

  /// Whether this source establishes one available definition.
  final AiNativeResourceResolution resolution;

  /// Freezes a qualified reference without silently choosing a duplicate name.
  AiNativeResourceUse._({
    required this.kind,
    required this.instruction,
    required this.owner,
    required this.name,
    required List<AiNativeVersionMembership> versions,
    required List<AiNativeStructureResource> candidates,
    required this.resolution,
  }) : versions = List.unmodifiable(versions),
       candidates = List.unmodifiable(candidates);

  /// Exact name bytes, independently of display encoding.
  Uint8List get nameBytes => aiStringBytes(name).asUnmodifiableView();
}

/// Semantic links of a live shape, separate from lexical source containment.
final class AiNativeShapeOwnership {
  /// Original shape and any unresolved association diagnostic.
  final AiLiveShape shape;

  /// Authoritative metadata owner identifying this shape in the snapshot.
  final AiNativeStructureNode dictionary;

  /// Bound authoring path, when identified by the native drawing reader.
  final AiNativeStructureNode? path;

  /// Separate printable group, when stored by the source.
  final AiNativeStructureNode? printingGroup;

  /// Printable paths, without conflating them with editable authoring geometry.
  final List<AiNativeStructureNode> printingPaths;

  /// Redundant metadata accompanying the printable group.
  final AiNativeStructureNode? printingDictionary;

  /// Older-version dictionaries bound to the same source shape.
  final List<AiNativeStructureNode> alternatives;

  /// Freezes known semantic links without making unresolved shapes editable.
  AiNativeShapeOwnership._({
    required this.shape,
    required this.dictionary,
    required this.path,
    required this.printingGroup,
    required List<AiNativeStructureNode> printingPaths,
    required this.printingDictionary,
    required List<AiNativeStructureNode> alternatives,
  }) : printingPaths = List.unmodifiable(printingPaths),
       alternatives = List.unmodifiable(alternatives);
}

/// Source identities, lexical ownership and qualified shared-resource links.
///
/// This inventory preserves every known source handle and both version branches.
/// It is not a display tree or a permission to mutate arbitrary object intervals.
/// Unknown record/instruction semantics stay opaque. Resource uses cover XW and
/// complete Bg instances, not unknown plug-in dependency schemas.
final class AiNativeStructure {
  /// Drawing snapshot supplying paths, groups and live-shape associations.
  final AiNativeDrawing drawing;

  /// Complete version-boundary inventory for this snapshot.
  final AiNativeVersions versions;

  /// Nodes in source order, with parents preceding their children.
  final List<AiNativeStructureNode> nodes;

  /// Fields in record-source order and then each record's saved entry order.
  final List<AiNativeStructureEntry> entries;

  /// Saved artboard and XML art identifiers, including repeated byte values.
  final List<AiNativeObjectIdentifier> identifiers;

  /// Separate named declarations, including conditional or duplicate definitions.
  final List<AiNativeStructureResource> resources;

  /// Known resource uses in source order, including unresolved references.
  final List<AiNativeResourceUse> resourceUses;

  /// Authoring/printing/alternate relationships retained independently of nesting.
  final List<AiNativeShapeOwnership> shapes;

  /// Private identity lookup; callers never receive the mutable map.
  final Map<Object, AiNativeStructureNode> _sources;

  /// Snapshot identity lookup for source fields, independent of their keys.
  final Map<AiNativeEntry, AiNativeStructureEntry> _entries;

  /// Builds a bounded source graph without rendering or selecting a target version.
  factory AiNativeStructure.decode({required AiNativeDrawing drawing}) => _nativeStructure(drawing);

  /// Owns the completed immutable structure and identity lookup.
  AiNativeStructure._({
    required this.drawing,
    required this.versions,
    required List<AiNativeStructureNode> nodes,
    required List<AiNativeStructureEntry> entries,
    required List<AiNativeObjectIdentifier> identifiers,
    required List<AiNativeStructureResource> resources,
    required List<AiNativeResourceUse> resourceUses,
    required List<AiNativeShapeOwnership> shapes,
  }) : nodes = List.unmodifiable(nodes),
       entries = List.unmodifiable(entries),
       identifiers = List.unmodifiable(identifiers),
       resources = List.unmodifiable(resources),
       resourceUses = List.unmodifiable(resourceUses),
       shapes = List.unmodifiable(shapes),
       _sources = Map.identity()..addEntries(nodes.map((node) => MapEntry(node.source, node))),
       _entries = Map.identity()..addEntries(entries.map((field) => MapEntry(field.entry, field)));

  /// Resolves an original source handle, rejecting foreign or stale snapshots.
  AiNativeStructureNode nodeFor(Object source) => _sources[source] ?? (throw ArgumentError('The source handle does not belong to this native structure.'));

  /// Resolves a field's owner and local order, rejecting foreign snapshots.
  AiNativeStructureEntry entryFor(AiNativeEntry entry) => _entries[entry] ?? (throw ArgumentError('The entry does not belong to this native structure.'));

  /// Returns the immediate lexical parent of an owned node.
  AiNativeStructureNode? parentOf(AiNativeStructureNode node) {
    _requireOwned(node);
    return node.parentIndex == null ? null : nodes[node.parentIndex!];
  }

  /// Returns direct lexical children in their saved order.
  List<AiNativeStructureNode> childrenOf(AiNativeStructureNode node) {
    _requireOwned(node);
    return List.unmodifiable(node.childIndices.map((index) => nodes[index]));
  }

  /// Includes conditional and ambiguous uses that may depend on this definition.
  List<AiNativeResourceUse> usesOf(AiNativeStructureResource resource) {
    if (!resources.contains(resource)) {
      throw ArgumentError('The resource belongs to a different native structure.');
    }
    return List.unmodifiable(resourceUses.where((use) => use.candidates.contains(resource)));
  }

  /// Requires node identity rather than accepting coincident source offsets.
  void _requireOwned(AiNativeStructureNode node) {
    if (node.index >= nodes.length || !identical(nodes[node.index], node)) {
      throw ArgumentError('The node belongs to a different native structure.');
    }
  }
}
