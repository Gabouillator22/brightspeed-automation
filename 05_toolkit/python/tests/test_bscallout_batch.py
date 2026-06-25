from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bscallout_batch
import bscallout_live


def make_plan(candidate: bscallout_live.Candidate) -> bscallout_live.CalloutPlan:
    source = bscallout_live.SourceSegment(
        index=1,
        handle="ABC",
        object_name="AcDbPolyline",
        layer="Buried Fiber in Duct",
        points=[(0.0, 0.0), (100.0, 0.0)],
        length=100.0,
        bbox=(0.0, 0.0, 100.0, 0.0),
        line=None,
    )
    return bscallout_live.CalloutPlan(
        source=source,
        border=None,
        border_id="GLOBAL",
        full_text='HDD BORE 100\' FIBER IN 2" DUCT',
        anchor=candidate.anchor,
        tangent=(1.0, 0.0),
        candidates=[candidate],
    )


def make_candidate(
    text_bbox: tuple[float, float, float, float] = (0.0, 10.0, 50.0, 20.0),
    text_point: tuple[float, float] = (50.0, 15.0),
) -> bscallout_live.Candidate:
    return bscallout_live.Candidate(
        number=7,
        side="left",
        offset=15.0,
        shift=0.0,
        anchor=(50.0, 0.0),
        text_point=text_point,
        text_bbox=text_bbox,
        score=985.0,
        reason="clear",
    )


def test_write_batch_lisp_uses_existing_mleader_helper(tmp_path: Path) -> None:
    candidate = bscallout_live.Candidate(
        number=7,
        side="left",
        offset=15.0,
        shift=0.0,
        anchor=(50.0, 0.0),
        text_point=(50.0, 15.0),
        text_bbox=(0.0, 10.0, 50.0, 20.0),
        score=985.0,
        reason="clear",
    )
    plan = make_plan(candidate)

    output = tmp_path / "batch.lsp"
    bscallout_batch.write_batch_lisp([bscallout_batch.BatchPlacement(plan, candidate)], output)
    text = output.read_text(encoding="ascii")

    assert "bscallout_place.lsp" in text
    assert "defun c:BSCALLOUT-BATCH-RUN" in text
    assert "(bscw-place-mleader 50.00000000 0.00000000 50.00000000 15.00000000" in text
    assert 'setvar "USERS1" "BSCALLOUT_BATCH_RUNNING"' in text
    assert 'BSCALLOUT_BATCH_DONE:' in text
    assert "(if (and result (handent result))" in text
    assert "Placement returned no valid handle" in text
    assert 'HDD BORE 100\\\' FIBER IN 2\\" DUCT' not in text
    assert 'HDD BORE 100\' FIBER IN 2\\" DUCT' in text


def test_select_placements_rejects_text_box_road_collision() -> None:
    candidate = make_candidate()
    plan = make_plan(candidate)
    blocker = bscallout_batch.BatchBlocker(
        handle="ROAD1",
        object_name="AcDbLine",
        layer="CENTERLINE",
        bbox=(10.0, 12.0, 20.0, 14.0),
        category="road",
        geometry=bscallout_live.LineString([(10.0, 13.0), (20.0, 13.0)]),
    )

    placements = bscallout_batch.select_placements([plan], [blocker])

    assert placements[0].decision == "manual"
    assert placements[0].candidate == candidate
    assert "text-collision" in placements[0].reason
    assert placements[0].text_conflicts == ("road:ROAD1:centerline",)


def test_select_placements_rejects_leader_corridor_collision() -> None:
    candidate = make_candidate(text_bbox=(100.0, 10.0, 170.0, 20.0), text_point=(100.0, 0.0))
    plan = make_plan(candidate)
    blocker = bscallout_batch.BatchBlocker(
        handle="CL1",
        object_name="AcDbLine",
        layer="CL",
        bbox=(70.0, -1.0, 80.0, 1.0),
        category="road",
        geometry=bscallout_live.LineString([(70.0, 0.0), (80.0, 0.0)]),
    )

    placements = bscallout_batch.select_placements([plan], [blocker])

    assert placements[0].decision == "manual"
    assert "leader-collision" in placements[0].reason
    assert placements[0].leader_conflicts == ("road:CL1:cl",)


def test_select_placements_does_not_hard_reject_existing_callout_collision() -> None:
    candidate = make_candidate(text_bbox=(100.0, 10.0, 170.0, 20.0), text_point=(100.0, 0.0))
    plan = make_plan(candidate)
    blocker = bscallout_batch.BatchBlocker(
        handle="OLD1",
        object_name="AcDbMLeader",
        layer="CABLE CALLOUTS",
        bbox=(70.0, -1.0, 80.0, 1.0),
        category="existing-callout",
        geometry=bscallout_live.LineString([(70.0, 0.0), (80.0, 0.0)]),
    )

    placements = bscallout_batch.select_placements([plan], [blocker])

    assert placements[0].decision == "place"
    assert placements[0].leader_conflicts == ("existing-callout:OLD1:cable callouts",)


def test_write_batch_lisp_omits_manual_review_placements(tmp_path: Path) -> None:
    candidate = make_candidate()
    plan = make_plan(candidate)

    output = tmp_path / "batch.lsp"
    bscallout_batch.write_batch_lisp(
        [bscallout_batch.BatchPlacement(plan, candidate, decision="manual", reason="text-collision")],
        output,
    )
    text = output.read_text(encoding="ascii")

    assert "bscw-place-mleader" not in text
    assert "Expected 0 accepted callouts" in text
    assert "BSCALLOUT_BATCH_DONE:" in text


def test_select_placements_progress_is_optional(capsys) -> None:
    candidate = make_candidate(text_bbox=(100.0, 10.0, 170.0, 20.0), text_point=(100.0, 0.0))
    plan = make_plan(candidate)

    placements = bscallout_batch.select_placements([plan], [], show_progress=True)

    assert placements[0].decision == "place"
    output = capsys.readouterr().out
    assert "Checking placement candidates" in output
    assert "ETA" in output


def test_format_duration() -> None:
    assert bscallout_batch.format_duration(9.2) == "00:09"
    assert bscallout_batch.format_duration(65.0) == "01:05"
    assert bscallout_batch.format_duration(3661.0) == "1:01:01"


def test_parse_batch_done_count() -> None:
    assert bscallout_batch.parse_batch_done_count("BSCALLOUT_BATCH_DONE:1/1") == (1, 1)
    assert bscallout_batch.parse_batch_done_count("BSCALLOUT_BATCH_RUNNING") is None
    assert bscallout_batch.parse_batch_done_count("BSCALLOUT_BATCH_DONE:nope") is None


def test_has_runnable_placements() -> None:
    assert bscallout_batch.has_runnable_placements(1)
    assert not bscallout_batch.has_runnable_placements(0)


def test_hard_conflicts_excludes_existing_callouts() -> None:
    conflicts = (
        "existing-callout:OLD1:cable callouts",
        "road:ROAD1:row",
        "blocker:DIM1:dimensions",
    )

    assert bscallout_batch.hard_conflicts(conflicts) == ("road:ROAD1:row", "blocker:DIM1:dimensions")
