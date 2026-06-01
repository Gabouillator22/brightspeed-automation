# /new-lisp

Create a new AutoLISP command file following the project conventions.

## Usage
```
/new-lisp <command-name>
```

## What this does
1. Creates `05_toolkit/lisp/bs<command-name>.lsp` with the standard header, `*error*` handler, UNDO bracket, and a stub `c:BS<COMMAND-NAME>` function.
2. Adds `(bs-load-file "bs<command-name>.lsp")` to the end of `bs_loader.lsp`.
3. Updates `05_toolkit/lisp/AGENTS.md` file inventory table.
4. Prints the command name and the expected label/layer behavior to confirm before writing.

## Template
```lisp
;;; ============================================================
;;; BS<NAME> - [brief description]
;;;
;;; Commands:
;;;   BS<NAME> - [what it does]
;;;
;;; Depends on: bs_helpers.lsp (loaded by bs_loader.lsp)
;;; AutoCAD Map 3D 2027
;;; ============================================================

(vl-load-com)

(defun c:BS<NAME> ( / *error* env)
  (defun *error* (msg)
    (command "_.UNDO" "_END")
    (bsrd-restore-env env)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\n[BS<NAME>] Error: " msg)))
    (princ))
  (setq env (bsrd-save-env))
  (bsrd-setup)
  (command "_.UNDO" "_BEGIN")

  ;; TODO: implement

  (command "_.UNDO" "_END")
  (bsrd-restore-env env)
  (princ))

(princ "\n[BS<NAME>] Loaded. Type BS<NAME> to run.")
(princ)
```

## Delegate to
`lisp-author` agent for implementation.
