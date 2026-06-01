;;; ============================================================
;;; bscleanvp.lsp - Legacy compatibility shim
;;;
;;; The active cleanup implementation is bsclean_border.lsp.
;;; This file intentionally contains no cleanup logic. It only redirects
;;; old APPLOAD habits to the new, simpler two-command workflow:
;;;   BSCLEANRECT -> draw cleanup rectangle
;;;   BSCLEAN     -> clean inside limit but outside BORDER rectangles
;;; ============================================================

(defun bscvp-load-clean-border ( / here target)
  (setq here
    (cond
      ((and (boundp '*bs-toolkit-dir*) *bs-toolkit-dir*) *bs-toolkit-dir*)
      ((findfile "bscleanvp.lsp") (vl-filename-directory (findfile "bscleanvp.lsp")))
      (T nil)))
  (if here
    (progn
      (setq target (strcat here "\\bsclean_border.lsp"))
      (if (findfile target)
        (load target)
        (princ "\n[BSCLEANVP] Missing bsclean_border.lsp in the same folder.")))
    (princ "\n[BSCLEANVP] Could not locate toolkit folder."))
  (princ)
)

(bscvp-load-clean-border)
(princ)
