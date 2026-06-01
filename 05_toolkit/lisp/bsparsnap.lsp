;;; ============================================================
;;; BSPARSNAP - Snap perpendicular PROPERTY LINE endpoints to ROW
;;;
;;; Usage:
;;;   BSPARSNAP -> pick ONE ROW line.
;;;
;;; What it does:
;;;   Finds PROPERTY LINE entities that come into the selected ROW
;;;   roughly perpendicular to it. The matching ROW-TRAP defines the
;;;   selected outside side, so opposite-side parcel lines are skipped.
;;;   Then the correct endpoint is moved exactly onto the ROW.
;;;
;;; Safety:
;;;   No deletes. No command-line TRIM/EXTEND. Uses entmod on LINE
;;;   endpoints only, so Ctrl+Z can undo the whole run.
;;; ============================================================

(defun c:BSPARSNAP ( / old-cmdecho old-layer row-ent trap-ent ss i ent
                       p1 p2 close-pt close-code
                       d1 d2 prop-dir row-dir ipt move-dist
                       side1 side2
                       max-adjust perp-dot side-anchor-min snap-count skip-count
                       not-line-count no-hit-count angle-skip-count
                       far-skip-count side-skip-count row-skip-count)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  ;; Maximum endpoint movement allowed. This catches gaps/crossings near ROW
  ;; without dragging deep parcel geometry across the drawing.
  (setq max-adjust 75.0)
  ;; Dot product near 0 means perpendicular. 0.45 is about 63-117 degrees.
  (setq perp-dot 0.45)
  ;; A line must have a real endpoint on the selected ROW's outside side.
  ;; Points already on ROW do not count as selected-side ownership.
  (setq side-anchor-min 3.0)

  (princ "\n[BSPARSNAP] Pick the ROW line to snap perpendicular property lines to: ")
  (setq row-ent (car (entsel "\nSelect ONE ROW line: ")))

  (cond
    ((not row-ent)
      (princ "\n[BSPARSNAP] Nothing selected. Aborting."))

    ((not (= (cdr (assoc 8 (entget row-ent))) "ROW"))
      (princ "\n[BSPARSNAP] Not a ROW layer entity. Please pick a ROW line."))

    (T
      (command "_.UNDO" "_BE")

      ;; The matching ROW-TRAP line tells us which side of ROW is outside.
      ;; That lets us trim the road-side endpoint instead of guessing by distance.
      (setq trap-ent (bsps-nearest-trap row-ent))

      (if (not trap-ent)
        (princ "\n[BSPARSNAP] No matching ROW-TRAP line found. Run BSROW first.")
        (progn
          (setq ss (ssget "X" '((0 . "LINE,LWPOLYLINE,POLYLINE") (8 . "PROPERTY LINE"))))

          (if (not ss)
            (princ "\n[BSPARSNAP] No PROPERTY LINE entities found.")
            (progn
              (setq snap-count 0
                    skip-count 0
                    not-line-count 0
                    no-hit-count 0
                    angle-skip-count 0
                    far-skip-count 0
                    side-skip-count 0
                    row-skip-count 0)

              (princ (strcat "\n[BSPARSNAP] Checking "
                (itoa (sslength ss)) " PROPERTY LINE entities..."))

              (setq i 0)
              (while (< i (sslength ss))
                (setq ent (ssname ss i))

                ;; GIS parcel fragments are expected to be LINEs after explode.
                ;; Polylines are skipped for now to avoid reshaping multi-vertex parcels.
                (if (not (= (cdr (assoc 0 (entget ent))) "LINE"))
                  (progn
                    (setq not-line-count (1+ not-line-count))
                    (setq skip-count (1+ skip-count)))
                  (progn
                    (setq p1 (cdr (assoc 10 (entget ent))))
                    (setq p2 (cdr (assoc 11 (entget ent))))
                    (setq prop-dir (bsps-unit (bsps-vsub p2 p1)))

                    (setq d1 (bsps-dist-to-ent p1 row-ent))
                    (setq d2 (bsps-dist-to-ent p2 row-ent))
                    (setq side1 (bsps-side-to-row p1 row-ent trap-ent))
                    (setq side2 (bsps-side-to-row p2 row-ent trap-ent))

                    ;; Require ownership on the selected outside side.
                    ;; This prevents lower/opposite-side parcel lines from being
                    ;; extended up to the ROW you selected.
                    (cond
                      ((and side1 side2 (< side1 -0.001) (> side2 side-anchor-min))
                        (setq close-pt p1)
                        (setq close-code 10))
                      ((and side1 side2 (< side2 -0.001) (> side1 side-anchor-min))
                        (setq close-pt p2)
                        (setq close-code 11))
                      ((and side1 side2 (> side1 side-anchor-min) (> side2 side-anchor-min))
                        (if (<= d1 d2)
                          (progn (setq close-pt p1) (setq close-code 10))
                          (progn (setq close-pt p2) (setq close-code 11))))
                      (T
                        (setq close-pt nil)
                        (setq close-code nil)))

                    ;; Check perpendicular against the ROW tangent near this line.
                    (if close-pt
                      (setq row-dir (bsps-tangent-at-point row-ent close-pt))
                      (setq row-dir nil))

                    (cond
                      ((not (bsps-selected-row-nearest-p ent row-ent 5.0))
                        (setq row-skip-count (1+ row-skip-count))
                        (setq skip-count (1+ skip-count)))

                      ((not close-pt)
                        (setq side-skip-count (1+ side-skip-count))
                        (setq skip-count (1+ skip-count)))

                      ((not (and prop-dir row-dir))
                        (setq skip-count (1+ skip-count)))

                      ((> (abs (bsps-dot prop-dir row-dir)) perp-dot)
                        (setq angle-skip-count (1+ angle-skip-count))
                        (setq skip-count (1+ skip-count)))

                      (T
                        ;; Extend this PROPERTY LINE only; ROW stays real/finite.
                        (setq ipt (bsps-intersect-nearest ent row-ent close-pt 1))

                        (if (not ipt)
                          (progn
                            (setq no-hit-count (1+ no-hit-count))
                            (setq skip-count (1+ skip-count)))
                          (progn
                            (setq move-dist (distance close-pt ipt))

                            (if (> move-dist max-adjust)
                              (progn
                                (setq far-skip-count (1+ far-skip-count))
                                (setq skip-count (1+ skip-count)))
                              (progn
                                (bsps-set-line-endpoint ent close-code ipt)
                                (setq snap-count (1+ snap-count)))))))))))

                (setq i (1+ i)))

              (princ "\n")
              (princ "\n[BSPARSNAP] ======== RESULTS ========")
              (princ (strcat "\n  Endpoints snapped to ROW : " (itoa snap-count)))
              (princ (strcat "\n  Skipped total            : " (itoa skip-count)))
              (princ (strcat "\n  Skipped non-LINE         : " (itoa not-line-count)))
              (princ (strcat "\n  Skipped not perpendicular: " (itoa angle-skip-count)))
              (princ (strcat "\n  Skipped no ROW hit       : " (itoa no-hit-count)))
              (princ (strcat "\n  Skipped too far          : " (itoa far-skip-count)))
              (princ (strcat "\n  Skipped side ambiguous   : " (itoa side-skip-count)))
              (princ (strcat "\n  Skipped closer other ROW : " (itoa row-skip-count)))
              (princ "\n  No entities deleted. LINE endpoints only were moved.")
              (princ "\n[BSPARSNAP] =========================")))))

      (command "_.UNDO" "_END"))

  (setvar "CMDECHO" old-cmdecho)
  (setvar "CLAYER" old-layer)
  (princ)
)

;;; ---------------------------------------------------------------
;;; Geometry helpers
;;; ---------------------------------------------------------------

(defun bsps-vsub (p1 p2 / )
  (list (- (car p1) (car p2)) (- (cadr p1) (cadr p2)) 0.0)
)

(defun bsps-dot (v1 v2 / )
  (+ (* (car v1) (car v2)) (* (cadr v1) (cadr v2)))
)

(defun bsps-len (v / )
  (sqrt (bsps-dot v v))
)

(defun bsps-unit (v / len)
  (setq len (bsps-len v))
  (if (> len 0.000001)
    (list (/ (car v) len) (/ (cadr v) len) 0.0)
    nil)
)

(defun bsps-closest-on-seg (p1 p2 pt / dx dy len2 tv)
  (setq dx (- (car p2) (car p1)))
  (setq dy (- (cadr p2) (cadr p1)))
  (setq len2 (+ (* dx dx) (* dy dy)))
  (if (= len2 0.0)
    p1
    (progn
      (setq tv (/ (+ (* (- (car pt) (car p1)) dx)
                     (* (- (cadr pt) (cadr p1)) dy)) len2))
      (if (< tv 0.0) (setq tv 0.0))
      (if (> tv 1.0) (setq tv 1.0))
      (list (+ (car p1) (* tv dx)) (+ (cadr p1) (* tv dy)) 0.0)))
)

(defun bsps-dist-to-ent (pt ent / etype ed p1 p2 cp)
  (setq etype (cdr (assoc 0 (entget ent))))
  (distance pt
    (cond
      ((= etype "LINE")
        (setq ed (entget ent))
        (setq p1 (cdr (assoc 10 ed)))
        (setq p2 (cdr (assoc 11 ed)))
        (bsps-closest-on-seg p1 p2 pt))
      ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
        (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
        (if (vl-catch-all-error-p cp) pt cp))
      (T pt)))
)

(defun bsps-midpt (ent / etype ed p1 p2)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")
      (setq ed (entget ent))
      (setq p1 (cdr (assoc 10 ed)))
      (setq p2 (cdr (assoc 11 ed)))
      (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (vlax-curve-getPointAtParam ent (/ (vlax-curve-getEndParam ent) 2.0)))
    (T nil))
)

(defun bsps-closest-point-to-ent (pt ent / etype ed p1 p2 cp)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")
      (setq ed (entget ent))
      (setq p1 (cdr (assoc 10 ed)))
      (setq p2 (cdr (assoc 11 ed)))
      (bsps-closest-on-seg p1 p2 pt))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
      (if (vl-catch-all-error-p cp) nil cp))
    (T nil))
)

