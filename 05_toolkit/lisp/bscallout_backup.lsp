;;; ============================================================
;;; BSCALLOUT - Buried fiber callout with length
;;;
;;; BSCALLOUT     - Pick one buried fiber polyline, place callout.
;;; BSCALLOUT-AUTO- Auto-scan all BURIED FIBER IN DUCT, auto-place.
;;;
;;; Label format : "HDD BORE [N]' FIBER IN 2\" DUCT"
;;;   where [N] = polyline length rounded to nearest foot.
;;;
;;; Text height  : 5.0
;;; Layer        : CALLOUTS
;;;
;;; Implementation uses entmake for text (no MLEADER/LEADER command
;;; dependencies).  A LINE is drawn from the fiber to the text box
;;; as a simple leader.  Fully undo-safe.
;;;
;;; AUTO mode perpendicular direction:
;;;   Evaluates at polyline midpoint.  Perpendicular to tangent,
;;;   toward nearest ROW line.  Offset 10' from fiber.
;;; ============================================================

;;; ---------------------------------------------------------------
;;; BSCALLOUT - interactive
;;; ---------------------------------------------------------------
(defun c:BSCALLOUT ( / old-cmdecho old-layer
                       fiber-ent fiber-len callout-txt
                       label-pt arrow-pt
                       mid-pt tangent perp-dir)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "CALLOUTS" 7)

  (princ "\n[BSCALLOUT] Select a BURIED FIBER IN DUCT polyline: ")
  (setq fiber-ent (car (entsel "\nSelect buried fiber polyline: ")))

  (if (not fiber-ent)
    (progn
      (princ "\n[BSCALLOUT] Nothing selected. Aborting.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      ;; Measure polyline length
      (setq fiber-len (bsco-measure-length fiber-ent))
      (setq callout-txt (bsco-format-callout fiber-len))

      (princ (strcat "\n[BSCALLOUT] Length: " (rtos fiber-len 2 1)
        "' -> Label: " callout-txt))

      ;; Get label placement point
      (setvar "CMDECHO" 1)
      (setq label-pt (getpoint "\n[BSCALLOUT] Pick callout text location: "))
      (setvar "CMDECHO" 0)

      (if (not label-pt)
        (princ "\n[BSCALLOUT] Cancelled.")
        (progn
          ;; Arrow point = closest point on fiber to label
          (setq arrow-pt (bsco-closest-on-ent label-pt fiber-ent))

          ;; Draw leader line and text
          (bs-make-leader-line arrow-pt label-pt "CALLOUTS")
          (bs-make-text label-pt 5.0 "CALLOUTS" callout-txt)

          (princ (strcat "\n[BSCALLOUT] Placed: " callout-txt))
        )
      )

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; BSCALLOUT-AUTO - automatic for all buried fiber polylines
;;; ---------------------------------------------------------------
(defun c:BSCALLOUT-AUTO ( / old-cmdecho old-layer
                             ss i ent
                             fiber-len callout-txt
                             mid-pt tangent perp-dir
                             label-pt arrow-pt
                             row-ss placed-count skip-count)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "CALLOUTS" 7)

  (setq ss (ssget "X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "BURIED FIBER IN DUCT"))))

  (if (not ss)
    (progn
      (princ "\n[BSCALLOUT-AUTO] No BURIED FIBER IN DUCT polylines found.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (setq row-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROW"))))
      (setq placed-count 0 skip-count 0)

      (princ (strcat "\n[BSCALLOUT-AUTO] Processing "
        (itoa (sslength ss)) " buried fiber segments..."))

      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))

        (setq fiber-len (bsco-measure-length ent))
        (if (> fiber-len 0.01)
          (progn
            (setq callout-txt (bsco-format-callout fiber-len))

            ;; Get tangent and perpendicular at midpoint
            (setq mid-pt  (bs-ent-midpt ent))
            (setq tangent (bs-tangent-at-pt ent mid-pt))

            (if (and mid-pt tangent)
              (progn
                ;; Perpendicular direction toward nearest ROW
                (setq perp-dir (bsco-toward-row mid-pt tangent row-ss))

                ;; Label point: 10' perpendicular from midpoint
                (setq label-pt
                  (bs-vadd mid-pt (bs-vscale perp-dir 10.0)))

                ;; Leader from midpoint (on fiber) to label
                (bs-make-leader-line mid-pt label-pt "CALLOUTS")
                (bs-make-text label-pt 5.0 "CALLOUTS" callout-txt)

                (setq placed-count (1+ placed-count))
              )
              (setq skip-count (1+ skip-count))
            )
          )
          (setq skip-count (1+ skip-count))
        )
        (setq i (1+ i))
      )

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n")
      (princ "\n[BSCALLOUT-AUTO] ======== RESULTS ========")
      (princ (strcat "\n  Callouts placed : " (itoa placed-count)))
      (princ (strcat "\n  Skipped         : " (itoa skip-count)))
      (princ "\n[BSCALLOUT-AUTO] =========================")
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bsco-measure-length (ent / etype ep)
  ;; Return arc length of polyline, or 0.0 on failure.
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq ep (vl-catch-all-apply 'vlax-curve-getEndParam (list ent)))
      (if (vl-catch-all-error-p ep) 0.0
        (progn
          (setq len (vl-catch-all-apply 'vlax-curve-getDistAtParam (list ent ep)))
          (if (vl-catch-all-error-p len) 0.0 len))))
    ((= etype "LINE")
      (distance (cdr (assoc 10 (entget ent)))
                (cdr (assoc 11 (entget ent)))))
    (T 0.0)))

(defun bsco-format-callout (len-ft / rounded)
  ;; Format length as "HDD BORE N' FIBER IN 2\" DUCT"
  (setq rounded (fix (+ len-ft 0.5)))   ; round to nearest foot
  (strcat "HDD BORE " (itoa rounded) "' FIBER IN 2\" DUCT"))

(defun bsco-closest-on-ent (pt ent / etype cp)
  ;; Closest point on entity to pt.
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
      (if (vl-catch-all-error-p cp) pt cp))
    ((= etype "LINE")
      (bs-closest-on-seg (cdr (assoc 10 (entget ent)))
                         (cdr (assoc 11 (entget ent))) pt))
    (T pt)))

