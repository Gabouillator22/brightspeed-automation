;;; ============================================================
;;; BSCALLOUTS_AUTO - Forced callout workflow launcher
;;;
;;; Commands:
;;;   BSCALLOUTS-RUN        - plan and place every required callout
;;;   BSCALLOUTS-AUDIT      - plan/report only, no final callouts
;;;   BSCALLOUTS-CLEAN      - remove temporary callout review/guide layers
;;;   BSCALLOUTS-STRUCTURES - forced run for structure labels only
;;;   BSCALLOUTS-BURIED     - forced run for buried route labels only
;;;   BSCALLOUTS-AERIAL     - forced run for aerial route labels only
;;;
;;; Depends on: Python script 05_toolkit/python/bscallouts_forced.py
;;; AutoCAD Map 3D 2027
;;; ============================================================

(vl-load-com)

(defun bscf-norm-dir (dir /)
  (if dir
    (vl-string-right-trim "\\/" dir)
    nil))

(defun bscf-lisp-dir ( /)
  (bscf-norm-dir
    (cond
      ((and (boundp '*bs-toolkit-dir*) *bs-toolkit-dir*) *bs-toolkit-dir*)
      ((findfile "bscallouts_auto.lsp") (vl-filename-directory (findfile "bscallouts_auto.lsp")))
      ((findfile "bs_loader.lsp") (vl-filename-directory (findfile "bs_loader.lsp")))
      ((findfile "bs_helpers.lsp") (vl-filename-directory (findfile "bs_helpers.lsp")))
      (T nil))))

(defun bscf-toolkit-root ( / dir)
  (setq dir (bscf-lisp-dir))
  (if dir
    (vl-filename-directory dir)
    nil))

(defun bscf-python-script ( / root)
  (setq root (bscf-toolkit-root))
  (if root
    (strcat root "\\python\\bscallouts_forced.py")
    nil))

(defun bscf-repo-root ( / root)
  (setq root (bscf-toolkit-root))
  (if root
    (vl-filename-directory root)
    nil))

(defun bscf-python-exe ( / repo venv)
  (setq repo (bscf-repo-root))
  (setq venv (if repo (strcat repo "\\.venv\\Scripts\\python.exe") nil))
  (if (and venv (findfile venv))
    venv
    "python"))

(defun bscf-quote (value /)
  (strcat "\"" value "\""))

(defun bscf-run-python (args / script py-dir pyexe cmd)
  (setq script (bscf-python-script))
  (if (not (and script (findfile script)))
    (princ "\n[BSCALLOUTS] Missing Python script: 05_toolkit/python/bscallouts_forced.py")
    (progn
      (setq py-dir (vl-filename-directory script))
      (setq pyexe (bscf-python-exe))
      (setq cmd
        (strcat
          "/c cd /d " (bscf-quote py-dir)
          " && " (bscf-quote pyexe) " " (bscf-quote script)
          " --yes " args
          " & pause"))
      (princ "\n[BSCALLOUTS] Launching forced callout planner in a console window.")
      (princ "\n[BSCALLOUTS] Keep AutoCAD open. The planner will connect back to this drawing.")
      (startapp "cmd.exe" cmd)))
  (princ))

(defun bscf-clean-layer (layer-name / ss i ent count)
  (setq count 0)
  (setq ss (ssget "_X" (list (cons 8 layer-name))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if ent
          (progn
            (entdel ent)
            (setq count (1+ count))))
        (setq i (1+ i)))))
  count)

(defun c:BSCALLOUTS-RUN ( /)
  (bscf-run-python "--run")
  (princ))

(defun c:BSCALLOUTS-FORCED-RUN ( /)
  (c:BSCALLOUTS-RUN)
  (princ))

(defun c:BSCALLOUTS-AUDIT ( /)
  (bscf-run-python "--audit-only")
  (princ))

(defun c:BSCALLOUTS-FORCED-AUDIT ( /)
  (c:BSCALLOUTS-AUDIT)
  (princ))

(defun c:BSCALLOUTS-STRUCTURES ( /)
  (bscf-run-python "--run --families structure")
  (princ))

(defun c:BSCALLOUTS-BURIED ( /)
  (bscf-run-python "--run --families buried")
  (princ))

(defun c:BSCALLOUTS-AERIAL ( /)
  (bscf-run-python "--run --families aerial")
  (princ))

(defun c:BSCALLOUTS-CLEAN ( / *error* old-cmdecho removed)
  (setq old-cmdecho (getvar "CMDECHO"))
  (defun *error* (msg)
    (if (= 8 (logand 8 (getvar "UNDOCTL")))
      (command "_.UNDO" "_E"))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if (and msg (/= (strcase msg) "*CANCEL*"))
      (princ (strcat "\n[BSCALLOUTS-CLEAN] ERROR: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (setq removed 0)
  (foreach layer-name
    '("BS-CALLOUT-GUIDES"
      "BS-CALLOUT-ANCHORS"
      "BS-CALLOUT-CANDIDATES"
      "BS-CALLOUT-COLLISION"
      "BS-CALLOUT-REVIEW"
      "BS-CALLOUT-MASKS")
    (setq removed (+ removed (bscf-clean-layer layer-name))))
  (command "_.UNDO" "_E")
  (setvar "CMDECHO" old-cmdecho)
  (princ (strcat "\n[BSCALLOUTS-CLEAN] Removed " (itoa removed) " temporary callout guide/review object(s)."))
  (princ))

(defun c:BSCALLOUTS-FORCED-CLEAN ( /)
  (c:BSCALLOUTS-CLEAN)
  (princ))

(princ "\n[BSCALLOUTS_AUTO] Loaded forced workflow commands.")
(princ "\n  BSCALLOUTS-RUN        -> plan and place every required callout")
(princ "\n  BSCALLOUTS-AUDIT      -> plan/report only")
(princ "\n  BSCALLOUTS-CLEAN      -> remove temporary callout guide/review layers")
(princ)
