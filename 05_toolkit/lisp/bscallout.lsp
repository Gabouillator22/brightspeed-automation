;;; ============================================================
;;; BSCALLOUT - Single-file buried fiber callout engine
;;;
;;; Commands:
;;;   BSCALLOUT      - Pick one buried fiber polyline, place callout.
;;;   BSCALLOUT-AUTO - Auto-place buried callouts, repeated per BORDER sheet.
;;;   BSCALLOUT-END-AUTO - Compatibility alias to BSCALLOUT-AUTO.
;;;
;;; Label format : "HDD BORE [N]' FIBER IN 2\" DUCT"
;;;   where [N] = polyline length rounded to nearest foot.
;;;
;;; Self-contained:
;;;   This file does not depend on bs_loader.lsp or bs_helpers.lsp.
;;;   It defines the helper functions it needs locally.
;;;
;;; Text height  : 5.0
;;; Layer        : CABLE CALLOUTS
;;;
;;; Implementation tries AutoCAD ActiveX Multileader creation first.
;;; If AutoCAD rejects AddMLeader, it falls back to entmake TEXT plus
;;; simple LINE leader geometry so the workflow can continue.
;;; ============================================================

(vl-load-com)

(setq *bsc-callout-layer* "CABLE CALLOUTS")
(setq *bsc-text-height* 5.0)
(setq *bsc-text-width-min* 85.0)
(setq *bsc-label-clear-pad* 6.0)
(setq *bsc-label-offsets* '(22.0 32.0 44.0 58.0 74.0 92.0 115.0))
(setq *bsc-label-shifts* '(0.0 20.0 -20.0 40.0 -40.0 65.0 -65.0 90.0 -90.0))
(setq *bsc-end-label-offset* 180.0)
(setq *bsc-sheet-label-offsets* '(180.0 150.0 120.0 90.0 60.0 45.0))
(setq *bsc-sheet-sample-step* 120.0)
(setq *bsc-leader-arrow-size* 7.5)
(setq *bsc-landing-dist* 5.0)
(setq *bsc-mleader-landing-gap* 5.0)
(setq *bsc-dup-radius* 28.0)
(setq *bsc-buried-layers* '("BURIED FIBER IN DUCT" "BURIED FIBER IN DUC" "BURIED FIBER" "PROPOSED BURIED" "UNDERGROUND"))
(setq *bsc-row-layers* '("ROW" "R/W" "RW" "EOP" "EDGE OF PAVEMENT" "PROPERTY LINES" "NC_PARCELS"))
(setq *bsc-ignore-blocker-layers* '("VIEWPORT IMAGE" "GEOMAP" "GMAP" "IMAGE" "BORDER" "BS-SHEET-PROPOSED" "BS-SHEET-LABELS"))

;;; ---------------------------------------------------------------
;;; BSCALLOUT - interactive
;;; ---------------------------------------------------------------
(defun c:BSCALLOUT ( / *error* old-cmdecho old-layer
                       fiber-ent fiber-len callout-txt
                       label-pt arrow-pt)

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))

  (defun *error* (msg)
    (if (= 8 (logand 8 (getvar "UNDOCTL")))
      (command-s "_.UNDO" "_END"))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-layer (setvar "CLAYER" old-layer))
    (if (and msg (/= (strcase (bsc-safe-str msg)) "*CANCEL*"))
      (princ (strcat "\n[BSCALLOUT] ERROR: " (bsc-safe-str msg))))
    (princ))

  (setvar "CMDECHO" 0)
  (command-s "_.UNDO" "_BEGIN")

  (bsc-ensure-layer *bsc-callout-layer* 7)

  (princ "\n[BSCALLOUT] Select a BURIED FIBER IN DUCT polyline: ")
  (setq fiber-ent (car (entsel "\nSelect buried fiber polyline: ")))

  (if (not fiber-ent)
    (progn
      (princ "\n[BSCALLOUT] Nothing selected. Aborting.")
      (command-s "_.UNDO" "_END")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (setq fiber-len (bsc-measure-length fiber-ent))
      (setq callout-txt (bsc-format-callout fiber-len))

      (princ (strcat "\n[BSCALLOUT] Length: " (rtos fiber-len 2 1)
        "' -> Label: " callout-txt))

      (setvar "CMDECHO" 1)
      (setq label-pt (getpoint "\n[BSCALLOUT] Pick callout text location: "))
      (setvar "CMDECHO" 0)

      (if (not label-pt)
        (princ "\n[BSCALLOUT] Cancelled.")
        (progn
          (setq arrow-pt (bsc-closest-on-ent label-pt fiber-ent))
          (bsc-make-callout arrow-pt label-pt callout-txt)
          (princ (strcat "\n[BSCALLOUT] Placed: " callout-txt))))

      (command-s "_.UNDO" "_END")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)))

  (princ))

;;; ---------------------------------------------------------------
;;; BSCALLOUT-AUTO - one simple buried-callout command
;;; ---------------------------------------------------------------
(defun c:BSCALLOUT-AUTO ( / *error* old-cmdecho old-layer
                             ent-list row-list sheet-list i ent result
                             entity-placed entity-skipped total-count
                             total-callouts)

  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))

  (defun *error* (msg)
    (if (= 8 (logand 8 (getvar "UNDOCTL")))
      (command-s "_.UNDO" "_END"))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-layer (setvar "CLAYER" old-layer))
    (if (and msg (/= (strcase (bsc-safe-str msg)) "*CANCEL*"))
      (princ (strcat "\n[BSCALLOUT-AUTO] ERROR: " (bsc-safe-str msg))))
    (princ))

  (setvar "CMDECHO" 0)
  (command-s "_.UNDO" "_BEGIN")

  (bsc-ensure-layer *bsc-callout-layer* 7)

  (setq ent-list (bsc-collect-buried-fibers))
  (setq total-count (length ent-list))

  (if (= total-count 0)
    (progn
      (princ "\n[BSCALLOUT-AUTO] No buried fiber entities found on supported buried layers.")
      (princ "\n[BSCALLOUT-AUTO] Supported layer names include Buried Fiber in Duct / BURIED FIBER IN DUCT / PROPOSED BURIED.")
      (command-s "_.UNDO" "_END")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (setq row-list (bsc-collect-row-lines))
      (setq sheet-list (bsc-collect-border-sheets))
      (setq entity-placed 0 entity-skipped 0 total-callouts 0 i 0)

      (princ (strcat "\n[BSCALLOUT-AUTO] Processing "
        (itoa total-count) " buried fiber segments..."))
      (princ (strcat "\n[BSCALLOUT-AUTO] BORDER rectangles found: "
        (itoa (length sheet-list))))

      (foreach ent ent-list
        (setq i (1+ i))
        (setq result (bsc-place-buried-sheet-callouts-simple ent row-list sheet-list))
        (princ
          (strcat "\n[BSCALLOUT-AUTO] Entity "
                  (bsc-safe-str (bsc-handle ent))
                  " len=" (rtos (nth 1 result) 2 1)
                  " sheets=" (itoa (nth 2 result))
                  " placed=" (itoa (nth 3 result))))
        (if (car result)
          (progn
            (setq entity-placed (1+ entity-placed))
            (setq total-callouts (+ total-callouts (nth 3 result)))
            (if (nth 4 result)
              (princ (strcat "\n[BSCALLOUT-AUTO]   " (bsc-safe-str (nth 4 result))))))
          (progn
            (setq entity-skipped (1+ entity-skipped))
            (princ (strcat "\n[BSCALLOUT-AUTO]   skipped: "
              (bsc-safe-str (nth 4 result)))))))

      (command-s "_.UNDO" "_END")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ "\n")
      (princ "\n[BSCALLOUT-AUTO] ======== RESULTS ========")
      (princ (strcat "\n  Fiber segments   : " (itoa total-count)))
      (princ (strcat "\n  BORDER sheets    : " (itoa (length sheet-list))))
      (princ (strcat "\n  Entities placed  : " (itoa entity-placed)))
      (princ (strcat "\n  Entities skipped : " (itoa entity-skipped)))
      (princ (strcat "\n  Callouts placed  : " (itoa total-callouts)))
      (princ "\n[BSCALLOUT-AUTO] =========================")))

  (princ))

