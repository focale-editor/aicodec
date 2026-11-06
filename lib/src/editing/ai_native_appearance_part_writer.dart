part of 'package:illustratorkit/src/model/ai_native_records.dart';

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

  if (definition.effect case final AiNativeEffect effect) {
    text(
      '/BasicFilter : (${effect.kind.plugin}) 1 0 /Filter , ${definition.visible ? 1 : 0} /Visible , (${_artboardStylePlugins[effect.kind.plugin]}) /PluginFileName , /Dictionary : /NotRecorded , ',
    );
    for (final MapEntry<String, double> field in effect.realParameters.entries) {
      text('${field.value} /Real (${field.key}) , ');
    }
    for (final MapEntry<String, int> field in effect.integerParameters.entries) {
      text('${field.value} /Int (${field.key}) , ');
    }
    for (final MapEntry<String, bool> field in effect.booleanParameters.entries) {
      text('${field.value ? 1 : 0} /Bool (${field.key}) , ');
    }
    if (effect.color case final AiColor color) {
      final String operator = switch (color.space) {
        .gray => 'g',
        .rgb => 'Xa',
        .cmyk => 'k',
      };
      text('/FillStyle : 0 O ${color.channels.join(' ')} $operator 0 1 0 0 0 Xy 0 XR 0 1 Xd /Def ; (sclr) , ');
    }
    text('; /Dict , ;');
    return output.takeBytes();
  }
  final bool compound = definition.kind == .stack || definition.kind == .chain;
  final bool calligraphic = definition.kind == .calligraphic;
  final bool artworkBrush = definition.kind == .artworkBrush;
  final bool offset = definition.kind == .stroke && definition.strokeAlignment != .center;
  final String filter = switch (definition.kind) {
    .stack => 'Stack Style Filter',
    .chain => 'Chain Style Filter',
    .fill => 'Fill Style Filter',
    .calligraphic => 'Adobe Calligraphic Brush Tool',
    .artworkBrush => definition.artworkBrush!.kind.plugin,
    .stroke => offset ? 'Adobe Stroke Offset' : 'Stroke Style Filter',
    .conduit => 'Conduit Filter',
    .blend => 'Blend Style Filter',
    _ => throw ArgumentError('Unsupported created appearance part.'),
  };
  text('/${compound ? 'CompoundFilter' : 'BasicFilter'} : ($filter) ${offset || calligraphic || artworkBrush ? 1 : 0} 0 /Filter , ${definition.visible ? 1 : 0} /Visible , ');
  if (compound) {
    for (final AiNativeAppearanceChild child in definition.children) {
      append(childBytes(child));
      text(' /Part ,\n${private ? '%_' : ''}');
    }
  } else if (definition.kind == .blend) {
    text('/Dictionary : /NotRecorded , /BlendStyle : ${definition.transparency!.operands.join(' ')} Xy /Def ; (BlendStyle) , ; /Dict , ');
  } else if (definition.kind != .conduit) {
    final bool stroke = definition.kind == .stroke || calligraphic || artworkBrush;
    if (stroke) {
      if (calligraphic) {
        text('(CalligraphicBrushTool.aip) /PluginFileName , ');
      }
      if (artworkBrush) {
        text('(${definition.artworkBrush!.kind == .art ? 'ArtOnPath' : 'PatternOnPath'}BrushTool.aip) /PluginFileName , ');
      }
      if (offset) {
        text('(StrokeOffset.aip) /PluginFileName , ');
      }
      text('2 /FillOrStroke , ');
    }
    text('/Dictionary : /NotRecorded , ');
    if (definition.calligraphic case final AiNativeCalligraphicPaint nib) {
      text('/GObjRef : ');
      append(_nativeLiteralString(nib.brushNameBytes, limits.maxDecodedBytes));
      text(' (Adobe Calligraphic Brush Tool) /PluginObject ; (Brush) , ');
      text('${nib.angle} /Real (Angle) , ${nib.diameter} /Real (Diameter) , ${nib.roundness} /Real (Roundness) , ');
      text('0 /Real (AngleVariation) , 0 /Real (DiameterVariation) , 0 /Real (RoundnessVariation) , ');
      text('0 /Int (AngleDependsOn) , 0 /Int (DiameterDependsOn) , 0 /Int (RoundnessDependsOn) , 0 /Int (AngleRelativeTo) , ');
      append(_nativeLiteralString(nib.brushNameBytes, limits.maxDecodedBytes));
      text(' /String (DisplayString) , ');
    }
    if (definition.artworkBrush case final AiNativeArtworkBrushPaint brush) {
      text('/GObjRef : ');
      append(_nativeLiteralString(brush.brushNameBytes, limits.maxDecodedBytes));
      text(' (${brush.kind.plugin}) /PluginObject ; (Brush) , ');
      text('${brush.scaling} /Real (Scaling) , ${brush.spacing} /Real (Spacing) , ');
      text('${brush.scaling} /Real (MinScaling) , ${brush.scaling} /Real (MaxScaling) , ');
      text('0 /Int (ScaleYDependsOn) , 1 /Int (Colorization) , 0 /Int (UpsideDown) , 0 /Int (Counterclockwise) , ${brush.adjustment} /Int (Adjustment) , ');
      text('0 /Real (StartSegmentLength) , 0 /Real (EndSegmentLength) , 0 /Bool (Segmented) , 1 /Bool (FoldAdjustment) , 0 /Bool (Proportional) , ');
      append(_nativeLiteralString(brush.brushNameBytes, limits.maxDecodedBytes));
      text(' /String (DisplayString) , ');
    }
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
    } else if (definition.gradient == null) {
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
    text('${stroke ? '1 0' : '0 1'} Xd ');
    if (definition.gradient case final AiNativeGradientPaint gradient) {
      append(gradient._bytes(stroke: stroke, limit: limits.maxDecodedBytes));
      text(' ');
    }
    text('/Def ; (${stroke ? 'StrokeStyle' : 'FillStyle'}) , ; /Dict , ');
  }
  text(';');
  return output.takeBytes();
}
