import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Creates simple authored geometry for portable model and writer tests.
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

/// Checks actual native authoring rather than relabeling a PDF graph as AI.
void main() {
  test('creates editable native paths, groups and hidden sublayers', () {
    final AiArtworkPath path = rectangle();
    final AiArtwork artwork = AiArtwork(
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
      children: [
        AiArtworkLayer(
          name: 'Artwork (1)',
          children: [
            AiArtworkGroup(children: [path]),
            AiArtworkLayer(
              name: 'Hidden',
              visible: false,
              locked: true,
              children: [
                path.copyWith(
                  stroke: AiColor(space: .cmyk, channels: [0, 0, 0, 1]),
                  strokeWidth: 3,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final AiPostScriptDocument document = artwork.toPostScript();
    final AiProgram program = AiProgram.decode(bytes: document.postScriptBytes);
    check(document.creator).equals('AiKit');
    check(program.layers.map((layer) => layer.name)).deepEquals(['Artwork (1)', 'Hidden']);
    check(program.layers[1].visible).isFalse();
    check(program.layers[1].locked).isTrue();
    check(program.paths.length).equals(2);
    check(program.paths.first.filled).isTrue();
    check(program.paths.last.stroked).isTrue();
    check(program.unhandledOperators).isEmpty();
    check(const AiCodec().encode(document)).deepEquals(document.bytes);
  });

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

  test('bounds writing and rejects invalid paints and stroke state', () {
    check(() => AiColor(space: .rgb, channels: [1, 2, 0])).throws<ArgumentError>();
    check(() => rectangle().copyWith(dash: [0, 0])).throws<ArgumentError>();
    check(() => rectangle().copyWith(strokeWidth: double.nan)).throws<ArgumentError>();
    final AiArtwork drawing = AiArtwork(bounds: AiBoundingBox(left: -1.5, bottom: 2, right: 100, top: 100), children: [rectangle()]);
    check(() => drawing.toPostScript(limits: const AiLimits(pdf: PdfLimits(maxFileBytes: 100)))).throws<FormatException>();
    check(latin1.decode(drawing.toPostScript().bytes).contains('%%BoundingBox: -2 2 100 100')).isTrue();
  });

  test('layer lock changes do not modify a legacy first object lock', () {
    final AiProgram original = AiProgram.decode(
      bytes: AiArtwork(
        bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
        children: [
          AiArtworkLayer(name: 'Layer', children: [rectangle()]),
        ],
      ).toPostScript().bytes,
    );
    final AiProgram changed = AiNativeEditor.updateLayer(program: original, layer: original.layers.single, locked: true);
    check(changed.layers.single.locked).isTrue();
    check(changed.instructions.firstWhere((instruction) => instruction.operator == 'A').numbers!).deepEquals([0.0]);
  });
}
