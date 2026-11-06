part of 'package:illustratorkit/src/model/ai_native_records.dart';

/// Collects direct setup wrappers without reading strings or executable bodies.
AiNativeArtworkResources _nativeArtworkResources(AiNativeStructure structure, {bool requireOrdinary = false}) {
  final AiNativeRecords records = structure.drawing.records;
  final _NativeArtworkResourceReader reader = _NativeArtworkResourceReader(records: records);
  final List<AiNativeArtworkResource> resources = [];
  AiToken? opening;
  AiNativeArtworkResourceKind? kind;
  bool setup = false;
  int procedure = 0;
  int embedded = 0;
  int root = 0;
  int inspected = 0;
  for (final AiToken token in records._projection.tokens.takeWhile((token) => token.start < records.program.bodyStart)) {
    while (root < records.roots.length && records.roots[root].end <= token.start) {
      root++;
    }
    if (root < records.roots.length && token.start >= records.roots[root].start) {
      continue;
    }
    if (procedure == 0 && token.kind == .comment) {
      if (token.lexeme.startsWith('%%BeginDocument')) {
        embedded++;
      } else if (token.lexeme == '%%EndDocument') {
        embedded--;
      }
    }
    if (embedded != 0) {
      continue;
    }
    if (token.kind == .procedureStart) {
      procedure++;
    } else if (token.kind == .procedureEnd) {
      procedure--;
    }
    if (procedure != 0 || token.kind != .comment) {
      continue;
    }
    if (token.lexeme == '%%BeginSetup') {
      setup = true;
    } else if (token.lexeme == '%%EndSetup') {
      if (opening != null) {
        throw const FormatException('An artwork resource crosses the setup boundary.');
      }
      setup = false;
    }
    if (!setup) {
      continue;
    }
    final AiNativeArtworkResourceKind? next = token.lexeme.startsWith('%AI3_BeginPattern:')
        ? .pattern
        : switch (token.lexeme) {
            '%AI14_BeginSymbol' => .symbol,
            '%AI8_BeginBrushPattern' => .brush,
            _ => null,
          };
    if (next != null) {
      if (opening != null) {
        if (requireOrdinary) {
          throw UnsupportedError('Retained artwork resources cannot contain nested declarations.');
        }
        throw const FormatException('Artwork resource declarations cannot overlap.');
      }
      opening = token;
      kind = next;
    } else if (const {'%AI3_EndPattern', '%AI10_EndSymbol', '%AI8_EndBrushPattern'}.contains(token.lexeme)) {
      final String? ending = switch (kind) {
        .pattern => '%AI3_EndPattern',
        .symbol => '%AI10_EndSymbol',
        .brush => '%AI8_EndBrushPattern',
        null => null,
      };
      if (opening == null || token.lexeme != ending) {
        throw const FormatException('An artwork resource has an unmatched closing wrapper.');
      }
      if (requireOrdinary &&
          (records._projection.isPrivate(opening.start) ||
              records._projection.isPrivate(token.start) ||
              structure.versions.blocks.any((block) => block.start < token.end && block.end > opening!.start))) {
        throw UnsupportedError('Retained resources require unconditional ordinary declaration boundaries.');
      }
      inspected += 1 + structure.versions.blocks.length;
      if (inspected > records.program.limits.maxTokens) {
        throw const AiLimitException(message: 'Artwork resource associations exceed the inspection limit.');
      }
      resources.add(_nativeArtworkResource(structure, reader, kind!, opening, token));
      opening = null;
      kind = null;
    }
  }
  if (opening != null) {
    throw const FormatException('An artwork resource has no closing wrapper.');
  }
  return AiNativeArtworkResources._(structure: structure, resources: resources);
}

