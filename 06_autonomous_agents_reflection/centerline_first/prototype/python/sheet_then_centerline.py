#!/usr/bin/env python3
"""Prototype stage runner: route/KMZ -> proposed sheets -> candidate centerlines."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


THIS_FILE = Path(__file__).resolve()
REPO_ROOT = THIS_FILE.parents[4]
PYTHON_TOOLKIT = REPO_ROOT / "05_toolkit" / "python"

sys.path.insert(0, str(PYTHON_TOOLKIT))
sys.path.insert(0, str(THIS_FILE.parent))

import bssheetplan  # noqa: E402
import centerline_candidate  # noqa: E402


DEFAULT_CONFIG = REPO_ROOT / "05_toolkit" / "config" / "bssheet_config.json"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="KMZ/KML/GeoJSON/CSV/TXT route source.")
    parser.add_argument("--out-dir", required=True, type=Path, help="Prototype output folder.")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="Sheet config JSON.")
    parser.add_argument("--target-epsg", type=int, default=2264)
    parser.add_argument("--max-centerline-segment-ft", type=float, default=500.0)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    input_path = args.input.expanduser().resolve()
    out_dir = args.out_dir.expanduser().resolve()
    config_path = args.config.expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    sheet_dir = out_dir / "01_sheets"
    centerline_dir = out_dir / "02_centerline_candidates"
    sheet_dir.mkdir(exist_ok=True)
    centerline_dir.mkdir(exist_ok=True)

    config = bssheetplan.load_config(config_path)
    sheets, report = bssheetplan.build_plan(input_path, config)
    bssheetplan.write_plan_csv(sheet_dir / "bssheet_plan.csv", sheets)
    bssheetplan.write_plan_lsp(sheet_dir / "bssheet_plan.lsp", sheets, config, report)
    bssheetplan.write_report(sheet_dir / "bssheet_report.txt", report)

    parts = centerline_candidate.load_route(input_path)
    parts = centerline_candidate.project_if_needed(parts, args.target_epsg)
    segments = centerline_candidate.build_segments(parts, args.max_centerline_segment_ft)
    centerline_candidate.write_manifest(
        centerline_dir / "centerline_segments.json",
        input_path,
        segments,
        args.target_epsg,
    )
    centerline_candidate.write_scr(centerline_dir / "centerline_candidate.scr", segments)

    print("Prototype outputs written:")
    print(f"  sheets:     {sheet_dir}")
    print(f"  centerline: {centerline_dir}")
    print(f"Sheet count: {len(sheets)}")
    print(f"Centerline candidate segments: {len(segments)}")
    print("")
    print("Recommended AutoCAD order:")
    print("  1. APPLOAD 01_sheets/bssheet_plan.lsp")
    print("  2. Run BSSHEETMAKEPLAN")
    print("  3. Review proposed orange sheets")
    print("  4. Run SCRIPT with 02_centerline_candidates/centerline_candidate.scr")
    print("  5. APPLOAD prototype/lisp/bsclproto.lsp")
    print("  6. Run BSCLAPPROVE, then BSCLPROMOTE only when validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
