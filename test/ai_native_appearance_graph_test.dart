import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearancePrinting;
import 'ai_native_appearance_order_test.dart' show appearanceOrderSource, reverseAppearanceChildren;

/// Authored process alternatives used without any kit-side color conversion.
AiNativeAppearancePartDefinition newAppearanceFill({bool visible = true}) => AiNativeAppearancePartDefinition(
  kind: .fill,
  visible: visible,
  colors: [
    AiColor(space: .cmyk, channels: [1, 0, 0, 0]),
    AiColor(space: .rgb, channels: [0, 1, 1]),
  ],
);

/// Retains source children without equating their handles with new snapshots.
List<AiNativeAppearanceChild> retainAppearanceParts(AiNativeAppearance style, Iterable<int> indices) => indices.map((index) => AiNativeAppearanceChild.retain(part: style.parts[index])).toList();

/// Isolates the last source user with one synchronized host-supplied group.
AiNativeAppearances _selected(AiNativeAppearances source, List<AiNativeAppearancePartChange> parts, {List<AiNativePaintChange> paints = const []}) => source.updateSelected(
  appearance: source.styles.single,
  parts: parts,
  paints: paints,
  printing: [appearancePrinting(source, 1)],
  nameBytes: latin1.encode('Graph'),
);

/// Keeps exact source data available for moved/copied subtree assertions.
List<int> _bytes(AiNativeAppearances source, AiNativeContainer record) => source.structure.drawing.records.program.bytes.sublist(record.start, record.end);

/// Builds an empty existing stack with either supported final-field delimiter.
String _emptySource({bool comma = true}) {
  final String text = appearanceOrderSource();
  return text.replaceRange(
    text.indexOf('/KnownStyle'),
    text.indexOf('%%EndSetup'),
    '/KnownStyle : (Shared) /Name , /ActiveStyle : /CompoundFilter : (Stack Style Filter) 0 0 /Filter , 1 /Visible ${comma ? ',' : ''} % retained empty stack\n; /Execution ; /Def ;\n',
  );
}

