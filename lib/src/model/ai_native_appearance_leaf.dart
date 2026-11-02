part of 'package:aikit/src/model/ai_native_records.dart';

/// Complete editable native data inside an independently styled group wrapper.
sealed class AiNativeAppearanceLeafDefinition {
  /// Keeps authoring restricted to explicit format-owned value types.
  const AiNativeAppearanceLeafDefinition();
}

/// A literal symbol reference placed in its producer-relative coordinate basis.
final class AiNativeAppearanceSymbolDefinition extends AiNativeAppearanceLeafDefinition {
  /// Exact declared master name, independent of wrapper identity.
  final List<int> nameBytes;

  /// Explicit nonsingular relative matrix; the host owns coordinate conversion.
  final List<double> relativeTransform;

  /// Captures one immutable static instance without deriving its printing view.
  AiNativeAppearanceSymbolDefinition({required List<int> nameBytes, required List<double> relativeTransform})
    : nameBytes = List.unmodifiable(nameBytes),
      relativeTransform = List.unmodifiable(relativeTransform) {
    if (nameBytes.isEmpty || nameBytes.any((byte) => byte < 0 || byte > 255) || relativeTransform.length != 6 || relativeTransform.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('Symbol instances require a literal name and six portable matrix components.');
    }
    final double determinant = relativeTransform[0] * relativeTransform[3] - relativeTransform[1] * relativeTransform[2];
    if (!determinant.isFinite || determinant == 0) {
      throw ArgumentError('Symbol instances require a nonsingular relative matrix.');
    }
  }
}

/// Original process samples placed independently of the compatibility raster.
final class AiNativeAppearanceRasterDefinition extends AiNativeAppearanceLeafDefinition {
  /// Original image planes and pixel placement, without wrapper attributes.
  final AiNativeRasterDefinition definition;

  /// Retains immutable pixels; object attributes belong to the enclosing group.
  AiNativeAppearanceRasterDefinition({required this.definition}) {
    final AiNativeImageAttributes attributes = definition.attributes;
    if (definition.stencilColor != null ||
        attributes.nameBytes != null ||
        attributes.identifierBytes != null ||
        attributes.hidden ||
        attributes.locked ||
        attributes.opacity != 1 ||
        attributes.transparency != null ||
        attributes.overprint) {
      throw ArgumentError('Appearance images require process pixels with attributes on their group wrapper.');
    }
  }
}

/// Complete editable mesh cells, separate from the host-composed printing view.
final class AiNativeAppearanceMeshDefinition extends AiNativeAppearanceLeafDefinition {
  /// Explicit native geometry, colors, weights and patch topology.
  final AiNativeMeshDefinition definition;

  /// Retains the existing bounded immutable mesh authoring contract.
  const AiNativeAppearanceMeshDefinition({required this.definition});
}

/// Editable shape parameters and their matching host-supplied contour.
final class AiNativeAppearanceShapeDefinition extends AiNativeAppearanceLeafDefinition {
  /// Complete process-painted geometry without a second object identity.
  final AiNativePathDefinition definition;

  /// Native handler parameters; the package does not derive the contour.
  final AiNativeShapeParameters parameters;

  /// Explicit retained frame angle, when authored by the host.
  final double? rotationRadians;

  /// Requires geometry and parameters to describe the same open/closed family.
  AiNativeAppearanceShapeDefinition({required this.definition, required this.parameters, this.rotationRadians}) {
    _nativeShapeAuthoring(parameters, definition.artwork.closed, rotationRadians);
    if (definition.identifierBytes != null || definition.nameBytes != null) {
      throw ArgumentError('Appearance shape names and identities belong to their group wrapper.');
    }
  }
}

/// A qualified single-family payload in an independently owned native group.
final class AiNativeAppearanceLeaf {
  /// Source wrapper owning the payload's name, identity, style and masks.
  final AiNativeGroup group;

  /// Original process image, absent for other native families.
  final AiNativeRaster? raster;

  /// Complete native mesh packet, absent for other native families.
  final AiNativeMesh? mesh;

  /// Live shape retaining both its contour and parameter dictionary.
  final AiLiveShape? shape;

  /// Global ATE frame reference, with its owned confinement when present.
  final AiNativeContainer? text;

  /// Literal native symbol reference with separately qualified master ownership.
  final AiNativeContainer? symbol;

  /// Exact commands whose payload is qualified independently of scalar state.
  final List<AiNativeInstruction> _commands;

  /// Owns a checked source view without copying binary data or composing ink.
  AiNativeAppearanceLeaf._({required this.group, this.raster, this.mesh, this.shape, this.text, this.symbol, required List<AiNativeInstruction> commands}) : _commands = List.unmodifiable(commands);

  /// Inspects one wrapper, returning null for ordinary path/group content.
  static AiNativeAppearanceLeaf? read({required AiNativeDrawing drawing, required AiNativeGroup group}) => _readNativeAppearanceLeaf(drawing, group);
}

/// Serializes the existing native family grammar inside a private or local group.
void _writeNativeAppearanceLeaf(_NativeDocumentBytes output, AiNativeDrawing drawing, AiNativeAppearanceLeafDefinition leaf, {required bool private}) {
  final String prefix = private ? '%_' : '';
  final int maximum = drawing.records.program.limits.maxDecodedBytes;

  /// Prefixes only generated textual source, never binary image bytes.
  void lines(List<int> bytes) {
    for (final String line in latin1.decode(bytes).split('\n')) {
      if (line.isNotEmpty) {
        output.text('$prefix${line.startsWith('%_') ? line.substring(2) : line}\n');
      }
    }
  }

  if (leaf is! AiNativeAppearanceShapeDefinition) {
    for (final String state in ['0 A', '0 Xw', '0 Ap', '0 D', '0 XR', '0 O', '0 R', '0 1 0 0 0 Xy']) {
      output.text('$prefix$state\n');
    }
  }
  switch (leaf) {
    case AiNativeAppearanceSymbolDefinition():
      output.text('$prefix/SymbolInstance : ');
      output.add(_nativeLiteralString(leaf.nameBytes, maximum));
      output.text(' /SymbolRef ,\n$prefix${leaf.relativeTransform.join(' ')} /RTransformMatrix , ;\n');
    case AiNativeAppearanceRasterDefinition():
      output.text(prefix);
      output.add(_nativeRasterBytes(leaf.definition.samples, leaf.definition.matrix, prefix, maximum));
      output.text('\n');
    case AiNativeAppearanceMeshDefinition():
      lines(_nativeMeshDefinitionBytes(leaf.definition, maximum));
    case AiNativeAppearanceShapeDefinition():
      lines(_createdNativePathBytes(drawing, leaf.definition));
      output.text('$prefix/ArtDictionary :\n$prefix/Dictionary :\n$prefix(${leaf.parameters.handler}) /UnicodeString (ai::LiveShape::HandlerName) ,\n$prefix');
      output.text(_nativeShapeParametersSource(leaf.parameters, prefix: prefix));
      output.text(' (ai::LiveShape::Params) ,\n$prefix; (ai::LiveShape) ,\n');
      if (leaf.rotationRadians case final double angle) {
        output.text('$prefix($angle) /String (BBAccumRotation) ,\n');
      }
      output.text('$prefix;\n');
  }
}
