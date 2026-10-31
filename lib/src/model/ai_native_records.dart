import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:aikit/src/codec/ai_native_data.dart';
import 'package:aikit/src/codec/ai_postscript.dart';
import 'package:aikit/src/model/ai_document.dart';
import 'package:aikit/src/model/ai_limit_exception.dart';
import 'package:aikit/src/model/ai_program.dart';
import 'package:pdfcore/pdfcore.dart';

part '../codec/ai_native_record_parser.dart';
part '../codec/ai_native_document_settings_parser.dart';
part '../codec/ai_native_version_parser.dart';
part '../codec/ai_native_structure_parser.dart';
part '../codec/ai_native_drawing_parser.dart';
part '../codec/ai_native_gradient_parser.dart';
part '../codec/ai_native_gradient_resource_parser.dart';
part '../codec/ai_native_raster_parser.dart';
part '../codec/ai_native_placement_parser.dart';
part '../codec/ai_native_mesh_parser.dart';
part '../codec/ai_native_printing_state.dart';
part '../editing/ai_live_shape_editor.dart';
part '../editing/ai_native_printing_editor.dart';
part '../editing/ai_native_printing_group_editor.dart';
part '../editing/ai_native_path_lifecycle.dart';
part '../editing/ai_native_group_lifecycle.dart';
part '../editing/ai_live_shape_gradient_editor.dart';
part '../editing/ai_live_shape_gradient_placement_editor.dart';
part '../editing/ai_live_shape_similarity_editor.dart';
part '../editing/ai_live_shape_scale_editor.dart';
part '../editing/ai_native_frame_rotation_editor.dart';
part '../editing/ai_native_gradient_editor.dart';
part '../editing/ai_native_gradient_copy_editor.dart';
part '../editing/ai_native_raster_editor.dart';
part '../editing/ai_native_raster_samples_editor.dart';
part '../editing/ai_native_image_geometry_editor.dart';
part '../editing/ai_native_placement_editor.dart';
part '../editing/ai_native_placement_links_editor.dart';
part '../editing/ai_native_gradient_geometry_editor.dart';
part '../editing/ai_native_gradient_placement_geometry.dart';
part '../editing/ai_native_gradient_focus_editor.dart';
part '../editing/ai_native_mesh_paint_editor.dart';
part 'ai_native_drawing.dart';
part 'ai_native_document_settings.dart';
part 'ai_native_versions.dart';
part 'ai_native_structure.dart';
part 'ai_native_printing.dart';
part 'ai_native_gradient.dart';
part 'ai_native_gradient_resources.dart';
part 'ai_native_rasters.dart';
part 'ai_native_raster_samples.dart';
part 'ai_native_placements.dart';
part 'ai_native_art.dart';
part 'ai_native_meshes.dart';

/// One source-backed component of Illustrator's native hierarchical records.
sealed class AiNativeItem {
  /// Inclusive byte offset in the original native program.
  final int start;

  /// Exclusive byte offset in the original native program.
  final int end;

  /// Retains original source coordinates even for comment-prefixed records.
  const AiNativeItem({required this.start, required this.end});
}

/// A lexical value or command retained inside a native record.
final class AiNativeToken extends AiNativeItem {
  /// Token text with native comment prefixes removed and source offsets retained.
  final AiToken token;

  /// Creates an immutable token view.
  AiNativeToken._({required this.token}) : super(start: token.start, end: token.end);
}

/// An ordered entry in a native dictionary, array or object record.
final class AiNativeEntry {
  /// Dictionary string key or object name key; null for positional entries.
  final String? key;

  /// Dictionary scalar type, such as Real, UnicodeString or RealPoint.
  final String? type;

  /// Original scalar type token, including an insertion point for empty strings.
  final AiToken? typeToken;

  /// Value components, including unknown commands and nested records.
  final List<AiNativeItem> items;

  /// Whether this entry contains no value and only a recording qualifier.
  final bool isQualifier;

  /// Creates an immutable entry without discarding unknown value syntax.
  AiNativeEntry._({required this.key, required this.type, required List<AiNativeItem> items, this.typeToken, this.isQualifier = false}) : items = List.unmodifiable(items);

  /// Nested record when this entry contains exactly one container value.
  AiNativeContainer? get container => items.length == 1 && items.single is AiNativeContainer ? items.single as AiNativeContainer : null;

