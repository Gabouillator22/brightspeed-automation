;;; ============================================================
;;; BSROW v5 - Auto-draw ROW, EOP, and TRAP lines
;;;
;;; CHANGES vs v4:
;;;   - After creating each ROW line, also creates a TRAP line
;;;     offset 35' further OUTSIDE (away from centerline)
;;;   - TRAP lines go on layer "ROW-TRAP" (color cyan, dashed)
;;;   - TRAP lines are used by BSPARCELS to define the catch zone
;;;     for hiding old parallel property line segments
;;;
;;; OFFSETS SUMMARY:
;;;   Centerline -> 30' each side -> ROW
;;;   ROW -> 20' inward           -> EOP (ROADS-paved)
;;;   ROW -> 35' outward          -> TRAP (ROW-TRAP) [NEW]
;;;
;;; All v4 bug fixes retained:
;;;   - True perpendicular direction via vlax-curve-getFirstDeriv
;;;   - entlast verification before/after each OFFSET
;;;   - Per-line inward vector for EOP
;;; ============================================================

(defun c:BSROW ( / old-cmdecho old-layer ss i ent ent-type
                   p-mid tangent perp-left perp-right
                   snap-before
                   new-row-1 new-row-2
                   new-eop-1 new-eop-2
                   new-trap-1 new-trap-2
                   cl-mid outward-1 outward-2)

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  ;; Ensure ROW-TRAP layer exists — cyan (4), dashed
  (bsrow-ensure-layer "ROW-TRAP" 4)
  ;; Set linetype to dashed on ROW-TRAP if DASHED linetype loaded
  ;; (silently skip if not loaded — won't crash)
  (if (tblsearch "LTYPE" "DASHED")
    (command "_.LAYER" "LT" "DASHED" "ROW-TRAP" "")
  )

  ;; Auto-select all centerlines on ROAD-CENTERLINE layer
  (setq ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROAD-CENTERLINE"))))

  (if (not ss)
    (princ "\n[BSROW] No objects found on ROAD-CENTERLINE layer. Aborting.")
    (progn
      (princ (strcat "\n[BSROW] Found " (itoa (sslength ss)) " centerline(s). Processing..."))

      (setq i 0)
      (while (< i (sslength ss))
        (setq ent      (ssname ss i))
        (setq ent-type (cdr (assoc 0 (entget ent))))

        ;; Midpoint of centerline
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

        ;; True perpendicular direction at midpoint
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

        ;; Perpendicular points — guaranteed opposite sides regardless of road angle
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
          (progn (princ (strcat "\n[BSROW] WARNING: Left ROW failed on #" (itoa (1+ i)))) (setq new-row-1 nil))
          (bsrow-force-layer new-row-1 "ROW")
        )

        ;; ===== ROW RIGHT (30') =====
        (setq snap-before (entlast))
        (command "_.OFFSET" 30.0 ent perp-right "")
        (setq new-row-2 (entlast))
        (if (equal new-row-2 snap-before)
          (progn (princ (strcat "\n[BSROW] WARNING: Right ROW failed on #" (itoa (1+ i)))) (setq new-row-2 nil))
          (bsrow-force-layer new-row-2 "ROW")
        )

        ;; ===== EOP LEFT (20' inward from ROW-left) =====
        (if new-row-1
          (progn
            (setq snap-before (entlast))
            (command "_.OFFSET" 20.0 new-row-1 cl-mid "")
            (setq new-eop-1 (entlast))
            (if (equal new-eop-1 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Left EOP failed on #" (itoa (1+ i))))
              (bsrow-force-layer new-eop-1 "ROADS-paved")
            )
          )
        )

        ;; ===== EOP RIGHT (20' inward from ROW-right) =====
        (if new-row-2
          (progn
            (setq snap-before (entlast))
            (command "_.OFFSET" 20.0 new-row-2 cl-mid "")
            (setq new-eop-2 (entlast))
            (if (equal new-eop-2 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Right EOP failed on #" (itoa (1+ i))))
              (bsrow-force-layer new-eop-2 "ROADS-paved")
            )
          )
        )

        ;; ===== TRAP LEFT (35' outward from ROW-left = 65' from centerline) =====
        ;; Outward from ROW-left means AWAY from centerline = same direction as perp-left
        (if new-row-1
          (progn
            (setq snap-before (entlast))
            (command "_.OFFSET" 35.0 new-row-1 perp-left "")
            (setq new-trap-1 (entlast))
            (if (equal new-trap-1 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Left TRAP failed on #" (itoa (1+ i))))
              (bsrow-force-layer new-trap-1 "ROW-TRAP")
            )
          )
        )

        ;; ===== TRAP RIGHT (35' outward from ROW-right) =====
        (if new-row-2
          (progn
            (setq snap-before (entlast))
            (command "_.OFFSET" 35.0 new-row-2 perp-right "")
            (setq new-trap-2 (entlast))
            (if (equal new-trap-2 snap-before)
              (princ (strcat "\n[BSROW] WARNING: Right TRAP failed on #" (itoa (1+ i))))
              (bsrow-force-layer new-trap-2 "ROW-TRAP")
            )
          )
        )

        (setq i (1+ i))
      )

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n[BSROW] Done.")
      (princ "\n[BSROW] ROW-TRAP lines created on layer ROW-TRAP.")
      (princ "\n[BSROW] Run BSPARCELS and pick a ROW line to clean property lines.")
    )
  )
  (princ)
)

(defun bsrow-force-layer (ent lname / elist)
  (if (and ent (entget ent))
    (progn
      (setq elist (entget ent))
      (entmod (subst (cons 8 lname) (assoc 8 elist) elist))
    )
  )
  (princ)
)

(defun bsrow-ensure-layer (lname lcolor / )
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "C" (itoa lcolor) lname "")
  )
)

(princ "\n[BSROW v5] Loaded. Type BSROW to run.")
(princ "\n[BSROW v5] Now creates ROW + EOP + TRAP lines in one pass.")
(princ)
