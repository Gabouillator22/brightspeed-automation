# BSPACKAGE

## Commands

Standalone load:

- `APPLOAD 05_toolkit/lisp/bspackage.lsp`
- Do not use `bs_loader.lsp` for this workflow.

- `BSPACKAGEINDEX`
  - Scans model-space sheet rectangles on configured layers.
  - Reads manual `BORDER` numbers from `TEXT`, `MTEXT`, and attributed blocks.
  - Matches one manual number to one rectangle.
  - Writes package dry-run artifacts to `<source>_PACKAGED_reports/`.

- `BSPACKAGEBUILD`
  - Warns the user to finish layout `2` first.
  - Re-runs the package index.
  - In `DryRun` mode, writes reports only.
  - In `Apply` mode, saves the current DWG first, then `SAVEAS`es to `<source>_PACKAGED.dwg` or a timestamped variant, duplicates layout `2` for missing numeric layouts, retargets the main viewport for each sheet, attempts viewport-only `BORDER` freeze, and updates title-block sheet/total attributes where recognized.

## Config

Config file:

- `05_toolkit/config/bspackage_config.json`

The first implementation assumes axis-aligned sheet rectangles. Rotated or non-rectangular borders are rejected during indexing instead of guessed.

## Reports

Generated under the packaged report folder:

- `sheet_index.json`
- `sheet_index.csv`
- `sheet_index_report.md`
- `layout_plan.json`
- `package_build_report.json`
- `package_build_report.md`

## Notes

- Manual `BORDER` number is the source of truth.
- Model-space geometry defines the viewport target only after the manual number selects the sheet.
- The original working DWG is not silently modified; apply mode packages into a new DWG first.
- AutoCAD execution remains untested until the commands are run inside Map 3D.
- This command set is intentionally standalone and is not registered through `bs_loader.lsp`.
