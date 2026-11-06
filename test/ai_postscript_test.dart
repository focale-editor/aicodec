import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Tests source-oriented legacy Illustrator tokenization without evaluation.
void main() {
  test('preserves source spans and distinguishes numbers from executable names', () {
    const String source = '%!PS-Adobe-3.0\n/paint { 1e2 -2.5 16#FF m (a\\(b\\)) <4142> [1 2] << /K true >> } def';
    final List<AiToken> tokens = AiPostScript.tokenize(latin1.encode(source));
    check(tokens.where((token) => token.kind == AiTokenKind.number).map((token) => token.number)).deepEquals([100, -2.5, 255, 1, 2]);
    check(tokens.where((token) => token.kind == AiTokenKind.executableName).map((token) => token.lexeme)).deepEquals(['m', 'true', 'def']);
    for (final AiToken token in tokens) {
      check(source.substring(token.start, token.end)).equals(token.lexeme);
    }
  });

  test('protects delimiter-like binary data from token interpretation', () {
    const String source = '%%BeginBinary: 5\n{}<\x00\xff\n%%EndBinary\n0 0 m';
    final List<AiToken> tokens = AiPostScript.tokenize(latin1.encode(source));
    check(tokens.where((token) => token.kind == AiTokenKind.data).single.lexeme).equals('{}<\x00\xff');
    check(tokens.last.lexeme).equals('m');
  });

  test('retains ASCII85 syntax and immediate names', () {
    final List<AiToken> tokens = AiPostScript.tokenize(latin1.encode('<~z~> //cached /literal'));
    check(tokens.first.kind).equals(AiTokenKind.ascii85String);
    check(tokens[1].lexeme).equals('//cached');
  });

  for (final String source in ['(unterminated', '<GG>', '<4142', '<~abc', '{ 1 2', '[ 1 }', ')', '%%BeginBinary: 99\nx']) {
    test('rejects invalid or truncated syntax: $source', () {
      check(() => AiPostScript.tokenize(latin1.encode(source))).throws<FormatException>();
    });
  }

  test('enforces token, byte and nesting budgets', () {
    check(() => AiPostScript.tokenize(latin1.encode('1 2 3'), maxTokens: 2)).throws<FormatException>();
    check(() => AiPostScript.tokenize(latin1.encode('{{{}}}'), maxDepth: 2)).throws<FormatException>();
    check(() => AiPostScript.tokenize([1, 2, 3], maxBytes: 2)).throws<FormatException>();
    check(() => AiPostScript.tokenize([256])).throws<FormatException>();
  });
}
