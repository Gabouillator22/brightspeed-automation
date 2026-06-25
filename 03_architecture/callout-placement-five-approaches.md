# Callout Placement Five Approaches

Date: 2026-06-08

Status: design proposal, not implementation

Scope: Brightspeed NCDOT permit callout placement for aerial fiber, buried
fiber, structures, MIN DOC labels, and repeated sheet labels.

This document intentionally does not assume the current Brightspeed callout
commands are the right architecture. Existing commands and reports are used
only as failure evidence and constraint context.

External AutoLISP material under
`02_research/external_autolisp_goldmine/` was reviewed as reference-only. The
useful ideas are curve sampling, point-at-distance operations, selection
filters, bounding boxes, text masks, draw-order handling, and variant/XData
patterns. No external code should be copied into Brightspeed production.

## 1. Problem Restatement

The drawing contains real-world utility geometry and sheet rectangles. The
permit set needs readable labels that identify structures, fiber technology,
depth notes, and repeated route information. A good callout is not just a text
string. It is a geometry decision:

- which source object is being labeled
- which sheet needs the label
- where the arrow touches the source
- where the text box goes
- which side of the road or route is acceptable
- what geometry the leader line may cross
- what geometry the text box must avoid
- whether a callout already exists for the same source and sheet

The core difficulty is that a correct source label can still be a bad drawing
label if it lands in the road, crosses a centerline, overlaps ROW, covers a
parcel, hides a structure, sits outside the sheet, or appears only once when
the same source spans multiple sheets.

The system needs a deterministic planner that can answer:

1. What labels are required?
2. Which sheets require each label?
3. Which candidate positions are legal?
4. Which candidate is best?
5. Which labels need human review instead of silent failure?

## 2. Geometry Inputs

Every approach needs the following geometry families, even if the extraction
method differs.

### Source Routes

- `LINE`, `LWPOLYLINE`, and `POLYLINE` route geometry.
- Buried layers:
  - `Buried Fiber in Duct`
  - `BURIED FIBER IN DUCT`
  - `BURIED FIBER`
  - `UNDERGROUND`
  - `PROPOSED BURIED`
- Aerial layers:
  - `AERIAL FIBER`
  - `NEW STRAND`
  - `NEW BUILD`
  - `E-LASH`
  - `OVERLASH`
- Route chain, branches, bends, intersections, and technology transitions.
- Full source segment length, independent of sheet clipping.

### Sheet Geometry

- Accepted permit sheet rectangles or view areas.
- `BORDER` layer closed rectangular polylines where available.
- Bounding boxes for fallback sheet rectangles.
- Sheet number or sheet ID if available.
- Local sheet coordinate system: inside area, top rail, bottom rail, left rail,
  right rail, and no-label margin.

### Structures

- Handhole points or blocks.
- Bore pit points or blocks.
- Pole blocks.
- Riser up/down classification.
- Structure rotation and block extents.
- Connection to the route graph for stationing.

### Collision Geometry

- Road centerlines.
- ROW / ROW-TRAP.
- EOP and pavement edges.
- Parcel and property lines.
- Existing fiber geometry.
- Structure blocks and their extents.
- Existing labels, callouts, MLeaders, dimensions, and text boxes.
- Borders, viewports, title blocks, match lines, north arrows, and sheet notes.

### Layer Categories

The planner should not reason only from exact layer names. It should map layers
into semantic groups:

- route-buried
- route-aerial
- structures
- road-body
- road-edge
- ROW
- parcels
- existing-labels
- sheet-boundaries
- protected-title/blocking areas
- temporary-planning
- final-callouts

## 3. NCDOT Label Rules

Canonical formats from project memory:

| Feature | Required label |
|---|---|
| Handhole | `STA XX+XX PL HANDHOLE` |
| Bore pit | `STA XX+XX PL 36"X36" BORE PIT` |
| Pole riser up | `STA XX+XX EX POLE/RISER UP` |
| Pole riser down | `STA XX+XX EX POLE/RISER DOWN` |
| Buried fiber | `HDD BORE [N]' FIBER IN 2" DUCT` |
| Aerial fiber | No footage label |
| MIN DOC | `MIN DOC 60"` |

Additional Brightspeed drafting rules:

- Callout text height is `5.0`.
- Callouts belong on `CABLE CALLOUTS`.
- Colors must remain BYLAYER.
- Buried fiber repeated across sheets uses the full source segment length, not
  the clipped visible length inside a sheet.
