part of 'package:aicodec/src/model/ai_native_records.dart';

/// Finds setup resources while excluding embedded documents and procedures.
List<AiNativeGradientDefinition> _readGradientResources(AiNativeRecords records) {
  final _NativeRecordProjection projection = records._projection;
  final List<AiToken> tokens = projection.tokens;
  final List<AiNativeGradientDefinition> result = [];
  int procedure = 0;
  int embedded = 0;
  int rootIndex = 0;
  for (int index = 0; index < tokens.length && tokens[index].start < records.program.bodyStart; index++) {
    final AiToken token = tokens[index];
    while (rootIndex < records.roots.length && records.roots[rootIndex].end <= token.start) {
      rootIndex++;
    }
    if (rootIndex < records.roots.length && token.start >= records.roots[rootIndex].start) {
      continue;
    }
    if (token.kind == .procedureStart) {
      procedure++;
    } else if (token.kind == .procedureEnd) {
      procedure--;
    }
    if (procedure != 0 || token.kind != .comment) {
      continue;
    }
    if (token.lexeme.startsWith('%%BeginDocument')) {
      embedded++;
    } else if (token.lexeme == '%%EndDocument') {
      embedded--;
    }
    if (embedded != 0 || !token.lexeme.startsWith('%AI5_BeginGradient:')) {
      continue;
    }
    final List<AiToken> content = [];
    int end = index + 1;
    while (end < tokens.length && tokens[end].lexeme != '%AI5_EndGradient') {
      final AiToken next = tokens[end++];
      if (next.start >= records.program.bodyStart || next.kind == .comment && next.lexeme.startsWith('%AI5_BeginGradient:')) {
        throw const FormatException('Unterminated or nested native gradient definition.');
      }
      if (next.kind == .comment && (next.lexeme.startsWith('%AI') || next.lexeme.startsWith('%%'))) {
        throw const FormatException('Unsupported metadata inside a native gradient definition.');
      }
      if (next.kind != .comment) {
        content.add(next);
      }
    }
    if (end == tokens.length || tokens[end].start >= records.program.bodyStart) {
      throw const FormatException('Missing native gradient end marker.');
    }
    try {
      final AiNativeGradientDefinition definition = _readGradientDefinition(content, projection);
      final List<AiToken> name = AiPostScript.tokenize(
        latin1.encode(token.lexeme.substring('%AI5_BeginGradient:'.length)),
        maxBytes: records.program.limits.maxDecodedBytes,
        maxTokens: records.program.limits.maxTokens,
        maxDepth: records.program.limits.maxDepth,
      );
      if (name.length != 1 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(name.single.kind) || !_gradientBytesEqual(aiStringBytes(name.single), definition.nameBytes)) {
        throw const FormatException('Gradient comment and resource names differ.');
      }
      result.add(definition);
    } on ArgumentError catch (error) {
      throw FormatException('Invalid native gradient resource: $error');
    }
    index = end;
  }
  return result;
}

/// Parses the mark-based gradient grammar without treating marks as arrays.
AiNativeGradientDefinition _readGradientDefinition(List<AiToken> tokens, _NativeRecordProjection projection) {
  AiNativeInstruction? opening;
  AiNativeInstruction? closing;
  final List<AiNativeGradientRamp> ramps = [];
  final List<AiNativeGradientStop> native = [];
  final List<AiNativeGradientStop> fallback = [];
  final List<AiNativeGradientStop> legacy = [];
  final List<AiToken> pending = [];
  int marks = 0;
  bool readingStops = false;
  for (final AiToken token in tokens) {
    if (closing != null) {
      throw const FormatException('Unexpected data after native gradient termination.');
    }
    if (token.kind == .arrayStart) {
      if (opening == null || pending.isNotEmpty || readingStops || ++marks > 2 || marks == 2 && ramps.isEmpty) {
        throw const FormatException('Invalid native gradient mark.');
      }
      continue;
    }
    if (const {AiTokenKind.number, AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind)) {
      pending.add(token);
      continue;
    }
    if (token.kind != .executableName) {
      throw const FormatException('Unsupported native gradient operand syntax.');
    }
    final AiNativeInstruction command = AiNativeInstruction._(token: token, operands: pending, isPrivate: projection.isPrivate(token.start));
    pending.clear();
    final List<AiToken> operands = command.operands;
    if (token.lexeme == 'Bd') {
      if (opening != null ||
          operands.length != 3 ||
          !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands[0].kind) ||
          !const {0, 1}.contains(operands[1].number) ||
          operands[2].number == null ||
          operands[2].number! < 2 ||
          operands[2].number! % 1 != 0) {
        throw const FormatException('Invalid native gradient header.');
      }
      opening = command;
      continue;
    }
    if (opening == null || marks == 0) {
      throw const FormatException('Native gradient data precedes its header or mark.');
    }
    switch (token.lexeme) {
      case 'Br':
        if (readingStops || marks != 1) {
          throw const FormatException('Native gradient ramps follow color stops.');
        }
        ramps.add(_readGradientRamp(operands));
      case 'Bs' || 'BS':
        if (ramps.isNotEmpty && marks != 2) {
          throw const FormatException('Native gradient stops have no separate mark.');
        }
        final AiNativeGradientStop stop = _readGradientStop(operands);
        readingStops = true;
        if (token.lexeme == 'BS') {
          fallback.add(stop);
        } else if (projection.isPrivate(operands.first.start)) {
          native.add(stop);
        } else {
          legacy.add(stop);
        }
      case 'BD':
        if (operands.isNotEmpty || !readingStops) {
          throw const FormatException('Invalid native gradient ending.');
        }
        closing = command;
      default:
        throw FormatException('Unsupported native gradient operator ${token.lexeme}.');
    }
  }
  if (opening == null || closing == null || pending.isNotEmpty) {
    throw const FormatException('Incomplete native gradient definition.');
  }
  final int expected = opening.operands[2].number!.toInt();
  final List<AiNativeGradientStop> stops = native.isNotEmpty
      ? native
      : legacy.isNotEmpty
      ? legacy
      : fallback;
  if (stops.length != expected ||
      [native, legacy, fallback].any((list) => list.isNotEmpty && list.length != expected) ||
      native.isNotEmpty && legacy.isNotEmpty ||
      ramps.isNotEmpty && ramps.length != expected - 1) {
    throw const FormatException('Native gradient stop or ramp counts do not match the header.');
  }
  return AiNativeGradientDefinition._(
    opening: opening,
    closing: closing,
    stops: stops,
    fallbackStops: native.isNotEmpty ? fallback : [],
    ramps: ramps,
    hasPairedStops: native.isNotEmpty && fallback.isNotEmpty,
    usesPrivateStops: native.isNotEmpty,
  );
}

