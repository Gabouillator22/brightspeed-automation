#!/usr/bin/env python3
"""Generate and optionally run fast batch buried-fiber callouts."""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

import bscallout_live as live


BATCH_LISP_PATH = live.SCRIPT_DIR / "reports" / "bscallout_batch_run.lsp"
BATCH_REPORT_PATH = live.SCRIPT_DIR / "reports" / "bscallout_batch_report.md"
TEXT_COLLISION_PAD = 2.0
LEADER_COLLISION_PAD = 2.0
LEADER_CORRIDOR_WIDTH = 3.0
LANDING_GAP = 5.0
PROGRESS_WIDTH = 28
HARD_REJECT_CATEGORIES = {"road", "blocker"}


class ProgressBar:
    def __init__(self, label: str, total: int | None = None) -> None:
        self.label = label
        self.total = total if total and total > 0 else None
        self.start = time.monotonic()
        self.last_update = 0.0

    def update(self, current: int, total: int | None = None, detail: str = "", force: bool = False) -> None:
        if total and total > 0:
            self.total = total
        now = time.monotonic()
        if not force and now - self.last_update < 0.25:
            return
        self.last_update = now
        elapsed = now - self.start
        if self.total:
            ratio = min(1.0, max(0.0, current / self.total))
            filled = int(PROGRESS_WIDTH * ratio)
            bar = "#" * filled + "-" * (PROGRESS_WIDTH - filled)
            eta = "--:--"
            if current > 0:
                remaining = elapsed * (self.total - current) / current
                eta = format_duration(remaining)
            line = f"\r[{bar}] {self.label}: {current}/{self.total} elapsed {format_duration(elapsed)} ETA {eta}"
        else:
            spinner = "|/-\\"[current % 4]
            line = f"\r[{spinner}] {self.label}: {current} elapsed {format_duration(elapsed)}"
        if detail:
            line += f" {detail}"
        print(line, end="", flush=True)

    def done(self, current: int | None = None, detail: str = "") -> None:
        final = current if current is not None else self.total or 0
        self.update(final, force=True, detail=detail)
        print(flush=True)


def format_duration(seconds: float) -> str:
    seconds = max(0, int(round(seconds)))
    minutes, secs = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


@dataclass(frozen=True)
class BatchPlacement:
    plan: live.CalloutPlan
    candidate: live.Candidate | None
    decision: str = "place"
    reason: str = "accepted"
    text_conflicts: tuple[str, ...] = ()
    leader_conflicts: tuple[str, ...] = ()


@dataclass(frozen=True)
class BatchBlocker:
    handle: str
    object_name: str
    layer: str
    category: str
    bbox: tuple[float, float, float, float]
    geometry: Any


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yes", action="store_true", help="Do not prompt to confirm the active drawing.")
    parser.add_argument("--run", action="store_true", help="Deprecated. Use AutoCAD BSCALLOUT-AUTO for production placement.")
    parser.add_argument(
        "--experimental-run",
        action="store_true",
        help="Actually run the experimental generated batch LISP. Production use should stay on BSCALLOUT-AUTO.",
    )
    parser.add_argument("--max", type=int, help="Limit source buried entities before sheet expansion.")
    parser.add_argument("--no-sheet-repeat", action="store_true", help="Create one global callout per source entity.")
    return parser.parse_args(argv)


def build_plans(
    ms: object,
    max_sources: int | None,
    no_sheet_repeat: bool,
) -> tuple[list[live.SourceSegment], list[live.BorderRegion], list[BatchBlocker], list[live.CalloutPlan]]:
    entities = collect_modelspace_entities(ms)
    sources = collect_sources_from_entities(entities)
    if max_sources:
        sources = sources[:max_sources]
    borders = collect_borders_from_entities(entities)
    blockers = collect_batch_blockers_from_entities(entities)

    plans: list[live.CalloutPlan] = []
    progress = ProgressBar("Planning callouts", len(sources))
    for index, source in enumerate(sources, start=1):
        progress.update(index, detail=f"source={source.handle}")
        matched = live.matching_borders(source, borders, no_sheet_repeat)
        targets: list[live.BorderRegion | None] = matched if matched else [None]
        for border in targets:
            plans.append(live.make_plan(source, border, blockers))
    progress.done(len(sources), detail=f"plans={len(plans)}")
    return sources, borders, blockers, plans


