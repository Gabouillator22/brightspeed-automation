;;; ============================================================
;;; BSSTATION - Auto-station HH, bore pits, and POLE/RISER only
;;;
;;; Scans INSERT (block) entities in the drawing.
;;; Matches block names containing any of these substrings
;;; (case-insensitive):  HANDHOLE  HH  BORE  BOREPIT  POLE + RISER
;;;
;;; For each matched block:
;;;   1. Pick the correct technology chain.
;;;      - handhole/bore pit -> buried fiber
;;;      - pole with riser    -> aerial fiber
;;;   2. Compute cumulative station along that chain.
;;;   3. Place a TEXT entity "STA XX+XX.X" at the block insertion point,
;;;      offset 5' to the right of the block.
;;;
;;; Note on station 0+00:
;;;   Station is measured from the START vertex of the selected technology
;;;   chain. Buried and aerial stationing reset independently.
;;;
;;; Text height  : 5.0
;;; Layer        : STATIONING
;;; Safety       : Adds TEXT entities only. No deletes. Undo-safe.
;;; ============================================================

(vl-load-com)

(defun c:BSSTATION ( / *error* old-cmdecho old-layer
                       ss-blocks
                       i block-ent block-name bname-up ins-pt
                       structure-kind curves dist-along
                       station-txt text-pt
                       placed-count skip-count)

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))

  (defun *error* (msg)
    (if (= 8 (logand 8 (getvar "UNDOCTL")))
      (command "_.UNDO" "_E"))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-layer (setvar "CLAYER" old-layer))
    (if (and msg (/= (strcase msg) "*CANCEL*"))
      (princ (strcat "\n[BSSTATION] ERROR: " msg)))
    (princ))

  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")

  (bs-ensure-layer "STATIONING" 7)

  (princ "\n[BSSTATION] Scanning blocks for HH/bore pit/POLE-RISER matches...")

  ;; Collect all INSERT entities
  (setq ss-blocks (ssget "X" '((0 . "INSERT"))))

  (if (not ss-blocks)
    (progn
      (princ "\n[BSSTATION] No block inserts found in drawing. Aborting.")
      (command "_.UNDO" "_E")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (setq placed-count 0 skip-count 0)
      (setq i 0)
      (while (< i (sslength ss-blocks))
        (setq block-ent  (ssname ss-blocks i))
        (setq block-name (cdr (assoc 2 (entget block-ent))))
        (setq bname-up   (strcase block-name))

        ;; Only station handholes, bore pits, and poles that explicitly have risers.
        (setq structure-kind (bsst-structure-kind bname-up))
        (if structure-kind
          (progn
            (setq ins-pt (cdr (assoc 10 (entget block-ent))))
            ;; Ensure z=0
            (setq ins-pt (list (car ins-pt) (cadr ins-pt) 0.0))

            ;; Use the correct technology chain so buried and aerial stations reset independently.
            (setq curves (bsst-curves-for-structure-kind structure-kind))
            (setq dist-along
              (if curves
                (bsca-cumulative-station ins-pt curves)
                0.0))

            ;; Use the same whole-foot station formatter as the callout system.
            (setq station-txt (bsca-format-sta dist-along))

            ;; Place text 5' to the right of block insertion
            (setq text-pt
              (list (+ (car ins-pt) 5.0)
                    (+ (cadr ins-pt) 5.0)
                    0.0))

            (bs-make-text text-pt 5.0 "STATIONING" station-txt)
            (princ (strcat "\n[BSSTATION] " block-name " -> " station-txt))
            (setq placed-count (1+ placed-count))
          )
          (setq skip-count (1+ skip-count))
        )
        (setq i (1+ i))
      )

      (command "_.UNDO" "_E")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n")
      (princ "\n[BSSTATION] ======== RESULTS ========")
      (princ (strcat "\n  Station labels placed : " (itoa placed-count)))
      (princ (strcat "\n  Blocks skipped        : " (itoa skip-count)))
      (princ "\n  Layer: STATIONING")
      (princ "\n  Station 0+00 = start vertex of the selected technology chain.")
      (princ "\n  Use PEDIT -> Reverse on fiber if stationing runs backward.")
      (princ "\n[BSSTATION] =========================")
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bsst-structure-kind (block-name-upper / )
  ;; Returns "BUR" for handholes/bore pits, "AIR" for POLE/RISER, else nil.
  (cond
    ((or (vl-string-search "HANDHOLE" block-name-upper)
         (vl-string-search "BORE" block-name-upper)
         (vl-string-search "BOREPIT" block-name-upper)
         (and (vl-string-search "HH" block-name-upper)
              (not (vl-string-search "POLE" block-name-upper))))
      "BUR")
    ((and (vl-string-search "POLE" block-name-upper)
          (vl-string-search "RISER" block-name-upper))
      "AIR")
    (T nil)))

(defun bsst-curves-for-structure-kind (kind / )
  ;; Use the correct technology chain so stationing resets between buried and aerial.
  (cond
    ((= kind "BUR")
      (bsca-curves-on-layers (list "BURIED FIBER IN DUCT")))
    ((= kind "AIR")
      (bsca-curves-on-layers (list "AERIAL FIBER" "ELASH")))
    (T nil)))

(princ "\n[BSSTATION] Loaded. Type BSSTATION to auto-station HH/bore pits/POLE-RISER.")
(princ)
