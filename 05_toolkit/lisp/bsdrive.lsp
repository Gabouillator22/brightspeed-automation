;;; ============================================================
;;; BSDRIVE - Draw and position a driveway line
;;;
;;; Usage: BSDRIVE -> pick 2 points -> automatic.
;;;
;;; Workflow:
;;;   1. User picks p1 and p2 (approximate driveway endpoints from aerial).
;;;   2. Draws LWPOLYLINE from p1 to p2 on DRIVEWAYS layer.
;;;   3. Finds the nearest EOP line (ROADS-paved) to each endpoint.
;;;   4. Extends the driveway to each EOP line (using virtual intersection).
;;;   5. Finds the nearest ROW line to each extended endpoint.
;;;   6. Trims the driveway at each ROW line (clips to ROW boundary).
;;;   Result: a clean driveway line from ROW to ROW.
;;;
;;; Extension/trim strategy:
;;;   Uses IntersectWith(acExtendBoth=3) to find virtual intersections
;;;   of the driveway line with EOP and ROW lines.  Endpoints are then
;;;   updated via entmod — no TRIM/EXTEND command dependencies.
;;;   This avoids entity-handle instability from TRIM/EXTEND AutoLISP calls.
;;;
;;; Edge cases:
;;;   No EOP found  -> warns, leaves driveway between user picks.
;;;   No ROW found  -> warns, leaves driveway at EOP endpoints.
;;;
;;; Layer   : DRIVEWAYS (color 30 = orange), created if missing.
;;; Safety  : No deletes. Undo-safe.
;;; ============================================================

(defun c:BSDRIVE ( / old-cmdecho old-layer
                     p1 p2 dw-ent elist
                     eop-ss row-ss
                     eop-near-p1 eop-near-p2
                     row-near-final-p1 row-near-final-p2
                     new-p1 new-p2
                     ipt-eop1 ipt-eop2
                     ipt-row1 ipt-row2
                     snap-before)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "DRIVEWAYS" 30)

  (setvar "CMDECHO" 1)
  (setq p1 (getpoint "\n[BSDRIVE] Pick first driveway point: "))
  (if p1
    (setq p2 (getpoint p1 "\n[BSDRIVE] Pick second driveway point: ")))
  (setvar "CMDECHO" 0)

  (if (not (and p1 p2))
    (progn
      (princ "\n[BSDRIVE] Cancelled.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      ;; Normalize to 2D (strip Z)
      (setq p1 (list (car p1) (cadr p1) 0.0))
      (setq p2 (list (car p2) (cadr p2) 0.0))

      ;; Draw initial driveway polyline
      (setvar "CLAYER" "DRIVEWAYS")
      (setq snap-before (entlast))
      (entmake
        (list
          '(0 . "LWPOLYLINE")
          (cons 8 "DRIVEWAYS")
          '(100 . "AcDbEntity")
          '(100 . "AcDbPolyline")
          '(90 . 2)
          '(70 . 0)
          (cons 10 (list (car p1) (cadr p1)))
          (cons 10 (list (car p2) (cadr p2)))))
      (setq dw-ent (entlast))

      (if (equal dw-ent snap-before)
        (progn
          (princ "\n[BSDRIVE] ERROR: Could not create driveway polyline.")
          (setvar "CMDECHO" old-cmdecho)
          (setvar "CLAYER" old-layer))
        (progn
          (princ "\n[BSDRIVE] Driveway drawn. Finding EOP and ROW lines...")

          ;; Get EOP and ROW entities
          (setq eop-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROADS-paved"))))
          (setq row-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROW"))))

          ;; --- STEP 1: Extend to EOP ---
          ;; Find virtual intersections with EOP lines.
          ;; The "EOP end" for p1 side = intersection closest to p1.
          (setq new-p1 p1)
          (setq new-p2 p2)

          (if (not eop-ss)
            (princ "\n[BSDRIVE] WARNING: No ROADS-paved (EOP) lines found. Skipping EOP extension.")
            (progn
              (setq eop-near-p1 (bs-nearest-ent-in-ss p1 eop-ss))
              (setq eop-near-p2 (bs-nearest-ent-in-ss p2 eop-ss))

              ;; Find virtual intersection of driveway with each EOP line
              (setq ipt-eop1 (if eop-near-p1 (bs-intersect-first dw-ent eop-near-p1 3) nil))
              (setq ipt-eop2 (if eop-near-p2 (bs-intersect-first dw-ent eop-near-p2 3) nil))

              ;; Update endpoints to EOP intersections (if found and closer to original points)
              (if ipt-eop1
                (setq new-p1 ipt-eop1)
                (princ "\n[BSDRIVE] WARNING: No EOP intersection found near first pick."))
              (if ipt-eop2
                (setq new-p2 ipt-eop2)
                (princ "\n[BSDRIVE] WARNING: No EOP intersection found near second pick."))
            )
          )

          ;; --- STEP 2: Trim at ROW ---
          (if (not row-ss)
            (princ "\n[BSDRIVE] WARNING: No ROW lines found. Skipping ROW trim.")
            (progn
              ;; Update entity to EOP endpoints first (need accurate geometry)
              (setq elist (entget dw-ent))
              (setq elist (bs-replace-nth-vertex elist 0 new-p1))
              (setq elist (bs-replace-nth-vertex elist 1 new-p2))
              (entmod elist)
              (entupd dw-ent)

              ;; Now find ROW intersections (virtual) from the updated endpoints
              ;; Use current endpoints of driveway (after EOP extension)
              (setq final-p1 (bs-ent-startpt dw-ent))
              (setq final-p2 (bs-ent-endpt   dw-ent))

              (setq row-near-final-p1 (bs-nearest-ent-in-ss final-p1 row-ss))
              (setq row-near-final-p2 (bs-nearest-ent-in-ss final-p2 row-ss))

              (setq ipt-row1 (if row-near-final-p1 (bs-intersect-first dw-ent row-near-final-p1 3) nil))
              (setq ipt-row2 (if row-near-final-p2 (bs-intersect-first dw-ent row-near-final-p2 3) nil))

              ;; Set final endpoints to ROW intersections
              (if ipt-row1
                (setq new-p1 ipt-row1)
                (princ "\n[BSDRIVE] WARNING: No ROW intersection found near first end."))
              (if ipt-row2
                (setq new-p2 ipt-row2)
                (princ "\n[BSDRIVE] WARNING: No ROW intersection found near second end."))
            )
          )

          ;; Apply final endpoints
          (setq elist (entget dw-ent))
          (setq elist (bs-replace-nth-vertex elist 0 new-p1))
          (setq elist (bs-replace-nth-vertex elist 1 new-p2))
          (entmod elist)
          (entupd dw-ent)

          (setvar "CMDECHO" old-cmdecho)
          (setvar "CLAYER" old-layer)
          (princ "\n[BSDRIVE] Done. Driveway placed on DRIVEWAYS layer.")
          (princ "\n[BSDRIVE] Undo with Ctrl+Z.")
        )
      )
    )
  )
  (princ)
)

(princ "\n[BSDRIVE] Loaded. Type BSDRIVE -> pick 2 points -> driveway auto-trimmed to ROW.")
(princ)
