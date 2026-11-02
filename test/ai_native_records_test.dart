import 'dart:convert';

import 'package:aicodec/aicodec.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Wraps synthetic authoring records in a source-backed native snapshot.
AiProgram _program(String body, {AiNativeLimits limits = const AiNativeLimits()}) => AiProgram.decode(
  bytes: latin1.encode('%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%%EndSetup\n$body\n%%Trailer\n%%EOF\n'),
  limits: limits,
);

/// Checks typed records, unknown preservation and byte-exact source edits.
void main() {
  test('reads dictionaries, artboards, wrapped strings and native qualifiers', () {
    final AiNativeRecords records = AiNativeRecords.decode(
      program: _program(r'''
%_/Document :
%_/Dictionary :
%_/Array :
%_/Dictionary :
%_(Plan ) (de travail) /UnicodeString (Name) ,
%_12 34 /RealPoint (RulerOrigin) ,
%_10 20 /RealPointRelToROrigin (PositionPoint1) ,
%_110 -60 /RealPointRelToROrigin (PositionPoint2) ,
%_1 /Bool (IsArtboardSelected) ,
%_; ,
%_; (ArtboardArray) ,
%_7 8 /FuturePoint (Unknown) ,
%_/String (Empty) ,
%_(one) (two) /String (wrapped) (key) ,
%_; /Recorded ,
%_/Dictionary : /NotRecorded ,
%_; /NotRecorded ,
%_;
'''),
    );
    final AiNativeContainer document = records.roots.single;
    final AiNativeContainer dictionary = document['Recorded']!.container!;
    final AiNativeContainer artboard = dictionary['ArtboardArray']!.container!.entries.single.container!;
    check(document.type).equals('Document');
    check(artboard['Name']!.text()).equals('Plan de travail');
    check(artboard['RulerOrigin']!.numbers!).deepEquals([12.0, 34.0]);
    check(artboard['IsArtboardSelected']!.boolean).equals(true);
    check(dictionary['Unknown']!.type).equals('FuturePoint');
    check(dictionary['Unknown']!.numbers!).deepEquals([7.0, 8.0]);
    check(dictionary['Empty']!.text()).equals('');
    check(dictionary['wrappedkey']!.text()).equals('onetwo');
    check(document['NotRecorded']!.container!.notRecorded).isTrue();
    check(latin1.decode(records.artboards.single.nameBytes)).equals('Plan de travail');
    check(records.artboards.single.selected).isTrue();
    check(records.artboards.single.bounds.left).equals(10);
    check(records.artboards.single.bounds.top).equals(20);
    check(records.artboards.single.bounds.right).equals(110);
    check(records.artboards.single.bounds.bottom).equals(-60);
    check(dictionary.entries.clear).throws<UnsupportedError>();
  });

  test('retains ordered repeated object fields and unknown nested containers', () {
    final AiNativeRecords records = AiNativeRecords.decode(
      program: _program(r'''
/CompoundFilter :
/FutureFilter : (one) /Name ; /Part ,
/FutureFilter : (two) /Name ; /Part ,
/Art : 0 0 m 10 10 L S /ArtDictionary : ; ; /Drawing ,
;
'''),
    );
    final AiNativeContainer root = records.roots.single;
    check(root.values('Part').map((entry) => entry.container!['Name']!.text())).deepEquals(['one', 'two']);
    check(() => root['Part']).throws<StateError>();
    check(root['Drawing']!.container!.entries.single.items.whereType<AiNativeToken>().map((item) => item.token.lexeme)).deepEquals(['0', '0', 'm', '10', '10', 'L', 'S']);
    check(records.containers.map((container) => container.type)).deepEquals(['CompoundFilter', 'FutureFilter', 'FutureFilter', 'Art', 'ArtDictionary']);
  });

  test('decodes ASCII85 binary lines beginning with the private comment prefix', () {
    final AiNativeRecords records = AiNativeRecords.decode(
      program: _program(r'''
%_/ArtDictionary :
%_/Binary : /ASCII85Decode ,
%_!!!!~>
%_; (Data) ,
%_10 /Real (After) ,
%_;
'''),
    );
    final AiNativeContainer binary = records.roots.single['Data']!.container!;
    check(binary.decodeBinary()).deepEquals([192, 232, 34, 222]);
    check(records.roots.single['After']!.number).equals(10);
    check(() => binary.decodeBinary(maxOutputBytes: 3)).throws<FormatException>();
    check(() => binary.decodeBinary().add(0)).throws<UnsupportedError>();
  });

  test('replaces numeric spans exactly and rejects handles from old snapshots', () {
    final AiNativeRecords original = AiNativeRecords.decode(program: _program('%_/ArtDictionary :\r\n%_12 34 /RealPoint\r\n%_ (Position) ,\r\n%_;'));
    final AiNativeEntry position = original.roots.single['Position']!;
    final AiNativeRecords edited = original.replaceNumbers(entry: position, values: [56, 78]);
    check(latin1.decode(edited.program.bytes).replaceFirst(RegExp(r'56(?:\.0)? 78(?:\.0)?'), '12 34')).equals(latin1.decode(original.program.bytes));
    check(original.roots.single['Position']!.numbers!).deepEquals([12.0, 34.0]);
    check(edited.roots.single['Position']!.numbers!).deepEquals([56.0, 78.0]);
    check(() => edited.replaceNumbers(entry: position, values: [0, 0])).throws<ArgumentError>();
    check(() => original.replaceNumbers(entry: position, values: [double.nan, 0])).throws<ArgumentError>();
  });

  test('preserves multiline string content and ignores record syntax in procedures', () {
    final AiNativeRecords records = AiNativeRecords.decode(
      program: _program(r'''
(/ArtDictionary : %_ untouched) pop
{ /ArtDictionary : (fake) /String (Name) , ; } pop
%_/ArtDictionary :
%_(line one
%_line two) /String (Text) ,
%_;
'''),
    );
    check(records.roots.length).equals(1);
    check(records.roots.single['Text']!.text()).equals('line one\nline two');
  });

  test('rejects duplicate keys, truncated records and invalid scalar types', () {
    for (final String body in [
      '%_/ArtDictionary : 1 /Real (same) , 2 /Real (same) , ;',
      '%_/ArtDictionary : 1 /Real (missing end) ,',
      '%_/ArtDictionary : 3 /Bool (flag) , ;',
      '%_/ArtDictionary : 1.5 /Int (count) , ;',
      '%_/ArtDictionary : 1 2 3 /RealMatrix (matrix) , ;',
      '%_/ArtDictionary : 42 /String (text) , ;',
      '%_/ArtDictionary : /Binary : /ASCII85Decode ,\n%invalid\n%_; (data) , ;',
      '%_/ArtDictionary : /Binary : /OtherDecode , ; (data) , ;',
    ]) {
      check(() => AiNativeRecords.decode(program: _program(body))).throws<FormatException>();
    }
    final AiNativeRecords flags = AiNativeRecords.decode(program: _program('%_/ArtDictionary : 1 /Bool (flag) , ;'));
    check(() => flags.replaceNumbers(entry: flags.roots.single['flag']!, values: [2])).throws<ArgumentError>();
  });

  test('replaces split and empty strings without guessing Unicode encodings', () {
    final AiNativeRecords original = AiNativeRecords.decode(program: _program('%_/ArtDictionary :\n%_(one)\n%_(two) /UnicodeString (Text) ,\n%_/String (Empty) ,\n%_;'));
    final AiNativeRecords first = original.replaceString(entry: original.roots.single['Text']!, bytes: utf8.encode('Été 🖋'));
    check(first.roots.single['Text']!.text(encoding: utf8)).equals('Été 🖋');
    check(original.roots.single['Text']!.text()).equals('onetwo');
    final AiNativeRecords second = first.replaceString(entry: first.roots.single['Empty']!, bytes: [40, 41, 92, 0, 255]);
    check(second.roots.single['Empty']!.stringBytes!).deepEquals([40, 41, 92, 0, 255]);
    check(() => second.replaceString(entry: original.roots.single['Text']!, bytes: [])).throws<ArgumentError>();
    check(() => second.replaceString(entry: second.roots.single['Text']!, bytes: [256])).throws<ArgumentError>();
  });

  test('preserves integer syntax and validates typed artboard geometry', () {
    final AiNativeRecords original = AiNativeRecords.decode(program: _program('%_/ArtDictionary : 1 /Int (Count) , ;'));
    final AiNativeRecords edited = original.replaceNumbers(entry: original.roots.single['Count']!, values: [5]);
    check(latin1.decode(edited.program.bytes).contains('5 /Int')).isTrue();
    check(() => original.replaceNumbers(entry: original.roots.single['Count']!, values: [1.5])).throws<ArgumentError>();
    final AiNativeRecords incomplete = AiNativeRecords.decode(program: _program('%_/Document : /Dictionary : /Array : /Dictionary : (Page) /String (Name) , ; , ; (ArtboardArray) , ; /Recorded , ;'));
    check(() => incomplete.artboards).throws<FormatException>();
  });

  test('bounds expanded private token counts and both kinds of nesting', () {
    final AiProgram excessive = _program('%_/ArtDictionary : ${List.generate(20, (index) => '$index /Real (key$index) ,').join()} ;', limits: const AiNativeLimits(maxTokens: 20));
    check(() => AiNativeRecords.decode(program: excessive)).throws<FormatException>();
    final AiProgram nested = _program('%_/ArtDictionary : /Dictionary : /Dictionary : ; (child) , ; (child) , ;', limits: const AiNativeLimits(maxDepth: 2));
    check(() => AiNativeRecords.decode(program: nested)).throws<FormatException>();
    final AiProgram arrays = _program('%_/ArtDictionary : [ [ [ 1 ] ] ] /FutureValue (value) , ;', limits: const AiNativeLimits(maxDepth: 2));
    check(() => AiNativeRecords.decode(program: arrays)).throws<FormatException>();
  });
}
