;;; ============================================================
;;; BSFILLET-ALL v3 - Autonomous ROW/EOP corner fillets (R = 25')
;;;
;;; Commands:
;;;   BSFILLET-ALL - Fillet valid ROW and ROADS-paved corners.
;;;
;;; Depends on: bs_helpers.lsp (loaded by bs_loader.lsp)
;;; AutoCAD Map 3D 2027
;;;
;;; Algorithm:
;;;   1. Collect supported linework on ROW and ROADS-paved.
;;;   2. Compare only entities from the same drawing family.
;;;   3. Require a real intersection where both entities terminate at the
;;;      corner, so mid-line crossings and T-intersections are skipped.
;;;   4. Build pick points from the intersection outward along each entity's
;;;      kept direction instead of using global midpoints.
;;;   5. Require a usable non-parallel angle before calling FILLET.
;;;
;;; Radius : 25' (matches manual workflow F R 25)
;;; Layers : ROW, ROADS-paved
;;; Safety : Native FILLET, explicit UNDO group, restored sysvars.
;;; ============================================================

(vl-load-com)

(defun bsf-layer-family (ent / lname upper)
  (if (and ent (entget ent))
    (progn
      (setq lname (cdr (assoc 8 (entget ent))))
      (setq upper (strcase lname))
      (cond
        ((= upper "ROW") "ROW")
        ((= upper "ROADS-PAVED") "EOP")
        (T nil)))
    nil))

(defun bsf-compatible-layer-p (ea eb / fa fb)
  ;; Keep ROW corners and EOP corners independent. Do not fillet ROW to EOP.
  (setq fa (bsf-layer-family ea))
  (setq fb (bsf-layer-family eb))
  (and fa fb (= fa fb)))

(defun bsf-curve-length (ent / etype ep len)
  (if (and ent (entget ent))
    (progn
      (setq etype (cdr (assoc 0 (entget ent))))
      (cond
        ((= etype "LINE")
          (distance (cdr (assoc 10 (entget ent)))
                    (cdr (assoc 11 (entget ent)))))
        ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
          (setq ep (vl-catch-all-apply 'vlax-curve-getEndParam (list ent)))
          (if (vl-catch-all-error-p ep)
            nil
            (progn
              (setq len (vl-catch-all-apply 'vlax-curve-getDistAtParam
                          (list ent ep)))
              (if (vl-catch-all-error-p len) nil len))))
        (T nil)))
    nil))

(defun bsf-curve-point-at-dist (ent dist / pt)
  (setq pt (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent dist)))
  (if (vl-catch-all-error-p pt) nil pt))

(defun bsf-line-corner-data (ent ipt tol pick-step min-leg / sp ep near-sp near-ep far len step pick tvec)
  (setq sp (cdr (assoc 10 (entget ent))))
  (setq ep (cdr (assoc 11 (entget ent))))
  (setq near-sp (<= (distance ipt sp) tol))
  (setq near-ep (<= (distance ipt ep) tol))
  (cond
    ((and near-sp near-ep) nil)
    ((not (or near-sp near-ep)) nil)
    (T
      (setq far (if near-sp ep sp))
      (setq len (distance ipt far))
      (if (< len min-leg)
        nil
        (progn
          (setq tvec (bs-vunit (bs-vsub far ipt)))
          (setq step (min pick-step (* len 0.5)))
          (setq pick (bs-vadd ipt (bs-vscale tvec step)))
          (if tvec (list pick tvec) nil))))))

(defun bsf-poly-corner-data (ent ipt tol pick-step min-leg / sp ep near-sp near-ep total step pick tvec)
  (setq sp (bs-ent-startpt ent))
  (setq ep (bs-ent-endpt ent))
  (setq near-sp (and sp (<= (distance ipt sp) tol)))
  (setq near-ep (and ep (<= (distance ipt ep) tol)))
  (cond
    ((and near-sp near-ep) nil)
    ((not (or near-sp near-ep)) nil)
    (T
      (setq total (bsf-curve-length ent))
      (if (or (not total) (< total min-leg))
        nil
        (progn
          (setq step (min pick-step (* total 0.5)))
          (setq pick
            (if near-sp
              (bsf-curve-point-at-dist ent step)
              (bsf-curve-point-at-dist ent (- total step))))
          (if pick
            (progn
              (setq tvec (bs-vunit (bs-vsub pick ipt)))
              (if tvec (list pick tvec) nil))
            nil))))))

(defun bsf-corner-data (ent ipt tol pick-step min-leg / etype)
  ;; Returns (pick-point outgoing-unit-vector) when ipt is a valid end corner.
  (if (and ent (entget ent))
    (progn
      (setq etype (cdr (assoc 0 (entget ent))))
      (cond
        ((= etype "LINE")
          (bsf-line-corner-data ent ipt tol pick-step min-leg))
        ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
          (bsf-poly-corner-data ent ipt tol pick-step min-leg))
        (T nil)))
    nil))

(defun bsf-angle-degrees (v1 v2 / dot perp)
  (setq dot (bs-vdot v1 v2))
  (if (> dot 1.0) (setq dot 1.0))
  (if (< dot -1.0) (setq dot -1.0))
  (setq perp (sqrt (max 0.0 (- 1.0 (* dot dot)))))
  (* 180.0 (/ (atan perp dot) pi)))

(defun bsf-valid-angle-p (v1 v2 min-angle max-angle / ang)
  (setq ang (bsf-angle-degrees v1 v2))
  (and (>= ang min-angle) (<= ang max-angle)))

