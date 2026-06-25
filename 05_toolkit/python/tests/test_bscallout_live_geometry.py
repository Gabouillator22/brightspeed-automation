from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bscallout_live


def test_polyline_length_and_midpoint() -> None:
    points = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)]
    assert math.isclose(bscallout_live.polyline_length(points), 20.0, abs_tol=1e-9)
    midpoint = bscallout_live.midpoint_on_polyline(points)
    assert midpoint == (10.0, 0.0)


def test_point_at_distance_and_tangent() -> None:
    points = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)]
    point = bscallout_live.point_at_distance(points, 15.0)
    tangent = bscallout_live.tangent_at_distance(points, 15.0)
    assert point == (10.0, 5.0)
    assert tangent == (0.0, 1.0)


def test_perpendicular_helpers() -> None:
    tangent = (1.0, 0.0)
    assert bscallout_live.perp_left(tangent) == (0.0, 1.0)
    assert bscallout_live.perp_right(tangent) == (0.0, -1.0)


def test_bbox_for_text_alignment() -> None:
    left_box = bscallout_live.bbox_for_text((100.0, 50.0), 'HDD BORE 42\' FIBER IN 2" DUCT', align="left")
    right_box = bscallout_live.bbox_for_text((100.0, 50.0), 'HDD BORE 42\' FIBER IN 2" DUCT', align="right")
    assert left_box[0] == 100.0
    assert right_box[2] == 100.0
    assert left_box[2] > left_box[0]
    assert right_box[0] < right_box[2]


def test_build_candidates_prefers_left_ordering() -> None:
    candidates = bscallout_live.make_candidates((0.0, 0.0), (1.0, 0.0), 'HDD BORE 42\' FIBER IN 2" DUCT', None, [])
    first = candidates[0]
    assert first.side == "left"
    assert first.offset == 15.0
    assert first.shift == 0.0
    assert first.text_point == (0.0, 15.0)


def test_com_point_falls_back_to_plain_tuple_without_com_runtime() -> None:
    assert bscallout_live.make_lisp_string('HDD BORE 42\' FIBER IN 2" DUCT') == '"HDD BORE 42\' FIBER IN 2\\" DUCT"'


def test_bbox_contains_detects_inner_box() -> None:
    assert bscallout_live.bbox_contains((1.0, 1.0, 2.0, 2.0), (0.0, 0.0, 3.0, 3.0))


def test_candidate_score_penalizes_road_collision() -> None:
    candidate = bscallout_live.Candidate(
        number=1,
        side="left",
        offset=15.0,
        shift=0.0,
        anchor=(50.0, 0.0),
        text_point=(50.0, 15.0),
        text_bbox=(50.0, 10.0, 120.0, 20.0),
        score=0.0,
        reason="",
    )
    blocker = bscallout_live.Blocker(
        handle="R",
        object_name="AcDbLine",
        layer="ROW",
        bbox=(45.0, 8.0, 130.0, 22.0),
        category="road",
    )
    score, reason = bscallout_live.score_candidate(candidate, None, [blocker])
    assert score < 200.0
    assert "road" in reason
