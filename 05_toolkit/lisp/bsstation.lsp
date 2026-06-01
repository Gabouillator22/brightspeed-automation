;;; ============================================================
;;; BSSTATION - Auto-station HH, borepits, and poles
;;;
;;; Scans all INSERT (block) entities in the drawing.
;;; Matches block names containing any of these substrings
;;; (case-insensitive):  HANDHOLE  HH  BORE  BOREPIT  POLE
;;;
;;; For each matched block:
;;;   1. Find the nearest fiber polyline (BURIED FIBER IN DUCT or AERIAL FIBER).
;;;   2. Get the distance from the fiber's start to the closest point on
;;;      the fiber — this is the station value in feet.
;;;   3. Place a TEXT entity "STA XX+XX.X" at the block insertion point,
;;;      offset 5' to the right of the block.
;;;
;;; Note on station 0+00:
;;;   Station is measured from the START vertex of the nearest fiber line.
;;;   If fiber direction is reversed vs field convention, run PEDIT -> Reverse
;;;   on the fiber polyline before running BSSTATION.
;;;
;;; Text height  : 5.0
;;; Layer        : STATIONING
;;; Safety       : Adds TEXT entities only. No deletes. Undo-safe.
;;; ============================================================

(defun c:BSSTATION ( / old-cmdecho old-layer
                       ss-blocks ss-fiber
                       i block-ent block-name bname-up ins-pt
                       nearest-fiber closest-pt dist-along
                       station-txt text-pt
                       placed-count skip-count keywords)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "STATIONING" 7)

  ;; Keywords that identify fiber-related structure blocks
  (setq keywords '("HANDHOLE" "HH" "BORE" "BOREPIT" "POLE"))

  (princ "\n[BSSTATION] Scanning blocks for HH/bore pit/pole matches...")

  ;; Collect all INSERT entities
  (setq ss-blocks (ssget "X" '((0 . "INSERT"))))

  ;; Collect all fiber lines as reference for station measurement
  (setq ss-fiber
    (ssget "X"
      '((0 . "LWPOLYLINE,POLYLINE")
        (-4 . "<OR")
          (8 . "BURIED FIBER IN DUCT")
          (8 . "AERIAL FIBER")
        (-4 . "OR>"))))

  (if (not ss-blocks)
    (progn
      (princ "\n[BSSTATION] No block inserts found in drawing. Aborting.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (if (not ss-fiber)
        (princ "\n[BSSTATION] WARNING: No fiber polylines found. Stations will show 0."))

      (setq placed-count 0 skip-count 0)

      (setq i 0)
      (while (< i (sslength ss-blocks))
        (setq block-ent  (ssname ss-blocks i))
        (setq block-name (cdr (assoc 2 (entget block-ent))))
        (setq bname-up   (strcase block-name))

        ;; Check if block name contains any keyword (substring match)
        (if (bsst-matches-any-keyword bname-up keywords)
          (progn
            (setq ins-pt (cdr (assoc 10 (entget block-ent))))
            ;; Ensure z=0
            (setq ins-pt (list (car ins-pt) (cadr ins-pt) 0.0))

            ;; Find station along nearest fiber
            (if ss-fiber
              (progn
                (setq nearest-fiber (bs-nearest-ent-in-ss ins-pt ss-fiber))
                (setq dist-along (bsst-dist-along-fiber ins-pt nearest-fiber))
              )
              (setq dist-along 0.0)
            )

            (setq station-txt (bs-format-station dist-along))

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

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n")
      (princ "\n[BSSTATION] ======== RESULTS ========")
      (princ (strcat "\n  Station labels placed : " (itoa placed-count)))
      (princ (strcat "\n  Blocks skipped        : " (itoa skip-count)))
      (princ "\n  Layer: STATIONING")
      (princ "\n  Station 0+00 = start vertex of nearest fiber line.")
      (princ "\n  Use PEDIT -> Reverse on fiber if stationing runs backward.")
      (princ "\n[BSSTATION] =========================")
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bsst-matches-any-keyword (block-name-upper keywords / kw match)
  ;; T if block-name-upper contains any keyword string as a substring.
  (setq match nil)
  (foreach kw keywords
    (if (vl-string-search kw block-name-upper)
      (setq match T)))
  match)

(defun bsst-dist-along-fiber (pt fiber-ent / cp dist-val)
  ;; Get arc-length distance from start of fiber to the closest point on fiber to pt.
  ;; Returns 0.0 on any failure.
  (setq cp
    (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list fiber-ent pt)))
  (if (vl-catch-all-error-p cp)
    0.0
    (progn
      (setq dist-val
        (vl-catch-all-apply 'vlax-curve-getDistAtPoint (list fiber-ent cp)))
      (if (vl-catch-all-error-p dist-val) 0.0 dist-val))))

(princ "\n[BSSTATION] Loaded. Type BSSTATION to auto-station HH/borepits/poles.")
(princ)