- Aerial pole-to-pole footage markers repeat per sheet when the same segment
  appears on multiple sheets.
- Leader arrow tips must touch the referenced source object, not a nearby
  structure by accident.
- Generated callouts should carry ownership metadata eventually: source handle,
  source family, sheet ID, and label text.

## 4. Approach 1: CAD-Native Route-Normal Search

### Concept

AutoCAD runs one native command. The command extracts sources, samples each
source inside each sheet, builds candidate leader anchors, and tries route
normal offsets on the same side of the road or ROW. It keeps the workflow
simple and avoids Python handoff files.

This is the closest to a "single reliable LISP command", but it should be a
fresh command, not a continuation of the current fragile command body.

### Geometry/math model

- Convert each route entity into distance samples using `vlax-curve` distance
  functions.
- Flatten sampled points to 2D to avoid mixed-Z failures.
- Group samples by `BORDER` rectangle.
- For each source-sheet pair, choose an anchor:
  - buried route: middle sampled point of the visible source portion
  - aerial route: middle pole-to-pole visible portion
  - structures: block insertion point or route-connected nearest point
- Estimate tangent at anchor from neighboring samples.
- Generate normal offsets on both sides, then prefer the side away from
  centerline/EOP/road body.
- Candidate text boxes are axis-aligned approximations with text height `5.0`,
  label length, and padding.
- Reject candidates whose box or leader corridor crosses protected geometry.

### Required layers/temp entities

Final:

- `CABLE CALLOUTS`

Optional debug:

- `BS-CALLOUT-ANCHORS`
- `BS-CALLOUT-CANDIDATES`
- `BS-CALLOUT-COLLISION`
- `BS-CALLOUT-REVIEW`

### Data flow

1. LISP scans drawing selections or whole model space.
2. LISP builds route, sheet, structure, and blocker lists in memory.
3. LISP generates candidates and scores them.
4. LISP creates final MLeaders for accepted candidates.
5. LISP creates review markers for unresolved candidates.
6. LISP prints a command report.

### AutoCAD/LISP role

LISP does all extraction, sampling, collision checks, drawing, and reporting.
It must use undo bracketing and restore sysvars.

### Python or external planner role

None for production. Python could later provide regression tests against DXF
fixtures, but the workflow remains CAD-native.

### Aerial routes

- Place route type callouts such as `NEW AERIAL FIBER STRAND` or
  `AERIAL FIBER ELASHED TO EXISTING` once per pole-to-pole segment per sheet.
- Place `AUBS` footage markers if the block exists.
- If `AUBS` is missing, create a review marker rather than silently using a
  non-standard marker in production.

### Buried routes

- Measure each structure-to-structure buried source once.
- Build `HDD BORE [N]' FIBER IN 2" DUCT`.
- Repeat once per sheet where samples fall inside the sheet.
- Use the same full length on every sheet.
- Prefer a leader anchor inside the visible portion and 10-20 feet away from a
  structure if the visible portion contains the end of the segment.

### Handholes

- Station from the route graph.
- Place `STA XX+XX PL HANDHOLE`.
- Use nearby route tangent to choose a leader side.
- Treat the handhole block extent as a protected zone for other labels.

### Bore pits

- Station from the route graph.
- Place `STA XX+XX PL 36"X36" BORE PIT`.
- Prefer label rotation/side related to the bore pit block rotation.
- Treat bore pit hatch/block extent as protected.

### Pole risers

- Detect riser up/down classification from block attributes, nearby transition
  geometry, or explicit layer/block naming.
- Place either `STA XX+XX EX POLE/RISER UP` or
  `STA XX+XX EX POLE/RISER DOWN`.
- No labels for ordinary poles.

### Repeated labels per sheet

The sample grouping is the sheet-repeat engine. A source that has samples in
three `BORDER` rectangles gets three source-sheet records and therefore three
callouts. Each callout keeps the source-level label text.

### Collision avoidance

- Text box cannot overlap blockers.
- Leader corridor cannot cross blockers.
- Candidate must remain inside sheet with a margin.
- Candidate should not cross road centerline unless there is no other legal
  route.
- Existing callouts are soft conflicts unless they carry a matching generated
  owner marker.

### Failure/manual review

If no candidate is legal, create a small review marker at the anchor on
`BS-CALLOUT-REVIEW` and print:

- source handle
- sheet ID
- label text
- rejected candidate count
- top blocker handles/layers

### End-to-end workflow

1. User APPLOADs the new experimental LISP file.
2. User runs one command, for example `BSCALLOUTX`.
3. Command scans source objects and sheets.
4. Command optionally draws anchors/candidates if debug mode is on.
5. Command places final callouts.
6. Command marks unresolved callouts for review.
7. User runs a cleanup command to remove planning layers.
8. Command report is copied to the AutoCAD text window or written to a local
   report file.

### Pros

- Single command for the drafter.
- No Python/COM startup or handoff failure.
- Easy to test in a scratch DWG.
- Good fit for immediate AutoCAD-first production.

### Cons

- AutoLISP is weaker for complex collision geometry.
- Harder to unit test than Python.
- Long LISP functions can become fragile if not kept small.
- Candidate search may be slower on very dense drawings.

### Implementation complexity

Medium.

### Expected reliability

Medium-high if the first prototype is scoped to buried routes and one sheet
case, then expanded carefully.

## 5. Approach 2: Python Preflight Planner With LISP Executor

### Concept

Python reads exported geometry, plans every callout, produces a transparent
plan file, and AutoCAD runs a small LISP executor that draws only accepted
placements. The planner is not allowed to draw directly. The executor is not
allowed to decide placement quality.

This is a stricter version of a planner/executor split, but it should be
rebuilt around a readable plan schema rather than command strings.

### Geometry/math model

- Python converts all route objects into Shapely geometries.
- Sheet rectangles become polygons.
- Blockers become lines, polygons, or buffered zones.
- Text boxes and leader corridors are real polygons.
- Candidate generation:
  - route-normal offsets
  - radial/quadrant offsets around structures
  - sheet rail candidates
  - along-route shifts
- Candidate score:
  - inside sheet margin
  - same-side preference
  - road/ROW avoidance
  - leader length target
  - overlap count
  - visual balance within sheet
- Hard reject if protected collision exists.

### Required layers/temp entities

Final:

- `CABLE CALLOUTS`

Planning/debug:

- `BS-CALLOUT-CANDIDATES`
- `BS-CALLOUT-COLLISION`
- `BS-CALLOUT-REVIEW`

Data files:

- `callout_plan.json`
- `callout_plan.csv`
- `callout_report.md`
- optional generated executor `.lsp`

### Data flow

1. LISP exporter writes geometry to JSON/CSV.
2. Python planner reads geometry.
3. Python writes `callout_plan.json` with accepted, rejected, and review rows.
4. User reviews report if desired.
5. LISP executor reads `callout_plan.json` and creates MLeaders.
6. LISP writes execution result back to a report.

### AutoCAD/LISP role

- Export geometry.
- Draw debug layers from the plan.
- Create final MLeaders.
- Attach ownership metadata to generated objects.
- Clear only generated planning layers.

### Python or external planner role

- All source-sheet pairing.
- All candidate generation.
- All collision checks.
- All scoring.
- All reports.
- Regression tests.

### Aerial routes

Python creates one route-type label and one optional `AUBS` footage marker per
source-sheet pair. The LISP executor inserts the `AUBS` block only if present;
otherwise it creates a review row.

### Buried routes

Python measures the full buried source segment once, then repeats the same
`HDD BORE [N]' FIBER IN 2" DUCT` label for every sheet intersection.

### Handholes

Python stationing engine computes cumulative station positions. Structure
callout candidates are tested radially around the block while respecting sheet
limits and route side.

### Bore pits

Bore pit station labels use the same structure engine, but collision boxes are
inflated because bore pit symbols are larger and visually busier.

### Pole risers

Python classifies risers from attributes/layers/block names if available and
places only riser poles. Ambiguous poles go to review.

### Repeated labels per sheet

The plan schema has one row per required source-sheet label. A source crossing
three sheets produces three rows with the same `source_id` and text but
different `sheet_id`, anchor, and text point.

### Collision avoidance

Python uses polygon operations:

- text-box polygon vs blockers
- leader-corridor polygon vs blockers
- sheet polygon containment
- no-label intersection buffers
- spacing from existing labels

### Failure/manual review

Review rows are first-class output, not a side effect. Each row includes:

- source ID
- sheet ID
- reason
- best rejected candidate
- blocker IDs/layers
- preview geometry

### End-to-end workflow

