# Callout Guide Diagnostic

Date: 2026-06-09  
Scope: diagnostic only. No production files were modified.

## 1. Current Callout Architecture Map

### Existing files

- `05_toolkit/lisp/bscallout.lsp`
- `05_toolkit/lisp/bscallouts_auto.lsp`
- `05_toolkit/lisp/working_commands/bscallout_place.lsp`
- `05_toolkit/lisp/working_commands/bscallouts_auto_V1.lsp`
- `05_toolkit/python/bscallout_live.py`
- `05_toolkit/python/bscallout_batch.py`
- `05_toolkit/python/bscallouts_forced.py`

### Commands currently exposed

- `bscallout.lsp`
  - `BSCALLOUT`
  - `BSCALLOUT-AUTO`
  - `BSCALLOUT-END-AUTO` compatibility alias
- `bscallouts_auto.lsp`
  - `BSCALLOUTS-RUN`
  - `BSCALLOUTS-AUDIT`
  - `BSCALLOUTS-STRUCTURES`
  - `BSCALLOUTS-BURIED`
  - `BSCALLOUTS-AERIAL`
  - `BSCALLOUTS-CLEAN`
  - `BSCALLOUTS-FORCED-*` compatibility aliases
- `working_commands/bscallout_place.lsp`
  - `bscw-place-mleader`
  - `BSCWPLACEHELPER`
- `working_commands/bscallouts_auto_V1.lsp`
  - no new production-facing behavior beyond the existing wrapper family
- `bscallout_live.py`
  - live planning/placement runner for buried callouts
- `bscallout_batch.py`
  - batch planner + LISP batch writer for buried callouts
- `bscallouts_forced.py`
  - broader planner/executor for buried, aerial, structure, and MIN DOC placement

### Current ownership by function

- Buried callouts in the older single-file path are still owned by `bscallout.lsp`:
  - `BSCALLOUT`
  - `BSCALLOUT-AUTO`
- Sheet-aware buried / structure / aerial orchestration is owned by `bscallouts_auto.lsp`, but the actual geometry planning is delegated to Python in the forced path.
- Final MLeader creation is owned by `working_commands/bscallout_place.lsp` through `bscw-place-mleader`.

### Who currently does what

- Current production-facing drawing primitive:
  - `bscw-place-mleader` in `working_commands/bscallout_place.lsp`
- Current buried-line callout placement in the single-file LISP path:
  - `bscallout.lsp`
- Current collision-aware buried planning in Python:
  - `bscallout_live.py`
  - `bscallout_batch.py`
- Current multi-family planning and forced placement:
  - `bscallouts_forced.py`
- Current repeated-callout handling per sheet:
  - `bscallout.lsp`
  - `bscallout_live.py`
  - `bscallout_batch.py`
  - `bscallouts_forced.py`

## 2. Current Failure Causes

### Why callouts sometimes become plain lines or bad leaders

- `bscallout.lsp` still contains a fallback path in `bsc-make-callout`:
  - it tries `vla-AddMLeader`
  - if that fails, it draws a simple `LINE` leader and `TEXT`
- That fallback is intentional, but it means a failed MLeader creation is not a hard error. The result can look visually acceptable in a quick pass while still being non-canonical.
- `bscallout.lsp` also has per-callout candidate generation, but it is still tied to approximate text box math and loose blocker detection. When the best candidate is weak, the fallback path can still produce something that looks wrong.

### Why callouts are placed in the road corridor

- The old single-file LISP path uses approximate candidate boxes and approximate blocker tests:
  - text width is estimated from string length
  - collision detection is mostly bounding-box based
  - leader corridor is not a first-class validated object in the older flow
- In the Python paths, road geometry is also frequently represented through blocker categories rather than exact route-aware placement constraints.
- In the forced planner, a candidate can still be accepted if it is merely the best available option, even when the sheet is congested. The architecture now supports hard rejection, but the plan still degrades to `warn` or `forced` placement rather than preventing placement entirely.

### Why sheet-split segments are not always getting repeated callouts

