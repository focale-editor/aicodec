part of 'package:aikit/src/model/ai_native_records.dart';

/// Native named-ink layouts, retaining their different saved alternatives.
enum AiNativeNamedColorKind {
  /// Legacy custom CMYK ink written by x/X.
  legacyCmyk,

  /// Generic CMYK custom ink written by Xx/XX with selector zero.
  customCmyk,

  /// Generic RGB custom ink written by Xx/XX with selector one.
  customRgb,

  /// Named CMYK paint written by Xs/XS.
  namedCmyk,

  /// Named CMYK and RGB alternatives written by Xz/XZ with selector one.
  namedRgb,
}

/// A named native paint with explicit alternatives and unconverted tint semantics.
final class AiNativeNamedColor {
  /// Original native representation, not an inferred color profile.
  final AiNativeNamedColorKind kind;

  /// CMYK, RGB, or CMYK followed by RGB, according to [kind].
  final List<double> components;

  /// Exact encoded ink name, independent of palette display labels.
  final Uint8List nameBytes;

  /// Native tint operand, retained without inversion or color conversion.
  final double tint;

  /// Captures a checked immutable named ink.
  AiNativeNamedColor({required this.kind, required List<double> components, required List<int> nameBytes, required this.tint})
    : components = List.unmodifiable(components),
      nameBytes = Uint8List.fromList(nameBytes).asUnmodifiableView() {
    final int count = kind == .customRgb
        ? 3
        : kind == .namedRgb
        ? 7
        : 4;
    if (components.length != count || components.any((value) => !_gradientUnit(value)) || !_gradientUnit(tint) || nameBytes.isEmpty || nameBytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Named colors require exact unit-range alternatives, a literal byte name and a tint.');
    }
  }

  /// Reads a supported command, returning null for another paint family.
  static AiNativeNamedColor? decode({required AiNativeInstruction instruction}) {
    final List<AiToken> operands = instruction.operands;
    final AiNativeNamedColorKind kind;
    switch (instruction.operator) {
      case 'x' || 'X':
        kind = .legacyCmyk;
      case 'Xs' || 'XS':
        kind = .namedCmyk;
      case 'Xz' || 'XZ':
        if (operands.isEmpty || operands.last.number != 1) {
          throw const FormatException('Unsupported named RGB selector.');
        }
        kind = .namedRgb;
      case 'Xx' || 'XX':
        if (operands.isEmpty || !{0, 1}.contains(operands.last.number)) {
          throw const FormatException('Unsupported custom color selector.');
        }
        kind = operands.last.number == 1 ? .customRgb : .customCmyk;
      default:
        return null;
    }
    final int count = kind == .customRgb
        ? 3
        : kind == .namedRgb
        ? 7
        : 4;
    final bool selector = kind == .customCmyk || kind == .customRgb || kind == .namedRgb;
    if (operands.length != count + (selector ? 3 : 2) || operands.take(count).any((token) => token.number == null) || !_artboardPaletteName(operands[count]) || operands[count + 1].number == null) {
      throw const FormatException('Malformed named color operands.');
    }
    try {
      return AiNativeNamedColor(
        kind: kind,
        components: operands.take(count).map((token) => token.number!.toDouble()).toList(),
        nameBytes: aiStringBytes(operands[count]),
        tint: operands[count + 1].number!.toDouble(),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid named color: $error');
    }
  }

  /// Serializes literal operands without inventing alternate color components.
  List<int> _bytes({required bool stroke, required int limit}) {
    final _GradientResourceWriter writer = _GradientResourceWriter(limit: limit);
    writer.add('${components.join(' ')} ');
    writer.string(nameBytes);
    writer.add(' $tint');
    if (kind == .customCmyk || kind == .customRgb || kind == .namedRgb) {
      writer.add(kind == .customCmyk ? ' 0' : ' 1');
    }
    final String operator = switch (kind) {
      .legacyCmyk => stroke ? 'X' : 'x',
      .customCmyk || .customRgb => stroke ? 'XX' : 'Xx',
      .namedCmyk => stroke ? 'XS' : 'Xs',
      .namedRgb => stroke ? 'XZ' : 'Xz',
    };
    writer.add(' $operator');
    return writer.output.takeBytes();
  }
}

/// The named literal operators with defined fill/stroke and value semantics.
const Set<String> _nativeNamedColorOperators = {'x', 'X', 'Xx', 'XX', 'Xs', 'XS', 'Xz', 'XZ'};

/// Identifies the paint channel without conflating upper/lowercase native names.
bool _nativeNamedColorStroke(String operator) => const {'X', 'XX', 'XS', 'XZ'}.contains(operator);
