import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_editing_test.dart' show appearanceAssignment, appearanceEditingModel, appearancePrinting;
import 'ai_native_appearance_graph_test.dart' show newAppearanceFill, retainAppearanceParts;
import 'ai_native_appearance_order_test.dart' show appearanceOrderSource;
import 'ai_native_artboard_palette_test.dart' show artboardPaletteGradient, paletteArtboardSource;
import 'ai_native_artboard_patterns_test.dart' show artboardPattern, patternArtboardSource;
import 'ai_native_artboards_test.dart' show artboardModel;
import 'ai_native_objects_test.dart' show objectDictionary;

/// Retains both complete branches without selecting an Illustrator version.
String appearanceScopeVersion(String newer, {String? older = '0.4 g (Older gray) Pc'}) =>
    '%AI17_Begin_Content_if_version_gt:24 15\n$newer\n${older == null ? '' : '%AI17_Alternate_Content\n$older\n'}%AI17_End_Versioned_Content\n';

/// Exercises nested conditional cells, local names, patterns and gradients.
String get appearanceScopePalette =>
    '%AI5_BeginPalette\n0 0 Pb\n${appearanceScopeVersion('Pn (None) Pc\n${appearanceScopeVersion('0.5 g (Newer gray) Pc', older: '')}'
    '(board-0) 0 0 1 1 0 0 0 0 0 [1 0 0 1 0 0] p (Pattern) Pc', older: 'Bb 2 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB (Gradient) Pc')}PB\n%AI5_EndPalette\n';

/// Producer-observed Boolean settings and an empty reference-bearing array.
const String appearanceScopeDocument = '''/Document : /Dictionary :
1 /Bool (SnapWhileDrawing) , 1 /Bool (SnapWhileMoving_anchorPoints) ,
1 /Bool (SnapWhileMoving_paths) , 1 /Bool (SnapWhileMoving_segments) ,
1 /Bool (SnapWhileScaling) , /Array : ; (Constraint Data) , ; /Recorded ,
/Dictionary : /NotRecorded , /Dictionary : /NotRecorded ,
1 /Int (/attributes/AI11PDF_IncludeHyperlinks) , ; (PDFPresetCollection) , ; /NotRecorded ;
''';

/// Adds retained resources to a complete synthetic pair without replacing it.
String appearanceScopeSource({String? palette, String pattern = artboardPattern, String document = appearanceScopeDocument}) =>
    appearanceOrderSource().replaceFirst('%%EndSetup', '$artboardPaletteGradient$pattern${palette ?? appearanceScopePalette}$document%%EndSetup');

/// Updates both original users while keeping source style identity intact.
AiNativeAppearances _shared(AiNativeAppearances source) => source.updateShared(
  appearance: source.styles.single,
  paints: [
    AiNativePaintChange(assignment: appearanceAssignment(source.styles.single, 2, .fillColor), values: [0.7, 0.6, 0.5]),
  ],
  printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)],
);

/// Requires exact native resource bytes independently of changed style offsets.
void _retained(AiNativeAppearances result, String text) => check(latin1.decode(result.structure.drawing.records.program.bytes)).contains(text);

