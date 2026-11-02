import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_color_resources_test.dart';

/// Reads independent literal palette syntax in a qualified native source.
AiNativeSwatches _swatches({String setup = '', String body = ''}) => AiNativeSwatches.decode(
  records: colorResources(setup: setup, body: body).records,
);

/// Covers palette lifecycle without claiming palette labels are artwork links.
void main() {
  test('creates the first palette and retains explicit dual process alternatives', () {
    final AiNativeSwatches source = _swatches();
    final AiNativeSwatches first = source.createProcess(
      nameBytes: [65, 0, 255, 40],
      color: AiColor(space: .rgb, channels: [0.2, 0.3, 0.4]),
      cmykAlternative: AiColor(space: .cmyk, channels: [0.1, 0.2, 0.3, 0.4]),
    );
    check(first.palettes.single.swatches.single.nameBytes!).deepEquals([65, 0, 255, 40]);
    check(first.palettes.single.swatches.single.color!.colors.map((color) => color.space)).deepEquals([AiColorSpace.cmyk, AiColorSpace.rgb]);
    final AiNativeSwatches removed = first.remove(swatches: first.palettes.single.swatches);
    check(removed.palettes.single.swatches).isEmpty();
    check(source.palettes).isEmpty();
  });

  test('inserts in an explicit group and removes cells without flattening groups', () {
    const String setup = '%AI5_BeginPalette\n0 0 Pb\n1 (Group) 1 Pg\n0.2 g (A) Pc\n0.8 g (B) Pc\nPB\n%AI5_EndPalette';
    final AiNativeSwatches source = _swatches(setup: setup);
    final AiNativeSwatches changed = source.createProcess(
      nameBytes: [67],
      color: AiColor(space: .gray, channels: [0.5]),
      before: source.palettes.single.swatches.last,
    );
    check(changed.palettes.single.swatches.map((swatch) => latin1.decode(swatch.nameBytes!))).deepEquals(['A', 'C', 'B']);
    final AiNativeSwatches removed = changed.remove(swatches: [changed.palettes.single.swatches[1]]);
    check(latin1.decode(removed.records.program.bytes)).contains('1 (Group) 1 Pg');
    check(removed.palettes.single.swatches.map((swatch) => swatch.color!.numbers!.single)).deepEquals([0.2, 0.8]);
  });

  test('creates named cells and rejects deleting a referenced ink', () {
    final AiNativeNamedColor ink = AiNativeNamedColor(kind: .namedRgb, components: [0, 0, 0, 1, 0.2, 0.3, 0.4], nameBytes: latin1.encode('Ink'), tint: 0.25);
    final AiNativeSwatches created = _swatches().createNamed(nameBytes: latin1.encode('Display'), color: ink);
    check(created.palettes.single.swatches.single.namedColor!.components).deepEquals(ink.components);
    check(created.remove(swatches: created.palettes.single.swatches).palettes.single.swatches).isEmpty();
    final String text = latin1.decode(created.records.program.bytes).replaceFirst('%%Trailer', '0 0 0 1 0.2 0.3 0.4 (Ink) 0.5 1 Xz\n0 0 m 10 10 L f\n%%Trailer');
    final AiNativeSwatches referenced = AiNativeSwatches.decode(
      records: AiNativeRecords.decode(program: AiProgram.decode(bytes: latin1.encode(text))),
    );
    check(() => referenced.remove(swatches: referenced.palettes.single.swatches)).throws<UnsupportedError>();
  });

  test('gradient swatch blocks resource deletion until its explicit removal', () {
    final AiNativeGradientResources gradient = colorResources().create(nameBytes: [65], radial: false, stops: [colorStop(0, 0), colorStop(100, 1)], ramps: [colorRamp(1)]);
    final AiNativeSwatches created = AiNativeSwatches.decode(records: gradient.records).createGradient(nameBytes: [66], definition: gradient.definitions.single);
    final AiNativeGradientResources referenced = AiNativeGradientResources.decode(records: created.records);
    check(() => referenced.remove(definition: referenced.definitions.single)).throws<UnsupportedError>();
    check(created.palettes.single.swatches.single.gradient!.geometry.nameBytes).deepEquals([65]);
    final AiNativeSwatches removed = created.remove(swatches: created.palettes.single.swatches);
    final AiNativeGradientResources unreferenced = AiNativeGradientResources.decode(records: removed.records);
    check(unreferenced.remove(definition: unreferenced.definitions.single).definitions).isEmpty();
  });

  test('rejects captured labels stale handles ambiguous palettes and conditional edits', () {
    final AiNativeSwatches source = _swatches().createProcess(
      nameBytes: [65],
      color: AiColor(space: .gray, channels: [0]),
    );
    check(
      () => source.createProcess(
        nameBytes: [65],
        color: AiColor(space: .gray, channels: [1]),
      ),
    ).throws<ArgumentError>();
    check(() => _swatches().remove(swatches: source.palettes.single.swatches)).throws<ArgumentError>();
    check(() => source.remove(swatches: [source.palettes.single.swatches.single, source.palettes.single.swatches.single])).throws<ArgumentError>();
    const String palette = '%AI5_BeginPalette\n0 0 Pb\n0.2 g (B) Pc\nPB\n%AI5_EndPalette';
    final AiNativeSwatches multiple = _swatches(setup: '$palette\n$palette');
    check(
      () => multiple.createProcess(
        nameBytes: [67],
        color: AiColor(space: .gray, channels: [1]),
      ),
    ).throws<ArgumentError>();
    final AiNativeSwatches conditional = _swatches(
      setup: palette.replaceFirst('0.2 g (B) Pc', '%AI17_Begin_Content_if_version_gt:17 0\n0.2 g (B) Pc\n%AI17_Alternate_Content\n0.3 g (C) Pc\n%AI17_End_Versioned_Content'),
    );
    check(() => conditional.remove(swatches: [conditional.palettes.single.swatches.first])).throws<UnsupportedError>();
  });
  test('skips embedded palette-shaped bytes and refuses implicit ink redefinition', () {
    check(() => _swatches(setup: '%AI5_BeginPalette\n0 0 Pb\nPn (None)\n0 g (Black) Pc\nPB\n%AI5_EndPalette')).throws<UnsupportedError>();
    const String fake = '%AI5_BeginPalette\n0 0 Pb\n0 g (Fake) Pc\nPB\n%AI5_EndPalette';
    check(_swatches(setup: '/Procedure {\n$fake\n} def\n%%BeginDocument: nested\n$fake\n%%EndDocument').palettes).isEmpty();
    final AiNativeSwatches source = _swatches(body: '0 0 0 1 (Ink) 0.5 Xs\n0 0 m 10 10 L f');
    check(
      () => source.createNamed(
        nameBytes: [65],
        color: AiNativeNamedColor(kind: .namedCmyk, components: [1, 0, 0, 0], nameBytes: latin1.encode('Ink'), tint: 0.5),
      ),
    ).throws<ArgumentError>();
  });
}
