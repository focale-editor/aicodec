import 'dart:io';

import 'package:illustratorkit/illustratorkit.dart';

/// Renames a native layer in an existing PDF-backed AI without changing its art.
///
/// Run with an input AI, a new output path and the desired layer name. Visual
/// edits additionally require matching derived representations from the host.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw ArgumentError('Usage: dart run example/illustratorkit_example.dart input.ai output.ai "Layer name"');
  }
  final File output = File(arguments[1]);
  if (await output.exists()) {
    throw ArgumentError('Choose a new output path to retain the original file.');
  }
  final AiDocument document = const AiCodec().decode(await File(arguments[0]).readAsBytes());
  if (document is! AiPdfDocument) {
    throw const FormatException('This example requires a PDF-backed Illustrator document.');
  }
  final List<AiNativeSource> sources = AiNativeData.extract(document);
  if (sources.isEmpty) {
    throw const FormatException('No native Illustrator program is available; PDF artwork alone is not natively editable.');
  }
  final AiNativeSource source = sources.first;
  final AiProgram program = AiProgram.decode(bytes: source.bytes);
  if (program.layers.isEmpty) {
    throw const FormatException('The selected native program has no supported layer to rename.');
  }
  final AiProgram edited = AiNativeEditor.updateLayer(program: program, layer: program.layers.first, name: arguments[2]);
  // A layer rename is nonvisual, so the original PDF appearance remains valid.
  final AiPdfDocument saved = AiNativeData.replace(source: source, program: edited.bytes, synchronizedPdf: document.pdf);
  final List<int> bytes = const AiCodec().encode(saved);
  final AiPdfDocument reopened = const AiCodec().decode(bytes) as AiPdfDocument;
  final AiProgram restored = AiProgram.decode(bytes: AiNativeData.extract(reopened).first.bytes);
  if (restored.layers.first.name != arguments[2]) {
    throw StateError('The saved native layer name did not survive reopening.');
  }
  await output.writeAsBytes(bytes, flush: true);
  print('Saved ${restored.layers.first.name}; other native records and PDF artwork are preserved.');
}
