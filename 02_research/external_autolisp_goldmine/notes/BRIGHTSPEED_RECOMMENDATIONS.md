# Brightspeed Recommendations

Top clean-room reimplementation ideas from the static audit. These are not merge approvals.

1. Callout MLeader creation
   - Source candidates: `raw_lsp/gc_AutomationHelpers.lsp` (high, score 43)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_AutomationHelpers.lsp: callout/mleader, arrow/leader creation, polyline splitting

2. Text background masks for callouts
   - Source candidates: `raw_lsp/Obj2wipeout.lsp` (high, score 66); `raw_lsp/Cadre_Masque.lsp` (medium, score 56); `raw_lsp/Special_selections.lsp` (medium, score 48)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities; raw_lsp/Cadre_Masque.lsp: text background mask, polyline splitting, selection filtering, collision/placement helpers, sort/draw order

3. Sheet-aware repeated callout placement
   - Source candidates: `raw_lsp/gc_MathGeom.lsp` (low, score 70); `raw_lsp/Obj2wipeout.lsp` (high, score 66); `raw_lsp/Cadre_Masque.lsp` (medium, score 56)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_MathGeom.lsp: polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order; raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities

4. Route splitting and segment extraction
   - Source candidates: `raw_lsp/gc_MathGeom.lsp` (low, score 70); `raw_lsp/Obj2wipeout.lsp` (high, score 66); `raw_lsp/Cadre_Masque.lsp` (medium, score 56)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_MathGeom.lsp: polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order; raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities

5. Bore pit insertion at 90-degree bends
   - Source candidates: `raw_lsp/gc_MathGeom.lsp` (low, score 70); `raw_lsp/Obj2wipeout.lsp` (high, score 66); `raw_lsp/Cadre_Masque.lsp` (medium, score 56)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_MathGeom.lsp: polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order; raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities

6. Handhole and bore pit block handling
   - Source candidates: `raw_lsp/gc_MathGeom.lsp` (low, score 70); `raw_lsp/Special_selections.lsp` (medium, score 48); `extracted/TotalArea/TotalArea.lsp` (high, score 44)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_MathGeom.lsp: polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order; raw_lsp/Special_selections.lsp: polyline splitting, point along curve, block handling, selection filtering

7. Selection filtering for fiber and structure entities
   - Source candidates: `raw_lsp/gc_MathGeom.lsp` (low, score 70); `raw_lsp/Obj2wipeout.lsp` (high, score 66); `raw_lsp/Cadre_Masque.lsp` (medium, score 56)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_MathGeom.lsp: polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order; raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities

8. Layer utilities with BYLAYER-safe reimplementation
   - Source candidates: `raw_lsp/Obj2wipeout.lsp` (high, score 66); `extracted/TotalArea/TotalArea.lsp` (high, score 44); `extracted/TotalPerim/TotalPerim.lsp` (high, score 44)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities; extracted/TotalArea/TotalArea.lsp: polyline splitting, block handling, selection filtering, layer utilities, sort/draw order

9. Draw order and mask ordering
   - Source candidates: `raw_lsp/gc_MathGeom.lsp` (low, score 70); `raw_lsp/Obj2wipeout.lsp` (high, score 66); `raw_lsp/Cadre_Masque.lsp` (medium, score 56)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_MathGeom.lsp: polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order; raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities

10. Curve math helper library
   - Source candidates: `raw_lsp/gc_MathGeom.lsp` (low, score 70); `raw_lsp/Obj2wipeout.lsp` (high, score 66); `raw_lsp/Special_selections.lsp` (medium, score 48)
   - Recommendation: use only as a static pattern reference, then reimplement with Brightspeed undo/error/layer rules.
   - Evidence: raw_lsp/gc_MathGeom.lsp: polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order; raw_lsp/Obj2wipeout.lsp: text background mask, polyline splitting, point along curve, selection filtering, layer utilities