/// Covers explicit child lifecycle, source ownership, immutable data and limits.
void main() {
  test('creates typed paints structures and offset strokes with explicit settings', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearancePartDefinition stroke = AiNativeAppearancePartDefinition(
      kind: .stroke,
      colors: [
        AiColor(space: .gray, channels: [0.25]),
      ],
      overprint: true,
      opacity: 0.5,
      evenOdd: true,
      strokeWidth: 3.5,
      lineCap: 1,
      lineJoin: 2,
      miterLimit: 8,
      dash: [2.5, 1.5],
      dashPhase: -1.5,
      strokeAlignment: .outside,
      alignmentLabelBytes: [0, 40, 92, 255],
    );
    final AiNativeAppearances changed = _selected(source, [
      AiNativeAppearancePartChange(
        part: style.parts[0],
        children: [
          ...retainAppearanceParts(style, [1]),
          AiNativeAppearanceChild.create(
            definition: AiNativeAppearancePartDefinition(
              kind: .stack,
              children: [
                AiNativeAppearanceChild.create(definition: newAppearanceFill()),
                AiNativeAppearanceChild.create(definition: stroke),
                AiNativeAppearanceChild.create(definition: AiNativeAppearancePartDefinition(kind: .conduit)),
              ],
            ),
          ),
          ...retainAppearanceParts(style, [6, 7]),
        ],
      ),
    ]);
    final AiNativeAppearance result = changed.styles.last;
    check(result.parts).length.equals(12);
    check(result.parts[6].kind).equals(AiNativeAppearancePartKind.stack);
    check(appearanceAssignment(result, 7, .fillColor).colors.map((color) => color.space)).deepEquals([AiColorSpace.cmyk, AiColorSpace.rgb]);
    check(appearanceAssignment(result, 8, .strokeWidth).numbers).isNotNull().deepEquals([3.5]);
    check(appearanceAssignment(result, 8, .dash).dash!.lengths).deepEquals([2.5, 1.5]);
    check(appearanceAssignment(result, 8, .dash).dash!.phase).equals(-1.5);
    check(result.parts[8].strokeAlignment).equals(AiNativeStrokeAlignment.outside);
    check(result.parts[8].parameters!['DisplayString']!.stringBytes).isNotNull().deepEquals([0, 40, 92, 255]);
    check(_bytes(changed, changed.styles.first.definition)).deepEquals(_bytes(source, style.definition));
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(appearanceOrderSource());
  });

  test('removes selected children and retains exact data of each surviving subtree', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = _selected(source, [
      AiNativeAppearancePartChange(part: style.parts[1], children: retainAppearanceParts(style, [2, 4])),
    ]);
    check(changed.styles.last.parts).length.equals(6);
    check(_bytes(changed, changed.styles.last.parts[2].record)).deepEquals(_bytes(source, style.parts[2].record));
    check(_bytes(changed, changed.styles.last.parts[3].record)).deepEquals(_bytes(source, style.parts[4].record));
    final AiNativeAppearances empty = _selected(source, [AiNativeAppearancePartChange(part: style.parts.first, children: [])]);
    check(empty.styles.last.parts).length.equals(1);
    check(empty.styles.last.parts.single.childIndices).isEmpty();
  });

  test('creates chain children and every stroke alignment without converting process colors', () {
    for (final AiNativeStrokeAlignment alignment in AiNativeStrokeAlignment.values) {
      for (final AiColor color in [
        AiColor(space: .gray, channels: [0.25]),
        AiColor(space: .rgb, channels: [0.2, 0.4, 0.6]),
        AiColor(space: .cmyk, channels: [0.1, 0.2, 0.3, 0.4]),
      ]) {
        final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
        final AiNativeAppearances changed = _selected(source, [
          AiNativeAppearancePartChange(
            part: source.styles.single.parts.first,
            children: [
              AiNativeAppearanceChild.create(
                definition: AiNativeAppearancePartDefinition(
                  kind: .chain,
                  children: [
                    AiNativeAppearanceChild.create(
                      definition: AiNativeAppearancePartDefinition(
                        kind: .stroke,
                        colors: [color],
                        strokeAlignment: alignment,
                        alignmentLabelBytes: alignment == .center ? null : latin1.encode(alignment.name),
                      ),
                    ),
                    AiNativeAppearanceChild.create(definition: AiNativeAppearancePartDefinition(kind: .conduit)),
                  ],
                ),
              ),
            ],
          ),
        ]);
        check(changed.styles.last.parts[1].kind).equals(AiNativeAppearancePartKind.chain);
        check(changed.styles.last.parts[2].strokeAlignment).equals(alignment);
        check(appearanceAssignment(changed.styles.last, 2, .strokeColor).colors.single.space).equals(color.space);
        check(appearanceAssignment(changed.styles.last, 2, .strokeColor).colors.single.channels).deepEquals(color.channels);
      }
    }
  });

  test('copies original snapshots independently of simultaneous retained paint edits', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = _selected(
      source,
      [
        AiNativeAppearancePartChange(
          part: style.parts.first,
          children: [
            ...retainAppearanceParts(style, [1, 6, 7]),
            AiNativeAppearanceChild.copy(part: style.parts[2]),
            AiNativeAppearanceChild.copy(part: style.parts[2]),
          ],
        ),
      ],
      paints: [
        AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0.7, 0.6, 0.5]),
      ],
    );
    check(changed.styles.last.parts).length.equals(10);
    check(appearanceAssignment(changed.styles.last, 2, .fillColor).numbers).isNotNull().deepEquals([0.7, 0.6, 0.5]);
    for (final int index in [8, 9]) {
      check(_bytes(changed, changed.styles.last.parts[index].record)).deepEquals(_bytes(source, style.parts[2].record));
    }
  });

  test('reparents complete parts between changed owners and out of removed ancestors', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances moved = _selected(source, [
      AiNativeAppearancePartChange(part: style.parts[0], children: retainAppearanceParts(style, [1, 7])),
      AiNativeAppearancePartChange(part: style.parts[1], children: retainAppearanceParts(style, [6, 2, 3, 4, 5])),
    ]);
    check(moved.styles.last.parts).length.equals(8);
    check(moved.styles.last.parts[2].parentIndex).equals(1);
    check(_bytes(moved, moved.styles.last.parts[2].record)).deepEquals(_bytes(source, style.parts[6].record));
    final AiNativeAppearances extracted = _selected(source, [
      AiNativeAppearancePartChange(part: style.parts[0], children: retainAppearanceParts(style, [2, 6, 7])),
    ]);
    check(extracted.styles.last.parts).length.equals(4);
    check(_bytes(extracted, extracted.styles.last.parts[1].record)).deepEquals(_bytes(source, style.parts[2].record));
  });

  test('combines shared child creation with nested order and scalar changes', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateShared(
      appearance: style,
      parts: [
        AiNativeAppearancePartChange(
          part: style.parts[0],
          children: [
            ...retainAppearanceParts(style, [1, 6, 7]),
            AiNativeAppearanceChild.create(definition: newAppearanceFill()),
          ],
        ),
        reverseAppearanceChildren(style, 1),
        AiNativeAppearancePartChange(part: style.parts[2], visible: true),
      ],
      printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)],
    );
    check(changed.styles).length.equals(1);
    check(changed.styles.single.parts).length.equals(9);
    check(changed.styles.single.parts[5].visible).equals(true);
    check(changed.styles.single.uses).length.equals(2);
  });

  test('inserts into empty stacks and retains delimiters and intervening comments', () {
    for (final bool comma in [true, false]) {
      final AiNativeAppearances source = appearanceEditingModel(source: _emptySource(comma: comma));
      final AiNativeAppearances unchanged = _selected(source, [AiNativeAppearancePartChange(part: source.styles.single.parts.first, children: [])]);
      check(_bytes(unchanged, unchanged.styles.last.parts.first.record)).deepEquals(_bytes(source, source.styles.single.parts.first.record));
      final AiNativeAppearances changed = _selected(source, [
        AiNativeAppearancePartChange(
          part: source.styles.single.parts.first,
          children: [AiNativeAppearanceChild.create(definition: newAppearanceFill())],
        ),
      ]);
      check(changed.styles.last.parts).length.equals(2);
      check(latin1.decode(_bytes(changed, changed.styles.last.definition))).contains('% retained empty stack');
    }
    final String text = appearanceOrderSource().replaceFirst('; /Part ,', '; % retained field comment\n/Part % retained key comment\n,');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearances changed = _selected(source, [AiNativeAppearancePartChange(part: source.styles.single.parts[1], children: [])]);
    check(latin1.decode(_bytes(changed, changed.styles.last.definition))).contains('% retained field comment');
    check(latin1.decode(_bytes(changed, changed.styles.last.definition))).contains('% retained key comment');
  });

  test('preserves private execution prefixes when creating copying and moving parts', () {
    final String text = appearanceOrderSource();
    final AiNativeAppearances ordinary = appearanceEditingModel(source: text);
    final AiNativeContainer owner = ordinary.styles.single.resource.definition.source as AiNativeContainer;
    final String fragment = text.substring(owner.start, owner.end);
    final AiNativeAppearances source = appearanceEditingModel(source: text.replaceFirst(fragment, fragment.split('\n').map((line) => '%_$line').join('\n')));
    final AiNativeAppearances changed = _selected(source, [
      AiNativeAppearancePartChange(
        part: source.styles.single.parts.first,
        children: [
          AiNativeAppearanceChild.copy(part: source.styles.single.parts[1]),
          AiNativeAppearanceChild.create(definition: newAppearanceFill()),
          ...retainAppearanceParts(source.styles.single, [6, 7]),
        ],
      ),
    ]);
    check(changed.styles.last.parts).length.equals(9);
    check(_bytes(changed, changed.styles.last.parts[1].record)).deepEquals(_bytes(source, source.styles.single.parts[1].record));
    check(changed.styles.last.parts[6].kind).equals(AiNativeAppearancePartKind.fill);
  });

  test('rejects cycles duplicate owners foreign handles and edits to removed parts', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceOrderSource());
    final AiNativeAppearance style = source.styles.single;
    for (final List<AiNativeAppearancePartChange> parts in [
      [
        AiNativeAppearancePartChange(part: style.parts[1], children: retainAppearanceParts(style, [0])),
      ],
      [
        AiNativeAppearancePartChange(part: style.parts[0], children: retainAppearanceParts(style, [1, 1])),
      ],
      [
        AiNativeAppearancePartChange(
          part: style.parts[0],
          children: [AiNativeAppearanceChild.copy(part: appearanceEditingModel().styles.single.parts[1])],
        ),
      ],
      [AiNativeAppearancePartChange(part: style.parts[0], children: []), AiNativeAppearancePartChange(part: style.parts[2], visible: true)],
      [
        AiNativeAppearancePartChange(
          part: style.parts[0],
          children: [AiNativeAppearanceChild.copy(part: style.parts[1])],
        ),
        reverseAppearanceChildren(style, 1),
      ],
    ]) {
      check(() => _selected(source, parts)).throws<ArgumentError>();
    }
    check(
      () => _selected(
        source,
        [AiNativeAppearancePartChange(part: style.parts[0], children: [])],
        paints: [
          AiNativePaintChange(assignment: appearanceAssignment(style, 2, .fillColor), values: [0, 0, 0]),
        ],
      ),
    ).throws<ArgumentError>();
    check(() => AiNativeAppearancePartChange(part: style.parts[0], childOrder: [], children: [])).throws<ArgumentError>();
    check(() => _selected(source, [AiNativeAppearancePartChange(part: style.parts[2], children: [])])).throws<UnsupportedError>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(appearanceOrderSource());
    final AiNativeContainer child = style.parts[3].record;
    final String text = appearanceOrderSource();
    final AiNativeAppearances mixed = appearanceEditingModel(source: text.replaceRange(child.start, child.start, '%_'));
    check(() => _selected(mixed, [AiNativeAppearancePartChange(part: mixed.styles.single.parts.first, children: [])])).throws<UnsupportedError>();
  });

  test('checks newly introduced native state before accepting following artwork', () {
    for (final bool reset in [false, true]) {
      final String text = _emptySource().replaceFirst('%%Trailer', '0 g 0 O 0 XR ${reset ? '0 1 0 0 0 Xy ' : ''}0 0 m 10 10 L f\n%%Trailer');
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      AiNativeAppearances edit() => _selected(source, [
        AiNativeAppearancePartChange(
          part: source.styles.single.parts.first,
          children: [AiNativeAppearanceChild.create(definition: newAppearanceFill())],
        ),
      ]);
      if (reset) {
        check(edit).returnsNormally();
      } else {
        check(edit).throws<UnsupportedError>();
      }
    }
  });

  test('owns definition payloads and rejects invalid kinds colors labels and numeric data', () {
    final List<double> dash = [2, 3];
    final List<int> label = [65];
    final List<AiColor> colors = [
      AiColor(space: .rgb, channels: [0.2, 0.4, 0.6]),
    ];
    final AiNativeAppearancePartDefinition definition = AiNativeAppearancePartDefinition(kind: .stroke, colors: colors, dash: dash, strokeAlignment: .inside, alignmentLabelBytes: label);
    dash.clear();
    label.clear();
    colors.clear();
    check(definition.dash).deepEquals([2.0, 3.0]);
    check(definition.alignmentLabelBytes!).deepEquals([65]);
    check(definition.colors).length.equals(1);
    check(definition.children.clear).throws<UnsupportedError>();
    check(definition.colors.clear).throws<UnsupportedError>();
    for (final void Function() create in [
      () => AiNativeAppearancePartDefinition(kind: .effect),
      () => AiNativeAppearancePartDefinition(kind: .fill),
      () => AiNativeAppearancePartDefinition(kind: .conduit, opacity: 0.5),
      () => AiNativeAppearancePartDefinition(kind: .stroke, colors: definition.colors, strokeAlignment: .inside),
      () => AiNativeAppearancePartDefinition(kind: .fill, colors: definition.colors, alignmentLabelBytes: [65]),
      () => AiNativeAppearancePartDefinition(kind: .fill, colors: [...definition.colors, ...definition.colors]),
      () => AiNativeAppearancePartDefinition(kind: .stroke, colors: definition.colors, dash: [0, 0]),
      () => AiNativeAppearancePartDefinition(kind: .stroke, colors: definition.colors, strokeWidth: double.infinity),
      () => AiNativeAppearancePartDefinition(kind: .stroke, colors: definition.colors, lineCap: 3),
      () => AiNativeAppearancePartDefinition(
        kind: .fill,
        colors: definition.colors,
        children: [AiNativeAppearanceChild.create(definition: newAppearanceFill())],
      ),
    ]) {
      check(create).throws<ArgumentError>();
    }
  });

  test('bounds deep shared definition expansion and source-copy growth before publishing', () {
    AiNativeAppearancePartDefinition definition = newAppearanceFill();
    for (int depth = 0; depth < 32; depth++) {
      definition = AiNativeAppearancePartDefinition(
        kind: .stack,
        children: [AiNativeAppearanceChild.create(definition: definition)],
      );
    }
    final String text = appearanceOrderSource();
    final AiNativeAppearances depthBounded = appearanceEditingModel(source: text, limits: const AiNativeLimits(maxDepth: 16));
    check(
      () => _selected(depthBounded, [
        AiNativeAppearancePartChange(
          part: depthBounded.styles.single.parts.first,
          children: [AiNativeAppearanceChild.create(definition: definition)],
        ),
      ]),
    ).throws<AiLimitException>();
    final AiNativeAppearances byteBounded = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length + 10),
    );
    check(
      () => _selected(byteBounded, [
        AiNativeAppearancePartChange(
          part: byteBounded.styles.single.parts.first,
          children: [for (int index = 0; index < 20; index++) AiNativeAppearanceChild.copy(part: byteBounded.styles.single.parts[1])],
        ),
      ]),
    ).throws<AiLimitException>();
    check(latin1.decode(byteBounded.structure.drawing.records.program.bytes)).equals(text);
  });
}
