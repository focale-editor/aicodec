<p align="center">
  <img src="screenshots/overview.png" alt="AiKit package illustration" width="180">
</p>

# AiKit

AiKit reads and writes Adobe Illustrator containers in pure Dart. PdfCore handles
the PDF representation; ZCodec opens compressed native authoring programs and
PsCore supplies the Adobe text-engine grammar shared with PsdKit.
Source-backed edits preserve unknown records, and typed artwork can be written
as self-contained AI7 PostScript.

## Supported data

- Signature-based detection of PDF and PostScript AI families.
- PDF pages, graphics streams, resources and metadata through PdfCore.
- Native Illustrator private-data blocks collected across pages in numeric order.
- Plain, zlib and Zstandard native programs, including recent CC files without
  usable PDF preview artwork.
- Native nested layers, names, visibility, locking and printing flags.
- Native hierarchical records, typed artboards and bounded ASCII85 resources.
- Source-preserving numeric/string record edits, including artboard renaming.
- Native ATE stories, UTF-16 style runs, fonts, styles, frames and drawing
  references; source-preserving style renaming and bounded binary replacement.
- Named CS and compact CC text dictionaries, inherited character/paragraph
  styles, OpenType switches and retained glyph-layout trees.
- Source-preserving layer edits and plain-path geometry replacement.
- CC live-shape associations and atomic translation of native outlines,
  solid/gradient appearances and parameters, including expanded strokes,
  shared style resources and versioned metadata.
- AI7 creation with editable layers, groups, Bézier paths, process colors,
  fills, strokes, dashes and winding rules.
- Exact preservation of legacy source bytes, binary blocks and DOS EPS previews.
- DSC titles, creators, bounding boxes, continuation lines and trailer metadata.
- PostScript numbers, names, strings, arrays, dictionaries, procedures and comments.
- Explicit PDF-interchange export that removes stale Illustrator authoring links.

## Installation

Use the sibling checkouts while these native APIs are under development:

```yaml
dependencies:
  aikit:
    path: ../FocalePackages/AiKit
```

Adjust the paths to your Dart or Flutter project. Zstandard uses hosted
ZCodec 0.2.6; text-engine parsing uses hosted PsCore 0.2.2. Until its first
pub.dev release, PdfCore resolves from the pinned Git revision in `pubspec.yaml`.
To work on a sibling PdfCore checkout while developing AiKit, copy
[`pubspec_overrides.yaml.example`](pubspec_overrides.yaml.example) to the ignored
`pubspec_overrides.yaml`. Otherwise, `dart pub get` needs no local override.

## Quick start

```dart
import 'dart:convert';
import 'package:aikit/aikit.dart';

final AiDocument document = const AiCodec().decode(latin1.encode(
  '%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n'
  '%%BoundingBox: 0 0 100 80\n%%EndComments\n0 0 m 100 80 l S\n%%EOF\n',
));
if (document is AiPostScriptDocument) {
  final List<AiToken> tokens = AiPostScript.tokenize(document.postScriptBytes);
  print('${document.creator}: ${tokens.length} tokens');
}
final AiNativeSource native = AiNativeData.extract(document).single;
final AiProgram program = AiProgram.decode(bytes: native.bytes);
print('${program.layers.length} native layers; ${program.paths.length} paths');
final List<int> preserved = const AiCodec().encode(document);
```

`AiCodec` implements `Codec<AiDocument, List<int>>`, with `AiDecoder` and
`AiEncoder` converters. Direct encoding returns `Uint8List`. See the runnable
[example](example/aikit_example.dart) for native artwork creation, layer editing
and explicit PDF interchange.

Native text is available independently of the PDF appearance:

```dart
final AiNativeRecords records = AiNativeRecords.decode(program: program);
final AiNativeTextDocument text = AiNativeTextDocument.decode(records: records);
for (final AiNativeTextStory story in text.stories) {
  for (final AiNativeStyledTextRange range in text.styledRanges(story: story)) {
    print('${range.start}–${range.end}: ${range.characterStyle.font?.postScriptName}');
  }
}
```

Select a container explicitly when several `AI11TextDocument` records exist.
Named CS and compact CC fields retain their original syntax; omitted character
runs inherit the document's normal style. Saved glyph layouts remain accessible
through `story.strikes` and are not treated as regenerated text.

`replaceText(story:, start:, end:, text:)` edits UTF-16 content and its style
coverage, splitting paragraphs and removing stale layout caches. The caller
must recompose the changed story and regenerate the PDF appearance before
saving a synchronized document. This API does not provide a shaping engine.
`setCharacterFeatures` and `setParagraphFeatures` update local typography with
typed change objects, preserve inherited styles and support returning individual
features to inheritance. Their changed stories also require recomposition.
Native paragraph spans retain both CR and U+0003 boundaries; paragraph feature
selections still cover the whole logical paragraph across forced line breaks.
`addFont` registers a host-supplied PostScript identity, technology, version and
optional variation coordinates without changing existing font indices. Assign
the returned snapshot's `fonts.last` with `setCharacterFeatures`; matching font
programs and their embedding remain host responsibilities.
`withTextLayout` writes point/area frame, line and segment positions supplied by
the host, including explicit overflow and compact automatic-hyphen maps. It
validates UTF-16 coverage and resource ownership; it does not generate glyph
shapes or synchronize the PDF appearance.
`translateFrames` moves point, area and path text while keeping local composition
intact. It updates the frame matrices and every corresponding native confinement
path together, including selected frames within linked text. PDF appearances and
effects still require host regeneration before saving a synchronized document.

`AiNativeGradientResources` reads global gradient definitions, native and fallback
color stops, opacity, named colors and sampled printing ramps. `replaceStops`
updates every same-name definition and its compatibility records atomically,
using explicit host-composed ramp intervals. Instance geometry stays intact;
color management, flattened effects and PDF synchronization remain host work.

## Scope

AI is not one uniform format. A PDF page can be a compatibility warning rather
than the artwork; `AiNativeData.extract` accesses the native program separately.
`AiProgram` interprets a structural subset and reports unhandled operators and
private extensions. It does not execute arbitrary PostScript or provide a renderer.

ATE text resources, stories and runs are modeled, while glyph shaping, layout
regeneration and synchronized text-content editing remain unfinished. Plug-ins,
effects, meshes, gradient and raster authoring semantics are preserved but not
fully modeled. Live rectangles, ellipses,
polygons, stars and lines support translation with solid and linear/radial
gradient appearances; resizing,
rotation and parameter-driven regeneration remain unfinished. Geometry edits
with unresolved private appearance dependencies are rejected. AI7 creation is an
explicit legacy target, not a reconstruction of CC editing records. Native and
PDF appearances must be synchronized by the caller when saving visual edits.
No Adobe Illustrator reopening validation has been performed.

See [docs/AI.md](docs/AI.md) for editing policies and
[test/corpus/README.md](test/corpus/README.md) for the external corpus. AiKit is an
independent implementation and is not affiliated with or endorsed by Adobe.

## More documentation

- [Illustrator container reference](docs/AI.md)
- [Inspection and PDF interchange example](example/aikit_example.dart)
- [External corpus and validation scope](test/corpus/README.md)
- [Contributing](CONTRIBUTING.md)

## Development

```sh
cp pubspec_overrides.yaml.example pubspec_overrides.yaml
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart test --platform node
```

The optional corpus checks extraction, layer renaming and native recompression
on 37 pinned files. Independent zlib/Zstandard decoding checks the resulting
bytes. Eight fixtures also check live-shape translations against a pinned
independent reader and renderer. These checks do not establish complete native
Illustrator compatibility.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
