#!/usr/bin/env python3
"""Verify ATE style and content edits with the pinned external Illustrator parser."""

import argparse
import copy
import importlib
import io
import itertools
import json
from pathlib import Path
import subprocess
import sys
import uuid

REVISION = "1a5f42a0b0407fc869e032420570682048810108"


def field(value, compact, named):
    """Access a retained field in either authored ATE spelling."""
    if value is None:
        return None
    assert compact == named or not (f"/{compact}" in value and f"/{named}" in value)
    return value.get(f"/{compact}", value.get(f"/{named}"))


def resources(root, compact, named):
    """Read one independent resource table without inventing missing entries."""
    table = field(field(root, "0", "DocumentResources"), compact, named)
    return [field(entry, "0", "Resource") for entry in field(table, "0", "Resources") or []]


def layout(node):
    """Project known cached fields from the independently parsed native tree."""
    tag = field(node, "99", "StreamTag").removeprefix("/")
    segment = tag in ("S", "Segment")
    glyphs = tag in ("G", "GlyphStrike")
    yield {
        "tag": tag,
        "origin": field(field(node, "0", "Transform"), "0", "Origin"),
        "bounds": field(node, "1", "Bounds"),
        "frame": field(node, "10", "Frame") if tag in ("F", "FrameStrike") else None,
        "start": field(node, "20", "FirstCharacterIndexInSegment") if segment else None,
        "characters": field(field(node, "15", "Mapping"), "0", "CharacterCount") if segment else None,
        "glyphs": (field(node, "5", "Glyphs") or []) if glyphs else [],
        "visualBounds": field(node, "8", "VisualBounds") if glyphs else None,
    }
    for child in field(node, "6", "Children") or []:
        yield from layout(child)


def fixture_style_layers(root, model, offset, character):
    """Read the corpus's normal-style plus local-override chains independently."""
    settings = field(field(root, "1", "DocumentObjects"), "0", "DocumentSettings")
    normal = field(settings, "1" if character else "2", "NormalStyleSheet" if character else "NormalParagraphSheet")
    styles = resources(root, "5" if character else "6", "StyleSheetSet" if character else "ParagraphSheetSet")
    assert normal == 0 and len(styles) == 1, "Expand the reference assertions for a fixture with named parent chains"
    feature_key = "6" if character else "5"
    layers = [field(styles[0], feature_key, "Features") or {}]
    table = field(model, "6" if character else "5", "StyleRun" if character else "ParagraphRun")
    end = 0
    for run in field(table, "0", "RunArray") or []:
        end += field(run, "1", "Length")
        if offset < end:
            selected = field(field(run, "0", "RunData"), "0", "StyleSheet" if character else "ParagraphSheet")
            if isinstance(selected, dict):
                assert field(selected, "5" if character else "6", "Parent") in (None, normal)
                layers.append(field(selected, feature_key, "Features") or {})
            else:
                assert selected == normal
            break
    return layers


def last_feature(layers, compact, named):
    """Select one feature without converting omitted native values to defaults."""
    values = [field(layer, compact, named) for layer in layers]
    return next((value for value in reversed(values) if value is not None), None)


def verify_ranges(root, content, decoded, fonts):
    """Compare every resolved range against the pinned corpus's actual features."""
    length = len(decoded["text"].encode("utf-16-le")) // 2
    boundaries = {0, length}
    for lengths in (decoded["characterRuns"], decoded["paragraphRuns"]):
        position = 0
        for count in lengths:
            position += count
            boundaries.add(position)
    boundaries = sorted(boundaries)
    assert [(entry["start"], entry["end"]) for entry in decoded["ranges"]] == list(zip(boundaries, boundaries[1:]))
    for result in decoded["ranges"]:
        paragraphs = fixture_style_layers(root, content, result["start"], False)
        characters = fixture_style_layers(root, content, result["start"], True)
        defaults = [field(layer, "32", "DefaultStyle") for layer in paragraphs]
        layers = characters[:1] + [value for value in defaults if value is not None] + characters[1:]
        font = fonts[last_feature(layers, "0", "Font")]
        assert result["font"] == field(field(font, "0", "Identifier"), "0", "Name")
        for output, compact, named in [
            ("fontSize", "1", "FontSize"), ("horizontalScale", "6", "HorizontalScale"),
            ("verticalScale", "7", "VerticalScale"), ("tracking", "8", "Tracking"),
            ("baselineShift", "9", "BaselineShift"), ("rotation", "10", "CharacterRotation"),
        ]:
            assert result[output] == last_feature(layers, compact, named), (result["start"], output)
        assert result["justification"] == last_feature(paragraphs, "0", "Justification")


