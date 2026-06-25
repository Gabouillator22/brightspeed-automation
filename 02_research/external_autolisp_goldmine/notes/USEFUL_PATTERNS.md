# Useful Patterns

Unknown-license external code is reference-only. Reimplement ideas cleanly before using them in Brightspeed production commands.

## Callouts and leaders
- `raw_lsp/Obj2wipeout.lsp`: Command routine: OB2WO. Teaches: text background mask, polyline splitting, point along curve, selection filtering, layer utilities. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Cadre_Masque.lsp`: Command routine: CT, MT. Teaches: text background mask, polyline splitting, selection filtering, collision/placement helpers, sort/draw order. Brightspeed use: clean-room pattern reference.
- `raw_lsp/gc_AutomationHelpers.lsp`: Leader/callout or annotation helper. Teaches: callout/mleader, arrow/leader creation, polyline splitting. Brightspeed use: clean-room pattern reference.

## Curve and route geometry
- `raw_lsp/gc_MathGeom.lsp`: Polyline or curve geometry helper. Teaches: polyline splitting, intersection, block handling, selection filtering, bounding boxes. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Obj2wipeout.lsp`: Command routine: OB2WO. Teaches: text background mask, polyline splitting, point along curve, selection filtering, layer utilities. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Cadre_Masque.lsp`: Command routine: CT, MT. Teaches: text background mask, polyline splitting, selection filtering, collision/placement helpers, sort/draw order. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Special_selections.lsp`: Command routine: INV_SEL, SSATT, SSC. Teaches: polyline splitting, point along curve, block handling, selection filtering. Brightspeed use: clean-room pattern reference.
- `extracted/TotalArea/TotalArea.lsp`: Command routine: AREABOX, AREACONV, AREAEDIT. Teaches: polyline splitting, block handling, selection filtering, layer utilities, sort/draw order. Brightspeed use: clean-room pattern reference.
- `extracted/TotalPerim/TotalPerim.lsp`: Command routine: PERIMBOX, PERIMCONV, PERIMEDIT. Teaches: polyline splitting, block handling, selection filtering, layer utilities, sort/draw order. Brightspeed use: clean-room pattern reference.
- `raw_lsp/gc_AutomationHelpers.lsp`: Leader/callout or annotation helper. Teaches: callout/mleader, arrow/leader creation, polyline splitting. Brightspeed use: clean-room pattern reference.
- `raw_lsp/3dPolyFillet.lsp`: Command routine: 3DPOLYFILLET. Teaches: polyline splitting, intersection, block handling. Brightspeed use: clean-room pattern reference.
- `raw_lsp/gc_List.lsp`: Polyline or curve geometry helper. Teaches: polyline splitting, intersection, sort/draw order. Brightspeed use: clean-room pattern reference.
- `raw_lsp/AddVtx_DelVtx.LSP`: Command routine: ADDVTX, DELVTX. Teaches: polyline splitting, intersection, selection filtering. Brightspeed use: clean-room pattern reference.

## Selection, block, and layer utilities
- `raw_lsp/gc_MathGeom.lsp`: Polyline or curve geometry helper. Teaches: polyline splitting, intersection, block handling, selection filtering, bounding boxes. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Obj2wipeout.lsp`: Command routine: OB2WO. Teaches: text background mask, polyline splitting, point along curve, selection filtering, layer utilities. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Cadre_Masque.lsp`: Command routine: CT, MT. Teaches: text background mask, polyline splitting, selection filtering, collision/placement helpers, sort/draw order. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Special_selections.lsp`: Command routine: INV_SEL, SSATT, SSC. Teaches: polyline splitting, point along curve, block handling, selection filtering. Brightspeed use: clean-room pattern reference.
- `extracted/TotalArea/TotalArea.lsp`: Command routine: AREABOX, AREACONV, AREAEDIT. Teaches: polyline splitting, block handling, selection filtering, layer utilities, sort/draw order. Brightspeed use: clean-room pattern reference.
- `extracted/TotalPerim/TotalPerim.lsp`: Command routine: PERIMBOX, PERIMCONV, PERIMEDIT. Teaches: polyline splitting, block handling, selection filtering, layer utilities, sort/draw order. Brightspeed use: clean-room pattern reference.
- `raw_lsp/3dPolyFillet.lsp`: Command routine: 3DPOLYFILLET. Teaches: polyline splitting, intersection, block handling. Brightspeed use: clean-room pattern reference.
- `raw_lsp/gc_List.lsp`: Polyline or curve geometry helper. Teaches: polyline splitting, intersection, sort/draw order. Brightspeed use: clean-room pattern reference.
- `raw_lsp/AddVtx_DelVtx.LSP`: Command routine: ADDVTX, DELVTX. Teaches: polyline splitting, intersection, selection filtering. Brightspeed use: clean-room pattern reference.
- `raw_lsp/Dialog.lsp`: Block or attribute helper. Teaches: block handling, selection filtering, layer utilities, sort/draw order. Brightspeed use: clean-room pattern reference.
