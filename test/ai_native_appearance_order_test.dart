import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearanceEditingSource, appearancePrinting;

/// Separates both users' inherited state without changing their source pairs.
String appearanceOrderSource() => appearanceEditingSource().replaceFirst('1 (Shared) XW', '1 (Shared) XW\n0 g 0 G 0 O 0 R 0 1 0 0 0 Xy 0 J 0 j 1 w 10 M [] 0 d 0 XR');

/// Keeps exact subtree bytes available for preservation and permutation checks.
List<int> _bytes(AiNativeAppearances model, AiNativeContainer record) => model.structure.drawing.records.program.bytes.sublist(record.start, record.end);

/// Requests the reverse order of one source-owned parent's direct children.
AiNativeAppearancePartChange reverseAppearanceChildren(AiNativeAppearance style, int parent) => AiNativeAppearancePartChange(
  part: style.parts[parent],
  childOrder: style.parts[parent].childIndices.reversed.map((index) => style.parts[index]).toList(),
);

/// Supplies distinct fills with identical explicit outgoing noncolor attributes.
String _uniformOrderSource() {
  final String text = appearanceOrderSource();
  final String style =
      '''/KnownStyle : (Shared) /Name ,
/ActiveStyle : /CompoundFilter : (Stack Style Filter) 0 0 /Filter , 1 /Visible ,
${[0.2, 0.4].map((color) => '/BasicFilter : (Fill Style Filter) 0 0 /Filter , 1 /Visible , /Dictionary : 0 /Bool (UseEvenOdd) , /FillStyle : $color g 0 O 0 1 0 0 0 Xy 0 XR /Def ; (FillStyle) , ; /Dict ; /Part ,').join('\n')}
; /Execution ; /Def ;
''';
  return text.replaceRange(text.indexOf('/KnownStyle'), text.indexOf('%%EndSetup'), style).replaceFirst('%%Trailer', '0 g 0 O 0 0 m 10 10 L f\n%%Trailer');
}

