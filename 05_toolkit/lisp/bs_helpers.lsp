;;; ============================================================
;;; BS_HELPERS - Shared math and entity helpers
;;; Prefix: bs-
;;; Must be loaded FIRST by bs_loader.lsp before command files.
;;;
;;; Provides:
;;;   Layer management   : bs-ensure-layer, bs-force-layer
;;;   Vector math        : bs-vsub, bs-vadd, bs-vscale, bs-vdot,
;;;                        bs-vlen, bs-vunit, bs-vperp-left, bs-vperp-right
;;;   Point utilities    : bs-midpt-2, bs-pt-at
;;;   Entity geometry    : bs-ent-midpt, bs-ent-startpt, bs-ent-endpt
;;;   Distance           : bs-closest-on-seg, bs-dist-to-ent
;;;   Tangent direction  : bs-tangent-at-pt
;;;   Intersections      : bs-intersect-first, bs-intersect-all,
;;;                        bs-near-endpoint-p
;;;   Selection          : bs-nearest-ent-in-ss
;;;   Entity creation    : bs-make-text, bs-make-leader-line
;;;   Formatting         : bs-format-station
;;;   LWPOLYLINE editing : bs-replace-nth-vertex
;;; ============================================================

(vl-load-com)

;;; ---------------------------------------------------------------
;;; Layer management
;;; ---------------------------------------------------------------

(defun bs-ensure-layer (lname lcolor / )
  ;; Create layer if it doesn't exist, then force ON and THAWED.
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "C" (itoa lcolor) lname ""))
  (command "_.LAYER" "ON" lname "T" lname "")
  (princ))

(defun bs-force-layer (ent lname / elist)
  ;; Move entity to a layer via entmod (no delete, undo-safe).
  (if (and ent (entget ent))
    (progn
      (setq elist (entget ent))
      (entmod (subst (cons 8 lname) (assoc 8 elist) elist))
      (entupd ent)))
  (princ))

;;; ---------------------------------------------------------------
;;; Vector math (2D, z kept as 0.0)
;;; ---------------------------------------------------------------

(defun bs-vsub (p1 p2)
  (list (- (car p1) (car p2)) (- (cadr p1) (cadr p2)) 0.0))

(defun bs-vadd (p1 p2)
  (list (+ (car p1) (car p2)) (+ (cadr p1) (cadr p2)) 0.0))

(defun bs-vscale (v s)
  (list (* (car v) s) (* (cadr v) s) 0.0))

(defun bs-vdot (v1 v2)
  (+ (* (car v1) (car v2)) (* (cadr v1) (cadr v2))))

(defun bs-vlen (v)
  (sqrt (+ (* (car v) (car v)) (* (cadr v) (cadr v)))))

(defun bs-vunit (v / len)
  (setq len (bs-vlen v))
  (if (> len 0.000001)
    (list (/ (car v) len) (/ (cadr v) len) 0.0)
    nil))

(defun bs-vperp-left (v)
  ;; 90-degree CCW rotation of a unit vector.
  (list (- (cadr v)) (car v) 0.0))

(defun bs-vperp-right (v)
  ;; 90-degree CW rotation of a unit vector.
  (list (cadr v) (- (car v)) 0.0))

;;; ---------------------------------------------------------------
;;; Point utilities
;;; ---------------------------------------------------------------

(defun bs-midpt-2 (p1 p2)
  (mapcar '(lambda (a b) (/ (+ a b) 2.0)) p1 p2))

(defun bs-pt-at (p1 p2 tv)
  ;; Interpolate between p1 and p2 at parameter tv (0.0=p1, 1.0=p2).
  (list (+ (car p1) (* tv (- (car p2) (car p1))))
        (+ (cadr p1) (* tv (- (cadr p2) (cadr p1))))
        0.0))

;;; ---------------------------------------------------------------
;;; Entity geometry
;;; ---------------------------------------------------------------

(defun bs-ent-midpt (ent / etype)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE")
      (bs-midpt-2 (cdr (assoc 10 (entget ent)))
                  (cdr (assoc 11 (entget ent)))))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (vl-catch-all-apply 'vlax-curve-getPointAtParam
        (list ent (/ (vlax-curve-getEndParam ent) 2.0))))
    (T nil)))

(defun bs-ent-startpt (ent / etype)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE") (cdr (assoc 10 (entget ent))))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (vl-catch-all-apply 'vlax-curve-getPointAtParam (list ent 0.0)))
    (T nil)))

