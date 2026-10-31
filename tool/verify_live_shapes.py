#!/usr/bin/env python3
"""Check native translations with a pinned independent Illustrator reader."""

import argparse
import importlib
import importlib.metadata
import json
import math
import re
from pathlib import Path
import subprocess
import sys

REVISION = "1a5f42a0b0407fc869e032420570682048810108"
# Name: all paths, private paths, live shapes, SVG units per source point.
FIXTURES = {
    "cmyk_rectangle.ai": (1, 0, 1, 25.4 / 72),
    "rgb_rectangle.ai": (1, 0, 1, 25.4 / 72),
    "circle.ai": (1, 0, 1, 25.4 / 72),
    "simple_shapes.ai": (19, 5, 5, 1),
    "simple_shapes_cc.ai": (19, 5, 5, 1),
    "opacity.ai": (5, 1, 2, 1),
    "gradient_linear.ai": (30, 15, 15, 1),
    "gradient_radial.ai": (36, 9, 9, 1),
}
GEOMETRY = {"m", "l", "L", "c", "C", "v", "V", "y", "Y"}


def walk_body(items):
    """Traverse the reference reader's parsed body, excluding setup resources."""
    for item in items:
        if hasattr(item, "children"):
            yield from walk_body(item.children)
        else:
            yield item


def check_records(before, after):
    """Require translated canvas centers and exact preservation of other fields."""
    if isinstance(before, dict):
        assert isinstance(after, dict) and before.keys() == after.keys()
        count = 0
        for key, value in before.items():
            if key.endswith("::CenterX") or key.endswith("::CenterY"):
                offset = 37 if key.endswith("::CenterX") else 19
                assert math.isclose(float(after[key]), float(value) + offset, abs_tol=1e-9, rel_tol=0), key
                count += 1
            else:
                count += check_records(value, after[key])
        return count
    if isinstance(before, list):
        assert isinstance(after, list) and len(before) == len(after)
        return sum(check_records(first, second) for first, second in zip(before, after))
    assert before == after, (before, after)
    return 0


def verify_native(inkai, original, translated, counts):
    """Check both private outlines and printable expansions through inkai.parse."""
    before = list(walk_body(inkai.parse(str(original)).trailer))
    after = list(walk_body(inkai.parse(str(translated)).trailer))
    assert len(before) == len(after), "Reference parser found changed body topology"
    path_index = -1
    private_paths = 0
    center_fields = 0
    for first, second in zip(before, after):
        command = getattr(first, "command", None)
        assert command == getattr(second, "command", None)
        if command is None:
            center_fields += check_records(first, second)
            continue
        assert first.is_pseudo_comment == second.is_pseudo_comment
        if command == "m":
            path_index += 1
            private_paths += first.is_pseudo_comment
        if command in GEOMETRY:
            # The two simple-shape fixtures also contain one ordinary final path.
            moving = not (counts[0] == 19 and path_index == 18)
            assert len(first.tokens) == len(second.tokens)
            for index, (a, b) in enumerate(zip(first.tokens, second.tokens)):
                offset = (37 if index % 2 == 0 else -19) if moving else 0
                assert math.isclose(float(b), float(a) + offset, abs_tol=1e-9, rel_tol=0), (command, a, b)
        elif command in {"Xm", "Bm", "Bc"}:
            assert len(first.tokens) == len(second.tokens) == 6
            for index, (a, b) in enumerate(zip(first.tokens, second.tokens)):
                offset = 37 if index == 4 else -19 if index == 5 else 0
                assert math.isclose(float(b), float(a) + offset, abs_tol=1e-9, rel_tol=0), (command, a, b)
        else:
            assert first.tokens == second.tokens, command
    assert path_index + 1 == counts[0]
    assert private_paths == counts[1]
    # Each private outline has a redundant appearance dictionary as well.
    assert center_fields == 2 * (counts[2] + counts[1]), center_fields
    return center_fields