/// Verifies ordering, simultaneous nested edits, ownership and atomic refusal.
void main() {
  test('isolates an ordered stack and retains complete moved subtrees and other users', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      parts: [reverseAppearanceChildren(style, 1)],
      printing: [appearancePrinting(source, 0)],
      nameBytes: latin1.encode('Reordered'),
    );
    final AiNativeAppearance selected = changed.styles.last;
    check(selected.parts[1].childIndices.map((index) => selected.parts[index].kind)).deepEquals([
      AiNativeAppearancePartKind.stroke,
      AiNativeAppearancePartKind.conduit,
      AiNativeAppearancePartKind.fill,
      AiNativeAppearancePartKind.fill,
    ]);
    for (final (int, int) entry in selected.parts[1].childIndices.indexed) {
      check(_bytes(changed, selected.parts[entry.$2].record)).deepEquals(_bytes(source, style.parts[style.parts[1].childIndices.reversed.elementAt(entry.$1)].record));
    }
    check(_bytes(changed, changed.styles.first.definition)).deepEquals(_bytes(source, style.definition));
    final AiLiveShape before = source.structure.drawing.liveShapes.last;
    final AiLiveShape after = changed.structure.drawing.liveShapes.last;
    check(changed.structure.drawing.records.program.bytes.sublist(after.start, after.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(before.start, before.end));
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(appearanceOrderSource());
  });

  test('combines nested chain and stack ordering with paint and part settings', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
      ],
      parts: [
        reverseAppearanceChildren(style, 0),
        reverseAppearanceChildren(style, 1),
        AiNativeAppearancePartChange(part: style.parts[2], visible: true, evenOdd: false),
        AiNativeAppearancePartChange(part: style.parts[6], strokeAlignment: .outside),
      ],
      printing: [appearancePrinting(source, 1)],
      nameBytes: latin1.encode('Nested'),
    );
    final AiNativeAppearance selected = changed.styles.last;
    check(selected.parts.map((part) => part.kind)).deepEquals([
      AiNativeAppearancePartKind.chain,
      AiNativeAppearancePartKind.blend,
      AiNativeAppearancePartKind.strokeOffset,
      AiNativeAppearancePartKind.stack,
      AiNativeAppearancePartKind.stroke,
      AiNativeAppearancePartKind.conduit,
      AiNativeAppearancePartKind.fill,
      AiNativeAppearancePartKind.fill,
    ]);
    check(selected.parts.last.parentIndex).equals(3);
    check(selected.parts.last.visible).equals(true);
    check(selected.parts.last.evenOdd).equals(false);
    check(appearanceAssignment(selected, 7, .fillColor).numbers).isNotNull().deepEquals([0.7, 0.6, 0.5]);
    check(selected.parts[2].strokeAlignment).equals(AiNativeStrokeAlignment.outside);
    check(_bytes(changed, selected.parts[6].record)).deepEquals(_bytes(source, style.parts[3].record));
  });

  test('reorders shared parts only with complete printing coverage', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final List<AiNativeAppearancePartChange> changes = [reverseAppearanceChildren(style, 1)];
    final AiNativeAppearances changed = source.updateShared(appearance: style, parts: changes, printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)]);
    check(changed.styles).length.equals(1);
    check(changed.styles.single.uses).length.equals(2);
    check(changed.styles.single.parts[2].kind).equals(AiNativeAppearancePartKind.stroke);
    check(() => source.updateShared(appearance: style, parts: changes, printing: [appearancePrinting(source, 1)])).throws<UnsupportedError>();
  });

  test('owns order lists and rejects missing repeated foreign and nonchild handles', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final List<AiNativeAppearancePart> children = style.parts[1].childIndices.map((index) => style.parts[index]).toList();
    final AiNativeAppearancePartChange saved = AiNativeAppearancePartChange(part: style.parts[1], childOrder: children);
    children.clear();
    check(saved.childOrder!).length.equals(4);
    check(saved.childOrder!.clear).throws<UnsupportedError>();
    for (final List<AiNativeAppearancePart> order in [
      <AiNativeAppearancePart>[],
      [style.parts[2], style.parts[3], style.parts[4]],
      [style.parts[2], style.parts[2], style.parts[4], style.parts[5]],
      [style.parts[0], style.parts[3], style.parts[4], style.parts[5]],
      [appearanceEditingModel().styles.single.parts[2], style.parts[3], style.parts[4], style.parts[5]],
    ]) {
      check(
        () => source.updateSelected(
          appearance: style,
          parts: [AiNativeAppearancePartChange(part: style.parts[1], childOrder: order)],
          printing: [appearancePrinting(source, 1)],
          nameBytes: [65],
        ),
      ).throws<ArgumentError>();
    }
    check(
      () => source.updateSelected(
        appearance: style,
        parts: [AiNativeAppearancePartChange(part: style.parts[2], childOrder: [])],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      ),
    ).throws<UnsupportedError>();
  });

  test('preserves private prefixes and comments inside reordered parts', () {
    final String annotated = appearanceOrderSource().replaceFirst('0.2 0.3 0.4 Xa', '0.2 % retained paint comment\n0.3 0.4 Xa');
    final AiNativeAppearances original = appearanceEditingModel(source: annotated);
    final AiNativeContainer declaration = original.styles.single.resource.definition.source as AiNativeContainer;
    final String text = annotated.substring(declaration.start, declaration.end);
    final String private = annotated.replaceFirst(text, text.split('\n').map((line) => '%_$line').join('\n'));
    final AiNativeAppearances source = appearanceEditingModel(source: private);
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateSelected(
      appearance: style,
      parts: [reverseAppearanceChildren(style, 0), reverseAppearanceChildren(style, 1)],
      printing: [appearancePrinting(source, 1)],
      nameBytes: [65],
    );
    check(_bytes(changed, changed.styles.last.parts.last.record)).deepEquals(_bytes(source, style.parts[2].record));
    check(latin1.decode(_bytes(changed, changed.styles.last.parts.last.record))).contains('% retained paint comment');
  });

  test('rejects order changes across ordinary and private source boundaries', () {
    final AiNativeAppearances original = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeContainer child = original.styles.single.parts[3].record;
    final String text = appearanceOrderSource();
    for (final String replacement in [
      '%_${text.substring(child.start, child.end)}',
      '${text.substring(child.start, child.end - 1)}\n%_;',
    ]) {
      final AiNativeAppearances source = appearanceEditingModel(source: text.replaceRange(child.start, child.end, replacement));
      check(
        () => source.updateSelected(
          appearance: source.styles.single,
          parts: [reverseAppearanceChildren(source.styles.single, 1)],
          printing: [appearancePrinting(source, 1)],
          nameBytes: [65],
        ),
      ).throws<UnsupportedError>();
    }
  });

  test('protects following native state and bounds copied graph output atomically', () {
    final AiNativeAppearances dependent = appearanceEditingModel(source: appearanceOrderSource().replaceFirst('%%Trailer', '0 0 m 10 10 L S\n%%Trailer'));
    check(
      () => dependent.updateSelected(
        appearance: dependent.styles.single,
        parts: [reverseAppearanceChildren(dependent.styles.single, 1)],
        printing: [appearancePrinting(dependent, 1)],
        nameBytes: [65],
      ),
    ).throws<UnsupportedError>();
    final String text = appearanceOrderSource();
    final AiNativeAppearances bounded = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length + 10),
    );
    check(
      () => bounded.updateSelected(
        appearance: bounded.styles.single,
        parts: [reverseAppearanceChildren(bounded.styles.single, 0), reverseAppearanceChildren(bounded.styles.single, 1)],
        printing: [appearancePrinting(bounded, 1)],
        nameBytes: [65],
      ),
    ).throws<FormatException>();
    check(latin1.decode(bounded.structure.drawing.records.program.bytes)).equals(text);
  });

  test('proves uniform explicit scalar state unchanged without inferring hidden or inherited values', () {
    final String text = _uniformOrderSource();
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    check(
      () => source.updateSelected(
        appearance: source.styles.single,
        parts: [reverseAppearanceChildren(source.styles.single, 0)],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      ),
    ).returnsNormally();
    for (final String variant in [
      text.replaceFirst('1 /Visible', '0 /Visible'),
      text.replaceFirst('1 /Visible ,', ''),
      text.replaceFirst('0 1 0 0 0 Xy ', ''),
      text.replaceFirst('0 1 0 0 0 Xy', '0 0.5 0 0 0 Xy'),
      text.replaceFirst('0 /Bool (UseEvenOdd)', '1 /Bool (UseEvenOdd)'),
      text.replaceFirst('0 /Bool (UseEvenOdd) ,', ''),
    ]) {
      final AiNativeAppearances unproven = appearanceEditingModel(source: variant);
      check(
        () => unproven.updateSelected(
          appearance: unproven.styles.single,
          parts: [reverseAppearanceChildren(unproven.styles.single, 0)],
          printing: [appearancePrinting(unproven, 1)],
          nameBytes: [65],
        ),
      ).throws<UnsupportedError>();
      check(latin1.decode(unproven.structure.drawing.records.program.bytes)).equals(variant);
    }
    check(
      () => source.updateSelected(
        appearance: source.styles.single,
        parts: [
          reverseAppearanceChildren(source.styles.single, 0),
          AiNativeAppearancePartChange(part: source.styles.single.parts[1], visible: false),
        ],
        printing: [appearancePrinting(source, 1)],
        nameBytes: [65],
      ),
    ).throws<UnsupportedError>();
  });
}
