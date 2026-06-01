# AutoLISP Debugger — Skill Reference

## Error decoder
| Error string | Root cause | Fix |
|---|---|---|
| `bad argument type` | Wrong type to function | Check `cdr/assoc`; use `vlax-3d-point` for COM coords |
| `no function definition` | `vl-load-com` missing or typo | Add `(vl-load-com)` at file top; check spelling |
| `too many arguments` | Extra token in `command` call | Count args against signature |
| `Automation Error` | COM exception | Wrap in `vl-catch-all-apply` |
| `null pointer` | Stale entity name | Re-fetch with `entlast`/`ssget` |
| `Function cancelled` | User hit Escape | Filter in `*error*` — not a real error |
| `divide by zero` | Unguarded division | Guard denominator |
| `bad list syntax` | Malformed DXF filter — `"<OR"` not closed | Balance all logical operators |

## Required error handler pattern
```lisp
(defun c:MYCOMMAND ( / *error* env)
  (defun *error* (msg)
    (command "_.UNDO" "_END")
    (bsrd-restore-env env)          ; or inline setvar restores
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\n[MYCOMMAND] Error: " msg)))
    (princ))
  (setq env (bsrd-save-env))
  (command "_.UNDO" "_BEGIN")
  ;; ... main logic ...
  (command "_.UNDO" "_END")
  (bsrd-restore-env env)
  (princ))
```

## DXF group codes (common)
| Code | Meaning |
|---|---|
| 0 | Entity type string |
| 1 | Primary text string |
| 2 | Block name / attribute tag |
| 8 | Layer name |
| 10 | Start point / vertex (X Y Z) |
| 11 | End point |
| 40 | Text height / radius |
| 43 | Constant width (LWPOLYLINE) |
| 62 | Color number (avoid — use BYLAYER) |
| 70 | Flags integer (70+128 = PLINEGEN on LWPOLYLINE) |
| 90 | Integer count |
| 100 | Subclass marker |

## ssget filter rules
- Logical operators must be balanced: `"<OR"` → `"OR>"`, `"<AND"` → `"AND>"`.
- Mode strings need `_` prefix for non-English AutoCAD: `"_X"` not `"X"`.
- `ssget "_X"` = all entities in drawing; `"_C"` = crossing window.
- String comparison on numeric code is wrong: `(cons 70 "1")` → `(cons 70 1)`.

## entget / entmod patterns
```lisp
; WRONG — returns dotted pair
(setq radius (assoc 40 elist))

; RIGHT
(setq radius (cdr (assoc 40 elist)))

; Modify and commit
(setq elist (subst (cons 8 "NEW-LAYER") (assoc 8 elist) elist))
(entmod elist)
(entupd ent)   ; required for complex entities
```

## command vs command-s
- `command` — interactive, shows prompts, can use `PAUSE` token.
- `command-s` — silent, no prompts, no `PAUSE`. Use in loops.
- Never use `command-s` with `PAUSE` — it crashes.

## COM / vlax patterns
- Always call `(vl-load-com)` at file top before any `vla-`/`vlax-` call.
- Pass points as `(vlax-3d-point x y z)` to VLA methods, not raw lists.
- Wrap unstable COM calls in `vl-catch-all-apply`.
- Unpack variant results: `(vlax-safearray->list (vlax-variant-value result))`.

## UNDO grouping
```lisp
(command "_.UNDO" "_BEGIN")
;; all entity changes here
(command "_.UNDO" "_END")
```
This makes the entire operation a single Ctrl+Z.
