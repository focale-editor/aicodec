part of 'package:aikit/src/model/ai_native_records.dart';

/// A path or group together with its directly attached native object dictionary.
///
/// Metadata ownership does not qualify the artwork's geometry or appearance.
/// Private shapes, compounds and opaque dictionaries retain separate contracts.
final class AiNativeObject extends AiNativeItem {
  /// Original path or group handle belonging to the drawing snapshot.
  final AiNativeItem source;

  /// Lexical artwork ownership, before the optional postfix dictionary.
  final AiNativeStructureNode node;

  /// Direct postfix dictionary, including preserved unknown fields.
  final AiNativeContainer? dictionary;

  /// Saved XML identity when the dictionary contains exactly one such field.
  final AiNativeObjectIdentifier? identifier;

  /// Existing name fields, retaining their native types and raw string bytes.
  final List<AiNativeEntry> names;

  /// Explains metadata that cannot participate in ordinary object lifecycle edits.
  final String? bindingIssue;

  /// Freezes a source association without inventing names or object identities.
  AiNativeObject._({
    required super.start,
    required super.end,
    required this.source,
    required this.node,
    required this.dictionary,
    required this.identifier,
    required List<AiNativeEntry> names,
    required this.bindingIssue,
  }) : names = List.unmodifiable(names);
}

/// Immutable path/group metadata ownership, separate from layer-header metadata.
final class AiNativeObjects {
  /// Drawing snapshot owning every indexed handle and source byte.
  final AiNativeDrawing drawing;

  /// Shared structural identities and version memberships used by the inventory.
  final AiNativeStructure structure;

  /// Paths and groups in source order, including unsupported object families.
  final List<AiNativeObject> objects;

  /// Artwork identities used for exact-handle lookup.
  final Map<AiNativeItem, AiNativeObject> _sources;

  /// Bound dictionaries indexed by their original source boundary.
  final Map<int, AiNativeObject> _dictionaries;

  /// Reuses the drawing's bounded immutable metadata snapshot.
  factory AiNativeObjects.decode({required AiNativeDrawing drawing}) => drawing._objects;

  /// Retains exact associations without assigning arbitrary neighboring records.
  AiNativeObjects._({required this.drawing, required this.structure, required List<AiNativeObject> objects})
    : objects = List.unmodifiable(objects),
      _sources = Map.unmodifiable({for (final AiNativeObject object in objects) object.source: object}),
      _dictionaries = Map.unmodifiable({
        for (final AiNativeObject object in objects)
          if (object.dictionary != null) object.dictionary!.start: object,
      });

  /// Looks up an exact owned path/group, rejecting foreign or stale handles.
  AiNativeObject forSource(AiNativeItem source) => _sources[source] ?? (throw ArgumentError('The artwork does not belong to this native object inventory.'));
}