(defun bs-ent-endpt (ent / etype ep)
  (setq etype (cdr (assoc 0 (entget ent))))
  (cond
    ((= etype "LINE") (cdr (assoc 11 (entget ent))))
    ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
      (setq ep (vl-catch-all-apply 'vlax-curve-getEndParam (list ent)))
      (if (vl-catch-all-error-p ep) nil
        (vl-catch-all-apply 'vlax-curve-getPointAtParam (list ent ep))))
    (T nil)))

;;; ---------------------------------------------------------------
;;; Distance and closest-point helpers
;;; ---------------------------------------------------------------

(defun bs-closest-on-seg (p1 p2 pt / dx dy len2 tv)
  ;; Closest point on finite line segment p1->p2 to pt.
  ;; Uses dot-product projection, clamped to [0,1].
  (setq dx (- (car p2) (car p1))
        dy (- (cadr p2) (cadr p1))
        len2 (+ (* dx dx) (* dy dy)))
  (if (= len2 0.0) p1
    (progn
      (setq tv (/ (+ (* (- (car pt)  (car p1))  dx)
                     (* (- (cadr pt) (cadr p1)) dy)) len2))
      (if (< tv 0.0) (setq tv 0.0))
      (if (> tv 1.0) (setq tv 1.0))
      (list (+ (car p1) (* tv dx)) (+ (cadr p1) (* tv dy)) 0.0))))

(defun bs-dist-to-ent (pt ent / etype cp)
  ;; Perpendicular distance from pt to entity (finite).
  (setq etype (cdr (assoc 0 (entget ent))))
  (distance pt
    (cond
      ((= etype "LINE")
        (bs-closest-on-seg (cdr (assoc 10 (entget ent)))
                           (cdr (assoc 11 (entget ent))) pt))
      ((or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
        (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
        (if (vl-catch-all-error-p cp) pt cp))
      (T pt))))

;;; ---------------------------------------------------------------
;;; Tangent direction at a point on entity
;;; ---------------------------------------------------------------

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
    (T nil)))

;;; ---------------------------------------------------------------
;;; Intersection helpers
;;; ---------------------------------------------------------------

(defun bs-intersect-first (ea eb extend-mode / res)
  ;; Returns first intersection point (x y z) or nil.
  ;; extend-mode: 0=none (real only), 3=both (virtual OK).
  (setq res
    (vl-catch-all-apply 'vlax-invoke
      (list (vlax-ename->vla-object ea)
            'IntersectWith
            (vlax-ename->vla-object eb)
            extend-mode)))
  (if (or (vl-catch-all-error-p res) (not res) (< (length res) 3))
    nil
    (list (nth 0 res) (nth 1 res) (nth 2 res))))

(defun bs-intersect-all (ea eb extend-mode / res pts)
  ;; Returns list of all intersection points or nil.
  (setq res
    (vl-catch-all-apply 'vlax-invoke
      (list (vlax-ename->vla-object ea)
            'IntersectWith
            (vlax-ename->vla-object eb)
            extend-mode)))
  (if (or (vl-catch-all-error-p res) (not res)) nil
    (progn
      (setq pts nil)
      (while (>= (length res) 3)
        (setq pts (append pts (list (list (nth 0 res) (nth 1 res) (nth 2 res)))))
        (setq res (cdddr res)))
      pts)))

(defun bs-near-endpoint-p (pt ent tol / sp ep)
  ;; T if pt is within tol of either endpoint of ent.
  (setq sp (bs-ent-startpt ent))
  (setq ep (bs-ent-endpt ent))
  (or (and sp (< (distance pt sp) tol))
      (and ep (< (distance pt ep) tol))))

;;; ---------------------------------------------------------------
;;; Selection helpers
;;; ---------------------------------------------------------------

(defun bs-nearest-ent-in-ss (pt ss / i best-ent best-dist ent d)
  ;; Return entity in selection set ss closest to pt.
  (setq best-ent nil best-dist 999999999.0)
  (setq i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (setq d (bs-dist-to-ent pt ent))
    (if (< d best-dist)
      (progn (setq best-dist d) (setq best-ent ent)))
    (setq i (1+ i)))
  best-ent)

;;; ---------------------------------------------------------------
;;; Entity creation helpers
;;; ---------------------------------------------------------------

(defun bs-make-text (ins-pt height layer-name text-str / )
  ;; Create a TEXT entity via entmake. Returns new entity name.
  (entmakex
    (list
      '(0 . "TEXT")
      (cons 8 layer-name)
      (cons 10 (list (car ins-pt) (cadr ins-pt) 0.0))
      (cons 11 (list (car ins-pt) (cadr ins-pt) 0.0))
      (cons 40 height)
      (cons 1 text-str)
      '(7 . "STANDARD"))))

(defun bs-make-line (p1 p2 layer-name / )
  ;; Create a LINE entity via entmake. Returns new entity name.
  (entmakex
    (list
      '(0 . "LINE")
      (cons 8 layer-name)
      (cons 10 (list (car p1) (cadr p1) 0.0))
      (cons 11 (list (car p2) (cadr p2) 0.0)))))

(defun bs-make-leader-line (from-pt to-pt layer-name / )
  ;; Draw a simple leader: line from from-pt to to-pt + small elbow.
  ;; from-pt = arrowhead (on fiber), to-pt = text location.
  (bs-make-line from-pt to-pt layer-name))

;;; ---------------------------------------------------------------
;;; Formatting helpers
;;; ---------------------------------------------------------------

(defun bs-format-station (dist / hundreds remainder)
  ;; Convert feet distance to "STA XX+XX.X" surveying notation.
  ;; Example: 1253.5 -> "STA 12+53.5"
  (setq hundreds  (fix (/ dist 100.0)))
  (setq remainder (- dist (* hundreds 100.0)))
  (strcat "STA "
    (itoa hundreds) "+"
    (if (< remainder 10.0) "0" "")
    (rtos remainder 2 1)))

;;; ---------------------------------------------------------------
;;; LWPOLYLINE vertex editing
;;; ---------------------------------------------------------------

(defun bs-replace-nth-vertex (elist idx new-pt / count result pair)
  ;; Replace the idx-th group 10 entry in LWPOLYLINE entity data.
  ;; idx is 0-based. Returns modified elist.
  (setq count 0 result nil)
  (foreach pair elist
    (if (= (car pair) 10)
      (progn
        (if (= count idx)
          (setq result (append result
            (list (cons 10 (list (car new-pt) (cadr new-pt))))))
          (setq result (append result (list pair))))
        (setq count (1+ count)))
      (setq result (append result (list pair)))))
  result)

(defun bs-count-vertices (elist / count pair)
  ;; Count the number of group-10 entries (vertices) in LWPOLYLINE elist.
  (setq count 0)
  (foreach pair elist
    (if (= (car pair) 10) (setq count (1+ count))))
  count)

(princ "\n[BS_HELPERS] Loaded. Shared helpers ready.")
(princ)
