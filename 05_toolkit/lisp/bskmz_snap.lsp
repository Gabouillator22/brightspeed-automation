;;; ============================================================
;;; BSKMZ_SNAP — Post-import drafting-standard snappers
;;;
;;; Run AFTER bskmz import to align raw GPS geometry to Brightspeed
;;; drafting standards. Each command operates independently and can
;;; be re-run safely.
;;;
;;;   BSKMZ-FIBERSNAP  Buried fiber polylines -> 4' from nearest ROW
;;;                    (offset toward ROAD-CENTERLINE)
;;;   BSKMZ-HHALIGN    Handhole blocks -> layer color red, rotation
;;;                    matches centerline tangent, position 4' from ROW
;;;   BSKMZ-AERIALSNAP Aerial fiber vertices -> snap to nearest pole
;;;                    within 80'. Vertices with no pole nearby left
;;;                    alone (aerial outside ROW stays as-is).
;;;   BSKMZ-SNAP       Runs all three in order.
;;;
;;; Tuning constants (top of file):
;;;   *bks-fiber-offset-ft*     default 4.0
;;;   *bks-row-search-ft*       default 200.0
;;;   *bks-pole-search-ft*      default 80.0
;;;   *bks-row-layer*           "ROW"
;;;   *bks-cl-layer*            "ROAD-CENTERLINE"
;;;   *bks-buried-layer*        "Buried Fiber in Duct"
;;;   *bks-aerial-layer*        "AERIAL FIBER"
;;;   *bks-hh-layer*            "HANDHOLE"
;;;   *bks-pole-block*          "TELPOLE1262023"
;;; ============================================================

(vl-load-com)

(setq *bks-fiber-offset-ft* 4.0)
(setq *bks-row-search-ft*   200.0)
(setq *bks-pole-search-ft*  80.0)
(setq *bks-row-layer*       "ROW")
(setq *bks-cl-layer*        "ROAD-CENTERLINE")
(setq *bks-buried-layer*    "Buried Fiber in Duct")
(setq *bks-aerial-layer*    "AERIAL FIBER")
(setq *bks-hh-layer*        "HANDHOLE")
(setq *bks-pole-block*      "TELPOLE1262023")

;;; --------------------------------------------------------------
;;; Geometry helpers (bks- prefix, local to this file)
;;; --------------------------------------------------------------

;; Perpendicular foot of pt onto curve ent. Returns 3D point or nil.
(defun bks-foot-on-ent (ent pt)
  (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))

;; Tangent direction (unit vector, 3D) at given point on curve.
(defun bks-tangent-at (ent pt / param d v len)
  (setq param (vl-catch-all-apply 'vlax-curve-getParamAtPoint (list ent pt)))
  (if (and param (not (vl-catch-all-error-p param)))
    (progn
      (setq d (vl-catch-all-apply 'vlax-curve-getFirstDeriv (list ent param)))
      (if (and d (not (vl-catch-all-error-p d)))
        (progn
          (setq len (sqrt (+ (* (car d) (car d)) (* (cadr d) (cadr d)))))
          (if (> len 1e-9)
            (list (/ (car d) len) (/ (cadr d) len) 0.0)
            nil))
        nil))
    nil))

;; Find nearest LWPOLYLINE/POLYLINE on layer to pt, within max-dist.
;; Returns (ent dist foot) or nil.
(defun bks-nearest-pline (layer pt max-dist / ss best-ent best-d best-foot
                                              i ent foot d)
  (setq ss (ssget "_X" (list (cons 0 "LWPOLYLINE,POLYLINE,LINE") (cons 8 layer))))
  (setq best-ent nil best-d 1e99 best-foot nil)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq foot (bks-foot-on-ent ent pt))
        (if (and foot (not (vl-catch-all-error-p foot)))
          (progn
            (setq d (distance pt foot))
            (if (< d best-d)
              (setq best-d d best-ent ent best-foot foot))))
        (setq i (1+ i)))))
  (if (and best-ent (<= best-d max-dist))
    (list best-ent best-d best-foot)
    nil))

