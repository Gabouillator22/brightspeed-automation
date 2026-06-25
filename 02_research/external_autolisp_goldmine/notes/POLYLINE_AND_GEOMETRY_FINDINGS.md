# Polyline And Geometry Findings

Static scan for route segmentation, vertex edits, curve walking, closest-point helpers, intersections, and placement geometry.

## Brightspeed read

`gc_MathGeom.lsp`, `AddVtx_DelVtx.LSP`, `PolySegments.lsp`, and `Special_selections.lsp` contain the strongest route-geometry ideas. These can inform clean-room implementations for route segmentation, point-at-distance callout spacing, 90-degree bend detection, and sheet-aware placement checks.

| File | Relevant hits | Uses | Risk | Notes |
|---|---|---|---|---|
| raw_lsp/gc_MathGeom.lsp | polyline splitting, intersection, block handling, selection filtering, bounding boxes, sort/draw order | vla-, vlax-, block/insert/attributes | low | Polyline or curve geometry helper |
| raw_lsp/Obj2wipeout.lsp | text background mask, polyline splitting, point along curve, selection filtering, layer utilities | entmake, vla-, vlax-, ssget, vlax-curve-getPointAtDist, wipeout | high | Command routine: OB2WO |
| raw_lsp/Cadre_Masque.lsp | text background mask, polyline splitting, selection filtering, collision/placement helpers, sort/draw order | command, entmake, entmakex, vla-, vlax-, ssget, mtext, text frame, wipeout, dictionaries/xdata | medium | Command routine: CT, MT |
| raw_lsp/Special_selections.lsp | polyline splitting, point along curve, block handling, selection filtering | vla-, vlax-, ssget, vlax-curve-getPointAtDist, text frame, block/insert/attributes | medium | Command routine: INV_SEL, SSATT, SSC |
| extracted/TotalArea/TotalArea.lsp | polyline splitting, block handling, selection filtering, layer utilities, sort/draw order | vla-, vlax-, ssget, block/insert/attributes | high | Command routine: AREABOX, AREACONV, AREAEDIT |
| extracted/TotalPerim/TotalPerim.lsp | polyline splitting, block handling, selection filtering, layer utilities, sort/draw order | vla-, vlax-, ssget, block/insert/attributes | high | Command routine: PERIMBOX, PERIMCONV, PERIMEDIT |
| raw_lsp/gc_AutomationHelpers.lsp | callout/mleader, arrow/leader creation, polyline splitting | vla-, vlax-, dictionaries/xdata | high | Leader/callout or annotation helper |
| raw_lsp/3dPolyFillet.lsp | polyline splitting, intersection, block handling | vla-, vlax-, block/insert/attributes | low | Command routine: 3DPOLYFILLET |
| raw_lsp/gc_List.lsp | polyline splitting, intersection, sort/draw order |  | high | Polyline or curve geometry helper |
| raw_lsp/AddVtx_DelVtx.LSP | polyline splitting, intersection, selection filtering | vla-, vlax-, ssget | medium | Command routine: ADDVTX, DELVTX |
| raw_lsp/PolySegments.lsp | polyline splitting, collision/placement helpers, layer utilities, sort/draw order | vla-, vlax-, vlax-curve-getClosestPointTo | high | Command routine: COPSEGS, OFSEGS |
| raw_lsp/gc_Sortents.lsp | block handling, collision/placement helpers, sort/draw order | vla-, vlax-, block/insert/attributes | low | Block or attribute helper |
| raw_lsp/Bsc_Med_Per_Tan.lsp | polyline splitting, intersection | entmakex, entmod, vla-, vlax- | medium | Command routine: BSC, MED, PER |
| raw_lsp/Arc2Seg.LSP | polyline splitting, selection filtering | entmake, entmod, ssget | medium | Command routine: ARC2SEG |
| raw_lsp/Fusion.lsp | polyline splitting, selection filtering | vla-, vlax-, ssget | medium | Command routine: FUSION, UPL |
| raw_lsp/Curve2pipe.lsp | polyline splitting, selection filtering | vla-, vlax-, ssget | high | Command routine: C2P, CURVE2PIPE |
| raw_lsp/Join3dPoly.lsp | polyline splitting, selection filtering | vla-, vlax-, ssget | high | Command routine: JOIN3DPOLY |
| raw_lsp/Dist.lsp | polyline splitting | vla-, vlax- | medium | Command routine: DIST |
| raw_lsp/Clean_poly.lsp | polyline splitting | entmod | medium | Command routine: CLEAN_POLY |
