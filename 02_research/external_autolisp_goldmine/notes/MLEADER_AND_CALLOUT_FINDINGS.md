# MLeader And Callout Findings

Static scan for MLeader creation, leader arrows, mtext/background mask, text frames, and wipeout-style text masks.

## Brightspeed read

The import has callout-adjacent material, but no drop-in Brightspeed fix. `gc_AutomationHelpers.lsp` is the only direct MLeader signal; `Cadre_Masque.lsp` and `Obj2wipeout.lsp` are more relevant for text masks and draw-order behavior. All should remain reference-only unless licensing is clarified and patterns are reimplemented cleanly.

| File | Relevant hits | Uses | Risk | Notes |
|---|---|---|---|---|
| raw_lsp/Obj2wipeout.lsp | text background mask, polyline splitting, point along curve, selection filtering, layer utilities | entmake, vla-, vlax-, ssget, vlax-curve-getPointAtDist, wipeout | high | Command routine: OB2WO |
| raw_lsp/Cadre_Masque.lsp | text background mask, polyline splitting, selection filtering, collision/placement helpers, sort/draw order | command, entmake, entmakex, vla-, vlax-, ssget, mtext, text frame, wipeout, dictionaries/xdata | medium | Command routine: CT, MT |
| raw_lsp/gc_AutomationHelpers.lsp | callout/mleader, arrow/leader creation, polyline splitting | vla-, vlax-, dictionaries/xdata | high | Leader/callout or annotation helper |
