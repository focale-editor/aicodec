import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artboard_brushes_test.dart' show artboardBrush;
import 'ai_native_artboard_lifecycle_test.dart' show newArtboard;
import 'ai_native_artboard_symbols_test.dart' show symbolArtboardSource;
import 'ai_native_artboards_test.dart' show artboardModel, artboardSource;

/// Escapes arbitrary literal bytes without introducing executable operands.
String _literal(String value) => '(${value.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)')})';

/// Writes a descriptor with continuations deliberately splitting words/numbers.
String artboardBrushDescriptor({String plugin = 'Adobe Calligraphic Brush Tool', String name = 'board-0', String data = '1 5 5 0 0 90 90 0 0 0 0', int fragmentLength = 19}) {
  final StringBuffer result = StringBuffer('%AI8_BeginPluginObject\n${_literal(plugin)}\n${_literal(name)}\n');
  for (int start = 0; start < data.length; start += fragmentLength) {
    final int end = start + fragmentLength < data.length ? start + fragmentLength : data.length;
    result.writeln('${_literal(data.substring(start, end))} ${end == data.length ? '.' : '-'}');
  }
  return '$result%AI8_EndPluginObject\n';
}

/// Retains a calligraphic style with its owned stroke and independent brush name.
String artboardCalligraphicStyle({String name = 'board-0', String plugin = 'CalligraphicBrushTool.aip'}) =>
    '''/KnownStyle : (board-0) /Name ,
/ActiveStyle : /BasicFilter : (Adobe Calligraphic Brush Tool) 1 0 /Filter ,
1 /Visible , ($plugin) /PluginFileName , (Calligraphic Brush) /Title , 2 /FillOrStroke ,
/Dictionary : /NotRecorded ,
/GObjRef : ${_literal(name)} (Adobe Calligraphic Brush Tool) /PluginObject ; (Brush) ,
/StrokeStyle : 0 R 0 G 0 1 0 0 0 Xy 0 J 0 j 2 w 10 M []0 d 0 XR 1 0 Xd /Def ; (StrokeStyle) ,
90 /Real (Angle) , 5 /Real (Diameter) , 0 /Real (Roundness) ,
0 /Real (AngleVariation) , 0 /Real (DiameterVariation) , 0 /Real (RoundnessVariation) ,
0 /Int (AngleDependsOn) , 0 /Int (DiameterDependsOn) , 0 /Int (RoundnessDependsOn) , 0 /Int (AngleRelativeTo) ,
${_literal(name)} /UnicodeString (DisplayString) , ; /Dict ; /Execution ; /Def ;
''';

/// A version-two tile descriptor with process color and retained scalar options.
String _tileData({String color = '0 1'}) => '2 / board-0/ / / / / 0 0/ $color / 1 0 1 0 1 0 0 0 1 1 0 1 25 25 1';

/// Builds independent brush namespaces and a panel whose order differs from setup.
String artboardBrushDescriptors() {
  const List<String> plugins = ['Adobe Calligraphic Brush Tool', 'Adobe ArtOnPath Brush Tool', 'Adobe PatternOnPath Brush Tool', 'Adobe dBrush Brush Tool'];
  return '${artboardBrush(art: '0.5 g 0 0 m 10 0 L 10 10 L f')}${artboardBrushDescriptor()}'
      '${artboardBrushDescriptor(
        plugin: plugins[1],
        data: _tileData(color: '5 0.2 0.4 0.6'),
      )}'
      '${artboardBrushDescriptor(plugin: plugins[2], data: _tileData())}'
      '${artboardBrushDescriptor(plugin: plugins[3], data: '0 4 0.5 0.75 0.33 0.75 1.5 6 AI_BristleBrushLibary_CS5 05_Round_Fan')}'
      '${artboardBrushDescriptor(plugin: 'Adobe Brush Manager Order', name: 'Adobe Brush Manager Order', data: plugins.reversed.map((name) => ' $name/ board-0/').join())}';
}

/// Confirms exact preservation outside the explicitly selected Document owner.
void _retained(AiNativeArtboards before, AiNativeArtboards after) {
  check(after.records.program.bytes.take(after.document.start)).deepEquals(before.records.program.bytes.take(before.document.start));
  check(after.records.program.bytes.skip(after.document.end)).deepEquals(before.records.program.bytes.skip(before.document.end));
}

