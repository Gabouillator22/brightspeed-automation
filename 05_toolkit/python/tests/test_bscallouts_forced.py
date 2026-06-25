from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bscallouts_forced as forced


def test_buried_line_repeats_full_label_per_sheet() -> None:
    source = forced.Source(
        source_id="SRC-1",
        handle="AA",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((0.0, 50.0), (300.0, 50.0)),
        point=None,
        length=300.0,
        bbox=(0.0, 50.0, 300.0, 50.0),
    )
    sheets = (
        forced.Sheet("SHEET-1", "S1", (0.0, 0.0, 100.0, 100.0)),
        forced.Sheet("SHEET-2", "S2", (100.0, 0.0, 200.0, 100.0)),
        forced.Sheet("SHEET-3", "S3", (200.0, 0.0, 300.0, 100.0)),
    )

    placements = forced.plan_callouts((source,), sheets, ())
    buried = [item for item in placements if item.family == "buried"]

    assert len(buried) == 3
    assert {item.sheet_id for item in buried} == {"SHEET-1", "SHEET-2", "SHEET-3"}
    assert {item.label for item in buried} == {'HDD BORE 300\' FIBER IN 2" DUCT'}


def test_hard_conflict_still_forces_a_placement() -> None:
    source = forced.Source(
        source_id="SRC-1",
        handle="AA",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((0.0, 50.0), (100.0, 50.0)),
        point=None,
        length=100.0,
        bbox=(0.0, 50.0, 100.0, 50.0),
    )
    sheet = forced.Sheet("SHEET-1", "S1", (0.0, 0.0, 120.0, 120.0))
    blockers = (
        forced.Blocker(
            handle="B1",
            layer="CENTERLINE",
            object_name="AcDbPolyline",
            category="road",
            bbox=(0.0, 0.0, 120.0, 120.0),
        ),
    )

    placements = forced.plan_callouts((source,), (sheet,), blockers)
    buried = [item for item in placements if item.family == "buried"]

    assert len(buried) == 1
    assert buried[0].quality == "forced"
    assert "hard-conflict" in buried[0].reason


def test_structure_labels_are_planned_before_route_labels() -> None:
    route = forced.Source(
        source_id="SRC-1",
        handle="ROUTE",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((0.0, 0.0), (200.0, 0.0)),
        point=None,
        length=200.0,
        bbox=(0.0, 0.0, 200.0, 0.0),
    )
    handhole = forced.Source(
        source_id="SRC-2",
        handle="HH1",
        family="structure",
        subtype="handhole",
        layer="HANDHOLE",
        object_name="AcDbBlockReference",
        points=(),
        point=(100.0, 0.0),
        length=0.0,
        bbox=(95.0, -5.0, 105.0, 5.0),
    )
    sheet = forced.Sheet("SHEET-1", "S1", (-20.0, -60.0, 220.0, 80.0))

    placements = forced.plan_callouts((route, handhole), (sheet,), ())

    assert placements[0].family == "structure"
    assert placements[0].label == "STA 01+00 PL HANDHOLE"
    assert placements[0].render_mode == "stationing-text"
    assert placements[0].text_rotation == pytest.approx(1.57079632679)
    assert placements[0].output_layer == "STATIONING"
    assert any(item.family == "buried" for item in placements)


def test_structure_rotation_is_carried_into_text_placement() -> None:
    handhole = forced.Source(
        source_id="SRC-2",
        handle="HH1",
        family="structure",
        subtype="handhole",
        layer="HANDHOLE",
        object_name="AcDbBlockReference",
        points=(),
        point=(100.0, 0.0),
        length=0.0,
        bbox=(95.0, -5.0, 105.0, 5.0),
        rotation=1.57079632679,
    )
    placements = forced.plan_callouts((handhole,), (), ())

    assert len(placements) == 1
    assert placements[0].render_mode == "stationing-text"
    assert placements[0].text_rotation == pytest.approx(0.0, abs=1e-9)
    assert placements[0].output_layer == "STATIONING"


def test_borepit_uses_stationing_layer_rotation_and_two_line_label() -> None:
    borepit = forced.Source(
        source_id="SRC-3",
        handle="BP1",
        family="structure",
        subtype="borepit",
        layer="BORE PIT",
        object_name="AcDbBlockReference",
        points=(),
        point=(125.0, 0.0),
        length=0.0,
        bbox=(120.0, -5.0, 130.0, 5.0),
        rotation=1.57079632679,
    )
    route = forced.Source(
        source_id="SRC-1",
        handle="ROUTE",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((0.0, 0.0), (200.0, 0.0)),
        point=None,
        length=200.0,
        bbox=(0.0, 0.0, 200.0, 0.0),
    )

    placements = forced.plan_callouts((route, borepit), (), ())
    note = next(item for item in placements if item.source_handle == "BP1")

    assert note.render_mode == "stationing-text"
    assert note.output_layer == "STATIONING"
    assert note.text_rotation == pytest.approx(1.57079632679)
    assert "\\PBORE PIT" in note.label


