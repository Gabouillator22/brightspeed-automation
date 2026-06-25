# SESSION NOTES — Brightspeed AutoLISP Toolkit

Session date: 2026-05-26  
Developer: Claude Sonnet 4.6 (autonomous session)

---

## 2026-06-03 Loader Registry Audit

### Scope

Static audit of the command registry across `05_toolkit/lisp/*.lsp`, with
loader-order and alias coverage checked against `bs_loader.lsp` and
`bs_helpers.lsp`.

### Findings

- All active command files are loaded by `bs_loader.lsp`.
- Legacy files `brightspeed_core.lsp` and `bsrow_v5.lsp` are intentionally
  not loaded.
- `bscleanvp.lsp` is also intentionally not loaded because the active cleanup
  workflow lives in `bsclean_border.lsp`.
- `BSSHEETMAKEPLAN` is conditional: it is defined only after `BSSHEETLOAD`
  successfully loads `bssheet_plan.lsp`.
- Duplicate `c:` definitions exist only in compatibility wrappers or disabled
  aliases:
  - `BSMAP`, `BCMAP`, `BSCLMAP`
  - `BSDIMS`, `BSDIM1`, `BSDIMC`, `BSDIAG`
  - `BSCLEANMASK` (the later stub intentionally overrides the older mask-maker)

### Result

No active loader-order bug was found in the current source tree. The registry
is complete for the loaded workflow, but the live AutoCAD APPLOAD +
`BSINSTALLCHECK` path still needs a runtime confirmation run.

---

## 2026-05-27 Cleanup Stabilization

### Fixed

The previous `bscleanvp.lsp` implementation had accumulated stale command
bindings while testing with multiple tools. AutoCAD could keep public commands
such as `BSCLEANAUTO` in memory while the internal helper function was not
available, producing errors like:

`no function definition: BSC_CLEANVP_MAIN` or `no function definition: BSCCLEANRUN`

### New active file

| File | Commands | Purpose |
|------|----------|---------|
| `bsclean_border.lsp` | `BSCLEANRECT`, `BSCLEAN` | Active two-command border cleaner |
| `bscleanvp.lsp` | compatibility shim only | Redirects old APPLOAD habits to `bsclean_border.lsp` |

### Loader change

`bs_loader.lsp` no longer loads the old `bscleanvp.lsp` implementation.
It loads `bsclean_border.lsp` last so it owns these command names:

- `BSCLEANRECT`
- `BSCLEAN`
- `BSCLEANLIMIT`
- `TRIMAGE`
- `BSCLEANVP`
- `BSCLEANAUTO`

### Cleanup workflow

1. `APPLOAD` -> load `bs_loader.lsp`
2. Confirm command line says `[BSCLEAN_BORDER] Loaded v1`
3. Run `BSCLEANRECT` and draw the large cleanup rectangle
4. Run `BSCLEAN`

### Safety model

The cleaner never deletes production entities. When clipping is required, it:

- recreates kept portions inside `BORDER` rectangles
- moves the original entity to `BS-CLEAN-HIDDEN`
- freezes `BS-CLEAN-HIDDEN`

This keeps cleanup undoable with `Ctrl+Z` and recoverable by thawing the hidden
layer.

---

## What Was Completed

### New files created

| File | Commands | Status |
|------|----------|--------|
| `bs_helpers.lsp` | Shared helpers (bs- prefix) | New |
| `bsfillet_all.lsp` | BSFILLET-ALL | New (rewrite) |
| `bscallout.lsp` | BSCALLOUT, BSCALLOUT-AUTO | New |
| `bsaerial.lsp` | BSAERIAL, BSAERIAL-AUTO | New |
| `bsstation.lsp` | BSSTATION | New |
| `bsdrive.lsp` | BSDRIVE | New |
| `bsworkarea.lsp` | BSWORKAREA | New |
| `bsminerdoc.lsp` | BSMINERDOC | New |
| `bsaudit.lsp` | BSAUDIT (8 checks) | New (rewrite) |
| `bscleanup.lsp` | BSCLEANUP | New |
| `README.md` | Full documentation | New |

### Modified files

