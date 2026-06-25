#!/usr/bin/env python3
"""Static audit for the isolated gileCAD AutoLISP research import."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTES = ROOT / "notes"
SCAN_EXTENSIONS = {".lsp", ".dcl", ".txt", ".fas", ".vlx"}
COMPILED_EXTENSIONS = {".fas", ".vlx"}

USE_PATTERNS = {
    "command": r"\(\s*command\b",
    "command-s": r"\(\s*command-s\b",
    "entmake": r"\(\s*entmake\b",
    "entmakex": r"\(\s*entmakex\b",
    "entmod": r"\(\s*entmod\b",
    "vla-": r"\bvla-[A-Za-z0-9_-]+",
    "vlax-": r"\bvlax-[A-Za-z0-9_-]+",
    "ssget": r"\(\s*ssget\b",
    "IntersectWith": r"\bIntersectWith\b",
    "vlax-curve-getPointAtDist": r"\bvlax-curve-getPointAtDist\b",
    "vlax-curve-getClosestPointTo": r"\bvlax-curve-getClosestPointTo\b",
    "AddMLeader": r"\bAddMLeader\b",
    "MLeader": r"\bMLeader\b",
    "BackgroundFill": r"\bBackgroundFill\b",
    "mtext": r"\bmtext\b",
    "text frame": r"\b(TextFrame|text frame|cadre)\b",
    "wipeout": r"\bwipeout\b",
    "block/insert/attributes": r"\b(block|insert|insertblock|attribute|attrib|attdef|attedit)\b",
    "dictionaries/xdata": r"\b(dictadd|dictsearch|namedobjdict|regapp|xdata|1001|1002|1003|1004|1005)\b",
}

RELEVANCE_PATTERNS = {
    "callout/mleader": r"\b(callout|leader|mleader|AddMLeader|acMLeader|qleader)\b",
    "text background mask": r"\b(backgroundfill|background fill|textmask|wipeout|mask|frame)\b",
    "arrow/leader creation": r"\b(arrow|leader|qleader|mleader)\b",
    "polyline splitting": r"\b(split|break|breakat|segment|vertex|vertices|polyline|lwpolyline)\b",
    "point along curve": r"\b(vlax-curve-getPointAtDist|getPointAtDist|distance along|point at)\b",
    "intersection": r"\b(intersect|IntersectWith|inters)\b",
    "block handling": r"\b(block|insertblock|insert|attribute|attrib|attdef)\b",
    "selection filtering": r"\b(ssget|filter|selection set|ssname|sslength)\b",
    "bounding boxes": r"\b(GetBoundingBox|bounding box|bbox|minpoint|maxpoint)\b",
    "collision/placement helpers": r"\b(collision|overlap|place|placement|clearance|offset)\b",
    "layer utilities": r"\b(layer|layfrz|layiso|tblsearch\s+\"layer\"|vla-add.*layers)\b",
    "sort/draw order": r"\b(draworder|sort|order|sendtoback|bringtofront)\b",
}

RISK_PATTERNS = {
    "erase/delete": r"\b(erase|delete|vla-delete|entdel)\b",
    "save/saveas": r"\b(qsave|saveas|save)\b",
    "hardcoded paths": r"([A-Za-z]:\\|\\\\|/Users/|/Volumes/|//Mac/|\\Mac\\|Z:\\)",
    "global setvar without restore": r"\(\s*setvar\b",
    "obfuscated code": r"(\\x[0-9A-Fa-f]{2}|eval\s*\(|read\s*\(|apply\s*\(|vl-string-translate)",
    "destructive commands": r"\b(purge|audit|overkill|explode|delete|erase|wblock|recover)\b",
}


@dataclass
class AuditRecord:
    path: Path
    suffix: str
    title: str = ""
    author: str = ""
    license_info: str = ""
    commands: list[str] = field(default_factory=list)
    helpers: list[str] = field(default_factory=list)
    uses: list[str] = field(default_factory=list)
    risk_flags: list[str] = field(default_factory=list)
    relevance_hits: list[str] = field(default_factory=list)
    relevance_score: int = 0
    risk_level: str = "low"
    purpose_guess: str = ""


def decode_text(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-8", "latin-1", "cp1252"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def looks_like_lisp(text: str, suffix: str) -> bool:
    if suffix in {".lsp", ".dcl"}:
        return True
    return bool(re.search(r"\(\s*(defun|setq|command|vl-load-com|ssget)\b", text, re.I))


def first_match(patterns: list[str], lines: list[str]) -> str:
    for line in lines[:80]:
        stripped = line.strip(" ;\t")
        for pattern in patterns:
            match = re.search(pattern, stripped, re.I)
            if match:
                value = match.group(1).strip(" :-\t") if match.groups() else stripped
                return value[:120]
    return ""


def detect_license(text: str, path: Path) -> str:
    name = path.name.lower()
    if "license" in name or "licence" in name:
        return "license file"
    if "readme" in name:
        return "readme file"
    patterns = [
        "MIT License",
        "GNU General Public License",
        "GPL",
        "LGPL",
        "Creative Commons",
        "public domain",
        "copyright",
        "all rights reserved",
        "freeware",
    ]
    found = [pattern for pattern in patterns if re.search(re.escape(pattern), text, re.I)]
    return ", ".join(found)


def extract_header(lines: list[str]) -> tuple[str, str]:
    title = first_match([r"^(?:title|routine|program|name)\s*[:=-]\s*(.+)$"], lines)
    author = first_match([r"^(?:author|by|written by)\s*[:=-]\s*(.+)$"], lines)

    if not title:
        for line in lines[:25]:
            stripped = line.strip(" ;\t")
            if stripped and not stripped.startswith("(") and len(stripped) > 4:
                title = stripped[:120]
                break
    return title, author


def public_commands(text: str) -> list[str]:
    return sorted({m.group(1).upper() for m in re.finditer(r"\(\s*defun\s+c:([A-Za-z0-9_*+\-]+)", text, re.I)})


def helper_functions(text: str) -> list[str]:
    helpers = set()
    for match in re.finditer(r"\(\s*defun\s+([A-Za-z0-9_*+\-:]+)", text, re.I):
        name = match.group(1)
        if not name.lower().startswith("c:"):
            helpers.add(name)
    return sorted(helpers, key=str.lower)


def purpose_from_hits(record: AuditRecord) -> str:
    if record.commands:
        return f"Command routine: {', '.join(record.commands[:3])}"
    if "callout/mleader" in record.relevance_hits:
        return "Leader/callout or annotation helper"
    if "polyline splitting" in record.relevance_hits or "point along curve" in record.relevance_hits:
        return "Polyline or curve geometry helper"
    if "block handling" in record.relevance_hits:
        return "Block or attribute helper"
    if "selection filtering" in record.relevance_hits:
        return "Selection/filter helper"
    if record.suffix in COMPILED_EXTENSIONS:
        return "Compiled AutoLISP binary"
    return "General AutoLISP/DCL utility"


def risk_level(flags: list[str], text: str, suffix: str) -> str:
    if suffix in COMPILED_EXTENSIONS:
        return "high"
    high = {"save/saveas", "hardcoded paths", "obfuscated code"}
    if any(flag in high for flag in flags):
        return "high"
    if "destructive commands" in flags and "missing error handler" in flags:
        return "high"
    if flags:
        return "medium"
    return "low"


def audit_file(path: Path) -> AuditRecord | None:
    suffix = path.suffix.lower()
    record = AuditRecord(path=path, suffix=suffix)

    if suffix in COMPILED_EXTENSIONS:
        record.risk_flags = ["compiled-only .vlx/.fas"]
        record.risk_level = "high"
        record.purpose_guess = "Compiled AutoLISP binary"
        return record

    try:
        text = decode_text(path)
    except OSError:
        return None

    if not looks_like_lisp(text, suffix):
        return None

    lines = text.splitlines()
    record.title, record.author = extract_header(lines)
    record.license_info = detect_license(text, path)
    record.commands = public_commands(text)
    record.helpers = helper_functions(text)

    for name, pattern in USE_PATTERNS.items():
        if re.search(pattern, text, re.I):
            record.uses.append(name)

    for name, pattern in RISK_PATTERNS.items():
        if re.search(pattern, text, re.I):
            record.risk_flags.append(name)

    if record.commands and not re.search(r"\*error\*", text, re.I):
        record.risk_flags.append("missing error handler")

    if "global setvar without restore" in record.risk_flags:
        setvars = re.findall(r"\(\s*setvar\s+\"([A-Za-z0-9]+)\"", text, re.I)
        restored = any(re.search(rf"\(\s*setvar\s+\"{re.escape(var)}\"\s+[^)]*old", text, re.I) for var in setvars)
        if restored or re.search(r"\*error\*.*setvar", text, re.I | re.S):
            record.risk_flags.remove("global setvar without restore")

    for name, pattern in RELEVANCE_PATTERNS.items():
        if re.search(pattern, text, re.I):
            record.relevance_hits.append(name)

    record.relevance_score = len(record.relevance_hits) * 10
    if "callout/mleader" in record.relevance_hits:
        record.relevance_score += 15
    if "point along curve" in record.relevance_hits:
        record.relevance_score += 12
    if "intersection" in record.relevance_hits:
        record.relevance_score += 10
    if "text background mask" in record.relevance_hits:
        record.relevance_score += 10
    if record.risk_flags:
        record.relevance_score = max(0, record.relevance_score - 2 * len(record.risk_flags))

    record.risk_level = risk_level(record.risk_flags, text, suffix)
    record.purpose_guess = purpose_from_hits(record)
    return record


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def md_escape(value: object) -> str:
    text = str(value) if value is not None else ""
    return text.replace("|", "\\|").replace("\n", " ")


def write_audit_index(records: list[AuditRecord]) -> None:
    lines = [
        "# AutoLISP Goldmine Audit Index",
        "",
        f"- Generated: {datetime.now().isoformat(timespec='seconds')}",
        f"- Files audited: {len(records)}",
        "",
        "| File | Purpose guess | Commands | Helper count | Risk level | Relevance score |",
        "|---|---|---:|---:|---|---:|",
    ]
    for record in sorted(records, key=lambda item: (-item.relevance_score, rel(item.path).lower())):
        commands = ", ".join(record.commands) if record.commands else ""
        lines.append(
            f"| {md_escape(rel(record.path))} | {md_escape(record.purpose_guess)} | "
            f"{md_escape(commands)} | {len(record.helpers)} | {record.risk_level} | {record.relevance_score} |"
        )
    (NOTES / "AUDIT_INDEX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def top_records(records: list[AuditRecord], predicate, limit: int = 15) -> list[AuditRecord]:
    return sorted([record for record in records if predicate(record)], key=lambda item: (-item.relevance_score, rel(item.path).lower()))[:limit]


def write_useful_patterns(records: list[AuditRecord]) -> None:
    lines = [
        "# Useful Patterns",
        "",
        "Unknown-license external code is reference-only. Reimplement ideas cleanly before using them in Brightspeed production commands.",
        "",
    ]
    groups = [
        ("Callouts and leaders", lambda r: any(hit in r.relevance_hits for hit in ("callout/mleader", "arrow/leader creation", "text background mask"))),
        ("Curve and route geometry", lambda r: any(hit in r.relevance_hits for hit in ("polyline splitting", "point along curve", "intersection", "bounding boxes"))),
        ("Selection, block, and layer utilities", lambda r: any(hit in r.relevance_hits for hit in ("selection filtering", "block handling", "layer utilities", "sort/draw order"))),
    ]
    for title, predicate in groups:
        lines.append(f"## {title}")
        matches = top_records(records, predicate, 10)
        if not matches:
            lines.append("")
            lines.append("No strong matches found.")
            lines.append("")
            continue
        for record in matches:
            teaches = ", ".join(record.relevance_hits[:5])
            lines.append(f"- `{rel(record.path)}`: {record.purpose_guess}. Teaches: {teaches}. Brightspeed use: clean-room pattern reference.")
        lines.append("")
    (NOTES / "USEFUL_PATTERNS.md").write_text("\n".join(lines), encoding="utf-8")


def write_finding_report(
    filename: str,
    title: str,
    records: list[AuditRecord],
    keywords: list[str],
    summary: str,
    brightspeed_read: str,
) -> None:
    matches = top_records(records, lambda r: any(hit in r.relevance_hits for hit in keywords) or any(use in r.uses for use in keywords), 20)
    lines = [
        f"# {title}",
        "",
        summary,
        "",
        "## Brightspeed read",
        "",
        brightspeed_read,
        "",
        "| File | Relevant hits | Uses | Risk | Notes |",
        "|---|---|---|---|---|",
    ]
    if not matches:
        lines.append("| _None found_ |  |  |  |  |")
    for record in matches:
        lines.append(
            f"| {md_escape(rel(record.path))} | {md_escape(', '.join(record.relevance_hits))} | "
            f"{md_escape(', '.join(record.uses))} | {record.risk_level} | {md_escape(record.purpose_guess)} |"
        )
    (NOTES / filename).write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_risky_or_ignore(records: list[AuditRecord]) -> None:
    risky = [record for record in records if record.risk_level in {"medium", "high"} or record.license_info]
    lines = [
        "# Risky Or Ignore",
        "",
        "Treat files without explicit permissive licensing as reference-only. Do not load compiled or destructive routines into AutoCAD.",
        "",
        "| File | Risk level | Flags | License/readme signal | Recommendation |",
        "|---|---|---|---|---|",
    ]
    for record in sorted(risky, key=lambda item: (item.risk_level != "high", rel(item.path).lower())):
        recommendation = "Ignore/load never" if record.suffix in COMPILED_EXTENSIONS else "Reference-only; inspect before reimplementation"
        if not record.license_info:
            recommendation += "; license unclear"
        lines.append(
            f"| {md_escape(rel(record.path))} | {record.risk_level} | {md_escape(', '.join(record.risk_flags))} | "
            f"{md_escape(record.license_info)} | {recommendation} |"
        )
    (NOTES / "RISKY_OR_IGNORE.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_recommendations(records: list[AuditRecord]) -> None:
    def best(*hits: str) -> list[AuditRecord]:
        return top_records(records, lambda r: any(hit in r.relevance_hits or hit in r.uses for hit in hits), 3)

    ideas = [
        ("Callout MLeader creation", best("callout/mleader", "AddMLeader", "MLeader")),
        ("Text background masks for callouts", best("text background mask", "BackgroundFill", "wipeout", "text frame", "mtext")),
        ("Sheet-aware repeated callout placement", best("point along curve", "collision/placement helpers", "bounding boxes")),
        ("Route splitting and segment extraction", best("polyline splitting", "point along curve")),
        ("Bore pit insertion at 90-degree bends", best("intersection", "polyline splitting", "point along curve")),
        ("Handhole and bore pit block handling", best("block handling", "block/insert/attributes")),
        ("Selection filtering for fiber and structure entities", best("selection filtering", "ssget")),
        ("Layer utilities with BYLAYER-safe reimplementation", best("layer utilities")),
        ("Draw order and mask ordering", best("sort/draw order", "text background mask")),
        ("Curve math helper library", best("intersection", "bounding boxes", "point along curve")),
    ]
    lines = [
        "# Brightspeed Recommendations",
        "",
        "Top clean-room reimplementation ideas from the static audit. These are not merge approvals.",
        "",
    ]
    for index, (idea, matches) in enumerate(ideas, start=1):
        lines.append(f"{index}. {idea}")
        if not matches:
            lines.append("   - Source candidates: none found in this import.")
            lines.append("   - Recommendation: implement from Brightspeed requirements without relying on this library.")
            lines.append("")
            continue
        source_list = "; ".join(f"`{rel(record.path)}` ({record.risk_level}, score {record.relevance_score})" for record in matches)
        hit_list = "; ".join(f"{rel(record.path)}: {', '.join(record.relevance_hits) or ', '.join(record.uses)}" for record in matches[:2])
        lines.append(f"   - Source candidates: {source_list}")
        lines.append(f"   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.")
        lines.append(f"   - Evidence: {hit_list}")
        lines.append("")
    (NOTES / "BRIGHTSPEED_RECOMMENDATIONS.md").write_text("\n".join(lines), encoding="utf-8")


def write_summary(records: list[AuditRecord]) -> None:
    source_count = len([record for record in records if record.suffix not in COMPILED_EXTENSIONS])
    compiled_count = len([record for record in records if record.suffix in COMPILED_EXTENSIONS])
    license_records = [record for record in records if record.license_info]
    lines = [
        "# Audit Summary",
        "",
        f"- Generated: {datetime.now().isoformat(timespec='seconds')}",
        f"- Text/DCL/LISP files audited: {source_count}",
        f"- Compiled files flagged: {compiled_count}",
        f"- Files with license/readme signals: {len(license_records)}",
        "",
        "## Top 10 Relevant Files",
        "",
    ]
    for record in sorted(records, key=lambda item: (-item.relevance_score, rel(item.path).lower()))[:10]:
        lines.append(f"- `{rel(record.path)}`: score {record.relevance_score}, risk {record.risk_level}, hits {', '.join(record.relevance_hits) or 'none'}")
    (NOTES / "AUDIT_SUMMARY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    NOTES.mkdir(parents=True, exist_ok=True)
    records: list[AuditRecord] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in SCAN_EXTENSIONS:
            continue
        if "notes" in path.relative_to(ROOT).parts:
            continue
        record = audit_file(path)
        if record:
            records.append(record)

    write_audit_index(records)
    write_useful_patterns(records)
    write_finding_report(
        "MLEADER_AND_CALLOUT_FINDINGS.md",
        "MLeader And Callout Findings",
        records,
        ["callout/mleader", "arrow/leader creation", "text background mask", "AddMLeader", "MLeader", "BackgroundFill", "wipeout"],
        "Static scan for MLeader creation, leader arrows, mtext/background mask, text frames, and wipeout-style text masks.",
        "The import has callout-adjacent material, but no drop-in Brightspeed fix. `gc_AutomationHelpers.lsp` is the only direct MLeader signal; `Cadre_Masque.lsp` and `Obj2wipeout.lsp` are more relevant for text masks and draw-order behavior. All should remain reference-only unless licensing is clarified and patterns are reimplemented cleanly.",
    )
    write_finding_report(
        "POLYLINE_AND_GEOMETRY_FINDINGS.md",
        "Polyline And Geometry Findings",
        records,
        ["polyline splitting", "point along curve", "intersection", "bounding boxes", "collision/placement helpers"],
        "Static scan for route segmentation, vertex edits, curve walking, closest-point helpers, intersections, and placement geometry.",
        "`gc_MathGeom.lsp`, `AddVtx_DelVtx.LSP`, `PolySegments.lsp`, and `Special_selections.lsp` contain the strongest route-geometry ideas. These can inform clean-room implementations for route segmentation, point-at-distance callout spacing, 90-degree bend detection, and sheet-aware placement checks.",
    )
    write_risky_or_ignore(records)
    write_recommendations(records)
    write_summary(records)

    print(f"files_audited={len(records)}")
    print(f"lisp_like_text_files={len([r for r in records if r.suffix not in COMPILED_EXTENSIONS])}")
    print(f"compiled_flagged={len([r for r in records if r.suffix in COMPILED_EXTENSIONS])}")
    print(f"reports_dir={NOTES}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
