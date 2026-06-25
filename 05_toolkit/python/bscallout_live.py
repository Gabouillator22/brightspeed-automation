#!/usr/bin/env python3
"""Orchestrate live buried-fiber callouts in the active AutoCAD drawing."""

from __future__ import annotations

import argparse
import math
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Sequence

try:
    from shapely.geometry import LineString, Point, box

    SHAPELY_AVAILABLE = True
except ImportError:
    LineString = Point = box = None  # type: ignore[assignment]
    SHAPELY_AVAILABLE = False


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
LISP_HELPER_PATH = REPO_ROOT / "05_toolkit" / "lisp" / "working_commands" / "bscallout_place.lsp"
REPORT_PATH = SCRIPT_DIR / "reports" / "bscallout_live_report.md"

CALLOUT_LAYER = "CABLE CALLOUTS"
TEXT_HEIGHT = 5.0
ARROW_TOLERANCE = 3.0
MIN_LENGTH_FT = 1.0
STRUCTURE_INSET_FT = 15.0
PLACEMENT_OFFSETS = (15.0, 22.0, 30.0, 40.0, 55.0, 70.0, 90.0, 115.0)
PLACEMENT_SHIFTS = (0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 70.0, -70.0)
TEXT_WIDTH_FACTOR = 0.65
TEXT_MIN_WIDTH = 70.0
TEXT_BOX_HEIGHT_FACTOR = 1.8
PYTHONCOM: Any | None = None

BURIED_OBJECTS = {"acdbline", "acdbpolyline", "acdblrwpolyline", "acdb2dpolyline", "acdb3dpolyline"}
BURIED_LAYERS = {"buried fiber in duct", "buried fiber", "proposed buried", "underground"}
ROAD_LAYER_TERMS = ("cl", "centerline", "road-centerline", "eop", "row", "r/w", "row-trap", "roads-paved")
BLOCKER_LAYER_TERMS = (
    "cl",
    "centerline",
    "road-centerline",
    "eop",
    "row",
    "r/w",
    "row-trap",
    "property",
    "parcel",
    "dim",
    "road names",
    "street",
    "cable callouts",
    "handhole",
    "bore",
    "pole",
    "gps",
)
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


@dataclass(frozen=True)
class SourceSegment:
    index: int
    handle: str
    object_name: str
    layer: str
    points: list[tuple[float, float]]
    length: float
    bbox: tuple[float, float, float, float]
    line: Any


@dataclass(frozen=True)
class BorderRegion:
    border_id: str
    handle: str
    bbox: tuple[float, float, float, float]
    polygon: Any


@dataclass(frozen=True)
class Blocker:
    handle: str
    object_name: str
    layer: str
    bbox: tuple[float, float, float, float]
    category: str


@dataclass(frozen=True)
class Candidate:
    number: int
    side: str
    offset: float
    shift: float
    anchor: tuple[float, float]
    text_point: tuple[float, float]
    text_bbox: tuple[float, float, float, float]
    score: float
    reason: str


@dataclass
class CalloutPlan:
    source: SourceSegment
    border: BorderRegion | None
    border_id: str
    full_text: str
    anchor: tuple[float, float]
    tangent: tuple[float, float]
    candidates: list[Candidate]
    candidate_results: list["AttemptResult"] = field(default_factory=list)
    final_status: str = "PENDING"
    final_reason: str = ""
    created_handle: str = ""


@dataclass
class AttemptResult:
    candidate_number: int
    status: str
    reason: str
    handle: str = ""
    lisp_result: str = ""


def normalize_layer(name: str) -> str:
    return re.sub(r"\s+", " ", (name or "").replace("_", " ").strip()).lower()


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


def normalize(v: Sequence[float]) -> tuple[float, float]:
    length = math.hypot(float(v[0]), float(v[1]))
    if length <= 1e-9:
        return (1.0, 0.0)
    return (float(v[0]) / length, float(v[1]) / length)


