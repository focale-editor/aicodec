part of 'ai_postscript.dart';

/// Internal checked byte layout shared by native tokens and DSC inspection.
typedef AiPlacedPreviewData = ({int width, int height, int rowBytes, int bits, int format, int samples, int end});

/// Bounds a placed preview from its five numeric fields, never delimiter search.
AiPlacedPreviewData readAiPlacedPreview({required Uint8List bytes, required int start, required bool privateData}) {
  int position = start;
  if (position + 2 <= bytes.length && bytes[position] == 37 && bytes[position + 1] == 95) {
    position += 2;
  }
  final List<int> fields = [];
  for (int index = 0; index < 5; index++) {
    final int first = position;
    int value = 0;
    while (position < bytes.length && bytes[position] >= 48 && bytes[position] <= 57) {
      value = value * 10 + bytes[position++] - 48;
      if (value > bytes.length * 8) {
        throw const FormatException('Placed preview header exceeds its source byte bounds.');
      }
    }
    if (position == first || position >= bytes.length || bytes[position] != 32 && bytes[position] != 9 || index == 4 && bytes[position] != 32) {
      throw const FormatException('Invalid placed preview header.');
    }
    fields.add(value);
    position++;
    if (index < 4) {
      while (position < bytes.length && (bytes[position] == 32 || bytes[position] == 9)) {
        position++;
      }
    }
  }
  final int width = fields[0];
  final int height = fields[1];
  final int rowBytes = fields[2];
  if (width <= 0 || height <= 0 || rowBytes <= 0 || width > rowBytes * 8 || fields[3] <= 0 || rowBytes > (bytes.length - position) ~/ height) {
    throw const FormatException('Invalid or truncated placed preview rows.');
  }
  final int end = position + rowBytes * height;
  int terminator = end;
  if (terminator < bytes.length && bytes[terminator] == 13) {
    terminator++;
  }
  if (terminator < bytes.length && bytes[terminator] == 10) {
    terminator++;
  }
  final String marker = privateData ? '%_%AI26_EndPlacedObjectPreview' : '%AI26_EndPlacedObjectPreview';
  if (terminator + marker.length > bytes.length ||
      latin1.decode(Uint8List.sublistView(bytes, terminator, terminator + marker.length)) != marker ||
      terminator + marker.length < bytes.length && !_space(bytes[terminator + marker.length])) {
    throw const FormatException('Invalid placed preview data boundary.');
  }
  return (width: width, height: height, rowBytes: rowBytes, bits: fields[3], format: fields[4], samples: position, end: end);
}