(defun bsco-toward-row (pt tangent row-ss / perp-l perp-r pt-l pt-r d-l d-r)
  ;; Return unit vector perpendicular to tangent, pointing toward nearest ROW line.
  ;; If no ROW found, returns left perpendicular by default.
  (setq perp-l (bs-vperp-left  (bs-vunit tangent)))
  (setq perp-r (bs-vperp-right (bs-vunit tangent)))

  (if (not row-ss)
    perp-l   ; default: left
    (progn
      ;; Sample points 10' each way
      (setq pt-l (bs-vadd pt (bs-vscale perp-l 10.0)))
      (setq pt-r (bs-vadd pt (bs-vscale perp-r 10.0)))
      ;; Find nearest ROW to each candidate point
      (setq d-l (bsco-dist-to-ss pt-l row-ss))
      (setq d-r (bsco-dist-to-ss pt-r row-ss))
      ;; Choose side closer to ROW
      (if (<= d-l d-r) perp-l perp-r))))

(defun bsco-dist-to-ss (pt ss / i best-dist ent d)
  ;; Minimum distance from pt to any entity in selection set ss.
  (setq best-dist 999999999.0)
  (setq i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (setq d (bs-dist-to-ent pt ent))
    (if (< d best-dist) (setq best-dist d))
    (setq i (1+ i)))
  best-dist)

(princ "\n[BSCALLOUT] Loaded.")
(princ "\n  BSCALLOUT      -> pick buried fiber -> pick label point -> places callout")
(princ "\n  BSCALLOUT-AUTO -> auto-places callouts on all BURIED FIBER IN DUCT polylines")
(princ)