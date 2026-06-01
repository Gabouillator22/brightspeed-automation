# Brightspeed AutoLISP Toolkit

AutoCAD Map 3D automation for Brightspeed fiber permit drawings.  
Targets AutoCAD Map 3D 2027. All commands are undo-safe (Ctrl+Z).

---

## Quick Start

1. Open AutoCAD Map 3D
2. Type `APPLOAD` → browse to `bs_loader.lsp` → Load
3. All commands are now available. Type any command name at the prompt.

> Reload after edits: type `APPLOAD` again and reload `bs_loader.lsp`.

---

## Commands Reference

### KMZ Field Data Import

#### BSKMZ
Import a KMZ (Google Earth) file from the field team. Places blocks for every
point feature and polylines for every line feature on the correct Brightspeed
layer. GPS lat/lon is converted to NC State Plane (NAD83 NC, US Survey Foot)
via a baked-in Lambert Conformal Conic transform — no Map 3D API dependency.

**Usage:** `BSKMZ` → pick `.kmz` file → automatic.

**Folder → AutoCAD mapping:**

| KMZ folder | Result | Layer | Block |
|---|---|---|---|
| `HANDHOLE` | Block insert | `HANDHOLE` | `NDS_HH` |
| `CO` | Block insert | `HANDHOLE` | `NDS_HH` (relabel after) |
| `BORE` | Block insert | `BORE PIT` | `BORE PIT` |
| `POLE` | Block insert | `Pole` | `TELPOLE1262023` |
| `UNDERGROUND` / `BURIED` | LWPOLYLINE | `Buried Fiber in Duct` | — |
| `AERIAL` / `NEW STRAND` / `NEW STRAND/NEW BUILD` | LWPOLYLINE | `AERIAL FIBER` | — |
| `ELASH` / `E-LASH` / `OVERLASH` | LWPOLYLINE | `E-LASH` | — |

**Pre-flight check:** before importing, BSKMZ verifies that all required
blocks (`NDS_HH`, `BORE PIT`, `TELPOLE1262023`) are defined in the drawing.
If any are missing, the command aborts and lists them. Fix: insert one of
each by hand once so the block definition exists, then re-run.

**Undo:** the whole import is one undo group — Ctrl+Z reverses everything.

**Companion file:** `bskmz.ps1` (extracts the KMZ archive, parses the KML).
Must live next to `bskmz.lsp`.

---

#### BSKMZ-FIBERSNAP
Snap every buried fiber vertex to **4 feet from the nearest ROW line**,
offset toward the road centerline.

**Usage:** `BSKMZ-FIBERSNAP` — fully automatic. Run after `BSKMZ` and `BSROW`.

**Requires:** at least one `ROW` line and one `ROAD-CENTERLINE` polyline.
Search radius for nearest ROW: 200 feet.

---

#### BSKMZ-HHALIGN
Three things per handhole insert on the `HANDHOLE` layer:
1. Set layer color to **red** (color 1)
2. Rotate each block to match the centerline tangent (long axis crosses road)
3. Move insertion point to 4' from the nearest ROW (sits on the fiber)

**Usage:** `BSKMZ-HHALIGN` — fully automatic.

If no centerline is found, rotation is skipped (warning printed).
If no ROW is found, repositioning is skipped (warning printed).
The red recolor always happens.

---

#### BSKMZ-AERIALSNAP
Snap every aerial fiber vertex to the **nearest pole within 80 feet**.
Vertices with no pole nearby are left alone — this preserves aerial runs
that legitimately sit outside the ROW (e.g. private easements).

**Usage:** `BSKMZ-AERIALSNAP` — fully automatic.

**Requires:** at least one `TELPOLE1262023` block insert in the drawing.
Consecutive vertices that snap to the same pole are deduplicated.

---

#### BSKMZ-SNAP
Run `BSKMZ-FIBERSNAP`, `BSKMZ-HHALIGN`, and `BSKMZ-AERIALSNAP` back-to-back.

**Recommended full workflow:**
```
1. BSKMZ              (raw import from field KMZ)
2. BSROW              (build ROW + EOP + TRAP from centerlines)
3. BSKMZ-SNAP         (conform raw geometry to drafting standards)
4. BSCALLOUT-AUTO     (label every buried fiber run)
5. BSAERIAL-AUTO      (label every aerial fiber run)
6. BSSTATION          (station every HH/pole/bore)
7. BSAUDIT            (final compliance scan)
```

**Tuning constants** (top of `bskmz_snap.lsp`):
- `*bks-fiber-offset-ft*` — default `4.0`
- `*bks-row-search-ft*` — default `200.0`
- `*bks-pole-search-ft*` — default `80.0`

