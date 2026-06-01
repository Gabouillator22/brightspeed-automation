;;; ============================================================
;;; BSFILLET-ALL v2 - Fillet all ROW/EOP corners (R = 25')
;;;
;;; Rewritten from scratch.  Previous version had two structural bugs:
;;;   1. Local defun inside c:BSFILLET-ALL doesn't survive all AutoLISP
;;;      environments (re-defined inside a function body at call-time).
;;;   2. FILLET command was passed entity names instead of pick points.
;;;
;;; Algorithm:
;;;   1. Collect all entities on layers ROW and ROADS-paved.
;;;   2. For every unique pair, call IntersectWith(acExtendNone=0) to find
;;;      REAL intersections only (no virtual / extrapolated).
;;;   3. Require the intersection to lie within 5' of at least one endpoint
;;;      of either entity — this is a corner, not a mid-line crossing.
;;;   4. Apply FILLET using the midpoint of each entity as pick point.
;;;      Midpoints are on the "body" side, which is the part to KEEP.
;;;      AutoCAD trims from the corner toward the pick side.
;;;
;;; Radius : 25' (hardcoded, matches manual workflow F R 25)
;;; Layers : ROW, ROADS-paved
;;; Safety : Uses AutoCAD FILLET command — fully undo-able.
;;; ============================================================

(defun c:BSFILLET-ALL ( / old-cmdecho old-layer
                          row-ss eop-ss all-ents
                          i j ea eb
                          ipt pick-a pick-b
                          fillet-count skip-count no-ipt-count
                          fillet-r ep-tol)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (setq fillet-r 25.0)
  (setq ep-tol   5.0)   ; intersection must be within 5' of an endpoint

  (princ "\n[BSFILLET-ALL] Collecting ROW and ROADS-paved entities...")

  (setq row-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROW"))))
  (setq eop-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROADS-paved"))))

  (if (not (or row-ss eop-ss))
    (progn
      (princ "\n[BSFILLET-ALL] No ROW or ROADS-paved entities found. Aborting.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      ;; Build flat list
      (setq all-ents nil)
      (if row-ss
        (progn (setq i 0)
          (while (< i (sslength row-ss))
            (setq all-ents (append all-ents (list (ssname row-ss i))))
            (setq i (1+ i)))))
      (if eop-ss
        (progn (setq i 0)
          (while (< i (sslength eop-ss))
            (setq all-ents (append all-ents (list (ssname eop-ss i))))
            (setq i (1+ i)))))

      (princ (strcat "\n[BSFILLET-ALL] " (itoa (length all-ents))
        " entities. Setting fillet radius R=" (rtos fillet-r 2 1) "'..."))

      ;; Set radius once before the loop
      (setvar "CMDECHO" 0)
      (command "_.FILLET" "R" (rtos fillet-r 2 1) "")

      (setq fillet-count  0
            skip-count    0
            no-ipt-count  0)

      ;; Check every unique pair
      (setq i 0)
      (while (< i (1- (length all-ents)))
        (setq ea (nth i all-ents))
        (setq j (1+ i))
        (while (< j (length all-ents))
          (setq eb (nth j all-ents))

          ;; Real intersection only (acExtendNone = 0)
          (setq ipt (bs-intersect-first ea eb 0))

          (cond
            ;; No real intersection → skip
            ((not ipt)
              (setq no-ipt-count (1+ no-ipt-count)))

            ;; Intersection must be near at least one endpoint (corner, not crossing)
            ((not (or (bs-near-endpoint-p ipt ea ep-tol)
                      (bs-near-endpoint-p ipt eb ep-tol)))
              (setq skip-count (1+ skip-count)))

            ;; Apply fillet using midpoints as pick points
            (T
              (setq pick-a (bs-ent-midpt ea))
              (setq pick-b (bs-ent-midpt eb))
              (if (and pick-a pick-b)
                (progn
                  (command "_.FILLET" pick-a pick-b)
                  (setq fillet-count (1+ fillet-count)))
                (setq skip-count (1+ skip-count)))))

          (setq j (1+ j)))
        (setq i (1+ i)))

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n")
      (princ "\n[BSFILLET-ALL] ======== RESULTS ========")
      (princ (strcat "\n  Fillets applied        : " (itoa fillet-count)))
      (princ (strcat "\n  Pairs no intersection  : " (itoa no-ipt-count)))
      (princ (strcat "\n  Pairs skipped (non-corner): " (itoa skip-count)))
      (princ (strcat "\n  Radius                 : " (rtos fillet-r 2 1) "'"))
      (princ "\n  All changes undo-able with Ctrl+Z")
      (princ "\n[BSFILLET-ALL] =========================")
    )
  )
  (princ)
)

(princ "\n[BSFILLET-ALL] Loaded. Type BSFILLET-ALL to fillet all ROW/EOP corners.")
(princ)