;;; ---------------------------------------------------------------
;;; BSCALLOUT-END-AUTO - compatibility alias
;;; ---------------------------------------------------------------
(defun c:BSCALLOUT-END-AUTO ( / )
  (princ "\n[BSCALLOUT-END-AUTO] Alias -> running BSCALLOUT-AUTO.")
  (c:BSCALLOUT-AUTO))

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bsc-str-up (s)
  (if s (strcase (bsc-safe-str s)) ""))

(defun bsc-safe-str (value)
  (cond
    ((null value) "")
    ((eq (type value) 'STR) value)
    (T (vl-princ-to-string value))))

(defun bsc-member-ci (value values / v found)
  (setq found nil)
  (foreach v values
    (if (= (bsc-str-up value) (bsc-str-up v))
      (setq found T)))
  found)

(defun bsc-layer-name (ent)
  (cdr (assoc 8 (entget ent))))

(defun bsc-buried-layer-p (layer-name)
  (bsc-member-ci layer-name *bsc-buried-layers*))

(defun bsc-row-layer-p (layer-name)
  (bsc-member-ci layer-name *bsc-row-layers*))

(defun bsc-ignore-blocker-layer-p (layer-name)
  (bsc-member-ci layer-name *bsc-ignore-blocker-layers*))

(defun bsc-entity-line-like-p (ent / t0)
  (setq t0 (cdr (assoc 0 (entget ent))))
  (member t0 '("LINE" "LWPOLYLINE" "POLYLINE")))

(defun bsc-collect-buried-fibers ( / ss i ent out)
  ;; Scan line-like entities and filter layer names manually so mixed-case
  ;; template layers still work. ssget layer filters are too brittle here.
  (setq out nil)
  (setq ss (ssget "_X" '((0 . "LINE,LWPOLYLINE,POLYLINE"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (and (bsc-entity-line-like-p ent)
                 (bsc-buried-layer-p (bsc-layer-name ent))
                 (> (bsc-measure-length ent) 0.01))
          (setq out (cons ent out)))
        (setq i (1+ i)))))
  (reverse out))

(defun bsc-collect-row-lines ( / ss i ent out)
  ;; ROW/EOP/property lines are used only as placement blockers/side cues.
  (setq out nil)
  (setq ss (ssget "_X" '((0 . "LINE,LWPOLYLINE,POLYLINE"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (and (bsc-entity-line-like-p ent)
                 (bsc-row-layer-p (bsc-layer-name ent)))
          (setq out (cons ent out)))
        (setq i (1+ i)))))
  (reverse out))

(defun bsc-collect-border-sheets ( / ss i ent rect out)
  ;; Accepted BORDER rectangles define the sheet map for placement.
  (setq out nil)
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "BORDER"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (and (bsc-entity-line-like-p ent)
                 (= (bsc-str-up (bsc-layer-name ent)) "BORDER")
                 (setq rect (bsc-entity-rect ent)))
          (setq out (cons rect out)))
        (setq i (1+ i)))))
  (reverse out))