def perp_left(v: Sequence[float]) -> tuple[float, float]:
    u = normalize(v)
    return (-u[1], u[0])


def perp_right(v: Sequence[float]) -> tuple[float, float]:
    u = normalize(v)
    return (u[1], -u[0])


def polyline_length(points: Sequence[Sequence[float]]) -> float:
    return sum(distance(a, b) for a, b in zip(points, points[1:]))


def point_at_distance(points: Sequence[Sequence[float]], target: float) -> tuple[float, float]:
    if not points:
        raise ValueError("point_at_distance requires points")
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


def midpoint_on_polyline(points: Sequence[Sequence[float]]) -> tuple[float, float]:
    return point_at_distance(points, polyline_length(points) / 2.0)


def tangent_at_distance(points: Sequence[Sequence[float]], target: float) -> tuple[float, float]:
    walked = 0.0
    for a, b in zip(points, points[1:]):
        seg_len = distance(a, b)
        if seg_len <= 1e-9:
            continue
        if walked + seg_len >= target:
            return normalize(sub(b, a))
        walked += seg_len
    if len(points) >= 2:
        return normalize(sub(points[-1], points[-2]))
    return (1.0, 0.0)


def bbox_from_points(points: Sequence[Sequence[float]]) -> tuple[float, float, float, float]:
    xs = [float(p[0]) for p in points]
    ys = [float(p[1]) for p in points]
    return (min(xs), min(ys), max(xs), max(ys))


def bbox_intersects(a: tuple[float, float, float, float], b: tuple[float, float, float, float], pad: float = 0.0) -> bool:
    return not (a[2] + pad < b[0] or b[2] + pad < a[0] or a[3] + pad < b[1] or b[3] + pad < a[1])


def bbox_contains(inner: tuple[float, float, float, float], outer: tuple[float, float, float, float], pad: float = 0.0) -> bool:
    return inner[0] >= outer[0] - pad and inner[1] >= outer[1] - pad and inner[2] <= outer[2] + pad and inner[3] <= outer[3] + pad


def bbox_center(bbox: tuple[float, float, float, float]) -> tuple[float, float]:
    return ((bbox[0] + bbox[2]) / 2.0, (bbox[1] + bbox[3]) / 2.0)


def bbox_for_text(point: Sequence[float], text: str, height: float = TEXT_HEIGHT, align: str = "left") -> tuple[float, float, float, float]:
    width = max(TEXT_MIN_WIDTH, len(text) * height * TEXT_WIDTH_FACTOR)
    half_h = height * TEXT_BOX_HEIGHT_FACTOR / 2.0
    x, y = float(point[0]), float(point[1])
    if align == "right":
        return (x - width, y - half_h, x, y + half_h)
    return (x, y - half_h, x + width, y + half_h)


def format_buried_text(length_ft: float) -> str:
    return f'HDD BORE {int(round(length_ft))}\' FIBER IN 2" DUCT'


def flatten_xy(values: Iterable[Any], stride: int) -> list[tuple[float, float]]:
    raw = list(values)
    return [(float(raw[i]), float(raw[i + 1])) for i in range(0, len(raw) - 1, stride)]


def safe_get(obj: Any, prop: str, default: Any = None) -> Any:
    try:
        return getattr(obj, prop)
    except Exception:
        return default


def object_handle(obj: Any) -> str:
    handle = safe_get(obj, "Handle", "")
    return str(handle) if handle else ""


def object_name(obj: Any) -> str:
    return str(safe_get(obj, "ObjectName", ""))


def entity_bbox(entity: Any) -> tuple[float, float, float, float] | None:
    try:
        lo, hi = entity.GetBoundingBox()
        return (float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1]))
    except Exception:
        return None


def modelspace_handles(ms: Any) -> set[str]:
    handles: set[str] = set()
    for obj in iter_modelspace(ms):
        handle = object_handle(obj)
        if handle:
            handles.add(handle)
    return handles


