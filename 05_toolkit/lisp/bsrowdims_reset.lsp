;;; ============================================================
;;; bsrowdims_reset.lsp
;;;
;;; Purpose:
;;;   Force-clear resident BSROWDIMS command/helper symbols from the
;;;   current AutoCAD session, then load the current bsrowdims.lsp file.
;;;
;;; Usage:
;;;   APPLOAD this file, then run BSROWDIMS-RESET
;;; ============================================================

(vl-load-com)

(defun bsrdr-clear-symbol (sym /)
  (if (and sym (boundp sym))
    (set sym nil))
  (princ))

(defun c:BSROWDIMS-RESET ( / here target syms)
  (setq syms
    '(
      c:BSROWDIMS c:BSROWDIMS1 c:BSROWDIMSC c:BSROWDIMS-DIAG
      c:BSDIMS c:BSDIM1 c:BSDIMC c:BSDIAG c:BSROWDIMS-SESSIONDIAG
      bsrd-build-tag
      bsrd-save-env bsrd-restore-env bsrd-setup
      bsrd-undo-begin bsrd-undo-end bsrd-yesno
      bsrd-centerline-layers bsrd-row-layers bsrd-eop-layers
      bsrd-fiber-layers bsrd-curve-types bsrd-guide-layer
      bsrd-measure-tolerance
    ))
  (foreach sym syms
    (bsrdr-clear-symbol sym))
  (setq here (getvar "DWGPREFIX"))
  (setq target (findfile "bsrowdims.lsp"))
  (if (null target)
    (progn
      (princ "\n[BSROWDIMS-RESET] Could not find bsrowdims.lsp on support path.")
      (princ "\n[BSROWDIMS-RESET] APPLOAD bsrowdims.lsp directly after running this reset."))
    (progn
      (princ (strcat "\n[BSROWDIMS-RESET] Loading " target))
      (load target)
      (princ "\n[BSROWDIMS-RESET] Reload complete.")))
  (princ))

(princ "\n[BSROWDIMS-RESET] Loaded. Run BSROWDIMS-RESET to clear resident rowdims symbols and reload bsrowdims.lsp.")
(princ)