(defun bsc-ensure-layer (lname lcolor / )
  ;; Create the layer if needed, then force it ON and THAWED.
  (if (not (tblsearch "LAYER" lname))
    (command-s "_.LAYER" "_N" lname "_C" (itoa lcolor) lname ""))
  (command-s "_.LAYER" "_ON" lname "_T" lname "")
  (princ))

(defun bsc-vsub (p1 p2)
  (list (- (car p1) (car p2)) (- (cadr p1) (cadr p2)) 0.0))

(defun bsc-vadd (p1 p2)
  (list (+ (car p1) (car p2)) (+ (cadr p1) (cadr p2)) 0.0))

(defun bsc-vscale (v s)
  (list (* (car v) s) (* (cadr v) s) 0.0))

(defun bsc-vlen (v)
  (sqrt (+ (* (car v) (car v)) (* (cadr v) (cadr v)))))

(defun bsc-vunit (v / len)
  (setq len (bsc-vlen v))
  (if (> len 0.000001)
    (list (/ (car v) len) (/ (cadr v) len) 0.0)
    nil))

(defun bsc-vperp-left (v)
  (list (- (cadr v)) (car v) 0.0))

(defun bsc-vperp-right (v)
  (list (cadr v) (- (car v)) 0.0))

(defun bsc-midpt-2 (p1 p2)
  (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))

(defun bsc-ent-midpt (ent / len pt)
  ;; True half-distance midpoint for curves, not vertex-param midpoint.
  (setq len (bsc-measure-length ent))
  (if (> len 0.01)
    (progn
      (setq pt (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent (/ len 2.0))))
      (if (vl-catch-all-error-p pt)
        (bsc-closest-on-ent (list 0.0 0.0 0.0) ent)
        pt))
    (bsc-closest-on-ent (list 0.0 0.0 0.0) ent)))

(defun bsc-ent-startpt (ent / etype)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE") (cdr (assoc 10 (entget ent))))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (vl-catch-all-apply 'vlax-curve-getPointAtParam (list ent 0.0)))
    (T nil)))

