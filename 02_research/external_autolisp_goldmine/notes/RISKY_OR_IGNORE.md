# Risky Or Ignore

Treat files without explicit permissive licensing as reference-only. Do not load compiled or destructive routines into AutoCAD.

| File | Risk level | Flags | License/readme signal | Recommendation |
|---|---|---|---|---|
| extracted/Edit_bloc_3.5/Edit_bloc.VLX | high | compiled-only .vlx/.fas |  | Ignore/load never; license unclear |
| extracted/Edit_bloc_3.5/Edit_bloc_3.5.lsp | high | obfuscated code |  | Reference-only; inspect before reimplementation; license unclear |
| extracted/Edit_bloc_3.5/Edit_bloc_rep.lsp | high | erase/delete, hardcoded paths, destructive commands, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| extracted/Res_hel/Res_hel.VLX | high | compiled-only .vlx/.fas |  | Ignore/load never; license unclear |
| extracted/ssf/SSFilter.VLX | high | compiled-only .vlx/.fas |  | Ignore/load never; license unclear |
| extracted/SSMatch/Ssmatch.VLX | high | compiled-only .vlx/.fas |  | Ignore/load never; license unclear |
| extracted/TotalArea/TotalArea.lsp | high | erase/delete, obfuscated code, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| extracted/TotalPerim/TotalPerim.lsp | high | erase/delete, obfuscated code, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Curve2pipe.lsp | high | erase/delete, destructive commands, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Dialog.lsp | high | erase/delete, obfuscated code, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/gc_AutomationHelpers.lsp | high | obfuscated code |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/gc_List.lsp | high | obfuscated code |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/gc_String.lsp | high | hardcoded paths, obfuscated code |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Increment.lsp | high | erase/delete, save/saveas, obfuscated code, destructive commands, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/InsTopo.lsp | high | erase/delete, obfuscated code, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Join3dPoly.lsp | high | erase/delete, destructive commands, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Obj2wipeout.lsp | high | erase/delete, destructive commands, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/PolySegments.lsp | high | erase/delete, global setvar without restore, destructive commands, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/RegExp.lsp | high | hardcoded paths |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Vues_Pav_.lsp | high | obfuscated code |  | Reference-only; inspect before reimplementation; license unclear |
| extracted/Res_hel/Res_hel.lsp | medium | missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| extracted/ssf/ssfilter.LSP | medium | missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| extracted/SSMatch/ssmatch.LSP | medium | missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/AddVtx_DelVtx.LSP | medium | erase/delete, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Arc2Seg.LSP | medium | erase/delete, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Arcedit.lsp | medium | erase/delete, global setvar without restore, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Bsc_Med_Per_Tan.lsp | medium | erase/delete |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Cadre_Masque.lsp | medium | global setvar without restore, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Clean_poly.lsp | medium | erase/delete, missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Dist.lsp | medium | missing error handler |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Fusion.lsp | medium | erase/delete, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/gc_Blocks.lsp | medium | erase/delete, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/gc_Dictionaries.lsp | medium | erase/delete |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/InsEdit.lsp | medium | erase/delete, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/LinkData.lsp | medium | erase/delete |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Soustrac.lsp | medium | erase/delete, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
| raw_lsp/Special_selections.lsp | medium | erase/delete, destructive commands |  | Reference-only; inspect before reimplementation; license unclear |
