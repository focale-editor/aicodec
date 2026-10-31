import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Writes a source link with intentionally noncanonical numeric spelling.
Uint8List _source({bool private = false, bool optional = true, int padding = 0}) {
  final String prefix = private ? '%_' : '';
  return (BytesBuilder()
        ..add(
          latin1.encode('''%!PS-Adobe-3.0
%%Creator: Adobe Illustrator
%%DocumentFiles:old.png
%%EndComments
%%EndSetup
$prefix%AI5_BeginPlace
$prefix%%FileType: 1
$prefix[2e0 0.0 0 -3 -90 250] 50 60 70 80 4 4 0 (old.png)`
$prefix%%IncludeFile:old.png
'''),
        )
        ..add(
          optional
              ? latin1.encode('''$prefix%AI17_Begin_Content_if_version_gt:24 12
$prefix%AI28_BeginPlacedRelativePath
$prefix(Old/)
$prefix%AI28_EndPlacedRelativePath
$prefix%AI17_Alternate_Content
$prefix%AI17_End_Versioned_Content
$prefix%AI17_Begin_Content_if_version_gt:24 5
$prefix%AI26_BeginPlacedObjectPreview
1 1 ${4 + padding} 32 17 ''')
              : [],
        )
        ..add(optional ? [255, 20, 40, 60, ...List.filled(padding, 128)] : [])
        ..add(optional ? latin1.encode('\n$prefix%AI26_EndPlacedObjectPreview\n$prefix%AI17_End_Versioned_Content\n') : [])
        ..add(
          latin1.encode('''$prefix~
$prefix%AI5_EndPlace
%_/ArtDictionary :
%_(Named picture) /UnicodeString (AIArtName) ,
%_(stable-object-id) /String (AI10_ArtUID) ,
%_;
${prefix}9 () XW
%%Trailer
%%EOF
'''),
        ))
      .takeBytes();
}

/// Reads an immutable placement inventory under explicit native byte bounds.
AiNativePlacements _decode(List<int> bytes, {AiNativeLimits limits = const AiNativeLimits()}) => AiNativePlacements.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(bytes: bytes, limits: limits),
  ),
);

/// Decodes native rows for exact sample comparisons, including transparent colors.
AiNativeRasterSamples _preview() => AiNativeRasterSamples(width: 2, height: 1, bitsPerComponent: 8, components: 3, colorSamples: [255, 240, 230, 10, 20, 30], alphaSamples: [32, 0]);

/// Changes one link with explicit optional metadata and its own source object.
AiNativePlacements _relink(AiNativePlacements source, {List<int>? path, List<int>? relative, AiNativeRasterSamples? preview, AiNativePlacedObject? object}) =>
    source.relink(object: object ?? source.objects.first, pathBytes: path ?? latin1.encode('new.png'), relativeDirectoryBytes: relative, preview: preview);

/// Extracts native dependency lines without normalizing their byte values.
List<String> _files(AiNativePlacements source) =>
    AiPostScript.tokenize(source.records.program.bytes)
        .where((token) => token.kind == .comment && (token.lexeme.startsWith('%%DocumentFiles:') || token.lexeme.startsWith('%%+')))
        .map((token) => token.lexeme)
        .toList();

