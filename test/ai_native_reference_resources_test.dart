import 'dart:convert';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_artwork_movement_test.dart' show movementLayer, movementPath;
import 'ai_native_objects_test.dart' show objectDictionary;
import 'ai_native_shape_lifecycle_test.dart' show identifiedShapeLifecycleSource;

/// Defines a source-backed gradient with distinct native/fallback stops and a ramp.
const String referenceGradient = '''%AI5_BeginGradient: (path_target)
(path_target) 0 2 Bd
[
<000080ff> 0 %_Br
[
0.91 0 50 100 %_BS
%_0.9 0 1 6 50 100 Bs
0.11 0 50 0 %_BS
%_0.1 0 1 6 50 0 Bs
BD
%AI5_EndGradient''';

/// Combines identified ordinary owners, complete pairs and retained shared banks.
String referenceResourcesSource({bool gradients = true, bool unusedStyle = true}) {
  final String text = identifiedShapeLifecycleSource();
  final AiNativeDrawing initial = _drawing(text);
  final AiNativeContainer style = initial.liveShapes.first.style!;
  final String shared = text.substring(style.start, style.end).replaceFirst('(Shared)', '(path_target)');
  final String layer = movementLayer('Target', 'u\n${movementPath(70)}\n${objectDictionary(identifier: 'path_target')}\nU\n${objectDictionary(identifier: 'group_target')}');
  return text
      .replaceRange(initial.liveShapes.first.start, initial.liveShapes.first.start, '$layer\n')
      .replaceFirst(
        '%%EndSetup',
        '${gradients ? '1 Bn\n$referenceGradient\n%AI5_Begin_NonPrinting\n1 Bn\n$referenceGradient\n%AI5_End_NonPrinting--\n' : ''}${unusedStyle ? '$shared\n' : ''}%%EndSetup',
      );
}

/// Opens an immutable drawing under the original bounded parser.
AiNativeDrawing _drawing(String text, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativeDrawing.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: latin1.encode(text), limits: limits),
  ),
);

/// Checks whole setup bytes and all retained pair records after an ordinary removal.
void _retained(AiNativeDrawing before, AiNativeDrawing after) {
  check(after.records.program.bytes.sublist(0, after.records.program.bodyStart)).deepEquals(before.records.program.bytes.sublist(0, before.records.program.bodyStart));
  check(after.liveShapes).length.equals(before.liveShapes.length);
  for (final (int, AiLiveShape) entry in before.liveShapes.indexed) {
    final AiLiveShape changed = after.liveShapes[entry.$1];
    check(after.records.program.bytes.sublist(changed.start, changed.end)).deepEquals(before.records.program.bytes.sublist(entry.$2.start, entry.$2.end));
  }
}

