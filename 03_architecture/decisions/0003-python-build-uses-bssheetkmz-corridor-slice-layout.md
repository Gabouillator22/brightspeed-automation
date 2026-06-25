# 0003 - Python build uses BSSHEETKMZ corridor-slice sheet layout

**Date:** 2026-06-02
**Status:** Accepted
**Deciders:** Gabriel, Codex

## Context
The Python `bsbuild.py` workflow generates the working DXF from KMZ field lines, parcel data, and proposed sheet rectangles. The earlier Python sheet planner used a branch-grid approach and also contained a signature mismatch that prevented sheet generation.

## Decision
The Python builder now uses the same corridor-slice math as `BSSHEETKMZ`:
1. Sample each running-line segment at a fixed interval.
2. Add buffered sample points above and below the route.
3. Slice the route corridor in world-X using fixed-width sheet columns.
4. Stack whole sheet heights within each active column.

This preserves the existing `bsbuild.py` operating mode while matching the established sheet-placement workflow.

## Consequences
- Adjacent proposed sheet rectangles snap edge-to-edge in the generated build output.
- Sheet placement no longer depends on the old branch-grid planner for `bsbuild.py`.
- The Python planner remains deterministic and can be regression tested against a straight-route fixture.
