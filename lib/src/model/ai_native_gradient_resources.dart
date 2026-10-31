part of 'package:aikit/src/model/ai_native_records.dart';

/// Native color models, including named colors and their retained alternatives.
enum AiNativeGradientColorKind {
  /// One gray component.
  gray,

  /// Four process ink components.
  cmyk,

  /// Three RGB components with an explicit four-component CMYK alternative.
  rgb,

  /// A custom CMYK ink with a native name and tint.
  customCmyk,

  /// A custom RGB ink with a native name, tint and CMYK alternative.
  customRgb,

  /// A type-five named CMYK color.
  namedCmyk,

  /// A type-five named RGB color with a CMYK alternative.
  namedRgb,
}

/// One editable native gradient color without implicit color conversion.
final class AiNativeGradientColor {
  /// Native color representation and naming semantics.
  final AiNativeGradientColorKind kind;

  /// Gray, CMYK, or CMYK followed by RGB components, each in zero to one.
  final List<double> components;

  /// Exact native color name bytes, when the color is named or custom.
  final Uint8List? nameBytes;

  /// Native tint value for a named or custom color, without changing its meaning.
  final double? tint;

  /// Creates a color while requiring explicit alternatives and name encoding.
  AiNativeGradientColor({required this.kind, required List<double> components, List<int>? nameBytes, this.tint})
    : components = List.unmodifiable(components),
      nameBytes = nameBytes == null ? null : Uint8List.fromList(nameBytes).asUnmodifiableView() {
    final int count = switch (kind) {
      .gray => 1,
      .cmyk || .customCmyk || .namedCmyk => 4,
      .rgb || .customRgb || .namedRgb => 7,
    };
    final bool named = kind.index >= AiNativeGradientColorKind.customCmyk.index;
    if (components.length != count ||
        components.any((value) => !_gradientUnit(value)) ||
        named != (nameBytes != null && tint != null) ||
        !named && (nameBytes != null || tint != null) ||
        nameBytes != null && (nameBytes.isEmpty || nameBytes.any((byte) => byte < 0 || byte > 255)) ||
        tint != null && !_gradientUnit(tint!)) {
      throw ArgumentError('Invalid native gradient color components, name or tint.');
    }
  }

  /// Native color-style selector, before an optional opacity wrapper.
  int get style => switch (kind) {
    .gray => 0,
    .cmyk => 1,
    .rgb => 2,
    .customCmyk => 3,
    .customRgb => 4,
    .namedCmyk || .namedRgb => 5,
  };
}

/// A native gradient stop, retaining positions and midpoint percentages.
final class AiNativeGradientStop {
  /// Process or named color with explicit native alternative components.
  final AiNativeGradientColor color;

  /// Position along the gradient, from zero to one hundred.
  final double position;

  /// Percentage of the following interval where the colors mix equally.
  final double midpoint;

  /// Stop opacity, separate from its color or custom-color tint.
  final double opacity;

  /// Whether the native representation explicitly carries opacity, even at one.
  final bool hasOpacity;

  /// Creates a finite stop without selecting a color interpolation algorithm.
  AiNativeGradientStop({required this.color, required this.position, this.midpoint = 50, this.opacity = 1, this.hasOpacity = true}) {
    if (!position.isFinite || position < 0 || position > 100 || !midpoint.isFinite || midpoint <= 0 || midpoint >= 100 || !_gradientUnit(opacity) || !hasOpacity && opacity != 1) {
      throw ArgumentError('Invalid native gradient position, midpoint or opacity.');
    }
  }
}

/// One printing-ramp channel, either a native constant or explicit byte samples.
final class AiNativeGradientChannel {
  /// Native constant, preserving legacy byte and newer normalized conventions.
  final double? constant;

  /// Immutable samples in native ramp order, or null for a constant channel.
  final Uint8List? samples;

  /// Creates a constant channel without expanding it into an arbitrary ramp size.
  AiNativeGradientChannel.constant({required double value}) : constant = value, samples = null {
    if (!value.isFinite || value < 0 || value > 255) {
      throw ArgumentError.value(value, 'value', 'Expected a finite native gradient constant.');
    }
  }

  /// Owns caller-composed channel samples; no color profile is assumed.
  AiNativeGradientChannel.samples({required List<int> values}) : constant = null, samples = Uint8List.fromList(values).asUnmodifiableView() {
    if (values.isEmpty || values.any((value) => value < 0 || value > 255)) {
      throw ArgumentError('Expected nonempty gradient byte samples.');
    }
  }
}

/// Native printing-ramp channel layouts, in the specification's numeric order.
enum AiNativeGradientRampKind {
  /// One gray channel.
  gray,

  /// Four CMYK channels.
  cmyk,

  /// CMYK followed by one custom-color tint channel.
  customCmyk,

  /// CMYK followed by two custom-color tint channels.
  twoCustomCmyk,

  /// CMYK followed by RGB channels.
  rgb,

  /// CMYK, RGB and one custom-color tint channel.
  customRgb,

  /// CMYK, RGB and two custom-color tint channels.
  twoCustomRgb,
}

/// One sampled interval of an Illustrator printing ramp.
final class AiNativeGradientRamp {
  /// Native channel layout and custom-color separation semantics.
  final AiNativeGradientRampKind kind;

  /// Immutable channels in the native layout's order.
  final List<AiNativeGradientChannel> channels;

