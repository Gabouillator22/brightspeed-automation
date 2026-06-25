#!/usr/bin/env python3
"""Validate Brightspeed package sheet indexes and write package reports."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_CONFIG_PATH = Path(__file__).resolve().parents[1] / "config" / "bspackage_config.json"

DEFAULT_CONFIG: dict[str, Any] = {
    "plan_template_layout": "2",
    "number_layer": "BORDER",
    "sheet_rectangle_layers": ["BS-SHEET-PROPOSED", "BORDER"],
    "hidden_layer": "BS-SHEET-HIDDEN",
    "output_suffix": "_PACKAGED",
    "viewport_padding_ft": 50.0,
    "require_clean_index": True,
    "layout_name_mode": "sheet_number",
    "allow_sheet_number_gaps": False,
    "freeze_border_in_plan_viewports": True,
    "sheet_map_layouts": ["1", "Map", "MAP"],
    "profile_layouts": [],
    "max_pages_per_permit": 25,
    "sectioning_enabled": False,
    "first_plan_page_in_section": 2,
    "plan_slots_per_full_section": 24,
    "titleblock_update_enabled": True,
    "titleblock_block_name_patterns": ["*TITLE*", "*BORDER*", "*SQUAN*", "*BRIGHTSPEED*"],
    "titleblock_sheet_attribute_tags": ["SHEET", "SHT", "SHEET_NO", "SHEET_NUMBER", "PAGE"],
    "titleblock_total_attribute_tags": ["OF", "TOTAL", "TOTAL_SHEETS", "SHEET_TOTAL"],
    "titleblock_project_attribute_tags": ["PROJECT", "PROJECT_NO", "PERMIT", "PERMIT_NO"],
    "dry_run_default": True,
}


@dataclass(frozen=True)
class Rectangle:
    """Axis-aligned sheet rectangle from model space."""

    handle: str
    layer: str
    min_x: float
    min_y: float
    max_x: float
    max_y: float

    @property
    def center_x(self) -> float:
        return (self.min_x + self.max_x) / 2.0

    @property
    def center_y(self) -> float:
        return (self.min_y + self.max_y) / 2.0

    @property
    def width(self) -> float:
        return self.max_x - self.min_x

    @property
    def height(self) -> float:
        return self.max_y - self.min_y


@dataclass(frozen=True)
class NumberCandidate:
    """Parsed manual sheet number candidate."""

    handle: str
    entity_type: str
    text: str
    number: int
    x: float
    y: float


@dataclass(frozen=True)
class IndexedSheet:
    """Validated sheet index record."""

    sheet_number: int
    rectangle: Rectangle
    number_candidate: NumberCandidate
    confidence: str = "HIGH"


def load_config(path: Path) -> dict[str, Any]:
    """Load JSON config and merge with defaults."""
    config = DEFAULT_CONFIG.copy()
    if path.exists():
        with path.open("r", encoding="utf-8") as handle:
            config.update(json.load(handle))
    return config


def parse_sheet_number(text: str) -> int | None:
    """Parse a manual BORDER number or return None when ambiguous."""
    cleaned = " ".join(text.strip().upper().split())
    if not cleaned:
        return None
    if "/" in cleaned or " OF " in cleaned:
        return None
    groups = re.findall(r"\d+", cleaned)
    if len(groups) != 1:
        return None
    value = int(groups[0])
    return value if value > 0 else None


def point_in_rectangle(x: float, y: float, rectangle: Rectangle, tolerance: float = 0.0) -> bool:
    """Return True when the point falls inside the axis-aligned rectangle."""
    return (
        rectangle.min_x - tolerance <= x <= rectangle.max_x + tolerance
        and rectangle.min_y - tolerance <= y <= rectangle.max_y + tolerance
    )


def match_numbers_to_rectangles(
    rectangles: list[Rectangle],
    numbers: list[NumberCandidate],
    *,
    allow_sheet_number_gaps: bool = False,
    near_tolerance: float = 0.0,
) -> tuple[list[IndexedSheet], list[str]]:
    """Match one manual number to each rectangle and return validation errors."""
    errors: list[str] = []
    if not rectangles:
        return [], ["No sheet rectangles were provided."]
    if not numbers:
        return [], ["No manual BORDER numbers were provided."]

    by_rectangle: dict[str, list[NumberCandidate]] = {rect.handle: [] for rect in rectangles}
    seen_numbers: dict[int, str] = {}

    for candidate in numbers:
        containing = [
            rect for rect in rectangles if point_in_rectangle(candidate.x, candidate.y, rect)
        ]
        confidence = "HIGH"
        if not containing and near_tolerance > 0.0:
            containing = [
                rect
                for rect in rectangles
                if point_in_rectangle(candidate.x, candidate.y, rect, tolerance=near_tolerance)
            ]
            confidence = "LOW" if containing else confidence
        if len(containing) == 0:
            errors.append(
                f"Number {candidate.number} ({candidate.handle}) is outside every sheet rectangle."
            )
            continue
        if len(containing) > 1:
            errors.append(
                f"Number {candidate.number} ({candidate.handle}) falls inside multiple sheet rectangles."
            )
            continue
        if candidate.number in seen_numbers:
            errors.append(
                f"Duplicate sheet number {candidate.number} on {seen_numbers[candidate.number]} and {candidate.handle}."
            )
            continue
        seen_numbers[candidate.number] = candidate.handle
        rect = containing[0]
        assigned = list(by_rectangle[rect.handle])
        if confidence == "LOW":
            # Keep low-confidence order deterministic when mixed with exact hits.
            assigned.append(
                NumberCandidate(
                    handle=candidate.handle,
                    entity_type=candidate.entity_type,
                    text=f"{candidate.text}|LOW",
                    number=candidate.number,
                    x=candidate.x,
                    y=candidate.y,
                )
            )
        else:
            assigned.append(candidate)
        by_rectangle[rect.handle] = assigned

    sheets: list[IndexedSheet] = []
    for rect in rectangles:
        candidates = by_rectangle[rect.handle]
        if len(candidates) == 0:
            errors.append(f"Rectangle {rect.handle} has no manual BORDER number.")
            continue
        if len(candidates) > 1:
            numbers_list = ", ".join(str(item.number) for item in candidates)
            errors.append(f"Rectangle {rect.handle} has multiple manual numbers: {numbers_list}.")
            continue
        candidate = candidates[0]
        confidence = "LOW" if candidate.text.endswith("|LOW") else "HIGH"
        if confidence == "LOW":
            candidate = NumberCandidate(
                handle=candidate.handle,
                entity_type=candidate.entity_type,
                text=candidate.text[:-4],
                number=candidate.number,
                x=candidate.x,
                y=candidate.y,
            )
        sheets.append(IndexedSheet(candidate.number, rect, candidate, confidence))

    sheets.sort(key=lambda item: item.sheet_number)
    if sheets and not allow_sheet_number_gaps:
        expected = list(range(sheets[0].sheet_number, sheets[-1].sheet_number + 1))
        actual = [sheet.sheet_number for sheet in sheets]
        if actual != expected:
            missing = sorted(set(expected) - set(actual))
            errors.append(f"Missing sheet numbers: {', '.join(str(value) for value in missing)}.")
    return sheets, errors


def required_layout_names(sheet_numbers: list[int], layout_name_mode: str = "sheet_number") -> list[str]:
    """Return required layout names for the indexed sheets."""
    if layout_name_mode != "sheet_number":
        raise ValueError(f"Unsupported layout_name_mode: {layout_name_mode}")
    return [str(number) for number in sorted(sheet_numbers)]


def missing_layout_names(
    existing_layouts: list[str],
    required_numbers: list[int],
    layout_name_mode: str = "sheet_number",
) -> list[str]:
    """Return required layouts that do not already exist."""
    existing = {name.strip() for name in existing_layouts}
    return [
        name
        for name in required_layout_names(required_numbers, layout_name_mode)
        if name not in existing
    ]


def layout_plan(
    existing_layouts: list[str],
    required_numbers: list[int],
    template_layout: str,
    layout_name_mode: str = "sheet_number",
) -> list[dict[str, Any]]:
    """Return ordered layout actions for the package build."""
    existing = {name.strip() for name in existing_layouts}
    actions: list[dict[str, Any]] = []
    for number in sorted(required_numbers):
        layout_name = required_layout_names([number], layout_name_mode)[0]
        actions.append(
            {
                "sheet_number": number,
                "layout_name": layout_name,
                "template_layout": template_layout,
                "action": "keep" if layout_name in existing else "copy_template",
            }
        )
    return actions


def titleblock_page_values(
    sheet_number: int,
    total_sheet_count: int,
    config: dict[str, Any],
) -> dict[str, int]:
    """Return page/total values for title-block updates."""
    if not config.get("sectioning_enabled", False):
        return {
            "sheet_value": sheet_number,
            "total_value": total_sheet_count,
            "section_number": 1,
            "total_sections": 1,
        }

    slots = int(config["plan_slots_per_full_section"])
    first_plan_page = int(config["first_plan_page_in_section"])
    max_pages = int(config["max_pages_per_permit"])
    section_number = math.floor((sheet_number - 1) / slots) + 1
    sheet_index_in_section = ((sheet_number - 1) % slots) + 1
    remaining_including_current = max(0, total_sheet_count - ((section_number - 1) * slots))
    plan_pages_this_section = min(slots, remaining_including_current)
    return {
        "sheet_value": first_plan_page + sheet_index_in_section - 1,
        "total_value": min(max_pages, first_plan_page - 1 + plan_pages_this_section),
        "section_number": section_number,
        "total_sections": math.ceil(total_sheet_count / slots),
    }


def choose_output_dwg_path(
    source_path: Path,
    suffix: str,
    *,
    existing_paths: set[Path] | None = None,
    timestamp: str | None = None,
) -> Path:
    """Choose a packaged DWG path without silently overwriting an existing file."""
    existing_paths = existing_paths or set()
    base = source_path.with_name(f"{source_path.stem}{suffix}{source_path.suffix}")
    if base not in existing_paths and not base.exists():
        return base
    stamp = timestamp or datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    return source_path.with_name(f"{source_path.stem}{suffix}_{stamp}{source_path.suffix}")


def ensure_reports_dir(output_dwg: Path) -> Path:
    """Return the report folder for a packaged output."""
    return output_dwg.with_name(f"{output_dwg.stem}_reports")


def _json_default(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    """Write JSON with stable formatting."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=False, default=_json_default) + "\n", encoding="utf-8")


