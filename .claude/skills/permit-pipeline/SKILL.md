# Permit Pipeline — End-to-End Runbook

## Overview
KMZ from field → NCDOT-compliant permit drawing set.

```
Field KMZ  →  BSKMZ import  →  ROW + labeling  →  Sheet layout  →  Cleanup + audit  →  Submit
```

## Prerequisites
- AutoCAD Map 3D 2027 open on Windows.
- `APPLOAD → 05_toolkit/lisp/bs_loader.lsp` (run once per session).
- `BSINSTALLCHECK` passes (all required blocks present).
- DWG template: `BSP NCDOT TEMPLATE 04-07-2026.dwg` open or referenced.
- KMZ file accessible on Windows local drive (not Mac shared path).

---

## Stage 1 — Field data import

```
BSKMZ           → pick KMZ → places fiber lines, HHs, bore pits, poles
BSROW           → pick each centerline → draws ROW + EOP + TRAP
BSKMZ-SNAP      → snap fiber 4' from ROW, align HH, snap aerial to poles
BSFILLET-ALL    → fillet all ROW/EOP corners (R=25')
```

Verify after:
- All fiber on correct layers.
- HH/bore blocks perpendicular to CL.
- No fiber outside NCDOT ROW without red arrow + note.

---

## Stage 2 — Sheet layout

```
BSSHEETKMZ      → import KMZ + auto-place proposed sheet rectangles
BSSHEETACCEPT   → confirm rectangles → promotes to BORDER layer
```

Rules:
- Max 25 sheets per permit.
- Profiles at the end.
- Freeze BORDER layer in permit sheets.

---

## Stage 3 — Labeling and annotation

```
BSCALLOUT-AUTO  → label all buried fiber runs (HDD BORE N' FIBER IN 2" DUCT)
BSAERIAL-AUTO   → label all aerial runs (no footage)
BSSTATION       → station all HHs, bore pits, poles
BSWORKAREA      → place WORK AREA START/END labels with lat/lon
BSMINERDOC      → place MIN D.O.C. 60" note on underground sheets
BSROWDIMS1      → ROW dimension stack on each sheet border
```

---

## Stage 4 — Property line cleanup

```
BSPARCELS       → snap parcel lines to ROW boundary
BSPARHIDE       → hide parcel lines parallel to ROW
BSPARSNAP       → snap perpendicular property line endpoints to ROW
```

---

## Stage 5 — Border cleanup

```
BSCLEANRECT     → draw cleanup limit rectangle
BSCLEAN         → trim linework to BORDER rectangles
BSCLEANUP       → pre-submission cleanup (widths, images, duplicates)
```

---

## Stage 6 — Audit and submission

```
BSAUDIT         → 8-check compliance scan; fix any FIX-severity findings
```

BSAUDIT checks:
1. All fiber on correct layers.
2. Label formats match NCDOT spec (STA XX+XX PL HANDHOLE, etc.).
3. Sheet count ≤ 25.
4. MIN DOC 60" present on underground sheets.
5. Text heights correct (5.0 / 6.0).
6. ROW dimensions present on all borders.
7. WORK AREA labels formatted correctly.
8. No manually assigned colors.

After BSAUDIT passes: export to PDF, submit to NCDOT.

---

## Common failure modes
| Symptom | Cause | Fix |
|---|---|---|
| BSKMZ says "blocks missing" | NDS_HH, BORE PIT, or TELPOLE1262023 not in DWG | Insert one of each by hand → re-run BSKMZ |
| BSKMZ path error | KMZ on Mac shared drive | Copy KMZ to Windows local drive first |
| BSROWDIMS places nothing | CL span < 40' or ROAD-CENTERLINE layer not found | Run BSROWDIMS-DIAG on border; verify layer names |
| Labels wrong side of fiber | Perpendicular direction flipped | Run BSCALLOUT manually; pick label point on correct side |
| Dims not parallel | ref-nvec drift on curved road | Already fixed in V2 — reload bs_loader.lsp |

---

## Two-machine workflow
- **Mac** = orchestration (Claude Code, git, file editing).
- **Windows** = execution (AutoCAD Map 3D, `.lsp` commands).
- Sync via: `git pull` on Windows before each AutoCAD session; `git push` after edits.
- DWG files stay on Windows local drive — never commit `.dwg` to git.
