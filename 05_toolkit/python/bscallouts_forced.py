#!/usr/bin/env python3
"""Plan and place forced Brightspeed MLeader callouts in active AutoCAD."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

try:
    from shapely.geometry import LineString, Point, box
    from shapely.geometry.base import BaseGeometry

    SHAPELY_AVAILABLE = True
except ImportError:
    LineString = Point = box = None  # type: ignore[assignment]
    BaseGeometry = object  # type: ignore[assignment,misc]
    SHAPELY_AVAILABLE = False


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
REPORT_DIR = SCRIPT_DIR / "reports"
LISP_HELPER_PATH = REPO_ROOT / "05_toolkit" / "lisp" / "working_commands" / "bscallout_place.lsp"
RUN_LISP_PATH = REPORT_DIR / "bscallouts_forced_run.lsp"
PLAN_JSON_PATH = REPORT_DIR / "bscallouts_forced_plan.json"
PLAN_CSV_PATH = REPORT_DIR / "bscallouts_forced_plan.csv"
REPORT_MD_PATH = REPORT_DIR / "bscallouts_forced_report.md"

CALLOUT_LAYER = "CABLE CALLOUTS"
STATIONING_LAYER = "STATIONING"
REVIEW_LAYER = "BS-CALLOUT-REVIEW"
COLLISION_LAYER = "BS-CALLOUT-COLLISION"
TEXT_HEIGHT = 5.0
TEXT_WIDTH_FACTOR = 0.65
TEXT_MIN_WIDTH = 70.0
TEXT_BOX_HEIGHT = 12.0
LANDING_GAP = 5.0
LEADER_CORRIDOR_WIDTH = 3.0
SHEET_MARGIN = 10.0
SHEET_SAMPLE_STEP = 25.0
SHEET_MIN_WIDTH = 100.0
SHEET_MIN_HEIGHT = 100.0
SHEET_DUP_TOLERANCE = 8.0
STATIONING_SIDE_OFFSETS = (15.0, 18.0, 20.0)
STATIONING_TANGENTIAL_SHIFTS = (0.0, 4.0, -4.0, 8.0, -8.0)

BURIED_LAYERS = {
    "buried fiber in duct",
    "buried fiber",
    "underground",
    "proposed buried",
}
AERIAL_LAYERS = {
    "aerial fiber",
    "new strand",
    "new build",
    "new strand/new build",
    "e-lash",
    "elash",
    "overlash",
}
CURVE_OBJECTS = {
    "acdbline",
    "acdbpolyline",
    "acdblrwpolyline",
    "acdb2dpolyline",
    "acdb3dpolyline",
}
BLOCKER_OBJECTS = {
    "acdbtext",
    "acdbmtext",
    "acdbdimension",
    "acdbmleader",
    "acdbleader",
    "acdbblockreference",
    "acdbline",
    "acdbpolyline",
    "acdblrwpolyline",
    "acdb2dpolyline",
    "acdb3dpolyline",
}
ROAD_LAYER_TERMS = (
    "cl",
    "centerline",
    "road-centerline",
    "eop",
    "roads-paved",
)
BLOCKER_LAYER_TERMS = (
    "row",
    "r/w",
    "row-trap",
    "property",
    "parcel",
    "dim",
    "road names",
    "street",
    "handhole",
    "bore",
    "pole",
    "gps",
)


@dataclass(frozen=True)
class Source:
    source_id: str
    handle: str
    family: str
    subtype: str
    layer: str
    object_name: str
    points: tuple[tuple[float, float], ...]
    point: tuple[float, float] | None
    length: float
    bbox: tuple[float, float, float, float]
    rotation: float = 0.0


@dataclass(frozen=True)
class Sheet:
    sheet_id: str
    handle: str
    bbox: tuple[float, float, float, float]


@dataclass(frozen=True)
class Blocker:
    handle: str
    layer: str
    object_name: str
    category: str
    bbox: tuple[float, float, float, float]
    points: tuple[tuple[float, float], ...] = ()


@dataclass(frozen=True)
class Candidate:
    number: int
    anchor: tuple[float, float]
    text_point: tuple[float, float]
    text_bbox: tuple[float, float, float, float]
    score: float
    reason: str
    side: str


@dataclass(frozen=True)
class Placement:
    placement_id: str
    source_id: str
    source_handle: str
    family: str
    subtype: str
    sheet_id: str
    label: str
    anchor: tuple[float, float]
    text_point: tuple[float, float]
    text_bbox: tuple[float, float, float, float]
    quality: str
    reason: str
    score: float
    render_mode: str
    text_rotation: float
    output_layer: str


@dataclass(frozen=True)
class PlanResult:
    sources: tuple[Source, ...]
    sheets: tuple[Sheet, ...]
    blockers: tuple[Blocker, ...]
    placements: tuple[Placement, ...]




def norm(value: str) -> str:
    return " ".join((value or "").replace("_", " ").strip().lower().split())


def safe_get(obj: Any, prop: str, default: Any = None) -> Any:
    try:
        return getattr(obj, prop)
    except Exception:
        return default


def object_name(obj: Any) -> str:
    return str(safe_get(obj, "ObjectName", ""))


def object_handle(obj: Any) -> str:
    handle = safe_get(obj, "Handle", "")
    return str(handle) if handle else ""


def layer_name(obj: Any) -> str:
    return str(safe_get(obj, "Layer", ""))


def xy(point: Any) -> tuple[float, float]:
    return (float(point[0]), float(point[1]))


def distance(a: Sequence[float], b: Sequence[float]) -> float:
    return math.hypot(float(a[0]) - float(b[0]), float(a[1]) - float(b[1]))


def add(a: Sequence[float], b: Sequence[float]) -> tuple[float, float]:
    return (float(a[0]) + float(b[0]), float(a[1]) + float(b[1]))


def sub(a: Sequence[float], b: Sequence[float]) -> tuple[float, float]:
    return (float(a[0]) - float(b[0]), float(a[1]) - float(b[1]))


def scale(v: Sequence[float], factor: float) -> tuple[float, float]:
    return (float(v[0]) * factor, float(v[1]) * factor)


def unit(v: Sequence[float]) -> tuple[float, float]:
    length = math.hypot(float(v[0]), float(v[1]))
    if length <= 1e-9:
        return (1.0, 0.0)
    return (float(v[0]) / length, float(v[1]) / length)


def perp_left(v: Sequence[float]) -> tuple[float, float]:
    u = unit(v)
    return (-u[1], u[0])


def perp_right(v: Sequence[float]) -> tuple[float, float]:
    u = unit(v)
    return (u[1], -u[0])


def bbox_from_points(points: Sequence[Sequence[float]]) -> tuple[float, float, float, float]:
    xs = [float(p[0]) for p in points]
    ys = [float(p[1]) for p in points]
    return (min(xs), min(ys), max(xs), max(ys))


def bbox_center(bbox: tuple[float, float, float, float]) -> tuple[float, float]:
    return ((bbox[0] + bbox[2]) / 2.0, (bbox[1] + bbox[3]) / 2.0)


def bbox_area(bbox: tuple[float, float, float, float]) -> float:
    return max(0.0, bbox[2] - bbox[0]) * max(0.0, bbox[3] - bbox[1])


def bbox_intersects(
    a: tuple[float, float, float, float],
    b: tuple[float, float, float, float],
    pad: float = 0.0,
) -> bool:
    return not (a[2] + pad < b[0] or b[2] + pad < a[0] or a[3] + pad < b[1] or b[3] + pad < a[1])


def bbox_contains(
    inner: tuple[float, float, float, float],
    outer: tuple[float, float, float, float],
    pad: float = 0.0,
) -> bool:
    return inner[0] >= outer[0] - pad and inner[1] >= outer[1] - pad and inner[2] <= outer[2] + pad and inner[3] <= outer[3] + pad


def bbox_almost_equal(
    a: tuple[float, float, float, float],
    b: tuple[float, float, float, float],
    tolerance: float = SHEET_DUP_TOLERANCE,
) -> bool:
    return all(abs(a[i] - b[i]) <= tolerance for i in range(4))


def clamp_point_to_sheet(point: tuple[float, float], sheet: Sheet | None, margin: float = SHEET_MARGIN) -> tuple[float, float]:
    if sheet is None:
        return point
    xmin, ymin, xmax, ymax = sheet.bbox
    return (
        min(max(point[0], xmin + margin), xmax - margin),
        min(max(point[1], ymin + margin), ymax - margin),
    )


def polyline_length(points: Sequence[Sequence[float]]) -> float:
    return sum(distance(a, b) for a, b in zip(points, points[1:]))


def point_at_distance(points: Sequence[Sequence[float]], target: float) -> tuple[float, float]:
    if not points:
        return (0.0, 0.0)
    if target <= 0.0 or len(points) == 1:
        return xy(points[0])
    walked = 0.0
    for a, b in zip(points, points[1:]):
        seg_len = distance(a, b)
        if seg_len <= 1e-9:
            continue
        if walked + seg_len >= target:
            ratio = (target - walked) / seg_len
            return (float(a[0]) + (float(b[0]) - float(a[0])) * ratio, float(a[1]) + (float(b[1]) - float(a[1])) * ratio)
        walked += seg_len
    return xy(points[-1])


def tangent_at_distance(points: Sequence[Sequence[float]], target: float) -> tuple[float, float]:
    walked = 0.0
    for a, b in zip(points, points[1:]):
        seg_len = distance(a, b)
        if seg_len <= 1e-9:
            continue
        if walked + seg_len >= target:
            return unit(sub(b, a))
        walked += seg_len
    if len(points) >= 2:
        return unit(sub(points[-1], points[-2]))
    return (1.0, 0.0)


def sampled_points(points: Sequence[Sequence[float]], step: float = SHEET_SAMPLE_STEP) -> tuple[tuple[float, float], ...]:
    if not points:
        return ()
    total = polyline_length(points)
    if total <= 0.0:
        return (xy(points[0]),)
    samples: list[tuple[float, float]] = []
    distance_along = 0.0
    while distance_along <= total:
        samples.append(point_at_distance(points, distance_along))
        distance_along += step
    last = xy(points[-1])
    if not samples or samples[-1] != last:
        samples.append(last)
    return tuple(samples)


def text_width(text: str) -> float:
    return max(TEXT_MIN_WIDTH, len(text) * TEXT_HEIGHT * TEXT_WIDTH_FACTOR)


def text_bbox(point: tuple[float, float], text: str) -> tuple[float, float, float, float]:
    width = text_width(text)
    half_h = TEXT_BOX_HEIGHT / 2.0
    return (point[0], point[1] - half_h, point[0] + width, point[1] + half_h)


def centered_text_bbox(point: tuple[float, float], text: str) -> tuple[float, float, float, float]:
    width = text_width(text)
    half_w = width / 2.0
    half_h = TEXT_BOX_HEIGHT / 2.0
    return (point[0] - half_w, point[1] - half_h, point[0] + half_w, point[1] + half_h)


def line_geom(points: Sequence[Sequence[float]]) -> BaseGeometry:
    return LineString([(float(p[0]), float(p[1])) for p in points])


def sheet_geom(sheet: Sheet) -> BaseGeometry:
    return box(*sheet.bbox)


def bbox_geom(bbox: tuple[float, float, float, float]) -> BaseGeometry:
    return box(*bbox)


def flatten_coords(values: Iterable[Any], stride: int) -> tuple[tuple[float, float], ...]:
    raw = list(values)
    return tuple((float(raw[i]), float(raw[i + 1])) for i in range(0, len(raw) - 1, stride))


def entity_bbox(entity: Any) -> tuple[float, float, float, float] | None:
    try:
        lo, hi = entity.GetBoundingBox()
        return (float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1]))
    except Exception:
        return None


def entity_points(entity: Any) -> tuple[tuple[float, float], ...]:
    name = norm(object_name(entity))
    if name == "acdbline":
        return (xy(entity.StartPoint), xy(entity.EndPoint))
    coords = safe_get(entity, "Coordinates")
    if coords is None:
        return ()
    if name in {"acdbpolyline", "acdblrwpolyline", "acdb2dpolyline"}:
        return flatten_coords(coords, 2)
    if name == "acdb3dpolyline":
        return flatten_coords(coords, 3)
    pts = flatten_coords(coords, 2)
    return pts if len(pts) >= 2 else ()


def distinct_points(points: Sequence[Sequence[float]], tolerance: float = 1.0) -> tuple[tuple[float, float], ...]:
    out: list[tuple[float, float]] = []
    for point in points:
        current = xy(point)
        if not out or distance(current, out[-1]) > tolerance:
            out.append(current)
    if len(out) >= 2 and distance(out[0], out[-1]) <= tolerance:
        out.pop()
    return tuple(out)


def is_axis_aligned_rectangle(points: Sequence[Sequence[float]], bbox: tuple[float, float, float, float]) -> bool:
    cleaned = distinct_points(points)
    if len(cleaned) != 4:
        return False
    xmin, ymin, xmax, ymax = bbox
    if xmax - xmin < SHEET_MIN_WIDTH or ymax - ymin < SHEET_MIN_HEIGHT:
        return False
    corners = {
        (xmin, ymin),
        (xmin, ymax),
        (xmax, ymin),
        (xmax, ymax),
    }
    return all(any(distance(point, corner) <= SHEET_DUP_TOLERANCE for corner in corners) for point in cleaned)


def border_sheet_bbox(entity: Any, bbox: tuple[float, float, float, float] | None) -> tuple[float, float, float, float] | None:
    if bbox is None:
        return None
    if norm(object_name(entity)) not in {"acdbpolyline", "acdblrwpolyline", "acdb2dpolyline"}:
        return None
    points = entity_points(entity)
    if not points:
        return None
    if not bool(safe_get(entity, "Closed", False)):
        return None
    if not is_axis_aligned_rectangle(points, bbox):
        return None
    return bbox


def iter_modelspace(ms: Any) -> Iterable[Any]:
    count = int(safe_get(ms, "Count", 0))
    for index in range(count):
        try:
            yield ms.Item(index)
        except Exception:
            continue


def connect_autocad() -> tuple[Any, Any, Any]:
    try:
        import pythoncom  # type: ignore
        import win32com.client  # type: ignore
    except ImportError as exc:
        raise SystemExit("Missing dependency. Install with: python -m pip install pywin32 shapely") from exc
    pythoncom.CoInitialize()
    try:
        acad = win32com.client.GetActiveObject("AutoCAD.Application")
    except Exception as exc:
        raise SystemExit("AutoCAD is not running or not available through COM. Open AutoCAD and a drawing first.") from exc
    doc = acad.ActiveDocument
    return acad, doc, doc.ModelSpace


def is_curve(entity: Any) -> bool:
    return norm(object_name(entity)) in CURVE_OBJECTS


def classify_structure(entity: Any) -> tuple[str, str] | None:
    name = norm(str(safe_get(entity, "EffectiveName", "") or safe_get(entity, "Name", "") or safe_get(entity, "ObjectName", "")))
    layer = norm(layer_name(entity))
    haystack = f"{name} {layer}"
    if "bore" in haystack:
        return ("borepit", "BORE PIT")
    if "handhole" in haystack or ("hh" in haystack and "pole" not in haystack):
        return ("handhole", "HANDHOLE")
    if "pole" in haystack and "riser" in haystack:
        if "down" in haystack or "dn" in haystack:
            return ("riser_down", "POLE/RISER DOWN")
        return ("riser_up", "POLE/RISER UP")
    return None


def insertion_point(entity: Any) -> tuple[float, float] | None:
    point = safe_get(entity, "InsertionPoint")
    if point is None:
        return None
    return xy(point)


def entity_rotation(entity: Any) -> float:
    try:
        return float(safe_get(entity, "Rotation", 0.0) or 0.0)
    except Exception:
        return 0.0


def classify_blocker(entity: Any) -> str | None:
    name = norm(object_name(entity))
    layer = norm(layer_name(entity))
    if name not in BLOCKER_OBJECTS:
        return None
    if layer == norm(CALLOUT_LAYER):
        return "existing-callout"
    if layer == "border":
        return None
    if any(term in layer for term in ROAD_LAYER_TERMS):
        return "road"
    if any(term in layer for term in BLOCKER_LAYER_TERMS):
        return "blocker"
    if name in {"acdbtext", "acdbmtext", "acdbdimension", "acdbmleader", "acdbleader", "acdbblockreference"}:
        return "blocker"
    return None


def append_sheet(sheets: list[Sheet], handle: str, bbox: tuple[float, float, float, float]) -> None:
    for existing in sheets:
        if bbox_almost_equal(existing.bbox, bbox):
            return
        if bbox_contains(bbox, existing.bbox, pad=SHEET_DUP_TOLERANCE) or bbox_contains(existing.bbox, bbox, pad=SHEET_DUP_TOLERANCE):
            existing_area = bbox_area(existing.bbox)
            new_area = bbox_area(bbox)
            if abs(existing_area - new_area) <= 200.0:
                return
    sheets.append(Sheet(f"SHEET-{len(sheets) + 1}", handle, bbox))


def collect_geometry(ms: Any) -> tuple[tuple[Source, ...], tuple[Sheet, ...], tuple[Blocker, ...]]:
    sources: list[Source] = []
    sheets: list[Sheet] = []
    blockers: list[Blocker] = []

    for entity in iter_modelspace(ms):
        handle = object_handle(entity)
        layer = layer_name(entity)
        object_type = object_name(entity)
        bbox = entity_bbox(entity)
        normalized_layer = norm(layer)

        if normalized_layer == "border":
            sheet_bbox = border_sheet_bbox(entity, bbox)
            if sheet_bbox:
                append_sheet(sheets, handle, sheet_bbox)

        if is_curve(entity):
            points = entity_points(entity)
            if len(points) >= 2:
                length = polyline_length(points)
                source_bbox = bbox or bbox_from_points(points)
                if normalized_layer in BURIED_LAYERS:
                    sources.append(
                        Source(
                            f"SRC-{len(sources) + 1}",
                            handle,
                            "buried",
                            "buried",
                            layer,
                            object_type,
                            points,
                            None,
                            length,
                            source_bbox,
                            0.0,
                        )
                    )
                elif normalized_layer in AERIAL_LAYERS:
                    subtype = "elash" if "lash" in normalized_layer else "aerial"
                    sources.append(
                        Source(
                            f"SRC-{len(sources) + 1}",
                            handle,
                            "aerial",
                            subtype,
                            layer,
                            object_type,
                            points,
                            None,
                            length,
                            source_bbox,
                            0.0,
                        )
                    )

        if norm(object_type) == "acdbblockreference":
            classified = classify_structure(entity)
            point = insertion_point(entity)
            if classified and point:
                subtype, label_type = classified
                structure_bbox = bbox or (point[0], point[1], point[0], point[1])
                family = "structure"
                sources.append(
                    Source(
                        f"SRC-{len(sources) + 1}",
                        handle,
                        family,
                        subtype,
                        layer,
                        object_type,
                        (),
                        point,
                        0.0,
                        structure_bbox,
                        entity_rotation(entity),
                    )
                )

        category = classify_blocker(entity)
        if category and bbox:
            blockers.append(Blocker(handle, layer, object_type, category, bbox, entity_points(entity)))

    return tuple(sources), tuple(sheets), tuple(blockers)


def format_station(distance_ft: float) -> str:
    total = max(0, int(round(distance_ft)))
    hundreds, feet = divmod(total, 100)
    return f"STA {hundreds:02d}+{feet:02d}"


def nearest_route(point: tuple[float, float], routes: Sequence[Source], family: str) -> tuple[Source | None, float]:
    best: Source | None = None
    best_dist = float("inf")
    for source in routes:
        if source.family != family or len(source.points) < 2:
            continue
        try:
            dist = line_geom(source.points).distance(Point(point))
        except Exception:
            dist = distance(point, bbox_center(source.bbox))
        if dist < best_dist:
            best = source
            best_dist = dist
    return best, best_dist


def station_for(point: tuple[float, float], routes: Sequence[Source], family: str) -> float:
    route, _ = nearest_route(point, routes, family)
    if route is None:
        return 0.0
    try:
        return float(line_geom(route.points).project(Point(point)))
    except Exception:
        return min(route.length, distance(route.points[0], point))


def angle_delta(a: float, b: float) -> float:
    diff = abs(a - b) % math.pi
    return min(diff, math.pi - diff)


def normalize_text_rotation(angle: float) -> float:
    while angle > math.pi / 2.0:
        angle -= math.pi
    while angle <= -math.pi / 2.0:
        angle += math.pi
    return angle


def text_rotation_from_route_tangent(tangent: tuple[float, float]) -> float:
    return normalize_text_rotation(math.atan2(tangent[1], tangent[0]) + (math.pi / 2.0))


def route_tangent_at_point(route: Source, point: tuple[float, float]) -> tuple[float, float]:
    try:
        station = float(line_geom(route.points).project(Point(point)))
    except Exception:
        station = min(route.length, distance(route.points[0], point))
    return tangent_at_distance(route.points, station)


def dominant_borepit_tangent(point: tuple[float, float], routes: Sequence[Source]) -> tuple[float, float]:
    candidates: list[tuple[float, float, Source, tuple[float, float]]] = []
    for source in routes:
        if source.family != "buried" or len(source.points) < 2:
            continue
        try:
            dist = float(line_geom(source.points).distance(Point(point)))
        except Exception:
            dist = distance(point, bbox_center(source.bbox))
        tangent = route_tangent_at_point(source, point)
        candidates.append((dist, source.length, source, tangent))

    if not candidates:
        return (1.0, 0.0)

    candidates.sort(key=lambda item: (item[0], -item[1]))
    primary = candidates[0]
    primary_angle = math.atan2(primary[3][1], primary[3][0])
    choice = primary

    for current in candidates[1:6]:
        current_angle = math.atan2(current[3][1], current[3][0])
        if angle_delta(primary_angle, current_angle) >= math.radians(45.0):
            choice = current if current[1] > primary[1] else primary
            break

    return choice[3]


def structure_reference_tangent(source: Source, routes: Sequence[Source]) -> tuple[float, float]:
    if source.point is None:
        return (math.cos(source.rotation), math.sin(source.rotation))
    if source.subtype == "borepit":
        tangent = dominant_borepit_tangent(source.point, routes)
        if abs(tangent[0]) > 1e-9 or abs(tangent[1]) > 1e-9:
            return tangent
    family = "aerial" if source.subtype.startswith("riser") else "buried"
    route, _ = nearest_route(source.point, routes, family)
    if route is not None:
        return route_tangent_at_point(route, source.point)
    return (math.cos(source.rotation), math.sin(source.rotation))


def label_for_source(source: Source, routes: Sequence[Source]) -> str:
    if source.family == "buried":
        return f"HDD BORE {int(round(source.length))}' FIBER IN 2\" DUCT"
    if source.family == "aerial":
        if source.subtype == "elash":
            return "AERIAL FIBER ELASHED TO EXISTING"
        return "NEW AERIAL FIBER STRAND"
    if source.family == "mindoc":
        return 'MIN DOC 60"'
    if source.subtype == "handhole":
        assert source.point is not None
        return f"{format_station(station_for(source.point, routes, 'buried'))} PL HANDHOLE"
    if source.subtype == "borepit":
        assert source.point is not None
        return f'{format_station(station_for(source.point, routes, "buried"))} PL 36"X36"\\PBORE PIT'
    if source.subtype == "riser_down":
        assert source.point is not None
        return f"{format_station(station_for(source.point, routes, 'aerial'))} EX POLE/RISER DOWN"
    if source.subtype == "riser_up":
        assert source.point is not None
        return f"{format_station(station_for(source.point, routes, 'aerial'))} EX POLE/RISER UP"
    return "CALLOUT"


def source_geometry(source: Source) -> BaseGeometry:
    if source.points:
        return line_geom(source.points)
    if source.point is not None:
        return Point(source.point)
    return bbox_geom(source.bbox)


def blocker_geometry(blocker: Blocker) -> BaseGeometry:
    if len(blocker.points) >= 2:
        return line_geom(blocker.points)
    return bbox_geom(blocker.bbox)


def blocker_tangent_at_point(blocker: Blocker, point: tuple[float, float]) -> tuple[float, float]:
    if len(blocker.points) >= 2:
        try:
            station = float(line_geom(blocker.points).project(Point(point)))
        except Exception:
            station = polyline_length(blocker.points) / 2.0
        return tangent_at_distance(blocker.points, station)
    xmin, ymin, xmax, ymax = blocker.bbox
    if (xmax - xmin) >= (ymax - ymin):
        return (1.0, 0.0)
    return (0.0, 1.0)


def source_sheets(source: Source, sheets: Sequence[Sheet]) -> tuple[Sheet | None, ...]:
    if not sheets:
        return (None,)
    matches: list[Sheet] = []
    samples = sampled_points(source.points) if source.points else ()
    for sheet in sheets:
        if not bbox_intersects(source.bbox, sheet.bbox, pad=1.0):
            continue
        if any(sheet.bbox[0] - 1.0 <= x <= sheet.bbox[2] + 1.0 and sheet.bbox[1] - 1.0 <= y <= sheet.bbox[3] + 1.0 for x, y in samples):
            matches.append(sheet)
            continue
        geometry = source_geometry(source)
        try:
            if geometry.intersects(sheet_geom(sheet)):
                matches.append(sheet)
        except Exception:
            matches.append(sheet)
    return tuple(matches) if matches else (None,)


def side_from_cross(tangent: tuple[float, float], origin: tuple[float, float], point: tuple[float, float]) -> str:
    vector = sub(point, origin)
    cross = tangent[0] * vector[1] - tangent[1] * vector[0]
    return "left" if cross >= 0.0 else "right"


def nearest_blocker_by_terms(
    point: tuple[float, float],
    blockers: Sequence[Blocker],
    include_terms: Sequence[str],
    category: str | None = None,
) -> Blocker | None:
    best: Blocker | None = None
    best_distance = float("inf")
    for blocker in blockers:
        if category is not None and blocker.category != category:
            continue
        layer = norm(blocker.layer)
        if not any(term in layer for term in include_terms):
            continue
        try:
            current_distance = float(blocker_geometry(blocker).distance(Point(point)))
        except Exception:
            current_distance = distance(point, bbox_center(blocker.bbox))
        if current_distance < best_distance:
            best = blocker
            best_distance = current_distance
    return best


def blocker_side_distance(
    blocker: Blocker,
    center_point: tuple[float, float],
    center_tangent: tuple[float, float],
) -> tuple[str, float]:
    try:
        geometry = blocker_geometry(blocker)
        nearest = geometry.interpolate(geometry.project(Point(center_point)))
        sample = (float(nearest.x), float(nearest.y))
        gap = float(geometry.distance(Point(center_point)))
    except Exception:
        sample = bbox_center(blocker.bbox)
        gap = distance(center_point, sample)
    return side_from_cross(center_tangent, center_point, sample), gap


def anchor_and_tangent(
    source: Source,
    sheet: Sheet | None,
    routes: Sequence[Source],
) -> tuple[tuple[float, float], tuple[float, float]]:
    if source.family in {"buried", "aerial"}:
        points = source.points
        if sheet is not None:
            try:
                clipped = line_geom(source.points).intersection(sheet_geom(sheet))
                if not clipped.is_empty:
                    if clipped.geom_type == "LineString":
                        points = tuple((float(x), float(y)) for x, y in clipped.coords)
                    elif clipped.geom_type == "MultiLineString":
                        longest = max(clipped.geoms, key=lambda geom: geom.length)
                        points = tuple((float(x), float(y)) for x, y in longest.coords)
            except Exception:
                pass
        length = polyline_length(points)
        anchor = point_at_distance(points, length / 2.0)
        return anchor, tangent_at_distance(points, length / 2.0)

    if source.family == "structure" and source.point is not None:
        return source.point, structure_reference_tangent(source, routes)

    if source.point is not None:
        family = "aerial" if source.subtype.startswith("riser") else "buried"
        route, _ = nearest_route(source.point, routes, family)
        tangent = (1.0, 0.0)
        if route is not None:
            station = station_for(source.point, routes, family)
            tangent = tangent_at_distance(route.points, station)
        return source.point, tangent

    return bbox_center(source.bbox), (1.0, 0.0)


def text_point_for_side(anchor: tuple[float, float], tangent: tuple[float, float], label: str, side: str, offset: float, shift: float) -> tuple[float, float]:
    perp = perp_left(tangent) if side == "left" else perp_right(tangent)
    desired = add(add(anchor, scale(perp, offset)), scale(tangent, shift))
    if side == "left":
        return (desired[0] - text_width(label), desired[1])
    return desired


def visible_text_edge_point(text_point: tuple[float, float], label: str, side: str) -> tuple[float, float]:
    if side == "left":
        return (text_point[0] + text_width(label), text_point[1])
    return text_point


def blocker_conflicts(
    text_box: tuple[float, float, float, float],
    leader: tuple[tuple[float, float], tuple[float, float]],
    blockers: Sequence[Blocker],
    source_handle: str,
) -> tuple[list[str], list[str]]:
    text_hits: list[str] = []
    leader_hits: list[str] = []
    leader_geom = LineString(leader).buffer(LEADER_CORRIDOR_WIDTH, cap_style=2, join_style=2)
    box_geom = bbox_geom(text_box)
    for blocker in blockers:
        if blocker.handle == source_handle:
            continue
        geom = bbox_geom(blocker.bbox)
        label = f"{blocker.category}:{blocker.handle}:{norm(blocker.layer)}"
        try:
            if box_geom.intersects(geom):
                text_hits.append(label)
            if leader_geom.intersects(geom):
                leader_hits.append(label)
        except Exception:
            if bbox_intersects(text_box, blocker.bbox):
                text_hits.append(label)
    return text_hits, leader_hits


def score_candidate(
    source: Source,
    sheet: Sheet | None,
    candidate: Candidate,
    blockers: Sequence[Blocker],
) -> tuple[float, str, str]:
    score = candidate.score
    reasons: list[str] = []
    quality = "clean"
    inside = sheet is None or bbox_contains(candidate.text_bbox, sheet.bbox, pad=-SHEET_MARGIN)
    if not inside:
        score -= 3000.0
        reasons.append("outside-sheet")
        quality = "forced"

    text_hits, leader_hits = blocker_conflicts(candidate.text_bbox, (candidate.anchor, candidate.text_point), blockers, source.handle)
    hard_hits = [hit for hit in text_hits + leader_hits if hit.startswith("road:") or hit.startswith("blocker:")]
    soft_hits = [hit for hit in text_hits + leader_hits if hit.startswith("existing-callout:")]

    if hard_hits:
        score -= 700.0 * len(hard_hits)
        quality = "forced"
        reasons.append("hard-conflict:" + ",".join(hard_hits[:5]))
    if soft_hits:
        score -= 75.0 * len(soft_hits)
        if quality == "clean":
            quality = "warn"
        reasons.append("soft-conflict:" + ",".join(soft_hits[:5]))
    return score, quality, ";".join(reasons) if reasons else "clear"


def make_candidates(
    source: Source,
    sheet: Sheet | None,
    label: str,
    anchor: tuple[float, float],
    tangent: tuple[float, float],
    blockers: Sequence[Blocker],
) -> tuple[Candidate, ...]:
    offsets = (30.0, 40.0, 50.0)
    shifts = (0.0, 6.0, -6.0, 12.0, -12.0)
    candidates: list[Candidate] = []
    number = 1
    for side_index, side in enumerate(("left", "right")):
        for offset in offsets:
            for shift in shifts:
                point = text_point_for_side(anchor, tangent, label, side, offset, shift)
                point = clamp_point_to_sheet(point, sheet)
                bbox = text_bbox(point, label)
                separation = distance(anchor, visible_text_edge_point(point, label, side))
                base = 1000.0 - abs(separation - 40.0) * 8.0 - abs(shift) * 2.0 - side_index * 150.0
                raw = Candidate(number, anchor, point, bbox, base, "", side)
                score, quality, reason = score_candidate(source, sheet, raw, blockers)
                candidates.append(Candidate(number, anchor, point, bbox, score, f"{quality}:{reason}", side))
                number += 1
    candidates.sort(key=lambda item: item.score, reverse=True)
    return tuple(candidates)


def make_structure_candidates(
    source: Source,
    sheet: Sheet | None,
    label: str,
    anchor: tuple[float, float],
    tangent: tuple[float, float],
    blockers: Sequence[Blocker],
) -> tuple[Candidate, ...]:
    if source.subtype in {"handhole", "borepit"}:
        offsets = STATIONING_SIDE_OFFSETS
        tangential = STATIONING_TANGENTIAL_SHIFTS
        directions = (
            perp_left(tangent),
            perp_right(tangent),
        )
    else:
        offsets = (18.0, 26.0, 35.0, 50.0, 70.0, 95.0, 125.0)
        tangential = (0.0, 12.0, -12.0, 24.0, -24.0)
        directions = (
            perp_left(tangent),
            perp_right(tangent),
            unit(tangent),
            scale(unit(tangent), -1.0),
        )
    candidates: list[Candidate] = []
    number = 1
    for direction in directions:
        for offset in offsets:
            for shift in tangential:
                center = add(add(anchor, scale(direction, offset)), scale(unit(tangent), shift))
                center = clamp_point_to_sheet(center, sheet)
                bbox = centered_text_bbox(center, label)
                if source.subtype in {"handhole", "borepit"}:
                    base = 1400.0 - abs(offset - 18.0) * 20.0 - abs(shift) * 4.0
                else:
                    base = 1200.0 - offset - abs(shift) * 0.5
                raw = Candidate(number, anchor, center, bbox, base, "", "structure")
                score, quality, reason = score_candidate(source, sheet, raw, blockers)
                candidates.append(Candidate(number, anchor, center, bbox, score, f"{quality}:{reason}", "structure"))
                number += 1
    candidates.sort(key=lambda item: item.score, reverse=True)
    return tuple(candidates)


def placement_quality(candidate: Candidate) -> tuple[str, str]:
    if ":" not in candidate.reason:
        return "clean", candidate.reason
    quality, reason = candidate.reason.split(":", 1)
    if quality not in {"clean", "warn", "forced"}:
        return "forced", candidate.reason
    return quality, reason


def make_mindoc_sources(sources: Sequence[Source], sheets: Sequence[Sheet]) -> tuple[Source, ...]:
    buried = [source for source in sources if source.family == "buried"]
    mindoc: list[Source] = []
    if not sheets:
        if buried:
            point = bbox_center(buried[0].bbox)
            mindoc.append(Source("MIN-DOC-1", "MIN-DOC", "mindoc", "mindoc", "", "NOTE", (), point, 0.0, (point[0], point[1], point[0], point[1]), 0.0))
        return tuple(mindoc)

    for sheet in sheets:
        has_buried = any(source_sheets(source, (sheet,)) != (None,) for source in buried)
        if not has_buried:
            continue
        xmin, ymin, _, _ = sheet.bbox
        point = (xmin + 25.0, ymin + 25.0)
        mindoc.append(Source(f"MIN-DOC-{sheet.sheet_id}", f"MIN-DOC-{sheet.sheet_id}", "mindoc", "mindoc", "", "NOTE", (), point, 0.0, (point[0], point[1], point[0], point[1]), 0.0))
    return tuple(mindoc)


def plan_callouts(
    sources: Sequence[Source],
    sheets: Sequence[Sheet],
    blockers: Sequence[Blocker],
    families: set[str] | None = None,
) -> tuple[Placement, ...]:
    all_sources = tuple(sources) + make_mindoc_sources(sources, sheets)
    routes = [source for source in sources if source.family in {"buried", "aerial"}]
    placements: list[Placement] = []

    priority = {"structure": 0, "mindoc": 1, "buried": 2, "aerial": 3}
    ordered_sources = sorted(all_sources, key=lambda source: (priority.get(source.family, 9), source.source_id))
    occupied = list(blockers)

    for source in ordered_sources:
        if families and source.family not in families and source.subtype not in families:
            continue
        label = label_for_source(source, routes)
        for sheet in source_sheets(source, sheets):
            sheet_id = sheet.sheet_id if sheet else "GLOBAL"
            anchor, tangent = anchor_and_tangent(source, sheet, routes)
            render_mode = "mleader"
            text_rotation = 0.0
            output_layer = CALLOUT_LAYER
            if source.family == "mindoc" and sheet is not None:
                xmin, ymin, _, _ = sheet.bbox
                anchor = (xmin + 20.0, ymin + 20.0)
                point = (xmin + 55.0, ymin + 20.0)
                bbox = centered_text_bbox(point, label)
                candidate = Candidate(1, anchor, point, bbox, 900.0, "clean:fixed-sheet-note", "right")
                render_mode = "filled-text"
            elif source.family == "structure":
                candidates = make_structure_candidates(source, sheet, label, anchor, tangent, occupied)
                candidate = candidates[0] if candidates else Candidate(1, anchor, add(anchor, (25.0, 0.0)), centered_text_bbox(add(anchor, (25.0, 0.0)), label), -9999.0, "forced:no-candidates", "structure")
                if source.subtype in {"handhole", "borepit"}:
                    render_mode = "stationing-text"
                    text_rotation = text_rotation_from_route_tangent(tangent)
                    output_layer = STATIONING_LAYER
                else:
                    render_mode = "filled-text"
                    text_rotation = source.rotation
            else:
                candidates = make_candidates(source, sheet, label, anchor, tangent, occupied)
                candidate = candidates[0] if candidates else Candidate(1, anchor, add(anchor, (25.0, 0.0)), text_bbox(add(anchor, (25.0, 0.0)), label), -9999.0, "forced:no-candidates", "right")
            quality, reason = placement_quality(candidate)
            placement = Placement(
                f"PLC-{len(placements) + 1}",
                source.source_id,
                source.handle,
                source.family,
                source.subtype,
                sheet_id,
                label,
                candidate.anchor,
                candidate.text_point,
                candidate.text_bbox,
                quality,
                reason,
                candidate.score,
                render_mode,
                text_rotation,
                output_layer,
            )
            placements.append(placement)
            occupied.append(Blocker(placement.placement_id, CALLOUT_LAYER, "PLANNED-CALLOUT", "existing-callout", placement.text_bbox))

    return tuple(placements)


def build_plan(ms: Any, families: set[str] | None = None) -> PlanResult:
    sources, sheets, blockers = collect_geometry(ms)
    placements = plan_callouts(sources, sheets, blockers, families=families)
    return PlanResult(sources, sheets, blockers, placements)


def lisp_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lisp_path(path: Path) -> str:
    return path.resolve().as_posix()


def quality_layer(quality: str) -> str:
    return REVIEW_LAYER if quality in {"warn", "forced"} else ""


def placement_lisp(placement: Placement) -> str:
    if placement.render_mode == "filled-text":
        width = placement.text_bbox[2] - placement.text_bbox[0]
        return (
            f"(bscf-place-filled-text {placement.text_point[0]:.8f} {placement.text_point[1]:.8f} "
            f"{width:.8f} {placement.text_rotation:.8f} "
            f"{lisp_string(placement.output_layer)} "
            f"{lisp_string(placement.label)} {lisp_string(placement.source_handle)} "
            f"{lisp_string(placement.sheet_id)} {lisp_string(placement.family)} "
            f"{lisp_string(placement.quality)} {lisp_string(placement.reason)})"
        )
    if placement.render_mode == "stationing-text":
        width = placement.text_bbox[2] - placement.text_bbox[0]
        return (
            f"(bscf-place-station-text {placement.text_point[0]:.8f} {placement.text_point[1]:.8f} "
            f"{width:.8f} {placement.text_rotation:.8f} "
            f"{lisp_string(placement.output_layer)} "
            f"{lisp_string(placement.label)} {lisp_string(placement.source_handle)} "
            f"{lisp_string(placement.sheet_id)} {lisp_string(placement.family)} "
            f"{lisp_string(placement.quality)} {lisp_string(placement.reason)})"
        )
    return (
        f"(bscf-place-route-leader {placement.anchor[0]:.8f} {placement.anchor[1]:.8f} "
        f"{placement.text_point[0]:.8f} {placement.text_point[1]:.8f} "
        f"{lisp_string(placement.label)} {lisp_string(placement.source_handle)} "
        f"{lisp_string(placement.sheet_id)} {lisp_string(placement.family)} "
        f"{lisp_string(placement.quality)} {lisp_string(placement.reason)})"
    )


def write_run_lisp(plan: PlanResult, output_path: Path = RUN_LISP_PATH) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    helper = lisp_path(LISP_HELPER_PATH)
    lines = [
        ";;; Auto-generated by bscallouts_forced.py.",
        ";;; Places every planned callout; quality only controls review markers.",
        "",
        "(vl-load-com)",
        f"(load {lisp_string(helper)})",
        "",
        "(defun bscf-ensure-layer (name / doc layers lay)",
        "  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))",
        "  (setq layers (vla-get-Layers doc))",
        "  (setq lay (vl-catch-all-apply 'vla-Item (list layers name)))",
        "  (if (vl-catch-all-error-p lay) (setq lay (vla-Add layers name)))",
        "  (vl-catch-all-apply 'vlax-put-property (list lay 'LayerOn :vlax-true))",
        "  (vl-catch-all-apply 'vlax-put-property (list lay 'Freeze :vlax-false))",
        "  (vl-catch-all-apply 'vlax-put-property (list lay 'Lock :vlax-false))",
        "  (vl-catch-all-apply 'vlax-put-property (list lay 'Plottable :vlax-true))",
        "  lay)",
        "",
        "(defun bscf-safe-set (obj prop value /)",
        "  (vl-catch-all-apply 'vlax-put-property (list obj prop value)))",
        "",
        "(defun bscf-tag (handle source sheet family quality label / ent edata)",
        "  (if (and handle (handent handle))",
        "    (progn",
        "      (regapp \"BSCALLOUTS\")",
        "      (setq ent (handent handle))",
        "      (setq edata (entget ent))",
        "      (entmod",
        "        (append edata",
        "          (list",
        "            (list -3",
        "              (list \"BSCALLOUTS\"",
        "                (cons 1000 source)",
        "                (cons 1000 sheet)",
        "                (cons 1000 family)",
        "                (cons 1000 quality)",
        "                (cons 1000 label))))))))",
        "  handle)",
        "",
        "(defun bscf-review-fill (x1 y1 x2 y2 / ent)",
        f"  (bscf-ensure-layer {lisp_string(REVIEW_LAYER)})",
        "  (setq ent",
        "    (entmakex",
        "      (list",
        "        '(0 . \"SOLID\")",
        f"        (cons 8 {lisp_string(REVIEW_LAYER)})",
        "        '(62 . 2)",
        "        (cons 10 (list x1 y1 0.0))",
        "        (cons 11 (list x2 y1 0.0))",
        "        (cons 12 (list x1 y2 0.0))",
        "        (cons 13 (list x2 y2 0.0)))))",
        "  ent)",
        "",
        "(defun bscf-place-route-leader (ax ay tx ty label source sheet family quality reason / result box)",
        f"  (bscf-ensure-layer {lisp_string(CALLOUT_LAYER)})",
        "  (setq result (bscw-place-mleader ax ay tx ty label \"CABLE CALLOUTS\"))",
        "  (if (and result (handent result))",
        "    (progn",
        "      (bscf-tag result source sheet family quality label)",
        "      (if (/= quality \"clean\")",
        "        (progn",
        "          (setq box (bscw-last-text-box))",
        "          (if box",
        "            (progn",
        "              (bscf-review-fill (nth 0 box) (nth 1 box) (nth 2 box) (nth 3 box))",
        "              (vl-cmdf \"_.DRAWORDER\" (handent result) \"\" \"F\")))))",
        "      result)",
        "    nil))",
        "",
        "(defun bscf-text-fill (tx ty width height layer color / ent)",
        "  (setq ent",
        "    (entmakex",
        "      (list",
        "        '(0 . \"SOLID\")",
        "        (cons 8 layer)",
        "        (cons 62 color)",
        "        (cons 10 (list (- tx (/ width 2.0)) (- ty (/ height 2.0)) 0.0))",
        "        (cons 11 (list (+ tx (/ width 2.0)) (- ty (/ height 2.0)) 0.0))",
        "        (cons 12 (list (- tx (/ width 2.0)) (+ ty (/ height 2.0)) 0.0))",
        "        (cons 13 (list (+ tx (/ width 2.0)) (+ ty (/ height 2.0)) 0.0)))))",
        "  ent)",
        "",
        "(defun bscf-place-filled-text (tx ty width rotation layer label source sheet family quality reason / fill-color fill-layer ent handle)",
        "  (bscf-ensure-layer layer)",
        f"  (bscf-ensure-layer {lisp_string(REVIEW_LAYER)})",
        "  (setq fill-color (if (/= quality \"clean\") 2 7))",
        "  (setq fill-layer (if (/= quality \"clean\") \"BS-CALLOUT-REVIEW\" layer))",
        "  (bscf-text-fill tx ty width 12.5 fill-layer fill-color)",
        "  (setq ent",
        "    (entmakex",
        "      (list",
        "        '(0 . \"TEXT\")",
        "        '(100 . \"AcDbEntity\")",
        "        (cons 8 layer)",
        "        '(100 . \"AcDbText\")",
        "        (cons 10 (list tx ty 0.0))",
        "        (cons 11 (list tx ty 0.0))",
        "        '(40 . 5.0)",
        "        (cons 1 label)",
        "        (cons 50 rotation)",
        "        '(7 . \"STANDARD\")",
        "        '(72 . 1)",
        "        '(73 . 2))))",
        "  (if ent",
        "    (progn",
        "      (setq handle (cdr (assoc 5 (entget ent))))",
        "      (bscf-tag handle source sheet family quality label)",
        "      (vl-cmdf \"_.DRAWORDER\" ent \"\" \"F\")",
        "      handle)",
        "    nil))",
        "",
        "(defun bscf-place-station-text (tx ty width rotation layer label source sheet family quality reason / doc ms fill-color bg obj handle)",
        "  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))",
        "  (setq ms (vla-get-ModelSpace doc))",
        "  (bscf-ensure-layer layer)",
        f"  (bscf-ensure-layer {lisp_string(REVIEW_LAYER)})",
        "  (setq bg (if (/= quality \"clean\") \"BS-CALLOUT-REVIEW\" layer))",
        "  (setq fill-color (if (/= quality \"clean\") 2 7))",
        "  (bscf-text-fill tx ty width 12.5 bg fill-color)",
        "  (setq obj (vla-AddMText ms (vlax-3d-point (list tx ty 0.0)) width label))",
        "  (bscf-safe-set obj 'Layer layer)",
        "  (bscf-safe-set obj 'AttachmentPoint 5)",
        "  (bscf-safe-set obj 'Height 5.0)",
        "  (bscf-safe-set obj 'Rotation rotation)",
        "  (bscf-safe-set obj 'BackgroundFill :vlax-true)",
        "  (bscf-safe-set obj 'UseBackgroundColor :vlax-false)",
        "  (bscf-safe-set obj 'BackgroundScaleFactor 1.1)",
        "  (bscf-safe-set obj 'LineSpacingDistance 5.0)",
        "  (bscf-safe-set obj 'StyleName \"STANDARD\")",
        "  (setq handle (vla-get-Handle obj))",
        "  (bscf-tag handle source sheet family quality label)",
        "  (vl-cmdf \"_.DRAWORDER\" (handent handle) \"\" \"F\")",
        "  handle)",
        "",
        "(defun c:BSCALLOUTS-FORCED-APPLY (/ doc olderr placed expected result)",
        "  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))",
        "  (setq olderr *error*)",
        "  (defun *error* (msg)",
        "    (if doc (vl-catch-all-apply 'vla-EndUndoMark (list doc)))",
        "    (setvar \"USERS1\" (strcat \"BSCALLOUTS_FORCED_ERROR:\" (if msg msg \"unknown\")))",
        "    (setq *error* olderr)",
        "    (if (and msg (/= msg \"Function cancelled\")) (princ (strcat \"\\n[BSCALLOUTS-FORCED] Error: \" msg)))",
        "    (princ))",
        f"  (setq expected {len(plan.placements)})",
        "  (setq placed 0)",
        "  (setvar \"USERS1\" \"BSCALLOUTS_FORCED_RUNNING\")",
        "  (vla-StartUndoMark doc)",
    ]
    for placement in plan.placements:
        lines.append(f"  ;; {placement.placement_id} source={placement.source_handle} sheet={placement.sheet_id} quality={placement.quality}")
        lines.append(f"  (setq result {placement_lisp(placement)})")
        lines.append("  (if (and result (handent result)) (setq placed (1+ placed)))")
    lines.extend(
        [
            "  (vla-EndUndoMark doc)",
            "  (vla-Regen doc 1)",
            "  (setvar \"USERS1\" (strcat \"BSCALLOUTS_FORCED_DONE:\" (itoa placed) \"/\" (itoa expected)))",
            "  (setq *error* olderr)",
            "  (princ (strcat \"\\n[BSCALLOUTS-FORCED] Placed \" (itoa placed) \"/\" (itoa expected) \" callouts.\"))",
            "  (princ))",
            "",
            "(princ \"\\n[BSCALLOUTS-FORCED] Loaded. Run BSCALLOUTS-FORCED-APPLY.\")",
            "(princ)",
            "",
        ]
    )
    output_path.write_text("\n".join(lines), encoding="ascii")
    return output_path


def write_reports(plan: PlanResult) -> tuple[Path, Path, Path]:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    PLAN_JSON_PATH.write_text(json.dumps(asdict(plan), indent=2), encoding="utf-8")

    with PLAN_CSV_PATH.open("w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(
            csvfile,
            fieldnames=[
                "placement_id",
                "source_handle",
                "family",
                "subtype",
                "sheet_id",
                "quality",
                "score",
                "reason",
                "render_mode",
                "text_rotation_deg",
                "output_layer",
                "anchor_x",
                "anchor_y",
                "text_x",
                "text_y",
                "label",
            ],
        )
        writer.writeheader()
        for item in plan.placements:
            writer.writerow(
                {
                    "placement_id": item.placement_id,
                    "source_handle": item.source_handle,
                    "family": item.family,
                    "subtype": item.subtype,
                    "sheet_id": item.sheet_id,
                    "quality": item.quality,
                    "score": f"{item.score:.2f}",
                    "reason": item.reason,
                    "render_mode": item.render_mode,
                    "text_rotation_deg": f"{math.degrees(item.text_rotation):.2f}",
                    "output_layer": item.output_layer,
                    "anchor_x": f"{item.anchor[0]:.4f}",
                    "anchor_y": f"{item.anchor[1]:.4f}",
                    "text_x": f"{item.text_point[0]:.4f}",
                    "text_y": f"{item.text_point[1]:.4f}",
                    "label": item.label,
                }
            )

    clean = sum(1 for item in plan.placements if item.quality == "clean")
    warn = sum(1 for item in plan.placements if item.quality == "warn")
    forced = sum(1 for item in plan.placements if item.quality == "forced")
    lines = [
        "# BSCALLOUTS Forced Placement Report",
        "",
        f"- Sources found: `{len(plan.sources)}`",
        f"- BORDER sheets found: `{len(plan.sheets)}`",
        f"- Blockers found: `{len(plan.blockers)}`",
        f"- Required callouts planned: `{len(plan.placements)}`",
        f"- Clean placements: `{clean}`",
        f"- Warn placements: `{warn}`",
        f"- Forced placements: `{forced}`",
        f"- Plan JSON: `{PLAN_JSON_PATH}`",
        f"- Plan CSV: `{PLAN_CSV_PATH}`",
        f"- Run LISP: `{RUN_LISP_PATH}`",
        "",
        "| Placement | Source | Family | Sheet | Quality | Score | Reason | Anchor | Text | Label |",
        "|---|---|---|---|---|---:|---|---|---|---|",
    ]
    for item in plan.placements:
        lines.append(
            f"| {item.placement_id} | {item.source_handle} | {item.family}/{item.subtype} | {item.sheet_id} | {item.quality} | {item.score:.1f} | {item.reason.replace('|', '/')} | ({item.anchor[0]:.2f}, {item.anchor[1]:.2f}) | ({item.text_point[0]:.2f}, {item.text_point[1]:.2f}) | {item.label} |"
        )
    REPORT_MD_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return PLAN_JSON_PATH, PLAN_CSV_PATH, REPORT_MD_PATH


def make_lisp_load_command(path: Path) -> str:
    return f"(load {lisp_string(lisp_path(path))})"


def wait_for_autocad(doc: Any, timeout: float = 30.0) -> None:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            if int(doc.GetVariable("CMDACTIVE")) == 0:
                time.sleep(0.15)
                return
        except Exception:
            pass
        time.sleep(0.1)


def send_command(doc: Any, expression: str) -> None:
    wait_for_autocad(doc, timeout=10.0)
    doc.SendCommand(expression.rstrip() + "\n")


def safe_set_variable(doc: Any, name: str, value: str) -> None:
    try:
        doc.SetVariable(name, value)
    except Exception:
        pass


def safe_get_variable(doc: Any, name: str) -> str:
    try:
        return str(doc.GetVariable(name))
    except Exception:
        return ""


def wait_for_marker(doc: Any, timeout: float = 300.0) -> str:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        marker = safe_get_variable(doc, "USERS1")
        if marker.startswith("BSCALLOUTS_FORCED_DONE:") or marker.startswith("BSCALLOUTS_FORCED_ERROR:"):
            return marker
        time.sleep(0.5)
    return safe_get_variable(doc, "USERS1")


def apply_plan(doc: Any, run_lisp_path: Path) -> str:
    if not LISP_HELPER_PATH.exists():
        raise SystemExit(f"Missing MLeader helper: {LISP_HELPER_PATH}")
    safe_set_variable(doc, "USERS1", "BSCALLOUTS_FORCED_LOADING")
    send_command(doc, make_lisp_load_command(run_lisp_path))
    wait_for_autocad(doc, timeout=15.0)
    safe_set_variable(doc, "USERS1", "BSCALLOUTS_FORCED_QUEUED")
    send_command(doc, "(c:BSCALLOUTS-FORCED-APPLY)")
    marker = wait_for_marker(doc)
    if marker.startswith("BSCALLOUTS_FORCED_ERROR:"):
        raise RuntimeError(f"AutoCAD reported: {marker}")
    return marker


def parse_families(raw: str | None) -> set[str] | None:
    if not raw:
        return None
    values = {norm(item) for item in raw.split(",") if norm(item)}
    aliases = {
        "structures": "structure",
        "handholes": "handhole",
        "borepits": "borepit",
        "min doc": "mindoc",
        "mindocs": "mindoc",
    }
    return {aliases.get(item, item) for item in values}


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yes", action="store_true", help="Do not prompt for drawing confirmation.")
    parser.add_argument("--run", action="store_true", help="Load the generated LISP and place every planned callout.")
    parser.add_argument("--audit-only", action="store_true", help="Plan and report only; do not generate/apply final callouts.")
    parser.add_argument("--families", help="Comma-separated family filter: structure,buried,aerial,mindoc.")
    return parser.parse_args(argv)


def confirm_document(doc: Any, yes: bool) -> None:
    name = safe_get(doc, "FullName", safe_get(doc, "Name", "<unknown>"))
    print(f"Active drawing: {name}")
    if yes:
        return
    answer = input("Use this drawing for forced callout placement? [y/N] ").strip().lower()
    if answer not in {"y", "yes"}:
        raise SystemExit("Cancelled.")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if not SHAPELY_AVAILABLE:
        print("Missing dependency. Install with: python -m pip install shapely pywin32")
        return 1

    acad, doc, ms = connect_autocad()
    _ = acad
    confirm_document(doc, args.yes)

    start = time.monotonic()
    families = parse_families(args.families)
    plan = build_plan(ms, families=families)
    run_lisp_path = write_run_lisp(plan)
    json_path, csv_path, report_path = write_reports(plan)

    clean = sum(1 for item in plan.placements if item.quality == "clean")
    warn = sum(1 for item in plan.placements if item.quality == "warn")
    forced = sum(1 for item in plan.placements if item.quality == "forced")
    print(f"Sources found: {len(plan.sources)}")
    print(f"BORDER sheets found: {len(plan.sheets)}")
    print(f"Blockers found: {len(plan.blockers)}")
    print(f"Required callouts planned: {len(plan.placements)}")
    print(f"Clean: {clean}  Warn: {warn}  Forced: {forced}")
    print(f"Plan JSON: {json_path}")
    print(f"Plan CSV: {csv_path}")
    print(f"Report: {report_path}")
    print(f"Run LISP: {run_lisp_path}")

    if args.audit_only:
        print("Audit-only mode. No final callouts placed.")
        return 0

    if args.run:
        print("Sending forced placement batch to AutoCAD...")
        marker = apply_plan(doc, run_lisp_path)
        print(f"AutoCAD result: {marker}")
    else:
        print("Plan-only mode. Rerun with --run to place every planned callout.")

    elapsed = int(round(time.monotonic() - start))
    print(f"Elapsed: {elapsed // 60:02d}:{elapsed % 60:02d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
