part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Accumulates one version boundary without exposing mutable document state.
final class _NativeVersionBuilder {
  /// Original opening marker.
  final AiToken opening;

  /// Producer marker family required on the matching delimiters.
  final String family;

  /// Saved major condition value.
  final int major;

  /// Saved minor condition value.
  final int minor;

  /// Optional alternate delimiter, assigned at most once.
  AiToken? alternate;

  /// Starts a source-owned version block.
  _NativeVersionBuilder({required this.opening, required this.family, required this.major, required this.minor});
}

/// Inspects version comments without interpreting binary samples or procedures.
List<AiNativeVersionBlock> _nativeVersionBlocks(AiNativeRecords records) {
  final RegExp marker = RegExp(r'^%(AI\d+)_(Begin_Content_if_version_gt|Alternate_Content|End_Versioned_Content)(.*)$');
  final RegExp condition = RegExp(r'^:\s*(\d+)\s+(\d+)\s*$');
  final List<AiNativeContainer> binary = records.containers.where((record) => record.hasBinary).toList()..sort((a, b) => a._binaryStart!.compareTo(b._binaryStart!));
  final List<_NativeVersionBuilder> stack = [];
  final List<AiNativeVersionBlock> result = [];
  int binaryIndex = 0;
  int procedures = 0;
  int embedded = 0;
  for (final AiToken token in records._projection.tokens) {
    while (binaryIndex < binary.length && binary[binaryIndex]._binaryEnd! <= token.start) {
      binaryIndex++;
    }
    if (binaryIndex < binary.length && token.start >= binary[binaryIndex]._binaryStart!) {
      continue;
    }
    if (token.kind == .procedureStart) {
      procedures++;
    } else if (token.kind == .procedureEnd) {
      procedures--;
    }
    if (procedures != 0 || token.kind != .comment) {
      continue;
    }
    if (token.lexeme.startsWith('%%BeginDocument')) {
      embedded++;
    } else if (token.lexeme == '%%EndDocument') {
      embedded--;
      continue;
    }
    if (embedded != 0) {
      continue;
    }
    final RegExpMatch? match = marker.firstMatch(token.lexeme);
    if (match == null) {
      continue;
    }
    final String family = match[1]!;
    if (match[2] == 'Begin_Content_if_version_gt') {
      final RegExpMatch? numbers = condition.firstMatch(match[3]!);
      final int? major = numbers == null ? null : int.tryParse(numbers[1]!);
      final int? minor = numbers == null ? null : int.tryParse(numbers[2]!);
      if (major == null || minor == null || major > 9007199254740991 || minor > 9007199254740991) {
        throw const FormatException('Invalid native version condition.');
      }
      if (stack.length >= records.program.limits.maxDepth) {
        throw const AiLimitException(message: 'Native version nesting exceeds the limit.');
      }
      stack.add(_NativeVersionBuilder(opening: token, family: family, major: major, minor: minor));
    } else {
      if (match[3]!.trim().isNotEmpty || stack.isEmpty || stack.last.family != family) {
        throw const FormatException('Unmatched native version delimiter.');
      }
      if (match[2] == 'Alternate_Content') {
        if (stack.last.alternate != null) {
          throw const FormatException('Repeated native alternate branch.');
        }
        stack.last.alternate = token;
      } else {
        final _NativeVersionBuilder block = stack.removeLast();
        result.add(AiNativeVersionBlock._(opening: block.opening, alternate: block.alternate, closing: token, family: family, major: block.major, minor: block.minor));
      }
    }
  }
  if (stack.isNotEmpty || embedded != 0 || procedures != 0) {
    throw const FormatException('Unterminated native version inspection scope.');
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}