;; Find nearest INSERT of given block name to pt, within max-dist.
;; Returns (ent dist insertion-pt) or nil.
(defun bks-nearest-block (blkname pt max-dist / ss best best-d best-ip
                                                 i ent ip d)
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 blkname))))
  (setq best nil best-d 1e99 best-ip nil)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq ip (cdr (assoc 10 (entget ent))))
        (setq d (distance pt ip))
        (if (< d best-d) (setq best-d d best ent best-ip ip))
        (setq i (1+ i)))))
  (if (and best (<= best-d max-dist)) (list best best-d best-ip) nil))

;; Find all entities on a layer of given type. Returns ss or nil.
(defun bks-all-on-layer (layer dxf-type)
  (ssget "_X" (list (cons 0 dxf-type) (cons 8 layer))))

;; Replace all vertices of an LWPOLYLINE with new-verts (list of (x y)).
;; Uses ActiveX Coordinates property — preserves layer/widths/closed flag.
(defun bks-set-pline-verts (ent new-verts / vobj flat arr)
  (setq vobj (vlax-ename->vla-object ent))
  (setq flat '())
  (foreach v new-verts
    (setq flat (cons (cadr v) (cons (car v) flat))))
  (setq flat (reverse flat))
  (setq arr (vlax-make-safearray vlax-vbDouble (cons 0 (1- (length flat)))))
  (vlax-safearray-fill arr flat)
  (vla-put-Coordinates vobj (vlax-make-variant arr)))

;; Read LWPOLYLINE vertices as list of (x y).
(defun bks-get-pline-verts (ent / data verts)
  (setq data (entget ent) verts '())
  (foreach p data
    (if (= (car p) 10) (setq verts (cons (list (cadr p) (caddr p)) verts))))
  (reverse verts))

;; Force a layer to a specific color (creates if missing, recolors if exists).
(defun bks-force-layer-color (lname lcolor)
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "")
  )
  (command "_.LAYER" "C" (itoa lcolor) lname "ON" lname "T" lname ""))

;;; --------------------------------------------------------------
;;; BSKMZ-FIBERSNAP : buried fiber -> 4' from ROW, toward CL
;;; --------------------------------------------------------------

(defun c:BSKMZ-FIBERSNAP ( / *error* ss i fent verts new-verts v
                             row-hit cl-hit row-ent foot
                             cl-foot dir-to-cl ux uy len off-pt
                             nFibers nMoved nUntouched)

  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*EXIT*")))
      (princ (strcat "\n[BSKMZ-FIBERSNAP] ERROR: " msg)))
    (princ))

  (princ "\n[BSKMZ-FIBERSNAP] Snapping buried fiber to 4' from ROW...")

  ;; sanity
  (if (not (bks-all-on-layer *bks-row-layer* "LWPOLYLINE,POLYLINE,LINE"))
    (progn (princ "\n[BSKMZ-FIBERSNAP] ABORT: no ROW lines found. Run BSROW first.") (exit)))
  (if (not (bks-all-on-layer *bks-cl-layer* "LWPOLYLINE,POLYLINE,LINE"))
    (progn (princ "\n[BSKMZ-FIBERSNAP] ABORT: no ROAD-CENTERLINE found.") (exit)))

  (setq ss (bks-all-on-layer *bks-buried-layer* "LWPOLYLINE"))
  (if (not ss)
    (progn (princ "\n[BSKMZ-FIBERSNAP] Nothing to do (no buried fiber polylines).") (exit)))

  (command "_.UNDO" "_BE")
  (setq nFibers 0 nMoved 0 nUntouched 0 i 0)
  (while (< i (sslength ss))
    (setq fent (ssname ss i) nFibers (1+ nFibers))
    (setq verts (bks-get-pline-verts fent) new-verts '())
    (foreach v verts
      (setq row-hit (bks-nearest-pline *bks-row-layer* v *bks-row-search-ft*))
      (if row-hit
        (progn
          (setq row-ent (car row-hit) foot (caddr row-hit))
          ;; direction from foot toward nearest point on CL
          (setq cl-hit (bks-nearest-pline *bks-cl-layer* foot 10000.0))
          (if cl-hit
            (progn
              (setq cl-foot (caddr cl-hit))
              (setq ux (- (car cl-foot) (car foot)) uy (- (cadr cl-foot) (cadr foot)))
              (setq len (sqrt (+ (* ux ux) (* uy uy))))
              (if (> len 1e-6)
                (progn
                  (setq ux (/ ux len) uy (/ uy len))
                  (setq off-pt (list (+ (car foot) (* ux *bks-fiber-offset-ft*))
                                     (+ (cadr foot) (* uy *bks-fiber-offset-ft*))))
                  (setq new-verts (cons off-pt new-verts))
                  (setq nMoved (1+ nMoved)))
                (progn (setq new-verts (cons v new-verts)) (setq nUntouched (1+ nUntouched)))))
            (progn (setq new-verts (cons v new-verts)) (setq nUntouched (1+ nUntouched)))))
        (progn (setq new-verts (cons v new-verts)) (setq nUntouched (1+ nUntouched)))))
    (setq new-verts (reverse new-verts))
    (if (>= (length new-verts) 2) (bks-set-pline-verts fent new-verts))
    (setq i (1+ i)))
  (command "_.UNDO" "_E")

  (princ (strcat "\n[BSKMZ-FIBERSNAP] Done. Fiber polylines: " (itoa nFibers)
                 "  vertices moved: " (itoa nMoved)
                 "  left alone: " (itoa nUntouched)))
  (princ))