(defun bsc-ent-endpt (ent / etype ep)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE") (cdr (assoc 11 (entget ent))))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq ep (vl-catch-all-apply 'vlax-curve-getEndParam (list ent)))
      (if (vl-catch-all-error-p ep) nil
        (vl-catch-all-apply 'vlax-curve-getPointAtParam (list ent ep))))
    (T nil)))

(defun bsc-closest-on-seg (p1 p2 pt / dx dy len2 tv)
  ;; Closest point on finite segment p1->p2 to pt.
  (setq dx (- (car p2) (car p1))
        dy (- (cadr p2) (cadr p1))
        len2 (+ (* dx dx) (* dy dy)))
  (if (= len2 0.0) p1
    (progn
      (setq tv (/ (+ (* (- (car pt)  (car p1)) dx)
                     (* (- (cadr pt) (cadr p1)) dy)) len2))
      (if (< tv 0.0) (setq tv 0.0))
      (if (> tv 1.0) (setq tv 1.0))
      (list (+ (car p1) (* tv dx)) (+ (cadr p1) (* tv dy)) 0.0))))

(defun bsc-dist-to-ent (pt ent / etype cp)
  ;; Perpendicular distance from pt to entity (finite).
  (setq etype (cdr (assoc 0 (entget ent))))
  (distance pt
    (cond
      ((= etype "LINE")
        (bsc-closest-on-seg (cdr (assoc 10 (entget ent)))
                            (cdr (assoc 11 (entget ent))) pt))
      ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
        (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
        (if (vl-catch-all-error-p cp) pt cp))
      (T pt))))

(defun bsc-tangent-at-pt (ent pt / len cp dist d1 d2 p1 p2)
  ;; Robust tangent from nearby points along curve. More reliable on LWPOLYLINE
  ;; vertices than getFirstDeriv alone.
  (setq len (bsc-measure-length ent))
  (if (<= len 0.01)
    nil
    (progn
      (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
      (if (vl-catch-all-error-p cp)
        nil
        (progn
          (setq dist (vl-catch-all-apply 'vlax-curve-getDistAtPoint (list ent cp)))
          (if (vl-catch-all-error-p dist)
            nil
            (progn
              (setq d1 (max 0.0 (- dist 5.0)))
              (setq d2 (min len (+ dist 5.0)))
              (if (< (- d2 d1) 0.1)
                (progn
                  (setq d1 (max 0.0 (- dist 15.0)))
                  (setq d2 (min len (+ dist 15.0)))))
              (setq p1 (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent d1)))
              (setq p2 (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent d2)))
              (if (or (vl-catch-all-error-p p1) (vl-catch-all-error-p p2))
                nil
                (bsc-vunit (bsc-vsub p2 p1))))))))))

(defun bsc-nearest-ent-in-ss (pt ss / i best-ent best-dist ent d)
  ;; Return entity in selection set ss closest to pt.
  (setq best-ent nil best-dist 999999999.0)
  (setq i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (setq d (bsc-dist-to-ent pt ent))
    (if (< d best-dist)
      (progn (setq best-dist d) (setq best-ent ent)))
    (setq i (1+ i)))
  best-ent)

(defun bsc-make-text (ins-pt height layer-name text-str / )
  ;; Create a TEXT entity via entmake. Returns new entity name.
  (setq text-str (bsc-safe-str text-str))
  (entmakex
    (list
      '(0 . "TEXT")
      (cons 8 layer-name)
      (cons 10 (list (car ins-pt) (cadr ins-pt) 0.0))
      (cons 11 (list (car ins-pt) (cadr ins-pt) 0.0))
      (cons 40 height)
      (cons 1 text-str)
      '(7 . "STANDARD"))))

(defun bsc-make-line (p1 p2 layer-name / )
  ;; Create a LINE entity via entmake. Returns new entity name.
  (entmakex
    (list
      '(0 . "LINE")
      (cons 8 layer-name)
      (cons 10 (list (car p1) (cadr p1) 0.0))
      (cons 11 (list (car p2) (cadr p2) 0.0)))))

(defun bsc-make-leader-line (from-pt to-pt layer-name / )
  ;; Draw a simple leader: line from from-pt to to-pt.
  (bsc-make-line from-pt to-pt layer-name))

(defun bsc-set-prop-safe (obj prop value / )
  (vl-catch-all-apply 'vlax-put-property (list obj prop value)))

(defun bsc-apply-mleader-box (obj / )
  ;; Use a filled text background without a visible frame, matching the
  ;; finished buried-fiber callout style.
  (bsc-set-prop-safe obj 'TextBackgroundFill :vlax-true)
  (bsc-set-prop-safe obj 'TextBackgroundScaleFactor 1.1)
  (bsc-set-prop-safe obj 'TextFrameDisplay :vlax-false)
  (bsc-set-prop-safe obj 'EnableFrameText :vlax-false)
  (bsc-set-prop-safe obj 'BackgroundFill :vlax-true)
  obj)

(defun bsc-format-callout (len-ft / rounded)
  ;; Format length as "HDD BORE N' FIBER IN 2\" DUCT".
  (setq rounded (fix (+ len-ft 0.5)))
  (strcat "HDD BORE " (itoa rounded) "' FIBER IN 2\" DUCT"))

(defun bsc-closest-on-ent (pt ent / etype cp)
  ;; Closest point on entity to pt.
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
      (if (vl-catch-all-error-p cp) pt cp))
    ((= etype "LINE")
      (bsc-closest-on-seg (cdr (assoc 10 (entget ent)))
                          (cdr (assoc 11 (entget ent))) pt))
    (T pt)))

(defun bsc-measure-length (ent / etype ep len)
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

(defun bsc-toward-row (pt tangent row-list / perp-l perp-r pt-l pt-r d-l d-r)
  ;; Return preferred perpendicular direction. If ROW/EOP/property references
  ;; exist, prefer the side closer to those references because the fiber usually
  ;; runs in that corridor. Candidate scoring still tests both sides.
  (setq perp-l (bsc-vperp-left  (bsc-vunit tangent)))
  (setq perp-r (bsc-vperp-right (bsc-vunit tangent)))

  (if (not row-list)
    perp-l
    (progn
      (setq pt-l (bsc-vadd pt (bsc-vscale perp-l 25.0)))
      (setq pt-r (bsc-vadd pt (bsc-vscale perp-r 25.0)))
      (setq d-l (bsc-dist-to-list pt-l row-list))
      (setq d-r (bsc-dist-to-list pt-r row-list))
      (if (<= d-l d-r) perp-l perp-r))))

(defun bsc-dist-to-list (pt ent-list / best-dist ent d)
  (setq best-dist 999999999.0)
  (foreach ent ent-list
    (setq d (bsc-dist-to-ent pt ent))
    (if (< d best-dist) (setq best-dist d)))
  best-dist)

(defun bsc-dist-to-ss (pt ss / i best-dist ent d)
  ;; Kept for backward compatibility with older bsco wrappers.
  (setq best-dist 999999999.0)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq d (bsc-dist-to-ent pt ent))
        (if (< d best-dist) (setq best-dist d))
        (setq i (1+ i)))))
  best-dist)

(defun bsc-point-p (pt)
  (and (listp pt)
       (>= (length pt) 2)
       (numberp (car pt))
       (numberp (cadr pt))))

(defun bsc-handle (ent)
  (cdr (assoc 5 (entget ent))))

(defun bsc-entity-tag (ent / data typ layer)
  (setq data (entget ent)
        typ (cdr (assoc 0 data))
        layer (cdr (assoc 8 data)))
  (strcat (bsc-safe-str typ) "@"
          (bsc-safe-str layer)))

(defun bsc-entity-rect (ent / obj res minp maxp mn mx)
  ;; Safe ActiveX bounding-box query.
  (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
  (if (or (null obj) (vl-catch-all-error-p obj))
    nil
    (progn
      (setq res (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'minp 'maxp)))
      (if (vl-catch-all-error-p res)
        nil
        (progn
          (setq mn (vl-catch-all-apply 'vlax-safearray->list (list minp)))
          (setq mx (vl-catch-all-apply 'vlax-safearray->list (list maxp)))
          (if (or (vl-catch-all-error-p mn)
                  (vl-catch-all-error-p mx)
                  (not (listp mn))
                  (not (listp mx)))
            nil
            (list (car mn) (cadr mn) (car mx) (cadr mx))))))))

(defun bsc-rect-intersects-p (a b / )
  (not (or (< (nth 2 a) (nth 0 b))
           (> (nth 0 a) (nth 2 b))
           (< (nth 3 a) (nth 1 b))
           (> (nth 1 a) (nth 3 b)))))

(defun bsc-rect-center (rect)
  (list (/ (+ (nth 0 rect) (nth 2 rect)) 2.0)
        (/ (+ (nth 1 rect) (nth 3 rect)) 2.0)
        0.0))

(defun bsc-point-in-rect-p (pt rect / x y)
  (setq x (car pt) y (cadr pt))
  (and (>= x (nth 0 rect))
       (<= x (nth 2 rect))
       (>= y (nth 1 rect))
       (<= y (nth 3 rect))))

(defun bsc-curve-sample-points (ent step / len dist pts p)
  ;; Sample the full buried segment at a fixed spacing for sheet-aware placement.
  (setq len (bsc-measure-length ent)
        pts nil)
  (if (and len (> len 0.01))
    (progn
      (if (or (null step) (<= step 0.01))
        (setq step *bsc-sheet-sample-step*))
      (setq dist 0.0)
      (while (<= dist len)
        (setq p (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent dist)))
        (if (not (vl-catch-all-error-p p))
          (setq pts (cons p pts)))
        (setq dist (+ dist step)))
      (setq p (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent len)))
      (if (not (vl-catch-all-error-p p))
        (setq pts (cons p pts)))))
  (reverse pts))

(defun bsc-points-in-rect (pts rect / out p)
  (setq out nil)
  (foreach p pts
    (if (bsc-point-in-rect-p p rect)
      (setq out (cons p out))))
  (reverse out))

(defun bsc-middle-point (pts / idx)
  (if pts
    (nth (fix (/ (length pts) 2.0)) pts)
    nil))

(defun bsc-sheet-rects-for-ent (ent-rect sheet-list / out sheet-rect)
  (setq out nil)
  (foreach sheet-rect sheet-list
    (if (bsc-rect-intersects-p ent-rect sheet-rect)
      (setq out (cons sheet-rect out))))
  (reverse out))

(defun bsc-text-box-width (text / )
  (setq text (bsc-safe-str text))
  (max *bsc-text-width-min*
       (* (strlen text) *bsc-text-height* 0.68)))

(defun bsc-text-box-height ( / )
  (* *bsc-text-height* 2.6))

(defun bsc-text-anchor-for-side (desired text side / width)
  ;; TEXT grows to the right from its insertion point. Move the anchor left
  ;; when the label needs to live on the left side of the corridor.
  (setq width (bsc-text-box-width text))
  (cond
    ((< (car side) -0.15)
      (list (- (car desired) width) (cadr desired) 0.0))
    ((> (car side) 0.15)
      desired)
    (T
      (list (- (car desired) (/ width 2.0)) (cadr desired) 0.0))))

(defun bsc-rect-from-textpt (textpt text / width height pad)
  (setq width (bsc-text-box-width text)
        height (bsc-text-box-height)
        pad *bsc-label-clear-pad*)
  (list
    (list (- (car textpt) pad) (- (cadr textpt) (+ (/ height 2.0) pad)) 0.0)
    (list (+ (car textpt) width pad) (- (cadr textpt) (+ (/ height 2.0) pad)) 0.0)
    (list (+ (car textpt) width pad) (+ (cadr textpt) (+ (/ height 2.0) pad)) 0.0)
    (list (- (car textpt) pad) (+ (cadr textpt) (+ (/ height 2.0) pad)) 0.0)))

(defun bsc-rect-window (rect / xs ys)
  (setq xs (mapcar 'car rect)
        ys (mapcar 'cadr rect))
  (list
    (list (apply 'min xs) (apply 'min ys) 0.0)
    (list (apply 'max xs) (apply 'max ys) 0.0)))

(defun bsc-candidate-blockers (rect source-ent / win ss i ent blockers er rwin)
  (setq win (bsc-rect-window rect)
        blockers nil)
  (setq ss
    (ssget "_C" (car win) (cadr win)
      '((0 . "TEXT,MTEXT,DIMENSION,LINE,LWPOLYLINE,POLYLINE,INSERT,LEADER,MULTILEADER,ARC,CIRCLE,ELLIPSE,SPLINE,HATCH"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (and (/= (bsc-handle ent) (bsc-handle source-ent))
                 (not (bsc-ignore-blocker-layer-p (bsc-layer-name ent))))
          (progn
            (setq er (bsc-entity-rect ent))
            (setq rwin (append (car win) (cadr win)))
            (setq rwin (list (nth 0 rwin) (nth 1 rwin) (nth 3 rwin) (nth 4 rwin)))
            (if (or (null er) (bsc-rect-intersects-p rwin er))
              (setq blockers (append blockers (list (bsc-entity-tag ent)))))))
        (setq i (1+ i)))))
  blockers)

(defun bsc-object-text (ent / obj txt data)
  (setq obj (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
  (if (or (null obj) (vl-catch-all-error-p obj))
    (setq txt nil)
    (setq txt (vl-catch-all-apply 'vlax-get-property (list obj 'TextString))))
  (if (or (null txt) (vl-catch-all-error-p txt))
    (progn
      (setq data (entget ent))
      (setq txt (or (cdr (assoc 1 data)) (cdr (assoc 304 data))))))
  txt)

(defun bsc-object-point (ent / data rect)
  (setq data (entget ent))
  (cond
    ((cdr (assoc 10 data)))
    ((setq rect (bsc-entity-rect ent))
      (list (/ (+ (nth 0 rect) (nth 2 rect)) 2.0)
            (/ (+ (nth 1 rect) (nth 3 rect)) 2.0)
            0.0))
    (T nil)))

(defun bsc-existing-callout-p (text pt / ss i ent txt ept found layer)
  ;; Detect existing identical generated/manual callout near source point.
  ;; This prevents repeated BSCALLOUT-AUTO runs from stacking duplicates.
  (setq ss (ssget "_X" '((0 . "TEXT,MTEXT,MULTILEADER,MLEADER")))
        found nil)
  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i)
              layer (bsc-layer-name ent)
              txt (bsc-object-text ent)
              ept (bsc-object-point ent))
        (if (and txt ept
                 (or (= (bsc-str-up layer) "CALLOUTS")
                     (= (bsc-str-up layer) "CABLE CALLOUTS"))
                 (= (bsc-str-up txt) (bsc-str-up text))
                 (<= (distance ept pt) *bsc-dup-radius*))
          (setq found T))
        (setq i (1+ i)))))
  found)

(defun bsc-blocker-summary (blockers / txt)
  (setq txt (if blockers (car blockers) ""))
  (if blockers
    (progn
      (foreach b (cdr blockers)
        (if (< (strlen txt) 80)
          (setq txt (strcat txt ", " (bsc-safe-str b)))))
      (if (> (length blockers) 3)
        (setq txt (strcat txt ", ...")))
      (strcat (itoa (length blockers)) " blockers: " txt))
    "no blockers"))

(defun bsc-join-messages (items / out)
  (setq out "")
  (foreach item items
    (if (/= (bsc-safe-str item) "")
      (if (= out "")
        (setq out (bsc-safe-str item))
        (setq out (strcat out "; " (bsc-safe-str item))))))
  out)

(defun bsc-leader-landing-point (arrow-pt text-pt text / width)
  (setq width (bsc-text-box-width text))
  (if (< (car arrow-pt) (car text-pt))
    (list (car text-pt) (cadr text-pt) 0.0)
    (list (+ (car text-pt) width) (cadr text-pt) 0.0)))

(defun bsc-mleader-landing-point (arrow-pt text-pt / unit)
  ;; Match the Python-tested helper: arrow tip on fiber, short landing before text.
  (setq unit (bsc-vunit (bsc-vsub text-pt arrow-pt)))
  (if unit
    (bsc-vadd text-pt (bsc-vscale unit (- *bsc-mleader-landing-gap*)))
    text-pt))

(defun bsc-draw-arrowhead (arrow-pt landing layer / dir back perp p1 p2 size)
  (setq size *bsc-leader-arrow-size*)
  (setq dir (bsc-vunit (bsc-vsub landing arrow-pt)))
  (if dir
    (progn
      (setq back (bsc-vscale dir (- size))
            perp (bsc-vscale (bsc-vperp-left dir) (* size 0.6))
            p1 (bsc-vadd arrow-pt (bsc-vadd back perp))
            p2 (bsc-vadd arrow-pt (bsc-vadd back (bsc-vscale perp -1.0))))
      (bsc-make-line arrow-pt p1 layer)
      (bsc-make-line arrow-pt p2 layer)))
  ) ;; close bsc-draw-arrowhead

(defun bsc-draw-callout-leader (arrow-pt text-pt text layer / landing)
  (setq landing (bsc-leader-landing-point arrow-pt text-pt text))
  (bsc-make-line arrow-pt landing layer)
  (bsc-draw-arrowhead arrow-pt landing layer)
  landing)

(defun bsc-make-mleader (arrow-pt text-pt text / doc ms arr arr2 obj landing)
  (setq text (bsc-safe-str text))
  (bsc-ensure-layer *bsc-callout-layer* 7)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms  (vla-get-ModelSpace doc))
  (setq landing (bsc-mleader-landing-point arrow-pt text-pt))
  (setq arr (vlax-make-safearray vlax-vbDouble '(0 . 8)))
  (vlax-safearray-fill arr
    (list (car arrow-pt) (cadr arrow-pt) 0.0
          (car landing)  (cadr landing)  0.0
          (car text-pt)  (cadr text-pt)  0.0))
  (setq obj (vl-catch-all-apply 'vla-AddMLeader (list ms arr 0)))
  (if (vl-catch-all-error-p obj)
    (progn
      (setq arr2 (vlax-make-safearray vlax-vbDouble '(0 . 5)))
      (vlax-safearray-fill arr2
        (list (car arrow-pt) (cadr arrow-pt) 0.0
              (car text-pt)  (cadr text-pt)  0.0))
      (setq obj (vl-catch-all-apply 'vla-AddMLeader (list ms arr2 0)))))
  (if (vl-catch-all-error-p obj)
    nil
    (progn
      (bsc-set-prop-safe obj 'Layer *bsc-callout-layer*)
      (bsc-set-prop-safe obj 'TextString text)
      (bsc-set-prop-safe obj 'TextHeight *bsc-text-height*)
      (bsc-set-prop-safe obj 'ArrowheadSize *bsc-leader-arrow-size*)
      (bsc-set-prop-safe obj 'ArrowSymbol "Closed filled")
      (bsc-set-prop-safe obj 'LandingGap *bsc-landing-dist*)
      (bsc-set-prop-safe obj 'DoglegLength *bsc-landing-dist*)
      (bsc-apply-mleader-box obj)
      obj)))

(defun bsc-make-callout (arrow-pt text-pt text / obj)
  (setq obj (bsc-make-mleader arrow-pt text-pt text))
  (if obj
    obj
    (progn
      (bsc-draw-callout-leader arrow-pt text-pt text *bsc-callout-layer*)
      (bsc-make-text text-pt *bsc-text-height* *bsc-callout-layer* text))))

(defun bsc-build-label-candidates (ent text arrow preferred-side / tangent side-list side-priority candidates cur-side off shift desired textpt rect blockers score)
  (setq tangent (bsc-tangent-at-pt ent arrow))
  (if (not tangent)
    (setq tangent (list 1.0 0.0 0.0)))
  (if (not (bsc-point-p preferred-side))
    (setq preferred-side (list 1.0 0.0 0.0)))
  (setq side-list (list preferred-side (bsc-vscale preferred-side -1.0))
        candidates nil
        side-priority 0)
  (foreach cur-side side-list
    (foreach off *bsc-label-offsets*
      (foreach shift *bsc-label-shifts*
        (setq desired (bsc-vadd
                        (bsc-vadd arrow (bsc-vscale cur-side off))
                        (bsc-vscale tangent shift)))
        (setq textpt (bsc-text-anchor-for-side desired text cur-side))
        (setq rect (bsc-rect-from-textpt textpt text))
        (setq blockers (bsc-candidate-blockers rect ent))
        (setq score (+ (* (length blockers) 1000000)
                       (* side-priority 100000)
                       (* off 100)
                       (abs shift)))
        (setq candidates
          (cons (list score cur-side off shift desired textpt rect blockers) candidates)))))
    (setq side-priority (1+ side-priority)))
  (vl-sort candidates '(lambda (a b) (< (car a) (car b))))

(defun bsc-place-buried-callout (ent row-list / len text arrow tangent preferred candidates chosen fallback blockers reason textpt)
  (setq len (bsc-measure-length ent))
  (if (<= len 0.01)
    (list nil "zero-length buried segment")
    (progn
      (setq text (bsc-format-callout len)
            arrow (bsc-ent-midpt ent))
      (if (not (bsc-point-p arrow))
        (setq arrow (bsc-closest-on-ent (list 0.0 0.0 0.0) ent)))
      (if (not (bsc-point-p arrow))
        (list nil "unable to resolve source point on fiber")
        (progn
          (setq tangent (bsc-tangent-at-pt ent arrow))
          (if (not tangent)
            (setq tangent (list 1.0 0.0 0.0)))
          (setq preferred
            (if row-list
              (bsc-toward-row arrow tangent row-list)
              (bsc-vperp-left tangent)))
          (setq candidates (bsc-build-label-candidates ent text arrow preferred))
          (setq chosen nil fallback nil reason nil)
          (foreach cand candidates
            (setq blockers (nth 7 cand))
            (if (null fallback)
              (setq fallback cand))
            (if (and (null blockers) (not chosen))
              (setq chosen cand))
            (if (and blockers (not reason))
              (setq reason (bsc-blocker-summary blockers))))
          (if (not chosen)
            (setq chosen fallback))
          (if chosen
            (progn
              (setq textpt (nth 5 chosen))
              (if (bsc-existing-callout-p text arrow)
                (list nil "matching callout already exists near source segment")
                (progn
                  (bsc-make-callout arrow textpt text)
                  (if (nth 7 chosen)
                    (list T (strcat "placed with fallback; " (bsc-blocker-summary (nth 7 chosen))))
                    (list T (strcat "placed cleanly at offset " (rtos (nth 2 chosen) 2 1)
                                    " shift " (rtos (nth 3 chosen) 2 1)))))))
            (list nil
              (if reason
                (strcat "no label candidate; " reason)
                "no label candidate"))))))))

(defun bsc-place-buried-end-callout (ent row-list / len text arrow tangent preferred candidates chosen fallback blockers reason textpt)
  (setq len (bsc-measure-length ent))
  (if (<= len 0.01)
    (list nil "zero-length buried segment")
    (progn
      (setq text (bsc-format-callout len)
            arrow (bsc-ent-endpt ent))
      (if (not (bsc-point-p arrow))
        (setq arrow (bsc-ent-midpt ent)))
      (if (not (bsc-point-p arrow))
        (list nil "unable to resolve endpoint on fiber")
        (progn
          (setq tangent (bsc-tangent-at-pt ent arrow))
          (if (not tangent)
            (setq tangent (list 1.0 0.0 0.0)))
          (setq preferred
            (if row-list
              (bsc-toward-row arrow tangent row-list)
              (bsc-vperp-left tangent)))
          (setq candidates (bsc-build-label-candidates ent text arrow preferred))
          (setq chosen nil fallback nil reason nil)
          (foreach cand candidates
            (setq blockers (nth 7 cand))
            (if (null fallback)
              (setq fallback cand))
            (if (and (null blockers) (not chosen))
              (setq chosen cand))
            (if (and blockers (not reason))
              (setq reason (bsc-blocker-summary blockers))))
          (if (not chosen)
            (setq chosen fallback))
          (if chosen
            (progn
              (setq textpt (nth 5 chosen))
              (if (bsc-existing-callout-p text arrow)
                (list nil "matching callout already exists near fiber endpoint")
                (progn
                  (bsc-make-callout arrow textpt text)
                  (if (nth 7 chosen)
                    (list T (strcat "endpoint arrow placed with fallback; " (bsc-blocker-summary (nth 7 chosen))))
                    (list T (strcat "endpoint arrow placed cleanly at offset " (rtos (nth 2 chosen) 2 1)
                                    " shift " (rtos (nth 3 chosen) 2 1)))))))
            (list nil
              (if reason
                (strcat "no endpoint label candidate; " reason)
                "no endpoint label candidate"))))))))

(defun bsc-label-point-for-sheet (arrow dir sheet-rect row-list / center preferred side-candidates offsets cand side idx)
  (setq center (bsc-rect-center sheet-rect)
        preferred (if row-list (bsc-toward-row arrow dir row-list) (bsc-vperp-left dir))
        side-candidates (list preferred (bsc-vscale preferred -1.0))
        offsets *bsc-sheet-label-offsets*
        cand nil)
  (foreach side side-candidates
    (if (not cand)
      (progn
        (setq idx 0)
        (while (and (< idx (length offsets)) (not cand))
          (setq cand (bsc-vadd arrow (bsc-vscale side (nth idx offsets))))
          (if (not (bsc-point-in-rect-p cand sheet-rect))
            (setq cand nil))
          (setq idx (1+ idx))))))
  (if cand
    cand
    (progn
      (setq cand (bsc-vadd arrow (bsc-vscale (bsc-vunit (bsc-vsub center arrow)) *bsc-end-label-offset*)))
      (if (bsc-point-in-rect-p cand sheet-rect)
        cand
        center))))

(defun bsc-sheet-anchor-for-ent (ent sheet-rect / samples inside anchor fallback)
  ;; Use the middle sampled point that falls inside the sheet rect.
  (setq samples (bsc-curve-sample-points ent *bsc-sheet-sample-step*)
        inside (bsc-points-in-rect samples sheet-rect)
        anchor (bsc-middle-point inside)
        fallback nil)
  (if anchor
    (list anchor nil)
    (if (bsc-rect-intersects-p (bsc-entity-rect ent) sheet-rect)
      (list (bsc-closest-on-ent (bsc-rect-center sheet-rect) ent) T)
      nil)))

(defun bsc-place-buried-sheet-callouts-simple (ent row-list sheet-list / len text ent-rect target-sheets
                                                   sheet-rect anchor-info anchor tangent dir
                                                   labelpt placed sheet-hits warnings used-fallback)
  ;; One simple path:
  ;; - no BORDER -> one global midpoint callout
  ;; - with BORDER -> one callout per intersecting sheet, using the middle
  ;;   visible sampled point inside that sheet as the arrow anchor
  (setq len (bsc-measure-length ent))
  (if (<= len 0.01)
    (list nil len 0 0 "zero-length buried segment")
    (progn
      (setq text (bsc-format-callout len)
            placed 0
            warnings nil)
      (if (null sheet-list)
        (progn
          (if (bsc-existing-callout-p text (bsc-ent-midpt ent))
            (list nil len 0 0 "matching global callout already exists")
            (progn
              (setq anchor (bsc-ent-midpt ent))
              (setq tangent (bsc-tangent-at-pt ent anchor))
              (if (not tangent)
                (setq tangent (list 1.0 0.0 0.0)))
              (setq dir
                (if row-list
                  (bsc-toward-row anchor tangent row-list)
                  (bsc-vperp-left tangent)))
              (setq labelpt (bsc-text-anchor-for-side
                              (bsc-vadd anchor (bsc-vscale dir *bsc-end-label-offset*))
                              text dir))
              (if (bsc-make-callout anchor labelpt text)
                (list T len 0 1 "no BORDER sheets found; used global midpoint placement")
                (list nil len 0 0 "failed to create global callout object")))))
        (progn
          (setq ent-rect (bsc-entity-rect ent)
                target-sheets (if ent-rect (bsc-sheet-rects-for-ent ent-rect sheet-list) nil)
                sheet-hits (length target-sheets))
          (if (= sheet-hits 0)
            (list nil len 0 0 "no intersecting BORDER sheet found")
            (progn
              (foreach sheet-rect target-sheets
                (setq anchor-info (bsc-sheet-anchor-for-ent ent sheet-rect))
                (if anchor-info
                  (progn
                    (setq anchor (car anchor-info)
                          used-fallback (cadr anchor-info)
                          tangent (bsc-tangent-at-pt ent anchor))
                    (if (not tangent)
                      (setq tangent (list 1.0 0.0 0.0)))
                    (setq labelpt (bsc-label-point-for-sheet anchor tangent sheet-rect row-list))
                    (if (bsc-existing-callout-p text anchor)
                      (setq warnings (cons "duplicate near sheet anchor" warnings))
                      (if (bsc-make-callout anchor labelpt text)
                        (progn
                          (setq placed (1+ placed))
                          (if used-fallback
                            (setq warnings (cons "used nearest-point fallback for one sheet anchor" warnings))))
                        (setq warnings (cons "failed to create one sheet callout" warnings)))))
                  (setq warnings (cons "sheet intersection found but no anchor resolved" warnings))))
              (if (> placed 0)
                (list T len sheet-hits placed
                      (if warnings
                        (bsc-join-messages (reverse warnings))
                        nil))
                (list nil len sheet-hits 0
                      (if warnings
                        (bsc-join-messages (reverse warnings))
                        "no sheet callouts placed"))))))))))

(defun bsc-place-buried-end-callout-simple (ent row-list / len text arrow start dir labelpt)
  (setq len (bsc-measure-length ent))
  (if (<= len 0.01)
    (list nil "zero-length buried segment")
    (progn
      (setq text (bsc-format-callout len)
            arrow (bsc-ent-endpt ent)
            start (bsc-ent-startpt ent))
      (if (not (bsc-point-p arrow))
        (setq arrow (bsc-ent-midpt ent)))
      (if (not (bsc-point-p arrow))
        (list nil "unable to resolve endpoint on fiber")
        (progn
          (setq dir nil)
          (if (and (bsc-point-p start) (bsc-point-p arrow))
            (setq dir (bsc-vsub arrow start))
            (setq dir (bsc-tangent-at-pt ent arrow)))
          (setq dir (bsc-vunit dir))
          (if (null dir)
            (setq dir (list 1.0 0.0 0.0)))
          (setq labelpt
            (bsc-vadd arrow (bsc-vscale (bsc-vperp-left dir) *bsc-end-label-offset*)))
          (if (bsc-make-callout arrow labelpt text)
            (list T (strcat "endpoint callout placed at " (rtos len 2 1) "'"))
            (list nil "failed to create callout object")))))))

;; Compatibility aliases for the existing loader path.
(defun bsco-measure-length (ent)
  (bsc-measure-length ent))

(defun bsco-format-callout (len-ft)
  (bsc-format-callout len-ft))

(defun bsco-closest-on-ent (pt ent)
  (bsc-closest-on-ent pt ent))

(defun bsco-toward-row (pt tangent row-ss)
  (bsc-toward-row pt tangent row-ss))

(defun bsco-dist-to-ss (pt ss)
  (bsc-dist-to-ss pt ss))

(princ "\n[BSCALLOUT] Loaded single-file standalone callout engine. No loader required.")
(princ "\n  BSCALLOUT      -> pick one buried fiber -> pick label point -> places callout")
(princ "\n  BSCALLOUT-AUTO -> one simple buried auto-callout command, repeated per BORDER sheet")
(princ "\n  BSCALLOUT-END-AUTO -> compatibility alias to BSCALLOUT-AUTO")
(princ)
