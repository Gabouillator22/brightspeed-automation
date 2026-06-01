# NCDOT Permit Compliance — Skill Reference

Source: `04_documentation/BRIGHTSPEED REQUIREMENTS AND COMMANDS.docx (1).pdf`

## Sheet organization
- Maximum **25 sheets per permit**.
- Profiles at the **end** of the permit set (Sheet 25 area).
- Separate permits for separate route sections.
- Sheet number blocks → `BORDER` layer (prevents printing in permit sheets).

## Text heights (hard rules)
| Content | Height |
|---|---|
| Street names | 6.0 |
| All other labels | 5.0 |
| Never scale text down | — |

## Standardized label formats (exact strings — state refuses deviations)
| Feature | Label |
|---|---|
| Handhole | `STA XX+XX PL HANDHOLE` |
| Bore pit | `STA XX+XX PL 36"X36" BORE PIT` |
| Pole with riser up | `STA XX+XX EX POLE/RISER UP` |
| Pole with riser down | `STA XX+XX EX POLE/RISER DOWN` |
| Buried fiber callout | `HDD BORE [N]' FIBER IN 2" DUCT` (HDD BORE prefix always present) |
| Aerial callout | **No footage** — remove length from aerial callouts |
| MIN DOC note | `MIN DOC 60"` — required on every sheet with underground work |

## Stationing rules
- Aerial stationing: **not required** except for pole with riser.
- Buried stationing: does **not** include aerial footage.
- At aerial↔buried transitions: riser pole must show station including underground footage.
- Follow UP/DOWN RISER labeling based on route path direction.

## Label placement
- All labels on the **same side** as the fiber line.
- Avoid overlaps between: dimensions, fiber callouts, poles/HHs, GPS callouts, street names.
- Move pole and HH symbols **above** the fiber line.

## Work area labeling
- Continuous fiber = single work area: `WORK AREA 1 START` / `WORK AREA 1A END`, `1B END`, …
- Disconnected fiber = new area number: `WORK AREA 2 START` / `WORK AREA 2A END`, …
- Every start/end label includes lat/lon on the next line.

## Fiber line standards
- All proposed fiber lines: global width **0.5**.
- Enable **LINETYPE GENERATION** on all fiber polylines.
- Colors from **layer** only — never manually assigned.
- Remove fiber (aerial or buried) not along NCDOT roads.
  - Add red arrow at structure + note: `FIBER CONTINUES OUTSIDE OF NCDOT R/W.`
  - If aerial/pole inside property lot: note this on the sheet.
  - Note for non-NCDOT roads: `NCDOT DOES NOT APPROVE ANYTHING OUTSIDE OF R/W.`

## ROW dimension stacks (BSROWDIMS)
- NCDOT standard: 60' ROW / 30' half-ROW / 20' EOP / fiber offset stacked arrows.
- Dims must be **perfectly parallel** (state refuses otherwise).
- 10' spacing between each arrow in the stack.
- Placed at entry and exit edges of each sheet border.
- Dim style: `SQUAN 60` if available.

## Geomap / imagery
- All geomap images → `VIEWPORT IMAGE` layer.
- Geomap fade: **30** to improve linework visibility.
- Freeze `BORDER` layer in permit sheets (prevents tile numbers from printing).

## Profiles
- Two standard profiles if applicable: Typical Aerial Parallel Profile + Typical Bore Parallel Profile.
- Include only the types that apply to the project.
- Note on sheets: `SEE ALL PROFILES ON SHEET XX.`
