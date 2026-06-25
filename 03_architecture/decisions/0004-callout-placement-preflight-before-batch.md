# 0004 - Callout placement requires preflight acceptance before batch drawing

Date: 2026-06-05

Status: Accepted

## Context

`bscallout_live.py` proved that the AutoLISP helper can create visually correct
callouts: arrow, MLeader form, text height, layer behavior, and filled text
background were acceptable.

`bscallout_batch.py` then improved speed by generating one LISP batch, but the
first live use showed a planning defect: callouts were placed over centerlines
and in the middle of roads. The batch report already showed road collisions,
but the batch writer still emitted those commands because it selected the best
candidate even when every candidate was bad.

## Decision

Keep the existing LISP drawing helper unchanged.

Move callout placement quality into Python preflight planning:

- reject candidates that collide with protected road/ROW/centerline/property
  geometry
- reject candidates whose text box is outside the sheet border
- add leader-corridor checks before accepting a candidate
- write only accepted placements into batch LISP
- report skipped/manual callouts with exact blocker handles and reasons

The slow live path remains available as a diagnostic/reference workflow. The
fast batch path is the production target only after it includes hard acceptance
rules.

## Consequences

- Batch placement will be faster and safer, but may skip callouts in dense
  sheets until candidate generation improves.
- Manual correction becomes explicit: skipped callouts are a reportable work
  queue, not accidental bad geometry.
- Future placement architectures must be documented in
  `03_architecture/callout-placement-architectures.md` before they are treated
  as stable production behavior.
