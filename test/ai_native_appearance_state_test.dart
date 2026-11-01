import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement, appearanceArtworkSource;
import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource, appearancePrinting;

/// A complete literal fill whose outgoing color needs no filter evaluation.
String appearanceStateFill({String color = '0.1 0.2 0.3 Xa', String visible = '1 /Visible ,', String opacity = '0 1 0 0 0 Xy'}) => '''/BasicFilter : (Fill Style Filter) 0 0 /Filter , $visible
/Dictionary : /NotRecorded , 0 /Bool (UseEvenOdd) ,
/FillStyle : 0 O $opacity 0 XR $color /Def ; (FillStyle) , ; /Dict , ; /Part ,''';

/// Keeps an opaque following owner to require identical incoming native state.
String appearanceStateSource({bool ordinary = false, String? fills, String tail = '/FutureRecord : (preserved) /String (Payload) , ;'}) {
  final String source = ordinary ? appearanceArtworkSource() : appearanceEditingSource();
  return source
      .replaceRange(source.indexOf('/KnownStyle'), source.indexOf('%%EndSetup'), '''/KnownStyle : (Shared) /Name ,
/ActiveStyle : /CompoundFilter : (Chain Style Filter) 0 0 /Filter , 1 /Visible ,
${fills ?? appearanceStateFill()}
; /Execution ; /Def ;
''')
      .replaceFirst('%%Trailer', '$tail\n%%Trailer');
}

/// Supplies the selected user's group while changing one literal native color.
AiNativeAppearances appearanceStateEdit(AiNativeAppearances source, {int index = 1, List<double> color = const [0.7, 0.6, 0.5]}) => source.updateSelected(
  appearance: source.styles.first,
  paints: [AiNativePaintChange(assignment: appearanceAssignment(source.styles.first, 1, .fillColor), values: color)],
  artwork: source.structure.drawing.liveShapes.isEmpty ? [appearanceArtworkReplacement(source, index)] : [],
  printing: source.structure.drawing.liveShapes.isEmpty ? [] : [appearancePrinting(source, index)],
  nameBytes: latin1.encode('Selected state'),
);

