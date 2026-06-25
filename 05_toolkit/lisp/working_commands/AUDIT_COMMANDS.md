# Brightspeed LISP Command Audit

Date: 2026-06-03

Scope: static audit only. No command behavior changed in this pass.

## 1. Executive Summary

- The repo has two command surfaces right now:
  - the loader-driven toolkit in `05_toolkit/lisp/bs_loader.lsp`
  - direct-load working copies in `05_toolkit/lisp/working_commands/`
- The practical working set is not the same as the loader list. The loader still references root files that are only present under `working_commands/` for `BSROW`, `BSPARSNAP`, and `BSKMZ`.
- The cleanest near-term strategy is to keep a small manual-test set in `working_commands/` and treat older shims, alias wrappers, and legacy files as reference material until the core set is stable.

## 2. Current Command Inventory

| File | Public commands | Classification | Notes |
|---|---|---|---|
| `05_toolkit/lisp/bs_loader.lsp` | `BSINSTALLCHECK`, `BSMAP`, `BCMAP`, `BSCLMAP`, `BSDIMS`, `BSDIM1`, `BSDIMC`, `BSDIAG` | `KEEP_NOW` for `BSINSTALLCHECK`; `LEGACY_REFERENCE` for the aliases | Install checker is useful. The alias commands duplicate functionality that already exists elsewhere. Loader still assumes root files for `BSROW`, `BSPARSNAP`, and `BSKMZ`, but those files are currently only under `working_commands/`. |
| `05_toolkit/lisp/working_commands/bsrow.lsp` | `BSROW` | `KEEP_NOW` | This is the practical direct-load ROW generator. It is the command the audit should keep in the working set. |
| `05_toolkit/lisp/working_commands/bsparsnap.lsp` | `BSPARSNAP`, `BSSNAP` | `KEEP_NOW` | This is the working direct-load parcel snapper. `BSSNAP` is just a compatibility alias. |
| `05_toolkit/lisp/working_commands/bskmz.lsp` | `BSKMZ` | `KEEP_NOW` | This is the working direct-load KMZ importer. It depends on `bskmz.ps1`. |
| `05_toolkit/lisp/bsrow_v5.lsp` | `BSROW` | `LEGACY_REFERENCE` | Old ROW generator. Superseded by `working_commands/bsrow.lsp`. |
| `05_toolkit/lisp/brightspeed_core.lsp` | `BSSETUP`, `BSFIBER`, `BSBURIED`, `BSCL`, `BSROW` | `LEGACY_REFERENCE` | Legacy startup file with outdated layer names and an old `BSROW`. Not part of the current working set. |
| `05_toolkit/lisp/bsparcels.lsp` | `BSPARCELS`, `BSPARHIDE`, `BSADDTRAP` | `BSPARHIDE: KEEP_NOW`, `BSADDTRAP: MERGE_LATER`, `BSPARCELS: LEGACY_REFERENCE` | Heavy parcel cleanup family. Uses legacy `bsp-*` helpers and still advertises `BSROW v5` as its dependency. |
| `05_toolkit/lisp/bscallout.lsp` | `BSCALLOUT`, `BSCALLOUT-AUTO` | `KEEP_NOW` | Strong candidate for the working folder. Self-contained buried-fiber callout flow. |
| `05_toolkit/lisp/bsaerial.lsp` | `BSAERIAL`, `BSAERIAL-AUTO` | `KEEP_NOW` | Strong candidate for the working folder. Self-contained aerial callout flow. |
| `05_toolkit/lisp/bscallouts_auto.lsp` | `BSCALLOUTS-STRUCTURES`, `BSCALLOUTS-BURIED`, `BSCALLOUTS-AERIAL`, `BSCALLOUTS-RUN`, `BSCALLOUTS-AUDIT` | `MERGE_LATER` | Useful family, but it overlaps with the simpler buried/aerial callout commands and should not be a first-wave deliverable. |
| `05_toolkit/lisp/bsstation.lsp` | `BSSTATION` | `KEEP_NOW` | Essential final-labeling command. Needs live drafting QA, but it is part of the core workflow. |
| `05_toolkit/lisp/bsworkarea.lsp` | `BSWORKAREA` | `KEEP_NOW` | Essential note command. Useful and simple. |
| `05_toolkit/lisp/bsminerdoc.lsp` | `BSMINERDOC` | `KEEP_NOW` | Required underground note command. Useful and simple. |
| `05_toolkit/lisp/bsaudit.lsp` | `BSAUDIT` | `KEEP_NOW` | Final QA command. Should remain in the working set. |
| `05_toolkit/lisp/bsdrive.lsp` | `BSDRIVE` | `UNKNOWN_UNTESTED` | Good drafting utility, but not yet logged as fully validated in this pass. |
| `05_toolkit/lisp/bsfillet_all.lsp` | `BSFILLET-ALL` | `UNKNOWN_UNTESTED` | Useful but still not part of the smallest proven working set. |
| `05_toolkit/lisp/bsrowdims.lsp` | `BSROWDIMS`, `BSROWDIMS1`, `BSROWDIMSC`, `BSROWDIMS-DIAG`, `BSDIMS`, `BSDIM1`, `BSDIMC`, `BSDIAG` | `BSROWDIMS` / `BSROWDIMS1: KEEP_NOW`, `BSROWDIMSC: UNKNOWN_UNTESTED`, `BSROWDIMS-DIAG: MERGE_LATER`, aliases: `LEGACY_REFERENCE` | Active row-dimension family. The alias names are compatibility only. |
| `05_toolkit/lisp/bskmz_snap.lsp` | `BSKMZ-FIBERSNAP`, `BSKMZ-HHALIGN`, `BSKMZ-AERIALSNAP`, `BSKMZ-SNAP` | `UNKNOWN_UNTESTED` | This is the post-import KMZ alignment family. Useful, but not yet part of the smallest proven set. |
| `05_toolkit/lisp/bssheets.lsp` | `BSSHEETRECT`, `BSSHEETLOAD`, `BSSHEETMAKEPLAN`, `BSSHEETMAKE`, `BSSHEETACCEPT`, `BSSHEETCLEAR` | `BSSHEETRECT: KEEP_NOW`, `BSSHEETLOAD` / `BSSHEETMAKE` / `BSSHEETACCEPT` / `BSSHEETCLEAR: UNKNOWN_UNTESTED`, `BSSHEETMAKEPLAN: MERGE_LATER` | Current sheet-planning workflow. It depends on generated plan files and is still being refined. |
| `05_toolkit/lisp/bssheet_kmz.lsp` | `BSSHEETKMZ` | `UNKNOWN_UNTESTED` | One-step KMZ import + sheet placement. Useful, but still not a first-wave working command. |
| `05_toolkit/lisp/bsclean_border.lsp` | `BSCLEANRECT`, `BSCLEAN`, `BSCLEANPICK`, `BSCLEANOUT`, `BSCLEANLINES`, `BSCLEANTRIMSEL`, `BSCLEANBAD`, `BSCLEANCLEARMASK`, `BSCLEANMASK`, `BSCLEANALL`, `BSCLEANMAP`, `BSMAP`, `BCMAP`, `BSCLMAP`, `BSCLEANLIMIT`, `TRIMAGE`, `BSCLEANVP`, `BSCLEANAUTO`, `BSCLEANFINAL` | Core cleanup commands: `KEEP_NOW`; aliases: `LEGACY_REFERENCE`; `BSCLEANMASK: DELETE_LATER` | This is the active cleanup family, but it still contains a dead/disabled `BSCLEANMASK` override and a pile of alias wrappers. |
| `05_toolkit/lisp/bscleanup.lsp` | `BSCLEANUP` | `KEEP_NOW` | Pre-submission cleanup pass. Useful, but keep its behavior conservative because it mutates drawing state. |
| `05_toolkit/lisp/bscleanvp.lsp` | none public | `LEGACY_REFERENCE` | Legacy compatibility shim only. It just redirects old APPLOAD habits to `bsclean_border.lsp`. |
| `05_toolkit/lisp/bs_helpers.lsp` | none public | `KEEP_NOW` | Shared helper library. Not a command file, but it is required infrastructure. |

