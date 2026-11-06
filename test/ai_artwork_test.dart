import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Creates simple authored geometry for native path model tests.
AiArtworkPath rectangle() => AiArtworkPath(
  segments: [
    AiPathSegment(operator: 'm', coordinates: [10, 10]),
    AiPathSegment(operator: 'L', coordinates: [90, 10]),
    AiPathSegment(operator: 'L', coordinates: [90, 90]),
    AiPathSegment(operator: 'L', coordinates: [10, 90]),
  ],
  fill: AiColor(space: .rgb, channels: [1, 0, 0]),
  closed: true,
);

/// Checks retained path values and source-backed layer editing.
void main() {
  test('copies simple appearance without mutating the original artwork', () {
    final AiArtworkPath original = rectangle();
    final AiArtworkPath copy = original.copyWith(
      clearFill: true,
      stroke: AiColor(space: .gray, channels: [0.2]),
      dash: [2, 4],
      dashPhase: 1,
      lineCap: 1,
      lineJoin: 2,
    );
    check(original.fill).isNotNull();
    check(copy.fill).isNull();
    check(copy.stroke!.space).equals(AiColorSpace.gray);
    check(() => copy.dash.add(1)).throws<UnsupportedError>();
  });

  test('rejects invalid paints and stroke state', () {
    check(() => AiColor(space: .rgb, channels: [1, 2, 0])).throws<ArgumentError>();
    check(() => rectangle().copyWith(dash: [0, 0])).throws<ArgumentError>();
    check(() => rectangle().copyWith(strokeWidth: double.nan)).throws<ArgumentError>();
  });

  test('layer lock changes do not modify a legacy first object lock', () {
    final AiProgram original = AiProgram.decode(
      bytes: latin1.encode(
        '%!PS-Adobe-3.0\n%%EndComments\n%%BeginSetup\n%%EndSetup\n'
        '%AI5_BeginLayer\n1 1 1 1 0 0 0 79 128 255 Lb\n(Layer) Ln\n'
        '0 A\n0 0 m\n10 10 L\nS\nLB\n%%EOF\n',
      ),
    );
    final AiProgram changed = AiNativeEditor.updateLayer(program: original, layer: original.layers.single, locked: true);
    check(changed.layers.single.locked).isTrue();
    check(changed.instructions.firstWhere((instruction) => instruction.operator == 'A').numbers!).deepEquals([0.0]);
  });
}