(defun bsps-nearest-trap (row-ent / row-mid trap-ss i cand cand-mid best bestd d)
  (setq row-mid (bsps-midpt row-ent))
  (setq trap-ss (ssget "X" '((0 . "LINE,LWPOLYLINE,POLYLINE") (8 . "ROW-TRAP"))))
  (setq best nil)
  (setq bestd 999999999.0)
  (if (and row-mid trap-ss)
    (progn
      (setq i 0)
      (while (< i (sslength trap-ss))
        (setq cand (ssname trap-ss i))
        (setq cand-mid (bsps-midpt cand))
        (if cand-mid
          (progn
            (setq d (distance row-mid cand-mid))
            (if (< d bestd)
              (progn
                (setq bestd d)
                (setq best cand)))))
        (setq i (1+ i)))))
  best
)

(defun bsps-row-score (ent row-ent / p1 p2 pm d1 d2 dm)
  (setq p1 (cdr (assoc 10 (entget ent))))
  (setq p2 (cdr (assoc 11 (entget ent))))
  (setq pm (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))
  (setq d1 (bsps-dist-to-ent p1 row-ent))
  (setq d2 (bsps-dist-to-ent p2 row-ent))
  (setq dm (bsps-dist-to-ent pm row-ent))
  (min d1 d2 dm)
)

(defun bsps-selected-row-nearest-p (ent row-ent tol / rows i cand sel-score cand-score best-score)
  (setq sel-score (bsps-row-score ent row-ent))
  (setq best-score sel-score)
  (setq rows (ssget "X" '((0 . "LINE,LWPOLYLINE,POLYLINE") (8 . "ROW"))))
  (if rows
    (progn
      (setq i 0)
      (while (< i (sslength rows))
        (setq cand (ssname rows i))
        (if (not (= cand row-ent))
          (progn
            (setq cand-score (bsps-row-score ent cand))
            (if (< cand-score best-score)
              (setq best-score cand-score))))
        (setq i (1+ i)))))
  ;; Allow ties so a full crossing can be cleaned one ROW at a time.
  (<= sel-score (+ best-score tol))
)

(defun bsps-side-to-row (pt row-ent trap-ent / row-pt trap-mid tangent n1 n2 out-dir side-dir)
  (setq row-pt (bsps-closest-point-to-ent pt row-ent))
  (setq trap-mid (bsps-midpt trap-ent))
  (setq tangent (bsps-tangent-at-point row-ent row-pt))
  (if (and row-pt trap-mid tangent)
    (progn
      ;; Positive = outside toward ROW-TRAP. Negative = road-side/inward.
      ;; Use ROW's local perpendicular, then orient it toward ROW-TRAP.
      ;; This avoids wrong signs near trap-line endpoints.
      (setq n1 (bsps-unit (list (- (cadr tangent)) (car tangent) 0.0)))
      (setq n2 (list (- (car n1)) (- (cadr n1)) 0.0))
      (if (>= (bsps-dot (bsps-vsub trap-mid row-pt) n1) 0.0)
        (setq out-dir n1)
        (setq out-dir n2))
      (setq side-dir (bsps-vsub pt row-pt))
      (if out-dir
        (bsps-dot side-dir out-dir)
        nil))
    nil)
)

(defun bsps-tangent-at-point (ent pt / etype ed p1 p2 cp param deriv)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")
      (setq ed (entget ent))
      (setq p1 (cdr (assoc 10 ed)))
      (setq p2 (cdr (assoc 11 ed)))
      (bsps-unit (bsps-vsub p2 p1)))

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
                (bsps-unit deriv)))))))
    (T nil))
)

