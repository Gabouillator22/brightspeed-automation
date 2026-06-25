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
;;; Standalone bootstrap
;;;
;;; Keep these fallbacks local so the file can be APPLOADed directly
;;; without relying on bs_loader.lsp or bs_helpers.lsp.
;;; ---------------------------------------------------------------

(if (not (fboundp 'bs-ensure-layer))
  (defun bs-ensure-layer (lname lcolor / )
    (if (not (tblsearch "LAYER" lname))
      (command "_.LAYER" "_N" lname "_C" (itoa lcolor) lname ""))
    (command "_.LAYER" "_ON" lname "_T" lname "")
    (princ)))

(if (not (fboundp 'bs-vsub))
  (defun bs-vsub (p1 p2)
    (list (- (car p1) (car p2)) (- (cadr p1) (cadr p2)) 0.0)))

(if (not (fboundp 'bs-vadd))
  (defun bs-vadd (p1 p2)
    (list (+ (car p1) (car p2)) (+ (cadr p1) (cadr p2)) 0.0)))

(if (not (fboundp 'bs-vscale))
  (defun bs-vscale (v s)
    (list (* (car v) s) (* (cadr v) s) 0.0)))

(if (not (fboundp 'bs-vlen))
  (defun bs-vlen (v)
    (sqrt (+ (* (car v) (car v)) (* (cadr v) (cadr v))))))

(if (not (fboundp 'bs-vunit))
  (defun bs-vunit (v / len)
    (setq len (bs-vlen v))
    (if (> len 0.000001)
      (list (/ (car v) len) (/ (cadr v) len) 0.0)
      nil)))

(if (not (fboundp 'bs-vperp-left))
  (defun bs-vperp-left (v)
    (list (- (cadr v)) (car v) 0.0)))

(if (not (fboundp 'bs-vperp-right))
  (defun bs-vperp-right (v)
    (list (cadr v) (- (car v)) 0.0)))

(if (not (fboundp 'bs-midpt-2))
  (defun bs-midpt-2 (p1 p2)
    (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2)))

(if (not (fboundp 'bs-closest-on-seg))
  (defun bs-closest-on-seg (p1 p2 pt / dx dy len2 tv)
    (setq dx (- (car p2) (car p1))
          dy (- (cadr p2) (cadr p1))
          len2 (+ (* dx dx) (* dy dy)))
    (if (= len2 0.0) p1
      (progn
        (setq tv (/ (+ (* (- (car pt)  (car p1)) dx)
                       (* (- (cadr pt) (cadr p1)) dy)) len2))
        (if (< tv 0.0) (setq tv 0.0))
        (if (> tv 1.0) (setq tv 1.0))
        (list (+ (car p1) (* tv dx)) (+ (cadr p1) (* tv dy)) 0.0)))))

(if (not (fboundp 'bs-ent-midpt))
  (defun bs-ent-midpt (ent / etype)
    (setq etype (cdr (assoc 0 (entget ent))))
    (cond
      ((= etype "LINE")
        (bs-midpt-2 (cdr (assoc 10 (entget ent)))
                    (cdr (assoc 11 (entget ent)))))
      ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
        (vl-catch-all-apply 'vlax-curve-getPointAtParam
          (list ent (/ (vlax-curve-getEndParam ent) 2.0))))
      (T nil))))

(if (not (fboundp 'bs-closest-on-ent))
  (defun bs-closest-on-ent (ent pt / etype cp)
    (setq etype (cdr (assoc 0 (entget ent))))
    (cond
      ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
        (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
        (if (vl-catch-all-error-p cp) pt cp))
      ((= etype "LINE")
        (bs-closest-on-seg (cdr (assoc 10 (entget ent)))
                           (cdr (assoc 11 (entget ent))) pt))
      (T pt))))

(if (not (fboundp 'bs-dist-to-ent))
  (defun bs-dist-to-ent (pt ent / etype cp)
    (setq etype (cdr (assoc 0 (entget ent))))
    (distance pt
      (cond
        ((= etype "LINE")
          (bs-closest-on-seg (cdr (assoc 10 (entget ent)))
                              (cdr (assoc 11 (entget ent))) pt))
        ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
          (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
          (if (vl-catch-all-error-p cp) pt cp))
        (T pt)))))

(if (not (fboundp 'bs-dist-to-ss))
  (defun bs-dist-to-ss (pt ss / i best-dist ent d)
    (setq best-dist 999999999.0)
    (setq i 0)
    (while (< i (sslength ss))
      (setq ent (ssname ss i))
      (setq d (bs-dist-to-ent pt ent))
      (if (< d best-dist) (setq best-dist d))
      (setq i (1+ i)))
    best-dist))

(if (not (fboundp 'bs-tangent-at-pt))
  (defun bs-tangent-at-pt (ent pt / etype cp param deriv)
    (setq etype (cdr (assoc 0 (entget ent))))
    (cond
      ((= etype "LINE")
        (bs-vunit (bs-vsub (cdr (assoc 11 (entget ent)))
                           (cdr (assoc 10 (entget ent))))))
      ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
        (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
        (if (vl-catch-all-error-p cp) nil
          (progn
            (setq param (vl-catch-all-apply 'vlax-curve-getParamAtPoint (list ent cp)))
            (if (vl-catch-all-error-p param) nil
              (progn
                (setq deriv (vl-catch-all-apply 'vlax-curve-getFirstDeriv (list ent param)))
                (if (vl-catch-all-error-p deriv) nil (bs-vunit deriv)))))))
      (T nil))))

(if (not (fboundp 'bs-make-text))
  (defun bs-make-text (ins-pt height layer-name text-str / )
    (entmakex
      (list
        '(0 . "TEXT")
        (cons 8 layer-name)
        (cons 10 (list (car ins-pt) (cadr ins-pt) 0.0))
        (cons 11 (list (car ins-pt) (cadr ins-pt) 0.0))
        (cons 40 height)
        (cons 1 text-str)
        '(7 . "STANDARD")))))

(if (not (fboundp 'bs-make-line))
  (defun bs-make-line (p1 p2 layer-name / )
    (entmakex
      (list
        '(0 . "LINE")
        (cons 8 layer-name)
        (cons 10 (list (car p1) (cadr p1) 0.0))
        (cons 11 (list (car p2) (cadr p2) 0.0))))))

(if (not (fboundp 'bs-make-leader-line))
  (defun bs-make-leader-line (from-pt to-pt layer-name / )
    (bs-make-line from-pt to-pt layer-name)))

(if (not (fboundp 'bsco-toward-row))
  (defun bsco-toward-row (pt tangent row-ss / perp-l perp-r pt-l pt-r d-l d-r)
    (setq perp-l (bs-vperp-left  (bs-vunit tangent)))
    (setq perp-r (bs-vperp-right (bs-vunit tangent)))
    (if (not row-ss)
      perp-l
      (progn
        (setq pt-l (bs-vadd pt (bs-vscale perp-l 10.0)))
        (setq pt-r (bs-vadd pt (bs-vscale perp-r 10.0)))
        (setq d-l (bs-dist-to-ss pt-l row-ss))
        (setq d-r (bs-dist-to-ss pt-r row-ss))
        (if (<= d-l d-r) perp-l perp-r)))))

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