---

### Border Cleanup

#### BSCLEANRECT
Draw the cleanup limit rectangle on layer `BS-CLEAN-LIMIT`.

**Usage:** `BSCLEANRECT` -> pick first corner -> pick opposite corner.

This rectangle is the only zone the cleaner is allowed to modify. Anything
outside this rectangle is ignored.

---

#### BSCLEAN
Clean linework inside the `BS-CLEAN-LIMIT` rectangle while preserving anything
inside the black sheet rectangles on layer `BORDER`.

**Usage:** `BSCLEAN` after drawing the cleanup rectangle.

**What it does:**
- Finds the newest `BS-CLEAN-LIMIT` rectangle automatically
- Finds all `BORDER` rectangular polylines inside that cleanup rectangle
- Scans `LINE`, `LWPOLYLINE`, `POLYLINE`, `ARC`, and `SPLINE` entities
- Keeps/recreates only the portions inside `BORDER` rectangles
- Moves original clipped entities to `BS-CLEAN-HIDDEN` and freezes that layer

**Safety:** Nothing is deleted. Use `Ctrl+Z` to undo, or thaw
`BS-CLEAN-HIDDEN` to recover originals.

Legacy aliases: `BSCLEANLIMIT` and `TRIMAGE` both run `BSCLEANRECT`.
`BSCLEANVP` and `BSCLEANAUTO` both run `BSCLEAN`.

---

### ROW / Road Geometry

#### BSROW
Auto-draw ROW, EOP, and TRAP lines from centerline polylines.

**Usage:**  
Place centerlines on layer `ROAD-CENTERLINE`, then type `BSROW`. Fully automatic.

**Creates:**
- `ROW` lines: 30' each side of centerline
- `ROADS-paved` lines: 20' inward from ROW (= 10' from CL)
- `ROW-TRAP` lines: 35' outward from ROW (= 65' from CL)

**Layers:** ROW (color 6), ROADS-paved (black), ROW-TRAP (cyan 4)

---

#### BSADDTRAP
Add TRAP lines to existing ROW lines (for drawings created with older BSROW).

**Usage:** `BSADDTRAP` — fully automatic, scans all ROW entities.

---

#### BSFILLET-ALL
Fillet all ROW and EOP corner intersections with R=25'.

**Usage:** `BSFILLET-ALL` — fully automatic.