(defun bsps-intersections-flat (ea eb extend-option / res)
  (setq res
    (vl-catch-all-apply
      'vlax-invoke
      (list (vlax-ename->vla-object ea)
            'IntersectWith
            (vlax-ename->vla-object eb)
            extend-option)))
  (if (vl-catch-all-error-p res)
    nil
    res)
)

(defun bsps-intersect-nearest (ea eb refpt extend-option / vals pt best bestd d)
  (setq vals (bsps-intersections-flat ea eb extend-option))
  (setq best nil)
  (setq bestd 999999999.0)
  (while (and vals (>= (length vals) 3))
    (setq pt (list (nth 0 vals) (nth 1 vals) (nth 2 vals)))
    (setq d (distance refpt pt))
    (if (< d bestd)
      (progn
        (setq bestd d)
        (setq best pt)))
    (setq vals (cdddr vals)))
  best
)

(defun bsps-set-line-endpoint (ent code pt / ed old)
  (setq ed (entget ent))
  (setq old (assoc code ed))
  (if old
    (entmod (subst (cons code (list (car pt) (cadr pt) 0.0)) old ed)))
  (entupd ent)
)

(princ "\n[BSPARSNAP] Loaded. Type BSPARSNAP to snap perpendicular PROPERTY LINE endpoints to ROW.")
(princ)