/// Requires an unsupported retained dependency to fail without source mutation.
void _refused(String extra) {
  final String source = artboardSource(extra: extra);
  final AiNativeArtboards before = artboardModel(source);
  check(() => before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null)).throws<UnsupportedError>();
  check(latin1.decode(before.records.program.bytes)).equals(source);
}

/// Checks retained descriptors, namespaces and style references without rendering.
void main() {
  test('preserves all brush namespaces panel ordering and calligraphic styles in four board edits', () {
    final AiNativeArtboards before = artboardModel(symbolArtboardSource(resources: artboardBrushDescriptors(), style: artboardCalligraphicStyle()));
    for (final AiNativeArtboards after in [
      before.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null),
      before.resize(artboard: before.artboards.first, bounds: AiBoundingBox(left: -20, bottom: -40, right: 100, top: 200), cropBounds: null),
      before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null),
      before.remove(artboards: [before.artboards.first], activeArtboard: null, cropBounds: null),
    ]) {
      _retained(before, after);
    }
  });

  test('retains escaped names fragmented values and both known plugin module names', () {
    const String name = r'board-(0)\flat';
    for (final String plugin in ['Illustrator.exe', 'CalligraphicBrushTool.aip']) {
      for (final int fragment in [1, 7, 1000]) {
        final String descriptor = artboardBrushDescriptor(name: name, fragmentLength: fragment);
        final String hex = '<${latin1.encode(name).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}>';
        final AiNativeArtboards before = artboardModel(
          artboardSource(
            extra: '${descriptor.replaceFirst(_literal(name), hex)}${artboardCalligraphicStyle(name: name, plugin: plugin)}',
          ),
        );
        _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
      }
    }
  });

  test('rejects unresolved or mismatched brush and tile references without confusing namespaces', () {
    final String descriptor = artboardBrushDescriptor();
    final String style = artboardCalligraphicStyle();
    final List<String> variants = [
      style,
      '$descriptor${artboardCalligraphicStyle(name: 'missing')}',
      '$descriptor${style.replaceFirst('(board-0) (Adobe Calligraphic Brush Tool) /PluginObject', '(board-0) (Adobe ArtOnPath Brush Tool) /PluginObject')}',
      '${artboardBrush(art: '')}$style',
      artboardBrushDescriptor(plugin: 'Adobe ArtOnPath Brush Tool', data: _tileData()),
      '${artboardBrush(art: '')}${artboardBrushDescriptor(plugin: 'Adobe PatternOnPath Brush Tool', data: _tileData().replaceFirst('/ / / /', '/ missing/ / /'))}',
      '$descriptor$descriptor',
    ];
    variants.forEach(_refused);
  });

  test('requires unique complete panel pairs resolved after all declarations', () {
    final String descriptor = artboardBrushDescriptor();
    final List<String> variants = [
      ' Adobe Calligraphic Brush Tool/ missing/',
      ' Adobe Calligraphic Brush Tool/ board-0/ Adobe Calligraphic Brush Tool/ board-0/',
      ' Adobe Calligraphic Brush Tool/ board-0',
      ' Adobe Calligraphic Brush Tool/',
      ' Unknown Brush Tool/ board-0/',
    ];
    for (final String data in variants) {
      _refused('$descriptor${artboardBrushDescriptor(plugin: 'Adobe Brush Manager Order', name: 'Adobe Brush Manager Order', data: data)}');
    }
    final String panel = artboardBrushDescriptor(plugin: 'Adobe Brush Manager Order', name: 'Adobe Brush Manager Order', data: ' Adobe Calligraphic Brush Tool/ board-0/');
    _refused('$panel$descriptor$panel');
    _refused('${panel.replaceFirst('(Adobe Brush Manager Order)\n(Adobe Brush Manager Order)', '(Adobe Brush Manager Order)\n(wrong)')}$descriptor');
    final AiNativeArtboards before = artboardModel(artboardSource(extra: '$panel$descriptor'));
    _retained(before, before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null));
  });

  test('rejects unknown layouts providers and hidden executable or conditional payloads', () {
    final String descriptor = artboardBrushDescriptor();
    final List<String> variants = [
      artboardBrushDescriptor(plugin: 'Unknown Brush Tool'),
      artboardBrushDescriptor(data: '2 5 5 0 0 90 90 0 0 0 0'),
      artboardBrushDescriptor(plugin: 'Adobe dBrush Brush Tool', data: '0 4 0.5 0.75 0.33 0.75 1.5 6 external.ai board-0'),
      '${artboardBrush(art: '')}${artboardBrushDescriptor(
        plugin: 'Adobe ArtOnPath Brush Tool',
        data: _tileData(color: '9 0.5'),
      )}',
      descriptor.replaceFirst(' -', ' load'),
      descriptor.replaceFirst(' .', ' -'),
      descriptor.replaceFirst('%AI8_EndPluginObject', '(hidden) load\n%AI8_EndPluginObject'),
      descriptor.replaceFirst('%AI8_EndPluginObject', '%%BeginData: 4\nABCD\n%%EndData\n%AI8_EndPluginObject'),
      descriptor.replaceFirst('%AI8_BeginPluginObject', '%AI8_BeginPluginObject\n%AI24_ArtboardRef: board-0'),
      descriptor.replaceFirst('%AI8_BeginPluginObject', '%AI8_BeginPluginObject\n%AI8_BeginPluginObject'),
      descriptor.replaceFirst('(board-0)', '%_(board-0)'),
      '%AI17_Begin_Content_if_version_gt:24 4\n$descriptor%AI17_End_Versioned_Content\n',
    ];
    variants.forEach(_refused);
  });

  test('rejects incomplete or executable style references and unknown local parameters', () {
    final String descriptor = artboardBrushDescriptor();
    final String style = artboardCalligraphicStyle();
    final List<String> variants = [
      style.replaceFirst('/GObjRef :', '/UnknownRef :'),
      style.replaceFirst('/PluginObject', '/OtherObject'),
      style.replaceFirst('(board-0) (Adobe Calligraphic Brush Tool) /PluginObject', '(board-0) load (Adobe Calligraphic Brush Tool) /PluginObject'),
      style.replaceFirst('(Brush)', '(OtherBrush)'),
      style.replaceFirst('(StrokeStyle)', '(OtherStroke)'),
      style.replaceFirst('(Angle)', '(ArtboardIndex)'),
      style.replaceFirst('CalligraphicBrushTool.aip', 'Unknown.aip'),
    ];
    for (final String changed in variants) {
      _refused('$descriptor$changed');
    }
  });

  test('rejects malformed scalar fields nonportable values and incomplete frames', () {
    for (final String data in ['1 5 5 0 0 90 90 0 0 0', '1 5 5 0 0 90 90 0 0 0 NaN', '1 5 5 0 0 90 90 0 0 0 Infinity', '1 5 5 0 0 90 90 0 0 0 9007199254740992', '1 5 5 0 0 90 90 0 0 0 load']) {
      final AiNativeArtboards before = artboardModel(artboardSource(extra: artboardBrushDescriptor(data: data)));
      check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
    }
    final AiNativeArtboards before = artboardModel(artboardSource(extra: artboardBrushDescriptor().replaceFirst('%AI8_EndPluginObject', '')));
    check(() => before.reorder(artboards: before.artboards.reversed.toList(), cropBounds: null)).throws<FormatException>();
  });

  test('retains token and output budgets with many split descriptor fragments', () {
    final String source = artboardSource(extra: '${artboardBrushDescriptor(fragmentLength: 1)}${artboardCalligraphicStyle()}');
    check(() => artboardModel(source, limits: const AiNativeLimits(maxTokens: 80))).throws<FormatException>();
    final String panel = artboardBrushDescriptor(
      plugin: 'Adobe Brush Manager Order',
      name: 'Adobe Brush Manager Order',
      data: List.filled(600, ' Adobe Calligraphic Brush Tool/ board-0/').join(),
      fragmentLength: 100000,
    );
    final AiNativeArtboards inventory = artboardModel(artboardSource(extra: '$panel${artboardBrushDescriptor()}'), limits: const AiNativeLimits(maxTokens: 1000));
    check(() => inventory.reorder(artboards: inventory.artboards.reversed.toList(), cropBounds: null)).throws<AiLimitException>();
    final AiNativeArtboards bounded = artboardModel(source, limits: AiNativeLimits(maxDecodedBytes: source.length));
    check(() => bounded.create(definition: newArtboard(), index: 1, lastArtboardId: 68, cropBounds: null)).throws<FormatException>();
  });
}
