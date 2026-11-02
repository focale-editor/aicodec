part of 'package:aicodec/src/model/ai_native_records.dart';

/// Reads linked-file placement syntax without resolving any external resource.
List<AiNativePlacedObject> _readNativePlacements(AiNativeRecords records, bool bodyOnly) {
  final _NativeRecordProjection projection = records._projection;
  final _NativeCommandReader reader = _NativeCommandReader(maxDepth: records.program.limits.maxDepth);
  final Map<int, AiNativeContainer> dictionaries = {
    for (final AiNativeContainer container in records.containers)
      if (container.type == 'ArtDictionary') container.start: container,
  };
  final List<AiNativePlacedObject> objects = [];
  final List<AiNativeInstruction> commands = [];
  final List<AiToken> comments = [];
  AiToken? opening;
  AiToken? relativeDirectory;
  AiToken? previewOpening;
  AiPlacedPreviewData? previewData;
  AiNativePlacedPreview? preview;
  bool relative = false;
  int? fileType;
  int procedures = 0;
  int embedded = 0;
  for (final (int, AiToken) item in projection.tokens.indexed) {
    final AiToken token = item.$2;
    if (bodyOnly && (token.start < records.program.bodyStart || token.start >= records.program.bodyEnd)) {
      continue;
    }
    if (token.kind == .procedureStart) {
      procedures++;
    } else if (token.kind == .procedureEnd) {
      procedures--;
    }
    if (token.kind == .comment && token.lexeme.startsWith('%%BeginDocument')) {
      if (opening != null) {
        throw UnsupportedError('Embedded placed documents require their own native representation.');
      }
      embedded++;
    } else if (token.kind == .comment && token.lexeme == '%%EndDocument') {
      embedded--;
    }
    if (procedures != 0 || embedded != 0) {
      continue;
    }
    if (token.kind == .comment && token.lexeme == '%AI5_BeginPlace') {
      if (opening != null) {
        throw const FormatException('Nested native placed object.');
      }
      opening = token;
      commands.clear();
      comments.clear();
      relativeDirectory = null;
      previewOpening = null;
      previewData = null;
      preview = null;
      fileType = null;
      relative = false;
    } else if (opening != null && token.kind == .comment) {
      if (token.lexeme == '%AI5_EndPlace') {
        reader.finish();
        if (relative ||
            previewOpening != null ||
            commands.length != 2 ||
            commands.first.operator != '`' ||
            commands.last.operator != '~' ||
            commands.last.operands.isNotEmpty ||
            commands.first.isPrivate != commands.last.isPrivate ||
            projection.isPrivate(opening.start) != commands.first.isPrivate ||
            projection.isPrivate(token.start) != commands.first.isPrivate ||
            comments.any((comment) => projection.isPrivate(comment.start) != commands.first.isPrivate)) {
          throw UnsupportedError('Native placement requires one linked-file command and terminator.');
        }
        final AiNativeInstruction placement = commands.first;
        final List<AiToken> operands = placement.operands;
        if (!const {13, 16}.contains(operands.length) ||
            operands.first.kind != .arrayStart ||
            operands[7].kind != .arrayEnd ||
            !const {AiTokenKind.string, AiTokenKind.hexString}.contains(operands.last.kind) ||
            operands.skip(1).take(6).any((field) => field.number == null) ||
            operands.skip(8).take(operands.length - 9).any((field) => field.number == null) ||
            operands.skip(12).take(operands.length - 13).any((field) => field.number != field.number!.truncate()) ||
            relativeDirectory != null && projection.isPrivate(relativeDirectory.start) != placement.isPrivate) {
          throw const FormatException('Invalid native placed-object operands.');
        }
        objects.add(
          AiNativePlacedObject._(
            start: opening.start,
            end: token.end,
            instruction: placement,
            closing: commands.last,
            fileType: fileType,
            comments: comments,
            relativeDirectory: relativeDirectory,
            preview: preview,
            dictionary: _attachedArtDictionary(projection, item.$1 + 1, dictionaries, placement.isPrivate),
          ),
        );
        opening = null;
      } else {
        comments.add(token);
        if (token.lexeme.startsWith('%%FileType:')) {
          final int? value = int.tryParse(token.lexeme.substring('%%FileType:'.length).trim());
          if (fileType != null || value == null || value < 0) {
            throw const FormatException('Invalid native placed-file type.');
          }
          fileType = value;
        } else if (token.lexeme == '%AI28_BeginPlacedRelativePath') {
          reader.finish();
          if (relative || relativeDirectory != null || previewOpening != null || commands.length != 1 || commands.single.operator != '`') {
            throw const FormatException('Repeated native placed-file directory.');
          }
          relative = true;
        } else if (token.lexeme == '%AI28_EndPlacedRelativePath') {
          if (!relative || relativeDirectory == null) {
            throw const FormatException('Missing native placed-file directory.');
          }
          relative = false;
        } else if (token.lexeme == '%AI26_BeginPlacedObjectPreview') {
          reader.finish();
          if (previewOpening != null || preview != null || relative || commands.length != 1 || commands.single.operator != '`') {
            throw const FormatException('Repeated or misplaced native preview.');
          }
          previewOpening = token;
        } else if (token.lexeme == '%AI26_EndPlacedObjectPreview') {
          if (previewOpening == null || previewData == null) {
            throw const FormatException('Missing native placed preview rows.');
          }
          preview = AiNativePlacedPreview._(start: previewOpening.start, end: token.end, layout: previewData, source: records.program.bytes);
          previewOpening = null;
        }
      }
    } else if (opening != null && token.kind == .data) {
      if (previewOpening == null || previewData != null) {
        throw const FormatException('Unexpected native placed-object data.');
      }
      previewData = readAiPlacedPreview(bytes: records.program.bytes, start: token.start, privateData: projection.isPrivate(previewOpening.start));
      if (previewData.end != token.end) {
        throw const FormatException('Native placed preview disagrees with its opaque span.');
      }
    } else if (opening != null && relative) {
      if (relativeDirectory != null || !const {AiTokenKind.string, AiTokenKind.hexString}.contains(token.kind)) {
        throw const FormatException('Invalid native placed-file directory string.');
      }
      relativeDirectory = token;
    } else if (opening != null) {
      final AiNativeInstruction? command = reader.add(token, isPrivate: projection.isPrivate(token.start));
      if (command != null) {
        commands.add(command);
      }
    }
  }
  if (opening != null) {
    throw const FormatException('Unterminated native placed object.');
  }
  return objects;
}