## 3. Duplicate Command Map

- `BSROW`
  - `05_toolkit/lisp/working_commands/bsrow.lsp`
  - `05_toolkit/lisp/bsrow_v5.lsp` (legacy)
  - `05_toolkit/lisp/brightspeed_core.lsp` (legacy)
- `BSPARSNAP`
  - `05_toolkit/lisp/working_commands/bsparsnap.lsp`
  - loader still expects a root `bsparsnap.lsp`, but that file is not present at the root right now
- `BSKMZ`
  - `05_toolkit/lisp/working_commands/bskmz.lsp`
  - loader still expects a root `bskmz.lsp`, but that file is not present at the root right now
- `BSCLEANRECT`
  - `BSCLEANLIMIT`
  - `TRIMAGE`
- `BSCLEAN`
  - `BSCLEANVP`
- `BSCLEANALL`
  - `BSCLEANAUTO`
  - `BSCLEANFINAL`
- `BSCLEANMAP`
  - `BSMAP`
  - `BCMAP`
  - `BSCLMAP`
  - note: the loader and `bsclean_border.lsp` both contain compatibility wrappers for these names
- `BSROWDIMS`
  - `BSDIMS`
  - `BSROWDIMS1` -> `BSDIM1`
  - `BSROWDIMSC` -> `BSDIMC`
  - `BSROWDIMS-DIAG` -> `BSDIAG`
