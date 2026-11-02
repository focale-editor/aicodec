import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aikit/src/codec/ai_codec.dart';
import 'package:aikit/src/model/ai_document.dart';
import 'package:pdfcore/pdfcore.dart';
import 'package:zcodec/zcodec.dart';

part 'ai_native_save.dart';
part 'ai_native_metadata_header.dart';
part 'ai_native_page_save.dart';

/// Explicit treatment of existing position-based PDF page labels during remapping.
enum AiNativePageLabelsPolicy {
  /// Require the host to replace or remove labels when page structure changes.
  requireUpdated,

  /// Keep existing labels attached to their numerical PDF positions.
  retainPositions,
}

/// One supplied PDF page and the original native metadata owner to retain or copy.
final class AiNativePageBinding {
  /// Indirect page reference in the host's synchronized PDF graph.
  final PdfReference page;

  /// Original source owner index; null explicitly selects its catalog metadata.
  ///
  /// A retained native page must select its own original index. New native pages
  /// explicitly choose a metadata template from the same extracted program.
  final int? metadataOwner;

  /// Records a mapping without inferring it from bounds, UUIDs or page counts.
  const AiNativePageBinding({required this.page, required this.metadataOwner});
}

/// A native replacement with its explicitly ordered compatibility PDF pages.
final class AiNativePageReplacement {
  /// Immutable source and supplied native bytes.
  final AiNativeReplacement replacement;

  /// Native page order, using current PDF references and original metadata owners.
  final List<AiNativePageBinding> pages;

  /// Original pages explicitly governed by this source's catalog metadata.
  ///
  /// Use only for pages without their own native owner, notably before removing
  /// them. The source must own catalog metadata; foreign, repeated or separately
  /// owned pages reject. Retained declared pages must bind to this replacement.
  /// Omission never infers ownership from page order or a catalog attachment.
  final List<PdfReference> catalogPages;

  /// Freezes one explicit mapping; any original catalog alias remains attached.
  AiNativePageReplacement({required this.replacement, required List<AiNativePageBinding> pages, List<PdfReference> catalogPages = const []})
    : pages = List.unmodifiable(pages),
      catalogPages = List.unmodifiable(catalogPages);
}

/// Compression inside Illustrator's private PDF streams, after PDF filtering.
enum AiNativeCompression {
  /// Plain authoring program, possibly compressed by the outer PDF filter.
  plain,

  /// The AI12 envelope used by CS2 and later legacy-compatible files.
  zlib,

  /// The AI24 envelope used by recent Illustrator releases.
  zstandard,
}

/// Resource ceilings shared by native extraction, parsing and editing.
final class AiNativeLimits {
  /// Maximum aggregate encoded bytes read from private streams.
  final int maxEncodedBytes;

  /// Maximum aggregate uncompressed program bytes.
  final int maxDecodedBytes;

  /// Maximum Zstandard history window allocation.
  final int maxWindowBytes;

  /// Maximum lexical tokens in a program.
  final int maxTokens;

  /// Maximum nested procedures and artwork containers.
  final int maxDepth;

  /// Creates bounded defaults without requiring a native compression engine.
  const AiNativeLimits({
    this.maxEncodedBytes = 128 * 1024 * 1024,
    this.maxDecodedBytes = 128 * 1024 * 1024,
    this.maxWindowBytes = 32 * 1024 * 1024,
    this.maxTokens = 1000000,
    this.maxDepth = 128,
  });

  /// Rejects unusable policies before processing input.
  void validate() {
    if ([maxEncodedBytes, maxDecodedBytes, maxWindowBytes, maxTokens, maxDepth].any((value) => value <= 0) || maxWindowBytes > 0x80000000) {
      throw ArgumentError('Invalid Illustrator native-data limits.');
    }
  }
}

/// One decoded authoring program, independently of its PDF appearance.
final class AiNativeSource {
  /// Owned program bytes; unknown native instructions remain intact.
  final Uint8List _bytes;