  /// Creates an interval whose sampled channels all have the same length.
  AiNativeGradientRamp({required this.kind, required List<AiNativeGradientChannel> channels}) : channels = List.unmodifiable(channels) {
    final int expected = const [1, 4, 5, 6, 7, 8, 9][kind.index];
    final Set<int> lengths = channels.map((channel) => channel.samples?.length).whereType<int>().toSet();
    if (channels.length != expected || lengths.length > 1) {
      throw ArgumentError('Invalid native gradient ramp channels or sample lengths.');
    }
  }
}

/// A source-backed global gradient definition, independent of its instances.
final class AiNativeGradientDefinition extends AiNativeItem {
  /// Opening resource command with its original name and gradient kind.
  final AiNativeInstruction opening;

  /// Closing command, before the retained EndGradient comment.
  final AiNativeInstruction closing;

  /// Authoritative native stops in original source order.
  final List<AiNativeGradientStop> stops;

  /// Compatibility stops, possibly using less precise color alternatives.
  final List<AiNativeGradientStop> fallbackStops;

  /// Cached printing intervals in original order, empty when not supplied.
  final List<AiNativeGradientRamp> ramps;

  /// Whether the source uses paired BS compatibility and private Bs records.
  final bool hasPairedStops;

  /// Whether stop operands use the newer private-line representation.
  final bool usesPrivateStops;

  /// Captures a validated definition without losing its source boundaries.
  AiNativeGradientDefinition._({
    required this.opening,
    required this.closing,
    required List<AiNativeGradientStop> stops,
    required List<AiNativeGradientStop> fallbackStops,
    required List<AiNativeGradientRamp> ramps,
    required this.hasPairedStops,
    required this.usesPrivateStops,
  }) : stops = List.unmodifiable(stops),
       fallbackStops = List.unmodifiable(fallbackStops),
       ramps = List.unmodifiable(ramps),
       super(start: opening.start, end: closing.end);

  /// Exact resource-name bytes, shared by every referencing Bg instruction.
  Uint8List get nameBytes => aiStringBytes(opening.operands.first).asUnmodifiableView();

  /// Whether this definition supplies radial rather than linear instances.
  bool get radial => opening.operands[1].number == 1;
}

/// Immutable gradient resources and atomic global-stop editing.
final class AiNativeGradientResources {
  /// Owning native-record snapshot.
  final AiNativeRecords records;

  /// Definitions in source order, including nonprinting swatches.
  final List<AiNativeGradientDefinition> definitions;

  /// Reads bounded setup definitions without executing PostScript or color code.
  factory AiNativeGradientResources.decode({required AiNativeRecords records}) => AiNativeGradientResources._(records: records, definitions: _readGradientResources(records));

  /// Retains the owning snapshot and immutable resource handles.
  AiNativeGradientResources._({required this.records, required List<AiNativeGradientDefinition> definitions}) : definitions = List.unmodifiable(definitions);

  /// Replaces a global gradient's stops and all its native printing intervals.
  ///
  /// Stops are supplied in strictly increasing position order; ramps are in the
  /// same interval order. Native linear stops are written in descending order,
  /// radial stops in ascending order. Every definition with the same byte name
  /// changes in one transaction. Linear printing strips and exterior caps follow
  /// the new positions in drawing, styles, patterns and swatches; the complete
  /// gradient placement stays fixed. Radial matrices and matrix-free authoring
  /// notes stay intact. Paired compatibility records are regenerated.
  ///
  /// Inconsistent or incomplete printing geometry rejects positional changes.
  /// Legacy strips without `Xm` must identify one consistent whole axis. Moving
  /// an endpoint requires its existing exterior cap, whose outer edge stays
  /// fixed. Command-local whitespace/comments may be regenerated; unrelated
  /// source bytes are preserved. Color-only edits do not reinterpret geometry.
  ///
  /// The host composes the ramps using its color profiles and interpolation, and
  /// regenerates flattened effects before a synchronized save. `AiNativePdf`
  /// can render supported classic fills into matching PDF appearances.
  /// Explicit ramps prevent stale printing caches; they do not certify that the
  /// host's samples match its stops. Old single-record syntax requires opaque
  /// colors with style codes zero through four.
  AiNativeGradientResources replaceStops({required AiNativeGradientDefinition definition, required List<AiNativeGradientStop> stops, required List<AiNativeGradientRamp> ramps}) =>
      _replaceGradientStops(this, definition, stops, ramps);

  /// Sets the normalized focus of every instance of a named radial gradient.
  ///
  /// This is a global operation: drawing instances, shared styles, swatches and
  /// nested native art referencing the same byte name all change atomically.
  /// [angle] is the native focus angle in degrees, between -360 and 360; [length]
  /// is the distance from the center as a fraction of the unit radius, in 0..1.
  /// The printing matrix maps `(length*cos(angle), -length*sin(angle))` to the
  /// corresponding highlight offset, including elliptical or skewed gradients.
  ///
  /// Printing instances require one nonsingular `Bm` and coherent existing
  /// highlight offsets. Nonprinting style notes retain zero offsets. Unknown
  /// layouts reject the entire edit. Absent highlights are inserted when needed;
  /// unchanged values preserve their exact source syntax. Stops, ramps, geometry
  /// and unrelated bytes remain intact. The host must regenerate PDF appearances
  /// and any flattened effects before saving the resulting native program.
  AiNativeGradientResources setRadialFocus({required AiNativeGradientDefinition definition, required double angle, required double length}) => _setNativeGradientFocus(this, definition, angle, length);
}

/// Whether a native unit-range component is finite and valid.
bool _gradientUnit(double value) => value.isFinite && value >= 0 && value <= 1;
