part of 'package:aikit/src/model/ai_native_records.dart';

/// Serializes mask-local vector authoring without inventing resource identities.
Uint8List _createdNativeOpacityMaskArtwork(AiNativeRecords records, List<AiNativeAppearanceElementDefinition> elements, bool private) {
  final AiNativeDrawing drawing = AiNativeDrawing.decode(records: records);
  final AiNativeLimits limits = records.program.limits;
  final _NativeDocumentBytes output = _NativeDocumentBytes(maximum: limits.maxDecodedBytes);
  final String prefix = private ? '%_' : '';
  int nodes = 0;
  output.text('X=\n');

  /// Preserves escaped names while converting only the generated line prefixes.
  void lines(List<int> bytes) {
    for (final String line in latin1.decode(bytes).split('\n')) {
      if (line.isNotEmpty) {
        output.text('$prefix${line.startsWith('%_') ? line.substring(2) : line}\n');
      }
    }
  }

  /// Applies the same byte/depth budget to masks and ordinary descendants.
  void enter(int depth) {
    if (++nodes > limits.maxTokens || depth > limits.maxDepth) {
      throw const AiLimitException(message: 'Mask vector artwork exceeds native structure limits.');
    }
  }

  /// Emits one path with its explicit paints or independent clipping role.
  void path(AiNativePathDefinition definition, {AiNativePathMask mask = .none}) {
    if (definition.identifierBytes != null) {
      throw UnsupportedError('Mask authoring identities require reference-aware lifecycle changes.');
    }
    lines(_createdNativePathBytes(drawing, definition, mask: mask));
  }

  /// Keeps ordinary grouping distinct from named group appearance composition.
  void write(AiNativeAppearanceElementDefinition element, int depth) {
    enter(depth);
    switch (element) {
      case AiNativeAppearancePathDefinition():
        path(element.definition);
      case AiNativeAppearanceGroupDefinition():
        if (element.styleNameBytes != null || element.identifierBytes != null) {
          throw UnsupportedError('Mask groups require local artwork without named styles or XML identities.');
        }
        output.text('$prefix${element.locked ? 1 : 0} A\n$prefix${element.hidden ? 1 : 0} Xw\n$prefix${element.clip == null ? 'u' : 'q'}\n');
        if (element.clip case final AiNativeAppearanceClipDefinition clip) {
          enter(depth + 1);
          path(
            AiNativePathDefinition(
              artwork: AiArtworkPath(segments: clip.segments, closed: clip.mask == .closed, evenOdd: clip.evenOdd),
              bounds: AiBoundingBox(left: 0, bottom: 0, right: 0, top: 0),
              counted: clip.counted,
              nameBytes: clip.nameBytes,
              identifierBytes: clip.identifierBytes,
            ),
            mask: clip.mask,
          );
        }
        for (final AiNativeAppearanceElementDefinition child in element.children) {
          write(child, depth + 1);
        }
        output.text('$prefix${element.clip == null ? 'U' : 'Q'}\n');
        lines(_createdNativeMetadata(drawing, element.nameBytes, null, '\n'));
    }
  }

  for (final AiNativeAppearanceElementDefinition element in elements) {
    write(element, 1);
  }
  output.text('${prefix}X+');
  return output.takeBytes().asUnmodifiableView();
}
