part of 'package:aikit/src/model/ai_native_records.dart';

/// Serializes explicit part data, delegating child ownership to the graph writer.
Uint8List _createdNativeAppearancePart(
  AiNativeAppearancePartDefinition definition,
  AiNativeLimits limits,
  bool private,
  Uint8List Function(AiNativeAppearanceChild child) childBytes,
) {
  final BytesBuilder output = BytesBuilder(copy: false);

  /// Bounds appended fields before retaining their complete encoded payloads.
  void append(List<int> bytes) {
    if (output.length + bytes.length > limits.maxDecodedBytes) {
      throw const AiLimitException(message: 'Created appearance parts exceed the native byte limit.');
    }
    output.add(bytes);
  }

  /// Writes fixed grammar and numeric data without changing source projection.
  void text(String value) => append(latin1.encode(value));

  final bool compound = definition.kind == .stack || definition.kind == .chain;
  final bool offset = definition.kind == .stroke && definition.strokeAlignment != .center;
  final String filter = switch (definition.kind) {
    .stack => 'Stack Style Filter',
    .chain => 'Chain Style Filter',
    .fill => 'Fill Style Filter',
    .stroke => offset ? 'Adobe Stroke Offset' : 'Stroke Style Filter',
    .conduit => 'Conduit Filter',
    .blend => 'Blend Style Filter',
    _ => throw ArgumentError('Unsupported created appearance part.'),
  };
  text('/${compound ? 'CompoundFilter' : 'BasicFilter'} : ($filter) ${offset ? 1 : 0} 0 /Filter , ${definition.visible ? 1 : 0} /Visible , ');
  if (compound) {
    for (final AiNativeAppearanceChild child in definition.children) {
      append(childBytes(child));
      text(' /Part ,\n${private ? '%_' : ''}');
    }
  } else if (definition.kind == .blend) {
    text('/Dictionary : /NotRecorded , /BlendStyle : ${definition.transparency!.operands.join(' ')} Xy /Def ; (BlendStyle) , ; /Dict , ');
  } else if (definition.kind != .conduit) {
    final bool stroke = definition.kind == .stroke;
    if (stroke) {
      if (offset) {
        text('(StrokeOffset.aip) /PluginFileName , ');
      }
      text('2 /FillOrStroke , ');
    }
    text('/Dictionary : /NotRecorded , ');
    if (!stroke) {
      text('${definition.evenOdd ? 1 : 0} /Bool (UseEvenOdd) , ');
    } else if (offset) {
      append(_nativeLiteralString(definition.alignmentLabelBytes!, limits.maxDecodedBytes));
      text(' /String (DisplayString) , ${definition.strokeAlignment == .inside ? 1 : 0} /Bool (StrokeOffsetInside) , ');
    }
    if (definition.adjustDashes case final bool adjust) {
      text('/Dictionary : /NotRecorded , 1 /Int (BSAdvStrokeDictionaryVersion) , ${adjust ? 1 : 0} /Bool (BSDashAdj) , ; (kAIBeautifulStrokesParamsDictKey) , ');
    }
    text('/${stroke ? 'StrokeStyle' : 'FillStyle'} : ${definition.overprint ? 1 : 0} ${stroke ? 'R' : 'O'} ');
    if (definition.pattern case final AiNativePatternPaint pattern) {
      append(pattern._bytes(stroke: stroke, limit: limits.maxDecodedBytes));
      text(' ');
    } else if (definition.namedColor case final AiNativeNamedColor named) {
      append(named._bytes(stroke: stroke, limit: limits.maxDecodedBytes));
      text(' ');
    } else {
      final String color = definition.colors.expand((color) => color.channels).join(' ');
      final String operator = definition.colors.length == 2
          ? (stroke ? 'XA' : 'Xa')
          : switch (definition.colors.single.space) {
              .gray => stroke ? 'G' : 'g',
              .rgb => stroke ? 'XA' : 'Xa',
              .cmyk => stroke ? 'K' : 'k',
            };
      text('$color $operator ');
    }
    final String transparency = definition.transparency?.operands.join(' ') ?? '0 ${definition.opacity} 0 0 0';
    text('$transparency Xy ${definition.evenOdd ? 1 : 0} XR ');
    if (stroke) {
      if (definition.dash.length > limits.maxTokens || definition.dash.length > limits.maxDecodedBytes ~/ 2) {
        throw const AiLimitException(message: 'Created appearance dash operands exceed native limits.');
      }
      text('${definition.lineCap} J ${definition.lineJoin} j ${definition.strokeWidth} w ${definition.miterLimit} M [${definition.dash.join(' ')}] ${definition.dashPhase} d ');
    }
    text('${stroke ? '1 0' : '0 1'} Xd /Def ; (${stroke ? 'StrokeStyle' : 'FillStyle'}) , ; /Dict , ');
  }
  text(';');
  return output.takeBytes();
}
