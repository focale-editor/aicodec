import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'ai_native_appearance_artwork_test.dart' show appearanceArtworkReplacement;
import 'ai_native_appearance_clipping_test.dart' show clippingAppearanceSource;
import 'ai_native_appearance_editing_test.dart' show appearanceEditingModel;
import 'ai_native_appearance_groups_test.dart' show appearanceGroupsSource;

/// A complete changed path with independent fill, stroke and winding attributes.
AiArtworkPath _paint({bool fill = true, bool stroke = true, bool closed = false}) => AiArtworkPath(
  segments: [
    AiPathSegment(operator: 'm', coordinates: [2, 3]),
    AiPathSegment(operator: 'C', coordinates: [4, 5, 12, 5, 15, 8]),
    AiPathSegment(operator: 'L', coordinates: [18, 20]),
  ],
  fill: fill ? AiColor(space: .rgb, channels: [.2, .4, .6]) : null,
  stroke: stroke ? AiColor(space: .cmyk, channels: [.1, .2, .3, .4]) : null,
  strokeWidth: 4,
  lineCap: 1,
  lineJoin: 2,
  miterLimit: 8,
  dash: [6, 2],
  dashPhase: -1,
  evenOdd: true,
  locked: true,
  closed: closed,
);

/// Reads literal state before private paths without applying the editor's helpers.
Map<String, String> _state(AiNativeAppearances model, AiNativePath path) {
  final Map<String, String> values = {};
  for (final AiNativeInstruction item in model.structure.drawing.items.whereType<AiNativeInstruction>().where((item) => item.end <= path.start)) {
    final String? key = switch (item.operator) {
      'g' || 'k' || 'Xa' => 'fill',
      'G' || 'K' || 'XA' => 'stroke',
      'A' || 'Xw' || 'Ap' || 'D' || 'XR' || 'Xy' || 'O' || 'R' || 'w' || 'J' || 'j' || 'M' || 'd' => item.operator,
      _ => null,
    };
    if (key != null) {
      values[key] = '${item.operands.map((operand) => operand.lexeme).join(' ')} ${item.operator}';
    }
  }
  return values;
}