  /// Finite numeric components, or null for nonnumeric values.
  List<double>? get numbers {
    if (items.isEmpty || items.any((item) => item is! AiNativeToken || item.token.number == null)) {
      return null;
    }
    return List.unmodifiable(items.map((item) => (item as AiNativeToken).token.number!.toDouble()));
  }

  /// A single numeric value, or null for other entry shapes.
  double? get number {
    final List<double>? values = numbers;
    return values?.length == 1 ? values!.single : null;
  }

  /// Boolean value for a validated Bool entry.
  bool? get boolean => type == 'Bool' ? number == 1 : null;

  /// Decoded PostScript string bytes, without guessing a text encoding.
  Uint8List? get stringBytes {
    if (items.isEmpty && const {'String', 'UnicodeString'}.contains(type)) {
      return Uint8List(0).asUnmodifiableView();
    }
    if (items.isEmpty || items.any((item) => item is! AiNativeToken || item.token.kind != .string && item.token.kind != .hexString)) {
      return null;
    }
    final BytesBuilder bytes = BytesBuilder(copy: false);
    for (final AiNativeItem item in items) {
      bytes.add(aiStringBytes((item as AiNativeToken).token));
    }
    return bytes.takeBytes().asUnmodifiableView();
  }

  /// Decodes string bytes with an explicitly selected source encoding.
  String? text({Encoding encoding = latin1}) {
    final Uint8List? bytes = stringBytes;
    return bytes == null ? null : encoding.decode(bytes);
  }
}

/// Reports a unique-field lookup encountering preserved repeated values.
///
/// Repeated entries can be valid native data. This error marks an ambiguous
/// typed lookup, without declaring the containing record malformed.
final class AiNativeAmbiguousFieldError extends StateError {
  /// Requested field whose multiple values cannot be selected implicitly.
  final String key;

  /// Inclusive start of the owning native container.
  final int start;

  /// Exclusive end of the owning native container.
  final int end;

  /// Retains the original StateError contract with explicit source context.
  AiNativeAmbiguousFieldError({required this.key, required this.start, required this.end}) : super('Native Illustrator field "$key" is repeated.');
}

/// A native hierarchical container, including unknown future container types.
final class AiNativeContainer extends AiNativeItem {
  /// Native name without its leading slash, such as ArtDictionary or Document.
  final String type;

  /// Ordered entries; repeated object keys remain separate entries.
  final List<AiNativeEntry> entries;

  /// Encoded binary content when the container uses ASCII85Decode.
  final Uint8List? _binary;

  /// First source byte of the comment-prefixed binary payload.
  final int? _binaryStart;

  /// Source byte immediately after the ASCII85 terminator line.
  final int? _binaryEnd;

  /// Creates a source-backed container after checking its terminator and depth.
  AiNativeContainer._({required super.start, required super.end, required this.type, required List<AiNativeEntry> entries, this._binary, this._binaryStart, this._binaryEnd})
    : entries = List.unmodifiable(entries);

  /// Returns all values for a key without losing repeated filter parts.
  List<AiNativeEntry> values(String key) => List.unmodifiable(entries.where((entry) => entry.key == key && !entry.isQualifier));

  /// Returns a unique key, rejecting ambiguous repeated object fields.
  AiNativeEntry? operator [](String key) {
    final List<AiNativeEntry> found = values(key);
    if (found.length > 1) {
      throw AiNativeAmbiguousFieldError(key: key, start: start, end: end);
    }
    return found.singleOrNull;
  }

  /// Whether the original container has an explicit recording qualifier.
  bool get notRecorded => entries.any((entry) => entry.isQualifier && entry.key == 'NotRecorded');

  /// Whether an ASCII85 payload is available for bounded decoding.
  bool get hasBinary => _binary != null;

  /// Decodes a binary record through PdfCore's bounded ASCII85 implementation.
  Uint8List decodeBinary({int maxOutputBytes = 128 * 1024 * 1024}) {
    if (maxOutputBytes <= 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    final Uint8List? encoded = _binary;
    if (encoded == null) {
      throw StateError('This native Illustrator record contains no binary payload.');
    }
    return PdfFilters.decode(
      PdfStream(
        dictionary: PdfDictionary(values: {'Filter': PdfName(value: 'ASCII85Decode')}),
        data: encoded,
      ),
      limits: PdfLimits(maxStreamBytes: maxOutputBytes),
    ).asUnmodifiableView();
  }
}

/// Immutable native dictionaries, object records and binary resources.
///
/// Comment-prefixed authoring records are parsed independently of PostScript
/// drawing instructions. Unknown types and commands retain their source spans.
/// This does not execute PostScript or interpret arbitrary plug-in semantics.
final class AiNativeRecords {
  /// Native snapshot owning every returned source span.
  final AiProgram program;

