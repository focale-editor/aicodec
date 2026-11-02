import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_text_creation_test.dart' show newDocumentText;

/// Creates actual source ownership; glyph values below exercise serialization.
AiNativeTextDocument _source(String value) => newDocumentText().createStory(text: value, frames: [AiNativeTextFrameDefinition.point(x: 20, y: 30)]);

/// Host fixture for one explicit glyph origin, without claiming font rendering.
AiNativeTextGlyphLayout _glyph(AiNativeTextDocument source, int id, double x, {bool mark = false}) =>
    AiNativeTextGlyphLayout(font: source.fonts.first, glyphId: id, x: x, y: 0, bounds: [0, -10, if (mark) 0 else 8, 2], paragraphMark: mark);

/// Attaches one line while exercising the complete native save checks.
AiNativeTextDocument _compose(AiNativeTextDocument source, List<AiNativeTextSegmentLayout> segments) => source.withGlyphLayout(
  story: source.stories.single,
  frames: [
    AiNativeTextFrameLayout(
      frame: source.frames.single,
      x: 20,
      y: 30,
      lines: [AiNativeTextLineLayout(segments: segments)],
    ),
  ],
  bounds: AiBoundingBox(left: 20, bottom: -40, right: 80, top: -20),
);

/// Checks native mappings and ownership; rendering acceptance belongs to Focale.
void main() {
  test('writes path glyphs with unwrapped origins and explicit projected bounds', () {
    final AiNativeTextDocument source = newDocumentText().createStory(
      text: 'X',
      frames: [
        AiNativeTextFrameDefinition(
          resource: PsEngineDictionary(
            values: {
              '1': PsEngineDictionary(
                values: {
                  '0': PsEngineArray(
                    values: [
                      for (final int value in [0, 0, 10, -20, 30, -20, 40, 0]) PsEngineNumber(value: value),
                    ],
                  ),
                },
              ),
              '2': PsEngineDictionary(
                values: {
                  '0': PsEngineNumber(value: 2),
                  '6': PsEngineArray(values: [PsEngineNumber(value: 0), PsEngineNumber(value: 1)]),
                },
              ),
            },
          ),
          confinement: latin1.encode('X= 0 0 m 10 20 30 20 40 0 C n X+'),
        ),
      ],
    );
    final AiNativeTextDocument composed = _compose(source, [
      AiNativeTextSegmentLayout(
        start: 0,
        end: 1,
        glyphs: [
          AiNativeTextGlyphLayout(font: source.fonts.first, glyphId: 2, x: 0, y: 0, bounds: [0, -10, 8, 2], pathBounds: [0, -20, 12, 2]),
        ],
      ),
      AiNativeTextSegmentLayout(
        start: 1,
        end: 2,
        glyphs: [
          AiNativeTextGlyphLayout(font: source.fonts.first, glyphId: 1, x: 8, y: 0, bounds: [0, 0, 0, 0], pathBounds: [0, 0, 0, 0], paragraphMark: true),
        ],
      ),
    ]);
    composed.validateTextForSave();
    final AiNativeTextStrike glyph = composed.stories.single.strikes.single.descendants.firstWhere((strike) => strike.kind == .glyphs);
    check(glyph.visualBounds!).deepEquals([0, -20, 12, 2]);
    check((glyph.record['24']! as PsEngineNumber).value).equals(0);
    check(composed.duplicateStory(story: composed.stories.single).stories.length).equals(2);
    for (final String omitted in ['8', '24']) {
      /// Removes only one required glyph-cache field from a host-provided view.
      PsEngineValue withoutField(PsEngineValue value) => switch (value) {
        PsEngineDictionary() => PsEngineDictionary(
          values: {
            for (final MapEntry<String, PsEngineValue> entry in value.values.entries)
              if (entry.key != omitted || value['99'] is! PsEngineName || (value['99']! as PsEngineName).value != 'G') entry.key: withoutField(entry.value),
          },
        ),
        PsEngineArray() => PsEngineArray(values: value.values.map(withoutField).toList()),
        _ => value,
      };
      check(
        () => composed.withComposedText(
          story: composed.stories.single,
          view: withoutField(composed.stories.single.view!) as PsEngineDictionary,
          bounds: AiBoundingBox(left: 0, bottom: -20, right: 40, top: 0),
        ),
      ).throws<UnsupportedError>();
      composed.validateTextForSave();
    }

    check(
      () => _compose(source, [
        AiNativeTextSegmentLayout(start: 0, end: 1, glyphs: [_glyph(source, 2, 0)]),
        AiNativeTextSegmentLayout(start: 1, end: 2, glyphs: [_glyph(source, 1, 8, mark: true)]),
      ]),
    ).throws<ArgumentError>();
  });

  test('rejects malformed path glyph bounds and path caches on ordinary frames', () {
    final AiNativeTextDocument source = _source('X');
    check(() => AiNativeTextGlyphLayout(font: source.fonts.first, glyphId: 2, x: 0, y: 0, bounds: [0, 0, 1, 1], pathBounds: [2, 0, 1, 1])).throws<ArgumentError>();
    check(
      () => _compose(source, [
        AiNativeTextSegmentLayout(
          start: 0,
          end: 1,
          glyphs: [
            AiNativeTextGlyphLayout(font: source.fonts.first, glyphId: 2, x: 0, y: 0, bounds: [0, 0, 1, 1], pathBounds: [0, 0, 1, 1]),
          ],
        ),
      ]),
    ).throws<ArgumentError>();
  });

  test('writes contractions, explicit glyph origins and a real paragraph-mark slot', () {
    final AiNativeTextDocument source = _source('fiX');
    final AiNativeTextDocument composed = _compose(source, [
      AiNativeTextSegmentLayout(start: 0, end: 2, glyphs: [_glyph(source, 52, 0)]),
      AiNativeTextSegmentLayout(start: 2, end: 3, glyphs: [_glyph(source, 40, 9)]),
      AiNativeTextSegmentLayout(start: 3, end: 4, glyphs: [_glyph(source, 3, 17, mark: true)]),
    ]);
    composed.validateTextForSave();
    final List<AiNativeTextStrike> segments = composed.stories.single.strikes.single.descendants.where((strike) => strike.kind == .segment).toList();
    final PsEngineDictionary mapping = segments.first.record['15']! as PsEngineDictionary;
    final PsEngineDictionary contraction = (mapping['1']! as PsEngineArray).values.single as PsEngineDictionary;
    check((contraction['0']! as PsEngineNumber).value).equals(1);
    check((contraction['2']! as PsEngineNumber).value).equals(2);
    check(segments.map((segment) => segment.children.single.origin)).deepEquals([
      [0.0, 0.0],
      [9.0, 0.0],
      [17.0, 0.0],
    ]);
    check(segments.map((segment) => segment.children.single.glyphIds.single)).deepEquals([52, 40, 3]);
    check((segments.last.children.single.record['11']! as PsEngineBoolean).value).isTrue();
    // Subsequent lifecycle edits must accept every field emitted by the writer.
    final AiNativeTextDocument duplicated = composed.duplicateStory(story: composed.stories.single);
    check(duplicated.stories.length).equals(2);
    check(duplicated.stories.first.strikes.single.descendants.where((strike) => strike.kind == .glyphs).length).equals(3);
  });

  test('retains one-to-many clusters without treating the count delta as a ligature', () {
    final AiNativeTextDocument source = _source('X');
    final AiNativeTextDocument composed = _compose(source, [
      AiNativeTextSegmentLayout(start: 0, end: 1, glyphs: [_glyph(source, 12, 0), _glyph(source, 13, 3)]),
      AiNativeTextSegmentLayout(start: 1, end: 2, glyphs: [_glyph(source, 3, 7, mark: true)]),
    ]);
    composed.validateTextForSave();
    final AiNativeTextStrike segment = composed.stories.single.strikes.single.descendants.firstWhere((strike) => strike.kind == .segment);
    final PsEngineDictionary mapping = segment.record['15']! as PsEngineDictionary;
    check((mapping['2']! as PsEngineNumber).value).equals(1);
    check(segment.children.map((child) => child.glyphIds.single)).deepEquals([12, 13]);
  });

  test('rejects foreign fonts, unmarked CR and unsupported many-to-many clusters', () {
    final AiNativeTextDocument source = _source('fi');
    final AiNativeTextDocument foreign = _source('fi');
    check(
      () => _compose(source, [
        AiNativeTextSegmentLayout(start: 0, end: 2, glyphs: [_glyph(foreign, 8, 0)]),
      ]),
    ).throws<ArgumentError>();
    check(
      () => _compose(source, [
        AiNativeTextSegmentLayout(start: 0, end: 2, glyphs: [_glyph(source, 8, 0), _glyph(source, 9, 8)]),
      ]),
    ).throws<UnsupportedError>();
    check(
      () => _compose(source, [
        AiNativeTextSegmentLayout(start: 0, end: 2, glyphs: [_glyph(source, 8, 0)]),
        AiNativeTextSegmentLayout(start: 2, end: 3, glyphs: [_glyph(source, 3, 8)]),
      ]),
    ).throws<ArgumentError>();
  });

  test('appending a font updates complete document dependencies once', () {
    final AiNativeTextDocument source = newDocumentText();
    final AiNativeFontDefinition face = AiNativeFontDefinition(postScriptName: 'OtherFace-Regular', technology: .trueType);
    final AiNativeTextDocument changed = source.addFont(font: face).addFont(font: face);
    final String header = latin1.decode(changed.records.program.bytes.sublist(0, changed.records.program.bodyStart));
    for (final String field in ['%%DocumentFonts:', '%%DocumentNeededFonts:']) {
      final String line = header.split('\n').singleWhere((line) => line.startsWith(field));
      check(line.split('OtherFace-Regular').length).equals(2);
      check(line).contains('DejaVuSans');
    }
    check(source.fonts.length).equals(1);
    check(changed.fonts.length).equals(3);
  });
}