1. User runs `BSCALLOUTX-EXPORT`.
2. User runs planner from PowerShell or AutoCAD launches it.
3. Planner writes `callout_plan.json` and `callout_report.md`.
4. User optionally runs `BSCALLOUTX-PREVIEW` to draw debug geometry.
5. User runs `BSCALLOUTX-APPLY`.
6. Executor creates final MLeaders and ownership metadata.
7. User runs `BSCALLOUTX-CLEAN-GUIDES`.
8. User runs `BSCALLOUTX-AUDIT`.

### Pros

- Best geometry tooling.
- Best testability.
- Best reports.
- Clean separation of planning and drawing.
- Easy to compare algorithm variants.

### Cons

- More moving parts.
- Export/import contracts must be bulletproof.
- Previous Python placement attempts created user trust problems, so the first
  prototype must be small and visible.
- Requires dependency stability.

### Implementation complexity

High.

### Expected reliability

High after prototype hardening, medium during early rebuild.

## 6. Approach 3: Temporary Guide Geometry And Human Acceptance

### Concept

The planner does not immediately create final callouts. It creates visible CAD
guide geometry: anchor ticks, candidate boxes, leader rays, collision zones,
and review markers. The drafter can see the proposed placement before final
MLeaders are created.

This approach treats AutoCAD itself as the review UI.

### Geometry/math model

- Every required source-sheet label becomes a guide bundle.
- Candidate leader anchors are ticks on the source.
- Candidate text boxes are rectangles on a temporary layer.
- Candidate leader corridors are lightweight guide polylines or rays.
- Rejected candidates are optionally drawn in a separate layer.
- Accepted candidates are marked with a source-sheet ID.

### Required layers/temp entities

- `BS-CALLOUT-GUIDES`
- `BS-CALLOUT-ANCHORS`
- `BS-CALLOUT-CANDIDATES`
- `BS-CALLOUT-COLLISION`
- `BS-CALLOUT-REVIEW`
- `BS-CALLOUT-MASKS`
- final `CABLE CALLOUTS`

### Data flow

1. Planner creates temporary guide geometry in model space.
2. User inspects the guides sheet by sheet.
3. User accepts all clean guides or manually moves candidate boxes.
4. Finalizer converts accepted guide bundles into MLeaders.
5. Cleanup deletes temporary layers.

### AutoCAD/LISP role

LISP can do almost everything here:

- draw guide entities
- attach XData to guide bundles
- allow user to accept/move/reject
- convert guide bundles to final callouts
- remove guides

Python can be absent or optional.

### Python or external planner role

Optional. Python could generate higher-quality candidates, but the defining
feature is that the drawing receives visible disposable geometry before final
placement.

### Aerial routes

Draw guide anchors on aerial spans and optional `AUBS` marker locations. The
user can see if markers are too close to poles, road labels, or sheet edges.

### Buried routes

Draw one guide bundle per buried source-sheet pair. The guide text always uses
the full source length. Candidate boxes near the visible segment show where
final MLeaders would land.

### Handholes

Draw station label candidates around each handhole. If the station engine is
uncertain, the guide marker shows a warning instead of placing final text.

### Bore pits

Draw station label candidates outside the bore pit block extent, with inflated
collision boxes.

### Pole risers

Draw riser labels only for classified riser poles. Ambiguous poles receive a
review marker.

### Repeated labels per sheet

The planner draws one guide bundle per source-sheet pair. Missing repeats are
visible because an expected source crossing each `BORDER` should have a guide
inside each sheet.

### Collision avoidance

The planner shows collisions instead of only reporting them:

- red rectangles for bad text boxes
- red leader corridors for crossings
- yellow boxes for soft conflicts
- green boxes for accepted candidates

### Failure/manual review

Manual review is the main workflow, not an exception. Unresolved labels remain
as review markers until accepted, moved, or explicitly skipped.

### End-to-end workflow

1. User runs `BSCALLOUTX-GUIDES`.
2. AutoCAD draws all candidate guide geometry.
3. User pans through sheets and reviews guide colors.
4. User moves or deletes guide boxes if needed.
5. User runs `BSCALLOUTX-FINALIZE`.
6. Finalizer creates MLeaders from accepted guide bundles.
7. User runs `BSCALLOUTX-CLEAN-GUIDES`.
8. Audit verifies missing source-sheet labels.

### Pros