/// Checks literal restoration without interpreting the retained opaque consumer.
void main() {
  test('restores explicit native color before opaque consumers of ordinary and live artwork', () {
    for (final bool ordinary in [false, true]) {
      final String text = appearanceStateSource(ordinary: ordinary);
      final AiNativeAppearances before = appearanceEditingModel(source: text);
      final AiNativeAppearances after = appearanceStateEdit(before);
      final String changed = latin1.decode(after.structure.drawing.records.program.bytes);
      check(changed.substring(after.uses.last.instruction.end)).startsWith('\n%_0.1 0.2 0.3 Xa\n');
      check(changed.substring(changed.indexOf('/FutureRecord'))).equals(text.substring(text.indexOf('/FutureRecord')));
      check(appearanceAssignment(after.styles.last, 1, .fillColor).numbers).isNotNull().deepEquals([0.7, 0.6, 0.5]);
      check(latin1.decode(before.structure.drawing.records.program.bytes)).equals(text);
      check(after.artworkFor(use: after.uses.last).path.geometry.length).equals(before.artworkFor(use: before.uses.last).path.geometry.length);
    }
  });

  test('copies gray CMYK and dual alternatives without converting their channels', () {
    for (final (String, List<double>) paint in [
      ('0.2 g', [0.8]),
      ('0 0.1 0.2 0.3 k', [0.1, 0.2, 0.3, 0.4]),
      ('0 0 0 0 1 1 1 Xa', [1, 0, 0, 0, 0, 1, 1]),
    ]) {
      final AiNativeAppearances source = appearanceEditingModel(
        source: appearanceStateSource(fills: appearanceStateFill(color: paint.$1)),
      );
      final AiNativeAppearances changed = appearanceStateEdit(source, color: paint.$2);
      check(latin1.decode(changed.structure.drawing.records.program.bytes)).contains('\n%_${paint.$1}\n');
    }
  });

  test('requires uniform visible original paint and preserves unqualified sources atomically', () {
    for (final String fills in [
      appearanceStateFill(visible: '0 /Visible ,'),
      appearanceStateFill(visible: ''),
      '${appearanceStateFill()}${appearanceStateFill(color: '0.9 g')}',
      '${appearanceStateFill()}${appearanceStateFill(color: '')}',
    ]) {
      final String text = appearanceStateSource(fills: fills);
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      check(() => appearanceStateEdit(source)).throws<UnsupportedError>();
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
    final AiNativeAppearances equal = appearanceEditingModel(source: appearanceStateSource(fills: '${appearanceStateFill()}${appearanceStateFill()}'));
    check(() => appearanceStateEdit(equal)).returnsNormally();
  });

  test('does not insert restoration when following source already overwrites the change', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceStateSource(tail: '0 g 0 0 m 1 1 L f'));
    final AiNativeAppearances changed = appearanceStateEdit(source);
    check(latin1.decode(changed.structure.drawing.records.program.bytes)).not((value) => value.contains('%_0.1 0.2 0.3 Xa'));
  });

  test('retains existing private declarations and allows subsequent appearance edits', () {
    final String text = appearanceStateSource();
    final int start = text.indexOf('/KnownStyle');
    final int end = text.indexOf('%%EndSetup');
    final String private = text.replaceRange(start, end, '${text.substring(start, end).trimRight().split('\n').map((line) => '%_$line').join('\n')}\n');
    final AiNativeAppearances source = appearanceEditingModel(source: private);
    final AiNativeAppearances changed = appearanceStateEdit(source);
    final AiNativeAppearance selected = changed.styles.last;
    final AiNativeAppearances next = changed.updateSelected(
      appearance: selected,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(selected, 1, .fillColor), values: [0.4, 0.3, 0.2]),
      ],
      printing: [appearancePrinting(changed, 1)],
      nameBytes: latin1.encode('Next state'),
    );
    check(next.styles).length.equals(3);
    check(latin1.decode(next.structure.drawing.records.program.bytes)).contains('%_0.1 0.2 0.3 Xa');
    check(next.structure.drawing.liveShapes.every((shape) => shape.isBound)).isTrue();
  });

  test('does not bypass missing shared coverage or unknown shared references', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceStateSource());
    final List<AiNativePaintChange> paints = [
      AiNativePaintChange(assignment: appearanceAssignment(source.styles.first, 1, .fillColor), values: [0.7, 0.6, 0.5]),
    ];
    for (final List<int> users in [
      [1],
      [0, 1],
    ]) {
      check(() => source.updateShared(appearance: source.styles.first, paints: paints, printing: users.map((index) => appearancePrinting(source, index)).toList())).throws<UnsupportedError>();
    }
  });

  test('restores every supplied shared user before an inheriting independent contour', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceStateSource(ordinary: true, tail: '20 0 m 30 0 L 30 10 L f'));
    final AiNativeAppearances changed = source.updateShared(
      appearance: source.styles.first,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(source.styles.first, 1, .fillColor), values: [0.7, 0.6, 0.5]),
      ],
      artwork: [appearanceArtworkReplacement(source, 0), appearanceArtworkReplacement(source, 1)],
    );
    check(changed.styles).length.equals(1);
    final String text = latin1.decode(changed.structure.drawing.records.program.bytes);
    for (final AiNativeResourceUse use in changed.uses) {
      check(text.substring(use.instruction.end)).startsWith('\n%_0.1 0.2 0.3 Xa\n');
    }
  });

  test('bounds restored source output before returning a changed snapshot', () {
    final String text = appearanceStateSource();
    final int exact = appearanceStateEdit(appearanceEditingModel(source: text)).structure.drawing.records.program.bytes.length;
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: exact - 1),
    );
    check(() => appearanceStateEdit(bounded)).throws<FormatException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(text);
  });
}
