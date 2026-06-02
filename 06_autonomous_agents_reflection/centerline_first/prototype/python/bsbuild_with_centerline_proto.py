#!/usr/bin/env python3
"""Run the existing bsbuild flow, then add prototype centerline outputs."""

from __future__ import annotations

import os
import sys
from pathlib import Path


THIS_FILE = Path(__file__).resolve()
REPO_ROOT = THIS_FILE.parents[4]
PYTHON_TOOLKIT = REPO_ROOT / "05_toolkit" / "python"

sys.path.insert(0, str(PYTHON_TOOLKIT))
sys.path.insert(0, str(THIS_FILE.parent))

import bsbuild  # noqa: E402
import centerline_candidate  # noqa: E402


def write_centerline_outputs(kmz: Path, job_dir: Path) -> None:
    out_dir = job_dir / "02_centerline_candidates"
    out_dir.mkdir(parents=True, exist_ok=True)

    parts = centerline_candidate.load_route(kmz)
    parts = centerline_candidate.project_if_needed(parts, 2264)
    segments = centerline_candidate.build_segments(parts, 500.0)

    centerline_candidate.write_manifest(out_dir / "centerline_segments.json", kmz, segments, 2264)
    centerline_candidate.write_scr(out_dir / "centerline_candidate.scr", segments)

    bsbuild.log(f"Centerline prototype outputs:")
    bsbuild.log(f"  -> {out_dir / 'centerline_segments.json'}")
    bsbuild.log(f"  -> {out_dir / 'centerline_candidate.scr'}")
    bsbuild.log(f"  Candidate segments: {len(segments)}")


def main() -> int:
    selected_kmz: dict[str, Path] = {}
    original_get_kmz = bsbuild.get_kmz

    def capture_kmz() -> Path | None:
        kmz = original_get_kmz()
        if kmz:
            selected_kmz["path"] = kmz
        return kmz

    bsbuild.get_kmz = capture_kmz
    os.environ.setdefault("BSBUILD_PAUSE", "1")

    rc = bsbuild.main()
    if rc != 0:
        return rc

    kmz = selected_kmz.get("path")
    if not kmz:
        bsbuild.log("WARN: no KMZ captured; centerline prototype outputs skipped.")
        return 0

    job_dir = kmz.parent / bsbuild.derive_job_name(kmz)
    try:
        write_centerline_outputs(kmz, job_dir)
    except Exception as exc:
        bsbuild.log(f"WARN: bsbuild succeeded, but centerline prototype generation failed: {exc}")
        return 2

    bsbuild.log("")
    bsbuild.log("Next AutoCAD prototype step:")
    bsbuild.log("  1. Open the WORKING DWG created by bsbuild.")
    bsbuild.log("  2. Run SCRIPT and select 02_centerline_candidates/centerline_candidate.scr.")
    bsbuild.log("  3. APPLOAD prototype/lisp/bsclproto.lsp.")
    bsbuild.log("  4. Run BSCLAPPROVE, then BSCLPROMOTE only after review.")
    return 0


if __name__ == "__main__":
    try:
        exit_code = main()
    except KeyboardInterrupt:
        bsbuild.log("Interrupted.")
        exit_code = 1
    if os.environ.get("BSBUILD_PAUSE", "1") == "1":
        input("\nPress Enter to close...")
    raise SystemExit(exit_code)