def iter_modelspace(ms: Any) -> Iterable[Any]:
    count = int(safe_get(ms, "Count", 0))
    for index in range(count):
        try:
            yield ms.Item(index)
        except Exception:
            continue


def entity_points(entity: Any) -> list[tuple[float, float]]:
    name = object_name(entity).lower()
    if name == "acdbline":
        return [xy(entity.StartPoint), xy(entity.EndPoint)]
    coords = safe_get(entity, "Coordinates")
    if coords is not None:
        if name in {"acdbpolyline", "acdblrwpolyline", "acdb2dpolyline"}:
            return flatten_xy(coords, 2)
        if name == "acdb3dpolyline":
            return flatten_xy(coords, 3)
        pts = flatten_xy(coords, 2)
        if len(pts) >= 2:
            return pts
    return []


def connect_autocad() -> tuple[Any, Any, Any]:
    global PYTHONCOM
    try:
        import pythoncom  # type: ignore
        import win32com.client  # type: ignore
    except ImportError as exc:
        raise SystemExit("Missing dependency. Install with: python -m pip install pywin32 shapely") from exc
    pythoncom.CoInitialize()
    PYTHONCOM = pythoncom
    try:
        acad = win32com.client.GetActiveObject("AutoCAD.Application")
    except Exception as exc:
        raise SystemExit("AutoCAD is not running or not available through COM. Open AutoCAD and a drawing first.") from exc
    doc = acad.ActiveDocument
    return acad, doc, doc.ModelSpace


def pump_com_messages() -> None:
    if PYTHONCOM is None:
        return
    try:
        PYTHONCOM.PumpWaitingMessages()
    except Exception:
        pass


def send_command(doc: Any, expression: str) -> None:
    command = expression.rstrip() + "\n"
    last_error: Exception | None = None
    wait_for_autocad(doc, timeout=5.0)
    for _ in range(80):
        try:
            doc.SendCommand(command)
            return
        except Exception as exc:
            last_error = exc
            pump_com_messages()
            time.sleep(0.25)
    raise RuntimeError(f"AutoCAD rejected SendCommand after retries: {last_error}")


def wait_for_autocad(doc: Any, timeout: float = 20.0) -> None:
    end = time.time() + timeout
    while time.time() < end:
        try:
            if int(doc.GetVariable("CMDACTIVE")) == 0:
                time.sleep(0.15)
                return
        except Exception:
            pass
        pump_com_messages()
        time.sleep(0.1)


def load_lisp(doc: Any) -> None:
    if not LISP_HELPER_PATH.exists():
        raise SystemExit(f"Missing LISP helper: {LISP_HELPER_PATH}")
    path = LISP_HELPER_PATH.as_posix()
    print(f"Loading LISP helper: {LISP_HELPER_PATH}")
    send_command(doc, f'(load "{path}")')
    wait_for_autocad(doc, timeout=10.0)


def is_buried_source(entity: Any) -> bool:
    if object_name(entity).lower() not in BURIED_OBJECTS:
        return False
    return normalize_layer(str(safe_get(entity, "Layer", ""))) in BURIED_LAYERS


def collect_sources(ms: Any) -> list[SourceSegment]:
    sources: list[SourceSegment] = []
    for obj in iter_modelspace(ms):
        if not is_buried_source(obj):
            continue
        points = entity_points(obj)
        if len(points) < 2:
            continue
        length = polyline_length(points)
        bbox = entity_bbox(obj) or bbox_from_points(points)
        sources.append(
            SourceSegment(
                index=len(sources) + 1,
                handle=object_handle(obj),
                object_name=object_name(obj),
                layer=str(safe_get(obj, "Layer", "")),
                points=points,
                length=length,
                bbox=bbox,
                line=LineString(points),
            )
        )
    return sources