  /// The source container, used to verify ownership when rewriting.
  final AiDocument document;

  /// Private-data owners; null denotes the catalog, integers denote pages.
  final List<int?> owners;

  /// Original inner compression family.
  final AiNativeCompression compression;

  /// Original numbered-block key prefix.
  final String _prefix;

  /// Creates an extraction result with immutable bytes and ownership.
  AiNativeSource._({required List<int> bytes, required this.document, required List<int?> owners, required this.compression, required this._prefix})
    : _bytes = Uint8List.fromList(bytes),
      owners = List.unmodifiable(owners);

  /// Exact decoded native program, including prolog and unknown extensions.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  /// Exposes the authoring program as a standalone PostScript AI container.
  ///
  /// This does not create a PDF preview or downgrade the Illustrator version.
  AiPostScriptDocument asPostScript({AiLimits limits = const AiLimits()}) => AiDecoder(limits: limits).convert(_bytes) as AiPostScriptDocument;
}

/// An immutable replacement of one extracted program and all its native owners.
final class AiNativeReplacement {
  /// Original extraction snapshot; all batch entries must share its document.
  final AiNativeSource source;

  /// Copied authoring bytes, independent of subsequent caller mutations.
  final Uint8List _program;

  /// Takes ownership of supplied native bytes without interpreting artwork.
  AiNativeReplacement({required this.source, required List<int> program}) : _program = _copyProgram(program);

  /// Authoring bytes to package with the host's synchronized representation.
  Uint8List get program => _program.asUnmodifiableView();

  /// Rejects out-of-range integers before copying into an unsigned buffer.
  static Uint8List _copyProgram(List<int> program) {
    if (program.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Native replacement requires byte values.');
    }
    return Uint8List.fromList(program);
  }
}

/// Reads and rewrites native Illustrator data without executing PostScript.
abstract final class AiNativeData {
  /// Collects independent programs, coalescing shared PDF private dictionaries.
  ///
  /// PDF filters are decoded first. Thumbnail-only blocks preceding the program
  /// are excluded. Each owner's numbered blocks must be contiguous; unrelated
  /// pages are never concatenated into a single compressed stream.
  static List<AiNativeSource> extract(AiDocument document, {AiNativeLimits limits = const AiNativeLimits()}) {
    limits.validate();
    if (document is AiPostScriptDocument) {
      if (document.postScriptLength > limits.maxDecodedBytes || document.postScriptLength > limits.maxEncodedBytes) {
        throw const FormatException('Native Illustrator program exceeds the decoded byte limit.');
      }
      return List.unmodifiable([AiNativeSource._(bytes: document.postScriptBytes, document: document, owners: [], compression: .plain, prefix: 'AIPrivateData')]);
    }
    final PdfDocument pdf = (document as AiPdfDocument).pdf;
    final Map<_NativeOwner, List<_NativeOwner>> owners = LinkedHashMap(equals: _sameBlocks, hashCode: (owner) => Object.hash(owner.prefix, Object.hashAll(owner.blocks)));
    for (final _NativeOwner owner in _owners(pdf)) {
      owners.putIfAbsent(owner, () => []).add(owner);
    }
    final List<AiNativeSource> sources = [];
    int encodedTotal = 0;
    int filteredTotal = 0;
    int decodedTotal = 0;
    for (final MapEntry<_NativeOwner, List<_NativeOwner>> entry in owners.entries) {
      final _NativeOwner owner = entry.key;
      final List<int?> aliases = entry.value.map((alias) => alias.pageIndex).toList();
      final BytesBuilder joined = BytesBuilder(copy: false);
      bool started = false;
      for (final _NativeBlock block in owner.blocks) {
        final PdfValue value = pdf.resolve(block.value);
        if (value is! PdfStream) {
          throw const FormatException('Illustrator private data must be a stream.');
        }
        encodedTotal += value.data.length;
        if (encodedTotal > limits.maxEncodedBytes) {
          throw const FormatException('Illustrator private streams exceed the encoded byte limit.');
        }
        final Uint8List data = PdfFilters.decode(
          value,
          resolve: pdf.resolve,
          limits: PdfLimits(maxStreamBytes: limits.maxEncodedBytes - filteredTotal > 0 ? limits.maxEncodedBytes - filteredTotal : 1),
        );
        filteredTotal += data.length;
        if (filteredTotal > limits.maxEncodedBytes) {
          throw const FormatException('Filtered Illustrator streams exceed the aggregate byte limit.');
        }
        if (!started) {
          if (!_startsEnvelope(data)) {
            // Thumbnail blocks have their own DSC header; arbitrary garbage is
            // not searched for a lucky zlib signature inside binary pixels.
            if (!_starts(data, '%%BoundingBox:') && !_starts(data, '%%HiResBoundingBox:') && !_starts(data, '%AI7_Thumbnail:')) {
              throw const FormatException('Unrecognized Illustrator native-data envelope.');
            }
            continue;
          }
          started = true;
        }
        if (joined.length + data.length > limits.maxEncodedBytes) {
          throw const FormatException('Illustrator native envelope exceeds the byte limit.');
        }
        joined.add(data);
      }
      if (!started) {
        throw const FormatException('Illustrator private data contains no authoring program.');
      }
      final Uint8List envelope = joined.takeBytes();
      final Uint8List bytes = decodeEnvelope(envelope, limits: limits, remainingBytes: limits.maxDecodedBytes - decodedTotal);
      decodedTotal += bytes.length;
      sources.add(AiNativeSource._(bytes: bytes, document: document, owners: aliases, compression: _compression(envelope)!, prefix: owner.prefix));
    }
    return List.unmodifiable(sources);
  }