- `BSCLEANMASK`
  - one real implementation
  - one disabled stub in the same file
- `BSSHEETLOAD`
  - conditional `BSSHEETMAKEPLAN` exists only after a plan file is loaded

## 4. File-by-File Usefulness Review

- `bs_helpers.lsp`
  - useful shared foundation
  - keep it
- `working_commands/bsrow.lsp`
  - one of the best current working commands
  - keep it and test it first
- `working_commands/bsparsnap.lsp`
  - one of the best current working commands
  - keep it and test it first
- `working_commands/bskmz.lsp`
  - one of the best current working commands
  - keep it and test it first
- `bsrow_v5.lsp`
  - legacy backup only
  - safe to delete later after the working copy is fully promoted
- `brightspeed_core.lsp`
  - old bootstrap-style command set
  - safe to delete later
- `bsparcels.lsp`
  - still useful conceptually, but the implementation is too tied to old helpers and `BSROW v5`
  - fix before promoting, or keep only as reference
- `bscallout.lsp`
  - useful and close to finished
  - good working-folder candidate
- `bsaerial.lsp`
  - useful and close to finished
  - good working-folder candidate
- `bscallouts_auto.lsp`
  - useful family, but too broad for the first minimal set
  - merge later
- `bsstation.lsp`
  - useful and core to the workflow
  - keep it
- `bsworkarea.lsp`
  - useful and core to the workflow
  - keep it
- `bsminerdoc.lsp`
  - useful and core to the workflow
  - keep it
- `bsaudit.lsp`
  - useful and core to the workflow
  - keep it
- `bsdrive.lsp`
  - useful, but still unproven in this audit
  - keep for now, but do not promote ahead of the core set
- `bsfillet_all.lsp`
  - useful, but still unproven in this audit
  - keep for now
- `bsrowdims.lsp`
  - useful active family
  - keep it, but treat the alias names as compatibility only
- `bskmz_snap.lsp`
  - useful family, but not yet part of the smallest proven set
  - keep for now
- `bssheets.lsp`
  - important sheet-planning workflow
  - keep, but treat the plan-file handoff as the real dependency
- `bssheet_kmz.lsp`
  - useful bridge file, but not yet stable enough to be first-wave working material
  - keep for now
- `bsclean_border.lsp`
  - active cleanup family
  - keep, but strip or isolate the dead `BSCLEANMASK` baggage later
- `bscleanup.lsp`
  - useful pre-submission cleanup pass
  - keep it
- `bscleanvp.lsp`
  - compatibility shim only
  - safe to delete later after users stop loading it directly

## 5. Recommended Minimal Working Command Set

Priority order based on the real drafting workflow:

