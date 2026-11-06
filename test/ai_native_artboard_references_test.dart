import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_lifecycle_test.dart' show artboardText, newArtboard;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;
import 'ai_native_objects_test.dart' show objectDictionary;

/// Retains a process-paint default whose name happens to match an artboard UUID.
const String artboardSimpleStyle = '''%_/KnownStyle : (board-0) /Name ,
%_/SimpleStyle : 0 O 0.2 0.3 0.4 Xa 0 R 0 0 0 1 K
%_0 1 0 0 0 Xy 0 J 0 j 1 w 10 M [] 0 d 0 XR 1 1 Xd /Paint ; /Def ;
''';

/// Keeps unused plug-in names, style references and registration colors declarative.
String _setupInventories({bool rgb = true}) =>
    '''%AI5_Begin_NonPrinting
Np
%AI8_PluginGroupInfo
(board-0) (Unused tool) (Example.aip)
%AI9_BeginArtStyles
$artboardSimpleStyle%AI9_EndArtStyles
%AI9_BeginArtStyleList
(board-0)
%AI9_EndArtStyleList
%AI24_BeginSymbolList
%AI24_EndSymbolList
%AI5_End_NonPrinting--
%AI5_BeginPalette
0 0 Pb
0 0 0 1 ${rgb ? '0 0 0 ' : ''}([Registration]) 0 ${rgb ? '1 Xz' : 'Xs'}
([Registration]) Pc
0.1 0.2 0.3 Xa (Process) Pc
PB
%AI5_EndPalette
''';

/// Encodes unused typography resources with no story, frame or artwork instance.
PsEngineDictionary emptyArtboardTextEngine({Map<String, PsEngineValue> resources = const {}, Map<String, PsEngineValue> objects = const {}, Map<String, PsEngineValue> extra = const {}}) =>
    PsEngineDictionary(
      values: {
        '98': PsEngineDictionary(values: {'0': PsEngineNumber(value: 9)}),
        '0': PsEngineDictionary(values: resources),
        '1': PsEngineDictionary(values: objects),
        ...extra,
      },
    );

/// Wraps each binary owner independently so source bytes and budgets can be checked.
String artboardTextOwner(String type, PsEngineValue engine) =>
    '''%_/$type : /ASCII85Decode ,
%${latin1.decode(PdfFilters.encodeAscii85(bytes: PsEngineCodec.encode(value: engine, bareDictionary: true)))}
%_${type == 'AI11TextDocument' ? '8000 8500 /RulerOrigin ,' : ''} ;
''';

/// Builds a complete native document with separate main and undo-free text data.
String artboardReferenceSource({PsEngineValue? main, PsEngineValue? undo, bool withUndo = true, String body = '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f'}) => artboardSource(
  extra:
      '''$artboardSimpleStyle
%AI11_BeginTextDocument
${artboardTextOwner('AI11TextDocument', main ?? emptyArtboardTextEngine())}${withUndo ? artboardTextOwner('AI11UndoFreeTextDocument', undo ?? emptyArtboardTextEngine()) : ''}%AI11_EndTextDocument
''',
  body: body,
).replaceFirst('%%EndComments', '%AI3_TemplateBox: 0 -100 200 0\n%AI24_LargeCanvasScale: 10\n%%PageOrigin: 3 4\n%%EndComments');

/// Checks all non-Document bytes and the independent global coordinate basis.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
  final AiNativeDocumentSettings settings = AiNativeDocumentSettings.decode(records: after.records);
  check(settings.textRulerOrigins.single.coordinates).deepEquals([8000.0, 8500.0]);
  check(settings.header['AI3_TemplateBox']!.values).deepEquals([0.0, -100.0, 200.0, 0.0]);
  check(settings.header['AI24_LargeCanvasScale']!.values).deepEquals([10.0]);
}