/// Deferred regression cases for actual paint roles, ownership and state isolation.
void main() {
  test('changes private paints closure and count while preserving metadata and sibling state', () {
    for (final bool counted in [false, true]) {
      final String text = appearanceGroupsSource(counted: counted)
          .replaceFirst('(First contour) /String (AIArtName)', '(First contour) /String (AIArtName) , /XMLUID : (child-1) ; (AI10_ArtUID) , (0.5) /String (BBAccumRotation)');
      final AiNativeAppearances source = appearanceEditingModel(source: text);
      final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
      final AiNativePath path = owner.group!.paths.first;
      final AiNativeAppearances result = source.replaceArtworkPaths(
        changes: [AiNativeAppearancePathChange(path: path, artwork: _paint(), opacity: .4, hidden: true, fillOverprint: true, strokeOverprint: true)],
        artwork: [appearanceArtworkReplacement(source, 0)],
      );
      final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
      final AiNativePath changed = after.group!.paths.first;
      check(changed.paint.operator).equals('B');
      check(changed.closed).isFalse();
      check(changed.geometry).length.equals(3);
      check(after.groupContours.first.pointCount?.numbers?.single).equals(counted ? 3.0 : null);
      final Map<String, String> paints = _state(result, changed);
      check(paints['fill']).equals('0.2 0.4 0.6 Xa');
      check(paints['stroke']).equals('0.1 0.2 0.3 0.4 K');
      check(paints['Xy']).equals('0 0.4 0 0 0 Xy');
      check(double.parse(paints['w']!.split(' ').first)).equals(4);
      check(paints['A']).equals('1 A');
      check(paints['Xw']).equals('1 Xw');
      check(paints['O']).equals('1 O');
      check(paints['R']).equals('1 R');
      check(_state(result, after.group!.paths.last)).deepEquals(_state(source, owner.group!.paths.last));
      final AiNativeContainer beforeMetadata = AiNativeObjects.decode(drawing: source.structure.drawing).forSource(path).dictionary!;
      final AiNativeContainer afterMetadata = AiNativeObjects.decode(drawing: result.structure.drawing).forSource(changed).dictionary!;
      check(result.structure.drawing.records.program.bytes.sublist(afterMetadata.start, afterMetadata.end))
          .deepEquals(source.structure.drawing.records.program.bytes.sublist(beforeMetadata.start, beforeMetadata.end));
      check(result.structure.identifiers.map((identity) => latin1.decode(identity.bytes))).deepEquals(['child-1']);
      final AiNativeAppearanceArtwork neighbor = source.artworkFor(use: source.uses.last);
      final AiNativeAppearanceArtwork retained = result.artworkFor(use: result.uses.last);
      check(result.structure.drawing.records.program.bytes.sublist(retained.start, retained.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(neighbor.start, neighbor.end));
      check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
    }
  });

  test('adds removes and repeats every direct fill and stroke role', () {
    AiNativeAppearances model = appearanceEditingModel(source: appearanceGroupsSource());
    for (final (bool fill, bool stroke, bool closed, String operator) in [(true, false, true, 'f'), (false, true, false, 'S'), (true, true, true, 'b'), (false, false, true, 'n')]) {
      final AiNativeAppearanceArtwork owner = model.artworkFor(use: model.uses.first);
      model = model.replaceArtworkPaths(
        changes: [
          AiNativeAppearancePathChange(
            path: owner.group!.paths.first,
            artwork: _paint(fill: fill, stroke: stroke, closed: closed),
          ),
        ],
        artwork: [appearanceArtworkReplacement(model, 0)],
      );
      final AiNativeAppearanceArtwork after = model.artworkFor(use: model.uses.first);
      check(after.group!.paths.first.paint.operator).equals(operator);
      check(after.groupContours.first.pointCount!.numbers!.single).equals(3);
      check(after.group!.paths.first.geometry).length.equals(closed ? 4 : 3);
      check(after.metadata.first['AIArtName']!.text()).equals('First contour');
    }
  });

  test('rejects unknown outgoing width when a sibling reads it and admits explicit overwrite', () {
    final String text = appearanceGroupsSource().replaceAll('1 w', '').replaceFirst('30 10 L 20 0 L n', '30 10 L 20 0 L s');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    check(
      () => source.replaceArtworkPaths(
        changes: [AiNativeAppearancePathChange(path: owner.group!.paths.first, artwork: _paint())],
        artwork: [appearanceArtworkReplacement(source, 0)],
      ),
    ).throws<UnsupportedError>();
    final AiNativeAppearances assigned = appearanceEditingModel(source: text.replaceFirst('%_20 0 m', '%_7 w\n%_20 0 m'));
    final AiNativeAppearanceArtwork assignedOwner = assigned.artworkFor(use: assigned.uses.first);
    final AiNativeAppearances result = assigned.replaceArtworkPaths(
      changes: [AiNativeAppearancePathChange(path: assignedOwner.group!.paths.first, artwork: _paint())],
      artwork: [appearanceArtworkReplacement(assigned, 0)],
    );
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
    check(_state(result, after.group!.paths.last)['w']).equals('7 w');
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('keeps same-line private commands private when several children change together', () {
    final String text = appearanceGroupsSource(metadata: false).replaceFirst('0 0 L n\n%_1 Ae', '0 0 L n 1 Ae');
    final AiNativeAppearances source = appearanceEditingModel(source: text);
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativeAppearances result = source.replaceArtworkPaths(
      changes: [
        AiNativeAppearancePathChange(path: owner.group!.paths.first, artwork: _paint(fill: false), opacity: .2),
        AiNativeAppearancePathChange(path: owner.group!.paths.last, artwork: _paint(stroke: false, closed: true), opacity: .8),
      ],
      artwork: [appearanceArtworkReplacement(source, 0)],
    );
    final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
    check(after.group!.paths.every((path) => path.isPrivate)).isTrue();
    check(after.group!.paths.map((path) => path.paint.operator)).deepEquals(['S', 'f']);
    check(_state(result, after.group!.paths.first)['Xy']).equals('0 0.2 0 0 0 Xy');
    check(_state(result, after.group!.paths.last)['Xy']).equals('0 0.8 0 0 0 Xy');
    check(after.group!.children.whereType<AiNativeGroup>()).length.equals(1);
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('retains clipping ancestors and mask contours while editing an independent child', () {
    for (final String variant in ['open', 'closed', 'nested', 'compound']) {
      final AiNativeAppearances source = appearanceEditingModel(source: clippingAppearanceSource(variant: variant));
      final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
      final AiNativeAppearances result = source.replaceArtworkPaths(
        changes: [AiNativeAppearancePathChange(path: owner.groupContours.last.path, artwork: _paint())],
        artwork: [appearanceArtworkReplacement(source, 0)],
      );
      final AiNativeAppearanceArtwork after = result.artworkFor(use: result.uses.first);
      check(after.groupContours.map((contour) => contour.mask)).deepEquals(owner.groupContours.map((contour) => contour.mask));
      check(after.groupContours.last.path.paint.operator).equals('B');
      for (final (int index, AiNativePathTopology contour) in owner.groupContours.indexed) {
        if (contour.mask != .none) {
          final AiNativePath path = after.groupContours[index].path;
          check(result.structure.drawing.records.program.bytes.sublist(path.start, path.end)).deepEquals(source.structure.drawing.records.program.bytes.sublist(contour.path.start, contour.path.end));
        }
      }
      check(
        () => source.replaceArtworkPaths(
          changes: [AiNativeAppearancePathChange(path: owner.groupContours.first.path, artwork: _paint())],
          artwork: [appearanceArtworkReplacement(source, 0)],
        ),
      ).throws<UnsupportedError>();
    }
  });

  test('bounds complete paints and printing before publishing any mutation', () {
    final String text = appearanceGroupsSource();
    final AiNativeAppearances source = appearanceEditingModel(
      source: text,
      limits: AiNativeLimits(maxDecodedBytes: text.length),
    );
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    check(
      () => source.replaceArtworkPaths(
        changes: [AiNativeAppearancePathChange(path: owner.group!.paths.first, artwork: _paint())],
        artwork: [appearanceArtworkReplacement(source, 0)],
      ),
    ).throws<AiLimitException>();
    check(latin1.decode(source.structure.drawing.records.program.bytes)).equals(text);
  });

  test('requires current complete owner coverage and independent unstyled contours', () {
    final AiNativeAppearances source = appearanceEditingModel(source: appearanceGroupsSource());
    final AiNativeAppearanceArtwork owner = source.artworkFor(use: source.uses.first);
    final AiNativeAppearancePathChange change = AiNativeAppearancePathChange(path: owner.group!.paths.first, artwork: _paint());
    check(() => source.replaceArtworkPaths(changes: [change], artwork: [])).throws<ArgumentError>();
    check(() => source.replaceArtworkPaths(changes: [change], artwork: [appearanceArtworkReplacement(source, 1)])).throws<ArgumentError>();
    check(() => source.replaceArtworkPaths(changes: [change, change], artwork: [appearanceArtworkReplacement(source, 0)])).throws<ArgumentError>();
    check(() => source.replaceArtworkPaths(changes: [change], artwork: [appearanceArtworkReplacement(source, 0), appearanceArtworkReplacement(source, 1)])).throws<ArgumentError>();
    final AiNativeAppearances foreign = appearanceEditingModel(source: appearanceGroupsSource());
    check(() => foreign.replaceArtworkPaths(changes: [change], artwork: [appearanceArtworkReplacement(foreign, 0)])).throws<ArgumentError>();
    for (final String text in [
      appearanceGroupsSource(compound: true),
      appearanceGroupsSource().replaceFirst('(First contour) /String (AIArtName) , ;', '(First contour) /String (AIArtName) , ;\n%_0 (Shared) XW'),
    ]) {
      final AiNativeAppearances unsupported = appearanceEditingModel(source: text);
      final AiNativeAppearanceArtwork group = unsupported.artworkFor(use: unsupported.uses.firstWhere((use) => !use.instruction.isPrivate));
      check(
        () => unsupported.replaceArtworkPaths(
          changes: [AiNativeAppearancePathChange(path: group.group!.paths.first, artwork: _paint())],
          artwork: [AiNativeAppearanceReplacement(artwork: group, bytes: latin1.encode('u 0 0 0 1 k 0 0 m 10 0 L 10 10 L f U'), bounds: AiBoundingBox(left: 0, bottom: 0, right: 30, top: 30))],
        ),
      ).throws<UnsupportedError>();
    }
  });
}