def collect_modelspace_entities(ms: object) -> list[object]:
    count = int(live.safe_get(ms, "Count", 0))
    entities: list[object] = []
    progress = ProgressBar("Reading AutoCAD ModelSpace", count)
    for index in range(count):
        progress.update(index + 1)
        try:
            entities.append(ms.Item(index))
        except Exception:
            continue
    progress.done(count, detail=f"read={len(entities)}")
    return entities


def collect_sources_from_entities(entities: Sequence[object]) -> list[live.SourceSegment]:
    sources: list[live.SourceSegment] = []
    progress = ProgressBar("Finding buried fiber", len(entities))
    for index, obj in enumerate(entities, start=1):
        progress.update(index)
        if not live.is_buried_source(obj):
            continue
        points = live.entity_points(obj)
        if len(points) < 2:
            continue
        length = live.polyline_length(points)
        bbox = live.entity_bbox(obj) or live.bbox_from_points(points)
        sources.append(
            live.SourceSegment(
                index=len(sources) + 1,
                handle=live.object_handle(obj),
                object_name=live.object_name(obj),
                layer=str(live.safe_get(obj, "Layer", "")),
                points=points,
                length=length,
                bbox=bbox,
                line=live.LineString(points),
            )
        )
    progress.done(len(entities), detail=f"found={len(sources)}")
    return sources


def collect_borders_from_entities(entities: Sequence[object]) -> list[live.BorderRegion]:
    borders: list[live.BorderRegion] = []
    seen: set[tuple[int, int, int, int]] = set()
    progress = ProgressBar("Finding BORDER sheets", len(entities))
    for index, obj in enumerate(entities, start=1):
        progress.update(index)
        if live.normalize_layer(str(live.safe_get(obj, "Layer", ""))) != "border":
            continue
        bbox = live.entity_bbox(obj)
        if not bbox:
            continue
        key = tuple(int(round(v)) for v in bbox)
        if key in seen:
            continue
        seen.add(key)
        borders.append(live.BorderRegion(f"BORDER-{len(borders) + 1}", live.object_handle(obj), bbox, live.box(*bbox)))
    progress.done(len(entities), detail=f"found={len(borders)}")
    return borders


def collect_batch_blockers_from_entities(entities: Sequence[object]) -> list[BatchBlocker]:
    blockers: list[BatchBlocker] = []
    progress = ProgressBar("Finding collision blockers", len(entities))
    for index, obj in enumerate(entities, start=1):
        progress.update(index)
        layer = str(live.safe_get(obj, "Layer", ""))
        normalized_layer = live.normalize_layer(layer)
        if normalized_layer == "border":
            continue
        category = live.blocker_category(obj)
        if not category:
            continue
        bbox = live.entity_bbox(obj)
        if not bbox:
            continue
        geometry: Any = live.box(*bbox)
        points = live.entity_points(obj)
        if len(points) >= 2:
            try:
                geometry = live.LineString(points)
            except Exception:
                geometry = live.box(*bbox)
        blockers.append(
            BatchBlocker(
                handle=live.object_handle(obj),
                object_name=live.object_name(obj),
                layer=layer,
                category=category,
                bbox=bbox,
                geometry=geometry,
            )
        )
    progress.done(len(entities), detail=f"found={len(blockers)}")
    return blockers


def blocker_label(blocker: BatchBlocker) -> str:
    layer = live.normalize_layer(blocker.layer)
    return f"{blocker.category}:{blocker.handle}:{layer}"


def bbox_collision_reasons(
    bbox: tuple[float, float, float, float],
    blockers: Sequence[BatchBlocker],
    pad: float,
) -> tuple[str, ...]:
    text_geometry = live.box(*bbox)
    reasons: list[str] = []
    for blocker in blockers:
        try:
            blocker_geometry = blocker.geometry.buffer(pad) if pad else blocker.geometry
            if text_geometry.intersects(blocker_geometry):
                reasons.append(blocker_label(blocker))
        except Exception:
            if live.bbox_intersects(bbox, blocker.bbox, pad=pad):
                reasons.append(blocker_label(blocker))
    return tuple(reasons)


