# AutoLISP Rules

These rules apply to all work in `05_toolkit/lisp/`.

## Naming
- File: `bs<command>.lsp` (lowercase, no underscores except `bs_loader.lsp` and `bs_helpers.lsp`).
- Public commands: `c:BSCOMMANDNAME` (uppercase, no hyphens except legacy `BSFILLET-ALL`).
- Helper functions: `bs-helper-name` (hyphenated, `bs-` prefix).
- Private helpers within a file: `bsXX-private-name` (two-letter file prefix, e.g., `bsrd-` for bsrowdims).

## Required structure in every command file
```lisp
(vl-load-com)                        ; if vla-/vlax- used

;;; header block with file description and command list

(defun c:BSCOMMAND ( / *error* env [other-locals])
  (defun *error* (msg)
    (command "_.UNDO" "_END")
    (bsrd-restore-env env)           ; or manual setvar restores
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\n[BSCOMMAND] Error: " msg)))
    (princ))
  (setq env (bsrd-save-env))
  (command "_.UNDO" "_BEGIN")
  ;; ... main logic ...
  (command "_.UNDO" "_END")
  (bsrd-restore-env env)
  (princ))

(princ "\n[BSCOMMAND] Loaded. Type BSCOMMAND to run.")
(princ)
```

## Entity creation rules
- Use `entmake`/`entmakex` over `command` whenever possible (faster, no prompt interference).
- Layer from layer table — never `(cons 62 N)`.
- Global width on fiber polylines: `(cons 43 0.5)`.
- LINETYPE GENERATION on fiber polylines: `(cons 70 128)` (or OR with existing flags).

## ssget rules
- Always prefix mode strings with `_`: `"_X"`, `"_C"`, `"_W"`.
- Balance all logical operators: every `"<OR"` needs `"OR>"`.
- Release selection sets after use: `(setq ss nil)`.

## Performance
- Never use `(command ...)` in loops expected to run >10 times. Use `entmake` or `vlax-` calls.
- Use `command-s` over `command` in automated code (no prompt display).

## Forbidden
- Hardcoded absolute paths anywhere.
- `(cons 62 N)` in entmake/entmod (manual color assignment).
- Writing `.dwg` files via script (AutoCAD manages DWG).
- Embedding secrets or tokens.
