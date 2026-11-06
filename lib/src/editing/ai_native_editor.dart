part of 'package:illustratorkit/src/model/ai_program.dart';

/// One byte-range replacement against an immutable native source snapshot.
final class AiSourceEdit {
  /// Inclusive original byte offset.
  final int start;

  /// Exclusive original byte offset.
  final int end;

  /// Owned replacement bytes.
  final Uint8List _bytes;

  /// Creates an edit; bounds and overlap are checked when applying a batch.
  AiSourceEdit({required this.start, required this.end, required List<int> bytes}) : _bytes = Uint8List.fromList(bytes) {
    if (start < 0 || end < start || bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Invalid Illustrator source edit.');
    }
  }

  /// Immutable replacement payload.
  Uint8List get bytes => _bytes.asUnmodifiableView();
}

/// Applies atomic source edits while preserving all untouched native data.
abstract final class AiNativeEditor {
  /// Expands DSC bounds to include their affine-transformed original extent.
  ///
  /// [matrix] uses the six drawing-space coefficients `[a, b, c, d, tx, ty]`.
  /// This is conservative for a partial selection and includes stroke extents
  /// already represented by the original bounds. Artboards and nested document
  /// bounds stay fixed; deferred declarations retain their trailer resolution.
  static List<AiSourceEdit> affineBoundsEdits({required AiProgram program, required List<double> matrix}) {
    if (matrix.length != 6 || matrix.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
      throw ArgumentError('Bounds transformation requires six finite, bounded affine coefficients.');
    }
    return _drawingBoundsEdits(program, (previous) {
      final List<double> horizontal = [previous.left, previous.right];
      final List<double> vertical = [previous.bottom, previous.top];
      for (final double x in [previous.left, previous.right]) {
        for (final double y in [previous.bottom, previous.top]) {
          horizontal.add(matrix[0] * x + matrix[2] * y + matrix[4]);
          vertical.add(matrix[1] * x + matrix[3] * y + matrix[5]);
        }
      }
      if ([...horizontal, ...vertical].any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
        throw ArgumentError('Transformed drawing bounds exceed finite source-coordinate limits.');
      }
      horizontal.sort();
      vertical.sort();
      return [horizontal.first, vertical.first, horizontal.last, vertical.last];
    });
  }

  /// Plans conservative DSC bounds covering both original and translated art.
  ///
  /// Displacements use drawing coordinates with y increasing upwards. Artboards
  /// stay fixed. Embedded documents and procedure comments are left untouched;
  /// `(atend)` declarations retain their trailer-based resolution.
  static List<AiSourceEdit> translationBoundsEdits({required AiProgram program, required double deltaX, required double deltaY}) {
    if (!deltaX.isFinite || !deltaY.isFinite) {
      throw ArgumentError('Translation requires finite coordinate offsets.');
    }
    return _drawingBoundsEdits(
      program,
      (previous) => [
        previous.left + (deltaX < 0 ? deltaX : 0),
        previous.bottom + (deltaY < 0 ? deltaY : 0),
        previous.right + (deltaX > 0 ? deltaX : 0),
        previous.top + (deltaY > 0 ? deltaY : 0),
      ],
    );
  }

  /// Expands existing DSC drawing bounds to include an edited object's extent.
  ///
  /// Artboards, embedded documents and procedure comments remain unchanged.
  /// Deferred declarations retain their trailer-based resolution. Bounds never
  /// shrink because the remaining artwork may still occupy the original area.
  static List<AiSourceEdit> includeBoundsEdits({required AiProgram program, required AiBoundingBox bounds}) => _drawingBoundsEdits(
    program,
    (previous) => [
      if (previous.left < bounds.left) previous.left else bounds.left,
      if (previous.bottom < bounds.bottom) previous.bottom else bounds.bottom,
      if (previous.right > bounds.right) previous.right else bounds.right,
      if (previous.top > bounds.top) previous.top else bounds.top,
    ],
  );