def geometry_collision_reasons(geometry: Any, blockers: Sequence[BatchBlocker]) -> tuple[str, ...]:
    reasons: list[str] = []
    for blocker in blockers:
        try:
            if geometry.intersects(blocker.geometry):
                reasons.append(blocker_label(blocker))
        except Exception:
            if live.bbox_intersects(tuple(geometry.bounds), blocker.bbox, pad=0.0):
                reasons.append(blocker_label(blocker))
    return tuple(reasons)


def protected_blockers_for_candidate(plan: live.CalloutPlan, candidate: live.Candidate, blockers: Sequence[BatchBlocker]) -> list[BatchBlocker]:
    protected: list[BatchBlocker] = []
    for blocker in blockers:
        if blocker.handle == plan.source.handle:
            continue
        protected.append(blocker)
    return protected


def leader_points(candidate: live.Candidate) -> list[tuple[float, float]]:
    unit = live.normalize(live.sub(candidate.text_point, candidate.anchor))
    landing = live.sub(candidate.text_point, live.scale(unit, LANDING_GAP))
    return [candidate.anchor, landing, candidate.text_point]


def leader_collision_reasons(
    candidate: live.Candidate,
    blockers: Sequence[BatchBlocker],
    width: float = LEADER_CORRIDOR_WIDTH,
) -> tuple[str, ...]:
    points = leader_points(candidate)
    if not live.SHAPELY_AVAILABLE:
        corridor_bbox = live.bbox_from_points(points)
        return bbox_collision_reasons(corridor_bbox, blockers, LEADER_COLLISION_PAD)
    corridor = live.LineString(points).buffer(width, cap_style=2, join_style=2)
    return geometry_collision_reasons(corridor, blockers)