  /// Top-level hierarchical records in source order.
  final List<AiNativeContainer> roots;

  /// Lazily indexed ownership for repeated nested-art lookups in one snapshot.
  late final Set<AiNativeContainer> _ownedContainers = containers.toSet();

  /// Shared projected tokens, avoiding a full reparse for every nested Art path.
  late final _NativeRecordProjection _projection = _NativeRecordProjection(program: program);

  /// Creates a checked immutable view of native authoring records.
  factory AiNativeRecords.decode({required AiProgram program}) {
    final _NativeRecordReader reader = _NativeRecordReader(program: program);
    return AiNativeRecords._(program: program, roots: reader.read());
  }

  /// Retains the source snapshot and the completed hierarchy.
  AiNativeRecords._({required this.program, required List<AiNativeContainer> roots}) : roots = List.unmodifiable(roots);

  /// Iterates every container in source order, including nested dictionaries.
  Iterable<AiNativeContainer> get containers sync* {
    /// Walks the already depth-bounded hierarchy without interpreting its data.
    Iterable<AiNativeContainer> walk(AiNativeContainer container) sync* {
      yield container;
      for (final AiNativeEntry entry in container.entries) {
        for (final AiNativeItem item in entry.items) {
          if (item is AiNativeContainer) {
            yield* walk(item);
          }
        }
      }
    }

    for (final AiNativeContainer root in roots) {
      yield* walk(root);
    }
  }

  /// Native artboards in document order, independent of PDF preview pages.
  List<AiNativeArtboard> get artboards {
    final List<AiNativeArtboard> result = [];
    for (final AiNativeContainer root in roots.where((root) => root.type == 'Document')) {
      final AiNativeContainer? array = root['Recorded']?.container?['ArtboardArray']?.container;
      if (array == null) {
        continue;
      }
      if (array.type != 'Array') {
        throw const FormatException('Invalid Illustrator artboard array.');
      }
      for (final (int, AiNativeEntry) indexed in array.entries.indexed) {
        final AiNativeEntry entry = indexed.$2;
        final AiNativeContainer? dictionary = entry.container;
        if (dictionary == null || dictionary.type != 'Dictionary') {
          throw const FormatException('Invalid Illustrator artboard entry.');
        }
        result.add(AiNativeArtboard._(record: dictionary, document: root, index: indexed.$1));
      }
    }
    return List.unmodifiable(result);
  }

  /// Replaces an owned binary payload while retaining its header and fields.
  ///
  /// This low-level operation does not synchronize dependent drawing or text
  /// layout records. ASCII85 encoding is shared with PdfCore.
  AiNativeRecords replaceBinary({required AiNativeContainer container, required List<int> bytes}) {
    if (!containers.contains(container) || !container.hasBinary) {
      throw ArgumentError('Invalid or foreign Illustrator binary record edit.');
    }
    final Uint8List encoded = PdfFilters.encodeAscii85(
      bytes: bytes,
      limits: PdfLimits(maxStreamBytes: program.limits.maxDecodedBytes),
    );
    final BytesBuilder output = BytesBuilder(copy: false);
    for (int offset = 0; offset < encoded.length - 2; offset += 80) {
      output.addByte(37);
      output.add(Uint8List.sublistView(encoded, offset, offset + 80 < encoded.length - 2 ? offset + 80 : encoded.length - 2));
      output.addByte(10);
    }
    output.add([37, 126, 62]);
    return AiNativeRecords.decode(
      program: AiNativeEditor.apply(
        program: program,
        edits: [AiSourceEdit(start: container._binaryStart!, end: container._binaryEnd!, bytes: output.takeBytes())],
      ),
    );
  }