def collect_borders(ms: Any) -> list[BorderRegion]:
    borders: list[BorderRegion] = []
    seen: set[tuple[int, int, int, int]] = set()
    for obj in iter_modelspace(ms):
        if normalize_layer(str(safe_get(obj, "Layer", ""))) != "border":
            continue
        bbox = entity_bbox(obj)
        if not bbox:
            continue
        key = tuple(int(round(v)) for v in bbox)
        if key in seen:
            continue
        seen.add(key)
        borders.append(BorderRegion(f"BORDER-{len(borders) + 1}", object_handle(obj), bbox, box(*bbox)))
    return borders


def blocker_category(entity: Any) -> str | None:
    name = object_name(entity).lower()
    layer = normalize_layer(str(safe_get(entity, "Layer", "")))
    if name not in BLOCKER_OBJECTS:
        return None
    if normalize_layer(CALLOUT_LAYER) == layer:
        return "existing-callout"
    if any(term in layer for term in ROAD_LAYER_TERMS):
        return "road"
    if any(term in layer for term in BLOCKER_LAYER_TERMS):
        return "blocker"
    if name in {"acdbtext", "acdbmtext", "acdbdimension", "acdbmleader", "acdbleader", "acdbblockreference"}:
        return "blocker"
    return None


def collect_blockers(ms: Any) -> list[Blocker]:
    blockers: list[Blocker] = []
    for obj in iter_modelspace(ms):
        category = blocker_category(obj)
        if not category:
            continue
        bbox = entity_bbox(obj)
        if not bbox:
            continue
        blockers.append(Blocker(object_handle(obj), object_name(obj), str(safe_get(obj, "Layer", "")), bbox, category))
    return blockers


def matching_borders(source: SourceSegment, borders: Sequence[BorderRegion], no_sheet_repeat: bool) -> list[BorderRegion]:
    if no_sheet_repeat or not borders:
        return []
    matches: list[BorderRegion] = []
    for border in borders:
        if not bbox_intersects(source.bbox, border.bbox, pad=0.1):
            continue
        try:
            if source.line.intersects(border.polygon):
                matches.append(border)
        except Exception:
            matches.append(border)
    return matches


def anchor_for(source: SourceSegment, border: BorderRegion | None) -> tuple[tuple[float, float], tuple[float, float]]:
    if border is not None:
        try:
            clipped = source.line.intersection(border.polygon)
            if not clipped.is_empty and clipped.geom_type == "LineString" and clipped.length > 0:
                pts = [(float(x), float(y)) for x, y in clipped.coords]
                anchor = midpoint_on_polyline(pts)
                return anchor, tangent_at_distance(pts, polyline_length(pts) / 2.0)
            if not clipped.is_empty and clipped.geom_type == "MultiLineString":
                longest = max(clipped.geoms, key=lambda g: g.length)
                pts = [(float(x), float(y)) for x, y in longest.coords]
                anchor = midpoint_on_polyline(pts)
                return anchor, tangent_at_distance(pts, polyline_length(pts) / 2.0)
        except Exception:
            pass
    if source.length > STRUCTURE_INSET_FT * 2.0:
        anchor_distance = max(STRUCTURE_INSET_FT, min(source.length / 2.0, source.length - STRUCTURE_INSET_FT))
    else:
        anchor_distance = source.length / 2.0
    return point_at_distance(source.points, anchor_distance), tangent_at_distance(source.points, anchor_distance)


def score_candidate(
    candidate: Candidate,
    border: BorderRegion | None,
    blockers: Sequence[Blocker],
) -> tuple[float, str]:
    score = 1000.0 - candidate.offset - abs(candidate.shift) * 0.1
    reasons: list[str] = []
    if border is not None and not bbox_contains(candidate.text_bbox, border.bbox, pad=1.0):
        return -1e9, "outside-border"
    for blocker in blockers:
        if not bbox_intersects(candidate.text_bbox, blocker.bbox, pad=2.0):
            continue
        if blocker.category == "road":
            score -= 900.0
            reasons.append(f"road:{blocker.handle}")
        else:
            score -= 250.0
            reasons.append(f"blocker:{blocker.handle}")
    return score, ",".join(reasons) if reasons else "clear"