def candidate_rejection_reasons(
    plan: live.CalloutPlan,
    candidate: live.Candidate,
    blockers: Sequence[BatchBlocker],
) -> tuple[tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
    hard_reasons: list[str] = []
    if candidate.score <= -1e8:
        hard_reasons.append("outside-border")
    if plan.border is not None and not live.bbox_contains(candidate.text_bbox, plan.border.bbox, pad=1.0):
        hard_reasons.append("outside-border")
    protected_blockers = protected_blockers_for_candidate(plan, candidate, blockers)
    text_conflicts = bbox_collision_reasons(candidate.text_bbox, protected_blockers, TEXT_COLLISION_PAD)
    leader_conflicts = leader_collision_reasons(candidate, protected_blockers)
    hard_text_conflicts = hard_conflicts(text_conflicts)
    hard_leader_conflicts = hard_conflicts(leader_conflicts)
    if hard_text_conflicts:
        hard_reasons.append("text-collision")
    if hard_leader_conflicts:
        hard_reasons.append("leader-collision")
    return tuple(hard_reasons), text_conflicts, leader_conflicts


def hard_conflicts(conflicts: Sequence[str]) -> tuple[str, ...]:
    hard: list[str] = []
    for conflict in conflicts:
        category = conflict.split(":", 1)[0]
        if category in HARD_REJECT_CATEGORIES:
            hard.append(conflict)
    return tuple(hard)


def select_placements(plans: Sequence[live.CalloutPlan], blockers: Sequence[BatchBlocker], show_progress: bool = False) -> list[BatchPlacement]:
    placements: list[BatchPlacement] = []
    progress = ProgressBar("Checking placement candidates", len(plans)) if show_progress else None
    for plan_index, plan in enumerate(plans, start=1):
        if progress:
            progress.update(plan_index, detail=f"source={plan.source.handle} border={plan.border_id}")
        best_rejected: BatchPlacement | None = None
        for candidate in plan.candidates:
            hard_reasons, text_conflicts, leader_conflicts = candidate_rejection_reasons(plan, candidate, blockers)
            if not hard_reasons:
                placements.append(
                    BatchPlacement(
                        plan=plan,
                        candidate=candidate,
                        decision="place",
                        reason="accepted",
                        text_conflicts=text_conflicts,
                        leader_conflicts=leader_conflicts,
                    )
                )
                break
            if best_rejected is None:
                best_rejected = BatchPlacement(
                    plan=plan,
                    candidate=candidate,
                    decision="manual",
                    reason=",".join(hard_reasons),
                    text_conflicts=text_conflicts,
                    leader_conflicts=leader_conflicts,
                )
        else:
            placements.append(best_rejected or BatchPlacement(plan, None, decision="skip", reason="no-candidates"))
    if progress:
        accepted = sum(1 for item in placements if item.decision == "place")
        manual = sum(1 for item in placements if item.decision == "manual")
        skipped = sum(1 for item in placements if item.decision == "skip")
        progress.done(len(plans), detail=f"place={accepted} manual={manual} skip={skipped}")
    return placements


def lisp_load_path(path: Path) -> str:
    return path.resolve().as_posix()


def placement_expression(placement: BatchPlacement) -> str:
    if placement.candidate is None:
        raise ValueError("placement has no candidate")
    return live.lisp_place_expression(placement.plan.anchor, placement.candidate.text_point, placement.plan.full_text)


def write_batch_lisp(placements: Sequence[BatchPlacement], output_path: Path = BATCH_LISP_PATH) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    runnable = [placement for placement in placements if placement.decision == "place" and placement.candidate is not None]
    helper_path = lisp_load_path(live.LISP_HELPER_PATH)
    lines = [
        ";;; Auto-generated by bscallout_batch.py.",
        ";;; Uses bscallout_place.lsp for identical arrow, MLeader, and text-background behavior.",
        "",
        "(vl-load-com)",
        f"(load {live.make_lisp_string(helper_path)})",
        "",
        "(defun c:BSCALLOUT-BATCH-RUN (/ doc olderr placed expected result)",
        "  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))",
        "  (setq olderr *error*)",
        "  (defun *error* (msg)",
        "    (if doc (vl-catch-all-apply 'vla-EndUndoMark (list doc)))",
        "    (setvar \"USERS1\" (strcat \"BSCALLOUT_BATCH_ERROR:\" (if msg msg \"unknown\")))",
        "    (setq *error* olderr)",
        "    (if (and msg (/= msg \"Function cancelled\"))",
        "      (princ (strcat \"\\n[BSCALLOUT-BATCH] Error: \" msg)))",
        "    (princ))",
        f"  (setq expected {len(runnable)})",
        "  (setq placed 0)",
        "  (setvar \"USERS1\" \"BSCALLOUT_BATCH_RUNNING\")",
        "  (vla-StartUndoMark doc)",
    ]
    for placement in runnable:
        plan = placement.plan
        candidate = placement.candidate
        assert candidate is not None
        lines.append(f"  ;; source={plan.source.handle} border={plan.border_id} candidate={candidate.number}")
        lines.append(f"  (setq result {placement_expression(placement)})")
        lines.append("  (if (and result (handent result))")
        lines.append("    (setq placed (1+ placed))")
        lines.append("    (princ \"\\n[BSCALLOUT-BATCH] Placement returned no valid handle.\"))")
    lines.extend(
        [
            "  (vla-EndUndoMark doc)",
            "  (vla-Regen doc 1)",
            "  (setvar \"USERS1\" (strcat \"BSCALLOUT_BATCH_DONE:\" (itoa placed) \"/\" (itoa expected)))",
            "  (setq *error* olderr)",
            f"  (princ \"\\n[BSCALLOUT-BATCH] Expected {len(runnable)} accepted callouts.\")",
            "  (princ (strcat \"\\n[BSCALLOUT-BATCH] Confirmed placed \" (itoa placed) \".\"))",
            "  (princ))",
            "",
            "(princ \"\\n[BSCALLOUT-BATCH] Loaded. Run BSCALLOUT-BATCH-RUN.\")",
            "(princ)",
            "",
        ]
    )
    output_path.write_text("\n".join(lines), encoding="ascii")
    return output_path


def write_report(
    doc: object,
    sources: Sequence[live.SourceSegment],
    borders: Sequence[live.BorderRegion],
    blockers: Sequence[BatchBlocker],
    placements: Sequence[BatchPlacement],
    report_path: Path = BATCH_REPORT_PATH,
) -> Path:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    runnable = [placement for placement in placements if placement.decision == "place" and placement.candidate is not None]
    manual = [placement for placement in placements if placement.decision == "manual"]
    skipped = [placement for placement in placements if placement.decision == "skip"]
    lines = [
        "# BSCALLOUT Batch Report",
        "",
        f"- Drawing: `{live.safe_get(doc, 'Name', '<unknown>')}`",
        f"- Full path: `{live.safe_get(doc, 'FullName', '<unknown>')}`",
        f"- Buried source entities found: `{len(sources)}`",
        f"- BORDER sheets found: `{len(borders)}`",
        f"- Blockers found: `{len(blockers)}`",
        f"- Callout plans generated: `{len(placements)}`",
        f"- Batch placements written: `{len(runnable)}`",
        f"- Manual review required: `{len(manual)}`",
        f"- Plans skipped without candidate: `{len(skipped)}`",
        f"- Batch LISP: `{BATCH_LISP_PATH}`",
        "",
        "| Source | Layer | Type | Length | Border | Decision | Candidate | Score | Reason | Text conflicts | Leader conflicts | Anchor | Text | Label |",
        "|---|---|---|---:|---|---|---:|---:|---|---|---|---|---|---|",
    ]
    for placement in placements:
        plan = placement.plan
        candidate = placement.candidate
        text_conflicts = "<br>".join(placement.text_conflicts)
        leader_conflicts = "<br>".join(placement.leader_conflicts)
        if candidate is None:
            lines.append(
                f"| {plan.source.handle} | {plan.source.layer} | {plan.source.object_name} | {plan.source.length:.1f} | {plan.border_id} | {placement.decision} |  |  | {placement.reason} | {text_conflicts} | {leader_conflicts} | ({plan.anchor[0]:.2f}, {plan.anchor[1]:.2f}) |  | {plan.full_text} |"
            )
            continue
        lines.append(
            "| {source} | {layer} | {otype} | {length:.1f} | {border} | {decision} | {candidate} | {score:.1f} | {reason} | {text_conflicts} | {leader_conflicts} | {anchor} | {text} | {label} |".format(
                source=plan.source.handle,
                layer=plan.source.layer,
                otype=plan.source.object_name,
                length=plan.source.length,
                border=plan.border_id,
                decision=placement.decision,
                candidate=candidate.number,
                score=candidate.score,
                reason=placement.reason.replace("|", "/"),
                text_conflicts=text_conflicts.replace("|", "/"),
                leader_conflicts=leader_conflicts.replace("|", "/"),
                anchor=f"({plan.anchor[0]:.2f}, {plan.anchor[1]:.2f})",
                text=f"({candidate.text_point[0]:.2f}, {candidate.text_point[1]:.2f})",
                label=plan.full_text,
            )
        )
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def safe_set_variable(doc: object, name: str, value: object) -> None:
    try:
        doc.SetVariable(name, value)
    except Exception:
        pass


def safe_get_variable(doc: object, name: str, default: object = "") -> object:
    try:
        return doc.GetVariable(name)
    except Exception:
        return default


def wait_for_batch_marker(doc: object, expected: int, timeout: float = 120.0) -> str:
    end = time.monotonic() + timeout
    progress = ProgressBar("Waiting for AutoCAD batch placement", None)
    tick = 0
    while time.monotonic() < end:
        status = str(safe_get_variable(doc, "USERS1", ""))
        if status.startswith("BSCALLOUT_BATCH_DONE:") or status.startswith("BSCALLOUT_BATCH_ERROR:"):
            progress.done(tick, detail=status)
            return status
        tick += 1
        progress.update(tick, detail=f"expected={expected}")
        live.pump_com_messages()
        time.sleep(0.5)
    progress.done(tick, detail="timeout")
    return str(safe_get_variable(doc, "USERS1", ""))


def parse_batch_done_count(status: str) -> tuple[int, int] | None:
    prefix = "BSCALLOUT_BATCH_DONE:"
    if not status.startswith(prefix):
        return None
    payload = status[len(prefix) :]
    if "/" not in payload:
        return None
    placed, expected = payload.split("/", 1)
    try:
        return int(placed), int(expected)
    except ValueError:
        return None


def has_runnable_placements(accepted_count: int) -> bool:
    return accepted_count > 0


def run_batch(doc: object, batch_path: Path, expected: int) -> str:
    live.load_lisp(doc)
    safe_set_variable(doc, "USERS1", "BSCALLOUT_BATCH_LOADING")
    live.send_command(doc, f"(load {live.make_lisp_string(lisp_load_path(batch_path))})")
    live.wait_for_autocad(doc, timeout=10.0)
    safe_set_variable(doc, "USERS1", "BSCALLOUT_BATCH_QUEUED")
    live.send_command(doc, "(c:BSCALLOUT-BATCH-RUN)")
    status = wait_for_batch_marker(doc, expected, timeout=120.0)
    if status.startswith("BSCALLOUT_BATCH_ERROR:"):
        raise RuntimeError(f"AutoCAD batch reported an error: {status}")
    counts = parse_batch_done_count(status)
    if counts is None:
        raise RuntimeError(f"AutoCAD did not confirm batch completion. Last marker: {status or '<empty>'}")
    placed, confirmed_expected = counts
    if confirmed_expected != expected:
        raise RuntimeError(f"AutoCAD expected-count mismatch: confirmed {confirmed_expected}, Python expected {expected}")
    if placed != expected:
        raise RuntimeError(f"AutoCAD confirmed only {placed}/{expected} callouts placed")
    return status


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if not live.SHAPELY_AVAILABLE:
        print("Missing dependency. Install with: python -m pip install pywin32 shapely")
        return 1

    acad, doc, ms = live.connect_autocad()
    print(f"Connected to AutoCAD: {'yes' if acad else 'no'}")
    live.confirm_document(doc, args.yes)

    start = time.monotonic()
    sources, borders, blockers, plans = build_plans(ms, args.max, args.no_sheet_repeat)
    placements = select_placements(plans, blockers, show_progress=True)
    batch_path = write_batch_lisp(placements)
    report_path = write_report(doc, sources, borders, blockers, placements)
    accepted = sum(1 for item in placements if item.decision == "place" and item.candidate is not None)
    manual = sum(1 for item in placements if item.decision == "manual")
    skipped = sum(1 for item in placements if item.decision == "skip")

    print(f"Buried entities found: {len(sources)}")
    print(f"BORDERs found: {len(borders)}")
    print(f"Blockers found: {len(blockers)}")
    print(f"Callout plans generated: {len(plans)}")
    print(f"Batch placements written: {accepted}")
    print(f"Manual review required: {manual}")
    print(f"Skipped: {skipped}")
    print(f"Batch LISP: {batch_path}")
    print(f"Report: {report_path}")
    print(f"Elapsed: {format_duration(time.monotonic() - start)}")

    if args.run and not args.experimental_run:
        print("Python batch placement is currently disabled for production.")
        print("Use the AutoCAD command path instead:")
        print("  APPLOAD 05_toolkit/lisp/bscallout.lsp")
        print("  BSCALLOUT-AUTO")
        print("For diagnostics only, rerun with --run --experimental-run.")
        return 2

    if args.run:
        if not has_runnable_placements(accepted):
            print("Run requested, but there are 0 accepted callouts. Nothing was sent to AutoCAD.")
            print("Open the report and resolve the manual-review conflicts before running again.")
            return 0
        print("Sending generated batch to AutoCAD...")
        status = run_batch(doc, batch_path, accepted)
        print(f"Batch command completed in AutoCAD: {status}")
    else:
        print("Plan-only mode. Run again with --run to place these callouts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
