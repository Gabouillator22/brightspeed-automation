# 0002 — Z-independent curve sampling over IntersectWith

**Date:** 2026-06-01
**Status:** Accepted
**Deciders:** Gabriel, Claude

## Context
NC83F (NC State Plane NAD83 US Survey Foot) drawings frequently have road centerlines at Z≠0 (elevation data). The `IntersectWith mode 0` (strict 3D intersection) silently returns no results when a Z=0 temporary entity is tested against a Z≠0 curve — causing `bsrowdims.lsp` to produce no dimensions.

## Decision
Replace all `IntersectWith` calls that involve curve-boundary crossing detection with a 2D arc-length sampling approach:
1. Sample up to 200 points along the curve using `vlax-curve-getPointAtDist`.
2. Flatten each point to Z=0 with `bsrd-flat`.
3. Test each flattened point against the 2D bounding box.

This is implemented in `bsrd-cl-bbox-span` in `bsrowdims.lsp`.

## Consequences
- Fully Z-independent — works regardless of elevation data.
- Slightly less exact at entry/exit boundary (up to `totalLength/200` feet of error — negligible at permit sheet scale).
- `bsrd-cl-bbox-span` is the canonical pattern for CL boundary detection going forward.

## Alternatives considered
- **IntersectWith mode 3 (extend both):** Rejected — still fails on Z≠0 if entities have no true 3D intersection.
- **Project curve to Z=0 with entmod:** Rejected — mutates the drawing; violates the "no side effects" principle.