- In the older LISP flow, sheet repetition depends on `BORDER` detection and on whether the source can be sampled inside each border rectangle.
- In `bscallout_live.py`, `matching_borders()` relies on bbox intersection plus shapely intersection. If border geometry is missing, malformed, or not a clean rectangle, the segment can fall back to `GLOBAL` or can miss a repeat.
- In `bscallout.lsp`, the visible-point anchor logic can fail when no sample points land inside a sheet, causing fallback behavior instead of a repeat.
- In `bscallouts_forced.py`, sheet repetition depends on `source_sheets()`, which is now more careful, but still relies on border geometry being a closed rectangular polyline and on sample-point coverage.

### Why the current system is hard to trust

- The system mixes at least four placement philosophies:
  - manual one-off MLeader creation
  - self-contained LISP auto placement
  - live Python placement with retry/validation
  - batch Python preflight + generated LISP execution
- The same conceptual decision can be made in different places:
  - in LISP
  - in Python
  - in generated LISP
  - or by a fallback path if something fails
- Existing-callout detection is still heuristic in several paths. It is not a reliable source/sheet ownership system.
- Some paths still count a result as success once a handle exists, even if the object is later judged visually or geometrically weak.

### Where the core defect most likely is

- This is primarily a placement-planning problem, not a pure MLeader-creation problem.
- The code now proves that AutoCAD can create acceptable MLeaders when given a good plan.
- The failures are mainly in:
  - source-sheet detection
  - candidate generation
  - collision validation
  - fallback policy when no strong candidate exists
- MLeader creation still matters, but it is not the main cause of road-corridor failures.

## 3. Feasibility of Temporary Placement Rectangle / Guide Geometry Approach

### Technical viability in AutoLISP

Yes, it is technically viable.

- AutoLISP can:
  - compute approximate text extents
  - create temporary closed LWPOLYLINE rectangles
  - create guide lines / rays
  - sample curves using `vlax-curve-*`
  - test collision against blockers using bounding boxes or curve proximity
  - attach metadata with XData
  - delete only objects on dedicated layers
- The main limitation is that AutoLISP collision testing will stay approximation-heavy unless the geometry checks are kept intentionally simple.

### Technical viability in Python + LISP

Yes, and it is safer.

- Python is better for:
  - rectangle math
  - corridor buffering
  - leader collision checks
  - repeated-sheet grouping
  - rejection reporting
- LISP is better for:
  - drawing temporary guide entities in AutoCAD
  - tagging guide bundles
  - final MLeader creation
  - cleanup in the active drawing
- This split matches the repository’s current direction in `bscallout_live.py`, `bscallout_batch.py`, and `bscallouts_forced.py`.

### Which is safer for this repo right now

Python + LISP is safer.

- The repo already contains a Python planning layer and a LISP drawing helper.
- The new idea is fundamentally a planner/executor split, and Python is the better place to compute and rank candidate rectangles.
- AutoLISP-only is viable for a small prototype, but it is more likely to drift into fragile geometry code quickly.

### Can it be done without touching production files

Yes.

- The prototype can live entirely in `05_toolkit/lisp/working_commands/`.
- It can APPLOAD directly in a scratch drawing.
- It does not need `bs_loader.lsp` changes for the experiment.

### Can it be done as an experimental APPLOAD-only file

Yes.

- That is the safest way to prove the guide-geometry idea.
- It should not be registered in `bs_loader.lsp` until the experiment is validated.

### Main risks

- Temporary geometry can clutter drawings if cleanup is not perfect.
- A rectangle-only acceptance model can reject viable placements in dense drawings.
- If the guide rectangles are treated as final truth too early, the experiment can encode a bad placement heuristic.
- If XData ownership is skipped, cleanup and audit will become unreliable.

## 4. Minimal Experimental Implementation Path

### Recommended file split

Create only:

- `05_toolkit/lisp/working_commands/bscallout_guides_experiment.lsp`

### Recommended command split

- `BSCALLOUTX-GUIDES`
  - generate candidate guide bundles only
