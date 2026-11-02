part of 'package:aikit/src/model/ai_native_records.dart';

/// Native descriptor namespaces, separate from brush artwork declarations.
enum AiNativeBrushKind {
  /// Version-one elliptical nib settings.
  calligraphic,

  /// Version-two artwork stretched along a path.
  art,

  /// Version-two repeated artwork and corner tiles.
  pattern,

  /// Version-zero settings referencing a built-in bristle library.
  bristle;

  /// Exact producer plug-in identity of this descriptor family.
  String get plugin => switch (this) {
    .calligraphic => 'Adobe Calligraphic Brush Tool',
    .art => 'Adobe ArtOnPath Brush Tool',
    .pattern => 'Adobe PatternOnPath Brush Tool',
    .bristle => 'Adobe dBrush Brush Tool',
  };
}

/// Qualified immutable descriptor with its complete original source span.
final class AiNativeBrushDescriptor {
  /// Exact plug-in namespace, independent of the display name.
  final String plugin;

  /// Literal resource name without PostScript escaping.
  final Uint8List nameBytes;

  /// Concatenated literal continuation fragments, without interpreting geometry.
  final Uint8List payloadBytes;

  /// Inclusive original declaration start.
  final int start;

  /// Exclusive original declaration end.
  final int end;

  /// Native brush family; null only for the internally retained panel inventory.
  AiNativeBrushKind? get kind => AiNativeBrushKind.values.where((kind) => kind.plugin == plugin).singleOrNull;

  /// Freezes payload bytes while keeping exact source ownership.
  AiNativeBrushDescriptor._({required this.plugin, required List<int> nameBytes, required List<int> payloadBytes, required this.start, required this.end})
    : nameBytes = Uint8List.fromList(nameBytes).asUnmodifiableView(),
      payloadBytes = Uint8List.fromList(payloadBytes).asUnmodifiableView();
}

/// Qualified brush descriptors, their native panel and immutable lifecycle edits.
///
/// Artwork resources remain owned by [AiNativeArtworkResources]. Creating a
/// descriptor does not generate an applied brush, printing artwork or a preview.
final class AiNativeBrushes {
  /// Source structure owning every returned descriptor handle.
  final AiNativeStructure structure;

  /// Brush definitions in their original declaration order.
  final List<AiNativeBrushDescriptor> brushes;

  /// Explicit panel entries in saved order; absent panels yield an empty list.
  final List<AiNativeBrushDescriptor> order;

  /// Source-owned optional manager declaration, kept separate from brushes.
  final AiNativeBrushDescriptor? _panel;

  /// Reads supported literal descriptors and resolves their artwork references.
  ///
  /// Unknown, conditional, executable and ambiguous declarations reject. The
  /// original source remains available through [structure], unchanged.
  factory AiNativeBrushes.decode({required AiNativeStructure structure}) {
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: structure.drawing);
    final _ArtboardResourceScope resources = _artboardResourceScope(layers);
    final List<AiNativeBrushDescriptor> values = [];
    _artboardBrushScope(layers, resources.brushes, inspect: values.add);
    final AiNativeBrushDescriptor? panel = values.where((value) => value.kind == null).singleOrNull;
    final List<AiNativeBrushDescriptor> brushes = values.where((value) => value.kind != null).toList();
    final List<String> names = panel == null ? [] : latin1.decode(panel.payloadBytes).split('/').map((name) => name.trim()).toList();
    return AiNativeBrushes._(
      structure: structure,
      brushes: brushes,
      panel: panel,
      order: [for (int index = 0; index < names.length - 1; index += 2) brushes.singleWhere((value) => value.plugin == names[index] && latin1.decode(value.nameBytes) == names[index + 1])],
    );
  }

  /// Retains immutable lists and source handles after qualification.
  AiNativeBrushes._({required this.structure, required List<AiNativeBrushDescriptor> brushes, required List<AiNativeBrushDescriptor> order, required this._panel})
    : brushes = List.unmodifiable(brushes),
      order = List.unmodifiable(order);

  /// Creates a fresh descriptor and optionally appends it to the native panel.
  ///
  /// Payload bytes must follow the qualified versioned layout for [kind]. All
  /// referenced art/pattern tiles must already exist in the brush-art namespace.
  /// Listed names cannot contain slashes or leading/trailing whitespace because
  /// the native panel stores delimiter-separated names without an escape grammar.
  AiNativeBrushes create({required AiNativeBrushKind kind, required List<int> nameBytes, required List<int> payloadBytes, bool listed = true}) =>
      _createNativeBrush(this, kind, nameBytes, payloadBytes, listed);

  /// Revises an unused descriptor without changing its name or panel position.
  ///
  /// Referenced descriptors require a synchronized appearance transaction; this
  /// method refuses them even when an unused style owns the reference.
  AiNativeBrushes replaceUnused({required AiNativeBrushDescriptor brush, required List<int> payloadBytes}) => _replaceUnusedNativeBrush(this, brush, payloadBytes);

  /// Removes unused descriptors and their panel entries as one atomic edit.
  AiNativeBrushes remove({required List<AiNativeBrushDescriptor> brushes}) => _removeNativeBrushes(this, brushes);

  /// Reorders or changes panel membership without modifying brush definitions.
  ///
  /// Every selected handle must belong to this snapshot; unlisted definitions
  /// remain available to existing appearances.
  AiNativeBrushes setOrder({required List<AiNativeBrushDescriptor> brushes}) => _orderNativeBrushes(this, brushes);
}
