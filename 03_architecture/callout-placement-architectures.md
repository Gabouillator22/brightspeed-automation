# Callout Placement Architectures

This document records the placement philosophies being tested for Brightspeed
callouts. The goal is to make each idea explicit, testable, and reportable
before it becomes production behavior.

## Separation of concerns

The callout system has two separate responsibilities:

1. **Placement planning**
   - Owner: Python.
   - Chooses source fiber, sheet, anchor point, text point, side, offset,
     and collision risk.
   - Must be deterministic and report why each callout was accepted,
     rejected, or left for manual correction.

2. **Callout drawing**
   - Owner: AutoLISP helper `bscallout_place.lsp`.
   - Creates the MLeader, arrow, text height, layer, and filled text
     background.
   - This is not where road/centerline placement decisions belong.

## 2026-06-05 observation

The live AutoCAD placement primitive produced the desired drafting form:

- arrow style was correct
- text form was correct
- filled background behind text was correct
- MLeader creation was visually acceptable

The failure was planning quality. The fast batch planner selected candidates
whose report already showed road/centerline conflicts, then placed them anyway.
That means the defect belongs in Python candidate acceptance, not the LISP
drawing helper.

## Architecture A: live verified placement

**Implementation:** `bscallout_live.py`

**Philosophy:** Try a candidate, create it in AutoCAD, inspect the created
object, delete it if validation fails, then try another candidate.

**Strengths:**

- Highest confidence that created AutoCAD objects exist.
- Can reject bad created objects immediately.
- Useful for debugging exact MLeader behavior.

**Weaknesses:**

- Too slow for production-size drawings because each candidate requires a
  Python/COM/AutoCAD round trip.
- Can spend minutes on the first callout if many candidate attempts fail.
- Poor fit for 100+ segments or hundreds of sheets.

**Status:** Keep as diagnostic/reference path. Do not remove.

## Architecture B: fast batch placement

**Implementation:** `bscallout_batch.py`

**Philosophy:** Python plans all callouts once, writes one LISP batch, and
AutoCAD places all selected candidates in one native run using the proven
MLeader helper.

**Strengths:**

- Much faster than live verified placement.
- Keeps the same arrow, text, MLeader, and background-fill behavior.
- Good for production speed once planning quality is high.

**Weaknesses found on 2026-06-05:**

- Current version picks the best candidate even if every candidate is bad.
- A negative score can still be selected and placed.
- Candidate reports can show `road:*` conflicts while the batch still writes
  the callout.

**Decision:** Batch placement must not mean blind placement. A batch planner
needs hard acceptance rules before it writes LISP commands.

## Architecture C: hard reject on conflict

**Philosophy:** Do not write a placement command unless the chosen candidate is
clear by deterministic rules.

**Candidate acceptance rules:**

- reject if text box overlaps any road, centerline, ROW, EOP, property,
  dimension, structure, or other protected blocker
- reject if text box is outside the sheet border
- reject if the leader path crosses a protected blocker
- report existing callout conflicts, but do not hard-reject on them until
  generated callouts carry reliable source/sheet ownership markers
- report skipped callouts with exact handles and reasons

**Strengths:**

- Prevents known-bad callouts from being placed.
- Converts bad geometry into a review list instead of creating cleanup work.
- Still allows fast batch placement for candidates that are clearly good.

**Weaknesses:**

- May skip many callouts in dense sheets until the candidate search improves.
- Requires a clear manual workflow for skipped callouts.

**Status:** Recommended next implementation layer for `bscallout_batch.py`.

**2026-06-08 update:** Hard rejection is implemented, but it must not turn
"no clean automated candidate" into a silent no-deliverable outcome. Existing
callouts on `CABLE CALLOUTS` are now treated as soft conflicts in the batch
path, matching the older live one-by-one workflow. Road, ROW, paved-road,
dimension, structure, and other protected drafting geometry remain hard
rejects.

## Architecture D: leader corridor / test polyline

**User proposal:** Before accepting a callout, create or simulate a polyline
running along the leader path and/or beside the text, then ensure that geometry
does not cross roads or other linework.

**Technical interpretation:**

- Build a planned leader path from anchor to landing point to text point.
- Build a buffered corridor around that path, for example 2 to 5 drawing feet.
- Build a text collision polygon from the text bounding box.
- Reject the candidate if either geometry intersects protected blockers.

**What to test:**

- Does the leader corridor cross centerline, ROW, EOP, parcel, dimension, or
  existing labels?
- Does the text box sit over the pavement/centerline region?
- Does the leader arrow stay short enough to feel attached to the fiber?
- Does the text end up outside the road body but still close enough to read?

**Strengths:**

- Adds the human drafting intuition that the leader itself matters, not just
  the final text box.
- Makes placement quality explainable with geometry.
- Can run in Python before any AutoCAD placement happens.

**Weaknesses:**

- Requires better geometry extraction than bounding boxes for some blockers.
- A too-wide corridor may reject good placements in dense sheets.
- A too-narrow corridor may still allow ugly overlaps.

**Status:** Recommended as the next experimental architecture.

## Architecture E: sheet-side lane placement

**Philosophy:** Treat each sheet as having preferred annotation lanes near the
top, bottom, left, and right of the sheet. Place callouts into those lanes
instead of near the road center.

**Strengths:**

- Mimics how a human drafter often arranges labels.
- Reduces labels in the road body.
- May be very fast once lanes are computed.

**Weaknesses:**

- Longer leader lines may cross more geometry.
- Needs sheet orientation awareness.
- Dense sheets may still need manual stacking rules.

**Status:** Candidate follow-up if corridor rejection alone skips too much.

## Architecture F: human-in-the-loop batch review

**Philosophy:** Generate a plan report before placement and classify each
candidate as:

- `place`
- `skip`
- `manual`
- `needs-new-candidate`

Only `place` rows are emitted into the batch LISP.

**Strengths:**

- Keeps speed while adding human judgment.
- Makes production decisions auditable.
- Allows the user to approve a placement philosophy before hundreds of
  callouts are drawn.

**Weaknesses:**

- Requires a lightweight editing or review format.
- More process than a one-command run.

**Status:** Recommended once hard-reject and corridor reports exist.

## Required report fields for every placement architecture

Every callout planner report should include:

- source handle
- source layer
- source length
- sheet/border id
- label text
- anchor point
- text point
- selected side
- offset and tangent shift
- score
- decision: `place`, `skip`, `manual`, or `failed`
- hard-reject reasons
- blocker handles and layers
- leader-corridor collision result
- text-box collision result
- whether the command was emitted into batch LISP

## Current recommendation

Keep the validated MLeader drawing helper unchanged.

Next, evolve the fast batch path into:

1. plan all candidates
2. run hard rejection against text box and leader corridor
3. report existing-callout conflicts without using them as hard blockers until
   generated callouts have source/sheet ownership markers
4. emit accepted callouts
5. refuse empty `--run` batches with a clear message instead of treating them
   as successful placement
6. report skipped/manual callouts clearly
7. place accepted callouts in one batch

This preserves production speed without knowingly placing labels in the
middle of the road.