(defun c:BSFILLET-ALL ( / *error* old-cmdecho old-osmode old-layer old-filletrad
                          undo-open row-ss eop-ss all-ents i j ea eb ipt
                          data-a data-b pick-a pick-b
                          fillet-count skip-count no-ipt-count layer-skip-count
                          dir-skip-count angle-skip-count
                          fillet-r ep-tol pick-step min-leg min-angle max-angle)

  (defun *error* (msg)
    (if undo-open
      (progn
        (command "_.UNDO" "_END")
        (setq undo-open nil)))
    (if old-filletrad (setvar "FILLETRAD" old-filletrad))
    (if old-osmode (setvar "OSMODE" old-osmode))
    (if old-layer (setvar "CLAYER" old-layer))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")))
      (princ (strcat "\n[BSFILLET-ALL] Error: " msg)))
    (princ))

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-osmode  (getvar "OSMODE"))
  (setq old-layer   (getvar "CLAYER"))
  (setq old-filletrad (getvar "FILLETRAD"))
  (setvar "CMDECHO" 0)
  (setvar "OSMODE" 0)

  (setq fillet-r 25.0)
  (setq ep-tol 5.0)
  (setq pick-step 10.0)
  (setq min-leg (+ fillet-r 1.0))
  (setq min-angle 15.0)
  (setq max-angle 165.0)

  (command "_.UNDO" "_BEGIN")
  (setq undo-open T)

  (princ "\n[BSFILLET-ALL] Collecting ROW and ROADS-paved entities...")

  (setq row-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROW"))))
  (setq eop-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROADS-paved"))))

  (if (not (or row-ss eop-ss))
    (princ "\n[BSFILLET-ALL] No ROW or ROADS-paved entities found. Aborting.")
    (progn
      (setq all-ents nil)
      (if row-ss
        (progn
          (setq i 0)
          (while (< i (sslength row-ss))
            (setq all-ents (append all-ents (list (ssname row-ss i))))
            (setq i (1+ i)))))
      (if eop-ss
        (progn
          (setq i 0)
          (while (< i (sslength eop-ss))
            (setq all-ents (append all-ents (list (ssname eop-ss i))))
            (setq i (1+ i)))))

      (princ
        (strcat "\n[BSFILLET-ALL] " (itoa (length all-ents))
          " entities. R=" (rtos fillet-r 2 1)
          "', endpoint tolerance=" (rtos ep-tol 2 1)
          "', angle window=" (rtos min-angle 2 0)
          "-" (rtos max-angle 2 0) " degrees."))

      (setvar "FILLETRAD" fillet-r)
      (command "_.FILLET" "R" (rtos fillet-r 2 1) "")

      (setq fillet-count 0)
      (setq skip-count 0)
      (setq no-ipt-count 0)
      (setq layer-skip-count 0)
      (setq dir-skip-count 0)
      (setq angle-skip-count 0)

      (setq i 0)
      (while (< i (1- (length all-ents)))
        (setq ea (nth i all-ents))
        (setq j (1+ i))
        (while (< j (length all-ents))
          (setq eb (nth j all-ents))
          (cond
            ((not (and (entget ea) (entget eb)))
              (setq skip-count (1+ skip-count)))

            ((not (bsf-compatible-layer-p ea eb))
              (setq layer-skip-count (1+ layer-skip-count)))

            (T
              (setq ipt (bs-intersect-first ea eb 0))
              (cond
                ((not ipt)
                  (setq no-ipt-count (1+ no-ipt-count)))

                (T
                  (setq data-a (bsf-corner-data ea ipt ep-tol pick-step min-leg))
                  (setq data-b (bsf-corner-data eb ipt ep-tol pick-step min-leg))
                  (cond
                    ((not (and data-a data-b))
                      (setq dir-skip-count (1+ dir-skip-count)))

                    ((not (bsf-valid-angle-p (cadr data-a) (cadr data-b)
                                             min-angle max-angle))
                      (setq angle-skip-count (1+ angle-skip-count)))

                    (T
                      (setq pick-a (car data-a))
                      (setq pick-b (car data-b))
                      (command "_.FILLET" pick-a pick-b)
                      (setq fillet-count (1+ fillet-count)))))))))

          (setq j (1+ j)))
        (setq i (1+ i)))

      (princ "\n")
      (princ "\n[BSFILLET-ALL] ======== RESULTS ========")
      (princ (strcat "\n  Fillets attempted      : " (itoa fillet-count)))
      (princ (strcat "\n  Pairs skipped by layer : " (itoa layer-skip-count)))
      (princ (strcat "\n  Pairs no intersection  : " (itoa no-ipt-count)))
      (princ (strcat "\n  Pairs skipped direction: " (itoa dir-skip-count)))
      (princ (strcat "\n  Pairs skipped angle    : " (itoa angle-skip-count)))
      (princ (strcat "\n  Pairs skipped stale    : " (itoa skip-count)))
      (princ (strcat "\n  Radius                 : " (rtos fillet-r 2 1) "'"))
      (princ "\n  All changes undo-able with one Ctrl+Z")
      (princ "\n[BSFILLET-ALL] ========================="))

  (if undo-open
    (progn
      (command "_.UNDO" "_END")
      (setq undo-open nil)))
  (setvar "FILLETRAD" old-filletrad)
  (setvar "OSMODE" old-osmode)
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ))

(princ "\n[BSFILLET-ALL] Loaded. Type BSFILLET-ALL to fillet valid ROW/EOP corners.")
(princ)
