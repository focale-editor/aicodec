import 'dart:io';
import 'dart:typed_data';

import 'package:illustratorkit/illustratorkit.dart';

/// Prints container metadata without interpreting Illustrator drawing commands.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/inspect_ai.dart file.ai');
    exitCode = 64;
    return;
  }
  final Uint8List bytes = await File(arguments.single).readAsBytes();
  final AiDocument document = const AiCodec().decode(bytes);
  switch (document) {
    case AiPdfDocument(:final pdf, :final privateBlocks):
      stdout.writeln('PDF: ${pdf.pages.length} pages, ${privateBlocks.length} native blocks');
    case AiPostScriptDocument(:final creator, :final postScriptBytes, :final dscIssue):
      if (dscIssue == null) {
        stdout.writeln('PostScript: $creator; ${AiPostScript.tokenize(postScriptBytes).length} tokens');
      } else {
        stdout.writeln('PostScript: $creator; ${postScriptBytes.length} preserved bytes');
        stderr.writeln('DSC inspection stopped at byte ${dscIssue.offset}: ${dscIssue.message}');
        exitCode = 1;
      }
  }
}
