;;; ============================================================
;;; BSAERIAL - Aerial fiber callout (no footage)
;;;
;;; BSAERIAL      - Pick one aerial/elash fiber, place callout.
;;; BSAERIAL-AUTO - Auto-scan all AERIAL FIBER and ELASH, auto-place.
;;;
;;; Label text:
;;;   AERIAL FIBER layer   -> "NEW AERIAL FIBER STRAND"
;;;   ELASH layer          -> "AERIAL FIBER ELASHED TO EXISTING"
;;;
;;; Text height  : 5.0
;;; Layer        : CALLOUTS
;;;
;;; No footage is included — aerial callouts never show length.
;;;
;;; AUTO mode perpendicular direction:
;;;   Evaluates at polyline midpoint, perpendicular to tangent,
;;;   toward nearest ROW line.  Offset 10' from fiber.
;;; ============================================================

;;; ---------------------------------------------------------------
;;; BSAERIAL - interactive
;;; ---------------------------------------------------------------
(defun c:BSAERIAL ( / old-cmdecho old-layer
                      fiber-ent fiber-layer callout-txt
                      label-pt arrow-pt)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "CALLOUTS" 7)

  (princ "\n[BSAERIAL] Select an AERIAL FIBER or ELASH polyline: ")
  (setq fiber-ent (car (entsel "\nSelect aerial fiber polyline: ")))

  (if (not fiber-ent)
    (progn
      (princ "\n[BSAERIAL] Nothing selected. Aborting.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (setq fiber-layer (cdr (assoc 8 (entget fiber-ent))))
      (setq callout-txt (bsae-label-for-layer fiber-layer))

      (princ (strcat "\n[BSAERIAL] Layer: " fiber-layer
        " -> Label: " callout-txt))

      (setvar "CMDECHO" 1)
      (setq label-pt (getpoint "\n[BSAERIAL] Pick callout text location: "))
      (setvar "CMDECHO" 0)

      (if (not label-pt)
        (princ "\n[BSAERIAL] Cancelled.")
        (progn
          (setq arrow-pt (bsae-closest-on-ent label-pt fiber-ent))
          (bs-make-leader-line arrow-pt label-pt "CALLOUTS")
          (bs-make-text label-pt 5.0 "CALLOUTS" callout-txt)
          (princ (strcat "\n[BSAERIAL] Placed: " callout-txt))
        )
      )

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; BSAERIAL-AUTO - automatic for all aerial and elash polylines
;;; ---------------------------------------------------------------
(defun c:BSAERIAL-AUTO ( / old-cmdecho old-layer
                            ss-aerial ss-elash
                            row-ss placed-count skip-count
                            i ent fiber-layer callout-txt
                            mid-pt tangent perp-dir label-pt)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "CALLOUTS" 7)

  (setq ss-aerial (ssget "X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "AERIAL FIBER"))))
  (setq ss-elash  (ssget "X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "ELASH"))))

  (if (not (or ss-aerial ss-elash))
    (progn
      (princ "\n[BSAERIAL-AUTO] No AERIAL FIBER or ELASH polylines found.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (setq row-ss (ssget "X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (8 . "ROW"))))
      (setq placed-count 0 skip-count 0)

      ;; Build combined list
      (setq all-fiber nil)
      (if ss-aerial
        (progn (setq i 0)
          (while (< i (sslength ss-aerial))
            (setq all-fiber (append all-fiber (list (ssname ss-aerial i))))
            (setq i (1+ i)))))
      (if ss-elash
        (progn (setq i 0)
          (while (< i (sslength ss-elash))
            (setq all-fiber (append all-fiber (list (ssname ss-elash i))))
            (setq i (1+ i)))))

      (princ (strcat "\n[BSAERIAL-AUTO] Processing "
        (itoa (length all-fiber)) " aerial fiber segments..."))

      (foreach ent all-fiber
        (setq fiber-layer (cdr (assoc 8 (entget ent))))
        (setq callout-txt (bsae-label-for-layer fiber-layer))

        (setq mid-pt  (bs-ent-midpt ent))
        (setq tangent (if mid-pt (bs-tangent-at-pt ent mid-pt) nil))

        (if (and mid-pt tangent)
          (progn
            (setq perp-dir (bsco-toward-row mid-pt tangent row-ss))
            (setq label-pt (bs-vadd mid-pt (bs-vscale perp-dir 10.0)))
            (bs-make-leader-line mid-pt label-pt "CALLOUTS")
            (bs-make-text label-pt 5.0 "CALLOUTS" callout-txt)
            (setq placed-count (1+ placed-count))
          )
          (setq skip-count (1+ skip-count))
        )
      )

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n")
      (princ "\n[BSAERIAL-AUTO] ======== RESULTS ========")
      (princ (strcat "\n  Callouts placed  : " (itoa placed-count)))
      (princ (strcat "\n  Skipped          : " (itoa skip-count)))
      (princ "\n[BSAERIAL-AUTO] =========================")
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bsae-label-for-layer (lname / )
  ;; Return the correct callout string for the given fiber layer name.
  (cond
    ((= (strcase lname) "ELASH")
      "AERIAL FIBER ELASHED TO EXISTING")
    (T
      "NEW AERIAL FIBER STRAND")))

(defun bsae-closest-on-ent (pt ent / etype cp)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
      (if (vl-catch-all-error-p cp) pt cp))
    ((= etype "LINE")
      (bs-closest-on-seg (cdr (assoc 10 (entget ent)))
                         (cdr (assoc 11 (entget ent))) pt))
    (T pt)))

(princ "\n[BSAERIAL] Loaded.")
(princ "\n  BSAERIAL      -> pick aerial fiber -> pick label point -> places callout")
(princ "\n  BSAERIAL-AUTO -> auto-places callouts on all AERIAL FIBER and ELASH polylines")
(princ)