| File | Change |
|------|--------|
| `bs_loader.lsp` | Complete rewrite — loads bs_helpers.lsp first, uses bsrow.lsp (v5.1), adds all 10 new commands |

---

## What Changed vs Original

### bs_loader.lsp
- **Was:** Loaded bsrow_v5.lsp (v5 with TRAP direction bug), did not load bs_helpers.lsp
- **Now:** Loads bs_helpers.lsp FIRST (required by all new command files), then loads bsrow.lsp (v5.1 with TRAP fix), then all new commands

### bsrow version selection
- `bsrow.lsp` = v5.1 (in repo, has TRAP direction bug fix + explicit layer ON/THAW)
- `bsrow_v5.lsp` = v5 (older, missing TRAP fix)
- The loader now uses `bsrow.lsp` (v5.1). The file `bsrow_v5.lsp` is kept but no longer loaded.

### bsfillet_all.lsp
- Previous version had internal `defun` definitions inside `c:BSFILLET-ALL` (unreliable in some AutoLISP environments)
- Previous version passed entity names to FILLET command (incorrect — FILLET needs pick points)
- New version: top-level defuns, uses entity midpoints as pick points, checks that intersection is near an endpoint (corner test)

### bsaudit.lsp
- Previous version unknown (not present in file system)
- New version: 8 checks fully implemented

---

## Architecture Decisions

### bs_helpers.lsp as shared foundation
All new command files depend on `bs_helpers.lsp` for:
- `bs-ensure-layer` / `bs-force-layer`
- Vector math (`bs-vsub`, `bs-vunit`, etc.)
- Entity geometry (`bs-ent-midpt`, `bs-ent-startpt`, `bs-ent-endpt`)
- Distance and tangent helpers
- `bs-intersect-first` / `bs-intersect-all` (IntersectWith wrappers)
- `bs-make-text` / `bs-make-line` (entmake-based, no command dependencies)
- `bs-format-station` (feet → STA XX+XX.X)
- `bs-replace-nth-vertex` (LWPOLYLINE vertex editing)

### Existing helper functions NOT consolidated
`bsparcels.lsp` uses `bsp-*` prefix helpers.  
`bsparsnap.lsp` uses `bsps-*` prefix helpers.  
These were left unchanged to avoid breaking working code.  
The `bs-*` helpers in `bs_helpers.lsp` are an additive addition for new commands only.

### callout and leader implementation
Uses `entmake` for TEXT and LINE entities directly.  
**Does not** use `MLEADER` or `LEADER` or `QLEADER` commands.  
Rationale: command-based leaders have prompt timing issues in AutoLISP, and the `entmake` approach is deterministic and version-independent.

### BSDRIVE endpoint calculation
Uses `IntersectWith(acExtendBoth=3)` + `entmod` to set LWPOLYLINE vertices.  
**Does not** use `TRIM`/`EXTEND` commands.  
Rationale: TRIM/EXTEND commands can change entity handles in AutoCAD, making follow-up entget unreliable.

### BSWORKAREA coordinate conversion
Attempts `vlax-get-property ... 'Map` → `vlax-invoke ... 'WcsToLl`.  
Falls back to user manual entry if Map 3D API is unavailable or drawing has no coordinate system.  
Fallback: shows WCS coordinates in the label.

---

## Known Issues / Limitations

### BSFILLET-ALL pick-point reliability
`FILLET` command receives midpoints of each entity as pick points. In drawings with many overlapping entities near the midpoint area, AutoCAD may snap to the wrong entity. Frequency: low in typical Brightspeed drawings (long, separated ROW/EOP lines). Workaround: manual fillet at affected corners + Ctrl+Z if wrong.

### BSWORKAREA coordinate accuracy
The `vlax-invoke ... 'WcsToLl` path is an attempt at the Map 3D API. The exact method name may differ between Map 3D versions. If it fails silently, the user will be prompted for manual entry. For production accuracy: configure NC83F coordinate system in Map 3D → Map → Drawing Settings.