1. `BSKMZ`
2. `BSROW`
3. `BSPARHIDE`
4. `BSPARSNAP`
5. `BSKMZ-FIBERSNAP`, `BSKMZ-HHALIGN`, `BSKMZ-AERIALSNAP`, `BSKMZ-SNAP`
6. `BSCALLOUT`, `BSCALLOUT-AUTO`, `BSAERIAL`, `BSAERIAL-AUTO`
7. `BSSTATION`, `BSWORKAREA`, `BSMINERDOC`
8. `BSSHEETRECT`, `BSSHEETLOAD`, `BSSHEETMAKE`, `BSSHEETACCEPT`, `BSSHEETCLEAR`, `BSSHEETKMZ`
9. `BSAUDIT`
10. `BSCLEANRECT`, `BSCLEAN`, `BSCLEANOUT`, `BSCLEANLINES`, `BSCLEANBAD`, `BSCLEANUP`

I would keep `BSADDTRAP`, `BSPARCELS`, `BSCALLOUTS-*`, `BSROWDIMS*`, and the cleanup aliases out of the first minimal working folder unless a real case forces them back in.

## 6. Files to Copy Into `working_commands` First

These are the first files I would promote into the manual-test folder if the goal is a small, usable set:

1. `05_toolkit/lisp/working_commands/bsrow.lsp` - already present and should stay first-wave
2. `05_toolkit/lisp/working_commands/bsparsnap.lsp` - already present and should stay first-wave
3. `05_toolkit/lisp/working_commands/bskmz.lsp` - already present and should stay first-wave
4. `05_toolkit/lisp/bscallout.lsp`
5. `05_toolkit/lisp/bsaerial.lsp`
6. `05_toolkit/lisp/bsstation.lsp`

If the working folder stays small, stop there until these are manually verified.

## 7. Files to Ignore for Now

- `bsrow_v5.lsp`
- `brightspeed_core.lsp`
- `bscleanvp.lsp`
- `bs_loader.lsp` as the primary source of truth for the working folder
- `bscallouts_auto.lsp` until the simpler callout commands are stable
- `bskmz_snap.lsp` until `BSKMZ` and `BSROW` are consistently validated
- `bssheet_kmz.lsp` until the base sheet planner is stable

## 8. Files Likely Safe to Delete Later

These are safe only after replacement files are fully promoted and users have moved off the old entry points:

- `brightspeed_core.lsp`
- `bsrow_v5.lsp`
- `bscleanvp.lsp`

Inside `bsclean_border.lsp`, the `BSCLEANMASK` implementation/stub should also be removed or retired later, but that is a command cleanup, not a file deletion.

## 9. Commands That Need Immediate Fixing

1. `BSROW`
   - loader points at a root file that is not currently present
2. `BSPARSNAP`
   - same root-path problem as `BSROW`
3. `BSKMZ`
   - same root-path problem as `BSROW`
4. `BSPARCELS`
   - still depends on `BSROW v5` and the legacy `bsp-*` helper family
5. `BSCLEANMASK`
   - duplicate/stub definition in the active cleanup file

## 10. Suggested One-By-One Testing Order

1. `BSROW`
2. `BSPARSNAP`
3. `BSPARHIDE`
4. `BSKMZ`
5. `BSKMZ-FIBERSNAP`
6. `BSKMZ-HHALIGN`
7. `BSKMZ-AERIALSNAP`
8. `BSCALLOUT`
9. `BSAERIAL`
10. `BSSTATION`
11. `BSWORKAREA`
12. `BSMINERDOC`
13. `BSSHEETRECT`
14. `BSSHEETLOAD`
15. `BSSHEETMAKE`
16. `BSSHEETACCEPT`
17. `BSSHEETCLEAR`
18. `BSSHEETKMZ`
19. `BSCLEANRECT`
20. `BSCLEAN`
21. `BSCLEANOUT`
22. `BSCLEANLINES`
23. `BSCLEANBAD`
24. `BSCLEANUP`
25. `BSAUDIT`

## 11. Manual APPLOAD Test Sequence by Family

### ROW / parcel family

1. `APPLOAD` `05_toolkit/lisp/working_commands/bsrow.lsp`
2. Run `BSROW` on a drawing with `ROAD-CENTERLINE`
3. `APPLOAD` `05_toolkit/lisp/working_commands/bsparsnap.lsp`
4. Run `BSPARSNAP` on a drawing with a `ROW` / `ROW-TRAP` pair and `PROPERTY LINE` geometry
5. If you still need the legacy parcel cleanup flow, test `BSPARHIDE` next

### KMZ family