/// Checks relinking, counted preview authoring and shared DSC dependency edits.
void main() {
  test('relinks escaped byte paths and replaces the preview without changing native geometry', () {
    final Uint8List original = _source();
    final AiNativePlacements source = _decode(original);
    final List<int> path = utf8.encode('C:\\New (100%)\\photographie-ą.png');
    final List<int> relative = utf8.encode('../Nouvelles (images)/');
    final AiNativeRasterSamples preview = _preview();
    final AiNativePlacements changed = _relink(source, path: path, relative: relative, preview: preview);
    final AiNativePlacedObject object = changed.objects.single;
    check(object.pathBytes).deepEquals(path);
    check(object.relativeDirectoryBytes!).deepEquals(relative);
    check(object.matrix).deepEquals(source.objects.single.matrix);
    check(object.bounds).deepEquals(source.objects.single.bounds);
    check(latin1.decode(changed.records.program.bytes)).contains('[2e0 0.0 0 -3 -90 250] 50 60 70 80 4 4 0');
    check(object.preview!.bytes).deepEquals([32, 255, 240, 230, 0, 10, 20, 30]);
    check(object.preview!.toSamples().colorSamples).deepEquals(preview.colorSamples);
    check(object.dictionary!['AI10_ArtUID']!.text()).equals('stable-object-id');
    check(object.dictionary!['AIArtName']!.text()).equals('Named picture');
    check(_files(changed)).deepEquals(['%%DocumentFiles:${latin1.decode(path)}']);
    check(source.records.program.bytes).deepEquals(original);
    check((const AiCodec().decode(changed.records.program.bytes) as AiPostScriptDocument).dscIssue).isNull();
  });

  test('adds and removes versioned relative directories and previews in both representations', () {
    for (final bool private in [false, true]) {
      final AiNativePlacements source = _decode(_source(private: private, optional: false));
      final AiNativePlacements added = _relink(source, relative: latin1.encode('Links/'), preview: _preview());
      check(added.objects.single.instruction.isPrivate).equals(private);
      check(added.objects.single.relativeDirectoryBytes!).deepEquals(latin1.encode('Links/'));
      check(added.objects.single.preview!.toSamples().alphaSamples!).deepEquals([32, 0]);
      final AiNativePlacements removed = _relink(added, path: latin1.encode('third.png'));
      check(removed.objects.single.preview).isNull();
      check(removed.objects.single.relativeDirectory).isNull();
      check(removed.objects.single.instruction.isPrivate).equals(private);
      check(latin1.decode(removed.records.program.bytes).contains('Versioned_Content')).isFalse();
      check((const AiCodec().decode(removed.records.program.bytes) as AiPostScriptDocument).dscIssue).isNull();
    }
  });

  test('returns unchanged snapshots for equivalent padded preview rows and optional opaque alpha', () {
    final AiNativePlacements source = _decode(_source(padding: 5));
    final AiNativePlacedObject object = source.objects.single;
    final AiNativeRasterSamples opaque = AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 8, components: 3, colorSamples: [20, 40, 60]);
    for (final AiNativeRasterSamples preview in [opaque, object.preview!.toSamples()]) {
      check(identical(source.relink(object: object, pathBytes: object.pathBytes, relativeDirectoryBytes: object.relativeDirectoryBytes, preview: preview), source)).isTrue();
    }
    final AiNativePlacements none = _decode(_source(optional: false));
    check(identical(_relink(none, path: none.objects.single.pathBytes), none)).isTrue();
    final AiNativePlacements refreshed = _relink(source, path: object.pathBytes, relative: object.relativeDirectoryBytes, preview: _preview());
    check(_files(refreshed)).deepEquals(_files(source));
    check(refreshed.objects.single.preview!.width).equals(2);
  });

  test('retains shared dependencies and deduplicates the new path after the last relink', () {
    final String original = latin1.decode(_source());
    final String section = original.substring(original.indexOf('%AI5_BeginPlace'), original.indexOf('%%Trailer'));
    final AiNativePlacements source = _decode(latin1.encode(original.replaceFirst('%%Trailer', '$section%%Trailer')));
    final AiNativePlacements first = _relink(source);
    check(_files(first)).deepEquals(['%%DocumentFiles:old.png', '%%+new.png']);
    check(first.objects.last.pathBytes).deepEquals(latin1.encode('old.png'));
    check(first.objects.last.preview!.bytes).deepEquals(source.objects.last.preview!.bytes);
    final AiNativePlacements last = _relink(first, object: first.objects.last);
    check(_files(last)).deepEquals(['%%DocumentFiles:new.png']);
    check(last.objects.map((object) => latin1.decode(object.pathBytes)).toList()).deepEquals(['new.png', 'new.png']);
  });

  test('updates concrete and deferred declarations while retaining unrelated imported files', () {
    final String original = latin1.decode(_source());
    for (final bool deferred in [false, true]) {
      final String source = original
          .replaceFirst('%%DocumentFiles:old.png', deferred ? '%%DocumentFiles: (atend)' : '%%DocumentFiles:old.png\n%%+other.png')
          .replaceFirst('%%Trailer', '%%Trailer\n%%DocumentFiles:old.png\n%%+other.png');
      final AiNativePlacements result = _relink(_decode(latin1.encode(source)));
      check(_files(result)).deepEquals([
        if (deferred) '%%DocumentFiles: (atend)' else ...['%%DocumentFiles:new.png', '%%+other.png'],
        '%%DocumentFiles:new.png',
        '%%+other.png',
      ]);
    }
    final AiNativePlacements listed = _decode(latin1.encode(original.replaceFirst('%%DocumentFiles:old.png', '%%DocumentFiles:old.png\n%%+new.png\n%%+other.png')));
    check(_files(_relink(listed))).deepEquals(['%%DocumentFiles:new.png', '%%+other.png']);
  });

  test('adds absent declarations in the header or the explicitly deferred trailer', () {
    final String original = latin1.decode(_source());
    final AiNativePlacements absent = _decode(latin1.encode(original.replaceFirst('%%DocumentFiles:old.png\n', '')));
    check(_files(_relink(absent))).deepEquals(['%%DocumentFiles:new.png']);
    final AiNativePlacements deferred = _decode(latin1.encode(original.replaceFirst('%%DocumentFiles:old.png', '%%DocumentFiles: (atend)')));
    check(_files(_relink(deferred))).deepEquals(['%%DocumentFiles: (atend)', '%%DocumentFiles:new.png']);
    final AiNativePlacements missingTrailer = _decode(latin1.encode(original.replaceFirst('%%DocumentFiles:old.png', '%%DocumentFiles: (atend)').replaceFirst('%%Trailer\n', '')));
    check(() => _relink(missingTrailer)).throws<UnsupportedError>();
  });

  test('preserves non-ASCII path bytes that Unicode trimming would discard', () {
    final AiNativePlacements source = _decode(_source());
    for (final List<int> path in [
      utf8.encode('Links/ą'),
      [160, 112, 105, 99, 160],
    ]) {
      final AiNativePlacements changed = _relink(source, path: path);
      check(changed.objects.single.pathBytes).deepEquals(path);
      check(_files(changed)).deepEquals(['%%DocumentFiles:${latin1.decode(path)}']);
      check(_files(_relink(changed))).deepEquals(['%%DocumentFiles:new.png']);
    }
  });

  test('keeps embedded document and procedure dependency comments untouched', () {
    const String nested = '%%BeginDocument: other.eps\n%%DocumentFiles:old.png\n%%EndDocument\n{\n%%DocumentFiles:old.png\n} pop\n';
    final String original = latin1.decode(_source()).replaceFirst('%%EndSetup', '$nested%%EndSetup');
    final AiNativePlacements changed = _relink(_decode(latin1.encode(original)));
    check(latin1.decode(changed.records.program.bytes)).contains(nested);
    check(latin1.decode(changed.records.program.bytes)).contains('%%DocumentFiles:new.png');
  });

  test('rejects malformed paths, unqualified preview planes and foreign objects atomically', () {
    final AiNativePlacements source = _decode(_source());
    for (final List<int> path in [
      [],
      [-1],
      [256],
      [0],
      latin1.encode(' leading.png'),
      latin1.encode('trailing.png '),
      latin1.encode('a\n%%Title: forged'),
      latin1.encode('(atend)'),
    ]) {
      check(() => _relink(source, path: path)).throws<ArgumentError>();
    }
    check(() => _relink(source, relative: [0])).throws<ArgumentError>();
    check(() => _relink(source, object: _decode(_source()).objects.single)).throws<ArgumentError>();
    for (final AiNativeRasterSamples preview in [
      AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 8, components: 1, colorSamples: [0]),
      AiNativeRasterSamples(width: 1, height: 1, bitsPerComponent: 16, components: 3, colorSamples: List.filled(6, 0)),
    ]) {
      check(() => _relink(source, preview: preview)).throws<ArgumentError>();
    }
    final AiNativePlacements unknown = _decode(latin1.encode(latin1.decode(_source()).replaceFirst('(AIArtName)', '(OpaqueLinkCache)')));
    check(() => _relink(unknown)).throws<UnsupportedError>();
    check(source.records.program.bytes).deepEquals(_source());
  });

  test('bounds replacement metadata and the aggregate edited source before copying', () {
    final Uint8List original = _source();
    final AiNativePlacements source = _decode(original, limits: AiNativeLimits(maxDecodedBytes: original.length));
    final AiNativeRasterSamples preview = AiNativeRasterSamples(width: 100, height: 100, bitsPerComponent: 8, components: 3, colorSamples: List.filled(30000, 0));
    check(() => _relink(source, preview: preview)).throws<FormatException>();
    check(() => _relink(source, path: List.filled(original.length, 65))).throws<ArgumentError>();
    check(() => _relink(source, path: List.filled(100, 65), relative: List.filled(100, 66), preview: _preview())).throws<FormatException>();
    check(source.records.program.bytes).deepEquals(original);
  });
}