def make_candidates(anchor: tuple[float, float], tangent: tuple[float, float], text: str, border: BorderRegion | None, blockers: Sequence[Blocker]) -> list[Candidate]:
    raw: list[Candidate] = []
    number = 1
    for side_name, perp in (("left", perp_left(tangent)), ("right", perp_right(tangent))):
        align = "right" if side_name == "left" else "left"
        for offset in PLACEMENT_OFFSETS:
            for shift in PLACEMENT_SHIFTS:
                text_point = add(add(anchor, scale(perp, offset)), scale(tangent, shift))
                bbox = bbox_for_text(text_point, text, align=align)
                placeholder = Candidate(number, side_name, offset, shift, anchor, text_point, bbox, 0.0, "")
                score, reason = score_candidate(placeholder, border, blockers)
                raw.append(Candidate(number, side_name, offset, shift, anchor, text_point, bbox, score, reason))
                number += 1
    raw.sort(key=lambda c: c.score, reverse=True)
    return raw


def make_lisp_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lisp_place_expression(anchor: tuple[float, float], text_point: tuple[float, float], text: str) -> str:
    return (
        f"(bscw-place-mleader {anchor[0]:.8f} {anchor[1]:.8f} "
        f"{text_point[0]:.8f} {text_point[1]:.8f} {make_lisp_string(text)} {make_lisp_string(CALLOUT_LAYER)})"
    )


def new_objects_after(ms: Any, before: set[str]) -> list[Any]:
    objects: list[Any] = []
    for obj in iter_modelspace(ms):
        handle = object_handle(obj)
        if handle and handle not in before:
            objects.append(obj)
    return objects


def handle_to_object(doc: Any, handle: str) -> Any | None:
    try:
        return doc.HandleToObject(handle)
    except Exception:
        return None


def delete_handle(doc: Any, handle: str) -> None:
    obj = handle_to_object(doc, handle)
    if obj is not None:
        try:
            obj.Delete()
        except Exception:
            pass


def zoom_to_plan(doc: Any, plan: CalloutPlan, candidate: Candidate) -> None:
    bbox = plan.source.bbox
    tb = candidate.text_bbox
    combined = (
        min(bbox[0], tb[0]) - 50.0,
        min(bbox[1], tb[1]) - 50.0,
        max(bbox[2], tb[2]) + 50.0,
        max(bbox[3], tb[3]) + 50.0,
    )
    try:
        doc.Application.ZoomWindow((combined[0], combined[1], 0.0), (combined[2], combined[3], 0.0))
    except Exception:
        pass


def validate_callout(obj: Any, plan: CalloutPlan, candidate: Candidate, blockers: Sequence[Blocker]) -> tuple[bool, str]:
    if obj is None:
        return False, "no-created-object"
    if "mleader" not in object_name(obj).lower():
        return False, f"not-multileader:{object_name(obj)}"
    layer = normalize_layer(str(safe_get(obj, "Layer", "")))
    if layer != normalize_layer(CALLOUT_LAYER):
        return False, f"wrong-layer:{layer}"
    text = str(safe_get(obj, "TextString", ""))
    if plan.full_text not in text:
        return False, f"text-mismatch:{text}"
    bbox = entity_bbox(obj) or candidate.text_bbox
    if plan.border is not None and not bbox_contains(bbox, plan.border.bbox, pad=2.0):
        return False, "outside-border"
    for blocker in blockers:
        if blocker.category == "existing-callout":
            continue
        if bbox_intersects(candidate.text_bbox, blocker.bbox, pad=2.0):
            return False, f"candidate-collides-{blocker.category}:{blocker.handle}"
    return True, "valid"


