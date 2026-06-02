#!/usr/bin/env python3
"""Create prototype centerline candidates from route source files."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from xml.etree import ElementTree as ET

try:
    from pyproj import Transformer
except ImportError:  # pragma: no cover - dependency guard
    Transformer = None


KML_NS = {"k": "http://www.opengis.net/kml/2.2"}
DEFAULT_EPSG = 2264
DEFAULT_MAX_SEGMENT_FT = 500.0


@dataclass(frozen=True)
class RoutePart:
    name: str
    coords: list[tuple[float, float]]
    source: str


@dataclass(frozen=True)
class Segment:
    segment_id: str
    route_name: str
    coords: list[tuple[float, float]]
    length_ft: float
    confidence: str
    confidence_score: float
    reasons: list[str]
    source: str


def parse_pair(text: str) -> tuple[float, float] | None:
    parts = [p.strip() for p in text.replace("\t", ",").split(",")]
    if len(parts) < 2:
        return None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None


def load_kml_or_kmz(path: Path) -> list[RoutePart]:
    if path.suffix.lower() == ".kmz":
        with zipfile.ZipFile(path) as zf:
            kml_names = [n for n in zf.namelist() if n.lower().endswith(".kml")]
            if not kml_names:
                return []
            xml_bytes = zf.read("doc.kml" if "doc.kml" in kml_names else kml_names[0])
    else:
        xml_bytes = path.read_bytes()

    root = ET.fromstring(xml_bytes)
    parts: list[RoutePart] = []
    for index, placemark in enumerate(root.findall(".//k:Placemark", KML_NS), 1):
        name_node = placemark.find("k:name", KML_NS)
        name = name_node.text.strip() if name_node is not None and name_node.text else f"kml_{index}"
        for node in placemark.findall(".//k:LineString/k:coordinates", KML_NS):
            coords = []
            for token in (node.text or "").replace("\n", " ").split():
                pair = parse_pair(token)
                if pair:
                    coords.append(pair)
            if len(coords) >= 2:
                parts.append(RoutePart(name=name, coords=coords, source=path.name))
    return parts


def load_geojson(path: Path) -> list[RoutePart]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    features = data.get("features", [data])
    parts: list[RoutePart] = []
    for index, feature in enumerate(features, 1):
        geom = feature.get("geometry", feature)
        props = feature.get("properties", {}) or {}
        name = str(props.get("name") or props.get("Name") or f"geojson_{index}")
        if not geom:
            continue
        gtype = geom.get("type")
        coords = geom.get("coordinates") or []
        if gtype == "LineString":
            line = [(float(x), float(y)) for x, y, *_ in coords]
            if len(line) >= 2:
                parts.append(RoutePart(name=name, coords=line, source=path.name))
        elif gtype == "MultiLineString":
            for sub_index, subline in enumerate(coords, 1):
                line = [(float(x), float(y)) for x, y, *_ in subline]
                if len(line) >= 2:
                    parts.append(RoutePart(name=f"{name}_{sub_index}", coords=line, source=path.name))
    return parts


def load_csv(path: Path) -> list[RoutePart]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        sample = f.read(4096)
        f.seek(0)
        dialect = csv.Sniffer().sniff(sample, delimiters=",\t;|")
        reader = csv.DictReader(f, dialect=dialect)
        if not reader.fieldnames:
            return []
        names = {name.lower().strip(): name for name in reader.fieldnames}
        x_name = names.get("x") or names.get("lon") or names.get("longitude") or names.get("easting")
        y_name = names.get("y") or names.get("lat") or names.get("latitude") or names.get("northing")
        route_name = names.get("route") or names.get("name") or names.get("folder")
        order_name = names.get("order") or names.get("station") or names.get("seq")
        if not x_name or not y_name:
            return []

        grouped: dict[str, list[tuple[float, float, float]]] = {}
        for index, row in enumerate(reader):
            try:
                x = float(row[x_name])
                y = float(row[y_name])
                order = float(row[order_name]) if order_name else float(index)
            except (TypeError, ValueError):
                continue
            key = (row.get(route_name, "") if route_name else "") or "csv_route"
            grouped.setdefault(key, []).append((order, x, y))

    parts = []
    for name, rows in grouped.items():
        coords = [(x, y) for _, x, y in sorted(rows)]
        if len(coords) >= 2:
            parts.append(RoutePart(name=name, coords=coords, source=path.name))
    return parts


def load_txt(path: Path) -> list[RoutePart]:
    parts: list[RoutePart] = []
    coords: list[tuple[float, float]] = []
    with path.open("r", encoding="utf-8-sig", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            pair = parse_pair(line)
            if pair:
                coords.append(pair)
    if len(coords) >= 2:
        parts.append(RoutePart(name=path.stem, coords=coords, source=path.name))
    return parts


def load_route(path: Path) -> list[RoutePart]:
    suffix = path.suffix.lower()
    if suffix in {".kml", ".kmz"}:
        return load_kml_or_kmz(path)
    if suffix in {".geojson", ".json"}:
        return load_geojson(path)
    if suffix == ".csv":
        return load_csv(path)
    if suffix in {".txt", ".tsv"}:
        return load_txt(path)
    raise ValueError(f"Unsupported input type: {path.suffix}")


def looks_like_lonlat(parts: Iterable[RoutePart]) -> bool:
    for part in parts:
        for x, y in part.coords[:20]:
            if abs(x) > 180 or abs(y) > 90:
                return False
    return True


def project_if_needed(parts: list[RoutePart], epsg: int) -> list[RoutePart]:
    if not parts or not looks_like_lonlat(parts):
        return parts
    if Transformer is None:
        raise SystemExit("pyproj is required to project lon/lat sources. Install with: python -m pip install pyproj")

    transformer = Transformer.from_crs("EPSG:4326", f"EPSG:{epsg}", always_xy=True)
    projected = []
    for part in parts:
        coords = [transformer.transform(x, y) for x, y in part.coords]
        projected.append(RoutePart(name=part.name, coords=coords, source=part.source))
    return projected


def distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(b[0] - a[0], b[1] - a[1])


def line_length(coords: list[tuple[float, float]]) -> float:
    return sum(distance(a, b) for a, b in zip(coords, coords[1:]))


def interpolate(a: tuple[float, float], b: tuple[float, float], t: float) -> tuple[float, float]:
    return a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t


def split_route(part: RoutePart, max_segment_ft: float, start_index: int) -> tuple[list[Segment], int]:
    segments: list[Segment] = []
    current = [part.coords[0]]
    current_len = 0.0
    index = start_index

    for a, b in zip(part.coords, part.coords[1:]):
        remaining_start = a
        edge_len = distance(a, b)
        if edge_len == 0:
            continue
        consumed = 0.0
        while consumed < edge_len:
            available = max_segment_ft - current_len
            step = min(available, edge_len - consumed)
            consumed += step
            t = consumed / edge_len
            point = interpolate(a, b, t)
            current.append(point)
            current_len += step

            if current_len >= max_segment_ft - 1e-6:
                segments.append(make_segment(index, part, current))
                index += 1
                current = [point]
                current_len = 0.0
            remaining_start = point

    if len(current) >= 2 and line_length(current) > 1.0:
        segments.append(make_segment(index, part, current))
        index += 1
    return segments, index


def make_segment(index: int, part: RoutePart, coords: list[tuple[float, float]]) -> Segment:
    length = line_length(coords)
    reasons = ["single-source prototype candidate"]
    confidence = "MED"
    score = 0.65
    if length < 25.0:
        confidence = "LOW"
        score = 0.35
        reasons.append("short segment")
    elif length > DEFAULT_MAX_SEGMENT_FT * 0.95:
        reasons.append("auto-split long route")

    return Segment(
        segment_id=f"CL-{index:04d}",
        route_name=part.name,
        coords=coords,
        length_ft=round(length, 2),
        confidence=confidence,
        confidence_score=score,
        reasons=reasons,
        source=part.source,
    )


def layer_for(segment: Segment) -> str:
    return {
        "HIGH": "BS-CL-CANDIDATE-HIGH",
        "MED": "BS-CL-CANDIDATE-MED",
        "LOW": "BS-CL-CANDIDATE-LOW",
    }[segment.confidence]


def acad_point(point: tuple[float, float]) -> str:
    return f"{point[0]:.3f},{point[1]:.3f}"


def write_scr(path: Path, segments: list[Segment]) -> None:
    lines = [
        "_.-LAYER",
        "_M",
        "BS-CL-CANDIDATE-HIGH",
        "_C",
        "3",
        "BS-CL-CANDIDATE-HIGH",
        "_M",
        "BS-CL-CANDIDATE-MED",
        "_C",
        "2",
        "BS-CL-CANDIDATE-MED",
        "_M",
        "BS-CL-CANDIDATE-LOW",
        "_C",
        "1",
        "BS-CL-CANDIDATE-LOW",
        "_M",
        "BS-CL-APPROVED",
        "_C",
        "4",
        "BS-CL-APPROVED",
        "_M",
        "BS-CL-REVIEW",
        "_C",
        "30",
        "BS-CL-REVIEW",
        "",
    ]
    for segment in segments:
        lines.extend(["_.-LAYER", "_S", layer_for(segment), ""])
        lines.append("_.PLINE")
        lines.extend(acad_point(pt) for pt in segment.coords)
        lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def segment_to_json(segment: Segment) -> dict[str, Any]:
    xs = [p[0] for p in segment.coords]
    ys = [p[1] for p in segment.coords]
    return {
        "segment_id": segment.segment_id,
        "route_name": segment.route_name,
        "status": "CANDIDATE",
        "layer": layer_for(segment),
        "length_ft": segment.length_ft,
        "bbox": {"min_x": min(xs), "min_y": min(ys), "max_x": max(xs), "max_y": max(ys)},
        "confidence": {
            "level": segment.confidence,
            "score": segment.confidence_score,
            "reasons": segment.reasons,
        },
        "source": segment.source,
        "coords": [{"x": round(x, 3), "y": round(y, 3)} for x, y in segment.coords],
    }


def write_manifest(path: Path, source: Path, segments: list[Segment], epsg: int) -> None:
    manifest = {
        "schema_version": "centerline-prototype-0.1",
        "source_file": str(source),
        "target_epsg": epsg,
        "status": "CANDIDATE",
        "prototype_layers": {
            "candidate_high": "BS-CL-CANDIDATE-HIGH",
            "candidate_medium": "BS-CL-CANDIDATE-MED",
            "candidate_low": "BS-CL-CANDIDATE-LOW",
            "approved": "BS-CL-APPROVED",
            "review": "BS-CL-REVIEW",
            "final": "ROAD-CENTERLINE",
        },
        "segments": [segment_to_json(segment) for segment in segments],
    }
    path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def build_segments(parts: list[RoutePart], max_segment_ft: float) -> list[Segment]:
    segments: list[Segment] = []
    next_index = 1
    for part in parts:
        new_segments, next_index = split_route(part, max_segment_ft, next_index)
        segments.extend(new_segments)
    return segments


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_file", type=Path)
    parser.add_argument("--out-dir", type=Path, default=Path("."))
    parser.add_argument("--target-epsg", type=int, default=DEFAULT_EPSG)
    parser.add_argument("--max-segment-ft", type=float, default=DEFAULT_MAX_SEGMENT_FT)
    args = parser.parse_args(argv)

    if args.max_segment_ft < 25:
        raise SystemExit("--max-segment-ft must be at least 25")

    parts = load_route(args.input_file)
    if not parts:
        raise SystemExit(f"No route lines found in {args.input_file}")

    parts = project_if_needed(parts, args.target_epsg)
    segments = build_segments(parts, args.max_segment_ft)
    if not segments:
        raise SystemExit("No centerline candidate segments generated")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = args.out_dir / "centerline_segments.json"
    script_path = args.out_dir / "centerline_candidate.scr"
    write_manifest(manifest_path, args.input_file, segments, args.target_epsg)
    write_scr(script_path, segments)

    print(f"Wrote {manifest_path}")
    print(f"Wrote {script_path}")
    print(f"Segments: {len(segments)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