/// Reads literal headers while retaining duplicate names and conditional content.
AiNativeArtworkResource _nativeArtworkResource(AiNativeStructure structure, _NativeArtworkResourceReader reader, AiNativeArtworkResourceKind kind, AiToken opening, AiToken closing) {
  final AiNativeRecords records = reader.records;
  final List<AiToken> contents = _pathInterval(records._projection.tokens, opening.end, closing.start, (token) => token.start).toList();
  final List<AiToken> values = contents.where((token) => token.kind != .comment).toList();
  final bool pattern = kind == .pattern;
  final bool private = records._projection.isPrivate(opening.start);
  if (values.length < (pattern ? 6 : 1) || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(values.first.kind)) {
    throw const FormatException('An artwork resource requires a literal name and complete header.');
  }
  if (records._projection.isPrivate(closing.start) != private || values.take(pattern ? 5 : 1).any((token) => records._projection.isPrivate(token.start) != private)) {
    throw const FormatException('Artwork resource headers require matching source representations.');
  }
  AiBoundingBox? bounds;
  if (pattern) {
    final List<AiToken> label = AiPostScript.tokenize(
      latin1.encode(opening.lexeme.substring('%AI3_BeginPattern:'.length)),
      maxBytes: records.program.limits.maxDecodedBytes,
      maxTokens: records.program.limits.maxTokens,
      maxDepth: records.program.limits.maxDepth,
    );
    if (label.length != 1 || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(label.single.kind) || !_sameNativeBytes(aiStringBytes(label.single), aiStringBytes(values.first))) {
      throw const FormatException('Pattern wrapper and declaration names must match.');
    }
    final List<AiToken> rectangle = values.sublist(1, 5);
    if (rectangle.any((token) => token.number == null || !token.number!.isFinite || token.number!.abs() > 9007199254740991) ||
        rectangle[0].number! >= rectangle[2].number! ||
        rectangle[1].number! >= rectangle[3].number! ||
        values.last.kind != .executableName ||
        values.last.lexeme != 'E' ||
        records._projection.isPrivate(values.last.start) != private) {
      throw const FormatException('A pattern requires a portable nonempty rectangle and matching E terminator.');
    }
    bounds = AiBoundingBox(left: rectangle[0].number!.toDouble(), bottom: rectangle[1].number!.toDouble(), right: rectangle[2].number!.toDouble(), top: rectangle[3].number!.toDouble());
  }
  final int start = values[pattern ? 4 : 0].end;
  final int end = pattern ? values.last.start : closing.start;
  final List<AiNativeContainer> metadata = _pathInterval(records.roots, start, end, (record) => record.start).toList();
  if (metadata.any((record) => record.end > end)) {
    throw const FormatException('Artwork metadata crosses its declaration boundary.');
  }
  return AiNativeArtworkResource._(
    reader: reader,
    kind: kind,
    opening: opening,
    closing: closing,
    name: values.first,
    bounds: bounds,
    artworkStart: start,
    artworkEnd: end,
    versions: structure.versions.memberships(start: opening.start, end: closing.end),
    tokens: contents.where((token) => token.start >= start && token.end <= end).toList(),
    metadata: metadata,
    uses: _pathInterval(structure.resourceUses, start, end, (use) => use.instruction.start).where((use) => use.instruction.end <= end).toList(),
  );
}

/// Shares local command parsing and lazy binary-image handles across definitions.
final class _NativeArtworkResourceReader {
  /// Original source and its parser limits.
  final AiNativeRecords records;

  /// Original image declarations, decoded only when a resource contains data.
  late final List<AiNativeRaster> rasters = _readNativeRasters(records, false);

  /// Creates a source-local reader without allocating another native program.
  _NativeArtworkResourceReader({required this.records});

  /// Builds local topology while preserving unqualified commands and records.
  AiNativeDrawing drawing(AiNativeArtworkResource resource) {
    final List<AiNativeItem> items = [];
    final _NativeCommandReader commands = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
    final List<AiNativeRaster> images = resource.rasters;
    int image = 0;
    int owner = 0;
    int embedded = 0;
    for (final AiToken token in resource.tokens) {
      while (owner < resource.metadata.length && resource.metadata[owner].end <= token.start) {
        owner++;
      }
      if (owner < resource.metadata.length && token.start >= resource.metadata[owner].start) {
        if (token.start == resource.metadata[owner].start) {
          commands.finish();
          items.add(resource.metadata[owner]);
        }
        continue;
      }
      while (image < images.length && images[image].end <= token.start) {
        image++;
      }
      if (image < images.length && token.start >= images[image].start) {
        if (images[image].end > resource.artworkEnd || token.end > images[image].end) {
          throw const FormatException('A resource image crosses its declaration boundary.');
        }
        if (token.start == images[image].start) {
          commands.finish();
          items.add(images[image]);
        }
        continue;
      }
      if (token.kind == .comment) {
        if (commands._delimiters.isEmpty && token.lexeme.startsWith('%%BeginDocument')) {
          embedded++;
        } else if (embedded != 0 && token.lexeme == '%%EndDocument') {
          embedded--;
        } else if (embedded == 0 && commands._delimiters.isEmpty && token.lexeme.startsWith('%AI17_')) {
          items.add(AiNativeVersionComment._(token: token));
        }
        continue;
      }
      if (embedded != 0) {
        continue;
      }
      if (token.kind == .data) {
        commands.finish();
        items.add(AiNativeToken._(token: token));
        continue;
      }
      final AiNativeInstruction? command = commands.add(token, isPrivate: records._projection.isPrivate(token.start));
      if (command != null) {
        if (command.operator == 'N' && command.operands.isNotEmpty) {
          throw const FormatException('A resource path or image terminator cannot consume operands.');
        }
        items.add(command);
      }
    }
    commands.finish();
    if (embedded != 0) {
      throw const FormatException('An embedded document crosses its artwork resource.');
    }
    return _NativeDrawingReader(records: records).readItems(items);
  }
}