def create_and_validate(doc: Any, ms: Any, plan: CalloutPlan, candidate: Candidate, blockers: Sequence[Blocker]) -> AttemptResult:
    before = modelspace_handles(ms)
    try:
        send_command(doc, lisp_place_expression(plan.anchor, candidate.text_point, plan.full_text))
        wait_for_autocad(doc)
    except Exception as exc:
        return AttemptResult(candidate.number, "RETRIED", f"send-command-failed:{exc}")
    created = new_objects_after(ms, before)
    if not created:
        return AttemptResult(candidate.number, "RETRIED", "lisp-created-no-object")
    mleaders = [obj for obj in created if "mleader" in object_name(obj).lower()]
    obj = mleaders[-1] if mleaders else created[-1]
    handle = object_handle(obj)
    valid, reason = validate_callout(obj, plan, candidate, blockers)
    if valid:
        return AttemptResult(candidate.number, "PLACED", reason, handle, "SUCCESS")
    if handle:
        delete_handle(doc, handle)
    return AttemptResult(candidate.number, "RETRIED", reason, handle, "INVALID")


def make_plan(source: SourceSegment, border: BorderRegion | None, blockers: Sequence[Blocker]) -> CalloutPlan:
    text = format_buried_text(source.length)
    anchor, tangent = anchor_for(source, border)
    candidates = make_candidates(anchor, tangent, text, border, blockers)
    return CalloutPlan(source, border, border.border_id if border else "GLOBAL", text, anchor, tangent, candidates)


@dataclass
class CalloutPlan:
    source: SourceSegment
    border: BorderRegion | None
    border_id: str
    full_text: str
    anchor: tuple[float, float]
    tangent: tuple[float, float]
    candidates: list[Candidate]
    attempts: list[AttemptResult] = field(default_factory=list)
    status: str = "PENDING"
    reason: str = ""
    handle: str = ""


def process_plan(doc: Any, ms: Any, plan: CalloutPlan, blockers: Sequence[Blocker], dry_run: bool, interactive: bool) -> bool:
    if dry_run:
        plan.status = "PLANNED"
        plan.reason = "dry-run"
        return True
    for candidate in plan.candidates:
        attempt = create_and_validate(doc, ms, plan, candidate, blockers)
        plan.attempts.append(attempt)
        if attempt.status != "PLACED":
            continue
        plan.status = "PLACED"
        plan.reason = attempt.reason
        plan.handle = attempt.handle
        if interactive:
            zoom_to_plan(doc, plan, candidate)
            print(f"Placed {plan.source.handle} {plan.border_id} candidate={candidate.number} handle={attempt.handle}")
            response = input("Accept this callout? [Y/r/s/q] ").strip().lower()
            if response in {"", "y", "yes"}:
                return True
            if response == "r":
                delete_handle(doc, attempt.handle)
                plan.status = "RETRIED"
                plan.reason = "user-retry"
                continue
            if response == "s":
                delete_handle(doc, attempt.handle)
                plan.status = "SKIPPED"
                plan.reason = "user-skip"
                return True
            if response == "q":
                raise KeyboardInterrupt
        return True
    plan.status = "FAILED"
    plan.reason = plan.attempts[-1].reason if plan.attempts else "no-candidates"
    return False