/// Covers cross-family reference qualification without widening deletion ownership.
void main() {
  test('removes identified ordinary paths, groups and layers beside complete CC pairs', () {
    final AiNativeDrawing source = _drawing(referenceResourcesSource());
    final AiNativeLayers layers = AiNativeLayers.decode(drawing: source);
    for (final AiNativeDrawing result in [
      source.removePaths(paths: [source.paths.first]),
      source.removeGroups(groups: [source.groups.first]),
      layers.remove(layers: layers.layers).drawing,
    ]) {
      check(result.paths).length.equals(source.paths.length - 1);
      _retained(source, result);
    }
  });

  test('keeps style and gradient namespaces distinct from deleted artwork identities', () {
    final AiNativeDrawing source = _drawing(referenceResourcesSource());
    final AiNativeDrawing result = source.removePaths(paths: [source.paths.first]);
    check(AiNativeStructure.decode(drawing: result).identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(['Target', 'group_target', 'author', 'older']);
    final AiNativeGradientResources gradients = AiNativeGradientResources.decode(records: result.records);
    check(gradients.definitions).length.equals(2);
    check(gradients.definitions.first.stops.map((stop) => stop.color.components.single)).deepEquals([0.9, 0.1]);
    check(gradients.definitions.first.fallbackStops.map((stop) => stop.color.components.single)).deepEquals([0.91, 0.11]);
    check(gradients.definitions.first.ramps.single.channels.single.samples!).deepEquals([0, 0, 128, 255]);
    check(result.records.roots.where((record) => record.type == 'KnownStyle').map((record) => record['Name']!.text())).deepEquals(['Shared', 'path_target']);
    _retained(source, result);
  });

  test('qualifies complete pairs before a wrapped layer without consuming its comments', () {
    final String text = referenceResourcesSource();
    final AiNativeLayer layer = AiNativeLayers.decode(drawing: _drawing(text)).layers.single;
    final String tail = text.substring(layer.start, layer.end);
    final AiNativeDrawing source = _drawing(text.replaceRange(layer.start, layer.end, '').replaceFirst('%%Trailer', '$tail\n%%Trailer'));
    final AiNativeDrawing result = source.removePaths(paths: [source.paths.last]);
    _retained(source, result);
  });

  test('uses the same shared-resource checks for deletion of identified CC pairs', () {
    final AiNativeDrawing source = _drawing(referenceResourcesSource());
    final AiNativeDrawing result = source.removeLiveShapes(shapes: [source.liveShapes.first]);
    check(result.liveShapes).length.equals(1);
    check(AiNativeStructure.decode(drawing: result).identifiers.map((identifier) => latin1.decode(identifier.bytes))).deepEquals(['Target', 'path_target', 'group_target']);
    check(result.records.program.bytes.take(result.records.program.bodyStart)).deepEquals(source.records.program.bytes.take(source.records.program.bodyStart));
  });

  test('accepts separate private scalar replay left by earlier pair operations', () {
    final AiNativeDrawing source = _drawing(referenceResourcesSource());
    final List<AiNativeDrawing> states = [
      source.removeLiveShapes(shapes: [source.liveShapes.first]),
      source.moveLiveShapeAfter(shape: source.liveShapes.first, after: source.liveShapes.last),
    ];
    for (final AiNativeDrawing before in states) {
      final AiNativeDrawing after = before.removePaths(paths: [before.paths.first]);
      _retained(before, after);
    }
  });

  test('qualifies unused literal styles without requiring a live-shape user', () {
    final AiNativeDrawing initial = _drawing(referenceResourcesSource());
    final AiNativeDrawing source = initial.removeLiveShapes(shapes: initial.liveShapes);
    final AiNativeDrawing result = source.removePaths(paths: [source.paths.first]);
    check(result.paths).isEmpty();
    _retained(source, result);
  });

  test('rejects unknown fields and executable or reference-bearing unused styles', () {
    final String text = referenceResourcesSource(unusedStyle: false);
    for (final String value in [
      '/KnownStyle : (Unused) /Name , /ActiveStyle : /Dictionary : /XMLUID : (path_target) ; (Reference) , ; /Execution ; /Def ;',
      '/KnownStyle : (Unused) /Name , /ActiveStyle : /Dictionary : 1 /Int (Future) , ; /Execution ; /Def ;',
      '/KnownStyle : (Unused) /Name , (path_target) load /Def ;',
    ]) {
      final AiNativeDrawing source = _drawing(text.replaceFirst('%%EndSetup', '$value\n%%EndSetup'));
      check(() => source.removePaths(paths: [source.paths.first])).throws<UnsupportedError>();
    }
  });

  test('rejects opaque annotations and conditional ownership in retained styles', () {
    final String text = referenceResourcesSource();
    final AiNativeContainer style = _drawing(text).records.roots.lastWhere((record) => record.type == 'KnownStyle');
    for (final String replacement in [
      text.substring(style.start, style.end).replaceFirst(':', ':\n%AI99_Ref: path_target\n'),
      '%AI17_Begin_Content_if_version_gt:17 4\n${text.substring(style.start, style.end)}\n%AI17_End_Versioned_Content',
    ]) {
      final AiNativeDrawing source = _drawing(text.replaceRange(style.start, style.end, replacement));
      check(() => source.removePaths(paths: [source.paths.first])).throws<UnsupportedError>();
    }
  });

  test('rejects malformed gradient counts and unqualified bank ownership', () {
    final String text = referenceResourcesSource();
    for (final String replacement in ['2 Bn', '-1 Bn', '1 1 Bn']) {
      final AiNativeDrawing source = _drawing(text.replaceFirst('1 Bn', replacement));
      check(() => source.removePaths(paths: [source.paths.first])).throws<FormatException>();
    }
    final AiNativeDrawing missing = _drawing(text.replaceFirst('1 Bn', ''));
    check(() => missing.removePaths(paths: [missing.paths.first])).throws<UnsupportedError>();
    final AiNativeDrawing private = _drawing(text.replaceFirst('1 Bn', '%_1 Bn'));
    check(() => private.removePaths(paths: [private.paths.first])).throws<FormatException>();
  });

  test('does not hide intervening reference comments inside a bank declaration', () {
    final AiNativeDrawing source = _drawing(referenceResourcesSource().replaceFirst('1 Bn', '1\n%AI99_Ref: path_target\nBn'));
    check(() => source.removePaths(paths: [source.paths.first])).throws<UnsupportedError>();
  });

  test('rejects conditional gradients and unmatched nonprinting wrappers', () {
    final String text = referenceResourcesSource();
    final AiNativeDrawing conditional = _drawing(text.replaceFirst(referenceGradient, '%AI17_Begin_Content_if_version_gt:17 4\n$referenceGradient\n%AI17_End_Versioned_Content'));
    check(() => conditional.removePaths(paths: [conditional.paths.first])).throws<UnsupportedError>();
    for (final String invalid in [
      text.replaceFirst('%AI5_Begin_NonPrinting', ''),
      text.replaceFirst('%AI5_End_NonPrinting--', ''),
      text.replaceFirst('%AI5_Begin_NonPrinting', '%AI5_Begin_NonPrinting\n%AI5_Begin_NonPrinting'),
    ]) {
      final AiNativeDrawing source = _drawing(invalid);
      check(() => source.removePaths(paths: [source.paths.first])).throws<FormatException>();
    }
  });

  test('rejects unknown private neighbors and external references before identity deletion', () {
    final String text = referenceResourcesSource();
    for (final String invalid in [
      text.replaceFirst('%%Trailer', '%_17 FutureState\n%%Trailer'),
      text.replaceFirst('%%EndSetup', '/Dictionary : /XMLUID : (path_target) ; (Reference) , ;\n%%EndSetup'),
      text.replaceFirst('(older)', '(path_target)'),
    ]) {
      final AiNativeDrawing source = _drawing(invalid);
      check(() => source.removePaths(paths: [source.paths.first])).throws<UnsupportedError>();
      check(latin1.decode(source.records.program.bytes)).equals(invalid);
    }
  });

  test('retains atomic failure for an unresolved neighboring complete pair', () {
    final String text = referenceResourcesSource().replaceFirst('/Visible ,', '/FutureVisibility ,');
    final AiNativeDrawing source = _drawing(text);
    check(() => source.removePaths(paths: [source.paths.first])).throws<UnsupportedError>();
    check(latin1.decode(source.records.program.bytes)).equals(text);
  });
}
