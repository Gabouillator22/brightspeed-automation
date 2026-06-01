;;; ============================================================
;;; BSPARCELS v4 - Trap-zone based parcel cleanup
;;;
;;; REQUIRES: BSROW v5 to have been run first (creates ROW-TRAP lines)
;;;
;;; HOW IT WORKS:
;;;   You pick ONE ROW line.
;;;   Script finds the corresponding TRAP line (on ROW-TRAP layer,
;;;   nearest to the selected ROW line on the outside).
;;;
;;;   For every PROPERTY LINE segment:
;;;     Test: are BOTH endpoints within the ROW-to-TRAP band?
;;;       dist(startpoint, ROW)  <= 35'
;;;       dist(startpoint, TRAP) <= 35'
;;;       dist(endpoint, ROW)    <= 35'
;;;       dist(endpoint, TRAP)   <= 35'
;;;       -> YES: both in band -> HIDE (move to PROPERTY LINE-HIDDEN)
;;;       -> NO:  one end deep in parcel -> EXTEND or TRIM to ROW
;;;
;;;   The trap zone (ROW to TRAP = 35') is guaranteed to contain
;;;   all parallel old-ROW-boundary segments and nothing else,
;;;   because parcel interior endpoints are always 50'+ from the road.
;;;
;;; Usage: BSPARCELS -> pick ONE ROW line -> automatic.
;;; All changes undo-able with Ctrl+Z.
;;; ============================================================

(defun c:BSPARCELS ( / old-cmdecho old-layer
                       row-ent trap-ent trap-ss
                       j trap-candidate trap-dist best-dist
                       ss-props i prop-ent
                       p-start p-end
                       d-start-row d-end-row
                       d-start-trap d-end-trap
                       start-in-band end-in-band
                       trap-offset
                       hidden-count extend-count trim-count skip-count
                       ipt close-end)

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  ;; Trap offset = distance BSROW used when creating TRAP lines
  ;; Must match the 35.0 value in BSROW v5
  (setq trap-offset 35.0)

  ;; Create hidden layer if needed
  (bsp-ensure-layer "PROPERTY LINE-HIDDEN" 8)

  (princ "\n[BSPARCELS] Pick the ROW line to work against: ")
  (setq row-ent (car (entsel "\nSelect ONE ROW line: ")))

  (if (not row-ent)
    (princ "\n[BSPARCELS] Nothing selected. Aborting.")
    (progn
      (if (not (= (cdr (assoc 8 (entget row-ent))) "ROW"))
        (princ "\n[BSPARCELS] Not a ROW layer entity. Please pick a ROW line.")
        (progn

          ;; -------------------------------------------------------
          ;; Find the corresponding TRAP line
          ;; Strategy: find the ROW-TRAP line whose midpoint is
          ;; closest to the ROW line midpoint — that's its partner
          ;; -------------------------------------------------------
          (setq row-mid
            (vlax-curve-getPointAtParam row-ent
              (/ (vlax-curve-getEndParam row-ent) 2.0)))

          (setq trap-ss (ssget "X" '((0 . "LWPOLYLINE,LINE") (8 . "ROW-TRAP"))))

          (setq trap-ent nil)
          (setq best-dist 999999.0)

          (if trap-ss
            (progn
              (setq j 0)
              (while (< j (sslength trap-ss))
                (setq trap-candidate (ssname trap-ss j))
                (setq trap-mid
                  (bsp-midpt trap-candidate))
                (setq trap-dist (distance row-mid trap-mid))
                (if (< trap-dist best-dist)
                  (progn
                    (setq best-dist trap-dist)
                    (setq trap-ent trap-candidate)
                  )
                )
                (setq j (1+ j))
              )
            )
          )

          (if (not trap-ent)
            (progn
              (princ "\n[BSPARCELS] No ROW-TRAP line found.")
              (princ "\n[BSPARCELS] Run BSROW v5 first to generate TRAP lines.")
              (princ "\n[BSPARCELS] Or type BSADDTRAP to add TRAP lines to existing ROW lines.")
            )
            (progn
              (princ (strcat "\n[BSPARCELS] TRAP line found. Band width = "
                (rtos trap-offset 2 0) "' from ROW."))

              ;; -------------------------------------------------------
              ;; Process all PROPERTY LINE segments
              ;; -------------------------------------------------------
              (setq ss-props (ssget "X" '((0 . "LWPOLYLINE,LINE") (8 . "PROPERTY LINE"))))

              (if (not ss-props)
                (princ "\n[BSPARCELS] No PROPERTY LINE entities found.")
                (progn
                  (setq hidden-count 0
                        extend-count 0
                        trim-count   0
                        skip-count   0)

                  (princ (strcat "\n[BSPARCELS] Analyzing "
                    (itoa (sslength ss-props)) " segments..."))

                  (setq i 0)
                  (while (< i (sslength ss-props))
                    (setq prop-ent (ssname ss-props i))

                    (if (= (cdr (assoc 8 (entget prop-ent))) "PROPERTY LINE")
                      (progn
                        (setq p-start (bsp-startpt prop-ent))
                        (setq p-end   (bsp-endpt   prop-ent))

                        ;; Distance of each endpoint to ROW and TRAP.
                        ;; A segment only counts as "in the band" if it stays
                        ;; inside the ROW-to-TRAP strip on the OUTSIDE side.
                        (setq d-start-row  (bsp-dist-to-ent p-start row-ent))
                        (setq d-end-row    (bsp-dist-to-ent p-end   row-ent))
                        (setq d-start-trap  (bsp-dist-to-ent p-start trap-ent))
                        (setq d-end-trap    (bsp-dist-to-ent p-end   trap-ent))

                        (setq start-in-band
                          (and (<= d-start-row trap-offset)
                               (<= d-start-trap trap-offset)))
                        (setq end-in-band
                          (and (<= d-end-row trap-offset)
                               (<= d-end-trap trap-offset)))

                        ;; Skip entirely if both endpoints far from ROW
                        (if (and (> d-start-row (* trap-offset 1.5))
                                 (> d-end-row   (* trap-offset 1.5)))
                          (setq skip-count (1+ skip-count))

                          (progn
                            ;; ==========================================
                            ;; TRAP TEST: both endpoints are inside the
                            ;; ROW-to-TRAP band on the OUTSIDE side
                            ;; -> this is a parallel band segment -> HIDE
                            ;; ==========================================
                            (if (and start-in-band end-in-band)

                              (progn
                                (bsp-force-layer prop-ent "PROPERTY LINE-HIDDEN")
                                (setq hidden-count (1+ hidden-count))
                              )

                              ;; ==========================================
                              ;; ONE END OUTSIDE TRAP ZONE
                              ;; -> parcel line -> extend or trim close end
                              ;; ==========================================
                              (progn
                                ;; Which end is closer to ROW?
                                (if (<= d-start-row d-end-row)
                                  (setq close-end p-start)
                                  (setq close-end p-end)
                                )

                                ;; Only act if close end is within trap zone
                                (if (or start-in-band end-in-band)
                                  (progn
                                    (setq ipt (bsp-intersect-extended prop-ent row-ent))
                                    (if ipt
                                      (progn
                                        ;; Crosses ROW -> trim the part past ROW
                                        (command "_.TRIM" row-ent "" close-end "")
                                        (setq trim-count (1+ trim-count))
                                      )
                                      (progn
                                        ;; Stops short -> extend to ROW
                                        (command "_.EXTEND" row-ent "" close-end "")
                                        (setq extend-count (1+ extend-count))
                                      )
                                    )
                                  )
                                  (setq skip-count (1+ skip-count))
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                    (setq i (1+ i))
                  )

                  ;; Freeze hidden layer
                  (command "_.LAYER" "F" "PROPERTY LINE-HIDDEN" "")

                  (princ "\n")
                  (princ "\n[BSPARCELS] ======== RESULTS ========")
                  (princ (strcat "\n  Parallel segments hidden  : " (itoa hidden-count)))
                  (princ (strcat "\n  Segments extended to ROW  : " (itoa extend-count)))
                  (princ (strcat "\n  Segments trimmed at ROW   : " (itoa trim-count)))
                  (princ (strcat "\n  Segments skipped          : " (itoa skip-count)))
                  (princ "\n  Hidden layer = PROPERTY LINE-HIDDEN (frozen)")
                  (princ "\n  Recover anytime: thaw PROPERTY LINE-HIDDEN")
                  (princ "\n  All changes undo-able with Ctrl+Z")
                  (princ "\n[BSPARCELS] =========================")
                )
              )
            )
          )
        )
      )
    )
  )

  (setvar "CMDECHO" old-cmdecho)
  (setvar "CLAYER" old-layer)
(princ)
)

;;; ---------------------------------------------------------------
;;; BSPARHIDE - Hide old parallel property-line fragments only
;;; Safer than BSPARCELS while testing: no trim, no extend, no delete.
;;; ---------------------------------------------------------------
(defun c:BSPARHIDE ( / old-cmdecho old-layer row-ent trap-ent trap-ss
                       row-mid trap-mid trap-candidate trap-dist best-dist
                       ss-props i prop-ent p-start p-end p-mid
                       prop-dir row-dir trap-offset band-tol inside-limit parallel-dot
                       in-outside-band in-inside-shoulder
                       hidden-count skip-count)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  ;; 35' is the designed ROW-to-TRAP distance. 6' tolerance absorbs GIS noise
  ;; and tiny parcel-segment endpoint gaps without catching road-side lines.
  (setq trap-offset 35.0)
  (setq band-tol 6.0)
  ;; Inside-running old ROW fragments can sit road-side of the new ROW.
  ;; Keep this close to the trap width so we do not reach deep into parcels.
  (setq inside-limit 35.0)
  (setq parallel-dot 0.94) ; roughly within 20 degrees of parallel

  (bsp-ensure-layer "PROPERTY LINE-HIDDEN" 8)

  (princ "\n[BSPARHIDE] Pick the ROW line beside the property fragments: ")
  (setq row-ent (car (entsel "\nSelect ONE ROW line: ")))

  (cond
    ((not row-ent)
      (princ "\n[BSPARHIDE] Nothing selected. Aborting."))

    ((not (= (cdr (assoc 8 (entget row-ent))) "ROW"))
      (princ "\n[BSPARHIDE] Not a ROW layer entity. Please pick a ROW line."))

    (T
      ;; Pair the picked ROW with the nearest ROW-TRAP line.
      (setq row-mid (bsp-midpt row-ent))
      (setq trap-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROW-TRAP"))))
      (setq trap-ent nil)
      (setq best-dist 999999.0)

      (if trap-ss
        (progn
          (setq i 0)
          (while (< i (sslength trap-ss))
            (setq trap-candidate (ssname trap-ss i))
            (setq trap-mid (bsp-midpt trap-candidate))
            (setq trap-dist (distance row-mid trap-mid))
            (if (< trap-dist best-dist)
              (progn
                (setq best-dist trap-dist)
                (setq trap-ent trap-candidate)))
            (setq i (1+ i)))))

      (if (not trap-ent)
        (princ "\n[BSPARHIDE] No ROW-TRAP line found. Run BSROW first.")
        (progn
          (setq ss-props (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "PROPERTY LINE"))))

          (if (not ss-props)
            (princ "\n[BSPARHIDE] No PROPERTY LINE entities found.")
            (progn
              (setq hidden-count 0)
              (setq skip-count 0)

              (princ (strcat "\n[BSPARHIDE] Checking "
                (itoa (sslength ss-props)) " property segments..."))

              (setq i 0)
              (while (< i (sslength ss-props))
                (setq prop-ent (ssname ss-props i))
                (setq p-start (bsp-startpt prop-ent))
                (setq p-end   (bsp-endpt prop-ent))
                (setq p-mid   (bsp-avgpt p-start p-end))
                (setq prop-dir (bsp-ent-dir prop-ent))
                (setq row-dir  (bsp-tangent-at-point row-ent p-mid))
                (setq in-outside-band
                  (and
                    (bsp-point-in-band-p p-mid row-ent trap-ent trap-offset band-tol)
                    (bsp-point-in-band-p p-start row-ent trap-ent trap-offset band-tol)
                    (bsp-point-in-band-p p-end row-ent trap-ent trap-offset band-tol)))
                (setq in-inside-shoulder
                  (and
                    (bsp-point-near-row-p p-mid row-ent inside-limit band-tol)
                    (bsp-point-near-row-p p-start row-ent inside-limit band-tol)
                    (bsp-point-near-row-p p-end row-ent inside-limit band-tol)))

                (if (and prop-dir
                         row-dir
                         (or in-outside-band in-inside-shoulder)
                         (bsp-parallel-p prop-dir row-dir parallel-dot))
                  (progn
                    (bsp-force-layer prop-ent "PROPERTY LINE-HIDDEN")
                    (setq hidden-count (1+ hidden-count)))
                  (setq skip-count (1+ skip-count)))

                (setq i (1+ i)))

              (command "_.LAYER" "F" "PROPERTY LINE-HIDDEN" "")

              (princ "\n")
              (princ "\n[BSPARHIDE] ======== RESULTS ========")
              (princ (strcat "\n  Parallel segments hidden : " (itoa hidden-count)))
              (princ (strcat "\n  Segments skipped         : " (itoa skip-count)))
              (princ "\n  No trim/extend/delete was performed.")
              (princ "\n  Hidden layer = PROPERTY LINE-HIDDEN (frozen)")
              (princ "\n[BSPARHIDE] =========================")))))))

  (setvar "CMDECHO" old-cmdecho)
  (setvar "CLAYER" old-layer)
  (princ)
)

;;; ---------------------------------------------------------------
;;; BSADDTRAP - Add TRAP lines to existing ROW lines
;;; Run this if you already have ROW lines from an older BSROW version
;;; ---------------------------------------------------------------
(defun c:BSADDTRAP ( / old-cmdecho old-layer ss i ent
                       p-mid tangent perp-out-1 perp-out-2
                       snap-before new-trap
                       row-mid cl-ss cl-ent cl-mid)

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bsp-ensure-layer "ROW-TRAP" 4)

  (setq ss (ssget "X" '((0 . "LWPOLYLINE,LINE") (8 . "ROW"))))

  (if (not ss)
    (princ "\n[BSADDTRAP] No ROW lines found. Aborting.")
    (progn
      (princ (strcat "\n[BSADDTRAP] Adding TRAP lines to "
        (itoa (sslength ss)) " ROW lines..."))

      ;; Get centerline midpoint for outward direction reference
      (setq cl-ss (ssget "X" '((0 . "LWPOLYLINE,LINE") (8 . "ROAD-CENTERLINE"))))

      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))

        ;; Midpoint of this ROW line
        (setq row-mid (bsp-midpt ent))

        ;; Find nearest centerline to determine outward direction
        (setq outward-pt nil)
        (if cl-ss
          (progn
            (setq cl-ent (ssname cl-ss 0))  ; use first centerline as reference
            (setq cl-mid (bsp-midpt cl-ent))
            ;; Outward = away from centerline
            ;; Point on opposite side of ROW from centerline
            (setq outward-pt
              (list
                (+ (car row-mid)  (- (car row-mid)  (car cl-mid)))
                (+ (cadr row-mid) (- (cadr row-mid) (cadr cl-mid)))
                0.0))
          )
        )

        (if outward-pt
          (progn
            (setq snap-before (entlast))
            (command "_.OFFSET" 35.0 ent outward-pt "")
            (setq new-trap (entlast))
            (if (not (equal new-trap snap-before))
              (progn
                (bsp-force-layer new-trap "ROW-TRAP")
                (princ (strcat "\n[BSADDTRAP] TRAP added for ROW line #" (itoa (1+ i))))
              )
              (princ (strcat "\n[BSADDTRAP] WARNING: TRAP failed for ROW line #" (itoa (1+ i))))
            )
          )
          (princ "\n[BSADDTRAP] WARNING: Could not determine outward direction.")
        )

        (setq i (1+ i))
      )

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n[BSADDTRAP] Done. Now run BSPARCELS and pick a ROW line.")
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------

(defun bsp-midpt (ent / etype)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (vlax-curve-getPointAtParam ent
        (/ (vlax-curve-getEndParam ent) 2.0)))
    ((= etype "LINE")
      (mapcar '(lambda (a b) (/ (+ a b) 2.0))
        (cdr (assoc 10 (entget ent)))
        (cdr (assoc 11 (entget ent)))))
  )
)

(defun bsp-startpt (ent / etype)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")      (cdr (assoc 10 (entget ent))))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (vlax-curve-getPointAtParam ent 0.0))
  )
)

(defun bsp-endpt (ent / etype)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")      (cdr (assoc 11 (entget ent))))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (vlax-curve-getPointAtParam ent (vlax-curve-getEndParam ent)))
  )
)

(defun bsp-dist-to-ent (pt ent / etype p1 p2)
  (setq etype (cdr (assoc 0 (entget ent))))
  (distance pt
    (cond
      ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
        (vlax-curve-getClosestPointTo ent pt))
      ((= etype "LINE")
        (setq p1 (cdr (assoc 10 (entget ent))))
        (setq p2 (cdr (assoc 11 (entget ent))))
        (bsp-closest-on-seg p1 p2 pt))
      (T pt)
    )
  )
)

(defun bsp-closest-on-seg (p1 p2 pt / dx dy len2 tv)
  (setq dx (- (car p2) (car p1)) dy (- (cadr p2) (cadr p1)))
  (setq len2 (+ (* dx dx) (* dy dy)))
  (if (= len2 0.0) p1
    (progn
      (setq tv (/ (+ (* (- (car pt) (car p1)) dx)
                     (* (- (cadr pt) (cadr p1)) dy)) len2))
      (if (< tv 0.0) (setq tv 0.0))
      (if (> tv 1.0) (setq tv 1.0))
      (list (+ (car p1) (* tv dx)) (+ (cadr p1) (* tv dy)) 0.0)
    )
  )
)

(defun bsp-intersect-extended (ea eb / res)
  (setq res
    (vlax-invoke (vlax-ename->vla-object ea)
      'IntersectWith (vlax-ename->vla-object eb) 3))
  (if (and res (> (length res) 0))
    (list (nth 0 res) (nth 1 res) (nth 2 res)) nil)
)

(defun bsp-force-layer (ent lname / elist)
  (if (and ent (entget ent))
    (progn
      (setq elist (entget ent))
      (entmod (subst (cons 8 lname) (assoc 8 elist) elist))
    )
  )
  (princ)
)

(defun bsp-avgpt (p1 p2 / )
  (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2)
)

(defun bsp-vsub (p1 p2 / )
  (list (- (car p1) (car p2)) (- (cadr p1) (cadr p2)) 0.0)
)

(defun bsp-vdot (v1 v2 / )
  (+ (* (car v1) (car v2)) (* (cadr v1) (cadr v2)))
)

(defun bsp-vlen (v / )
  (sqrt (bsp-vdot v v))
)

(defun bsp-vunit (v / len)
  (setq len (bsp-vlen v))
  (if (> len 0.000001)
    (list (/ (car v) len) (/ (cadr v) len) 0.0)
    nil)
)

(defun bsp-ent-dir (ent / etype p1 p2)
  (setq etype (cdr (assoc 0 (entget ent))))
  (setq p1 (bsp-startpt ent))
  (setq p2 (bsp-endpt ent))
  (if (and p1 p2)
    (bsp-vunit (bsp-vsub p2 p1))
    nil)
)

(defun bsp-tangent-at-point (ent pt / etype ed p1 p2 cp param deriv)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")
      (setq ed (entget ent))
      (setq p1 (cdr (assoc 10 ed)))
      (setq p2 (cdr (assoc 11 ed)))
      (bsp-vunit (bsp-vsub p2 p1)))

    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
      (if (vl-catch-all-error-p cp)
        nil
        (progn
          (setq param (vl-catch-all-apply 'vlax-curve-getParamAtPoint (list ent cp)))
          (if (vl-catch-all-error-p param)
            nil
            (progn
              (setq deriv (vl-catch-all-apply 'vlax-curve-getFirstDeriv (list ent param)))
              (if (vl-catch-all-error-p deriv)
                nil
                (bsp-vunit deriv)))))))
    (T nil))
)

(defun bsp-point-in-band-p (pt row-ent trap-ent trap-offset tol / d-row d-trap)
  (setq d-row  (bsp-dist-to-ent pt row-ent))
  (setq d-trap (bsp-dist-to-ent pt trap-ent))
  (and
    (<= d-row (+ trap-offset tol))
    (<= d-trap (+ trap-offset tol))
    (<= (abs (- (+ d-row d-trap) trap-offset)) tol))
)

(defun bsp-point-near-row-p (pt row-ent max-dist tol / d-row)
  (setq d-row (bsp-dist-to-ent pt row-ent))
  (<= d-row (+ max-dist tol))
)

(defun bsp-parallel-p (dir1 dir2 min-dot / dotval)
  (setq dotval (abs (bsp-vdot dir1 dir2)))
  (>= dotval min-dot)
)

(defun bsp-ensure-layer (lname lcolor / )
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "C" (itoa lcolor) lname "")
  )
)

(princ "\n[BSPARCELS v4] Loaded.")
(princ "\n  BSPARCELS  -> pick a ROW line -> cleans property lines using TRAP zone")
(princ "\n  BSPARHIDE  -> hides only parallel PROPERTY LINE fragments in ROW/TRAP band")
(princ "\n  BSADDTRAP  -> adds TRAP lines to existing ROW lines (if using old BSROW)")
(princ)
