import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:illustratorkit/illustratorkit.dart';

/// Checks the explicitly downloaded corpus and emits files for independent QA.
Future<void> main() async {
  final File manifestFile = File('test/corpus/manifest.json');
  final Map<String, Object?> manifest = (jsonDecode(await manifestFile.readAsString()) as Map).cast<String, Object?>();
  final List<Object?> entries = (manifest['files']! as List).cast<Object?>();
  final List<Map<String, Object?>> report = [];
  int failures = 0;
  await Directory('test/corpus/output').create(recursive: true);
  for (final Object? value in entries) {
    final Map<String, Object?> entry = (value! as Map).cast<String, Object?>();
    final String name = entry['file']! as String;
    final bool rejected = entry['expected'] == 'reject';
    try {
      final Uint8List bytes = await File('test/corpus/files/$name').readAsBytes();
      final AiDocument decoded = const AiCodec().decode(bytes);
      final Uint8List encoded = const AiCodec().encode(decoded);
      final AiDocument reopened = const AiCodec().decode(encoded);
      if (decoded.kind != reopened.kind) {
        throw StateError('Container kind changed');
      }
      if (decoded is AiPostScriptDocument) {
        if (decoded.dscIssue case final AiDscIssue issue) {
          throw FormatException('Incomplete DSC inspection at ${issue.offset}: ${issue.message}');
        }
        AiPostScript.tokenize(decoded.postScriptBytes);
      }
      if (decoded is AiPostScriptDocument && !_same(bytes, encoded)) {
        throw StateError('Legacy bytes changed');
      }
      if (decoded is AiPdfDocument && reopened is AiPdfDocument) {
        final List<AiPrivateBlock> before = decoded.privateBlocks;
        final List<AiPrivateBlock> after = reopened.privateBlocks;
        if (before.length != after.length) {
          throw StateError('Private block count changed');
        }
        for (int index = 0; index < before.length; index++) {
          if (!_same(before[index].stream.data, after[index].stream.data)) {
            throw StateError('Private data changed');
          }
        }
      }
      if (rejected) {
        throw StateError('Expected rejection but file decoded');
      }
      await File('test/corpus/output/$name').writeAsBytes(encoded);
      report.add({'file': name, 'status': 'accepted', 'bytes': encoded.length, if (decoded is AiPostScriptDocument) 'dscComplete': decoded.dscIssue == null});
    } on FormatException catch (error) {
      report.add({'file': name, 'status': rejected ? 'rejected' : 'failed', 'error': error.toString()});
      if (!rejected) {
        failures++;
        stdout.writeln('$name: $error');
      }
    } on Object catch (error) {
      failures++;
      report.add({'file': name, 'status': 'failed', 'error': error.toString()});
      stdout.writeln('$name: $error');
    }
  }
  await File('test/corpus/output/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('AiCodec: ${entries.length - failures}/${entries.length} expected outcomes');
  if (failures != 0) {
    exitCode = 1;
  }
}

/// Compares exact encoded payloads independently of model identity.
bool _same(List<int> first, List<int> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