1. `APPLOAD` `05_toolkit/lisp/working_commands/bskmz.lsp`
2. Run `BSKMZ` on a sample KMZ
3. Then test `BSKMZ-FIBERSNAP`, `BSKMZ-HHALIGN`, `BSKMZ-AERIALSNAP`, and `BSKMZ-SNAP` one at a time

### Callout family

1. `APPLOAD` `05_toolkit/lisp/bscallout.lsp`
2. Run `BSCALLOUT` on a buried-fiber line
3. Run `BSCALLOUT-AUTO` on a multi-line buried-fiber case
4. `APPLOAD` `05_toolkit/lisp/bsaerial.lsp`
5. Run `BSAERIAL` and then `BSAERIAL-AUTO`

### Labeling family

1. `APPLOAD` `05_toolkit/lisp/bsstation.lsp`
2. Run `BSSTATION`
3. `APPLOAD` `05_toolkit/lisp/bsworkarea.lsp`
4. Run `BSWORKAREA`
5. `APPLOAD` `05_toolkit/lisp/bsminerdoc.lsp`
6. Run `BSMINERDOC` on a sheet with underground work

### Sheet family

1. `APPLOAD` `05_toolkit/lisp/bssheets.lsp`
2. Generate or place `bssheet_plan.csv` / `bssheet_plan.lsp`
3. Run `BSSHEETLOAD`
4. Run `BSSHEETMAKE`
5. Then test `BSSHEETACCEPT`, `BSSHEETCLEAR`, and `BSSHEETKMZ`

### Cleanup family

1. `APPLOAD` `05_toolkit/lisp/bsclean_border.lsp`
2. Run `BSCLEANRECT`
3. Run `BSCLEAN`
4. Then test `BSCLEANOUT`, `BSCLEANLINES`, `BSCLEANBAD`, `BSCLEANPICK`, and `BSCLEANCLEARMASK`
5. `APPLOAD` `05_toolkit/lisp/bscleanup.lsp`
6. Run `BSCLEANUP`

### Audit

1. `APPLOAD` `05_toolkit/lisp/bsaudit.lsp`
2. Run `BSAUDIT` last, after the drawing has been cleaned and labeled

## 12. Recommended Final Simplified Command Names

The following is the simplified set I would aim for long term:

- `BSROW`
- `BSPARHIDE`
- `BSPARSNAP`
- `BSKMZ`
- `BSCALLOUT`
- `BSAERIAL`
- `BSSTATION`
- `BSWORKAREA`
- `BSMINERDOC`
- `BSSHEETRECT`
- `BSSHEETLOAD`
- `BSSHEETMAKE`
- `BSSHEETACCEPT`
- `BSSHEETCLEAR`
- `BSSHEETKMZ`
- `BSAUDIT`
- `BSCLEANRECT`
- `BSCLEAN`
- `BSCLEANOUT`
- `BSCLEANLINES`
- `BSCLEANBAD`
- `BSCLEANUP`

Aliases and older names to retire from the user-facing surface:

- `BSDIMS`, `BSDIM1`, `BSDIMC`, `BSDIAG`
- `BSMAP`, `BCMAP`, `BSCLMAP`
- `BSCLEANLIMIT`, `TRIMAGE`
- `BSCLEANVP`, `BSCLEANAUTO`, `BSCLEANFINAL`
- `BSCLEANMASK`
- `BSSETUP`, `BSFIBER`, `BSBURIED`, `BSCL`

## 13. Risks

- The loader is not currently the source of truth for the practical working set because some root files are missing and only exist under `working_commands/`.
- `BSPARCELS` mutates geometry and still depends on legacy helper names and the older `BSROW v5` contract.
- `BSCLEAN*` commands are safe only if the layer/model-space assumptions are right; they hide and recreate geometry, so bad inputs can look like lost data until thawed.
- Sheet commands depend on generated plan files. If the plan file is stale, the LISP command can look "broken" when the real issue is the generated data.
- The KMZ family depends on the external `bskmz.ps1` bridge, so the LISP command surface is only half of that workflow.
- `BSCLEANMASK` is a duplicate/stub hazard and should not stay in the long-term command surface.
- `BSROWDIMSC` and the `BSROWDIMS-DIAG` path need a separate live pass before they are considered production-safe.

