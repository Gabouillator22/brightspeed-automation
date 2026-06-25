# Brightspeed Sheet Planner

Creates proposed `BORDER` sheet rectangles along the running lines exported from `BSKMZ`.
This supports the early workflow where sheets are placed first, then the oversized
database/map linework is trimmed to those sheets.

## Setup

Install Python 3, then from the copied Brightspeed toolkit folder:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install pyproj shapely
```

This machine has Python 3.12 installed. If `python` opens the Microsoft Store, use the local virtual environment command shown below.

## Generate Sheets

### One-command AutoCAD workflow

Use this when starting from the field KMZ:

1. `APPLOAD bs_loader.lsp`
2. Run `BSSHEETKMZ`
3. Pick the KMZ file
4. Review the orange proposed sheets

`BSSHEETKMZ` imports the same handholes/running lines as `BSKMZ`, writes the KMZ running-line records to `bssheet_route_selected.txt`, runs the Python planner, loads `bssheet_plan.lsp`, and draws the proposed sheets.

The original `BSKMZ` command is unchanged.

### Manual Python workflow

Run `BSKMZ` first. Its intermediate export format is:

```text
P|FOLDER|lon|lat
L|FOLDER|lon,lat;lon,lat;...
```

Then run the planner against either that BSKMZ text export, the source KMZ/KML, CSV, or GeoJSON:

```powershell
.\.venv\Scripts\python.exe .\05_toolkit\python\bssheetplan.py --input path_to_bskmz_export --out-dir .\06_jobs\inbox\fremont_northwest1\sheet_outputs
```

Outputs:

- `bssheet_plan.csv`
- `bssheet_plan.lsp`
- `bssheet_report.txt`

## AutoCAD Workflow

1. `APPLOAD bs_loader.lsp`
2. If `bssheets.lsp` is not loader-enabled yet, `APPLOAD bssheets.lsp`
3. Run `BSSHEETMAKEPLAN` if `bssheet_plan.lsp` is loaded, or run `BSSHEETLOAD` then `BSSHEETMAKE`
4. Review orange proposed sheets on `BS-SHEET-PROPOSED`
5. Move/rotate rectangles manually if needed
6. Run `BSSHEETACCEPT` and select approved proposed rectangles
7. Run `BSSHEETCLEAR` to hide remaining proposed rectangles without deleting them

`BSSHEETACCEPT` moves selected proposed rectangles to `BORDER` and sets color ByLayer. It does not delete anything.

## Measuring Existing Border Size

In AutoCAD:

1. Load `bssheets.lsp`
2. Run `BSSHEETRECT`
3. Select an existing four-corner `BORDER` rectangle
4. The command writes `sheet_width_ft` and `sheet_height_ft` into `05_toolkit\config\bssheet_config.json`

If writing the JSON fails, copy the printed width and height into `05_toolkit\config\bssheet_config.json`.

## Config Defaults

```json
{
  "sheet_width_ft": 900,
  "sheet_height_ft": 600,
  "overlap_ft": 0,
  "side_margin_ft": 75,
  "road_buffer_left_ft": 150,
  "road_buffer_right_ft": 150,
  "required_edge_clearance_ft": 20,
  "endpoint_inset_ratio": 0.6667,
  "fixed_sheet_angle_deg": 0,
  "target_epsg": 2264,
  "border_layer": "BORDER",
  "proposed_layer": "BS-SHEET-PROPOSED",
  "label_layer": "BS-SHEET-LABELS"
}
```

The planner transforms lon/lat coordinates from `EPSG:4326` to North Carolina State Plane feet `EPSG:2264`. If the input coordinates already look like State Plane feet, it leaves them unchanged.

`overlap_ft` defaults to `0` so proposed sheets are generated as a touching chain, not stacked over each other.

`endpoint_inset_ratio` controls the start/end context. The default `0.6667` means the running-line start and end are pushed deep into the first and last sheets instead of sitting on the sheet edge.

`road_buffer_left_ft` and `road_buffer_right_ft` define the road/context corridor that must fit inside the sheets around the running line. `required_edge_clearance_ft` keeps that corridor away from the sheet border.

`fixed_sheet_angle_deg` keeps every sheet parallel. The default `0` creates straight rectangles aligned to the drawing axes instead of rotating each sheet to the running line.

## Report

`bssheet_report.txt` includes:

- route length
- sheet count
- total covered feet
- uncovered corridor stations, if any
- sheet overlap warnings, if any
- branch count

If uncovered corridor stations appear, the running-line road corridor is not fully inside the proposed sheets at those stations. Reduce the corridor width, increase sheet height, manually rotate/shift those sheets, or split the run into a better sheet chain.

If sheet overlap warnings appear, adjacent proposed sheets are physically crossing each other. Review those sheet pairs in AutoCAD before accepting them to `BORDER`.