/// Checks complete source dependencies and every branch before shared editing.
void main() {
  test('updates shared paint beside nested conditional palettes and retained resources', () {
    for (final String palette in [appearanceScopePalette, appearanceScopePalette.replaceFirst('%AI17_Alternate_Content\n\n%AI17_End', '%AI17_End')]) {
      final String text = appearanceScopeSource(palette: palette);
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      final AiNativeAppearances changed = _shared(source);
      check(changed.styles).length.equals(1);
      check(changed.styles.single.uses).length.equals(2);
      check(appearanceAssignment(changed.styles.single, 2, .fillColor).numbers).isNotNull().deepEquals([0.7, 0.6, 0.5]);
      _retained(changed, '$artboardPaletteGradient$artboardPattern$palette$appearanceScopeDocument');
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('creates shared parts without changing conditional resources or style identity', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceScopeSource());
    final AiNativeAppearance style = source.styles.single;
    final AiNativeAppearances changed = source.updateShared(
      appearance: style,
      parts: [
        AiNativeAppearancePartChange(
          part: style.parts.first,
          children: [
            ...retainAppearanceParts(style, [1, 6, 7]),
            AiNativeAppearanceChild.create(definition: newAppearanceFill()),
          ],
        ),
      ],
      printing: [appearancePrinting(source, 0), appearancePrinting(source, 1)],
    );
    check(changed.styles.single.parts).length.equals(9);
    _retained(changed, '$artboardPaletteGradient$artboardPattern$appearanceScopePalette$appearanceScopeDocument');
  });

  test('inspects both branches and refuses executable or unresolved palette references', () {
    for (final String bad in ['(Shared) load', '1 (Shared) XW', '(missing) 0 0 1 1 0 0 0 0 0 [1 0 0 1 0 0] p Pc', 'Bb 2 (missing) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB Pc']) {
      for (final bool newer in [true, false]) {
        final String palette = '%AI5_BeginPalette\n0 0 Pb\n${appearanceScopeVersion(newer ? bad : 'Pn Pc', older: newer ? 'Pn Pc' : bad)}PB\n%AI5_EndPalette\n';
        final String text = appearanceScopeSource(palette: palette);
        final AiNativeAppearances source = appearanceEditingModel(source: text);
        check(() => _shared(source)).throws<UnsupportedError>();
        check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
      }
    }
  });

  test('refuses branches across operands paints gradients or palette boundaries', () {
    for (final String body in [
      '0 ${appearanceScopeVersion('g Pc', older: 'g Pc')}',
      'Pn ${appearanceScopeVersion('Pc', older: 'Pc')}',
      appearanceScopeVersion('Pn', older: 'Pc'),
      'Bb ${appearanceScopeVersion('2 (board-0) 0 0 0 1 1 0 0 1 0 0 1 Bg 0 BB Pc', older: null)}',
      appearanceScopeVersion('PB', older: null),
    ]) {
      final AiNativeAppearances source = appearanceEditingModel(source: appearanceScopeSource(palette: '%AI5_BeginPalette\n0 0 Pb\n$body\nPB\n%AI5_EndPalette\n'));
      check(() => _shared(source)).throws<UnsupportedError>();
    }
    for (final String palette in [
      appearanceScopeVersion('%AI5_BeginPalette\n0 0 Pb Pn Pc PB\n%AI5_EndPalette', older: null),
      '%AI5_BeginPalette\n${appearanceScopeVersion('0 0 Pb Pn Pc PB', older: '0 0 Pb Pn Pc PB')}%AI5_EndPalette\n',
    ]) {
      check(() => _shared(appearanceEditingModel(source: appearanceScopeSource(palette: palette)))).throws<UnsupportedError>();
    }
  });

  test('rejects private conditional syntax and opaque annotations inside a checked branch', () {
    for (final String palette in [
      appearanceScopePalette.replaceFirst('%AI17_Begin', '%_%AI17_Begin'),
      appearanceScopePalette.replaceFirst('Pn (None)', '%_Pn (None)'),
      appearanceScopePalette.replaceFirst('Pn (None)', '%AI24_Unknown: Shared\nPn (None)'),
    ]) {
      check(() => _shared(appearanceEditingModel(source: appearanceScopeSource(palette: palette)))).throws<UnsupportedError>();
    }
  });

  test('counts resource artwork uses and refuses uncovered or unknown owners', () {
    final String linked = artboardPattern.replaceFirst('6 () XW', '1 (Shared) XW');
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceScopeSource(pattern: linked));
    check(source.styles.single.uses).length.equals(3);
    check(() => _shared(source)).throws<UnsupportedError>();
    for (final String pattern in [
      artboardPattern.replaceFirst('0 Ae', '(Shared) load'),
      artboardPattern.replaceFirst('1 /Bool (AIPattern_Editor_AutoGrow)', '(Shared) /String (FutureOwner)'),
    ]) {
      check(() => _shared(appearanceEditingModel(source: appearanceScopeSource(pattern: pattern)))).throws<UnsupportedError>();
    }
  });

  test('retains only empty constraint arrays and explicitly typed snapping settings', () {
    for (final String document in [
      appearanceScopeDocument.replaceFirst('/Array : ; (Constraint Data)', '/Array : (Shared) , ; (Constraint Data)'),
      appearanceScopeDocument.replaceFirst('/Array : ; (Constraint Data)', '/Dictionary : ; (Constraint Data)'),
      appearanceScopeDocument.replaceFirst('1 /Bool (SnapWhileScaling)', '(Shared) /String (SnapWhileScaling)'),
      appearanceScopeDocument.replaceFirst('1 /Int (/attributes/AI11PDF_IncludeHyperlinks)', '(Shared) /String (/attributes/AI11PDF_IncludeHyperlinks)'),
    ]) {
      check(() => _shared(appearanceEditingModel(source: appearanceScopeSource(document: document)))).throws<UnsupportedError>();
    }
  });

  test('retains complete conditional cells during artboard edits without lowering deletion scope', () {
    final String palette = '%AI5_BeginPalette\n0 0 Pb\n${appearanceScopeVersion('0.3 g Pc')}PB\n%AI5_EndPalette\n';
    final AiNativeArtboards source = artboardModel(paletteArtboardSource(palette: palette));
    final AiNativeArtboards changed = source.reorder(artboards: source.artboards.reversed.toList(), cropBounds: null);
    check(latin1.decode(changed.records.program.bytes)).contains(palette);
    final AiNativeArtboards resources = artboardModel(patternArtboardSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f\n${objectDictionary(identifier: 'target')}'));
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: resources.records);
    check(() => drawing.removePaths(paths: drawing.paths)).throws<UnsupportedError>();
  });

  test('bounds nested version inspection using the original program depth limit', () {
    String cells = 'Pn Pc';
    for (int depth = 0; depth < 17; depth++) {
      cells = appearanceScopeVersion(cells, older: null);
    }
    final String text = appearanceScopeSource(palette: '%AI5_BeginPalette\n0 0 Pb\n${cells}PB\n%AI5_EndPalette\n');
    check(() => appearanceEditingModel(source: text, limits: const AiNativeLimits(maxDepth: 16))).throws<AiLimitException>();
  });
}