def verify_model(root, model, name):
    """Compare fonts, frame geometry, run coverage and every cached glyph node."""
    fonts = resources(root, "1", "FontSet")
    assert model["fonts"] == [{
        "name": field(field(font, "0", "Identifier"), "0", "Name"),
        "version": field(field(font, "0", "Identifier"), "5", "VersionString"),
    } for font in fonts], name
    frames = resources(root, "8", "TextFrameSet")
    assert model["frames"] == [{
        "kind": {0: "point", 1: "area", 2: "path"}.get(field(field(frame, "2", "Data"), "0", "Type") or 0, "unknown"),
        "position": field(frame, "0", "Position"),
        "matrix": field(field(frame, "2", "Data"), "2", "FrameMatrix"),
        "path": field(field(frame, "1", "Bezier"), "0", "Points"),
    } for frame in frames], name
    stories = field(field(root, "1", "DocumentObjects"), "1", "TextObjects") or []
    assert len(stories) == len(model["stories"]), name
    for index, (story, decoded) in enumerate(zip(stories, model["stories"])):
        content = field(story, "0", "Model")
        view = field(story, "1", "View")
        assert decoded["text"] == field(content, "0", "Text"), (name, index)
        assert decoded["frames"] == [field(frame, "0", "Resource") for frame in field(view, "0", "Frames") or []]
        for compact, named, output in [("6", "StyleRun", "characterRuns"), ("5", "ParagraphRun", "paragraphRuns")]:
            table = field(content, compact, named)
            assert decoded[output] == [field(run, "1", "Length") for run in field(table, "0", "RunArray") or []]
        assert decoded["strikes"] == [node for strike in field(view, "2", "Strikes") or [] for node in layout(strike)]
        verify_ranges(root, content, decoded, fonts)
        if name.startswith("simple_") and name not in ("simple_shapes.ai", "simple_shapes_cc.ai"):
            assert decoded["text"] == "Hellow mom\r"
            assert len(decoded["ranges"]) == 1
            resolved = decoded["ranges"][0]
            assert resolved["font"] == "MyriadPro-Regular"
            assert resolved["fontSize"] == 159.1304
            assert (resolved["start"], resolved["end"]) == (0, 11)
    if name == "text_transforms.ai":
        assert len(stories) == 10 and len(frames) == 16
        assert sum(len(story["ranges"]) for story in model["stories"]) == 24
        assert sum(len(story["strikes"]) for story in model["stories"]) == 387
        assert sum(len(node["glyphs"]) for story in model["stories"] for node in story["strikes"]) == 4003
        assert [index for index, story in enumerate(model["stories"]) if not story["characterRuns"]] == [2, 4, 5, 6]


def key(record, compact, named):
    """Retain the authored spelling of one independently decoded field."""
    field(record, compact, named)
    return f"/{compact}" if f"/{compact}" in record else f"/{named}"


