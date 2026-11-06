part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// A saved symbol instance, independent of its printing representation.
///
/// Inspection retains unknown fields and conditional instances. A resolved master
/// does not qualify native editing, printing ownership or coordinate conversion.
final class AiNativeSymbolInstance {
  /// Exact record, including repeated, unknown and nested producer fields.
  final AiNativeContainer record;

  /// Lexical owner and saved version memberships in this source snapshot.
  final AiNativeStructureNode node;

  /// Enclosing setup artwork declaration, or null outside resource artwork.
  final AiNativeArtworkResource? resource;

  /// Exact nonempty literal symbol name, or null for an unsupported reference.
  final Uint8List? nameBytes;

  /// Saved six-component `RTransformMatrix`, or null for unsupported syntax.
  ///
  /// These values remain in the producer's relative coordinate system. No ruler,
  /// canvas, artboard, registration-point or y-axis conversion is inferred.
  final List<double>? relativeTransform;

  /// Entries outside the two observed instance fields, including qualifiers.
  final List<AiNativeEntry> otherEntries;

  /// Compatible declarations, excluding mutually exclusive saved branches.
  final List<AiNativeArtworkResource> candidates;

  /// Name resolution, or null when no unique literal reference can be read.
  final AiNativeResourceResolution? resolution;

  /// Retains immutable fields without selecting a target Illustrator version.
  AiNativeSymbolInstance._({
    required this.record,
    required this.node,
    required this.resource,
    required Uint8List? nameBytes,
    required List<double>? relativeTransform,
    required List<AiNativeEntry> otherEntries,
    required List<AiNativeArtworkResource> candidates,
    required this.resolution,
  }) : nameBytes = nameBytes?.asUnmodifiableView(),
       relativeTransform = relativeTransform == null ? null : List.unmodifiable(relativeTransform),
       otherEntries = List.unmodifiable(otherEntries),
       candidates = List.unmodifiable(candidates);

  /// Unique available master; null for missing, conditional or ambiguous names.
  AiNativeArtworkResource? get definition => resolution == AiNativeResourceResolution.resolved ? candidates.single : null;
}

/// Source-backed symbol links and relative placements with explicit ambiguity.
final class AiNativeSymbols {
  /// Shared declaration snapshot; patterns and brush names remain separate.
  final AiNativeArtworkResources artworkResources;

  /// Every lexical `SymbolInstance`, including unsupported field layouts.
  final List<AiNativeSymbolInstance> instances;

  /// Reads literal references without expanding masters or interpreting caches.
  factory AiNativeSymbols.decode({required AiNativeArtworkResources artworkResources}) => _nativeSymbols(artworkResources);

  /// Freezes the complete source inventory and its reference associations.
  AiNativeSymbols._({required this.artworkResources, required List<AiNativeSymbolInstance> instances}) : instances = List.unmodifiable(instances);

  /// Includes ambiguous and conditional instances that may refer to this master.
  List<AiNativeSymbolInstance> instancesOf({required AiNativeArtworkResource definition}) {
    if (!artworkResources.resources.contains(definition) || definition.kind != AiNativeArtworkResourceKind.symbol) {
      throw ArgumentError('Symbol lookup requires a current symbol declaration.');
    }
    return List.unmodifiable(instances.where((instance) => instance.candidates.contains(definition)));
  }

  /// Returns references lexically stored in one setup artwork declaration.
  ///
  /// This is an inventory, not proof that the declaration is safe to execute or
  /// edit. Unknown fields may carry additional dependencies.
  List<AiNativeSymbolInstance> referencesIn({required AiNativeArtworkResource resource}) {
    if (!artworkResources.resources.contains(resource)) {
      throw ArgumentError('Symbol dependency lookup requires a current artwork declaration.');
    }
    return List.unmodifiable(instances.where((instance) => identical(instance.resource, resource)));
  }
}