- Very transparent.
- Easy to debug visually.
- Safer when automation confidence is low.
- Lets a human fix hard cases without fighting generated MLeaders.

### Cons

- More clicks than a full automatic command.
- Requires disciplined cleanup.
- Temporary geometry can clutter drawings if left behind.
- Needs robust XData/ownership on guide bundles.

### Implementation complexity

Medium.

### Expected reliability

High for user-trusted production, medium for full automation speed.

## 7. Approach 4: Graph-Based Route Segmentation And Conflict Graph

### Concept

Build an explicit route graph before placing anything. Nodes are structures,
poles, bends, intersections, sheet crossings, technology transitions, and
branch points. Edges are route spans. Required labels come from graph edges and
nodes, not raw independent CAD entities.

Then build a conflict graph between labels. Placement is solved as an ordering
and conflict-resolution problem.

### Geometry/math model

- Route graph:
  - node types: handhole, bore pit, pole, riser, branch, bend, sheet crossing
  - edge types: buried, aerial, e-lash
  - edge length: full source/structure span
  - edge sheet coverage: sheet IDs crossed by edge
- Label graph:
  - one required label node per source-sheet pair
  - candidate placements per label node
  - conflict edges between candidate boxes/corridors
- Solve in staged passes:
  1. structures
  2. MIN DOC
  3. buried route labels
  4. aerial route labels
  5. aerial footage markers
  6. repeated route labels and cleanup labels

### Required layers/temp entities

- `BS-CALLOUT-ANCHORS`
- `BS-CALLOUT-CANDIDATES`
- `BS-CALLOUT-COLLISION`
- `BS-CALLOUT-REVIEW`
- optional `BS-ROUTE-GRAPH`
- final `CABLE CALLOUTS`

### Data flow

1. Extract routes and structures.
2. Snap structures to route graph.
3. Insert graph nodes at sheet crossings and technology transitions.
4. Generate required labels from graph rules.
5. Generate candidate placements for each required label.
6. Build conflict graph.
7. Choose a non-conflicting candidate set in priority order.
8. Draw accepted labels; mark unresolved graph nodes.

### AutoCAD/LISP role

LISP draws final callouts and may draw route graph/debug geometry. It may also
perform a lightweight graph build if Python is not used, but this approach is
better with Python.

### Python or external planner role

Python should own graph construction, route snapping, sheet crossing, conflict
graph creation, scoring, and report generation.

### Aerial routes

Aerial labels are generated from aerial graph edges. Pole-to-pole lengths and
`AUBS` markers are graph edge attributes, not text guesses from raw line
fragments.

### Buried routes

Buried HDD labels are generated from buried graph edges between structures.
The edge length is the full label length. Each sheet coverage entry creates one
repeated label using the same edge length.

### Handholes

Handhole labels are graph node labels. Stationing is derived from graph
distance along the route section, not from nearest isolated polyline.

### Bore pits

Bore pit labels are graph node labels. Bends and bore pit symbols can be
related explicitly in the graph.

### Pole risers

Risers are transition nodes between aerial and buried edges. The graph can
classify up/down based on edge direction and technology transition.

### Repeated labels per sheet

Sheet crossings are graph events. An edge with coverage `[5, 6, 7]` must
produce three labels. If the final output has fewer than three, the audit can
prove the miss.

### Collision avoidance

Conflict graph edges represent collisions between candidate placements. The
solver freezes high-priority labels first, then chooses lower-priority
candidates that do not conflict.

### Failure/manual review

Unsolved labels remain graph nodes with no selected candidate. The report can
show the exact conflict set, not just "failed".

### End-to-end workflow

1. User runs route graph builder.
2. User optionally previews `BS-ROUTE-GRAPH`.
3. User runs placement planner.
4. Planner stages labels by priority.
5. Planner outputs final placements plus unresolved graph conflicts.
6. LISP executor places final MLeaders.
7. Audit checks required graph label count against placed object metadata.

### Pros

- Best long-term model for structures, stationing, branches, and transitions.
- Prevents raw entity fragmentation from controlling label correctness.
- Makes missing repeated labels auditable.
- Handles bends and route transitions naturally.

### Cons

- Larger architecture.
- Requires a robust route graph, which is a separate hard problem.
- More up-front work before visible payoff.
- Needs many fixture tests.

### Implementation complexity

Very high.

### Expected reliability

Very high once implemented, low-medium during early development.