- `BSCALLOUTX-FINALIZE`
  - convert accepted guide bundles into final MLeaders
- `BSCALLOUTX-CLEAN-GUIDES`
  - delete only temporary guide entities
- `BSCALLOUTX-AUDIT`
  - report missing guide bundles, unresolved collisions, and repeated-sheet coverage

### Is this the right split

Yes.

- The guide generator and finalizer should be separate so the plan can be inspected before final output exists.
- The cleanup command should be separate so temporary geometry can be removed safely without touching final callouts.
- The audit command should be separate so repeated-sheet misses are visible before finalizing.

### What should not be included in v0

- No loader registration.
- No production file edits.
- No broad multi-family placement.
- No aerial or structure callouts.
- No auto-healing of ambiguous placements.
- No attempts to move or edit existing production MLeaders.

## 5. Prototype Scope

### Yes, this is the right v0

The proposed prototype scope is the correct first step.

It should:

- only handle buried fiber
- only scan `BORDER` rectangles
- not create final MLeaders yet
- generate one guide bundle per buried source segment per intersecting `BORDER`
- use the full source segment length for repeated labels
- sample the buried segment inside each `BORDER`
- choose the middle visible point as the initial anchor
- draw a candidate rectangle sized to fit the callout text
- draw a leader guide from anchor to rectangle edge
- mark collisions or review candidates
- print counts and debug info

### One refinement

The v0 should treat rectangle rejection as advisory unless it is obviously outside the sheet or colliding with a hard blocker.

Reason:

- a strict hard reject in v0 will overfit the early heuristic
- the first goal is visibility and debuggability, not perfect placement

## 6. Implementation Details To Evaluate

### AutoLISP-only

#### Text box width

- Use a conservative approximation based on string length and 5.0 text height.
- Current repo precedent:
  - `bscallout.lsp` uses `strlen * height * 0.68` with a minimum width clamp
  - `bscallout_live.py` and `bscallout_batch.py` use the same general approximation
- For the experiment, keep the width model simple and deterministic.

#### Temporary rectangles

- Create closed LWPOLYLINE rectangles on `BS-CALLOUT-CANDIDATES`.
- Keep them axis-aligned in v0.
- Store the anchor and source/sheet identity in XData or a companion text tag.

#### Rectangle intersections

- Use bounding-box intersection first.
- Use curve/entity proximity only if needed for hard blockers.
- Do not build a full geometric solver in LISP v0.

#### Sampling source polylines

- Use `vlax-curve-getPointAtDist` at a fixed interval.
- Reuse the current `bsc-curve-sample-points` pattern from `bscallout.lsp`.

#### Detecting sampled points inside a BORDER

- Use point-in-rect tests against the border bbox first.
- For v0, do not overcomplicate with full polygon clipping unless the border is not rectangular.

#### Metadata on guide bundles

- Use XData if the experiment needs robust cleanup and audit.
- If XData is too much for v0, use companion tagged `TEXT`/`MTEXT` placed on a debug layer, but that is weaker.

#### Safe cleanup

- Cleanup should delete only objects on the temporary layers:
  - `BS-CALLOUT-GUIDES`
  - `BS-CALLOUT-ANCHORS`
  - `BS-CALLOUT-CANDIDATES`
  - `BS-CALLOUT-COLLISION`
  - `BS-CALLOUT-REVIEW`
  - optional `BS-CALLOUT-MASKS`

### Python + LISP

#### Python responsibilities

- compute candidate boxes
- compute leader corridor
- score and reject candidates
- write a plan file for the drawing
- produce repeatable audit output

#### LISP responsibilities

- draw guide rectangles, anchor ticks, and corridor lines
- create final MLeaders only after finalization
- cleanup temporary layers

#### Final creation

- Final MLeader creation should remain in LISP, using the same drawing helper style that already exists in `bscallout_place.lsp`.

## 7. Compatibility With Current Repo

### Does this conflict with `bscallout.lsp`

No direct conflict if kept experimental.