  /// Decodes a plain, AI12/zlib or AI24/Zstandard native program envelope.
  static Uint8List decodeEnvelope(List<int> input, {AiNativeLimits limits = const AiNativeLimits(), int? remainingBytes}) {
    limits.validate();
    final int ceiling = remainingBytes ?? limits.maxDecodedBytes;
    if (ceiling <= 0 || ceiling > limits.maxDecodedBytes || input.length > limits.maxEncodedBytes || input.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Invalid or excessive Illustrator native envelope.');
    }
    final AiNativeCompression? compression = _compression(input);
    final Uint8List data = Uint8List.fromList(input);
    final Uint8List decoded;
    try {
      decoded = switch (compression) {
        AiNativeCompression.plain => data,
        AiNativeCompression.zlib => ZlibDecoder(maxOutputBytes: ceiling).convert(Uint8List.sublistView(data, _zlibMarker.length)),
        AiNativeCompression.zstandard => ZstdDecoder(maxWindowBytes: limits.maxWindowBytes, maxOutputBytes: ceiling).convert(
          Uint8List.sublistView(data, _zstandardMarker.length),
        ),
        null => throw const FormatException('Unsupported Illustrator native compression envelope.'),
      };
    } on ZCodecException catch (error) {
      throw FormatException('Invalid Illustrator compressed data: $error');
    }
    if (decoded.length > ceiling || !_starts(decoded, '%!PS-Adobe-')) {
      throw const FormatException('Invalid or excessive decoded Illustrator program.');
    }
    return decoded.asUnmodifiableView();
  }