  /// Plans source-backed bounds edits with one policy for every DSC variant.
  static List<AiSourceEdit> _drawingBoundsEdits(AiProgram program, List<double> Function(AiBoundingBox) update) {
    final List<AiSourceEdit> edits = [];
    int embedded = 0;
    int procedure = 0;
    for (final AiToken token in AiPostScript.tokenize(program.bytes, maxBytes: program.limits.maxDecodedBytes, maxTokens: program.limits.maxTokens, maxDepth: program.limits.maxDepth)) {
      if (token.kind == .procedureStart) {
        procedure++;
      } else if (token.kind == .procedureEnd) {
        procedure--;
      }
      if (token.kind != .comment || procedure != 0) {
        continue;
      }
      if (token.lexeme.startsWith('%%BeginDocument')) {
        embedded++;
      } else if (token.lexeme == '%%EndDocument') {
        embedded--;
      }
      if (embedded != 0) {
        continue;
      }
      final RegExpMatch? match = RegExp(r'^(%%(?:HiResBoundingBox|BoundingBox|PageBoundingBox):)\s*(.*)$').firstMatch(token.lexeme);
      if (match == null || match[2] == '(atend)') {
        continue;
      }
      final AiBoundingBox previous = AiBoundingBox.parse(value: match[2]!);
      final List<double> bounds = update(previous);
      if (bounds.any((value) => !value.isFinite || value.abs() > 9007199254740991)) {
        throw ArgumentError('Drawing bounds exceed finite source-coordinate limits.');
      }
      if (bounds[0] == previous.left && bounds[1] == previous.bottom && bounds[2] == previous.right && bounds[3] == previous.top) {
        continue;
      }
      final bool precise = match[1] == '%%HiResBoundingBox:';
      final List<String> fields = [
        for (int index = 0; index < bounds.length; index++)
          if (precise) bounds[index].toString() else (index < 2 ? bounds[index].floor() : bounds[index].ceil()).toString(),
      ];
      edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: latin1.encode('${match[1]} ${fields.join(' ')}')));
    }
    return List.unmodifiable(edits);
  }

  /// Applies nonoverlapping edits, then reparses the complete native program.
  ///
  /// Offsets always refer to [program], never to a previously edited result.
  /// This low-level API leaves cross-object/private-data consistency to callers.
  static AiProgram apply({required AiProgram program, required List<AiSourceEdit> edits}) => AiProgram.decode(
    bytes: copyRange(program: program, start: 0, end: program.bytes.length, edits: edits),
    limits: program.limits,
  );

  /// Copies a source range with checked edits for duplicating native resources.
  ///
  /// Edit offsets refer to the original program. This byte-level operation does
  /// not parse the copied fragment or resolve its references; [apply] reparses
  /// complete programs. The owning program's byte limit bounds the result.
  /// Insertions precede replacements at the same offset; equal-position
  /// insertions retain their input order.
  static Uint8List copyRange({required AiProgram program, required int start, required int end, List<AiSourceEdit> edits = const []}) {
    if (start < 0 || end < start || end > program.bytes.length) {
      throw ArgumentError('Invalid Illustrator source range.');
    }
    final List<(int, AiSourceEdit)> indexed = edits.indexed.toList()
      ..sort((first, second) {
        final int start = first.$2.start.compareTo(second.$2.start);
        final int end = first.$2.end.compareTo(second.$2.end);
        return start != 0 ? start : (end != 0 ? end : first.$1.compareTo(second.$1));
      });
    final List<AiSourceEdit> ordered = indexed.map((entry) => entry.$2).toList();
    int position = start;
    int resultLength = end - start;
    for (final AiSourceEdit edit in ordered) {
      if (edit.start < position || edit.end > end) {
        throw ArgumentError('Overlapping or out-of-bounds Illustrator source edits.');
      }
      resultLength += edit.bytes.length - (edit.end - edit.start);
      position = edit.end;
    }
    if (resultLength > program.limits.maxDecodedBytes) {
      throw const FormatException('Edited Illustrator program exceeds the byte limit.');
    }
    final BytesBuilder result = BytesBuilder(copy: false);
    position = start;
    for (final AiSourceEdit edit in ordered) {
      result
        ..add(Uint8List.sublistView(program.bytes, position, edit.start))
        ..add(edit.bytes);
      position = edit.end;
    }
    result.add(Uint8List.sublistView(program.bytes, position, end));
    return result.takeBytes();
  }

  /// Updates a native layer's display name and flags, including CC header flags.
  ///
  /// Names use explicit source bytes; [name] accepts Latin-1 only, avoiding a
  /// guessed legacy encoding. Use [nameBytes] for an application-selected encoding.
  static AiProgram updateLayer({required AiProgram program, required AiLayer layer, String? name, List<int>? nameBytes, bool? visible, bool? locked, bool? printing}) {
    if (!program.layers.contains(layer)) {
      throw ArgumentError('The layer belongs to another Illustrator snapshot.');
    }
    if (name != null && nameBytes != null) {
      throw ArgumentError('Supply either name or nameBytes.');
    }
    final List<AiSourceEdit> edits = [];

    /// Replaces only a numeric flag token without normalizing adjacent syntax.
    void flag(AiToken token, bool value) => edits.add(AiSourceEdit(start: token.start, end: token.end, bytes: [if (value) 49 else 48]));

    if (visible != null) {
      flag(layer.begin.operands[0], visible);
    }
    if (locked != null) {
      flag(layer.begin.operands[2], !locked);
    }
    if (printing != null) {
      flag(layer.begin.operands[3], printing);
    }
    int? flagEnd = layer.header.where((command) => command.operator == 'AE').firstOrNull?.end;
    for (final AiInstruction instruction in layer.header) {
      // Only the consecutive legacy flags immediately after AE belong to the
      // layer. Later flags may belong to its first group or another child.
      if (flagEnd != null && instruction.start >= flagEnd) {
        if (!const {'A', 'Xw'}.contains(instruction.operator) || latin1.decode(program.bytes.sublist(flagEnd, instruction.start)).trim().isNotEmpty) {
          break;
        }
        flagEnd = instruction.end;
      }
      if (layer.header.any((header) => header.operator == 'AE') && instruction.operands.length == 1 && instruction.numbers != null) {
        if (instruction.operator == 'Xw' && visible != null) {
          flag(instruction.operands.single, !visible);
        } else if (instruction.operator == 'A' && locked != null) {
          flag(instruction.operands.single, locked);
        }
      }
    }
    final List<int>? renamed = nameBytes ?? (name == null ? null : latin1.encode(name));
    if (renamed != null) {
      if (renamed.any((byte) => byte < 0 || byte > 255)) {
        throw ArgumentError('Layer name contains an invalid byte.');
      }
      final List<int> encoded = latin1.encode('(${renamed.map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()})');
      final AiInstruction? naming = layer.naming;
      edits.add(
        naming == null
            ? AiSourceEdit(start: layer.begin.end, end: layer.begin.end, bytes: [10, ...encoded, ...latin1.encode(' Ln\n')])
            : AiSourceEdit(start: naming.operands.single.start, end: naming.operands.single.end, bytes: encoded),
      );
    }
    return apply(program: program, edits: edits);
  }

  /// Replaces plain path geometry while retaining its paint and corner semantics.
  ///
  /// Appearance-owned paths are rejected: changing only a rendered outline would
  /// leave live-shape, text or plug-in authoring geometry inconsistent.
  /// Qualified CC point counts are updated with explicit closed-path endpoints.
  static AiProgram replacePath({required AiProgram program, required AiPath path, required List<AiPathSegment> segments}) {
    if (!program.paths.contains(path)) {
      throw ArgumentError('The path belongs to another Illustrator snapshot.');
    }
    if (path.hasDependentAppearance || program.hasPrivateExtensions || program.hasUnhandledBodyOperators) {
      throw UnsupportedError('Path replacement requires synchronized private Illustrator appearance data.');
    }
    if (segments.isEmpty || segments.first.operator != 'm') {
      throw ArgumentError('An Illustrator path must begin with moveto.');
    }
    final AiInstruction? count = _pathPointCount(program, path);
    final List<AiPathSegment> normalized = [...segments];
    if (count != null) {
      if (segments.skip(1).any((segment) => segment.operator == 'm')) {
        throw ArgumentError('A counted native path requires exactly one initial moveto.');
      }
      final List<double> first = segments.first.coordinates;
      final List<double> last = segments.last.coordinates;
      if (path.closed && (segments.length == 1 || last[last.length - 2] != first[0] || last.last != first[1])) {
        normalized.add(AiPathSegment(operator: 'L', coordinates: first));
      }
    }
    final String replacement = normalized.map((segment) => '${segment.coordinates.map((value) => value.toString()).join(' ')} ${segment.operator}\n').join();
    final List<AiSourceEdit> edits = [
      if (count != null) AiSourceEdit(start: count.operands.single.start, end: count.operands.single.end, bytes: latin1.encode('${normalized.length - (path.closed ? 1 : 0)}')),
      AiSourceEdit(start: path.geometry.first.start, end: path.geometry.first.end, bytes: latin1.encode(replacement)),
      for (final AiInstruction instruction in path.geometry.skip(1)) AiSourceEdit(start: instruction.start, end: instruction.end, bytes: []),
    ];
    return apply(program: program, edits: edits);
  }

  /// Locates an optional source count without crossing another path or object.
  static AiInstruction? _pathPointCount(AiProgram program, AiPath path) {
    int previous = program.bodyStart;
    for (final AiPath candidate in program.paths) {
      if (candidate.paint.end < path.geometry.first.start && candidate.paint.end > previous) {
        previous = candidate.paint.end;
      }
    }
    AiInstruction? count;
    for (final AiInstruction item in program.instructions.where((item) => item.start >= previous && item.end <= path.paint.end)) {
      if (item.operator == 'As') {
        if (count != null || item.start >= path.geometry.first.start) {
          throw UnsupportedError('A native point count must precede exactly one path.');
        }
        count = item;
      } else if (count != null && const {'u', 'U', '*u', '*U', 'q', 'Q', 'Lb', 'LB'}.contains(item.operator)) {
        throw UnsupportedError('A native point count crosses an object boundary.');
      }
    }
    if (count != null) {
      final List<double>? numbers = count.numbers;
      final List<double> first = path.geometry.first.numbers!;
      final List<double> last = path.geometry.last.numbers!;
      if (numbers == null ||
          numbers.length != 1 ||
          numbers.single != path.geometry.length - (path.closed ? 1 : 0) ||
          path.geometry.skip(1).any((item) => item.operator == 'm') ||
          path.closed && (path.geometry.length == 1 || last[last.length - 2] != first[0] || last.last != first[1])) {
        throw UnsupportedError('The native point count or closed-path layout is inconsistent.');
      }
    }
    return count;
  }
}