/// Exercises meaningful ownership boundaries rather than rendering the document.
void main() {
  test('isolates retained styles and empty text across every native artboard operation', () {
    final String source = artboardReferenceSource();
    final AiNativeArtboards model = artboardModel(source);
    final AiNativeArtboards resized = model.resize(artboard: model.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -30, right: 120, top: 140), cropBounds: null);
    final AiNativeArtboards added = resized.create(definition: newArtboard(), index: 0, lastArtboardId: 68, cropBounds: null);
    final AiNativeArtboards reordered = added.reorder(artboards: added.artboards.reversed.toList(), cropBounds: null);
    final AiNativeArtboards removed = reordered.remove(artboards: [reordered.artboards.last], activeArtboard: null, cropBounds: null);
    for (final AiNativeArtboards result in [resized, added, reordered, removed]) {
      _retained(model, result);
    }
    check(removed.artboards.map((board) => board.identifier)).deepEquals(['board-2', 'board-1', 'board-0']);
    check(removed.artboards.last.bounds.left).equals(-20);
    check(artboardText(model)).equals(source);
  });

  test('preserves unused font and style namespaces while keeping empty frame arrays', () {
    final PsEngineDictionary engine = emptyArtboardTextEngine(
      resources: {
        '1': PsEngineDictionary(
          values: {
            '0': PsEngineArray(
              values: [
                PsEngineDictionary(
                  values: {
                    '0': PsEngineDictionary(values: {'97': PsEngineString.fromText(text: 'board-0')}),
                  },
                ),
              ],
            ),
            '1': PsEngineArray(
              values: [
                PsEngineDictionary(values: {'0': PsEngineNumber(value: 0)}),
              ],
            ),
          },
        ),
        '8': PsEngineDictionary(
          values: {
            '0': PsEngineArray(values: []),
            '1': PsEngineArray(values: []),
          },
        ),
      },
      objects: {
        '1': PsEngineArray(values: []),
        '2': PsEngineDictionary(values: {}),
      },
    );
    final AiNativeArtboards model = artboardModel(artboardReferenceSource(main: engine));
    final AiNativeArtboards result = model.remove(artboards: [model.artboards.first], activeArtboard: null, cropBounds: null);
    _retained(model, result);
    check(result.artboards).length.equals(2);
  });

  test('supports an absent undo-free snapshot and optional wrapper comments', () {
    for (final bool wrappers in [true, false]) {
      final String source = artboardReferenceSource(withUndo: false);
      final AiNativeArtboards model = artboardModel(wrappers ? source : source.replaceAll('%AI11_BeginTextDocument', '').replaceAll('%AI11_EndTextDocument', ''));
      _retained(model, model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null));
    }
  });

  test('retains literal setup inventories without instantiating plug-ins or colors', () {
    for (final bool rgb in [false, true]) {
      final AiNativeArtboards model = artboardModel(artboardReferenceSource().replaceFirst(artboardSimpleStyle, _setupInventories(rgb: rgb)));
      _retained(model, model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null));
    }
  });

  test('refuses opaque inventories conditional declarations and dangling style uses', () {
    final String source = artboardReferenceSource().replaceFirst(artboardSimpleStyle, _setupInventories());
    for (final String changed in [
      source.replaceFirst('(Example.aip)', '(Example.aip) (board-0)'),
      source.replaceFirst('(Example.aip)', 'load'),
      source.replaceFirst('%AI24_EndSymbolList', '(board-0)\n%AI24_EndSymbolList'),
      source.replaceFirst('%AI9_BeginArtStyleList\n(board-0)', '%AI9_BeginArtStyleList\n(missing)'),
      source.replaceFirst('%AI9_EndArtStyles', '/Future : (board-0) /Reference , ;\n%AI9_EndArtStyles'),
      source.replaceFirst('%AI8_PluginGroupInfo', '%AI17_Begin_Content_if_version_gt:24 4\n%AI8_PluginGroupInfo').replaceFirst('(Example.aip)', '(Example.aip)\n%AI17_End_Versioned_Content'),
      source.replaceFirst('0.1 0.2 0.3 Xa', '(board-0) load'),
      source.replaceFirst('0.1 0.2 0.3 Xa', '%AI24_Future: board-0\n0.1 0.2 0.3 Xa'),
    ]) {
      final AiNativeArtboards model = artboardModel(changed);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(artboardText(model)).equals(changed);
    }
  });

  test('rejects unfinished inventory sections and palette cells', () {
    final String source = artboardReferenceSource().replaceFirst(artboardSimpleStyle, _setupInventories());
    for (final String changed in [
      source.replaceFirst('%AI9_EndArtStyleList', ''),
      source.replaceFirst('([Registration]) Pc', '([Registration]) Pc 0 g'),
      source.replaceFirst('0.1 0.2 0.3 Xa (Process) Pc', '0.1 0.2 0.3 Xa'),
    ]) {
      final AiNativeArtboards model = artboardModel(changed);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
      check(artboardText(model)).equals(changed);
    }
  });

  test('qualifies unused text namespaces independently when deleting artwork identities', () {
    final AiNativeArtboards model = artboardModel(artboardReferenceSource(body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f\n${objectDictionary(identifier: 'path_target')}'));
    final AiNativeDrawing drawing = AiNativeDrawing.decode(records: model.records);
    _retained(model, model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null));
    final AiNativeDrawing removed = drawing.removePaths(paths: drawing.paths);
    check(removed.paths).isEmpty();
    check(removed.records.program.bytes.take(removed.records.program.bodyStart)).deepEquals(drawing.records.program.bytes.take(drawing.records.program.bodyStart));
    final AiNativeDrawing unknown = AiNativeDrawing.decode(
      records: artboardModel(
        artboardReferenceSource(
          main: emptyArtboardTextEngine(extra: {'99': PsEngineString.fromText(text: 'path_target')}),
          body: '0 A 0 Xw 0.3 g 10 -10 m 30 -20 L f\n${objectDictionary(identifier: 'path_target')}',
        ),
      ).records,
    );
    check(() => unknown.removePaths(paths: unknown.paths)).throws<UnsupportedError>();
  });

  test('rejects unknown simple-style fields and executable or reference-bearing paints', () {
    final String source = artboardReferenceSource();
    for (final String changed in [
      source.replaceFirst('/SimpleStyle :', '/SimpleStyle : (board-0) /Reference ,'),
      source.replaceFirst('/Paint ;', '(board-0) load /Paint ;'),
      source.replaceFirst('1 1 Xd', '1 1 FuturePaint'),
      source.replaceFirst('/Paint ;', '%AI24_FutureReference: board-0\n%_/Paint ;'),
    ]) {
      final AiNativeArtboards model = artboardModel(changed);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(artboardText(model)).equals(changed);
    }
    final AiNativeArtboards malformed = artboardModel(source.replaceFirst('0.2 0.3 0.4 Xa', '2 3 4 Xa'));
    check(() => malformed.reorder(artboards: malformed.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
  });

  test('rejects incomplete text objects and unknown ATE owners in either snapshot', () {
    for (final PsEngineDictionary engine in [
      emptyArtboardTextEngine(
        objects: {
          '1': PsEngineArray(values: [PsEngineDictionary(values: {})]),
        },
      ),
      emptyArtboardTextEngine(
        resources: {
          '8': PsEngineDictionary(
            values: {
              '0': PsEngineArray(values: [PsEngineDictionary(values: {})]),
            },
          ),
        },
      ),
      emptyArtboardTextEngine(extra: {'Future': PsEngineNumber(value: 0)}),
      emptyArtboardTextEngine(resources: {'Future': PsEngineDictionary(values: {})}),
      emptyArtboardTextEngine(objects: {'4': PsEngineArray(values: [])}),
      emptyArtboardTextEngine(
        objects: {
          '0': PsEngineDictionary(values: {'Artboard': PsEngineNumber(value: 0)}),
        },
      ),
      emptyArtboardTextEngine(
        objects: {
          '2': PsEngineDictionary(values: {'Future': const PsEngineToken(value: 'future')}),
        },
      ),
      emptyArtboardTextEngine(
        extra: {
          '98': PsEngineDictionary(values: {'0': PsEngineNumber(value: 10)}),
        },
      ),
    ]) {
      for (final bool undo in [false, true]) {
        final AiNativeArtboards model = artboardModel(artboardReferenceSource(main: undo ? null : engine, undo: undo ? engine : null));
        check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      }
    }
  });

  test('refuses dangling text resource indices before changing any artboard', () {
    final AiNativeArtboards model = artboardModel(
      artboardReferenceSource(
        main: emptyArtboardTextEngine(
          resources: {
            '1': PsEngineDictionary(
              values: {
                '0': PsEngineArray(values: []),
                '1': PsEngineArray(
                  values: [
                    PsEngineDictionary(values: {'0': PsEngineNumber(value: 0)}),
                  ],
                ),
              },
            ),
          },
        ),
      ),
    );
    check(() => model.remove(artboards: [model.artboards.first], activeArtboard: null, cropBounds: null)).throws<FormatException>();
  });

  test('requires an explicit origin unique text owners and unambiguous wrapper ownership', () {
    final String source = artboardReferenceSource();
    for (final String changed in [
      source.replaceFirst('8000 8500 /RulerOrigin ,', ''),
      source.replaceFirst('8000 8500 /RulerOrigin ,', '8000 /RulerOrigin ,'),
      source.replaceFirst('%AI11_EndTextDocument', '%_/AI11Text : 0 /StoryIndex , ;\n%AI11_EndTextDocument'),
      source.replaceFirst('%AI11_EndTextDocument', '${artboardTextOwner('AI11TextDocument', emptyArtboardTextEngine())}%AI11_EndTextDocument'),
      source.replaceFirst('%AI11_EndTextDocument', ''),
      source.replaceFirst('%AI11_BeginTextDocument', '%AI11_EndTextDocument'),
      source.replaceFirst('8000 8500 /RulerOrigin ,', '8000 8500 /RulerOrigin ,\n%AI24_Future: board-0\n%_'),
      source
          .replaceFirst('%AI11_BeginTextDocument', '%AI17_Begin_Content_if_version_gt:24 4\n%AI11_BeginTextDocument')
          .replaceFirst('%AI11_EndTextDocument', '%AI11_EndTextDocument\n%AI17_End_Versioned_Content'),
    ]) {
      final AiNativeArtboards model = artboardModel(changed);
      check(() => model.reorder(artboards: model.artboards.reversed.toList(), cropBounds: null)).throws<UnsupportedError>();
      check(artboardText(model)).equals(changed);
    }
  });

  test('bounds aggregate decoded bytes across independently compressed text owners', () {
    final PsEngineDictionary engine = emptyArtboardTextEngine(
      objects: {
        '2': PsEngineDictionary(values: {'97': PsEngineString(bytes: List.filled(12000, 0))}),
      },
    );
    final String source = artboardReferenceSource(main: engine, undo: engine).replaceFirst('%%EndComments', '% ${'padding' * 800}\n%%EndComments');
    final int decoded = PsEngineCodec.encode(value: engine, bareDictionary: true).length;
    check(source.length).isGreaterThan(decoded);
    check(source.length).isLessThan(2 * decoded);
    final AiNativeArtboards limited = artboardModel(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => limited.reorder(artboards: limited.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    check(artboardText(limited)).equals(source);
  });

  test('bounds hidden engine nodes with the original native token policy', () {
    final PsEngineDictionary engine = emptyArtboardTextEngine(
      objects: {
        '2': PsEngineDictionary(values: {'66': PsEngineArray(values: List.filled(1000, const PsEngineBoolean(value: false)))}),
      },
    );
    final String source = artboardReferenceSource(main: engine);
    final AiNativeArtboards limited = artboardModel(source, limits: const AiNativeLimits(maxTokens: 600));
    check(() => limited.reorder(artboards: limited.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    check(artboardText(limited)).equals(source);
  });
}