- The experiment should not load into production by default.
- It should not overwrite the current buried callout command names.

### Does this conflict with `bscallout_live.py`

No direct conflict if the new file uses separate command names and separate layers.

- `bscallout_live.py` is a planning/placement path, not a guide-layer experiment.
- The new experiment can reuse ideas from it, but should not alter it.

### Does this require changing the loader

No.

- Do not edit `bs_loader.lsp` for v0.
- APPLOAD the experiment file manually in a scratch drawing.

### Can it live safely in `working_commands` and be manually APPLOADed

Yes.

- This is the recommended deployment mode for the experiment.
- It isolates the experiment from the production loader surface.

### Can it be tested on a scratch DWG without breaking anything

Yes, if the experiment obeys the temporary-layer cleanup rule.

- Use a copied scratch DWG.
- Keep all guide geometry on temporary layers.
- Do not touch existing production callout layers except when finalizing to a separate allowed target.

## 8. Recommendation

### Recommendation

Implement as a Python planner + LISP guide drawer experiment.

### Why

- The repo already has the right split direction.
- Python is the correct place for the candidate box math and repeated-sheet logic.
- LISP is the correct place for drawing the temporary guide geometry and final MLeaders.
- This keeps the experiment visible in AutoCAD without forcing the hard geometry logic into AutoLISP first.

### First file to create

- `05_toolkit/lisp/working_commands/bscallout_guides_experiment.lsp`

### Proposed commands

- `BSCALLOUTX-GUIDES`
- `BSCALLOUTX-FINALIZE`
- `BSCALLOUTX-CLEAN-GUIDES`
- `BSCALLOUTX-AUDIT`

### Proposed temporary layers

- `BS-CALLOUT-GUIDES`
- `BS-CALLOUT-ANCHORS`
- `BS-CALLOUT-CANDIDATES`
- `BS-CALLOUT-COLLISION`
- `BS-CALLOUT-REVIEW`
- `BS-CALLOUT-MASKS`

### Proposed data flow

1. Scan buried source geometry.
2. Scan `BORDER` rectangles.
3. Sample each buried segment inside each border.
4. Compute a candidate text rectangle and leader corridor.
5. Draw guide geometry on temporary layers.
6. Mark accepted / rejected / review candidates.
7. Finalize only accepted guide bundles into `CABLE CALLOUTS`.
8. Clean only the guide layers.
9. Audit source-sheet coverage against expected repeated labels.

### Risks

- candidate geometry may still be wrong if the text-width model is poor
- `BORDER` handling may miss non-rectangular sheet definitions
- cleanup can leave remnants if XData / layer tagging is incomplete
- guide clutter can become confusing if finalization is not clearly separated from preview mode

## 9. Exact Next Implementation Prompt If Approved

Use this prompt for the build step:

> Create a new experimental AutoLISP file at `05_toolkit/lisp/working_commands/bscallout_guides_experiment.lsp` only. Do not modify `bs_loader.lsp`, `bscallout.lsp`, `bscallout_place.lsp`, or any current production callout script. Implement APPLOAD-only experimental commands `BSCALLOUTX-GUIDES`, `BSCALLOUTX-FINALIZE`, `BSCALLOUTX-CLEAN-GUIDES`, and `BSCALLOUTX-AUDIT`. Prototype v0 must handle buried fiber only, scan only rectangular `BORDER` sheets, generate temporary guide rectangles / anchor ticks / leader guides on dedicated temporary layers, attach guide metadata, and leave final MLeader creation for finalize mode. Start with simple axis-aligned candidate rectangles based on text length, 5.0 text height, padding, and background mask allowance. Do not touch production layers or the loader. Keep cleanup limited to the temporary guide layers only.

## 10. Bottom Line

- The temporary rectangle / guide-geometry idea is viable.
- It is safest as a Python planner + LISP drawer experiment.
- It can be done without touching the current production structure.
- The right first test is buried fiber only, one scratch DWG, one candidate bundle per sheet intersection, with no final MLeaders until finalize mode.