;;; --------------------------------------------------------------
;;; BSKMZ-HHALIGN : handholes red + rotated + 4' from ROW
;;; --------------------------------------------------------------

(defun c:BSKMZ-HHALIGN ( / *error* ss i ent ip row-hit cl-hit
                          foot cl-foot ux uy len off-pt
                          tan-vec ang vobj has-row has-cl
                          nHH nMoved nRot nSkipped)

  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*EXIT*")))
      (princ (strcat "\n[BSKMZ-HHALIGN] ERROR: " msg)))
    (princ))

  (princ "\n[BSKMZ-HHALIGN] Aligning handholes...")

  ;; recolor layer red
  (bks-force-layer-color *bks-hh-layer* 1)

  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 8 *bks-hh-layer*))))
  (if (not ss)
    (progn (princ "\n[BSKMZ-HHALIGN] No handhole inserts found.") (exit)))

  (setq has-row (bks-all-on-layer *bks-row-layer* "LWPOLYLINE,POLYLINE,LINE"))
  (setq has-cl  (bks-all-on-layer *bks-cl-layer*  "LWPOLYLINE,POLYLINE,LINE"))
  (if (not has-cl)
    (princ "\n[BSKMZ-HHALIGN] WARN: no centerline found — rotation will be skipped."))
  (if (not has-row)
    (princ "\n[BSKMZ-HHALIGN] WARN: no ROW found — position snap will be skipped."))

  (command "_.UNDO" "_BE")
  (setq nHH 0 nMoved 0 nRot 0 nSkipped 0 i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i) nHH (1+ nHH))
    (setq ip (cdr (assoc 10 (entget ent))))
    (setq vobj (vlax-ename->vla-object ent))

    ;; --- position: 4' from ROW toward CL ---
    (if has-row
      (progn
        (setq row-hit (bks-nearest-pline *bks-row-layer* ip *bks-row-search-ft*))
        (if row-hit
          (progn
            (setq foot (caddr row-hit))
            (setq cl-hit (bks-nearest-pline *bks-cl-layer* foot 10000.0))
            (if cl-hit
              (progn
                (setq cl-foot (caddr cl-hit))
                (setq ux (- (car cl-foot) (car foot))
                      uy (- (cadr cl-foot) (cadr foot)))
                (setq len (sqrt (+ (* ux ux) (* uy uy))))
                (if (> len 1e-6)
                  (progn
                    (setq ux (/ ux len) uy (/ uy len))
                    (setq off-pt (list (+ (car foot) (* ux *bks-fiber-offset-ft*))
                                       (+ (cadr foot) (* uy *bks-fiber-offset-ft*))
                                       0.0))
                    (vla-put-InsertionPoint vobj
                      (vlax-3d-point off-pt))
                    (setq ip off-pt)
                    (setq nMoved (1+ nMoved)))))))))
    )

    ;; --- rotation: align with centerline tangent ---
    (if has-cl
      (progn
        (setq cl-hit (bks-nearest-pline *bks-cl-layer* ip 10000.0))
        (if cl-hit
          (progn
            (setq tan-vec (bks-tangent-at (car cl-hit) (caddr cl-hit)))
            (if tan-vec
              (progn
                (setq ang (atan (cadr tan-vec) (car tan-vec)))
                (vla-put-Rotation vobj ang)
                (setq nRot (1+ nRot)))
              (setq nSkipped (1+ nSkipped)))))))

    (setq i (1+ i)))
  (command "_.UNDO" "_E")

  (princ (strcat "\n[BSKMZ-HHALIGN] Done. HH inserts: " (itoa nHH)
                 "  repositioned: " (itoa nMoved)
                 "  rotated: " (itoa nRot)))
  (princ))