def write_sheet_index_csv(path: Path, sheets: list[dict[str, Any]]) -> None:
    """Write the sheet index CSV."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "sheet_number",
        "rectangle_handle",
        "rectangle_layer",
        "number_handle",
        "number_entity_type",
        "number_text",
        "confidence",
        "min_x",
        "min_y",
        "max_x",
        "max_y",
        "center_x",
        "center_y",
        "width",
        "height",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for sheet in sheets:
            bbox = sheet["bbox"]
            center = sheet["center"]
            writer.writerow(
                {
                    "sheet_number": sheet["sheet_number"],
                    "rectangle_handle": sheet["rectangle_handle"],
                    "rectangle_layer": sheet["rectangle_layer"],
                    "number_handle": sheet["number_handle"],
                    "number_entity_type": sheet["number_entity_type"],
                    "number_text": sheet["number_text"],
                    "confidence": sheet["confidence"],
                    "min_x": bbox["min_x"],
                    "min_y": bbox["min_y"],
                    "max_x": bbox["max_x"],
                    "max_y": bbox["max_y"],
                    "center_x": center["x"],
                    "center_y": center["y"],
                    "width": sheet["width"],
                    "height": sheet["height"],
                }
            )


def write_sheet_index_markdown(path: Path, payload: dict[str, Any]) -> None:
    """Write the human-readable sheet-index report."""
    path.parent.mkdir(parents=True, exist_ok=True)
    errors = payload.get("errors", [])
    warnings = payload.get("warnings", [])
    sheets = payload.get("sheets", [])
    lines = [
        "# Brightspeed Package Sheet Index",
        "",
        f"- Source DWG: `{payload.get('source_dwg', '')}`",
        f"- Template layout: `{payload.get('plan_template_layout', '')}`",
        f"- Sheets found: `{len(sheets)}`",
        f"- Status: `{'FAIL' if errors else 'PASS'}`",
        "",
    ]
    if errors:
        lines.extend(["## Errors", ""])
        lines.extend(f"- {item}" for item in errors)
        lines.append("")
    if warnings:
        lines.extend(["## Warnings", ""])
        lines.extend(f"- {item}" for item in warnings)
        lines.append("")
    lines.extend(["## Sheets", "", "| Sheet | Rect | Number | Layer | Confidence | Size |", "|---|---|---|---|---|---|"])
    for sheet in sheets:
        lines.append(
            "| {sheet} | `{rect}` | `{text}` | `{layer}` | `{confidence}` | `{width:.3f} x {height:.3f}` |".format(
                sheet=sheet["sheet_number"],
                rect=sheet["rectangle_handle"],
                text=sheet["number_text"],
                layer=sheet["rectangle_layer"],
                confidence=sheet["confidence"],
                width=float(sheet["width"]),
                height=float(sheet["height"]),
            )
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_package_build_markdown(path: Path, payload: dict[str, Any]) -> None:
    """Write the human-readable package-build report."""
    path.parent.mkdir(parents=True, exist_ok=True)
    errors = payload.get("errors", [])
    warnings = payload.get("warnings", [])
    layout_actions = payload.get("layout_actions", [])
    lines = [
        "# Brightspeed Package Build Report",
        "",
        f"- Source DWG: `{payload.get('source_dwg', '')}`",
        f"- Output DWG: `{payload.get('output_dwg', '')}`",
        f"- Template layout: `{payload.get('plan_template_layout', '')}`",
        f"- Dry run: `{payload.get('dry_run', False)}`",
        f"- Sheets found: `{payload.get('sheet_count', 0)}`",
        f"- Existing layouts: `{', '.join(payload.get('existing_layouts', [])) or 'none'}`",
        f"- Missing layouts created: `{payload.get('created_layout_count', 0)}`",
        f"- Viewports updated: `{payload.get('updated_viewport_count', 0)}`",
        f"- BORDER frozen in plan viewports: `{payload.get('border_freeze_attempted', False)}`",
        f"- Title block updates attempted: `{payload.get('titleblock_update_attempted', False)}`",
        f"- Final verdict: `{'FAIL' if errors else 'PASS'}`",
        "",
    ]
    if errors:
        lines.extend(["## Errors", ""])
        lines.extend(f"- {item}" for item in errors)
        lines.append("")
    if warnings:
        lines.extend(["## Warnings", ""])
        lines.extend(f"- {item}" for item in warnings)
        lines.append("")
    lines.extend(["## Layout Actions", "", "| Sheet | Layout | Action | Viewport |", "|---|---|---|---|"])
    for action in layout_actions:
        lines.append(
            "| {sheet} | `{layout}` | `{kind}` | `{viewport}` |".format(
                sheet=action.get("sheet_number", ""),
                layout=action.get("layout_name", ""),
                kind=action.get("action", ""),
                viewport=action.get("viewport_handle", ""),
            )
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_index_outputs(payload: dict[str, Any], out_dir: Path) -> None:
    """Write the sheet-index artifacts."""
    sheets = payload.get("sheets", [])
    write_json(out_dir / "sheet_index.json", payload)
    write_sheet_index_csv(out_dir / "sheet_index.csv", sheets)
    write_sheet_index_markdown(out_dir / "sheet_index_report.md", payload)


def write_build_outputs(payload: dict[str, Any], out_dir: Path) -> None:
    """Write the package-build artifacts."""
    write_json(out_dir / "package_build_report.json", payload)
    if "layout_plan" in payload:
        write_json(out_dir / "layout_plan.json", payload["layout_plan"])
    write_package_build_markdown(out_dir / "package_build_report.md", payload)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=["index-report", "build-report"],
        help="Report mode to execute.",
    )
    parser.add_argument("--input", required=True, type=Path, help="Input JSON payload from AutoCAD.")
    parser.add_argument("--config", default=DEFAULT_CONFIG_PATH, type=Path, help="bspackage_config.json path.")
    parser.add_argument("--out-dir", required=True, type=Path, help="Output report directory.")
    return parser.parse_args(argv)


def _load_payload(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    args = parse_args(argv)
    config = load_config(args.config)
    payload = _load_payload(args.input)
    payload.setdefault("config_snapshot", config)
    payload.setdefault("generated_at_utc", datetime.now(timezone.utc).isoformat())
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.command == "index-report":
        write_index_outputs(payload, out_dir)
    else:
        write_build_outputs(payload, out_dir)

    print(f"Wrote reports to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
