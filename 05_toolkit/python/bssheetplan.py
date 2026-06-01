#!/usr/bin/env python3
"""Plan Brightspeed sheet rectangles along BSKMZ-exported route lines."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
import zipfile
from dataclasses import dataclass
from collections import OrderedDict
from pathlib import Path
from typing import Any, Iterable
from xml.etree import ElementTree as ET

try:
    from pyproj import Transformer
except ImportError as exc:  # pragma: no cover - dependency guard
    raise SystemExit(
        "Missing dependency: pyproj. Install with: python -m pip install pyproj shapely"
    ) from exc

try:
    from shapely.geometry import LineString, Point, Polygon, shape
    from shapely.ops import linemerge
except ImportError as exc:  # pragma: no cover - dependency guard
    raise SystemExit(
        "Missing dependency: shapely. Install with: python -m pip install pyproj shapely"
    ) from exc


DEFAULT_CONFIG_PATH = Path(__file__).resolve().parents[1] / "config" / "bssheet_config.json"

DEFAULT_CONFIG = {
    "sheet_width_ft": 900.0,
    "sheet_height_ft": 600.0,
    "overlap_ft": 0.0,
    "side_margin_ft": 75.0,
    "road_buffer_left_ft": 150.0,
    "road_buffer_right_ft": 150.0,
    "required_edge_clearance_ft": 20.0,
    "endpoint_inset_ratio": 0.6667,
    "fixed_sheet_angle_deg": 0.0,
    "target_epsg": 2264,
    "border_layer": "BORDER",
    "proposed_layer": "BS-SHEET-PROPOSED",
    "label_layer": "BS-SHEET-LABELS",
    "hidden_layer": "BS-SHEET-HIDDEN",
    "sample_interval_ft": 25.0,
    "label_height_ft": 60.0,
}


@dataclass(frozen=True)
class RoutePart:
    name: str
    coords: list[tuple[float, float]]


@dataclass
class Sheet:
    sheet_number: str
    branch_index: int
    center_x: float
    center_y: float
    angle_rad: float
    width: float
    height: float
    start_station: float
    end_station: float
    vertices: list[tuple[float, float]]


def load_config(path: Path) -> dict[str, Any]:
    config = DEFAULT_CONFIG.copy()
    if path.exists():
        with path.open("r", encoding="utf-8") as f:
            config.update(json.load(f))
    return config


def split_num_pair(text: str) -> tuple[float, float] | None:
    parts = [p.strip() for p in text.split(",")]
    if len(parts) < 2:
        return None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None


def load_route_from_bskmz_txt(path: Path) -> list[RoutePart]:
    parts: list[RoutePart] = []
    with path.open("r", encoding="utf-8-sig", errors="replace") as f:
        for line_no, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or not line.startswith("L|"):
                continue
            fields = line.split("|", 2)
            if len(fields) != 3:
                raise ValueError(f"Invalid BSKMZ line record at line {line_no}: {line}")
            name = fields[1].strip() or f"line_{line_no}"
            coords = []
            for token in fields[2].split(";"):
                pair = split_num_pair(token)
                if pair:
                    coords.append(pair)
            if len(coords) >= 2:
                parts.append(RoutePart(name=name, coords=coords))
    return parts


def load_route_from_csv(path: Path) -> list[RoutePart]:
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
        route_name = names.get("route") or names.get("name") or names.get("folder") or names.get("doc")
        order_name = names.get("order") or names.get("station") or names.get("seq")
        wkt_name = names.get("wkt")

        if wkt_name:
            rows = list(reader)
            parts = []
            for index, row in enumerate(rows, 1):
                wkt = row.get(wkt_name, "")
                if not wkt.upper().startswith("LINESTRING"):
                    continue
                inside = wkt[wkt.find("(") + 1 : wkt.rfind(")")]
                coords = []
                for pair_text in inside.split(","):
                    nums = pair_text.strip().split()
                    if len(nums) >= 2:
                        coords.append((float(nums[0]), float(nums[1])))
                if len(coords) >= 2:
                    parts.append(RoutePart(row.get(route_name, "") or f"csv_{index}", coords))
            return parts

        if not x_name or not y_name:
            return []

        grouped: dict[str, list[tuple[float, float, float]]] = {}
        for index, row in enumerate(reader):
            try:
                x = float(row[x_name])
                y = float(row[y_name])
            except (TypeError, ValueError):
                continue
            key = (row.get(route_name, "") if route_name else "") or "csv_route"
            try:
                order = float(row[order_name]) if order_name else float(index)
            except (TypeError, ValueError):
                order = float(index)
            grouped.setdefault(key, []).append((order, x, y))

    parts = []
    for name, rows in grouped.items():
        coords = [(x, y) for _, x, y in sorted(rows)]
        if len(coords) >= 2:
            parts.append(RoutePart(name=name, coords=coords))
    return parts


def load_route_from_geojson(path: Path) -> list[RoutePart]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    features = data.get("features", [data])
    parts: list[RoutePart] = []
    for index, feature in enumerate(features, 1):
        geom = feature.get("geometry", feature)
        props = feature.get("properties", {}) or {}
        name = str(props.get("name") or props.get("Name") or f"geojson_{index}")
        if not geom:
            continue
        geom_obj = shape(geom)
        if geom_obj.geom_type == "LineString":
            parts.append(RoutePart(name, [(float(x), float(y)) for x, y, *_ in geom_obj.coords]))
        elif geom_obj.geom_type == "MultiLineString":
            for sub_index, line in enumerate(geom_obj.geoms, 1):
                coords = [(float(x), float(y)) for x, y, *_ in line.coords]
                parts.append(RoutePart(f"{name}_{sub_index}", coords))
    return parts


def load_route_from_kml(path: Path) -> list[RoutePart]:
    if path.suffix.lower() == ".kmz":
        with zipfile.ZipFile(path) as zf:
            kml_names = [n for n in zf.namelist() if n.lower().endswith(".kml")]
            if not kml_names:
                return []
            xml_bytes = zf.read("doc.kml" if "doc.kml" in kml_names else kml_names[0])
    else:
        xml_bytes = path.read_bytes()

    root = ET.fromstring(xml_bytes)
    ns = {"k": "http://www.opengis.net/kml/2.2"}
    parts: list[RoutePart] = []
    for index, placemark in enumerate(root.findall(".//k:Placemark", ns), 1):
        name_node = placemark.find("k:name", ns)
        name = name_node.text.strip() if name_node is not None and name_node.text else f"kml_{index}"
        for node in placemark.findall(".//k:LineString/k:coordinates", ns):
            coords = []
            for token in (node.text or "").replace("\n", " ").split():
                pair = split_num_pair(token)
                if pair:
                    coords.append(pair)
            if len(coords) >= 2:
                parts.append(RoutePart(name, coords))
    return parts


def load_route_auto(path: Path) -> list[RoutePart]:
    suffix = path.suffix.lower()
    if suffix in {".geojson", ".json"}:
        parts = load_route_from_geojson(path)
        if parts:
            return parts
    if suffix in {".kml", ".kmz"}:
        parts = load_route_from_kml(path)
        if parts:
            return parts
    if suffix == ".csv":
        parts = load_route_from_csv(path)
        if parts:
            return parts
    parts = load_route_from_bskmz_txt(path)
    if parts:
        return parts
    raise ValueError(f"No usable route lines found in {path}")


def looks_like_lonlat(parts: Iterable[RoutePart]) -> bool:
    coords = [xy for part in parts for xy in part.coords]
    if not coords:
        return False
    in_degrees = [
        -180.0 <= x <= 180.0 and -90.0 <= y <= 90.0
        for x, y in coords[: min(len(coords), 1000)]
    ]
    return sum(in_degrees) / len(in_degrees) >= 0.95


def transform_parts(parts: list[RoutePart], target_epsg: int) -> tuple[list[RoutePart], bool]:
    if not looks_like_lonlat(parts):
        return parts, False
    transformer = Transformer.from_crs("EPSG:4326", f"EPSG:{target_epsg}", always_xy=True)
    transformed = []
    for part in parts:
        transformed.append(RoutePart(part.name, [transformer.transform(x, y) for x, y in part.coords]))
    return transformed, True


def clean_line(coords: list[tuple[float, float]]) -> LineString | None:
    cleaned = []
    last = None
    for xy in coords:
        if last is None or math.hypot(xy[0] - last[0], xy[1] - last[1]) > 0.01:
            cleaned.append(xy)
            last = xy
    if len(cleaned) < 2:
        return None
    line = LineString(cleaned)
    if line.length <= 0:
        return None
    return line


def merge_touching_parts(parts: list[RoutePart]) -> list[tuple[str, LineString]]:
    lines = []
    for part in parts:
        line = clean_line(part.coords)
        if line is not None:
            lines.append((part.name, line))
    if len(lines) <= 1:
        return lines

    merged = linemerge([line for _, line in lines])
    if merged.geom_type == "LineString":
        return [("merged_route", merged)]
    if merged.geom_type == "MultiLineString":
        return [(f"route_{i}", line) for i, line in enumerate(merged.geoms, 1)]
    return lines


def tangent_angle(line: LineString, station: float) -> float:
    length = line.length
    station = min(max(station, 0.0), length)
    delta = min(10.0, max(length / 100.0, 1.0))
    s1 = max(0.0, station - delta)
    s2 = min(length, station + delta)
    if abs(s2 - s1) < 0.001:
        s1 = max(0.0, station - 1.0)
        s2 = min(length, station + 1.0)
    p1 = line.interpolate(s1)
    p2 = line.interpolate(s2)
    return math.atan2(p2.y - p1.y, p2.x - p1.x)


def point_at_station(line: LineString, station: float) -> Point:
    length = line.length
    if 0.0 <= station <= length:
        return line.interpolate(station)

    if station < 0.0:
        base = line.interpolate(0.0)
        angle = tangent_angle(line, 0.0)
        distance = station
    else:
        base = line.interpolate(length)
        angle = tangent_angle(line, length)
        distance = station - length

    return Point(base.x + math.cos(angle) * distance, base.y + math.sin(angle) * distance)


def rectangle_vertices(cx: float, cy: float, angle: float, width: float, height: float) -> list[tuple[float, float]]:
    ux, uy = math.cos(angle), math.sin(angle)
    vx, vy = -uy, ux
    hw, hh = width / 2.0, height / 2.0
    return [
        (cx - ux * hw - vx * hh, cy - uy * hw - vy * hh),
        (cx + ux * hw - vx * hh, cy + uy * hw - vy * hh),
        (cx + ux * hw + vx * hh, cy + uy * hw + vy * hh),
        (cx - ux * hw + vx * hh, cy - uy * hw + vy * hh),
    ]


def make_sheet(sheet_number: str, branch_index: int, line: LineString, station: float, config: dict[str, Any]) -> Sheet:
    width = float(config["sheet_width_ft"])
    height = float(config["sheet_height_ft"])
    pt = point_at_station(line, station)
    angle = math.radians(float(config["fixed_sheet_angle_deg"]))
    return Sheet(
        sheet_number=sheet_number,
        branch_index=branch_index,
        center_x=pt.x,
        center_y=pt.y,
        angle_rad=angle,
        width=width,
        height=height,
        start_station=max(0.0, station - width / 2.0),
        end_station=min(line.length, station + width / 2.0),
        vertices=rectangle_vertices(pt.x, pt.y, angle, width, height),
    )


def make_sheet_at_center(
    sheet_number: str,
    branch_index: int,
    center_x: float,
    center_y: float,
    angle: float,
    width: float,
    height: float,
) -> Sheet:
    return Sheet(
        sheet_number=sheet_number,
        branch_index=branch_index,
        center_x=center_x,
        center_y=center_y,
        angle_rad=angle,
        width=width,
        height=height,
        start_station=0.0,
        end_station=0.0,
        vertices=rectangle_vertices(center_x, center_y, angle, width, height),
    )


def sheet_polygon(sheet: Sheet, expand: float = 0.0) -> Polygon:
    verts = rectangle_vertices(
        sheet.center_x,
        sheet.center_y,
        sheet.angle_rad,
        sheet.width + 2.0 * expand,
        sheet.height + 2.0 * expand,
    )
    return Polygon(verts)


def initial_stations(length: float, width: float, overlap: float, endpoint_ratio: float) -> list[float]:
    if length <= 0:
        return []
    endpoint_ratio = min(max(endpoint_ratio, 0.5), 0.9)
    step = max(width - overlap, width * 0.25)
    first_center = (0.5 - endpoint_ratio) * width
    last_target = length + (endpoint_ratio - 0.5) * width
    if length <= width:
        count = max(1, math.ceil((last_target - first_center) / step) + 1)
        return [first_center + i * step for i in range(count)]

    stations = [first_center]
    while stations[-1] < last_target:
        stations.append(stations[-1] + step)
    return stations


def sample_stations(length: float, interval: float) -> list[float]:
    stations = []
    s = 0.0
    while s <= length:
        stations.append(s)
        s += max(interval, 1.0)
    if not stations or stations[-1] < length:
        stations.append(length)
    return stations


def sample_offsets(left: float, right: float, interval: float) -> list[float]:
    offsets = [0.0]
    step = max(interval, 1.0)
    distance = step
    while distance <= left:
        offsets.append(distance)
        distance += step
    if left > 0.0 and (not offsets or abs(offsets[-1] - left) > 0.01):
        offsets.append(left)

    distance = step
    while distance <= right:
        offsets.append(-distance)
        distance += step
    if right > 0.0 and all(abs(offset + right) > 0.01 for offset in offsets):
        offsets.append(-right)
    return sorted(offsets)


def offset_point(line: LineString, station: float, offset: float) -> Point:
    center = line.interpolate(min(max(station, 0.0), line.length))
    angle = tangent_angle(line, station)
    nx, ny = -math.sin(angle), math.cos(angle)
    return Point(center.x + nx * offset, center.y + ny * offset)


def axis_coords(pt: Point, angle: float) -> tuple[float, float]:
    ux, uy = math.cos(angle), math.sin(angle)
    vx, vy = -uy, ux
    return pt.x * ux + pt.y * uy, pt.x * vx + pt.y * vy


def world_from_axis(s: float, t: float, angle: float) -> tuple[float, float]:
    ux, uy = math.cos(angle), math.sin(angle)
    vx, vy = -uy, ux
    return s * ux + t * vx, s * uy + t * vy


def plan_line_grid(branch_index: int, line: LineString, config: dict[str, Any], start_number: int) -> tuple[list[Sheet], list[str]]:
    width = float(config["sheet_width_ft"])
    height = float(config["sheet_height_ft"])
    angle = math.radians(float(config["fixed_sheet_angle_deg"]))
    endpoint_ratio = min(max(float(config["endpoint_inset_ratio"]), 0.5), 0.9)
    interval = float(config["sample_interval_ft"])
    left = max(0.0, float(config["road_buffer_left_ft"]))
    right = max(0.0, float(config["road_buffer_right_ft"]))
    offset_interval = max(interval, min(left or interval, right or interval, interval))

    start_pt = line.interpolate(0.0)
    start_s, start_t = axis_coords(start_pt, angle)
    grid_left = start_s - endpoint_ratio * width
    grid_bottom = start_t - height / 2.0

    cells: OrderedDict[tuple[int, int], None] = OrderedDict()
    for station in sample_stations(line.length, interval):
        for offset in sample_offsets(left, right, offset_interval):
            pt = offset_point(line, station, offset)
            s, t = axis_coords(pt, angle)
            ix = math.floor((s - grid_left) / width)
            iy = math.floor((t - grid_bottom) / height)
            cells.setdefault((ix, iy), None)

    sheets: list[Sheet] = []
    for index, (ix, iy) in enumerate(cells.keys()):
        center_s = grid_left + ix * width + width / 2.0
        center_t = grid_bottom + iy * height + height / 2.0
        x, y = world_from_axis(center_s, center_t, angle)
        sheets.append(make_sheet_at_center(f"S{start_number + index:03d}", branch_index, x, y, angle, width, height))

    return sheets, corridor_uncovered_points(line, sheets, config)


def corridor_uncovered_points(line: LineString, sheets: list[Sheet], config: dict[str, Any]) -> list[str]:
    interval = float(config["sample_interval_ft"])
    left = max(0.0, float(config["road_buffer_left_ft"]))
    right = max(0.0, float(config["road_buffer_right_ft"]))
    clearance = max(0.0, float(config["required_edge_clearance_ft"]))
    offset_interval = max(interval, min(left or interval, right or interval, interval))

    sheet_polygons = [sheet_polygon(sheet) for sheet in sheets]
    if clearance > 0.0:
        sheet_polygons = [poly.buffer(-clearance) for poly in sheet_polygons]
    sheet_polygons = [poly for poly in sheet_polygons if not poly.is_empty]

    uncovered: list[str] = []
    for station in sample_stations(line.length, interval):
        for offset in sample_offsets(left, right, offset_interval):
            pt = offset_point(line, station, offset)
            if not any(poly.covers(pt) for poly in sheet_polygons):
                uncovered.append(f"{station:.1f}@{offset:.1f}")
                break
    return uncovered


def sheet_overlap_warnings(sheets: list[Sheet]) -> list[str]:
    warnings: list[str] = []
    polygons = [sheet_polygon(sheet) for sheet in sheets]
    for i, sheet_a in enumerate(sheets):
        for j in range(i + 1, len(sheets)):
            sheet_b = sheets[j]
            area = polygons[i].intersection(polygons[j]).area
            if area > 1.0:
                warnings.append(f"{sheet_a.sheet_number}-{sheet_b.sheet_number}:{area:.1f}sf")
    return warnings


def find_bend_stations(line: LineString, threshold_deg: float = 25.0) -> list[float]:
    """Return stations along the line where the direction changes >= threshold_deg.
    Walks the original polyline vertices — bends are where the input route turns
    (intersections, road bends, route-direction reversals)."""
    coords = list(line.coords)
    bends: list[float] = []
    if len(coords) < 3:
        return bends
    cumlen = 0.0
    for i in range(1, len(coords) - 1):
        x0, y0 = coords[i - 1][0], coords[i - 1][1]
        x1, y1 = coords[i    ][0], coords[i    ][1]
        x2, y2 = coords[i + 1][0], coords[i + 1][1]
        seg_len = math.hypot(x1 - x0, y1 - y0)
        cumlen += seg_len
        a1 = math.atan2(y1 - y0, x1 - x0)
        a2 = math.atan2(y2 - y1, x2 - x1)
        # wrap to [-pi, pi]
        delta = (a2 - a1 + math.pi) % (2.0 * math.pi) - math.pi
        if abs(math.degrees(delta)) >= threshold_deg:
            bends.append(cumlen)
    return bends


def adjust_stations_for_bends(stations: list[float],
                              bends: list[float],
                              line_length: float,
                              clearance_ft: float = 50.0) -> list[float]:
    """Shift sheet centers so the boundary between any two consecutive sheets
    is at least clearance_ft from any bend along the route."""
    if not bends or len(stations) < 2:
        return stations
    out = list(stations)
    for i in range(len(out) - 1):
        boundary = (out[i] + out[i + 1]) / 2.0
        # find closest bend
        nearest = min(bends, key=lambda b: abs(b - boundary))
        if abs(boundary - nearest) >= clearance_ft:
            continue
        # push boundary away from the bend in whichever direction keeps it within line
        if boundary <= nearest:
            new_boundary = max(0.0, nearest - clearance_ft)
        else:
            new_boundary = min(line_length, nearest + clearance_ft)
        # apply shift by moving the NEXT sheet's center so boundary lands at new_boundary
        out[i + 1] = 2.0 * new_boundary - out[i]
    return out


def filter_empty_sheets(sheets: list[Sheet], line: LineString,
                        min_overlap_ft: float = 10.0) -> list[Sheet]:
    """Drop sheets the route does not meaningfully pass through."""
    kept: list[Sheet] = []
    for s in sheets:
        poly = sheet_polygon(s)
        try:
            inter = poly.intersection(line)
        except Exception:
            inter = None
        if inter is None or inter.is_empty:
            continue
        length = getattr(inter, "length", 0.0)
        if length >= min_overlap_ft:
            kept.append(s)
    return kept


def plan_line(branch_index: int, line: LineString, config: dict[str, Any], start_number: int) -> tuple[list[Sheet], list[str]]:
    # Placement mode: "follow_route" (per-station tangent, staggered) is default.
    # Set placement_mode = "grid" in config to use the older axis-aligned grid.
    mode = str(config.get("placement_mode", "follow_route")).lower()
    if mode == "grid" and "fixed_sheet_angle_deg" in config:
        return plan_line_grid(branch_index, line, config, start_number)

    width          = float(config["sheet_width_ft"])
    overlap        = float(config["overlap_ft"])
    endpoint_ratio = float(config["endpoint_inset_ratio"])
    bend_thresh    = float(config.get("bend_threshold_deg", 25.0))
    bend_clear     = float(config.get("bend_clearance_ft", 50.0))

    # 1) initial evenly-spaced stations along the route
    stations = initial_stations(line.length, width, overlap, endpoint_ratio)

    # 2) Rule 2: keep sheet boundaries >= 50' from any bend in the route
    bends = find_bend_stations(line, bend_thresh)
    stations = adjust_stations_for_bends(stations, bends, line.length, bend_clear)

    # 3) build sheets, each rotated to the route tangent at its center
    sheets = [
        make_sheet(f"S{start_number + i:03d}", branch_index, line, st, config)
        for i, st in enumerate(stations)
    ]

    # 4) Rule 1: drop sheets the route does not actually pass through
    sheets = filter_empty_sheets(sheets, line)

    return sheets, corridor_uncovered_points(line, sheets, config)


def renumber_sheets(sheets: list[Sheet]) -> None:
    for index, sheet in enumerate(sheets, 1):
        sheet.sheet_number = f"S{index:03d}"


def write_plan_csv(path: Path, sheets: list[Sheet]) -> None:
    fields = [
        "sheet_number",
        "branch_index",
        "center_x",
        "center_y",
        "angle_rad",
        "angle_deg",
        "width",
        "height",
        "start_station",
        "end_station",
        "v1_x",
        "v1_y",
        "v2_x",
        "v2_y",
        "v3_x",
        "v3_y",
        "v4_x",
        "v4_y",
    ]
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for sheet in sheets:
            row = {
                "sheet_number": sheet.sheet_number,
                "branch_index": sheet.branch_index,
                "center_x": f"{sheet.center_x:.3f}",
                "center_y": f"{sheet.center_y:.3f}",
                "angle_rad": f"{sheet.angle_rad:.8f}",
                "angle_deg": f"{math.degrees(sheet.angle_rad):.4f}",
                "width": f"{sheet.width:.3f}",
                "height": f"{sheet.height:.3f}",
                "start_station": f"{sheet.start_station:.3f}",
                "end_station": f"{sheet.end_station:.3f}",
            }
            for i, (x, y) in enumerate(sheet.vertices, 1):
                row[f"v{i}_x"] = f"{x:.3f}"
                row[f"v{i}_y"] = f"{y:.3f}"
            writer.writerow(row)


def lsp_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_plan_lsp(path: Path, sheets: list[Sheet], config: dict[str, Any], report: dict[str, Any]) -> None:
    proposed_layer = str(config["proposed_layer"])
    label_layer = str(config["label_layer"])
    label_height = float(config["label_height_ft"])
    with path.open("w", encoding="ascii", newline="\n") as f:
        f.write(";;; Generated by bssheetplan.py. Safe to overwrite.\n")
        f.write("(vl-load-com)\n")
        f.write("(defun bssheet-plan-ensure-layer (lname color / )\n")
        f.write("  (if (not (tblsearch \"LAYER\" lname)) (command \"_.LAYER\" \"N\" lname \"C\" (itoa color) lname \"\"))\n")
        f.write("  (command \"_.LAYER\" \"ON\" lname \"T\" lname \"\")\n")
        f.write("  (princ))\n")
        f.write("(defun bssheet-plan-make-rect (verts layer / )\n")
        f.write("  (entmakex (append (list '(0 . \"LWPOLYLINE\") '(100 . \"AcDbEntity\") (cons 8 layer) '(100 . \"AcDbPolyline\") '(90 . 4) '(70 . 1)) (mapcar '(lambda (p) (cons 10 p)) verts))))\n")
        f.write("(defun bssheet-plan-make-text (pt ang txt layer height / )\n")
        f.write("  (entmakex (list '(0 . \"TEXT\") (cons 8 layer) (cons 10 pt) (cons 11 pt) (cons 40 height) (cons 1 txt) (cons 50 ang) '(72 . 1) '(73 . 2) '(7 . \"STANDARD\"))))\n")
        f.write("(setq *bssheet-generated-plan*\n  '(\n")
        for sheet in sheets:
            verts = " ".join(f"({x:.3f} {y:.3f} 0.0)" for x, y in sheet.vertices)
            f.write(
                f"    ({lsp_string(sheet.sheet_number)} "
                f"({sheet.center_x:.3f} {sheet.center_y:.3f} 0.0) "
                f"{sheet.angle_rad:.8f} ({verts}))\n"
            )
        f.write("  ))\n")
        f.write("(defun c:BSSHEETMAKEPLAN ( / old-clayer old-cmdecho rec label-pt)\n")
        f.write("  (setq old-clayer (getvar \"CLAYER\") old-cmdecho (getvar \"CMDECHO\"))\n")
        f.write("  (setvar \"CMDECHO\" 0)\n")
        f.write("  (command \"_.UNDO\" \"_BE\")\n")
        f.write(f"  (bssheet-plan-ensure-layer {lsp_string(proposed_layer)} 30)\n")
        f.write(f"  (bssheet-plan-ensure-layer {lsp_string(label_layer)} 30)\n")
        f.write("  (foreach rec *bssheet-generated-plan*\n")
        f.write(f"    (bssheet-plan-make-rect (nth 3 rec) {lsp_string(proposed_layer)})\n")
        f.write("    (setq label-pt (cadr rec))\n")
        f.write(f"    (bssheet-plan-make-text label-pt (nth 2 rec) (car rec) {lsp_string(label_layer)} {label_height:.3f}))\n")
        f.write("  (command \"_.UNDO\" \"_E\")\n")
        f.write("  (setvar \"CLAYER\" old-clayer)\n")
        f.write("  (setvar \"CMDECHO\" old-cmdecho)\n")
        f.write(f"  (princ \"\\n[BSSHEETMAKEPLAN] Created {len(sheets)} proposed sheet rectangle(s).\")\n")
        f.write("  (princ))\n")
        f.write("(princ \"\\n[BSSHEET_PLAN] Loaded. Run BSSHEETMAKEPLAN.\")\n(princ)\n")


def write_report(path: Path, report: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as f:
        f.write("Brightspeed Sheet Plan Report\n")
        f.write("=============================\n")
        for key, value in report.items():
            if isinstance(value, list):
                f.write(f"{key}: {', '.join(str(v) for v in value) if value else 'none'}\n")
            else:
                f.write(f"{key}: {value}\n")


def build_plan(input_path: Path, config: dict[str, Any]) -> tuple[list[Sheet], dict[str, Any]]:
    raw_parts = load_route_auto(input_path)
    parts, transformed = transform_parts(raw_parts, int(config["target_epsg"]))
    merged_lines = merge_touching_parts(parts)
    if not merged_lines:
        raise ValueError("No valid route geometry after parsing")

    all_sheets: list[Sheet] = []
    uncovered_all: list[str] = []
    total_length = 0.0
    next_number = 1
    for branch_index, (_, line) in enumerate(merged_lines, 1):
        sheets, uncovered = plan_line(branch_index, line, config, next_number)
        all_sheets.extend(sheets)
        next_number += len(sheets)
        total_length += line.length
        uncovered_all.extend(f"B{branch_index}:{station}" for station in uncovered)

    renumber_sheets(all_sheets)
    covered_feet = sum(max(0.0, sheet.end_station - sheet.start_station) for sheet in all_sheets)
    overlaps = sheet_overlap_warnings(all_sheets)
    report = {
        "source": str(input_path),
        "coordinate_transform": f"EPSG:4326 -> EPSG:{config['target_epsg']}" if transformed else "none",
        "route_length_ft": f"{total_length:.1f}",
        "sheet_count": len(all_sheets),
        "total_covered_feet": f"{covered_feet:.1f}",
        "corridor_width_ft": f"{float(config['road_buffer_left_ft']) + float(config['road_buffer_right_ft']):.1f}",
        "endpoint_inset_ratio": f"{float(config['endpoint_inset_ratio']):.4f}",
        "uncovered_corridor_stations": uncovered_all,
        "sheet_overlap_warnings": overlaps,
        "branch_count": len(merged_lines),
        "raw_line_count": len(raw_parts),
    }
    return all_sheets, report


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create AutoCAD sheet rectangles along a BSKMZ route export.")
    parser.add_argument("--input", required=True, help="Path to BSKMZ .txt, CSV, GeoJSON, KML, or KMZ route export.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH), help="Path to bssheet_config.json.")
    parser.add_argument("--out-dir", default=".", help="Output directory for bssheet_plan.csv/.lsp/report.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    input_path = Path(args.input).expanduser().resolve()
    config_path = Path(args.config).expanduser().resolve()
    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    config = load_config(config_path)
    sheets, report = build_plan(input_path, config)
    write_plan_csv(out_dir / "bssheet_plan.csv", sheets)
    write_plan_lsp(out_dir / "bssheet_plan.lsp", sheets, config, report)
    write_report(out_dir / "bssheet_report.txt", report)

    print(f"Route length: {report['route_length_ft']} ft")
    print(f"Sheet count: {report['sheet_count']}")
    print(f"Branch count: {report['branch_count']}")
    print(f"Uncovered corridor stations: {', '.join(report['uncovered_corridor_stations']) if report['uncovered_corridor_stations'] else 'none'}")
    print(f"Sheet overlap warnings: {', '.join(report['sheet_overlap_warnings']) if report['sheet_overlap_warnings'] else 'none'}")
    print(f"Wrote: {out_dir / 'bssheet_plan.csv'}")
    print(f"Wrote: {out_dir / 'bssheet_plan.lsp'}")
    print(f"Wrote: {out_dir / 'bssheet_report.txt'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
