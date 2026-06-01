# KMZ → CAD Layer Mapping — Skill Reference

## KMZ folder → AutoCAD layer mapping
| KMZ folder name | Entity type | AutoCAD layer | Block name |
|---|---|---|---|
| `HANDHOLE` | Block insert | `HANDHOLE` | `NDS_HH` |
| `CO` | Block insert | `HANDHOLE` | `NDS_HH` (relabel after) |
| `BORE` | Block insert | `BORE PIT` | `BORE PIT` |
| `POLE` | Block insert | `Pole` | `TELPOLE1262023` |
| `UNDERGROUND` or `BURIED` | LWPOLYLINE | `Buried Fiber in Duct` | — |
| `OVERLASH` | LWPOLYLINE | `E-LASH` | — |
| `NEW STRAND/NEW BUILD` | LWPOLYLINE | `AERIAL FIBER` | — |
| `NEW STRAND` | LWPOLYLINE | `AERIAL FIBER` | — |
| `NEW BUILD` | LWPOLYLINE | `AERIAL FIBER` | — |
| `AERIAL` | LWPOLYLINE | `AERIAL FIBER` | — |
| `ELASH` or `E-LASH` | LWPOLYLINE | `E-LASH` | — |

## Layer-naming aliases (from NCDOT requirements)
| Field name | CAD layer name |
|---|---|
| OVERLASH | `E-LASH` (ELASH layer) |
| NEW STRAND | `AERIAL FIBER` |
| UNDERGROUND | `Buried Fiber in Duct` |

## Coordinate system
- GPS input: **WGS84 lat/lon** (from field KMZ).
- CAD output: **NC State Plane NAD83 US Survey Foot** (EPSG:2264 / NC83F).
- Transform: Lambert Conformal Conic 2SP — baked into `bskmz.lsp` / `bskmz.ps1`, no Map 3D API needed.

## Block pre-flight
Before importing, `BSKMZ` checks that all required block definitions exist in the drawing:
- `NDS_HH`
- `BORE PIT`
- `TELPOLE1262023`

If any are missing, the import aborts with a list of missing blocks. Fix: insert one of each block by hand anywhere in the drawing so the definition exists, then re-run `BSKMZ`.

## Post-import snap operations (`BSKMZ-SNAP`)
Runs three sub-commands in sequence:

1. **`BSKMZ-FIBERSNAP`** — moves all `Buried Fiber in Duct` vertices to **4 feet from the nearest ROW line**, offset toward the road centerline. Search radius: 200'.
2. **`BSKMZ-HHALIGN`** — recolors handhole blocks red, rotates each to match the CL tangent (long axis crosses road), repositions to 4' from nearest ROW.
3. **`BSKMZ-AERIALSNAP`** — snaps each aerial fiber vertex to the nearest pole within **80 feet**. Consecutive vertices snapping to the same pole are deduplicated.

## Technical notes
- `BSKMZ` uses `bskmz.ps1` (PowerShell) to unzip the KMZ and parse the KML.
- `bskmz.ps1` must live in the same folder as `bskmz.lsp`.
- KMZ path is passed via a temp parameter file (avoids cmd.exe quoting issues with special characters in folder names).
- The KML parser handles both `//k:Document` and `//k:Folder` as the folder-name source.

## Geomap layer
- All imported imagery → `VIEWPORT IMAGE` layer.
- Fade level: **30** (set via Map 3D Display Manager).