def test_borepit_uses_perpendicular_to_dominant_corner_run() -> None:
    borepit = forced.Source(
        source_id="SRC-3",
        handle="BP1",
        family="structure",
        subtype="borepit",
        layer="BORE PIT",
        object_name="AcDbBlockReference",
        points=(),
        point=(10.0, 10.0),
        length=0.0,
        bbox=(8.0, 8.0, 12.0, 12.0),
        rotation=0.0,
    )
    vertical_long = forced.Source(
        source_id="SRC-1",
        handle="V",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((10.0, -100.0), (10.0, 100.0)),
        point=None,
        length=200.0,
        bbox=(10.0, -100.0, 10.0, 100.0),
    )
    horizontal_short = forced.Source(
        source_id="SRC-2",
        handle="H",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((-10.0, 10.0), (40.0, 10.0)),
        point=None,
        length=50.0,
        bbox=(-10.0, 10.0, 40.0, 10.0),
    )

    placements = forced.plan_callouts((vertical_long, horizontal_short, borepit), (), ())
    note = next(item for item in placements if item.source_handle == "BP1")

    assert note.text_rotation == pytest.approx(0.0, abs=1e-9)


def test_stationing_candidates_stay_within_15_to_20_feet_of_icon() -> None:
    source = forced.Source(
        source_id="SRC-4",
        handle="HH2",
        family="structure",
        subtype="handhole",
        layer="HANDHOLE",
        object_name="AcDbBlockReference",
        points=(),
        point=(100.0, 100.0),
        length=0.0,
        bbox=(98.0, 98.0, 102.0, 102.0),
        rotation=0.0,
    )
    anchor = (100.0, 100.0)
    tangent = (0.0, 1.0)
    candidates = forced.make_structure_candidates(source, None, "STA 01+00 PL HANDHOLE", anchor, tangent, ())

    assert candidates
    distances = [forced.distance(anchor, item.text_point) for item in candidates]
    assert min(distances) >= 15.0
    assert max(distances) <= 21.6


def test_single_buried_source_repeats_across_three_sheets() -> None:
    source = forced.Source(
        source_id="SRC-1",
        handle="A",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((0.0, 50.0), (200.0, 50.0)),
        point=None,
        length=200.0,
        bbox=(0.0, 50.0, 200.0, 50.0),
    )
    sheets = (
        forced.Sheet("SHEET-1", "S1", (0.0, 0.0, 80.0, 100.0)),
        forced.Sheet("SHEET-2", "S2", (80.0, 0.0, 140.0, 100.0)),
        forced.Sheet("SHEET-3", "S3", (140.0, 0.0, 220.0, 100.0)),
    )
    placements = forced.plan_callouts((source,), sheets, ())
    buried = [item for item in placements if item.family == "buried"]

    assert len(buried) == 3
    assert {item.sheet_id for item in buried} == {"SHEET-1", "SHEET-2", "SHEET-3"}
    assert {item.label for item in buried} == {'HDD BORE 200\' FIBER IN 2" DUCT'}


def test_append_sheet_skips_near_duplicate_borders() -> None:
    sheets: list[forced.Sheet] = []
    forced.append_sheet(sheets, "A", (0.0, 0.0, 200.0, 300.0))
    forced.append_sheet(sheets, "B", (1.0, 1.0, 199.5, 299.0))
    forced.append_sheet(sheets, "C", (250.0, 0.0, 450.0, 300.0))

    assert len(sheets) == 2
    assert [sheet.handle for sheet in sheets] == ["A", "C"]


def test_route_candidates_stay_in_tight_distance_band() -> None:
    source = forced.Source(
        source_id="SRC-1",
        handle="AA",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((0.0, 0.0), (100.0, 0.0)),
        point=None,
        length=100.0,
        bbox=(0.0, 0.0, 100.0, 0.0),
    )
    candidates = forced.make_candidates(source, None, 'HDD BORE 100\' FIBER IN 2" DUCT', (50.0, 0.0), (1.0, 0.0), ())

    assert candidates
    assert all(29.0 <= forced.distance(item.anchor, forced.visible_text_edge_point(item.text_point, 'HDD BORE 100\' FIBER IN 2" DUCT', item.side)) <= 52.0 for item in candidates)
    assert {item.side for item in candidates} == {"left", "right"}


def test_lisp_string_escapes_quotes_for_labels() -> None:
    assert forced.lisp_string('STA 01+00 PL 36"X36"\\PBORE PIT') == '"STA 01+00 PL 36\\"X36\\"\\\\PBORE PIT"'


@pytest.mark.skipif(not forced.SHAPELY_AVAILABLE, reason="shapely not installed")
def test_mindoc_created_for_sheet_with_buried_route() -> None:
    source = forced.Source(
        source_id="SRC-1",
        handle="AA",
        family="buried",
        subtype="buried",
        layer="Buried Fiber in Duct",
        object_name="AcDbPolyline",
        points=((0.0, 50.0), (100.0, 50.0)),
        point=None,
        length=100.0,
        bbox=(0.0, 50.0, 100.0, 50.0),
    )
    sheet = forced.Sheet("SHEET-1", "S1", (0.0, 0.0, 120.0, 120.0))

    placements = forced.plan_callouts((source,), (sheet,), ())

    assert any(item.family == "mindoc" and item.label == 'MIN DOC 60"' for item in placements)