  /// Encodes authoring bytes using the requested native compression family.
  static Uint8List encodeEnvelope(List<int> program, {required AiNativeCompression compression, AiNativeLimits limits = const AiNativeLimits()}) {
    limits.validate();
    if (program.length > limits.maxDecodedBytes || program.any((byte) => byte < 0 || byte > 255) || !_starts(program, '%!PS-Adobe-')) {
      throw const FormatException('Invalid or excessive Illustrator program.');
    }
    final Uint8List result = switch (compression) {
      AiNativeCompression.plain => Uint8List.fromList(program),
      AiNativeCompression.zlib => Uint8List.fromList([...latin1.encode(_zlibMarker), ...const ZlibEncoder().convert(program)]),
      AiNativeCompression.zstandard => Uint8List.fromList([...latin1.encode(_zstandardMarker), ...const ZstdEncoder().convert(program)]),
    };
    if (result.length > limits.maxEncodedBytes) {
      throw const FormatException('Encoded Illustrator native data exceeds the byte limit.');
    }
    return result;
  }

  /// Replaces an extracted native program and attaches synchronized PDF artwork.
  ///
  /// The caller must derive [synchronizedPdf] from the original PDF graph and
  /// regenerate its appearance from the same edit, retaining original metadata
  /// objects and the catalog/page references in their original order. Foreign
  /// graphs, stale native sources and implicit page remapping are rejected.
  /// Reacquire sources after each save, or use [replaceAll] for one batch. This API
  /// cannot infer equivalence between native and PDF artwork. Stale thumbnail
  /// blocks are removed; private metadata and other producers are retained.
  /// Known AIMetaData header copies follow changed native headers. Unknown cache
  /// layouts reject header changes; unchanged headers retain opaque caches.
  /// All shared owners are updated. Unreferenced old objects are not redacted.
  static AiPdfDocument replace({
    required AiNativeSource source,
    required List<int> program,
    required PdfDocument synchronizedPdf,
    AiNativeLimits limits = const AiNativeLimits(),
    int blockBytes = 65536,
  }) => replaceAll(
    replacements: [AiNativeReplacement(source: source, program: program)],
    synchronizedPdf: synchronizedPdf,
    limits: limits,
    blockBytes: blockBytes,
  );

  /// Atomically packages distinct programs from the same extraction document.
  ///
  /// All native owners and their referenced metadata must still belong to the
  /// original immutable graph. The host may replace page artwork/resources,
  /// but cannot reorder, remove, add or renumber pages through this API. Artboard
  /// counts do not establish a page mapping. Unselected programs stay intact.
  /// [limits] also bounds aggregate replacement bytes and metadata traversal.
  static AiPdfDocument replaceAll({
    required List<AiNativeReplacement> replacements,
    required PdfDocument synchronizedPdf,
    AiNativeLimits limits = const AiNativeLimits(),
    int blockBytes = 65536,
  }) => _replaceNativePrograms(replacements: replacements, synchronizedPdf: synchronizedPdf, limits: limits, blockBytes: blockBytes);

  /// Saves explicit page remappings while preserving unrelated native programs.
  ///
  /// The host derives [synchronizedPdf] from the original graph and supplies all
  /// page content, boxes, resources and dependent PDF structure. Each replacement
  /// declares its complete resulting page order and metadata owners. All new
  /// pages require a binding; removing pages belonging to unselected programs or
  /// leaving references to removed pages rejects. Unselected page order remains
  /// stable. Original catalog aliases remain attached, and retained or copied
  /// metadata dependencies must remain unchanged. Page labels require an explicit policy.
  /// This validates ownership and references, not visual equivalence or drawing.
  static AiPdfDocument replaceMapped({
    required List<AiNativePageReplacement> replacements,
    required PdfDocument synchronizedPdf,
    AiNativePageLabelsPolicy pageLabels = .requireUpdated,
    AiNativeLimits limits = const AiNativeLimits(),
    int blockBytes = 65536,
  }) => _replaceNativePrograms(
    replacements: replacements.map((entry) => entry.replacement).toList(),
    synchronizedPdf: synchronizedPdf,
    limits: limits,
    blockBytes: blockBytes,
    pageReplacements: replacements,
    pageLabels: pageLabels,
  );
}

/// Adobe's zlib envelope marker, with no newline before the compressed bytes.
const String _zlibMarker = '%AI12_CompressedData';

