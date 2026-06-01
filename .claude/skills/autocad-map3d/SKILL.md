# AutoCAD Map 3D — Skill Reference

## Environment
- **AutoCAD Map 3D 2027**, Windows (via Parallels on Mac).
- Coordinate system: **NC State Plane NAD83 US Survey Foot (NC83F / EPSG:2264)**.
- All drawing units are **feet**.

## Toolkit load sequence
```
APPLOAD → 05_toolkit/lisp/bs_loader.lsp
BSINSTALLCHECK            ← adds toolkit folder to trusted+support paths
```
After loading, all `BS*` commands are available in any drawing.

## Core BS commands
| Command | Purpose |
|---|---|
| `BSROW` | Pick centerline → draws ROW, EOP, and TRAP lines |
| `BSADDTRAP` | Add TRAP segment to existing ROW |
| `BSFILLET-ALL` | Fillet all ROW/EOP corners (R=25') |
| `BSDRIVE` | Draw driveway, trim to ROW/EOP |
| `BSKMZ` | Import KMZ field data onto correct layers |
| `BSKMZ-SNAP` | Snap fiber 4' from ROW, align HH, snap aerial to poles |
| `BSCALLOUT-AUTO` | Auto-label all buried fiber runs |
| `BSAERIAL-AUTO` | Auto-label all aerial fiber runs |
| `BSSTATION` | Auto-station HH / bore pits / poles |
| `BSWORKAREA` | Place WORK AREA START/END labels with lat/lon |
| `BSMINERDOC` | Place MIN D.O.C. note |
| `BSROWDIMS` | Auto-place NCDOT ROW dimension stacks on all BORDER viewports |
| `BSROWDIMS1` | Same, pick one BORDER rectangle |
| `BSAUDIT` | 8-check compliance scan |
| `BSCLEANRECT` | Draw cleanup rectangle |
| `BSCLEAN` | Trim linework to BORDER rectangles |
| `BSSHEETKMZ` | Import KMZ + auto-place proposed sheet rectangles |
| `BSSHEETACCEPT` | Promote proposed rectangles to BORDER layer |

## Key layers
| Layer | Color | Content |
|---|---|---|
| `ROAD-CENTERLINE` | white | Road center lines |
| `ROW` | magenta | Right-of-way boundary |
| `ROADS-Paved` | cyan | Edge-of-pavement |
| `Buried Fiber in Duct` | cyan | Underground fiber |
| `AERIAL FIBER` | cyan | Aerial fiber |
| `E-LASH` | cyan | Overlash fiber |
| `HANDHOLE` | red | Handhole blocks |
| `Pole` | — | Pole blocks |
| `BORE PIT` | — | Bore pit blocks |
| `BORDER` | — | Sheet border polylines |
| `DIM` | white | Dimension annotations |
| `CALLOUTS` | white | Fiber length callouts |
| `STATIONING` | white | Station labels |

## Linework standards (enforced by `code-reviewer`)
- Global width: **0.5** on all fiber polylines.
- **LINETYPE GENERATION** must be enabled (`PLINEGEN 1` or `(cons 70 128)` in entmake).
- Colors from **layer** only — never manually assigned.

## AutoCAD Map 3D specifics
- Use `vlax-curve-getPointAtDist` for arc-length walking (Z-independent).
- `IntersectWith mode 0` fails with NC83F Z≠0 entities — use 2D bbox sampling instead (see `bsrd-cl-bbox-span` in `bsrowdims.lsp`).
- `(getvar "CVPORT") = 1` means paper space — `entsel` cannot reach model-space entities.
- `vla-GetBoundingBox` + `vlax-safearray->list` for entity bbox extraction.
- `*bs-toolkit-dir*` global holds the toolkit folder path (set by `bs_loader.lsp`).
