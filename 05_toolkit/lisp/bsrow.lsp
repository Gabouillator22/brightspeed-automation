;;; ============================================================
;;; BSROW v5.1 - Auto-draw ROW, EOP, and TRAP lines
;;;
;;; FIX vs v5:
;;;   Bug 1: TRAP offset direction was wrong — used perp-left which
;;;          is near centerline, making it INWARD of the ROW line.
;;;          Fixed: outward direction = reflect cl-mid across each
;;;          ROW line midpoint, guaranteeing it's on the outside.
;;;   Bug 2: ROW-TRAP layer not explicitly turned ON after creation.
;;;          Fixed: layer is forced ON and THAWED after all lines placed.
;;;
;;; OFFSETS:
;;;   Centerline -> 30' each side        -> ROW (pink)
;;;   ROW -> 20' inward toward CL        -> EOP / ROADS-paved (black)
;;;   ROW -> 35' outward away from CL    -> TRAP / ROW-TRAP (cyan)
;;; ============================================================

(defun c:BSROW ( / old-cmdecho old-layer ss i ent ent-type
                   p-mid tangent perp-left perp-right
                   snap-before
                   new-row-1 new-row-2
                   new-eop-1 new-eop-2
                   new-trap-1 new-trap-2
                   cl-mid
                   row1-mid row2-mid
                   outward-1 outward-2)

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  ;; Ensure ROW-TRAP layer exists, ON, THAWED, color cyan (4)
  (bsrow-ensure-layer "ROW-TRAP" 4)

  (setq ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROAD-CENTERLINE"))))

  (if (not ss)
    (princ "\n[BSROW] No objects on ROAD-CENTERLINE layer. Aborting.")
    (progn
      (princ (strcat "\n[BSROW] Found " (itoa (sslength ss)) " centerline(s). Processing..."))

      (setq i 0)
      (while (< i (sslength ss))
        (setq ent      (ssname ss i))
        (setq ent-type (cdr (assoc 0 (entget ent))))

        ;; Centerline midpoint
        (setq p-mid
          (cond
            ((or (= ent-type "LWPOLYLINE") (= ent-type "POLYLINE"))
              (vlax-curve-getPointAtParam ent
                (/ (vlax-curve-getEndParam ent) 2.0)))
            ((= ent-type "LINE")
              (mapcar '(lambda (a b) (/ (+ a b) 2.0))
                (cdr (assoc 10 (entget ent)))
                (cdr (assoc 11 (entget ent)))))
          )
        )
        (setq cl-mid p-mid)

        ;; True perpendicular via tangent at midpoint
        (setq tangent
          (cond
            ((or (= ent-type "LWPOLYLINE") (= ent-type "POLYLINE"))
              (vlax-curve-getFirstDeriv ent
                (vlax-curve-getParamAtPoint ent p-mid)))
            ((= ent-type "LINE")
              (mapcar '-
                (cdr (assoc 11 (entget ent)))
                (cdr (assoc 10 (entget ent)))))
          )
        )

        ;; Perpendicular side points (guaranteed opposite sides)
        (setq perp-left
          (list (+ (car p-mid)  (* -1.0 (cadr tangent)))
                (+ (cadr p-mid) (* 1.0  (car tangent)))
                0.0))
        (setq perp-right
          (list (+ (car p-mid)  (* 1.0  (cadr tangent)))
                (+ (cadr p-mid) (* -1.0 (car tangent)))
                0.0))

        ;; ===== ROW LEFT (30') =====
        (setq snap-before (entlast))
        (command "_.OFFSET" 30.0 ent perp-left "")
        (setq new-row-1 (entlast))
        (if (equal new-row-1 snap-before)
          (progn
            (princ (strcat "\n[BSROW] WARNING: Left ROW failed on centerline #" (itoa (1+ i))))
            (setq new-row-1 nil))
          (bsrow-force-layer new-row-1 "ROW")
        )

        ;; ===== ROW RIGHT (30') =====
        (setq snap-before (entlast))
        (command "_.OFFSET" 30.0 ent perp-right "")
        (setq new-row-2 (entlast))
        (if (equal new-row-2 snap-before)
          (progn
            (princ (strcat "\n[BSROW] WARNING: Right ROW failed on centerline #" (itoa (1+ i))))
            (setq new-row-2 nil))
          (bsrow-force-layer new-row-2 "ROW")
        )

        ;; ===== EOP LEFT (20' inward from ROW-left toward centerline) =====
        (if new-row-1
          (progn
            (setq snap-before (entlast))
            (command "_.OFFSET" 20.0 new-row-1 cl-mid "")
            (setq new-eop-1 (entlast))
            (if (equal new-eop-1 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Left EOP failed on centerline #" (itoa (1+ i))))
              (bsrow-force-layer new-eop-1 "ROADS-paved")
            )
          )
        )

        ;; ===== EOP RIGHT (20' inward from ROW-right toward centerline) =====
        (if new-row-2
          (progn
            (setq snap-before (entlast))
            (command "_.OFFSET" 20.0 new-row-2 cl-mid "")
            (setq new-eop-2 (entlast))
            (if (equal new-eop-2 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Right EOP failed on centerline #" (itoa (1+ i))))
              (bsrow-force-layer new-eop-2 "ROADS-paved")
            )
          )
        )

        ;; ===== TRAP LEFT (35' outward from ROW-left) =====
        ;; FIX: outward direction = reflect cl-mid across ROW-left midpoint
        ;; This guarantees the pick point is on the OUTSIDE of the ROW line
        (if new-row-1
          (progn
            ;; Midpoint of the new ROW-left line
            (setq row1-mid
              (vlax-curve-getPointAtParam new-row-1
                (/ (vlax-curve-getEndParam new-row-1) 2.0)))
            ;; Reflect cl-mid across row1-mid -> point on outward side
            (setq outward-1
              (list (- (* 2.0 (car  row1-mid)) (car  cl-mid))
                    (- (* 2.0 (cadr row1-mid)) (cadr cl-mid))
                    0.0))
            (setq snap-before (entlast))
            (command "_.OFFSET" 35.0 new-row-1 outward-1 "")
            (setq new-trap-1 (entlast))
            (if (equal new-trap-1 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Left TRAP failed on centerline #" (itoa (1+ i))))
              (bsrow-force-layer new-trap-1 "ROW-TRAP")
            )
          )
        )

        ;; ===== TRAP RIGHT (35' outward from ROW-right) =====
        (if new-row-2
          (progn
            (setq row2-mid
              (vlax-curve-getPointAtParam new-row-2
                (/ (vlax-curve-getEndParam new-row-2) 2.0)))
            (setq outward-2
              (list (- (* 2.0 (car  row2-mid)) (car  cl-mid))
                    (- (* 2.0 (cadr row2-mid)) (cadr cl-mid))
                    0.0))
            (setq snap-before (entlast))
            (command "_.OFFSET" 35.0 new-row-2 outward-2 "")
            (setq new-trap-2 (entlast))
            (if (equal new-trap-2 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Right TRAP failed on centerline #" (itoa (1+ i))))
              (bsrow-force-layer new-trap-2 "ROW-TRAP")
            )
          )
        )

        (setq i (1+ i))
      )

      ;; FIX: explicitly turn ON and THAW ROW-TRAP after all lines placed
      (command "_.LAYER" "ON" "ROW-TRAP" "T" "ROW-TRAP" "")

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n[BSROW] Done.")
      (princ "\n[BSROW] ROW-TRAP lines visible on layer ROW-TRAP (cyan).")
      (princ "\n[BSROW] Run BSPARCELS -> pick a ROW line to clean property lines.")
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Force entity to a specific layer
;;; ---------------------------------------------------------------
(defun bsrow-force-layer (ent lname / elist)
  (if (and ent (entget ent))
    (progn
      (setq elist (entget ent))
      (entmod (subst (cons 8 lname) (assoc 8 elist) elist))
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Create layer if missing, force ON and THAWED
;;; ---------------------------------------------------------------
(defun bsrow-ensure-layer (lname lcolor / )
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "C" (itoa lcolor) lname "")
  )
  ;; Always force ON and THAWED regardless of previous state
  (command "_.LAYER" "ON" lname "T" lname "")
)

(princ "\n[BSROW v5.1] Loaded. Type BSROW to run.")
(princ "\n  Creates: ROW (30') + EOP (20' inward) + TRAP (35' outward)")
(princ)