def verify_content_edits(before, name, output, text_parser, stream, inkai, binary_type):
    """Rebuild expected run ownership per code unit, independently of Dart spans."""
    original_stories = field(field(before, "1", "DocumentObjects"), "1", "TextObjects") or []
    for index, original in enumerate(original_stories):
        expected = copy.deepcopy(before)
        story = field(field(expected, "1", "DocumentObjects"), "1", "TextObjects")[index]
        model = field(story, "0", "Model")
        old_text = field(model, "0", "Text")
        # The pinned source stories are BMP Latin; the replacement exercises
        # non-BMP UTF-16 lengths and introduces a new paragraph in every story.
        assert all(ord(character) <= 0xFFFF for character in old_text)
        end = min(5, len(old_text) - 1)
        replacement = "Édité 🖋\r"
        inserted = len(replacement.encode("utf-16-le")) // 2
        new_text = replacement + old_text[end:]
        model[key(model, "0", "Text")] = new_text
        for compact, named in [("6", "StyleRun"), ("5", "ParagraphRun"), ("KernRun", "KernRun"),
                               ("AlternateGlyphRun", "AlternateGlyphRun"), ("HyperlinkRun", "HyperlinkRun")]:
            table = field(model, compact, named)
            if table is None:
                continue
            runs = field(table, "0", "RunArray")
            owners = [owner for owner, run in enumerate(runs) for _ in range(field(run, "1", "Length"))]
            assert len(owners) == len(old_text)
            owners = [owners[0]] * inserted + owners[end:]
            if named == "ParagraphRun":
                lengths = [len(paragraph.encode("utf-16-le")) // 2 + 1 for paragraph in new_text[:-1].split("\r")]
                offsets = [0] + list(itertools.accumulate(lengths))[:-1]
                groups = [(owners[offset], count) for offset, count in zip(offsets, lengths)]
            else:
                groups = [(owner, len(list(group))) for owner, group in itertools.groupby(owners)]
            rewritten = []
            for owner, length in groups:
                run = copy.deepcopy(runs[owner])
                run[key(run, "1", "Length")] = length
                rewritten.append(run)
            table[key(table, "0", "RunArray")] = rewritten
        view = field(story, "1", "View")
        for field_name in ("/1", "/RenderedData", "/2", "/Strikes"):
            view.pop(field_name, None)
        payload = (output / f"{name}.story-{index}.edited.ate").read_bytes()
        actual = text_parser.read_object(stream(io.BytesIO(payload)))
        assert actual == expected, f"Unexpected native story edit: {name} / {index}"
        parsed = inkai.parse(str(output / f"{name}.story-{index}.edited.ps"))
        section = parsed.setup.first_subsection_of_type(b"%AI11_BeginTextDocument")
        decoded = next(child.Data for child in section.children if isinstance(child, binary_type))
        assert decoded == payload, f"Edited story ASCII85 mismatch: {name} / {index}"
    return len(original_stories)


def identifiers(value):
    """Collect source identities without interpreting unrelated native fields."""
    if isinstance(value, dict):
        identifier = value.get('/97', value.get('/UUID'))
        if isinstance(identifier, str):
            yield identifier
        for child in value.values():
            yield from identifiers(child)
    elif isinstance(value, list):
        for child in value:
            yield from identifiers(child)


def verify_feature_edits(before, name, output, text_parser, stream, inkai, binary_type):
    """Compare changed properties and per-character ownership against source data."""
    stories = field(field(before, "1", "DocumentObjects"), "1", "TextObjects") or []
    reserved = set(identifiers(before))
    for index, source in enumerate(stories):
        for character, suffix in [(True, "characters"), (False, "paragraphs")]:
            payload = (output / f"{name}.story-{index}.{suffix}.ate").read_bytes()
            actual = text_parser.read_object(stream(io.BytesIO(payload)))
            expected = copy.deepcopy(before)
            story = field(field(expected, "1", "DocumentObjects"), "1", "TextObjects")[index]
            model = field(story, "0", "Model")
            text = field(model, "0", "Text")
            assert all(ord(letter) <= 0xFFFF for letter in text)
            named = '/Text' in model
            def spelling(compact, name):
                return f"/{name if named else compact}"
            compact, table_name = ("6", "StyleRun") if character else ("5", "ParagraphRun")
            selection_name = "StyleSheet" if character else "ParagraphSheet"
            table = field(model, compact, table_name)
            if table is None:
                table = {spelling("0", "RunArray"): [{
                    spelling("0", "RunData"): {spelling("0", selection_name): {}},
                    spelling("1", "Length"): len(text),
                }]}
                model[spelling(compact, table_name)] = table
            runs = field(table, "0", "RunArray")
            owners = [owner for owner, run in enumerate(runs) for _ in range(field(run, "1", "Length"))]
            assert len(owners) == len(text)
            start, end = (1, min(4, len(text))) if character else (text.rfind('\r', 0, 2) + 1, text.index('\r', 2) + 1)
            attributes = [("1", "FontSize", 24), ("89", "RefFontSize", 24), ("8", "Tracking", 35),
                          ("4", "AutoLeading", False), ("5", "Leading", 29), ("18", "Ligatures", False)] if character else [
                ("0", "Justification", 2), ("1", "FirstLineIndent", -4), ("5", "SpaceAfter", 6),
                ("33", "ParagraphDirection", 0), ("35", "ComposerEngine", 1), ("9", "AutoHyphenate", False),
            ]
            actual_story = field(field(actual, "1", "DocumentObjects"), "1", "TextObjects")[index]
            actual_table = field(field(actual_story, "0", "Model"), compact, table_name)
            actual_runs = field(actual_table, "0", "RunArray")
            rewritten = []
            assigned = {}
            labels = [(owner, start <= position < end) for position, owner in enumerate(owners)]
            for output_index, ((owner, selected), positions) in enumerate(itertools.groupby(labels)):
                run = copy.deepcopy(runs[owner])
                run[key(run, "1", "Length")] = len(list(positions))
                if selected:
                    data = field(run, "0", "RunData")
                    selection = field(data, "0", selection_name)
                    if not isinstance(selection, dict):
                        selection = {spelling("5" if character else "6", "Parent"): selection}
                        data[key(data, "0", selection_name)] = selection
                    feature_key = "6" if character else "5"
                    features = field(selection, feature_key, "Features")
                    if features is None:
                        features = {}
                        selection[spelling(feature_key, "Features")] = features
                    for field_key, field_name, value in attributes:
                        destination = key(features, field_key, field_name) if field(features, field_key, field_name) is not None else spelling(field_key, field_name)
                        features[destination] = value
                    if field(selection, "97", "UUID") is not None:
                        actual_selection = field(field(actual_runs[output_index], "0", "RunData"), "0", selection_name)
                        identifier = field(actual_selection, "97", "UUID")
                        assert isinstance(identifier, str) and uuid.UUID(identifier).version == 4 and identifier not in reserved
                        selection[key(selection, "97", "UUID")] = identifier
                        if identifier in assigned:
                            assert assigned[identifier] == selection
                        assigned[identifier] = selection
                rewritten.append(run)
            table[key(table, "0", "RunArray")] = rewritten
            view = field(story, "1", "View")
            for cache in ('/1', '/RenderedData', '/2', '/Strikes'):
                view.pop(cache, None)
            assert actual == expected, f"Unexpected {suffix} edit: {name} / {index}"
            parsed = inkai.parse(str(output / f"{name}.story-{index}.{suffix}.ps"))
            section = parsed.setup.first_subsection_of_type(b"%AI11_BeginTextDocument")
            decoded = next(child.Data for child in section.children if isinstance(child, binary_type))
            assert decoded == payload, f"Formatted story ASCII85 mismatch: {name} / {index}"
    return len(stories) * 2


def main():
    """Require complete parsed equality except for the independently expected edits."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("test/corpus/output/native"))
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "-C", str(args.reference), "rev-parse", "HEAD"], text=True).strip()
    if revision != REVISION:
        raise RuntimeError(f"Unexpected reference revision: {revision}")
    if subprocess.check_output(["git", "-C", str(args.reference), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise RuntimeError("The reference checkout contains modified tracked files")
    sys.path.insert(0, str(args.reference.resolve()))
    inkai = importlib.import_module("inkai")
    text_parser = importlib.import_module("inkai.parser.text").TextDocumentParser
    stream = importlib.import_module("inkai.parser.streamreader").StreamWrapper
    binary_type = importlib.import_module("inkai.parser.consts").AI11TextDocument
    results = []
    entries = json.loads((args.output / "report.json").read_text())
    for entry in entries:
        if not entry.get("textDocuments"):
            continue
        name = entry["file"]
        original = (args.output / f"{name}.ate").read_bytes()
        renamed = (args.output / f"{name}.renamed.ate").read_bytes()
        before = text_parser.read_object(stream(io.BytesIO(original)))
        after = text_parser.read_object(stream(io.BytesIO(renamed)))
        expected = copy.deepcopy(before)
        styles = resources(expected, "5", "StyleSheetSet")
        if styles:
            styles[0]["/0" if "/0" in styles[0] else "/Name"] = "AiKit corpus style 🖋"
        assert after == expected, f"ATE data other than the style name changed: {name}"
        parsed = inkai.parse(str(args.output / f"{name}.text-renamed.ps"))
        section = parsed.setup.first_subsection_of_type(b"%AI11_BeginTextDocument")
        payload = next(child.Data for child in section.children if isinstance(child, binary_type))
        assert payload == renamed, f"The independent ASCII85 decoding differs: {name}"
        stories = field(field(after, "1", "DocumentObjects"), "1", "TextObjects") or []
        assert len(stories) == entry["textStories"]
        verify_model(before, json.loads((args.output / f"{name}.text-model.json").read_text()), name)
        if name == "flowtext.ai":
            assert len(stories) == 1
            model = stories[0]["/0"]
            assert model["/0"] == "Lorem ipsum dolor sit amet, consectetuer adipiscing elit, sed diam nonummy \r"
            for key in ("/5", "/6"):
                assert sum(run["/1"] for run in model[key]["/0"]) == 76
        edits = verify_content_edits(before, name, args.output, text_parser, stream, inkai, binary_type)
        feature_edits = verify_feature_edits(before, name, args.output, text_parser, stream, inkai, binary_type)
        results.append({"file": name, "stories": len(stories), "renamedStyle": bool(styles), "contentEdits": edits, "featureEdits": feature_edits, "status": "passed"})
    assert len(results) == 32, "The required text-document corpus was not fully exercised"
    content_edits = sum(result["contentEdits"] for result in results)
    assert content_edits == 20, "The required native stories were not all edited"
    feature_edits = sum(result["featureEdits"] for result in results)
    assert feature_edits == 40, "The required native stories were not all formatted"
    report = {"referenceRevision": revision, "python": sys.version.split()[0], "fixtures": results}
    (args.output / "native-text-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Native text: {len(results)} style rewrites, {content_edits} content edits and {feature_edits} feature edits independently passed")


if __name__ == "__main__":
    main()