  /// Replaces string bytes while retaining the native key and scalar type.
  ///
  /// Encoding selection and synchronization with any dependent records belong
  /// to the caller. Split source fragments are replaced atomically.
  AiNativeRecords replaceString({required AiNativeEntry entry, required List<int> bytes}) {
    if (!containers.any((container) => container.entries.contains(entry)) || entry.stringBytes == null || bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Invalid or foreign Illustrator string record edit.');
    }
    final List<int> encoded = latin1.encode('(${bytes.map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}').join()})');
    final List<AiSourceEdit> edits = entry.items.isEmpty
        ? [
            AiSourceEdit(start: entry.typeToken!.start, end: entry.typeToken!.start, bytes: [...encoded, 32]),
          ]
        : [
            AiSourceEdit(start: entry.items.first.start, end: entry.items.first.end, bytes: encoded),
            for (final AiNativeItem fragment in entry.items.skip(1)) AiSourceEdit(start: fragment.start, end: fragment.end, bytes: []),
          ];
    return AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: program, edits: edits),
    );
  }

  /// Replaces a scalar value while preserving its key, type and unrelated bytes.
  ///
  /// This low-level edit does not synchronize drawing geometry or PDF appearance.
  /// Use it only when the caller also updates every dependent representation.
  AiNativeRecords replaceNumbers({required AiNativeEntry entry, required List<double> values}) {
    final bool owned = containers.any((container) => container.entries.contains(entry));
    final List<double>? previous = entry.numbers;
    if (!owned ||
        previous == null ||
        previous.length != values.length ||
        values.any((value) => !value.isFinite) ||
        entry.type == 'Bool' && values.any((value) => value != 0 && value != 1) ||
        entry.type == 'Int' && values.any((value) => value != value.truncateToDouble() || value.abs() > 9007199254740991)) {
      throw ArgumentError('Invalid or foreign Illustrator numeric record edit.');
    }
    final List<AiSourceEdit> edits = [
      for (int index = 0; index < values.length; index++)
        AiSourceEdit(
          start: entry.items[index].start,
          end: entry.items[index].end,
          bytes: latin1.encode(const {'Int', 'Bool'}.contains(entry.type) ? values[index].toInt().toString() : values[index].toString()),
        ),
    ];
    return AiNativeRecords.decode(
      program: AiNativeEditor.apply(program: program, edits: edits),
    );
  }
}

/// An editable artboard record retaining its native drawing-coordinate bounds.
final class AiNativeArtboard {
  /// Owning Document record, independent of catalog/page preview ownership.
  final AiNativeContainer document;

  /// Position within the owning document's ArtboardArray.
  final int index;

  /// Source dictionary owning the artboard's fields and unknown settings.
  final AiNativeContainer record;

  /// Validated artboard rectangle in native drawing coordinates, with y up.
  final AiBoundingBox bounds;

  /// Checks required coordinates without inventing missing artboard geometry.
  factory AiNativeArtboard._({required AiNativeContainer record, required AiNativeContainer document, required int index}) {
    final AiNativeEntry? firstEntry = record['PositionPoint1'];
    final AiNativeEntry? secondEntry = record['PositionPoint2'];
    final List<double>? first = firstEntry?.numbers;
    final List<double>? second = secondEntry?.numbers;
    if (first?.length != 2 ||
        second?.length != 2 ||
        firstEntry?.type != 'RealPointRelToROrigin' ||
        secondEntry?.type != 'RealPointRelToROrigin' ||
        record['Name']?.stringBytes == null ||
        record['IsArtboardSelected'] != null && (record['IsArtboardSelected']!.type != 'Bool' || !const {0, 1}.contains(record['IsArtboardSelected']!.number)) ||
        record['ArtboardUUID'] != null && (!const {'String', 'UnicodeString'}.contains(record['ArtboardUUID']!.type) || record['ArtboardUUID']!.stringBytes == null) ||
        record['RulerOrigin'] != null && (record['RulerOrigin']!.type != 'RealPoint' || record['RulerOrigin']!.numbers?.length != 2)) {
      throw const FormatException('Incomplete Illustrator artboard geometry or name.');
    }
    return AiNativeArtboard._checked(
      record: record,
      document: document,
      index: index,
      bounds: AiBoundingBox(left: first![0], bottom: second![1], right: second[0], top: first[1]),
    );
  }

  /// Stores a source-backed artboard after validating its bounds.
  const AiNativeArtboard._checked({required this.record, required this.document, required this.index, required this.bounds});

  /// Exact PostScript name bytes, ready for an explicitly selected text encoding.
  Uint8List get nameBytes => record['Name']!.stringBytes!;

  /// Whether this was the active artboard in the saved document.
  bool get selected => record['IsArtboardSelected']?.boolean ?? false;

  /// Stable source identifier when the producing Illustrator version stored one.
  String? get identifier => record['ArtboardUUID']?.text();

  /// Explicit artboard ruler origin in canvas coordinates, with y down.
  ///
  /// Missing origins stay absent; drawing bounds and global/text origins are
  /// different fields and are never substituted for this saved value.
  List<double>? get rulerOrigin => record['RulerOrigin']?.numbers;
}
