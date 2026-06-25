from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bssheetplan
from shapely.ops import unary_union


def make_config() -> dict:
    config = bssheetplan.DEFAULT_CONFIG.copy()
    config.update(
        {
            "sheet_width_ft": 974.0,
            "sheet_height_ft": 473.0,
            "side_margin_ft": 75.0,
            "sample_interval_ft": 50.0,
            "road_buffer_left_ft": 150.0,
            "road_buffer_right_ft": 150.0,
            "placement_mode": "follow_route",
        }
    )
    return config


def assert_sheet_geometry(sheet: bssheetplan.Sheet, config: dict) -> None:
    width = config["sheet_width_ft"]
    height = config["sheet_height_ft"]
    polygon = bssheetplan.sheet_polygon(sheet)
    min_x, min_y, max_x, max_y = polygon.bounds

    assert sheet.angle_rad == 0.0
    assert math.isclose(max_x - min_x, width, rel_tol=0.0, abs_tol=1e-6)
    assert math.isclose(max_y - min_y, height, rel_tol=0.0, abs_tol=1e-6)
    assert math.isclose(sheet.width, width, rel_tol=0.0, abs_tol=1e-6)
    assert math.isclose(sheet.height, height, rel_tol=0.0, abs_tol=1e-6)
    xs = sorted({round(x, 6) for x, _ in sheet.vertices})
    ys = sorted({round(y, 6) for _, y in sheet.vertices})
    assert len(xs) == 2
    assert len(ys) == 2
    assert math.isclose(xs[1] - xs[0], width, rel_tol=0.0, abs_tol=1e-6)
    assert math.isclose(ys[1] - ys[0], height, rel_tol=0.0, abs_tol=1e-6)


def assert_full_coverage(parts: list[bssheetplan.RoutePart], sheets: list[bssheetplan.Sheet]) -> None:
    line = bssheetplan.clean_line(parts[0].coords)
    assert line is not None
    coverage = unary_union([bssheetplan.sheet_polygon(sheet) for sheet in sheets])
    assert line.difference(coverage).is_empty


def assert_no_overlap(sheets: list[bssheetplan.Sheet]) -> None:
    warnings = bssheetplan.sheet_overlap_warnings(sheets)
    assert warnings == []


def test_short_angled_route_fits_in_one_sheet() -> None:
    config = make_config()
    parts = [bssheetplan.RoutePart("route", [(0.0, 0.0), (220.0, 60.0), (410.0, 110.0)])]

    sheets = bssheetplan.plan_route_sheets_kmz(parts, config)

    assert len(sheets) == 1
    assert_sheet_geometry(sheets[0], config)
    assert_no_overlap(sheets)
    assert_full_coverage(parts, sheets)


def test_bent_route_fitting_within_bbox_still_uses_one_sheet() -> None:
    config = make_config()
    parts = [bssheetplan.RoutePart("route", [(0.0, 0.0), (140.0, 80.0), (280.0, 0.0)])]

    sheets = bssheetplan.plan_route_sheets_kmz(parts, config)

    assert len(sheets) == 1
    assert_sheet_geometry(sheets[0], config)
    assert_no_overlap(sheets)
    assert_full_coverage(parts, sheets)


def test_long_horizontal_route_tiles_edge_to_edge_without_overlap() -> None:
    config = make_config()
    parts = [bssheetplan.RoutePart("route", [(0.0, 0.0), (3000.0, 0.0)])]

    sheets = bssheetplan.plan_route_sheets_kmz(parts, config)

    assert len(sheets) > 1
    for sheet in sheets:
        assert_sheet_geometry(sheet, config)
    assert_no_overlap(sheets)
    assert_full_coverage(parts, sheets)

    bounds = [bssheetplan.sheet_polygon(sheet).bounds for sheet in sheets]
    bounds.sort(key=lambda item: item[0])
    for prev, curr in zip(bounds, bounds[1:]):
        assert math.isclose(curr[0], prev[2], rel_tol=0.0, abs_tol=1e-6)
        assert math.isclose(curr[1], prev[1], rel_tol=0.0, abs_tol=1e-6)
        assert math.isclose(curr[3], prev[3], rel_tol=0.0, abs_tol=1e-6)


def test_diagonal_route_tiles_axis_aligned_without_overlap() -> None:
    config = make_config()
    parts = [bssheetplan.RoutePart("route", [(0.0, 0.0), (900.0, 420.0), (1800.0, 840.0), (2600.0, 1200.0)])]

    sheets = bssheetplan.plan_route_sheets_kmz(parts, config)

    assert len(sheets) > 1
    for sheet in sheets:
        assert_sheet_geometry(sheet, config)
    assert_no_overlap(sheets)
    assert_full_coverage(parts, sheets)


def test_bent_route_tiles_axis_aligned_without_overlap() -> None:
    config = make_config()
    parts = [bssheetplan.RoutePart("route", [(0.0, 0.0), (700.0, 0.0), (700.0, 360.0), (1300.0, 360.0)])]

    sheets = bssheetplan.plan_route_sheets_kmz(parts, config)

    assert len(sheets) > 1
    for sheet in sheets:
        assert_sheet_geometry(sheet, config)
    assert_no_overlap(sheets)
    assert_full_coverage(parts, sheets)