;;; --------------------------------------------------------------
;;; BSKMZ-AERIALSNAP : aerial vertices -> nearest pole within 80'
;;; --------------------------------------------------------------

(defun c:BSKMZ-AERIALSNAP ( / *error* ss i fent verts new-verts v
                             hit snapped lastv nFibers nSnapped nKept)

  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*EXIT*")))
      (princ (strcat "\n[BSKMZ-AERIALSNAP] ERROR: " msg)))
    (princ))

  (princ "\n[BSKMZ-AERIALSNAP] Snapping aerial fiber to poles...")

  (setq ss (bks-all-on-layer *bks-aerial-layer* "LWPOLYLINE"))
  (if (not ss)
    (progn (princ "\n[BSKMZ-AERIALSNAP] No aerial fiber polylines found.") (exit)))

  ;; verify at least one pole exists
  (if (not (ssget "_X" (list (cons 0 "INSERT") (cons 2 *bks-pole-block*))))
    (progn (princ (strcat "\n[BSKMZ-AERIALSNAP] No pole blocks ("
                          *bks-pole-block* ") in drawing — nothing to snap to.")) (exit)))

  (command "_.UNDO" "_BE")
  (setq nFibers 0 nSnapped 0 nKept 0 i 0)
  (while (< i (sslength ss))
    (setq fent (ssname ss i) nFibers (1+ nFibers))
    (setq verts (bks-get-pline-verts fent) new-verts '() lastv nil)
    (foreach v verts
      (setq hit (bks-nearest-block *bks-pole-block* v *bks-pole-search-ft*))
      (if hit
        (progn
          (setq snapped (list (car (caddr hit)) (cadr (caddr hit))))
          ;; dedupe consecutive identical
          (if (or (not lastv)
                  (> (distance lastv snapped) 0.01))
            (progn (setq new-verts (cons snapped new-verts))
                   (setq lastv snapped)
                   (setq nSnapped (1+ nSnapped)))))
        (progn (setq new-verts (cons v new-verts))
               (setq lastv v)
               (setq nKept (1+ nKept)))))
    (setq new-verts (reverse new-verts))
    (if (>= (length new-verts) 2) (bks-set-pline-verts fent new-verts))
    (setq i (1+ i)))
  (command "_.UNDO" "_E")

  (princ (strcat "\n[BSKMZ-AERIALSNAP] Done. Aerial polylines: " (itoa nFibers)
                 "  vertices snapped to poles: " (itoa nSnapped)
                 "  kept as-is: " (itoa nKept)))
  (princ))

;;; --------------------------------------------------------------
;;; BSKMZ-SNAP : run all three in order
;;; --------------------------------------------------------------

(defun c:BSKMZ-SNAP ( / )
  (princ "\n[BSKMZ-SNAP] Running full post-import snap chain...")
  (c:BSKMZ-FIBERSNAP)
  (c:BSKMZ-HHALIGN)
  (c:BSKMZ-AERIALSNAP)
  (princ "\n[BSKMZ-SNAP] All three snappers complete.")
  (princ))
