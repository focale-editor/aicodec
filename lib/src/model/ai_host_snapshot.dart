import 'dart:typed_data';

import 'package:aicodec/src/model/ai_document.dart';
import 'package:pdfcore/pdfcore.dart';

/// Opaque host authoring bound to a separately usable Illustrator/PDF document.
///
/// This is host metadata, never native Illustrator editability. The host defines
/// a SHA-256 binding over [bindingBytes] and [data], and verifies it on restoration.
final class AiHostSnapshot {
  /// Maximum decoded snapshot size, independent of its compressed representation.
  static const int maximumBytes = 32 * 1024 * 1024;

  /// Immutable host-owned payload; its schema is interpreted only by the host.
  final Uint8List data;

  /// Host-supplied SHA-256 binding of the snapshot and its native/PDF container.
  final Uint8List binding;

  /// Freezes a bounded payload and its explicit digest.
  factory AiHostSnapshot({required List<int> data, required List<int> binding}) {
    if (data.length > maximumBytes || binding.length != 32 || (binding.any((byte) => byte < 0 || byte > 255) || data.any((byte) => byte < 0 || byte > 255))) {
      throw ArgumentError('Host snapshots require bounded bytes and a SHA-256 binding.');
    }
    return AiHostSnapshot._(data: Uint8List.fromList(data).asUnmodifiableView(), binding: Uint8List.fromList(binding).asUnmodifiableView());
  }

  /// Stores bytes only after validating their size and range.
  const AiHostSnapshot._({required this.data, required this.binding});

  /// Reads owned metadata without asserting that its binding is still current.
  static AiHostSnapshot? read({required AiPdfDocument document, required String application}) {
    final PdfValue? value = document.pdf.catalog[_key(application)];
    if (value == null) {
      return null;
    }
    final PdfValue stream = document.pdf.resolve(value);
    if (value is! PdfReference || stream is! PdfStream || stream.dictionary.name('Type') != 'AiKitHostSnapshot' || stream.dictionary.integer('Version') != 1) {
      throw const FormatException('Unsupported host snapshot ownership or version.');
    }
    final PdfValue? digest = stream.dictionary['SHA256'];
    if (digest is! PdfString || digest.bytes.length != 32) {
      throw const FormatException('Missing host snapshot binding.');
    }
    final PdfDocument bounded = PdfDocument(
      objects: document.pdf.objects,
      trailer: document.pdf.trailer,
      version: document.pdf.version,
      limits: const PdfLimits(maxStreamBytes: maximumBytes),
    );
    return AiHostSnapshot(data: bounded.decodeStream(stream), binding: digest.bytes);
  }

  /// Returns canonical binding bytes, including native data and PDF resources.
  static Uint8List bindingBytes({required AiPdfDocument document, required String application}) => const PdfCodec().encode(without(document: document, application: application).pdf);

  /// Removes only this owned snapshot, refusing shared or malformed payloads.
  static AiPdfDocument without({required AiPdfDocument document, required String application}) {
    final String key = _key(application);
    final PdfValue? value = document.pdf.catalog[key];
    if (value == null) {
      return document;
    }
    if (value is! PdfReference) {
      throw const FormatException('Host snapshots require an indirect payload.');
    }
    final PdfValue owned = document.pdf.resolve(value);
    if (owned is! PdfStream || owned.dictionary.name('Type') != 'AiKitHostSnapshot' || owned.dictionary.integer('Version') != 1) {
      throw const FormatException('Unknown host snapshot schema cannot be replaced.');
    }
    final PdfReference root = document.pdf.trailer['Root']! as PdfReference;
    final Map<PdfReference, PdfValue> objects = {...document.pdf.objects};
    objects[root] = document.pdf.catalog.copyWith(remove: {key});
    objects.remove(value);

    /// Checks direct graph edges without following references or cycles.
    void visit(PdfValue item, int depth) {
      if (depth > document.pdf.limits.maxDepth || item == value) {
        throw const FormatException('Shared or excessive host snapshot ownership.');
      }
      if (item is PdfStream) {
        visit(item.dictionary, depth + 1);
      } else if (item is PdfDictionary) {
        for (final PdfValue child in item.values.values) {
          visit(child, depth + 1);
        }
      } else if (item is PdfArray) {
        for (final PdfValue child in item.values) {
          visit(child, depth + 1);
        }
      }
    }

    for (final PdfValue item in objects.values) {
      visit(item, 0);
    }
    visit(document.pdf.trailer, 0);
    return AiPdfDocument(pdf: document.pdf.copyWith(objects: objects));
  }

  /// Attaches compressed host data without changing native or printable artwork.
  AiPdfDocument attach({required AiPdfDocument document, required String application}) {
    final PdfEditor editor = PdfEditor(
      document: without(document: document, application: application).pdf,
    );
    final PdfReference reference = editor.addObject(
      value: PdfStreams.encode(
        bytes: data,
        dictionary: PdfDictionary(
          values: {
            'Type': PdfName(value: 'AiKitHostSnapshot'),
            'Version': PdfNumber(value: 1),
            'SHA256': PdfString(bytes: binding),
          },
        ),
      ),
    );
    editor.setCatalogEntries(values: {_key(application): reference});
    return AiPdfDocument(pdf: editor.document);
  }

  /// Reserves a namespaced catalog key independently of standard PDF features.
  static String _key(String application) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9]{0,63}$').hasMatch(application)) {
      throw ArgumentError.value(application, 'application', 'must be a bounded ASCII application identifier');
    }
    return 'AiKitHost_$application';
  }
}
