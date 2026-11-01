part of 'package:aikit/src/model/ai_native_records.dart';

/// One counted setup bank, preserving printing/nonprinting placement.
final class _NativeGradientBank {
  /// Original numeric Bn operand.
  final AiToken count;

  /// Definitions following this declaration and preceding the next bank.
  final List<AiNativeGradientDefinition> definitions;

  /// Captures source-backed bank ownership without moving existing definitions.
  _NativeGradientBank({required this.count, required List<AiNativeGradientDefinition> definitions}) : definitions = List.unmodifiable(definitions);
}

/// Reads top-level setup counts without treating data or procedures as resources.
List<_NativeGradientBank> _nativeGradientBanks(AiNativeGradientResources resources, {List<_NativeFontEncoding>? fontDeclarations}) {
  final AiNativeRecords records = resources.records;
  final List<AiToken> counts = [];
  final List<AiToken> numbers = [];
  int procedure = 0;
  int embedded = 0;
  int root = 0;
  int definition = 0;
  final List<AiTokenKind> literals = [];
  bool setup = false;
  final List<AiToken> tokens = records._projection.tokens;
  for (int index = 0; index < tokens.length; index++) {
    final AiToken token = tokens[index];
    if (token.start >= records.program.bodyStart) {
      break;
    }
    while (root < records.roots.length && records.roots[root].end <= token.start) {
      root++;
    }
    if (root < records.roots.length && token.start >= records.roots[root].start) {
      numbers.clear();
      continue;
    }
    while (definition < resources.definitions.length && resources.definitions[definition].end <= token.start) {
      definition++;
    }
    if (definition < resources.definitions.length && token.start >= resources.definitions[definition].start) {
      if (literals.isNotEmpty) {
        throw UnsupportedError('Gradient isolation requires top-level setup definitions.');
      }
      numbers.clear();
      continue;
    }
    if (token.kind == .procedureStart) {
      procedure++;
    } else if (token.kind == .procedureEnd) {
      procedure--;
    }
    if (procedure != 0) {
      numbers.clear();
      continue;
    }
    if (token.kind == .comment) {
      if (token.lexeme.startsWith('%%BeginDocument')) {
        embedded++;
      } else if (token.lexeme == '%%EndDocument') {
        embedded--;
      } else if (embedded == 0 && token.lexeme == '%%BeginSetup') {
        setup = true;
        numbers.clear();
      } else if (embedded == 0 && token.lexeme == '%%EndSetup') {
        setup = false;
      }
      continue;
    }
    if (embedded != 0 || !setup) {
      numbers.clear();
      continue;
    }
    if (literals.isEmpty && token.kind == .arrayStart) {
      final ({int endIndex, List<String> names})? font = _readNativeFontEncoding(records, index);
      if (font != null) {
        index = font.endIndex;
        fontDeclarations?.add((start: token.start, end: tokens[index].end, names: font.names));
        numbers.clear();
        continue;
      }
    }
    if (const {AiTokenKind.arrayStart, AiTokenKind.dictionaryStart}.contains(token.kind)) {
      literals.add(token.kind);
    } else if (const {AiTokenKind.arrayEnd, AiTokenKind.dictionaryEnd}.contains(token.kind)) {
      final AiTokenKind expected = token.kind == .arrayEnd ? AiTokenKind.arrayStart : AiTokenKind.dictionaryStart;
      if (literals.isEmpty || literals.removeLast() != expected) {
        throw UnsupportedError('Gradient isolation requires balanced setup literals.');
      }
    }
    if (literals.isNotEmpty) {
      numbers.clear();
      continue;
    }
    if (token.kind == .number) {
      numbers.add(token);
      continue;
    }
    if (token.kind == .executableName && token.lexeme == 'Bn') {
      if (numbers.length != 1 ||
          numbers.single.number! < 0 ||
          numbers.single.number! % 1 != 0 ||
          numbers.single.number! > records.program.limits.maxTokens ||
          records._projection.isPrivate(token.start) ||
          records._projection.isPrivate(numbers.single.start)) {
        throw const FormatException('Gradient isolation requires ordinary finite integer Bn declarations.');
      }
      counts.add(numbers.single);
    }
    numbers.clear();
  }
  final List<_NativeGradientBank> banks = [];
  for (int index = 0; index < counts.length; index++) {
    final int end = index + 1 < counts.length ? counts[index + 1].start : records.program.bodyStart;
    final List<AiNativeGradientDefinition> definitions = resources.definitions.where((definition) => definition.start > counts[index].end && definition.end < end).toList();
    if (definitions.length != counts[index].number) {
      throw const FormatException('Native gradient bank count disagrees with its definitions.');
    }
    banks.add(_NativeGradientBank(count: counts[index], definitions: definitions));
  }
  if (banks.fold<int>(0, (total, bank) => total + bank.definitions.length) != resources.definitions.length) {
    throw UnsupportedError('Gradient isolation requires counted setup banks for every definition.');
  }
  return banks;
}

/// Clones complete gradient definitions, preserving ramps and fallback records.
List<AiSourceEdit> _copyNativeGradientResources(_LiveShapeGradientIsolation isolation) {
  final AiNativeRecords records = isolation.drawing.records;
  final List<AiSourceEdit> edits = [];
  for (final _NativeGradientBank bank in _nativeGradientBanks(isolation.resources)) {
    final List<AiNativeGradientDefinition> sources = bank.definitions.where((definition) => _gradientBytesEqual(definition.nameBytes, isolation.sourceNameBytes)).toList();
    if (sources.isEmpty) {
      continue;
    }
    if (sources.length != 1) {
      throw UnsupportedError('Gradient isolation requires one source definition per bank.');
    }
    final AiNativeGradientDefinition source = sources.single;
    if (source.opening.isPrivate || source.closing.isPrivate) {
      throw UnsupportedError('Gradient isolation requires ordinary resource boundaries.');
    }
    final AiToken closing = records._projection.tokens.firstWhere((token) => token.start >= source.end && token.kind == .comment && token.lexeme == '%AI5_EndGradient');
    final AiToken name = source.opening.operands.first;
    const String label = '\n%AI5_BeginGradient: ';
    final List<int> suffix = latin1.encode('\n%AI5_EndGradient\n');
    isolation.reserve(label.length + isolation.encodedName.length + 1 + source.end - source.start + isolation.encodedName.length - (name.end - name.start) + suffix.length);
    final List<int> prefix = [...latin1.encode(label), ...isolation.encodedName, 10];
    final Uint8List copy = AiNativeEditor.copyRange(
      program: records.program,
      start: source.start,
      end: source.end,
      edits: [AiSourceEdit(start: name.start, end: name.end, bytes: isolation.encodedName)],
    );
    edits.add(AiSourceEdit(start: closing.end, end: closing.end, bytes: [...prefix, ...copy, ...suffix]));
    final List<int> count = latin1.encode((bank.definitions.length + 1).toString());
    isolation.reserve(count.length - (bank.count.end - bank.count.start));
    edits.add(AiSourceEdit(start: bank.count.start, end: bank.count.end, bytes: count));
  }
  return edits;
}