/// Reads process, custom and named stop colors with one optional opacity wrapper.
AiNativeGradientStop _readGradientStop(List<AiToken> tokens) {
  if (tokens.length < 4) {
    throw const FormatException('Truncated native gradient stop.');
  }
  final double position = _gradientNumber(tokens.last);
  final double midpoint = _gradientNumber(tokens[tokens.length - 2]);
  int style = _gradientInteger(tokens[tokens.length - 3]);
  final bool hasOpacity = style == 6;
  int end = tokens.length - 3;
  double opacity = 1;
  if (hasOpacity) {
    if (end < 3) {
      throw const FormatException('Truncated native gradient opacity.');
    }
    opacity = _gradientNumber(tokens[--end]);
    style = _gradientInteger(tokens[--end]);
  }
  final AiNativeGradientColorKind kind = switch (style) {
    0 => .gray,
    1 => .cmyk,
    2 => .rgb,
    3 => .customCmyk,
    4 => .customRgb,
    5 when end > 0 && tokens[end - 1].number == 0 => .namedCmyk,
    5 when end > 0 && tokens[end - 1].number == 1 => .namedRgb,
    _ => throw const FormatException('Unsupported native gradient color style.'),
  };
  final bool named = style >= 3;
  Uint8List? name;
  double? tint;
  if (named) {
    if (style >= 4) {
      if (end == 0 || tokens[end - 1].number != (kind == .namedCmyk ? 0 : 1)) {
        throw const FormatException('Invalid native gradient color type.');
      }
      end--;
    }
    if (end < 2 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(tokens[end - 2].kind)) {
      throw const FormatException('Invalid named gradient color.');
    }
    tint = _gradientNumber(tokens[--end]);
    name = aiStringBytes(tokens[--end]);
  }
  return AiNativeGradientStop(
    color: AiNativeGradientColor(kind: kind, components: tokens.take(end).map(_gradientNumber).toList(), nameBytes: name, tint: tint),
    position: position,
    midpoint: midpoint,
    opacity: opacity,
    hasOpacity: hasOpacity,
  );
}

/// Reads retained constant or byte-sampled native printing channels.
AiNativeGradientRamp _readGradientRamp(List<AiToken> tokens) {
  if (tokens.isEmpty) {
    throw const FormatException('Missing native gradient ramp type.');
  }
  final int type = _gradientInteger(tokens.last);
  if (type < 0 || type >= AiNativeGradientRampKind.values.length) {
    throw const FormatException('Unknown native gradient ramp type.');
  }
  return AiNativeGradientRamp(
    kind: AiNativeGradientRampKind.values[type],
    channels: [
      for (final AiToken token in tokens.take(tokens.length - 1))
        if (token.kind == .number)
          AiNativeGradientChannel.constant(value: _gradientNumber(token))
        else if (const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind))
          AiNativeGradientChannel.samples(values: aiStringBytes(token))
        else
          throw const FormatException('Invalid native gradient ramp channel.'),
    ],
  );
}

/// Requires a finite native numeric operand.
double _gradientNumber(AiToken token) => token.number?.toDouble() ?? (throw const FormatException('Expected a numeric gradient operand.'));

/// Requires an exact integer without rounding fractional native fields.
int _gradientInteger(AiToken token) {
  final double value = _gradientNumber(token);
  if (value % 1 != 0 || value.abs() > 9007199254740991) {
    throw const FormatException('Expected an integer gradient operand.');
  }
  return value.toInt();
}

/// Compares native names without assuming a string encoding or allocating keys.
bool _gradientBytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