def write_report(doc: Any, plans: Sequence[CalloutPlan], borders: Sequence[BorderRegion], sources: Sequence[SourceSegment]) -> None:
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    placed = sum(1 for p in plans if p.status == "PLACED")
    failed = sum(1 for p in plans if p.status == "FAILED")
    skipped = sum(1 for p in plans if p.status == "SKIPPED")
    retries = sum(max(0, len(p.attempts) - (1 if p.status == "PLACED" else 0)) for p in plans)
    lines = [
        "# BSCALLOUT Live Report",
        "",
        f"- Drawing: `{safe_get(doc, 'Name', '<unknown>')}`",
        f"- Full path: `{safe_get(doc, 'FullName', '<unknown>')}`",
        f"- Buried source entities found: `{len(sources)}`",
        f"- BORDER sheets found: `{len(borders)}`",
        f"- Callout plans generated: `{len(plans)}`",
        f"- Callouts placed: `{placed}`",
        f"- Failed: `{failed}`",
        f"- Skipped: `{skipped}`",
        f"- Total retries: `{retries}`",
        "",
        "| Source | Layer | Type | Length | Border | Candidate | Anchor | Text | LISP | Validation | Status | Reason | Handle |",
        "|---|---|---|---:|---|---:|---|---|---|---|---|---|---|",
    ]
    for plan in plans:
        attempts = plan.attempts or [AttemptResult(0, plan.status, plan.reason, plan.handle, "")]
        for attempt in attempts:
            candidate = next((c for c in plan.candidates if c.number == attempt.candidate_number), None)
            text_pt = candidate.text_point if candidate else (0.0, 0.0)
            lines.append(
                "| {source} | {layer} | {otype} | {length:.1f} | {border} | {cand} | {anchor} | {text} | {lisp} | {validation} | {status} | {reason} | {handle} |".format(
                    source=plan.source.handle,
                    layer=plan.source.layer,
                    otype=plan.source.object_name,
                    length=plan.source.length,
                    border=plan.border_id,
                    cand=attempt.candidate_number,
                    anchor=f"({plan.anchor[0]:.2f}, {plan.anchor[1]:.2f})",
                    text=f"({text_pt[0]:.2f}, {text_pt[1]:.2f})",
                    lisp=attempt.lisp_result,
                    validation=attempt.status,
                    status=plan.status,
                    reason=attempt.reason.replace("|", "/"),
                    handle=attempt.handle,
                )
            )
    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.set_defaults(buried_only=True)
    parser.add_argument("--buried-only", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--max", type=int)
    parser.add_argument("--interactive-review", action="store_true")
    parser.add_argument("--no-sheet-repeat", action="store_true")
    parser.add_argument("--load-lisp", action="store_true")
    return parser.parse_args(argv)


def confirm_document(doc: Any, yes: bool) -> None:
    print(f"Active drawing: {safe_get(doc, 'Name', '<unknown>')}")
    print(f"Drawing path: {safe_get(doc, 'FullName', '<unknown>')}")
    if yes:
        return
    if input("Continue on this drawing? [y/N] ").strip().lower() not in {"y", "yes"}:
        raise SystemExit(1)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if not SHAPELY_AVAILABLE:
        print("Missing dependency. Install with: python -m pip install pywin32 shapely")
        return 1

    acad, doc, ms = connect_autocad()
    print(f"Connected to AutoCAD: {'yes' if acad else 'no'}")
    confirm_document(doc, args.yes)
    if not args.dry_run:
        load_lisp(doc)

    sources = collect_sources(ms)
    if args.max:
        sources = sources[: args.max]
    borders = collect_borders(ms)
    blockers = collect_blockers(ms)

    plans: list[CalloutPlan] = []
    for source in sources:
        matched = matching_borders(source, borders, args.no_sheet_repeat)
        targets: list[BorderRegion | None] = matched if matched else [None]
        for border in targets:
            plans.append(make_plan(source, border, blockers))

    total_retries = 0
    try:
        for plan in plans:
            print(f"Planning source={plan.source.handle} border={plan.border_id} length={plan.source.length:.1f}")
            process_plan(doc, ms, plan, blockers, args.dry_run, args.interactive_review)
            total_retries += max(0, len(plan.attempts) - (1 if plan.status == "PLACED" else 0))
    except KeyboardInterrupt:
        print("Quit requested. Writing report for completed attempts.")

    try:
        doc.Regen(1)
    except Exception:
        pass

    write_report(doc, plans, borders, sources)
    placed = sum(1 for p in plans if p.status == "PLACED")
    failed = sum(1 for p in plans if p.status == "FAILED")
    skipped = sum(1 for p in plans if p.status == "SKIPPED")
    print(f"Buried entities found: {len(sources)}")
    print(f"BORDERs found: {len(borders)}")
    print(f"Callout plans generated: {len(plans)}")
    print(f"Placed: {placed}")
    print(f"Failed: {failed}")
    print(f"Skipped: {skipped}")
    print(f"Total retries: {total_retries}")
    print(f"Report: {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
