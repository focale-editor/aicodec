import 'dart:convert';
import 'dart:typed_data';

import 'package:illustratorkit/src/model/ai_document.dart';
import 'package:pdfcore/pdfcore.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

part '../codec/ai_xmp_parser.dart';
part '../editing/ai_xmp_editor.dart';

/// Bounds for a complete in-memory XMP packet and its XML structure.
final class AiXmpLimits {
  /// Maximum UTF-8 packet size, including padding and rewritten references.
  final int maxBytes;

  /// Maximum XML events and attributes counted before building the tree.
  final int maxNodes;

  /// Maximum nested XML elements.
  final int maxDepth;

  /// Creates limits independent of the much larger native artwork program.
  const AiXmpLimits({this.maxBytes = 8 * 1024 * 1024, this.maxNodes = 100000, this.maxDepth = 64});

  /// Rejects nonpositive resource ceilings.
  void validate() {
    if (maxBytes <= 0 || maxNodes <= 0 || maxDepth <= 0) {
      throw ArgumentError('XMP limits must be positive.');
    }
  }
}

/// The dependency property containing a resource reference.
enum AiXmpResourceKind {
  /// One entry in Illustrator's ordered or unordered dependency manifest.
  manifest,

  /// One resource incorporated into the document by inclusion or reference.
  ingredient,
}

/// An immutable, source-owned dependency reference, without path normalization.
///
/// Manifest entries do not reliably identify native placed objects by index.
/// The host must select references using its own resource mapping. References
/// in history, pantry data and `DerivedFrom` are deliberately excluded.
final class AiXmpResource {
  /// The dependency property containing this reference.
  final AiXmpResourceKind kind;

  /// Zero-based position in the packet's combined dependency inventory.
  final int index;

  /// Exact Unicode path or URI, without decoding or platform conversion.
  final String? filePath;

  /// Identifier shared by versions of the referenced resource, when present.
  final String? documentId;

  /// Identifier of the referenced resource's particular revision, when present.
  final String? instanceId;

  /// Manifest link form, or null for an ingredient or an unspecified form.
  final String? linkForm;

  /// Private element retained only for source ownership and qualified editing.
  final XmlElement _element;

  /// Character span of the complete resource property or ingredient item.
  final ({int start, int end}) _span;

  /// Captures a reference without exposing a mutable XML tree.
  const AiXmpResource._({
    required this.kind,
    required this.index,
    required this.filePath,
    required this.documentId,
    required this.instanceId,
    required this.linkForm,
    required this._element,
    required this._span,
  });
}

/// A bounded UTF-8 XMP packet with source-preserving dependency edits.
///
/// This is a dependency editor, not a complete RDF or XMP processor. Unknown
/// metadata remains byte-equivalent when encoded as UTF-8. Only selected
/// resource elements are serialized again. XML entities declared by a DTD,
/// non-UTF-8 packets and ambiguous dependency structures reject explicitly.
final class AiXmpMetadata {
  /// Exact XML text, including packet instructions, comments and padding.
  final String source;

  /// Limits retained by subsequent edits.
  final AiXmpLimits limits;

  /// Source-owned manifest and ingredient references in document order.
  final List<AiXmpResource> resources;

  /// Parses a Unicode packet after checking size, depth, namespaces and shape.
  factory AiXmpMetadata.parse({required String source, AiXmpLimits limits = const AiXmpLimits()}) => _parseXmp(source, limits);

  /// Captures an immutable dependency inventory and its exact source.
  AiXmpMetadata._({required this.source, required this.limits, required List<AiXmpResource> resources}) : resources = List.unmodifiable(resources);

  /// Reads catalog-level metadata, returning null when no packet is attached.
  ///
  /// Page and image metadata are distinct resources and are not merged. PDF
  /// filters are decoded with the tighter PDF/XMP stream limit. Reading never
  /// fetches a resource or executes XML processing instructions.
  static AiXmpMetadata? fromPdf({required AiPdfDocument document, AiXmpLimits limits = const AiXmpLimits()}) {
    limits.validate();
    final PdfDocument pdf = document.pdf;
    final PdfValue? value = pdf.catalog['Metadata'];
    if (value == null || value is PdfNull) {
      return null;
    }
    final PdfValue resolved = pdf.resolve(value);
    if (resolved is! PdfStream || resolved.dictionary.name('Type') != 'Metadata' || resolved.dictionary.name('Subtype') != 'XML') {
      throw const FormatException('Catalog metadata must be an XML metadata stream.');
    }
    if (resolved.data.length > pdf.limits.maxStreamBytes || resolved.data.length > limits.maxBytes) {
      throw const FormatException('Encoded XMP exceeds the byte limit.');
    }
    final Uint8List bytes = PdfFilters.decode(
      resolved,
      resolve: pdf.resolve,
      limits: PdfLimits(maxStreamBytes: limits.maxBytes < pdf.limits.maxStreamBytes ? limits.maxBytes : pdf.limits.maxStreamBytes),
    );
    final bool bom = bytes.length >= 3 && bytes[0] == 239 && bytes[1] == 187 && bytes[2] == 191;
    return AiXmpMetadata.parse(source: '${bom ? '\uFEFF' : ''}${utf8.decode(bytes)}', limits: limits);
  }

  /// Replaces explicitly selected dependency references with known asset data.
  ///
  /// Pass both matching manifest and ingredient references when appropriate.
  /// Null identifiers remove old identities; they are never inferred from the
  /// path or invented. Existing fallback paths are removed. Selected references
  /// may contain only `filePath`, `documentID`, `instanceID` and `alternatePaths`;
  /// richer relationships or managed metadata require a separate policy and
  /// reject. Other XML, including unselected identical paths, stays exact.
  ///
  /// The host supplies Unicode XMP paths independently of native path bytes.
  /// This method does not change native artwork, previews, document identifiers,
  /// timestamps, placement resolution fields or pantry/history records.
  AiXmpMetadata relink({required Iterable<AiXmpResource> resources, required String filePath, required String? documentId, required String? instanceId}) =>
      _relinkXmp(this, resources, filePath, documentId, instanceId);

  /// Attaches this complete packet to a new PDF snapshot after native saving.
  ///
  /// The catalog and stream receive new indirect objects so shared old metadata
  /// remains unchanged. Pages, native data and other catalog properties are
  /// preserved. Old unreferenced objects remain; this operation is not redaction.
  /// This is an explicit replacement, including when parsed from another PDF.
  AiPdfDocument writeTo({required AiPdfDocument document}) => _writeXmp(this, document);
}
