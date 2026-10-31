@TestOn('vm')
library;

import 'dart:io';

import 'package:aikit/aikit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Validates generated AI prologs through an independent PostScript interpreter.
void main() {
  test('Ghostscript renders authored artwork and suppresses hidden/nonprinting layers', () async {
    final Directory directory = Directory.systemTemp.createTempSync('aikit-artwork-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final AiArtworkPath red = AiArtworkPath(
      segments: [
        AiPathSegment(operator: 'm', coordinates: [10, 10]),
        AiPathSegment(operator: 'L', coordinates: [90, 10]),
        AiPathSegment(operator: 'L', coordinates: [90, 90]),
        AiPathSegment(operator: 'L', coordinates: [10, 90]),
      ],
      fill: AiColor(space: .rgb, channels: [1, 0, 0]),
      closed: true,
    );
    final AiArtworkPath black = red.copyWith(
      fill: AiColor(space: .gray, channels: [0]),
    );
    final AiArtwork drawing = AiArtwork(
      bounds: AiBoundingBox(left: 0, bottom: 0, right: 100, top: 100),
      children: [
        AiArtworkLayer(name: 'Red', children: [red]),
        AiArtworkLayer(
          name: 'Hidden',
          visible: false,
          children: [
            AiArtworkLayer(name: 'Visible child of hidden parent', children: [black]),
          ],
        ),
        AiArtworkLayer(name: 'Nonprinting', printing: false, children: [black]),
      ],
    );
    final File source = File('${directory.path}/drawing.ai')..writeAsBytesSync(drawing.toPostScript().bytes);
    final String image = '${directory.path}/drawing.ppm';
    final ProcessResult rendered = await Process.run('gs', ['-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=ppmraw', '-r72', '-g100x100', '-sOutputFile=$image', source.path]);
    check(rendered.exitCode).equals(0);
    final List<int> bytes = await File(image).readAsBytes();
    // Ghostscript's PPM header precedes exactly 100 * 100 RGB pixels.
    final int pixelStart = bytes.length - 30000;
    check(pixelStart).isGreaterThan(0);
    final int center = pixelStart + (50 * 100 + 50) * 3;
    check(bytes.sublist(center, center + 3)).deepEquals([255, 0, 0]);
    check(bytes.sublist(pixelStart, pixelStart + 3)).deepEquals([255, 255, 255]);
  }, skip: !_available() ? 'Requires Ghostscript for independent native rendering' : false);
}

/// Detects the optional independent interpreter without invoking a shell.
bool _available() {
  try {
    return Process.runSync('gs', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