## 8. Approach 5: Sheet-Local Rails And Occupancy Map

### Concept

Treat each sheet like a small drafting page with reserved annotation rails and
an occupancy map. Labels are not merely offset from their source. They are
placed into available page slots, with leaders routed back to anchors.

This approach imitates final sheet drafting: keep labels in clean regions and
away from the road body.

### Geometry/math model

- Divide each sheet into cells, for example 5-foot or 10-foot grid cells.
- Mark occupied cells:
  - road body
  - ROW/EOP/CL
  - parcels
  - structures
  - title block and borders
  - existing labels
- Define label rails:
  - top rail
  - bottom rail
  - left rail
  - right rail
  - near-route shoulder rails
- Each required label searches rail slots first.
- Leader corridors are routed from rail slot to anchor as simple straight or
  two-segment leaders.
- Slot scoring considers distance, crossing count, density, and route side.

### Required layers/temp entities

- `BS-CALLOUT-GUIDES`
- `BS-CALLOUT-CANDIDATES`
- `BS-CALLOUT-COLLISION`
- `BS-CALLOUT-REVIEW`
- optional `BS-CALLOUT-HEATMAP`
- final `CABLE CALLOUTS`

### Data flow

1. For each sheet, create an occupancy grid.
2. Convert source labels into per-sheet requirements.
3. Sort labels by priority and size.
4. Assign labels into rail slots.
5. Test leader corridors.
6. Freeze accepted slots and update occupancy.
7. Place final callouts.

### AutoCAD/LISP role

LISP can draw the final callouts and optionally draw rail/debug geometry.
Python is better for occupancy-grid construction and scoring, but a simple
LISP-only version is possible for rectangular sheets.

### Python or external planner role

Python can own:

- grid construction
- occupancy rasterization
- label slot search
- heatmap report
- conflict summaries

### Aerial routes

Aerial labels and footage markers use the same rail assignment but receive
lower priority than structure labels. Footage markers are preferably placed
near the route, not on far sheet rails.

### Buried routes

Buried HDD labels use rail slots nearest the visible buried portion. If a
source appears on three sheets, the sheet requirement generator creates three
rail assignments with the same full-length label.

### Handholes

Handholes get high priority because station labels are structure-critical.
They are placed before route labels so route labels route around them.

### Bore pits

Bore pit labels are high priority and receive larger exclusion zones.

### Pole risers

Riser labels are medium-high priority because they explain technology
transitions.

### Repeated labels per sheet

The sheet requirement generator makes one label requirement for every
source-sheet pair. The occupancy map is sheet-local, so each sheet is solved
independently after global source text is calculated.

### Collision avoidance

Collision avoidance is explicit occupancy:

- occupied cells are illegal
- near-occupied cells receive penalties
- leader corridors update occupancy after placement
- accepted labels freeze cells for later labels

### Failure/manual review

If no slot exists, the label receives a review marker at the anchor and the
heatmap shows why the sheet is saturated.

### End-to-end workflow

1. User runs planner.
2. Planner builds occupancy per sheet.
3. Planner optionally draws rails and heatmap.
4. Planner places accepted labels or previews them.
5. Review markers show saturated sheets.
6. User cleans temporary heatmap/rail layers.
7. Audit checks required vs placed counts.

### Pros

- Excellent visual organization.
- Good for crowded sheets.
- Very transparent with heatmap/debug layers.
- Scales to many label families.

### Cons

- More abstract than normal CAD drafting.
- Requires tuning grid size and rail definitions.
- May create longer leaders.
- Grid approximation can reject possible placements unless resolution is good.

### Implementation complexity

High.

### Expected reliability

High for visual quality after tuning, medium for first prototype.

## 9. Candidate Approach Ideas Covered

The five approaches cover these candidate ideas:

- Route-normal offset labels: Approach 1 and Approach 2.
- Radial/quadrant search around anchor points: Approach 2 and Approach 4.
- Sheet-local callout lanes: Approach 5.
- Collision-box scoring and simulated placement: Approach 2 and Approach 5.
- Temporary guide geometry generated in CAD: Approach 3.
- Python preflight planner with AutoCAD execution: Approach 2.
- Graph-based route segmentation: Approach 4.
- Grid/occupancy-map placement: Approach 5.
- Structure-first then route-label second pass: Approach 4 and Approach 5.
- Human-review layer for unresolved callouts: all approaches, especially
  Approach 3.

