# Contributing to AiKit

Bug reports, focused fixes, documentation improvements, and well-scoped features are welcome.

## Before you start

- Search existing issues before opening a new one.
- Include a minimal reproduction, the Dart SDK version, and the Illustrator version and PDF-compatibility setting involved.
- Share sample files only when their license and contents permit it. Do not include secrets, private artwork, or personal data in a public report.

## Development setup

Use a Dart SDK compatible with [`pubspec.yaml`](pubspec.yaml). Clone
[PdfCore](https://github.com/focale-editor/pdfcore) into a sibling `PdfCore`
directory. From the AiKit checkout:

```sh
cp pubspec_overrides.yaml.example pubspec_overrides.yaml
dart pub get
```

Follow [`AGENTS.md`](AGENTS.md) and keep each change focused on one fix or feature.

## Making changes

- Keep format models independent of Flutter, native libraries, and Focale. Native authoring records belong in AiKit; rendering and synchronization with the host's scene belong to the application adapter.
- Document public and private APIs, preserve caller-owned values, and add regression tests for parser, editing or writer changes.
- Base compatibility changes on specifications and real files. Preserve opaque data when safe; reject transformations that would silently lose unsupported content.
- Update the [technical reference](docs/AI.md), examples, and README when support or public behavior changes.

Keep legacy PostScript byte preservation separate from PDF interchange edits. Never execute PostScript. Preserve private blocks when the graph is coherent, and remove stale native authoring links for explicit PDF interchange. QPDF/Poppler checks do not establish native Illustrator reopening or editability.

External corpora stay outside the published package and Git history. Pin source revisions, sizes, SHA-256 values, and provenance in the manifest. Do not assume that a repository's code license covers every embedded artwork.

## Quality checks

Before opening a pull request, run:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart test --platform node
```

Add the relevant [corpus checks](test/corpus/README.md) for format changes. A decode/write/read test alone is not independent interoperability evidence. State the external tool versions and untested features. Ordinary unit tests run offline; corpus downloading is explicit.

The package illustration is maintained as `screenshots/overview.svg`. After changing it, regenerate the README and pub.dev PNG with librsvg:

```sh
rsvg-convert screenshots/overview.svg -o screenshots/overview.png
```

The package follows the sibling kits' `docs/` layout, which Pub's dry-run
validator reports as a naming warning.
AiKit uses an ignored local PdfCore override during development; resolve that
dependency release before publishing AiKit. ZCodec is resolved from pub.dev.

## Pull requests

Explain the problem and solution, link a related issue when applicable, and describe the checks and platforms exercised. Call out compatibility, performance, licensing, or migration implications. If a check cannot run in your environment, explain why.

Use Conventional Commits for commit messages and pull request titles, such as `fix:`, `feat:`, `docs:`, `test:`, or `refactor:`. Keep review follow-up changes on the same branch. Routine validation does not include package publication or a release-version change.