Finds all real (non-virtual) intersections between ROW and ROADS-paved entities,
confirms each is a corner (intersection within 5' of an endpoint), then applies fillet.

**Known limitation:** Pick points use entity midpoints. In very dense drawings
with overlapping entities, occasional wrong-entity selection may occur.
Undo and manually fillet affected corners.

---

#### BSDRIVE
Draw a driveway line, extended to EOP and trimmed at ROW.

**Usage:** `BSDRIVE` → pick first point → pick second point → automatic.

**Result:** LWPOLYLINE on DRIVEWAYS layer, clipped from ROW to ROW.  
Extends to nearest ROADS-paved (EOP) line, then trims at nearest ROW line on each end.

**Layers:** DRIVEWAYS (color 30 = orange)

---

### Fiber Callouts

#### BSCALLOUT
Place a buried fiber callout with measured length.

**Usage:** `BSCALLOUT` → select BURIED FIBER IN DUCT polyline → pick text location.

**Label format:** `HDD BORE N' FIBER IN 2" DUCT` (N = length rounded to nearest foot)  
**Text height:** 5.0  
**Layer:** CALLOUTS

---

#### BSCALLOUT-AUTO
Automatically place callouts on all BURIED FIBER IN DUCT polylines.

**Usage:** `BSCALLOUT-AUTO` — no input required.

Text is placed 10' perpendicular to the fiber at its midpoint, toward the nearest ROW line.

---

#### BSAERIAL
Place an aerial fiber callout (no footage).

**Usage:** `BSAERIAL` → select AERIAL FIBER or ELASH polyline → pick text location.

**Labels:**
- AERIAL FIBER layer → `NEW AERIAL FIBER STRAND`
- ELASH layer → `AERIAL FIBER ELASHED TO EXISTING`

**Text height:** 5.0 | **Layer:** CALLOUTS

---

#### BSAERIAL-AUTO
Automatically place callouts on all AERIAL FIBER and ELASH polylines.

**Usage:** `BSAERIAL-AUTO` — no input required.

---

### Labeling

#### BSSTATION
Auto-station all handhole, bore pit, and pole blocks.

**Usage:** `BSSTATION` — fully automatic.

Scans all INSERT entities for block names containing: `HANDHOLE`, `HH`, `BORE`, `BOREPIT`, `POLE`  
(case-insensitive substring match — `BS_HANDHOLE_24` is matched by `HANDHOLE`).

Station = arc-length distance from the start vertex of the nearest fiber polyline.

**Station format:** `STA XX+XX.X`  
**Text height:** 5.0 | **Layer:** STATIONING

> **Note:** Station 0+00 is the START vertex of the nearest fiber polyline.  
> If stationing runs backward vs field convention, use `PEDIT → Reverse` on the fiber polyline before running BSSTATION.

---

#### BSWORKAREA
Place WORK AREA START and END labels with coordinates.

**Usage:** `BSWORKAREA`
1. Enter work area number (e.g. `1`)
2. Pick START point → label placed
3. Pick END points one by one (labeled A, B, C...) → press Enter to finish

**Label format:**
```
WORK AREA 1 START
35.123456, -80.654321

WORK AREA 1A END
35.234567, -80.765432
```

**Coordinate conversion:** Attempts AutoCAD Map 3D WCS-to-LatLon transform.
If no Map coordinate system is configured, prompts for manual coordinate entry.
WCS coordinates are shown as fallback if no input given.

**Text height:** 5.0 | **Layer:** WORK AREA (color 1 = red)

---

#### BSMINERDOC
Place the required MIN D.O.C. note on sheets with underground fiber.

**Usage:** `BSMINERDOC` — pick placement point or press Enter for default (lower-left).

Checks: (1) buried fiber exists, (2) note not already present. Places only if needed.

**Note text (stacked):**
```
MIN D.O.C.
UNDER NATURAL GROUND
60"
────────────>
```

**Text height:** 5.0 | **Layer:** CALLOUTS

---

### Property Line Cleanup

#### BSPARCELS
Clean property lines using the ROW-TRAP zone.

**Usage:** `BSPARCELS` → pick ONE ROW line → automatic.

Hides parallel band segments (old ROW boundary fragments).  
Extends/trims angled parcel lines to the ROW line.

**Requires:** BSROW v5+ (creates ROW-TRAP lines).

---

#### BSPARHIDE
Hide only the parallel property-line fragments. No trim/extend.

**Usage:** `BSPARHIDE` → pick ONE ROW line → automatic.

Safer than BSPARCELS when testing. Use this first to preview what will be hidden.

---

#### BSPARSNAP
Snap perpendicular property line endpoints exactly onto the ROW line.

**Usage:** `BSPARSNAP` → pick ONE ROW line → automatic.

Moves LINE entity endpoints only (not polylines). Works on LINE entities.  
Max adjustment: 75'. Lines more than 75' from ROW are skipped.

---

### Quality / Final

#### BSAUDIT
Run 8-check compliance scan. No changes — diagnostic only.

**Usage:** `BSAUDIT` — fully automatic.

| Check | What it verifies |
|-------|-----------------|
| 1 | Text height on CALLOUTS/STATIONING must be 5.0 or 6.0 |
| 2 | Fiber layer entities should be polylines, not LINE entities |
| 3 | Each BURIED FIBER segment has nearby "HDD BORE" callout (50' radius) |
| 4 | Each HH/bore pit/pole block has nearby STA label (15' radius) |
| 5 | Wide polylines (width ≥ 0.4) must be on a fiber layer |
| 6 | Callout text entities on CALLOUTS must not overlap (< 5' apart) |
| 7 | At least one WORK AREA label must exist |
| 8 | If buried fiber exists, MIN D.O.C. note must exist |

Output: violations listed with entity handles for easy location.

---

#### BSCLEANUP
Pre-submission drawing cleanup — one command.

**Usage:** `BSCLEANUP` — fully automatic. No user input.

1. ZOOM EXTENTS
2. Sets all fiber polyline widths to 0.5, enables PLINEGEN (linetype continuous)
3. Moves all IMAGE entities to VIEWPORT IMAGE layer
4. Finds duplicate PROPERTY LINE segments (same endpoints ±0.01') → moves to PROPERTY LINE-HIDDEN

No entities are deleted. Summary printed at end.

---

#### BSCLEANLIMIT
Draw a cleanup limit rectangle for BSCLEANVP.

**Usage:** `BSCLEANLIMIT` → draw rectangle in viewport area.

---

#### BSCLEANVP
Clip all linework to BORDER rectangles within the cleanup limit.

**Usage:** `BSCLEANVP` → select the BSCLEANLIMIT rectangle → automatic.

Linework outside BORDER rectangles is moved to BS-CLEAN-HIDDEN (frozen).
Kept pieces are recreated as LINE entities on the original layer.

---

## Layer Reference

| Layer | Color | Purpose |
|-------|-------|---------|
| ROAD-CENTERLINE | 4 (cyan) | Road centerlines (input to BSROW) |
| ROW | 6 (magenta) | Right-of-way lines (30' from CL) |
| ROADS-paved | 7 (white) | Edge of pavement (10' from CL) |
| ROW-TRAP | 4 (cyan) | Trap zone outer boundary (65' from CL) |
| AERIAL FIBER | 1 (red) | Above-ground fiber strand |
| BURIED FIBER IN DUCT | 5 (blue) | Underground fiber in conduit |
| ELASH | 6 (magenta) | Fiber lashed to existing strand |
| DRIVEWAYS | 30 (orange) | Driveway access lines |
| CALLOUTS | 7 (white) | All annotation text and leaders |
| STATIONING | 7 (white) | Station labels (STA XX+XX) |
| WORK AREA | 1 (red) | Work area start/end labels |
| PROPERTY LINE | varies | GIS parcel boundaries (input) |
| PROPERTY LINE-HIDDEN | 8 (gray) | Hidden parcel segments (recoverable) |
| VIEWPORT IMAGE | 8 (gray) | Raster aerial images |
| BORDER | 7 (white) | Viewport border rectangles |
| BS-CLEAN-LIMIT | 30 (orange) | BSCLEANVP limit rectangle |
| BS-CLEAN-HIDDEN | 8 (gray) | Linework hidden by BSCLEANVP |

---

## Offset Reference

```
                     TRAP (65' from CL)
                     |
         PROPERTY    |  35'   ROW (30' from CL)
         (outside)   |        |
                     |  20'   |  EOP (10' from CL)
                     |        |  |
                 ----+--------+--+--[ C L ]--+--+--------+----
                     |        |  |           |  |        |
                     |        | 10'          10'|        |
                     |       30'               30'       |
                     |      ROW                ROW       |
                    65'                                  65'
                   TRAP                                TRAP
```

Key numbers:
- CL → EOP: **10'** (inside road shoulder)
- CL → ROW: **30'** (right-of-way boundary)
- ROW → EOP: **20'** (inward, EOP is 20' inside ROW)
- ROW → TRAP: **35'** (outward, for parcel cleanup zone)
- CL → TRAP: **65'** (total = 30 + 35)

---

## Brightspeed Standards Summary

- **All callout text:** height 5.0
- **Street name text:** height 6.0
- **Buried fiber callout:** `HDD BORE N' FIBER IN 2" DUCT`
- **Aerial fiber callout:** `NEW AERIAL FIBER STRAND`
- **Elash callout:** `AERIAL FIBER ELASHED TO EXISTING`
- **Station format:** `STA XX+XX.X` (e.g. `STA 12+53.5`)
- **Required note on underground sheets:** `MIN D.O.C. UNDER NATURAL GROUND 60"`
- **Fillet radius at ROW/EOP corners:** 25'
- **Fiber polyline width:** 0.5 (global constant width)
- **Fiber linetype generation:** PLINEGEN ON (continuous across vertices)

---

## Troubleshooting

**`[MISSING] bsxxx.lsp`** — The .lsp file is not in the same folder as bs_loader.lsp.  
Move all .lsp files to the same directory.

**BSROW finds no centerlines** — Make sure road centerlines are on layer `ROAD-CENTERLINE` (exact spelling, case-sensitive).

**BSFILLET-ALL applies 0 fillets** — No real intersections found. ROW/EOP lines do not currently touch at corners. Manually drag endpoints together first, then re-run.

**BSSTATION shows STA 0+00 for everything** — Fiber polylines exist but the start vertex is at the wrong end. Run `PEDIT → Reverse` on the fiber polyline, then re-run BSSTATION.

**BSWORKAREA shows WCS coordinates instead of lat/lon** — The drawing does not have a Map 3D coordinate system configured, or the Map 3D ActiveX API returned an error. Enter coordinates manually when prompted, or set up the NC83F coordinate system in Map 3D before running.

**BSAUDIT Check 3 flags all buried fiber** — No callout text found near fiber segments. Run `BSCALLOUT-AUTO` first to place callouts, then re-run BSAUDIT.

**BSPARCELS says "No ROW-TRAP line found"** — You have an older drawing that was processed with BSROW v4 or earlier. Run `BSADDTRAP` to add TRAP lines to existing ROW lines.

**BSCLEANVP hides too much linework** — The BORDER rectangles may not be aligned with your viewports. Verify BORDER layer entities are closed rectangles around each viewport.

---

*Brightspeed AutoLISP Toolkit — AutoCAD Map 3D 2027*
