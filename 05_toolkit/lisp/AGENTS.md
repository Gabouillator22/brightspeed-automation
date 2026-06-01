# LISP Sub-brain — 05_toolkit/lisp/

## File naming
`bs_<command>.lsp` — one public command per file unless the existing pattern says otherwise.

## Header template
```lisp
;;; ============================================================
;;; BS<COMMAND> - One-line description
;;;
;;; Commands:
;;;   BS<COMMAND>     - what it does
;;;   BS<COMMAND>-AUTO- auto variant if applicable
;;;
;;; Depends on: bs_helpers.lsp (loaded by bs_loader.lsp)
;;; AutoCAD Map 3D 2027
;;; ============================================================
```

## Mandatory patterns
Every public `c:BSCOMMAND` must have:
1. Local `*error*` handler (restores CMDECHO, OSMODE, CLAYER; ends UNDO group).
2. `(command "_.UNDO" "_BEGIN")` + `(command "_.UNDO" "_END")` bracket.
3. `(vl-load-com)` at file top if any `vla-`/`vlax-` calls are made.
4. `(princ)` as the last expression to suppress nil output.

## Load sequence
```
APPLOAD bs_loader.lsp
BSINSTALLCHECK
```
bs_loader.lsp loads bs_helpers.lsp FIRST, then all command files in dependency order.
New files are registered via `(bs-load-file "bsNEWFILE.lsp")` at the end of bs_loader.lsp.

## Shared helpers (bs_helpers.lsp)
- Layer: `bs-ensure-layer`, `bs-force-layer`
- Vector math: `bs-vsub`, `bs-vadd`, `bs-vscale`, `bs-vdot`, `bs-vlen`, `bs-vunit`, `bs-vperp-left`, `bs-vperp-right`
- Entity geometry: `bs-ent-midpt`, `bs-ent-startpt`, `bs-ent-endpt`
- Distance: `bs-closest-on-seg`, `bs-dist-to-ent`
- Tangent: `bs-tangent-at-pt`
- Intersections: `bs-intersect-first`, `bs-intersect-all`, `bs-near-endpoint-p`
- Selection: `bs-nearest-ent-in-ss`
- Creation: `bs-make-text`, `bs-make-line`, `bs-make-leader-line`
- Formatting: `bs-format-station`
- Editing: `bs-replace-nth-vertex`, `bs-count-vertices`

## File inventory
| File | Commands | Notes |
|---|---|---|
| `bs_loader.lsp` | loader | APPLOAD this only |
| `bs_helpers.lsp` | shared lib | Loaded first; all `bs-` helpers |
| `bsrow.lsp` | BSROW, BSADDTRAP | v5.1 with TRAP direction fix |
| `bsfillet_all.lsp` | BSFILLET-ALL | Corner fillet (R=25') |
| `bscallout.lsp` | BSCALLOUT, BSCALLOUT-AUTO | Buried fiber callouts |
| `bsaerial.lsp` | BSAERIAL, BSAERIAL-AUTO | Aerial callouts (no footage) |
| `bsstation.lsp` | BSSTATION | Auto-station HH/bore/poles |
| `bscallouts_auto.lsp` | BSCALLOUTS-RUN, BSCALLOUTS-STRUCTURES, BSCALLOUTS-BURIED, BSCALLOUTS-AERIAL, BSCALLOUTS-AUDIT | Sheet-aware multileader callout automation |
| `bsdrive.lsp` | BSDRIVE | Driveway drafting |
| `bsworkarea.lsp` | BSWORKAREA | WORK AREA START/END labels |
| `bsminerdoc.lsp` | BSMINERDOC | MIN D.O.C. 60" note |
| `bsaudit.lsp` | BSAUDIT | 8-check compliance scan |
| `bscleanup.lsp` | BSCLEANUP | Pre-submission cleanup |
| `bsparcels.lsp` | BSPARCELS, BSPARHIDE, BSADDTRAP | Parcel line cleanup |
| `bsparsnap.lsp` | BSPARSNAP | Property line endpoint snap |
| `bsrowdims.lsp` | BSROWDIMS, BSROWDIMS1, BSROWDIMSC | ROW dimension stacks |
| `bskmz.lsp` | BSKMZ | KMZ field data import |
| `bskmz_snap.lsp` | BSKMZ-SNAP, BSKMZ-FIBERSNAP, BSKMZ-HHALIGN, BSKMZ-AERIALSNAP | Post-import snapping |
| `bssheets.lsp` | BSSHEETRECT, BSSHEETLOAD, BSSHEETMAKE, BSSHEETACCEPT, BSSHEETCLEAR | Sheet planning |
| `bssheet_kmz.lsp` | BSSHEETKMZ | KMZ + sheet auto-placement |
| `bsclean_border.lsp` | BSCLEANRECT, BSCLEAN, BSCLEANALL | Border cleanup (active) |
| `bscleanvp.lsp` | shim | Compatibility shim → bsclean_border.lsp |
| `brightspeed_core.lsp` | legacy | Not loaded by bs_loader.lsp |
| `bsrow_v5.lsp` | legacy v5 | Kept, not loaded (use bsrow.lsp v5.1) |