### BSSTATION station 0+00 reference
Station is measured from the START vertex of the nearest fiber polyline. There is no global "project station 0+00" defined. If fiber polylines are broken into segments (multiple polylines), each segment has its own 0+00. For accurate total-project stationing, merge fiber into one continuous polyline first.

### BSAUDIT Check 3 proximity radius
"Callout within 50' of fiber midpoint" is a heuristic. Long fiber segments may have the callout near one end, far from the midpoint. Workaround: place callout near the midpoint, or adjust the `50.0` threshold in `bsaudit.lsp` line ~110.

### BSAUDIT ssget filter for text content
AutoCAD DXF group 1 wildcard filter `(cons 1 "*WORK AREA*")` works for TEXT entities but may not match all MTEXT content (MTEXT stores formatted strings in group 3 for overflow). If WORK AREA labels are MTEXT, CHECK 7 may show a false positive. Resolution: ensure BSWORKAREA-placed text is used (it creates TEXT entities via entmake, not MTEXT).

### BSCLEANUP POLYLINE (3D) width
For POLYLINE (heavy polyline) entities, uses `vla-put-ConstantWidth`. This requires the Visual LISP COM interface and may fail on older POLYLINE types. LWPOLYLINE (the common type) is handled correctly.

---

## Recommended Next Steps

1. **Test BSDRIVE** on a live drawing with known ROW and EOP lines. The virtual intersection calculation assumes the driveway line, when extended, will intersect those lines. If EOP/ROW lines are very short or end before the driveway line reaches them, the intersection may be nil.

2. **Test BSFILLET-ALL** on the standard intersection scenario. Verify fillet count vs expected.

3. **Configure NC83F coordinate system** in Map 3D (Map → Drawing Settings → Coordinate System → NC83F) to enable BSWORKAREA automatic lat/lon conversion.

4. **Consider BSCALLOUT text justification.** Currently all callout TEXT is left-aligned. A center-aligned or right-aligned option could improve layout in tight spaces. Enhancement: add `(cons 72 1)` (center) to entmake call in `bs-make-text`.

5. **Consider BSSTATION label offset direction.** Currently always offsets +5' in X and Y (diagonal). A smarter approach would offset perpendicular to the nearest fiber line so labels don't overlap fiber callouts.

6. **Consider BSMINERDOC block definition.** Placing the MIN DOC note as a block (instead of raw TEXT + LINE entities) would allow updates via block redefinition. Currently it places loose entities.

7. **Long-term: merge bsp-* and bsps-* helpers into bs_helpers.lsp.** This would eliminate 3 sets of duplicate geometry functions. Requires updating bsparcels.lsp and bsparsnap.lsp function call prefixes. Low urgency since existing code works.

---

## File Inventory (end of session)

```
AUTOMATION/
  bs_loader.lsp          ← master loader (APPLOAD this)
  bs_helpers.lsp         ← shared helpers (NEW)
  bsrow.lsp              ← BSROW v5.1 (active version)
  bsrow_v5.lsp           ← BSROW v5 (kept, no longer loaded)
  bsfillet_all.lsp       ← BSFILLET-ALL (REWRITTEN)
  bscallout.lsp          ← BSCALLOUT, BSCALLOUT-AUTO (NEW)
  bsaerial.lsp           ← BSAERIAL, BSAERIAL-AUTO (NEW)
  bsstation.lsp          ← BSSTATION (NEW)
  bsdrive.lsp            ← BSDRIVE (NEW)
  bsworkarea.lsp         ← BSWORKAREA (NEW)
  bsminerdoc.lsp         ← BSMINERDOC (NEW)
  bsaudit.lsp            ← BSAUDIT 8-check (NEW)
  bscleanup.lsp          ← BSCLEANUP (NEW)
  bsparcels.lsp          ← BSPARCELS, BSPARHIDE, BSADDTRAP (unchanged)
  bsparsnap.lsp          ← BSPARSNAP (unchanged)
  bscleanvp.lsp          ← BSCLEANVP, BSCLEANLIMIT (unchanged)
  brightspeed_core.lsp   ← legacy core (not loaded by bs_loader.lsp)
  README.md              ← documentation (NEW)
  SESSION_NOTES.md       ← this file (NEW)
```
