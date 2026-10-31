part of 'package:aikit/src/model/ai_native_records.dart';

/// Rewrites a complete global resource without leaving stale ramp alternatives.
AiNativeGradientResources _replaceGradientStops(AiNativeGradientResources resources, AiNativeGradientDefinition definition, List<AiNativeGradientStop> stops, List<AiNativeGradientRamp> ramps) {
  if (!resources.definitions.contains(definition) || stops.length < 2 || ramps.length != stops.length - 1) {
    throw ArgumentError('Expected an owned gradient, at least two stops and one ramp per interval.');
  }
  for (int index = 1; index < stops.length; index++) {
    if (stops[index].position <= stops[index - 1].position) {
      throw ArgumentError('Gradient stops must have strictly increasing positions.');
    }
  }
  final List<AiNativeGradientDefinition> targets = resources.definitions.where((candidate) => _gradientBytesEqual(candidate.nameBytes, definition.nameBytes)).toList();
  if (targets.any((target) => target.radial != definition.radial)) {
    throw const FormatException('Same-name native gradients have ambiguous linear/radial kinds.');
  }
  final List<AiSourceEdit> edits = [];
  final int limit = resources.records.program.limits.maxDecodedBytes;
  int remaining = limit - resources.records.program.bytes.length;
  for (final AiNativeGradientDefinition target in targets) {
    if (target.opening.isPrivate || target.closing.isPrivate) {
      throw UnsupportedError('Gradient editing requires ordinary Bd/BD resource boundaries.');
    }
    if (!target.usesPrivateStops && stops.any((stop) => stop.hasOpacity || stop.color.style > 4)) {
      throw UnsupportedError('Legacy gradient stops require opaque colors without newer wrappers.');
    }
    final int countDelta = stops.length.toString().length - (target.opening.operands[2].end - target.opening.operands[2].start);
    final int capacity = remaining + target.closing.start - target.opening.end - countDelta;
    final _GradientResourceWriter writer = _GradientResourceWriter(limit: capacity);
    writer.add('\n[\n');
    for (final AiNativeGradientRamp ramp in ramps) {
      for (final AiNativeGradientChannel channel in ramp.channels) {
        if (channel.constant case final double value) {
          writer.add('${value % 1 == 0 ? value.toInt() : value}\n');
        } else {
          writer.hex(channel.samples!);
          writer.add('\n');
        }
      }
      writer.add('${ramp.kind.index} %_Br\n');
    }
    writer.add('[\n');
    for (final AiNativeGradientStop stop in stops.reversed) {
      writer.stop(stop);
      writer.add(target.usesPrivateStops ? ' %_BS\n%_' : ' %_Bs\n');
      if (target.usesPrivateStops) {
        writer.stop(stop);
        writer.add(' Bs\n');
      }
    }
    final Uint8List bytes = writer.output.takeBytes();
    remaining += target.closing.start - target.opening.end - bytes.length - countDelta;
    edits.add(AiSourceEdit(start: target.opening.operands[2].start, end: target.opening.operands[2].end, bytes: latin1.encode(stops.length.toString())));
    edits.add(AiSourceEdit(start: target.opening.end, end: target.closing.start, bytes: bytes));
  }
  return AiNativeGradientResources.decode(
    records: AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: resources.records.program, edits: edits),
    ),
  );
}

/// Writes bounded ASCII syntax while avoiding unbounded intermediate hex strings.
final class _GradientResourceWriter {
  /// Maximum bytes available for this replacement within the whole program.
  final int limit;

  /// Accumulated checked bytes.
  final BytesBuilder output = BytesBuilder(copy: false);

  /// Creates a writer constrained by the remaining native-program budget.
  _GradientResourceWriter({required this.limit});

  /// Checks expansion before appending ASCII syntax.
  void add(String text) {
    if (text.length > limit - output.length) {
      throw const FormatException('Gradient replacement exceeds the native output limit.');
    }
    output.add(latin1.encode(text));
  }

  /// Encodes a native byte string in small hexadecimal chunks.
  void hex(List<int> bytes) {
    if (bytes.length > (limit - output.length - 2) ~/ 2) {
      throw const FormatException('Gradient string exceeds the native output limit.');
    }
    add('<');
    for (int index = 0; index < bytes.length; index += 32) {
      final int end = index + 32 < bytes.length ? index + 32 : bytes.length;
      add(bytes.sublist(index, end).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join());
    }
    add('>');
  }

  /// Writes conventional native color names with byte-exact octal escaping.
  void string(List<int> bytes) {
    if (bytes.length > (limit - output.length - 2) ~/ 4) {
      throw const FormatException('Gradient name exceeds the native output limit.');
    }
    add('(');
    for (int index = 0; index < bytes.length; index += 32) {
      final int end = index + 32 < bytes.length ? index + 32 : bytes.length;
      add(bytes.sublist(index, end).map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join());
    }
    add(')');
  }

  /// Writes complete color, optional opacity, midpoint and position operands.
  void stop(AiNativeGradientStop stop) {
    final AiNativeGradientColor color = stop.color;
    for (final double component in color.components) {
      add('$component ');
    }
    if (color.nameBytes case final Uint8List name) {
      string(name);
      add(' ${color.tint} ');
      if (color.style >= 4) {
        add(color.kind == .namedCmyk ? '0 ' : '1 ');
      }
    }
    add('${color.style} ');
    if (stop.hasOpacity) {
      add('${stop.opacity} 6 ');
    }
    add('${stop.midpoint} ${stop.position}');
  }
}
