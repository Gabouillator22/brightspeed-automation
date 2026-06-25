# Brightspeed Callout Automation Rules

This document is the source of truth for KMZ running-line placement and callout automation.
Update it whenever a finished DWG, PDF, screenshot, or drafting decision changes the rules.

## Reference Inputs

Use these references when validating the script:

- Finished DWG when available.
- Finished reference DWG: `C:\Users\Gabriel\Desktop\BRIGHTSPEED\JOBS\May 2026\Week 3\Job 2\FRMTNCXA_VANCE_V4.dwg`
- KMZ used to create the finished job.
- Screenshots of correct callouts and sheet layout.
- Screenshots of incorrect callouts, if available.

The DWG can reveal layers, object types, text, rotations, styles, and existing callout placement.
Screenshots and user rules define the drafting intent behind those objects.

## Overall Workflow

Recommended automation sequence:

1. Import KMZ running lines and structures.
2. Snap/align imported geometry to drafting standards.
3. Build a station network along the running route.
4. Place handhole and bore pit station callouts.
5. Place buried fiber segment callouts.
6. Place aerial fiber line callouts.
7. Place aerial footage marker objects.
8. Repeat required line callouts per sheet when a segment crosses sheet borders.
9. Run an audit to find missing, duplicate, or misplaced callouts.

## Command Architecture

Use multiple internal commands plus one master command.

Recommended commands:

- `BSCALLOUTS-RUN` - master command that runs the full callout sequence.
- `BSCALLOUTS-STRUCTURES` - handhole and bore pit callouts only.
- `BSCALLOUTS-BURIED` - buried fiber callouts only.
- `BSCALLOUTS-AERIAL` - aerial fiber callouts and aerial footage markers only.
- `BSCALLOUTS-CLEAR` - removes generated callouts only, using a generation marker/layer rule.
- `BSCALLOUTS-AUDIT` - reports missing/duplicate callouts without changing the drawing.

This keeps the workflow automatic while still letting us debug one family of callouts at a time.

Implemented first-pass commands:

- `BSCALLOUTS-RUN`
- `BSCALLOUTS-STRUCTURES`
- `BSCALLOUTS-BURIED`
- `BSCALLOUTS-AERIAL`
- `BSCALLOUTS-AUDIT`

Not implemented yet:

- `BSCALLOUTS-CLEAR`

The first-pass implementation is non-destructive and does not delete existing callouts.

## Layers And Source Objects

KMZ folder mapping:

| KMZ folder names | AutoCAD result |
|---|---|
| `HANDHOLE`, `CO` | handhole block on `HANDHOLE` layer |
| `BORE` | bore pit block on `BORE PIT` layer |
| `POLE` | pole block; only poles with risers get station labels |
| `UNDERGROUND`, `BURIED` | buried fiber on `Buried Fiber in Duct` layer |
| `AERIAL`, `NEW STRAND`, `NEW BUILD`, `NEW STRAND/NEW BUILD` | aerial fiber on `AERIAL FIBER` layer |
| `ELASH`, `E-LASH`, `OVERLASH` | elash/aerial existing attachment line |

Callout layer:

- Finished examples show callouts as `Multileader` objects on `CABLE CALLOUTS`.
- Current older toolkit used plain `TEXT` plus `LINE`; final automation should use `MLEADER`/`MULTILEADER` behavior where practical.

Structure detection:

- Handholes are red square blocks with `HH` inside.
- Bore pits are red square blocks with red hatch/diagonal lines inside.
- The script should find these from expected layers and from block names. Do not rely only on one exact layer name, because drawings may use variants such as `HANDHOLES` or block names containing `HH`, `HANDHOLE`, or `BORE`.

## Sheet Rule

Final deliverables are sheet/layout-driven.

Callouts must be placed inside accepted sheet/border areas. Nothing intended for final output should be placed outside the sheet coverage area.

When a fiber segment crosses a sheet border, the callout must appear on both sheets.

Important: repeated sheet callouts use the full source segment length, not the clipped visible length inside that sheet.

## Stationing Rule

Handhole and bore pit stations are cumulative along the total running route.

Do not reset stationing at each fiber segment.

Route station start:

- Station `00+00` starts from the first route point coming from the KMZ.
- The first route point will normally be a handhole or a pole with riser.
- The command should derive the center/running route from the KMZ import, not from manually placed callouts.

Technology reset rule:

- When the route changes from aerial to buried fiber, the length/station count resets to `00+00` for the new technology section.
- Aerial pole-to-pole footage and buried structure-to-structure footage are measured separately.
- Plain poles do not get station labels. Only poles with risers are stationed.

Branch rule:

- Callouts must be generated on each route branch.
- Stationing/callout logic should treat branches explicitly instead of only processing one main route.
- If branch stationing behavior is ambiguous, prefer producing correct callouts per branch over skipping the branch.

Example:

- Total route length is 800 feet.
- The route is split into 3 line segments.
- If the last handhole sits at the 800-foot cumulative position, its callout is:

```text
STA 08+00 PL HANDHOLE
```

Station formatting:

```text
STA ##+##
```

Use feet as station units. `08+00` means 800 feet.
Use leading zeroes for early stations, for example `STA 00+00`, `STA 00+52`, and `STA 04+00`.

## Structure Callouts

Handhole callout text:

```text
STA ##+## PL
HANDHOLE
```

Bore pit callout text:

```text
STA ##+## PL
36"x36" BORE PIT
```

Known rules:

- Handhole callouts are always the same format.
- Bore pit callouts are a separate standard from handholes.
- Structure stationing is cumulative from route start.
- Structure stationing must include the continuous cumulative length of all connected buried lines in that buried route section. Do not restart at each bore pit or handhole.
- Structure callouts should follow the finished-file/screenshot rotation.
- Bore pit callouts should be parallel to the bore pit symbol/block, the red square with hatch/diagonal red lines inside.
- Handhole callouts should be parallel to the handhole symbol/block, the red square with `HH` inside.
- Structure callouts should be `Multileader` objects.

## Buried Fiber Callouts

Buried fiber callout text:

```text
HDD BORE 42' FIBER IN 2" DUCT
```

Rules:

- Always use `HDD BORE`.
- Length is the distance between two structures.
- Structures include handholes and bore pits.
- If a buried source line is cut by a sheet border, use the full source segment length, not the visible clipped sheet length.
- If the same segment appears on multiple sheets, repeat the same full-length callout on each sheet.
- Leader arrow must point exactly at the buried fiber line.
- Fiber callout text is not aligned with the line unless a finished example proves otherwise.
- Place the text on the same side of the road/ROW as the buried fiber line.
- The whole text box must stay on that side, not only the leader/text insertion point. Since AutoCAD MLeader text grows rightward from its insertion point, left-side callouts must shift the insertion point left by the box width.
- Do not place the text over road labels, ROW/EOP/CL geometry, dimensions, other callouts, structures, or other drafting elements.
- Buried callout text should normally sit close to the leader arrow, roughly 10-20 feet away when a clear spot exists.
- Buried callout placement should search multiple same-side offsets in feet, then shift slightly along the line until a blank rectangle is found inside the sheet border.
- The HDD bore leader arrow/tip must land on the fiber line, never inside the bore pit or handhole symbol.
- When a buried segment starts/ends at a structure, place the leader tip outside the structure by roughly 10-20 feet along the fiber line.
- The callout object should be one `Multileader`.
- The apparent filled rectangle is the multileader text background mask/frame around the callout text, not a separate loose rectangle that needs manual placement.
- The callout text should display with a filled white background mask only. Do not show a black rectangle/frame around the text.
- Leader geometry should land at the edge of the text background and must not pass through or underneath the filled callout text.

## Aerial Fiber Callouts

Aerial fiber callout text:

```text
NEW AERIAL FIBER STRAND
```

Elash callout text:

```text
AERIAL FIBER ELASHED TO EXISTING
```

Rules:

- Aerial line callout identifies the aerial line type.
- Aerial footage is stored in a small object placed along the aerial line, not in the main callout text.
- Aerial length is always measured pole-to-pole.
- If a pole-to-pole aerial segment crosses a sheet border, repeat the required callout/footage marker on both sheets.
- Leader arrow must point exactly at the aerial line.
- Red aerial line labels such as `E-LASH` align with the aerial line.
- Main fiber callouts are not aligned with the fiber line unless the standard screenshot shows that specific callout aligned.

## Aerial Footage Marker

Screenshots show a small rounded/oval marker placed along aerial line segments with footage such as:

```text
171'
```

Rules:

- Footage marker length is pole-to-pole.
- Marker is placed along or near the corresponding aerial segment.
- Marker is repeated per sheet when the pole-to-pole segment crosses sheets.
- Marker appears as a small object, not plain unboxed text.
- Finished screenshot properties show this marker as block reference `AUBS`.
- Example selected marker properties:
  - Layer: `0`
  - Name: `AUBS`
  - Scale X/Y/Z: `0.600000`
  - Rotation: `0`
  - Custom value `SL`: footage text, for example `171'`
  - Custom values `Distance1`, `Angle1`, `Angle2`, `Position1 X`, and `Position1 Y` are present.

The meaning/source of `AUBS` is not known yet. Treat it as an observed finished-file block name until the finished DWG is inspected.

Implementation note:

- If the drawing already contains block definition `AUBS`, the script inserts it at scale `0.6` and attempts to set dynamic property `SL` to the footage string.
- If `AUBS` is missing, the first-pass script falls back to a callout-style text marker so the run can continue.

## Leader And Arrow Rules

Finished screenshots show callouts as multileaders on `CABLE CALLOUTS`.

Confirmed multileader properties from screenshot:

- Object type: `Multileader`
- Layer: `CABLE CALLOUTS`
- Multileader style: `Standard`
- Leader type: `Straight`
- Arrowhead: `Closed filled`
- Arrowhead size: `8.500000`
- Horizontal landing: `Yes`
- Landing distance: `5.000000`
- Text style: `Standard`
- Text height: `5.000000`
- Text justification: `Left`
- Background mask: `Yes`
- Text frame / visible outline: `No`

Rules:

- Arrow tips must land exactly on the referenced line or structure.
- Buried and aerial fiber arrows point to the fiber line.
- Structure arrows point to the handhole or bore pit symbol/block.
- Use generated callouts only; avoid manual placement.

Open detail:

- Exact MLeader style name.
- Arrowhead type and size.
- Landing gap and text attachment behavior.
- Text height and text style from finished DWG.

## Duplicate Rules

The automation should avoid duplicate callouts.

Expected behavior:

- If generated callouts already exist for a segment/structure/sheet, do not add a second copy.
- Do not delete old callouts at the start of the first automation pass.
- Prefer a generation marker strategy if possible, such as XData, object handle mapping, or a dedicated generated-callout layer/name convention.
- Until generated callouts have reliable source/sheet ownership markers, existing objects on `CABLE CALLOUTS` are soft conflicts for placement planning. They should be reported, but they must not globally block unrelated leader corridors.
- `BSCALLOUTS-CLEAR` should remove only generated callouts, not manually drafted notes unless explicitly requested.

## Length Rules

Buried fiber:

- Measure between structures.
- Use cumulative stationing for structures.
- Use segment length for line callouts.
- Do not reduce length because of sheet clipping.

Aerial fiber:

- Measure pole-to-pole.
- Main aerial callout gives line type.
- Footage marker gives pole-to-pole length.

## Known Existing Toolkit Gap

Current scripts provide a first draft only:

- `BSCALLOUT` and `BSCALLOUT-AUTO` attempt to create `Multileader` callouts on `CABLE CALLOUTS`, then fall back to plain `TEXT` and a simple `LINE` if AutoCAD rejects ActiveX multileader creation.
- `BSAERIAL-AUTO` creates plain `TEXT` and a simple `LINE`.
- `BSSTATION` places simple station `TEXT`.

Final callout automation should move toward multileader-style objects and sheet-aware duplication.

New first-pass script:

- `05_toolkit\lisp\bscallouts_auto.lsp`
- Uses `BORDER` geometry to repeat callouts per sheet when a source segment crosses sheets.
- Uses `CABLE CALLOUTS` for generated callouts.
- Attempts to create `Multileader` objects through AutoCAD ActiveX.
- Falls back to plain leader line plus text only if AutoCAD rejects ActiveX multileader creation.
- Does not clear or delete old callouts.
- `BSCALLOUTS-AUDIT` compares handhole and bore pit block counts against generated structure callout text counts and warns when they do not match.

## Remaining Questions

1. If multiple branches exist within the same technology section, does stationing continue through branches from the branch tie-in distance, or restart at the branch's first point?
2. Should the script create the `AUBS` aerial footage marker from an existing block definition only, or should it be able to create/import the block definition if missing?
3. Should generated multileaders use the current drawing's `Standard` MLeader style exactly, or should the script create a dedicated Brightspeed style if missing?
4. What exact duplicate-detection tolerance should be used: text match within a radius, object handle mapping, sheet/segment IDs, or another rule?
