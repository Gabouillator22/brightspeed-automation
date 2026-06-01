;;; ============================================================
;;; bsrowdims.lsp - ROW Dimension Stacker for BRIGHTSPEED  v2
;;; Commands:
;;;   BSROWDIMS  - dimension every BORDER rectangle in drawing
;;;   BSROWDIMS1 - dimension a single BORDER rectangle picked by user
;;;   BSROWDIMSC - pick a centerline, auto-find its BORDER rectangle
;;;
;;; V2 changes vs V1:
;;;   - No probe-line temp entities; uses closestPointTo instead
;;;   - Candidates gathered with crossing-window ssget (border-local)
;;;   - Stack direction driven by border centroid (always faces interior)
;;;
;;; Depends on: bs_helpers.lsp (loaded by bs_loader.lsp)
;;; AutoCAD Map 3D 2027
;;; ============================================================

(vl-load-com)

;;; ============================================================
;;; Shared geometry helpers
;;; ============================================================

(setq bsrd-centerline-layers '("ROAD-CENTERLINE" "CENTERLINE" "ROAD CENTERLINE"))
(setq bsrd-row-layers '("ROW"))
(setq bsrd-eop-layers '("ROADS-paved" "ROADS-PAVED" "EOP"))
(setq bsrd-fiber-layers '("Buried Fiber in Duct" "BURIED FIBER IN DUCT" "AERIAL FIBER" "E-LASH" "ELASH"))
(setq bsrd-curve-types "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE")
(setq bsrd-guide-layer "BS-DIM-GUIDE")
(setq bsrd-measure-tolerance 5.0)

(defun bsrd-flat (p)
  (if (and p (listp p) (>= (length p) 2))
    (list (car p) (cadr p) 0.0)
    nil))

(defun bsrd-bbox (ent / vo res min-pt max-pt mn mx)
  (setq vo (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
  (if (or (null vo) (vl-catch-all-error-p vo))
    nil
    (progn
      (setq res (vl-catch-all-apply
                  'vla-GetBoundingBox (list vo 'min-pt 'max-pt)))
      (if (vl-catch-all-error-p res)
        nil
        (progn
          (setq mn (vl-catch-all-apply 'vlax-safearray->list (list min-pt)))
          (setq mx (vl-catch-all-apply 'vlax-safearray->list (list max-pt)))
          (if (or (vl-catch-all-error-p mn) (vl-catch-all-error-p mx)
                  (not (listp mn)) (not (listp mx)))
            nil
            (list (bsrd-flat mn) (bsrd-flat mx))))))))

(defun bsrd-pt-in-bbox (pt bb / mn mx)
  (if (and pt bb)
    (progn
      (setq mn (car bb) mx (cadr bb))
      (and (>= (car pt) (car mn)) (<= (car pt) (car mx))
           (>= (cadr pt) (cadr mn)) (<= (cadr pt) (cadr mx))))
    nil))

;;; ============================================================
;;; Curve helpers
;;; ============================================================

(defun bsrd-dist-at (ent pt / cp param dist)
  (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (or (vl-catch-all-error-p cp) (null cp))
    nil
    (progn
      (setq param (vl-catch-all-apply 'vlax-curve-getParamAtPoint (list ent cp)))
      (if (or (vl-catch-all-error-p param) (null param))
        nil
        (progn
          (setq dist (vl-catch-all-apply 'vlax-curve-getDistAtParam (list ent param)))
          (if (vl-catch-all-error-p dist) nil dist))))))

(defun bsrd-point-at-dist (ent dist / pt)
  (setq pt (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent dist)))
  (if (vl-catch-all-error-p pt) nil (bsrd-flat pt)))

;;; Entry / exit points of a CL polyline within a border rect.
;;; Uses 2D bbox sampling — fully Z-independent (no IntersectWith).
;;; Samples up to 200 points along the curve; finds first and last
;;; point whose XY projection is inside the border bbox.
(defun bsrd-cl-bbox-span (cl-ent bb / end-param total-len step dist pt first-in last-in)
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam   (list cl-ent)))
  (setq total-len (vl-catch-all-apply 'vlax-curve-getDistAtParam
                    (list cl-ent
                          (if (vl-catch-all-error-p end-param) 1 end-param))))
  (if (or (vl-catch-all-error-p total-len) (null total-len) (< total-len 1.0))
    nil
    (progn
      (setq step     (max 0.5 (/ total-len 200.0))
            first-in nil
            last-in  nil
            dist     0.0)
      (while (<= dist (+ total-len 0.001))
        (setq pt (vl-catch-all-apply 'vlax-curve-getPointAtDist (list cl-ent dist)))
        (if (and pt (not (vl-catch-all-error-p pt)))
          (progn
            (setq pt (bsrd-flat pt))
            (if (bsrd-pt-in-bbox pt bb)
              (progn
                (if (null first-in) (setq first-in pt))
                (setq last-in pt)))))
        (setq dist (+ dist step)))
      (if (and first-in last-in (> (distance first-in last-in) 1.0))
        (list first-in last-in)
        nil))))

;;; ============================================================
;;; V2 CORE — spatial-bounded, closestPointTo, centroid-stacking
;;; ============================================================

;;; Project pt onto the perpendicular line through cl-pt along nvec.
;;; All projected points are collinear → all dims are perfectly parallel.
(defun bsrd-proj-pt (pt cl-pt nvec / d)
  (setq d (bs-vdot (bs-vsub pt cl-pt) nvec))
  (bs-vadd cl-pt (bs-vscale nvec d)))

;;; Collect enames within border bbox via crossing-window ssget.
;;; layer  - exact layer name string
;;; types  - entity type filter string e.g. "LINE,LWPOLYLINE,POLYLINE,ARC"
(defun bsrd-gather-layer (bb layer types / mn mx ss lst i)
  (setq mn (car bb) mx (cadr bb) lst nil)
  (setq ss (ssget "_C"
                  (list (car mn) (cadr mn))
                  (list (car mx) (cadr mx))
                  (list (cons 0 types) (cons 8 layer))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq lst (cons (ssname ss i) lst))
        (setq i (1+ i)))
      (setq ss nil)))
  lst)

(defun bsrd-gather-layers (bb layers types / out layer)
  (setq out nil)
  (foreach layer layers
    (setq out (append out (bsrd-gather-layer bb layer types))))
  out)

(defun bsrd-layer-in-list-p (layer layers / hit item)
  (setq hit nil)
  (if layer
    (foreach item layers
      (if (= (strcase layer) (strcase item))
        (setq hit T))))
  hit)

;;; Find nearest entity on each side of cl-pt using closestPointTo.
;;; Returns (left-pt right-pt) — either may be nil.
(defun bsrd-pick-side-v2 (candidates max-dist cl-pt perp-vec
                           / ent cp d v dot bl br bld brd)
  (setq bl nil br nil bld 1e99 brd 1e99)
  (foreach ent candidates
    (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent cl-pt)))
    (if (and cp (not (vl-catch-all-error-p cp)))
      (progn
        (setq cp (bsrd-flat cp))
        (setq d (distance cp cl-pt))
        (if (and (> d 0.5) (<= d max-dist))
          (progn
            (setq v   (bs-vsub cp cl-pt))
            (setq dot (bs-vdot v perp-vec))
            (cond
              ((and (< dot 0.0) (< d bld)) (setq bl cp bld d))
              ((and (> dot 0.0) (< d brd)) (setq br cp brd d))))))))
  (list bl br))

(defun bsrd-temp-guide-line (pt nvec len / p1 p2)
  (bs-ensure-layer bsrd-guide-layer 8)
  (setq p1 (bs-vadd pt (bs-vscale nvec (- len))))
  (setq p2 (bs-vadd pt (bs-vscale nvec len)))
  (entmakex
    (list
      '(0 . "LINE")
      '(100 . "AcDbEntity")
      (cons 8 bsrd-guide-layer)
      '(62 . 8)
      (cons 10 (bsrd-flat p1))
      (cons 11 (bsrd-flat p2))))
)

(defun bsrd-intersection-points (ent1 ent2 / obj1 obj2 raw nums pts)
  (setq obj1 (vlax-ename->vla-object ent1))
  (setq obj2 (vlax-ename->vla-object ent2))
  (setq raw (vl-catch-all-apply 'vlax-invoke (list obj1 'IntersectWith obj2 0)))
  (if (or (vl-catch-all-error-p raw) (not raw))
    nil
    (progn
      (setq nums raw)
      (setq pts nil)
      (while (>= (length nums) 3)
        (setq pts (cons (list (car nums) (cadr nums) 0.0) pts))
        (setq nums (cdddr nums)))
      pts))
)

(defun bsrd-pick-side-guide (candidates max-dist cl-pt perp-vec / guide ent pts pt d v dot bl br bld brd)
  (setq bl nil br nil bld 1e99 brd 1e99)
  (setq guide (bsrd-temp-guide-line cl-pt perp-vec 500.0))
  (if guide
    (progn
      (foreach ent candidates
        (setq pts (bsrd-intersection-points guide ent))
        (foreach pt pts
          (setq pt (bsrd-flat pt))
          (setq d (distance pt cl-pt))
          (if (and (> d 0.5) (<= d max-dist))
            (progn
              (setq v (bs-vsub pt cl-pt))
              (setq dot (bs-vdot v perp-vec))
              (cond
                ((and (< dot 0.0) (< d bld)) (setq bl pt bld d))
                ((and (> dot 0.0) (< d brd)) (setq br pt brd d)))))))
      (entdel guide)))
  (list bl br)
)

(defun bsrd-near-dist-p (a b expected / d)
  (if (and a b)
    (progn
      (setq d (distance a b))
      (<= (abs (- d expected)) bsrd-measure-tolerance))
    nil)
)

(defun bsrd-section-verified-p (row-l row-r eop-l eop-r / ok)
  (setq ok T)
  (if (not (bsrd-near-dist-p row-l row-r 60.0))
    (setq ok nil))
  (if (and ok eop-r (not (bsrd-near-dist-p eop-r row-r 20.0)))
    (setq ok nil))
  (if (and ok eop-l (not (bsrd-near-dist-p row-l eop-l 20.0)))
    (setq ok nil))
  ok
)

;;; Detect fiber closest to cl-pt from pre-gathered candidates.
;;; Returns (fiber-pt row-pt label) or nil.
(defun bsrd-find-fiber-v2 (fiber-cands cl-pt perp-vec row-l row-r
                            / ent cp d dot v lyr
                              best best-dist best-lyr near-row lbl toward fc)
  (setq best nil best-dist 1e99 best-lyr nil)
  (foreach ent fiber-cands
    (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent cl-pt)))
    (if (and cp (not (vl-catch-all-error-p cp)))
      (progn
        (setq cp (bsrd-flat cp))
        (setq d (distance cp cl-pt))
        (if (and (<= d 200.0) (< d best-dist))
          (progn
            (setq best cp best-dist d)
            (setq best-lyr (cdr (assoc 8 (entget ent)))))))))
  (if (null best)
    nil
    (progn
      (setq v   (bs-vsub best cl-pt))
      (setq dot (bs-vdot v perp-vec))
      (setq near-row (if (< dot 0.0) row-l row-r))
      (if (null near-row)
        nil
        (cond
          ((= (strcase best-lyr) "BURIED FIBER IN DUCT")
           (setq toward (bs-vunit (bs-vsub cl-pt near-row)))
           (setq fc     (bs-vadd near-row (bs-vscale toward 4.0)))
           (list (bsrd-flat fc) near-row "4'"))
          (T
           (setq lbl (strcat (itoa (fix (+ 0.5 (distance best near-row)))) "'"))
           (list best near-row lbl)))))))

;;; Stack direction: +1.0 if centroid is ahead along tvec, else -1.0.
;;; Guarantees the dim stack points toward the interior of the border.
(defun bsrd-stack-dir (pt tvec centroid)
  (if (>= (bs-vdot (bs-vsub centroid pt) tvec) 0.0) 1.0 -1.0))

;;; ============================================================
;;; Dimension placement
;;; ============================================================

(defun bsrd-dim-command (pt1 pt2 dim-loc)
  (command-s "_.DIMALIGNED" (bsrd-flat pt1) (bsrd-flat pt2) (bsrd-flat dim-loc)))

(defun bsrd-upsert-dxf (elist code value / pair)
  (setq pair (assoc code elist))
  (if pair
    (subst (cons code value) pair elist)
    (append elist (list (cons code value)))))

(defun bsrd-update-dim (dim-ent txt / elist)
  (if (and dim-ent (entget dim-ent))
    (progn
      (setq elist (entget dim-ent))
      (if (= (cdr (assoc 0 elist)) "DIMENSION")
        (progn
          (setq elist (bsrd-upsert-dxf elist 8 "DIM"))
          (setq elist (bsrd-upsert-dxf elist 1 txt))
          (entmod elist)
          (entupd dim-ent)
          dim-ent)
        nil))
    nil))

(defun bsrd-place-dim (pt1 pt2 dim-loc txt / before after res d)
  (setq d (if (and pt1 pt2) (distance pt1 pt2) -1))
  (princ (strcat "\n  DIM " txt " dist=" (rtos d 2 2)
                 " pt1=" (if pt1 (strcat "(" (rtos (car pt1) 2 1) "," (rtos (cadr pt1) 2 1) ")") "NIL")
                 " pt2=" (if pt2 (strcat "(" (rtos (car pt2) 2 1) "," (rtos (cadr pt2) 2 1) ")") "NIL")))
  (if (and pt1 pt2 dim-loc txt (> d 0.1))
    (progn
      (setq before (entlast))
      (setq res (vl-catch-all-apply 'bsrd-dim-command (list pt1 pt2 dim-loc)))
      (if (vl-catch-all-error-p res)
        (progn (princ (strcat " ERR=" (vl-catch-all-error-message res))) nil)
        (progn
          (setq after (entlast))
          (if (and after (/= after before))
            (progn (princ " OK") (bsrd-update-dim after txt))
            (progn (princ " NO-ENT") nil)))))
    (progn (princ " SKIP") nil)))

(defun bsrd-mid (a b / )
  (if (and a b)
    (list (/ (+ (car a) (car b)) 2.0)
          (/ (+ (cadr a) (cadr b)) 2.0)
          0.0)
    nil)
)

(defun bsrd-curve-section-p (local-tvec ref-tvec / lt rt dot)
  (if (and local-tvec ref-tvec)
    (progn
      (setq lt (bs-vunit local-tvec))
      (setq rt (bs-vunit ref-tvec))
      (if (and lt rt)
        (progn
          (setq dot (abs (bs-vdot lt rt)))
          (< dot 0.999))
        nil))
    nil)
)

(defun bsrd-split-point (cl-pt row-l row-r use-cl-split / mid)
  (setq mid (bsrd-mid row-l row-r))
  (if (and use-cl-split cl-pt row-l row-r
           (bsrd-near-dist-p row-l cl-pt 30.0)
           (bsrd-near-dist-p cl-pt row-r 30.0))
    cl-pt
    mid)
)

(defun bsrd-guide-seg (p1 p2 / )
  (if (and p1 p2 (> (distance p1 p2) 0.1))
    (progn
      (bs-ensure-layer bsrd-guide-layer 8)
      (entmakex
        (list
          '(0 . "LINE")
          '(100 . "AcDbEntity")
          (cons 8 bsrd-guide-layer)
          '(62 . 8)
          (cons 10 (bsrd-flat p1))
          (cons 11 (bsrd-flat p2))))))
  (princ)
)

;;; Place the full dimension stack at one cross-section.
;;; stack-dir: +1.0 = stack along +tvec, -1.0 = along -tvec
;;;
;;; NCDOT nesting convention — shorter dims innermost (smallest offset from
;;; section point), longer dims outermost. This prevents extension-line crossings.
;;;
;;;   Offset  Dim       Points            Label
;;;   1 sp    EOP-R→ROW-R  eop-r,row-r   "20'"
;;;   2 sp    ROW-L→EOP-L  row-l,eop-l   "20'"
;;;   3 sp    CL→ROW-R     cl-pt,row-r   "30'"
;;;   4 sp    ROW-L→CL     row-l,cl-pt   "30'"
;;;   5 sp    ROW-L→ROW-R  row-l,row-r   "60'"
;;;   6 sp    fiber dim                   label
;;;
;;; Starting at 1sp (not 0) keeps every dim line off the section point itself.
(defun bsrd-place-stack (cl-pt tvec stack-dir use-cl-split
                          row-l row-r eop-l eop-r fiber-info
                          / sp dloc dloc20 dloc30 dloc60 dlocf row-mid fiber-pt near-row flbl)
  (setq sp 10.0)
  (princ (strcat "\n STACK dir=" (rtos stack-dir 2 1)
                 " rl=" (if row-l "Y" "n") " rr=" (if row-r "Y" "n")
                 " el=" (if eop-l "Y" "n") " er=" (if eop-r "Y" "n")))
  ;; Phase 1: draw exact guide segments before any arrows.
  (if (and row-l row-r)
    (progn
      (setq row-mid (bsrd-split-point cl-pt row-l row-r use-cl-split))
      (bsrd-guide-seg row-l row-r)))
  (if (and eop-r row-r) (bsrd-guide-seg eop-r row-r))
  (if (and row-l eop-l) (bsrd-guide-seg row-l eop-l))
  (setq dloc20 (bs-vadd cl-pt (bs-vscale tvec (* stack-dir sp))))
  (setq dloc30 (bs-vadd cl-pt (bs-vscale tvec (* stack-dir (* 3.0 sp)))))
  (setq dloc60 (bs-vadd cl-pt (bs-vscale tvec (* stack-dir (* 5.0 sp)))))
  (setq dlocf  (bs-vadd cl-pt (bs-vscale tvec (* stack-dir (* 6.0 sp)))))
  ;; 20' EOP dims — innermost (offset 1sp, 2sp)
  (if (and eop-r row-r)
    (progn
      (setq dloc dloc20)
      (bsrd-place-dim eop-r row-r dloc "20'")))
  (if (and row-l eop-l)
    (progn
      (setq dloc dloc20)
      (bsrd-place-dim row-l eop-l dloc "20'")))
  ;; 30' half-ROW dims — middle (offset 3sp, 4sp)
  (if (and row-l row-r row-mid)
    (progn
      (bsrd-place-dim row-l row-mid dloc30 "30'")
      (bsrd-place-dim row-mid row-r dloc30 "30'")))
  ;; 60' full ROW — outermost (offset 5sp)
  (if (and row-l row-r)
    (progn
      (setq dloc dloc60)
      (bsrd-place-dim row-l row-r dloc "60'")))
  ;; Fiber dim — beyond ROW (offset 6sp)
  (if fiber-info
    (progn
      (setq fiber-pt (nth 0 fiber-info))
      (setq near-row (nth 1 fiber-info))
      (setq flbl    (nth 2 fiber-info))
      (setq dloc dlocf)
      (bsrd-guide-seg near-row fiber-pt)
      (bsrd-place-dim near-row fiber-pt dloc flbl)))
  T)

;;; ============================================================
;;; V2 section / CL / border processors
;;; ============================================================

;;; Process one cross-section.
;;; ref-tvec and ref-nvec are BOTH shared from the CL midpoint — never local.
;;; Using shared vectors for both projection AND dloc offset guarantees that
;;; every dimension line AND every extension line across both stacks is parallel.
(defun bsrd-process-section-v2 (p ref-tvec ref-nvec centroid
                                  row-cands eop-cands fiber-cands
                                  use-cl-split
                                  / rp ep rl rr el er fp sd)
  (bsrd-make-guide p ref-nvec)
  (setq rp (bsrd-pick-side-guide row-cands  100.0 p ref-nvec))
  (setq ep (bsrd-pick-side-guide eop-cands   60.0 p ref-nvec))
  (setq rl (car rp) rr (cadr rp))
  (setq el (car ep) er (cadr ep))
  (princ (strcat " [ROW-L=" (if rl "Y" "n") " ROW-R=" (if rr "Y" "n")
                 " EOP-L=" (if el "Y" "n") " EOP-R=" (if er "Y" "n") "]"))
  (if (bsrd-section-verified-p rl rr el er)
    (progn
      (princ " VERIFY=OK")
      (setq fp (bsrd-find-fiber-v2 fiber-cands p ref-nvec rl rr))
      (if fp
        (setq fp (list (bsrd-proj-pt (nth 0 fp) p ref-nvec)
                       (nth 1 fp)
                       (nth 2 fp))))
      (setq sd (bsrd-stack-dir p ref-tvec centroid))
      (bsrd-place-stack p ref-tvec sd use-cl-split rl rr el er fp))
    (princ " VERIFY=FAIL-SKIP")))

;;; Process one CL entity within a border.
;;; Places two stacks: one 15' inside the entry edge, one 15' inside the exit edge.
;;; Both share ref-tvec AND ref-nvec from the midpoint tangent.
;;; Using the same ref-tvec for the dloc offset in both stacks guarantees that
;;; all dimension lines AND extension lines are geometrically parallel.
(defun bsrd-process-cl-v2 (cl-ent bb centroid
                             row-cands eop-cands fiber-cands
                             / ee p-entry p-exit dist d-entry d-exit d-mid
                               p-mid p1 p2 tdir ref-tvec ref-nvec tvec1 nvec1 tvec2 nvec2)
  (setq ee (bsrd-cl-bbox-span cl-ent bb))
  (if (null ee)
    (princ " [CL: no span in bbox]")
    (progn
      (setq p-entry (car ee) p-exit (cadr ee))
      (setq dist (distance p-entry p-exit))
      (princ (strcat " [CL span=" (rtos dist 2 1) "']"))
      (if (> dist 40.0)
        (progn
          (setq d-entry (bsrd-dist-at cl-ent p-entry))
          (setq d-exit  (bsrd-dist-at cl-ent p-exit))
          ;; Section points 15' inset from each border edge.
          ;; Stack spans 6*sp = 60' from section point → outermost dim is 75' from edge.
          (if (and d-entry d-exit (> d-exit d-entry))
            (progn
              (setq d-mid (/ (+ d-entry d-exit) 2.0))
              (setq p-mid (bsrd-point-at-dist cl-ent d-mid))
              (setq p1    (bsrd-point-at-dist cl-ent (+ d-entry 15.0)))
              (setq p2    (bsrd-point-at-dist cl-ent (- d-exit  15.0))))
            ;; Fallback: linear offset when arc-length params unavailable
            (progn
              (setq tdir  (bs-vunit (bs-vsub p-exit p-entry)))
              (setq p-mid (bs-vadd p-entry (bs-vscale tdir (/ dist 2.0))))
              (setq p1    (bs-vadd p-entry (bs-vscale tdir 15.0)))
              (setq p2    (bs-vadd p-exit  (bs-vscale tdir -15.0)))))
          ;; Single ref-tvec from midpoint tangent; ref-nvec = perpendicular-right of ref-tvec.
          ;; Both vectors are shared across ALL sections of this CL — full parallelism.
          (setq ref-tvec (if p-mid (bs-tangent-at-pt cl-ent p-mid) nil))
          (setq ref-nvec (if ref-tvec (bs-vperp-right ref-tvec) nil))
          ;; Fallback: derive both from entry→exit chord when midpoint tangent fails
          (if (null ref-tvec)
            (progn
              (setq tdir (bs-vunit (bs-vsub p-exit p-entry)))
              (if tdir
                (progn
                  (setq ref-tvec tdir)
                  (setq ref-nvec (bs-vperp-right tdir))))))
          (if (and ref-tvec ref-nvec)
            (progn
              (if p1
                (progn
                  (setq tvec1 (bs-tangent-at-pt cl-ent p1))
                  (setq nvec1 (if tvec1 (bs-vperp-right tvec1) nil))
                  (if (not tvec1) (setq tvec1 ref-tvec nvec1 ref-nvec))
                  (bsrd-process-section-v2 p1 tvec1 nvec1 centroid
                                           row-cands eop-cands fiber-cands
                                           (bsrd-curve-section-p tvec1 ref-tvec))))
              (if p2
                (progn
                  (setq tvec2 (bs-tangent-at-pt cl-ent p2))
                  (setq nvec2 (if tvec2 (bs-vperp-right tvec2) nil))
                  (if (not tvec2) (setq tvec2 ref-tvec nvec2 ref-nvec))
                  (bsrd-process-section-v2 p2 tvec2 nvec2 centroid
                                           row-cands eop-cands fiber-cands
                                           (bsrd-curve-section-p tvec2 ref-tvec)))))))))))


;;; Process one BORDER entity — gathers all candidates up front.
(defun bsrd-border-ref-vectors (cl-ss bb / i ent ee p-entry p-exit dist best-ent best-ee best-dist d1 d2 dmid pmid tvec nvec chord)
  (setq i 0 best-dist 0.0 best-ent nil best-ee nil)
  (while (< i (sslength cl-ss))
    (setq ent (ssname cl-ss i))
    (setq ee (bsrd-cl-bbox-span ent bb))
    (if ee
      (progn
        (setq p-entry (car ee))
        (setq p-exit (cadr ee))
        (setq dist (distance p-entry p-exit))
        (if (> dist best-dist)
          (progn
            (setq best-dist dist)
            (setq best-ent ent)
            (setq best-ee ee)))))
    (setq i (1+ i)))
  (if (and best-ent best-ee)
    (progn
      (setq p-entry (car best-ee))
      (setq p-exit (cadr best-ee))
      (setq d1 (bsrd-dist-at best-ent p-entry))
      (setq d2 (bsrd-dist-at best-ent p-exit))
      (if (and d1 d2)
        (progn
          (setq dmid (/ (+ d1 d2) 2.0))
          (setq pmid (bsrd-point-at-dist best-ent dmid))))
      (setq tvec (if pmid (bs-tangent-at-pt best-ent pmid) nil))
      (if (null tvec)
        (progn
          (setq chord (bs-vunit (bs-vsub p-exit p-entry)))
          (setq tvec chord)))
      (setq nvec (if tvec (bs-vperp-right tvec) nil))
      (if (and tvec nvec) (list tvec nvec) nil))
    nil)
)

(defun bsrd-make-guide (pt nvec / p1 p2)
  (if (and pt nvec)
    (progn
      (bs-ensure-layer bsrd-guide-layer 8)
      (setq p1 (bs-vadd pt (bs-vscale nvec -160.0)))
      (setq p2 (bs-vadd pt (bs-vscale nvec 160.0)))
      (entmakex
        (list
          '(0 . "LINE")
          '(100 . "AcDbEntity")
          (cons 8 bsrd-guide-layer)
          '(62 . 8)
          (cons 10 (bsrd-flat p1))
          (cons 11 (bsrd-flat p2))))))
  (princ)
)

(defun bsrd-hide-guides ( / )
  (if (tblsearch "LAYER" bsrd-guide-layer)
    (command "_.LAYER" "F" bsrd-guide-layer ""))
  (princ)
)

(defun bsrd-process-border-v2 (border-ent / bb mn mx cx cy centroid
                                 row-cands eop-cands fiber-cands cl-ss i cl-ent)
  (setq bb (bsrd-bbox border-ent))
  (if (null bb)
    (princ " bbox failed, skipped.")
    (progn
      (setq mn (car bb) mx (cadr bb))
      (setq cx       (/ (+ (car mn)  (car mx))  2.0)
            cy       (/ (+ (cadr mn) (cadr mx)) 2.0)
            centroid (list cx cy 0.0))
      ;; Candidates bounded to this border only
      (setq row-cands (bsrd-gather-layers bb bsrd-row-layers bsrd-curve-types))
      (setq eop-cands (bsrd-gather-layers bb bsrd-eop-layers bsrd-curve-types))
      (setq fiber-cands (bsrd-gather-layers bb bsrd-fiber-layers bsrd-curve-types))
      (princ (strcat " ROW=" (itoa (length row-cands))
                     " EOP=" (itoa (length eop-cands))
                     " fiber=" (itoa (length fiber-cands))))
      ;; CL entities crossing the border window
      (setq cl-ss (ssget "_C"
                         (list (car mn) (cadr mn))
                         (list (car mx) (cadr mx))
                         (list (cons 0 bsrd-curve-types)
                               '(-4 . "<OR")
                               (cons 8 "ROAD-CENTERLINE")
                               (cons 8 "CENTERLINE")
                               (cons 8 "ROAD CENTERLINE")
                               '(-4 . "OR>"))))
      (if cl-ss
        (progn
          (princ (strcat " CL=" (itoa (sslength cl-ss))))
          (princ " GUIDE=centerline")
          (setq i 0)
          (while (< i (sslength cl-ss))
            (setq cl-ent (ssname cl-ss i))
            (vl-catch-all-apply 'bsrd-process-cl-v2
              (list cl-ent bb centroid row-cands eop-cands fiber-cands))
            (setq i (1+ i)))
          (setq cl-ss nil))
        (princ " no ROAD-CENTERLINE found."))))
  T)

;;; ============================================================
;;; Environment helpers
;;; ============================================================

(defun bsrd-save-env ()
  (list (cons "CMDECHO"  (getvar "CMDECHO"))
        (cons "CLAYER"   (getvar "CLAYER"))
        (cons "DIMSTYLE" (getvar "DIMSTYLE"))
        (cons "OSMODE"   (getvar "OSMODE"))))

(defun bsrd-restore-env (env)
  (foreach pair env
    (vl-catch-all-apply 'setvar (list (car pair) (cdr pair)))))

(defun bsrd-setup ()
  (setvar "CMDECHO" 0)
  (setvar "OSMODE"  0)
  (bs-ensure-layer "DIM" 7)
  (setvar "CLAYER" "DIM")
  (if (tblsearch "DIMSTYLE" "SQUAN 60")
    (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" "SQUAN 60"))))

;;; ============================================================
;;; Commands
;;; ============================================================

;;; BSROWDIMS — dimension every BORDER rectangle in drawing
(defun c:BSROWDIMS ( / *error* env ss i ent cnt)
  (defun *error* (msg)
    (command "_.UNDO" "_END")
    (bsrd-restore-env env)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\n[BSROWDIMS] Error: " msg)))
    (princ))
  (setq env (bsrd-save-env))
  (bsrd-setup)
  (command "_.UNDO" "_BEGIN")
  (setq cnt 0)
  (princ "\n[BSROWDIMS] Scanning BORDER layer...")
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "BORDER"))))
  (if (null ss)
    (princ "\n[BSROWDIMS] No BORDER polyline entities found.")
    (progn
      (princ (strcat "\n[BSROWDIMS] Found " (itoa (sslength ss)) " BORDER polyline(s)."))
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (princ (strcat "\n[BSROWDIMS] Border " (itoa (1+ i)) "..."))
        (vl-catch-all-apply 'bsrd-process-border-v2 (list ent))
        (setq cnt (1+ cnt) i (1+ i)))
      (setq ss nil)
      (princ (strcat "\n[BSROWDIMS] Done. Processed " (itoa cnt) " border(s)."))))
  (bsrd-hide-guides)
  (command "_.UNDO" "_END")
  (bsrd-restore-env env)
  (princ))

;;; BSROWDIMS1 — pick one BORDER rectangle (must be in model space)
(defun c:BSROWDIMS1 ( / *error* env sel ent edata lyr)
  (defun *error* (msg)
    (command "_.UNDO" "_END")
    (bsrd-restore-env env)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\n[BSROWDIMS1] Error: " msg)))
    (princ))
  (setq env (bsrd-save-env))
  ;; Paper space guard: entsel cannot reach model-space BORDER entities
  (if (= (getvar "CVPORT") 1)
    (progn
      (princ "\n[BSROWDIMS1] You are in PAPER SPACE.")
      (princ "\n             Double-click inside the viewport first, then re-run BSROWDIMS1.")
      (princ "\n             Or use BSROWDIMS to process all borders automatically."))
    (progn
      (setvar "CMDECHO" 1)
      (setq sel (entsel "\nPick BORDER rectangle: "))
      (setvar "CMDECHO" 0)
      (cond
        ((null sel)
         (princ "\n[BSROWDIMS1] Nothing selected — click directly on the rectangle border line."))
        (T
         (setq ent   (car sel))
         (setq edata (entget ent))
         (setq lyr   (cdr (assoc 8 edata)))
         (cond
           ((not (member (cdr (assoc 0 edata)) '("LWPOLYLINE" "POLYLINE")))
            (princ "\n[BSROWDIMS1] Not a polyline — click the rectangle line itself."))
           ((/= (strcase lyr) "BORDER")
            (princ (strcat "\n[BSROWDIMS1] Layer \"" lyr "\" is not BORDER — expected BORDER layer.")))
           (T
            (bsrd-setup)
            (command "_.UNDO" "_BEGIN")
            (princ "\n[BSROWDIMS1] Processing selected border...")
            (vl-catch-all-apply 'bsrd-process-border-v2 (list ent))
            (bsrd-hide-guides)
            (command "_.UNDO" "_END")
            (princ "\n[BSROWDIMS1] Done.")))))))
  (bsrd-restore-env env)
  (princ))

;;; BSROWDIMSC — pick a centerline, auto-find its BORDER rectangle
(defun bsrd-find-border-for-cl (cl-ent / ss i ent bb mid found)
  (setq mid (vl-catch-all-apply
              'vlax-curve-getPointAtDist
              (list cl-ent
                    (/ (vl-catch-all-apply
                         'vlax-curve-getDistAtParam
                         (list cl-ent
                               (vl-catch-all-apply
                                 'vlax-curve-getEndParam (list cl-ent))))
                       2.0))))
  (if (or (null mid) (vl-catch-all-error-p mid))
    (setq mid (bs-ent-midpt cl-ent)))
  (setq found nil)
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "BORDER"))))
  (if (and ss mid)
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (null found))
        (setq ent (ssname ss i))
        (setq bb (bsrd-bbox ent))
        (if (bsrd-pt-in-bbox (bsrd-flat mid) bb)
          (setq found ent))
        (setq i (1+ i)))))
  found)

(defun c:BSROWDIMSC ( / *error* env sel cl-ent edata lyr border bb mn mx cx cy centroid
                         row-cands eop-cands fiber-cands)
  (defun *error* (msg)
    (command "_.UNDO" "_END")
    (bsrd-restore-env env)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\n[BSROWDIMSC] Error: " msg)))
    (princ))
  (setq env (bsrd-save-env))
  (if (= (getvar "CVPORT") 1)
    (progn
      (princ "\n[BSROWDIMSC] You are in PAPER SPACE.")
      (princ "\n             Double-click inside the viewport first, then re-run BSROWDIMSC."))
    (progn
      (setvar "CMDECHO" 1)
      (setq sel (entsel "\nPick ROAD-CENTERLINE: "))
      (setvar "CMDECHO" 0)
      (cond
        ((null sel)
         (princ "\n[BSROWDIMSC] Nothing selected."))
        (T
         (setq cl-ent (car sel))
         (setq edata  (entget cl-ent))
         (setq lyr    (cdr (assoc 8 edata)))
         (cond
           ((not (bsrd-layer-in-list-p lyr bsrd-centerline-layers))
            (princ (strcat "\n[BSROWDIMSC] Layer \"" lyr "\" is not a known centerline layer.")))
           (T
            (setq border (bsrd-find-border-for-cl cl-ent))
            (cond
              ((null border)
               (princ "\n[BSROWDIMSC] No BORDER rectangle contains this centerline's midpoint."))
              (T
               (bsrd-setup)
               (command "_.UNDO" "_BEGIN")
               (setq bb (bsrd-bbox border))
               (setq mn (car bb) mx (cadr bb))
               (setq cx       (/ (+ (car mn)  (car mx))  2.0)
                     cy       (/ (+ (cadr mn) (cadr mx)) 2.0)
                     centroid (list cx cy 0.0))
               (setq row-cands (bsrd-gather-layers bb bsrd-row-layers bsrd-curve-types))
               (setq eop-cands (bsrd-gather-layers bb bsrd-eop-layers bsrd-curve-types))
               (setq fiber-cands (bsrd-gather-layers bb bsrd-fiber-layers bsrd-curve-types))
               (princ "\n[BSROWDIMSC] Processing centerline within border...")
               (vl-catch-all-apply 'bsrd-process-cl-v2
                 (list cl-ent bb centroid row-cands eop-cands fiber-cands))
               (bsrd-hide-guides)
               (command "_.UNDO" "_END")
               (princ "\n[BSROWDIMSC] Done.")))))))))
  (bsrd-restore-env env)
  (princ))

;;; ============================================================
;;; BSROWDIMS-DIAG — diagnostic: lists what's in the border bbox
;;; Run this first to verify layer names match what the code expects.
;;; ============================================================
(defun c:BSROWDIMS-DIAG ( / sel ent bb mn mx tmp cl-n row-n eop-n all-ss i ed lyr layers)
  (setvar "CMDECHO" 1)
  (setq sel (entsel "\nPick BORDER rectangle: "))
  (if (null sel)
    (princ "\nNothing selected.")
    (progn
      (setq ent (car sel))
      (setq bb  (bsrd-bbox ent))
      (if (null bb)
        (princ "\nbbox FAILED — not a valid entity.")
        (progn
          (setq mn (car bb) mx (cadr bb))
          (princ (strcat "\nBbox: ("
                         (rtos (car mn) 2 1) ", " (rtos (cadr mn) 2 1)
                         ") to ("
                         (rtos (car mx) 2 1) ", " (rtos (cadr mx) 2 1) ")"))
          ;; Check expected layers — single ssget per layer, result stored in tmp
          (setq cl-n (length (bsrd-gather-layers bb bsrd-centerline-layers bsrd-curve-types)))
          (setq row-n (length (bsrd-gather-layers bb bsrd-row-layers bsrd-curve-types)))
          (setq eop-n (length (bsrd-gather-layers bb bsrd-eop-layers bsrd-curve-types)))
          (princ (strcat "\nCenterline found:       " (itoa cl-n)  " (need >0)"))
          (princ (strcat "\nROW found:              " (itoa row-n) " (need >0)"))
          (princ (strcat "\nEOP / ROADS-paved found:" (itoa eop-n) " (need >0)"))
          ;; Dump all unique layer names of ALL curves in bbox
          (princ "\n\nAll curve/line layers in bbox (exact spelling):")
          (setq all-ss (ssget "_C"
                              (list (car mn) (cadr mn))
                              (list (car mx) (cadr mx))
                              (list (cons 0 bsrd-curve-types))))
          (if (null all-ss)
            (princ "\n  (none found — check UCS or zoom level)")
            (progn
              (setq layers nil i 0)
              (while (< i (sslength all-ss))
                (setq ed  (entget (ssname all-ss i)))
                (setq lyr (cdr (assoc 8 ed)))
                (if (not (member lyr layers)) (setq layers (cons lyr layers)))
                (setq i (1+ i)))
              (setq all-ss nil)
              (foreach l (vl-sort layers '<)
                (princ (strcat "\n  \"" l "\"")))))))))
  (princ))

(defun c:BSDIMS ( / ) (c:BSROWDIMS))
(defun c:BSDIM1 ( / ) (c:BSROWDIMS1))
(defun c:BSDIMC ( / ) (c:BSROWDIMSC))
(defun c:BSDIAG ( / ) (c:BSROWDIMS-DIAG))

(princ "\n[BSROWDIMS] v9 Loaded. Straight ROW split restored; curve-only verified centerline snap. Commands: BSDIMS / BSDIM1 / BSDIMC / BSDIAG / BSROWDIMS")
(princ)