## 10. Temporary Geometry Strategy

Temporary geometry should be treated as an intentional planning product, not
debug leftovers.

### Layers

- `BS-CALLOUT-GUIDES`: neutral guide lines and rails.
- `BS-CALLOUT-ANCHORS`: ticks or small crosses at arrow anchor points.
- `BS-CALLOUT-CANDIDATES`: candidate text boxes and leader paths.
- `BS-CALLOUT-COLLISION`: rejected boxes/corridors and blocker highlights.
- `BS-CALLOUT-REVIEW`: unresolved required labels.
- `BS-CALLOUT-MASKS`: optional simulated text background extents.

### Entity types

- Guide rays from anchor along candidate leader directions.
- Candidate text boxes as closed lightweight polylines.
- Leader corridors as buffered rectangles or simple polylines with width.
- Anchor ticks as short crossing lines.
- Rejected candidate markers as small red X geometry or colored boxes.
- Review markers as small blocks/text with source handle and sheet ID.

### Metadata

Each guide bundle should carry XData or clear text attributes:

- source handle
- source type
- sheet ID
- label text
- candidate ID
- decision state: accepted, rejected, review
- rejection reason

### Cleanup

A cleanup command should delete only the temporary planning layers:

- `BSCALLOUTX-CLEAN-GUIDES`

It must not delete final `CABLE CALLOUTS`. It should warn if final callouts
still depend on unfinalized guide bundles.

## 11. End-to-End Workflow Summary

### Approach 1 workflow

User runs one CAD-native command. The command scans, plans, places, logs, and
marks review items. Debug layers are optional.

### Approach 2 workflow

User exports geometry, runs a Python planner, previews the plan, applies the
accepted rows through LISP, then audits.

### Approach 3 workflow

User generates visible guide geometry, reviews or adjusts it in AutoCAD,
finalizes accepted guides into MLeaders, then cleans guide layers.

### Approach 4 workflow

User builds a route graph, previews graph errors, plans labels from graph
nodes/edges, places labels in staged priority order, and audits graph coverage.

### Approach 5 workflow

User builds sheet occupancy maps, assigns labels into rails, previews crowded
sheets with heatmap/debug geometry, places final labels, and audits missing
requirements.

## 12. Non-Obvious Ideas

1. Callout corridors: treat leader paths as buffered geometry, not just lines.
2. Sheet-edge label rails: reserve page lanes near sheet edges for labels.
3. Route-side preference inferred from road centerline and ROW geometry.
4. No-label zones around intersections, bore pits, handholes, and driveways.
5. Callout density heatmap per sheet to reveal saturated areas.
6. Staged placement with frozen accepted labels, so later passes route around
   earlier accepted labels.
7. Conflict graph between labels, where overlapping candidates become graph
   edges and the solver chooses a compatible set.
8. Automatic split of long HDD label opportunities across allowed sheet
   locations without changing the required full source length text.
9. Anchor sliding windows: move the arrow anchor along a legal portion of the
   source while keeping the label tied to the same source-sheet requirement.
10. Border-entry anchors: for a source entering a sheet and ending inside it,
   place the arrow halfway between sheet border crossing and source endpoint.
11. Review-first mode: generate only guide boxes and no final MLeaders until
   the drafter accepts the sheet.
12. Ownership metadata on final MLeaders for exact duplicate prevention.
13. Candidate "why rejected" geometry, where clicking a review marker shows
   blocker handles and layers.
14. Per-sheet label budget: cap the number of route labels per rail and force
   crowded sheets into review instead of making unreadable drawings.
15. Protected title-block buffer extracted from layout or model-space blocks.
16. Technology transition priority: riser labels place before aerial/buried
   route labels because they explain why stationing resets.
17. Label family zoning: structures near route, MIN DOC in a fixed sheet zone,
   route labels on rails, repeated labels near visible source center.
18. Frozen manual labels: manually accepted labels can be tagged so future
   automation treats them as fixed blockers, not duplicates to delete.
19. Local leader rerouting: use a two-segment leader if a straight leader would
   cross ROW or CL.
20. Audit-only dry run: compute all required labels and missing counts without
   drawing anything.

## 13. Recommendation Matrix

Scores: 1 low, 5 high.