/// Adobe's Zstandard envelope marker, with no newline before the frame.
const String _zstandardMarker = '%AI24_ZStandard_Data';

/// Both AI containers and Illustrator-compatible PDF exports carry native data.
final RegExp _blockPattern = RegExp(r'^(AIPrivateData|AIPDFPrivateData)(\d+)$');

/// Tests an ASCII prefix without decoding a potentially large binary payload.
bool _starts(List<int> bytes, String prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (int index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

/// Recognizes a marker split across numbered streams without scanning payloads.
bool _startsEnvelope(List<int> bytes) {
  if (bytes.isEmpty) {
    return false;
  }
  for (final String marker in ['%!PS-Adobe-', _zlibMarker, _zstandardMarker]) {
    final int length = bytes.length < marker.length ? bytes.length : marker.length;
    if (_starts(bytes, marker.substring(0, length))) {
      return true;
    }
  }
  return false;
}

/// Detects only documented envelopes at a block boundary.
AiNativeCompression? _compression(List<int> bytes) => _starts(bytes, '%!PS-Adobe-')
    ? .plain
    : _starts(bytes, _zlibMarker)
    ? .zlib
    : _starts(bytes, _zstandardMarker)
    ? .zstandard
    : null;

/// One numbered native PDF stream reference or direct stream value.
typedef _NativeBlock = ({int number, PdfValue value});

/// A private dictionary and its enclosing Illustrator metadata.
typedef _NativeOwner = ({int? pageIndex, PdfDictionary illustrator, PdfDictionary data, String prefix, List<_NativeBlock> blocks});

/// Resolves each native-data dictionary without combining independent programs.
List<_NativeOwner> _owners(PdfDocument pdf) {
  final List<_NativeOwner> result = [];
  final List<PdfDictionary> owners = [pdf.catalog, ...pdf.pages.map((page) => page.dictionary)];
  for (int index = 0; index < owners.length; index++) {
    final PdfValue? pieces = owners[index]['PieceInfo'];
    if (pieces == null || pieces is PdfNull) {
      continue;
    }
    final PdfValue? illustratorValue = pdf.dictionary(pieces)['Illustrator'];
    if (illustratorValue == null || illustratorValue is PdfNull) {
      continue;
    }
    final PdfDictionary illustrator = pdf.dictionary(illustratorValue);
    final PdfValue? private = illustrator['Private'];
    if (private == null || private is PdfNull) {
      continue;
    }
    final PdfDictionary data = pdf.dictionary(private);
    for (final String prefix in ['AIPrivateData', 'AIPDFPrivateData']) {
      final List<_NativeBlock> blocks = [];
      for (final MapEntry<String, PdfValue> entry in data.values.entries) {
        final RegExpMatch? match = _blockPattern.firstMatch(entry.key);
        if (match == null || match[1] != prefix) {
          continue;
        }
        final int? number = int.tryParse(match[2]!);
        if (number == null || number <= 0) {
          throw const FormatException('Invalid Illustrator native block number.');
        }
        blocks.add((number: number, value: entry.value));
      }
      blocks.sort((a, b) => a.number.compareTo(b.number));
      for (int block = 0; block < blocks.length; block++) {
        if (blocks[block].number != block + 1) {
          throw const FormatException('Missing or duplicate Illustrator native block number.');
        }
      }
      if (blocks.isNotEmpty) {
        result.add((pageIndex: index == 0 ? null : index - 1, illustrator: illustrator, data: data, prefix: prefix, blocks: blocks));
      }
    }
  }
  return result;
}

/// Identifies aliases by the complete ordered stream sequence, never a subset.
bool _sameBlocks(_NativeOwner first, _NativeOwner second) {
  if (first.prefix != second.prefix || first.blocks.length != second.blocks.length) {
    return false;
  }
  for (int index = 0; index < first.blocks.length; index++) {
    if (first.blocks[index] != second.blocks[index]) {
      return false;
    }
  }
  return true;
}