def verify_render(inkai, original, translated, counts, output):
    """Render the reference SVG and compare with an explicitly shifted original."""
    from lxml import etree
    from PIL import Image, ImageChops, ImageStat
    from inkex import Transform

    before = etree.fromstring(inkai.to_svg(str(original)))
    after = etree.fromstring(inkai.to_svg(str(translated)))
    tags = {"path", "rect", "ellipse", "circle", "line", "polygon"}
    original_shapes = [node for node in before.iter() if etree.QName(node).localname in tags]
    changed_shapes = [node for node in after.iter() if etree.QName(node).localname in tags]
    extra = 1 if counts[0] == 19 else 0
    assert len(original_shapes) == len(changed_shapes) == counts[2] + extra
    for index, (first, second) in enumerate(zip(original_shapes, changed_shapes)):
        assert first.tag == second.tag
        # The oracle allocates fresh SVG IDs on each conversion. Check resource
        # effects through rendering rather than comparing those arbitrary IDs.
        assert re.sub(r"url\(#[^)]+\)", "url(#resource)", first.get("style", "")) == re.sub(r"url\(#[^)]+\)", "url(#resource)", second.get("style", "")), "Native appearance changed"
        for attribute in ("width", "height", "rx", "ry", "r"):
            assert first.get(attribute) == second.get(attribute), attribute
        resources_before = re.findall(r"url\(#([^)]+)\)", first.get("style", ""))
        resources_after = re.findall(r"url\(#([^)]+)\)", second.get("style", ""))
        assert len(resources_before) == len(resources_after)
        for source_id, changed_id in zip(resources_before, resources_after):
            source_paint = before.xpath("//*[@id=$id]", id=source_id)[0]
            changed_paint = after.xpath("//*[@id=$id]", id=changed_id)[0]
            assert source_paint.tag == changed_paint.tag
            assert source_paint.get("gradientUnits") == changed_paint.get("gradientUnits") == "userSpaceOnUse"
            assert [dict(stop.attrib) for stop in source_paint] == [dict(stop.attrib) for stop in changed_paint]
            transform_before = Transform(source_paint.get("gradientTransform", ""))
            transform_after = Transform(changed_paint.get("gradientTransform", ""))
            if etree.QName(source_paint).localname == "radialGradient":
                assert source_paint.get("r") == changed_paint.get("r")
                assert source_paint.get("gradientTransform") == changed_paint.get("gradientTransform")
                pairs = [("cx", "cy"), ("fx", "fy")]
            else:
                pairs = [("x1", "y1"), ("x2", "y2")]
            for x, y in pairs:
                p = transform_before.apply_to_point((float(source_paint.get(x)), float(source_paint.get(y))))
                q = transform_after.apply_to_point((float(changed_paint.get(x)), float(changed_paint.get(y))))
                # The independent reader rounds serialized SVG matrices.
                assert math.isclose(q.x - p.x, 37 * counts[3], abs_tol=0.001, rel_tol=0)
                assert math.isclose(q.y - p.y, 19 * counts[3], abs_tol=0.001, rel_tol=0)
        if index < counts[2]:
            shift = f"translate({37 * counts[3]},{19 * counts[3]})"
            first.set("transform", shift + " " + first.get("transform", ""))
    images = []
    for variant, tree in [("expected", before), ("actual", after)]:
        svg = output / f"{original.name}.{variant}.svg"
        png = output / f"{original.name}.{variant}.png"
        svg.write_bytes(etree.tostring(tree))
        subprocess.run(["inkscape", str(svg), "--export-type=png", "--export-width=1200", f"--export-filename={png}"], check=True)
        with Image.open(png) as image:
            images.append(image.convert("RGBA"))
    assert images[0].size == images[1].size
    difference = ImageChops.difference(*images)
    mean = max(ImageStat.Stat(difference).mean)
    # Upstream SVG path strings round coordinates to six significant digits.
    # This allows subpixel edge rounding, not a missing path or stale position.
    assert mean < 0.05, f"Rendered translation differs by {mean} mean channel levels"
    difference.save(output / f"{original.name}.difference.png")
    return mean


def main():
    """Require the pinned oracle, every output, and both geometry/render checks."""
    if not __debug__:
        raise RuntimeError("Run validation without Python's -O assertion stripping")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inkai-source", required=True, type=Path)
    parser.add_argument("--native-output", default=Path("test/corpus/output/native"), type=Path)
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "-C", str(args.inkai_source), "rev-parse", "HEAD"], text=True).strip()
    if revision != REVISION:
        parser.error(f"The independent reader must be pinned to {REVISION}")
    if subprocess.check_output(["git", "-C", str(args.inkai_source), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        parser.error("The independent reader contains modified tracked source")
    sys.path.insert(0, str(args.inkai_source.resolve()))
    inkai = importlib.import_module("inkai")
    output = args.native_output / "live-shape-oracle"
    output.mkdir(parents=True, exist_ok=True)
    report = []
    for name, counts in FIXTURES.items():
        original = args.native_output / f"{name}.native.ps"
        translated = args.native_output / f"{name}.translated.ps"
        if not original.is_file() or not translated.is_file():
            raise FileNotFoundError(f"Missing required native inputs for {name}")
        fields = verify_native(inkai, original, translated, counts)
        mean = verify_render(inkai, original, translated, counts, output)
        report.append({"file": name, "status": "passed", "paths": counts[0], "liveShapes": counts[2], "centerFields": fields, "renderMeanChannelDifference": mean})
        print(f"{name}: independent geometry and rendering passed")
    runtime = {name: importlib.metadata.version(name) for name in ("inkex", "Pillow", "lxml", "pypdf", "zstandard")}
    runtime["inkscape"] = subprocess.check_output(["inkscape", "--version"], text=True).strip()
    (output / "report.json").write_text(json.dumps({"oracleRevision": revision, "runtime": runtime, "files": report}, indent=2) + "\n")
    print(f"Live shapes: {len(report)}/{len(FIXTURES)} independent checks passed")


if __name__ == "__main__":
    main()