| Approach | Reliability | Implementation speed | AutoCAD compatibility | User control | Visual quality | Failure transparency | Future extensibility |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1. CAD-native route-normal search | 3 | 4 | 5 | 3 | 3 | 3 | 3 |
| 2. Python preflight planner + LISP executor | 4 | 2 | 3 | 4 | 4 | 5 | 5 |
| 3. Temporary guide geometry + acceptance | 4 | 3 | 5 | 5 | 4 | 5 | 4 |
| 4. Graph-based segmentation + conflict graph | 5 | 1 | 3 | 4 | 5 | 5 | 5 |
| 5. Sheet rails + occupancy map | 4 | 2 | 4 | 4 | 5 | 4 | 5 |

## 14. Final Recommendation

The best first experiment is Approach 3: Temporary Guide Geometry And Human
Acceptance.

Reasoning:

- It does not depend on trusting a full automatic planner immediately.
- It makes the hidden geometry decisions visible in AutoCAD.
- It can prove sheet-aware repeated labels without finalizing bad MLeaders.
- It can be implemented as a new experimental command without touching
  production commands.
- It gives the drafter control while still moving toward automation.
- It creates reusable pieces for every other approach: anchors, candidate
  boxes, leader corridors, review markers, ownership metadata, and cleanup.

Approach 1 is the fastest one-command target, but recent failures show that
silent one-command behavior is risky until the planner can explain itself.
Approach 2 is likely the best long-term production engine. Approach 4 is the
best final architecture for stationing, structures, branches, and transitions.
Approach 5 is the best visual-quality direction for crowded sheets. But the
first proof should be visible, reversible, and independent of production
commands.

## 15. First Prototype Plan

Prototype name:

- `bscallout_guides_experiment.lsp`

Prototype command names:

- `BSCALLOUTX-GUIDES`
- `BSCALLOUTX-FINALIZE`
- `BSCALLOUTX-CLEAN-GUIDES`
- `BSCALLOUTX-AUDIT`

Do not register these in `bs_loader.lsp` at first. APPLOAD the experiment file
directly in a scratch drawing.

### Minimum prototype scope

Only buried fiber, only `BORDER` rectangles, only guide generation.

The prototype should:

1. Scan buried fiber entities on known buried layers.
2. Scan `BORDER` rectangles by bounding box.
3. Measure each buried source length once.
4. Generate one required label per source-sheet pair.
5. Use the full source length for every repeated label.
6. Sample the source inside each sheet and choose the middle visible sample as
   the first anchor rule.
7. Draw anchor ticks on `BS-CALLOUT-ANCHORS`.
8. Draw candidate text boxes on `BS-CALLOUT-CANDIDATES`.
9. Draw leader guide rays on `BS-CALLOUT-GUIDES`.
10. Draw review markers if a source intersects a sheet but has no sample.
11. Print counts:
    - buried sources found
    - BORDER rectangles found
    - required source-sheet labels
    - guide bundles created
    - review markers created

### Success criteria

- A buried source crossing two sheets creates two guide bundles.
- Both guide bundles show the same full HDD label text.
- Each anchor lands on the visible part of the source inside the sheet.
- No final MLeaders are created in the first prototype.
- Cleanup removes every temporary guide layer and leaves source geometry alone.

### Next prototype after guide success

Add finalization:

1. Convert accepted guide bundles into MLeaders on `CABLE CALLOUTS`.
2. Attach ownership metadata.
3. Audit required source-sheet labels against final generated callouts.
4. Add collision boxes and rejected candidate visualization.

This proves the planning model before risking production callout placement.

## 16. 2026-06-08 Forced Placement Direction

User preference changed the acceptance policy: missing callouts are worse than
imperfect callouts. The first implementation should therefore place every
required callout row and use quality status only to mark visibility risk.

Implementation direction:

- Approach 2 remains the core: Python plans, AutoLISP executes MLeaders.
- Approach 5 contributes sheet-local placement discipline and structure-first
  ordering.
- Approach 3 contributes visible review markers for imperfect placements.
- Candidate quality is classified as `clean`, `warn`, or `forced`.
- `forced` still creates a final MLeader on `CABLE CALLOUTS`; it also creates
  a review marker on `BS-CALLOUT-REVIEW`.
- Only source-definition failures should prevent placement. Collision, ugly
  leader length, or crowded sheets should not suppress a required callout.

The first code path for this direction is intentionally experimental but uses
the canonical command names in `bscallouts_auto.lsp` because the loader already
advertises the `BSCALLOUTS-*` family.
