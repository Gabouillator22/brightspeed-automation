;;; ============================================================
;;; BSCALLOUTS_AUTO - Sheet-aware Brightspeed callout automation
;;;
;;; Commands:
;;;   BSCALLOUTS-RUN        - structures + buried + aerial
;;;   BSCALLOUTS-STRUCTURES - handhole and bore pit multileaders
;;;   BSCALLOUTS-BURIED     - HDD bore duct multileaders
;;;   BSCALLOUTS-AERIAL     - aerial/elash multileaders + AUBS footage blocks
;;;   BSCALLOUTS-AUDIT      - summary counts only
;;;
;;; First production pass is intentionally non-destructive:
;;; it never deletes old callouts and skips nearby duplicates.
;;; ============================================================

(vl-load-com)

(setq *bsca-callout-layer* "CABLE CALLOUTS")
(setq *bsca-station-layer* "STATIONING")
(setq *bsca-buried-layer* "BURIED FIBER IN DUCT")
(setq *bsca-aerial-layer* "AERIAL FIBER")
(setq *bsca-elash-layer*  "ELASH")
(setq *bsca-hh-layer*     "HANDHOLE")
(setq *bsca-bore-layer*   "BORE PIT")
(setq *bsca-border-layer* "BORDER")
(setq *bsca-aubs-block*   "AUBS")
(setq *bsca-road-layers*  '("ROAD-CENTERLINE" "CENTERLINE" "ROAD CENTERLINE" "CL"))
(setq *bsca-text-height*  5.0)
(setq *bsca-arrow-size*   8.5)
(setq *bsca-landing-dist* 5.0)
(setq *bsca-label-offset* 25.0)
(setq *bsca-label-offsets* '(10.0 14.0 18.0 22.0 28.0 34.0))
(setq *bsca-label-shifts*  '(0.0 15.0 -15.0 25.0 -25.0 40.0 -40.0))
(setq *bsca-label-clear-pad* 5.0)
(setq *bsca-arrow-structure-clearance* 15.0)
(setq *bsca-structure-tol* 35.0)
(setq *bsca-connect-tol*  5.0)
(setq *bsca-dup-radius*   25.0)
(setq *bsca-aubs-scale*   0.6)

;;; ------------------------------------------------------------
;;; Small utilities
;;; ------------------------------------------------------------

(defun bsca-up (s / )
  (if s (strcase s) ""))

(defun bsca-2d (p / )
  (if p (list (car p) (cadr p) 0.0) nil))

(defun bsca-round-ft (n / )
  (fix (+ n 0.5)))

(defun bsca-clamp (v lo hi / )
  (max lo (min hi v)))

(defun bsca-format-sta (dist / hundreds rem)
  (setq hundreds (fix (/ dist 100.0)))
  (setq rem (- dist (* hundreds 100.0)))
  (strcat "STA "
          (if (< hundreds 10) "0" "")
          (itoa hundreds)
          "+"
          (if (< rem 10.0) "0" "")
          (rtos rem 2 0)))

(defun bsca-layer-ss (layer types / )
  (ssget "_X" (list (cons 0 types) (cons 8 layer))))

(defun bsca-append-ss (ss out / i)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq out (append out (list (ssname ss i))))
        (setq i (1+ i)))))
  out)

(defun bsca-curves-on-layers (layers / out layer)
  (setq out nil)
  (foreach layer layers
    (setq out (bsca-append-ss
                (bsca-layer-ss layer "LWPOLYLINE,POLYLINE,LINE")
                out)))
  out)

(defun bsca-inserts-on-layers (layers / out layer)
  (setq out nil)
  (foreach layer layers
    (setq out (bsca-append-ss (bsca-layer-ss layer "INSERT") out)))
  out)

(defun bsca-curve-len (ent / ep len)
  (setq ep (vl-catch-all-apply 'vlax-curve-getEndParam (list ent)))
  (if (vl-catch-all-error-p ep)
    0.0
    (progn
      (setq len (vl-catch-all-apply 'vlax-curve-getDistAtParam (list ent ep)))
      (if (vl-catch-all-error-p len) 0.0 len))))

(defun bsca-dist-at-pt (ent pt / cp d)
  (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p cp)
    0.0
    (progn
      (setq d (vl-catch-all-apply 'vlax-curve-getDistAtPoint (list ent cp)))
      (if (vl-catch-all-error-p d) 0.0 d))))

(defun bsca-pt-at-dist (ent dist / p)
  (setq p (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent dist)))
  (if (vl-catch-all-error-p p) nil (bsca-2d p)))

(defun bsca-closest-on-ent (ent pt / p)
  (setq p (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p p) pt (bsca-2d p)))

(defun bsca-curve-start (ent / p)
  (setq p (vl-catch-all-apply 'vlax-curve-getStartPoint (list ent)))
  (if (vl-catch-all-error-p p) nil (bsca-2d p)))

(defun bsca-curve-end (ent / p)
  (setq p (vl-catch-all-apply 'vlax-curve-getEndPoint (list ent)))
  (if (vl-catch-all-error-p p) nil (bsca-2d p)))

(defun bsca-same-pt-p (a b tol / )
  (and a b (<= (distance a b) tol)))

(defun bsca-point-key (pt / scale)
  (setq scale *bsca-connect-tol*)
  (strcat
    (itoa (fix (+ 0.5 (/ (car pt) scale))))
    ","
    (itoa (fix (+ 0.5 (/ (cadr pt) scale))))))

(defun bsca-handle (ent / )
  (cdr (assoc 5 (entget ent))))

(defun bsca-ent-in-list-p (ent items / found item h)
  (setq found nil h (bsca-handle ent))
  (foreach item items
    (if (= h (bsca-handle item)) (setq found T)))
  found)

(defun bsca-nearest-curve (pt curves / best bestd d ent)
  (setq best nil bestd 1.0e99)
  (foreach ent curves
    (setq d (bs-dist-to-ent pt ent))
    (if (< d bestd)
      (setq best ent bestd d)))
  best)

(defun bsca-graph-add-node (key pt nodes / rec)
  (if (assoc key nodes)
    nodes
    (append nodes (list (list key pt)))))

(defun bsca-graph-build (curves / nodes edges ent sp ep sk ek len)
  (setq nodes nil edges nil)
  (foreach ent curves
    (setq sp (bsca-curve-start ent)
          ep (bsca-curve-end ent)
          len (bsca-curve-len ent))
    (if (and sp ep (> len 0.0))
      (progn
        (setq sk (bsca-point-key sp)
              ek (bsca-point-key ep))
        (setq nodes (bsca-graph-add-node sk sp nodes))
        (setq nodes (bsca-graph-add-node ek ep nodes))
        (setq edges (append edges (list (list sk ek len ent)))))))
  (list nodes edges))

(defun bsca-node-degree (key edges / n e)
  (setq n 0)
  (foreach e edges
    (if (or (= key (car e)) (= key (cadr e)))
      (setq n (1+ n))))
  n)

(defun bsca-graph-start-key (nodes edges / best key)
  ;; Pick an open endpoint when available. This is the practical route start
  ;; for imported KMZ chains and avoids resetting stationing at every block.
  (setq best nil)
  (foreach n nodes
    (setq key (car n))
    (if (and (not best) (= (bsca-node-degree key edges) 1))
      (setq best key)))
  (if best best (car (car nodes))))

(defun bsca-dist-get (key dist / rec)
  (setq rec (assoc key dist))
  (if rec (cadr rec) 1.0e99))

(defun bsca-dist-set (key val dist / out done item)
  (setq out nil done nil)
  (foreach item dist
    (if (= (car item) key)
      (progn
        (setq out (append out (list (list key val))))
        (setq done T))
      (setq out (append out (list item)))))
  (if done out (append out (list (list key val)))))

(defun bsca-unvisited-min (unvisited dist / best bestd d key)
  (setq best nil bestd 1.0e99)
  (foreach key unvisited
    (setq d (bsca-dist-get key dist))
    (if (< d bestd)
      (setq best key bestd d)))
  best)

(defun bsca-remove-key (key items / out item)
  (setq out nil)
  (foreach item items
    (if (/= item key)
      (setq out (append out (list item)))))
  out)

(defun bsca-graph-distances (graph start / nodes edges unvisited dist n key cur curd e other nd)
  (setq nodes (car graph)
        edges (cadr graph)
        unvisited nil
        dist nil)
  (foreach n nodes
    (setq key (car n))
    (setq unvisited (append unvisited (list key)))
    (setq dist (append dist (list (list key (if (= key start) 0.0 1.0e99))))))
  (while unvisited
    (setq cur (bsca-unvisited-min unvisited dist))
    (setq unvisited (bsca-remove-key cur unvisited))
    (setq curd (bsca-dist-get cur dist))
    (if (< curd 1.0e98)
      (foreach e edges
        (setq other nil)
        (cond
          ((= cur (car e)) (setq other (cadr e)))
          ((= cur (cadr e)) (setq other (car e))))
        (if other
          (progn
            (setq nd (+ curd (caddr e)))
            (if (< nd (bsca-dist-get other dist))
              (setq dist (bsca-dist-set other nd dist))))))))
  dist)

(defun bsca-cumulative-station (pt curves / graph nodes edges start dist ent cp local len sk ek ds de)
  (setq ent (bsca-nearest-curve pt curves))
  (if ent
    (progn
      (setq graph (bsca-graph-build curves)
            nodes (car graph)
            edges (cadr graph)
            start (bsca-graph-start-key nodes edges)
            dist (bsca-graph-distances graph start)
            cp (bsca-closest-on-ent ent pt)
            local (bsca-dist-at-pt ent cp)
            len (bsca-curve-len ent)
            sk (bsca-point-key (bsca-curve-start ent))
            ek (bsca-point-key (bsca-curve-end ent))
            ds (+ (bsca-dist-get sk dist) local)
            de (+ (bsca-dist-get ek dist) (- len local)))
      (min ds de))
    0.0))

(defun bsca-cumulative-station-by-tech (pt / buried aerial nb na db da curves)
  ;; Aerial and buried station chains reset from each other. Pick the nearest
  ;; technology section first, then calculate cumulative station inside it.
  (setq buried (bsca-curves-on-layers (list *bsca-buried-layer*)))
  (setq aerial (bsca-curves-on-layers (list *bsca-aerial-layer* *bsca-elash-layer*)))
  (setq nb (if buried (bsca-nearest-curve pt buried) nil))
  (setq na (if aerial (bsca-nearest-curve pt aerial) nil))
  (setq db (if nb (bs-dist-to-ent pt nb) 1.0e99))
  (setq da (if na (bs-dist-to-ent pt na) 1.0e99))
  (setq curves (if (<= db da) buried aerial))
  (if curves (bsca-cumulative-station pt curves) 0.0))

;;; ------------------------------------------------------------
;;; Border/sheet helpers
;;; ------------------------------------------------------------

(defun bsca-lwpoly-verts (ent / data verts pair)
  (setq data (entget ent) verts nil)
  (foreach pair data
    (if (= (car pair) 10)
      (setq verts (append verts (list (list (cadr pair) (caddr pair) 0.0))))))
  verts)

(defun bsca-point-in-poly (pt verts / inside j i pi pj xi yi xj yj px py)
  (setq inside nil px (car pt) py (cadr pt))
  (if (> (length verts) 2)
    (progn
      (setq i 0 j (1- (length verts)))
      (while (< i (length verts))
        (setq pi (nth i verts)
              pj (nth j verts)
              xi (car pi)
              yi (cadr pi)
              xj (car pj)
              yj (cadr pj))
        (if (and (/= (> yi py) (> yj py))
                 (< px (+ xi (/ (* (- xj xi) (- py yi)) (- yj yi)))))
          (setq inside (not inside)))
        (setq j i i (1+ i)))))
  inside)

(defun bsca-border-list ( / ss out i ent verts)
  (setq ss (bsca-layer-ss *bsca-border-layer* "LWPOLYLINE"))
  (setq out nil)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq verts (bsca-lwpoly-verts ent))
        (if (> (length verts) 2)
          (setq out (append out (list (list ent verts)))))
        (setq i (1+ i)))))
  out)

(defun bsca-borders-for-curve-range (ent d1 d2 borders / out steps k dist pt border found)
  (setq out nil steps 8 k 0)
  (while (<= k steps)
    (setq dist (+ d1 (* (/ (float k) steps) (- d2 d1))))
    (setq pt (bsca-pt-at-dist ent dist))
    (if pt
      (foreach border borders
        (if (and (bsca-point-in-poly pt (cadr border))
                 (not (assoc (bsca-handle (car border)) out)))
          (setq out (append out (list (list (bsca-handle (car border)) pt)))))))
    (setq k (1+ k)))
  out)

(defun bsca-border-by-handle (borders h / found border)
  (setq found nil)
  (foreach border borders
    (if (= h (bsca-handle (car border)))
      (setq found border)))
  found)

(defun bsca-place-point-for-border (fallback border-hit / )
  (if border-hit (cadr border-hit) fallback))

;;; ------------------------------------------------------------
;;; Existing callout / duplicate detection
;;; ------------------------------------------------------------

(defun bsca-object-text (ent / data typ obj txt)
  (setq data (entget ent)
        typ  (cdr (assoc 0 data))
        txt  nil)
  (cond
    ((= typ "TEXT")  (setq txt (cdr (assoc 1 data))))
    ((= typ "MTEXT") (setq txt (cdr (assoc 1 data))))
    ((= typ "MULTILEADER")
      (setq obj (vlax-ename->vla-object ent))
      (setq txt (vl-catch-all-apply 'vla-get-TextString (list obj)))
      (if (vl-catch-all-error-p txt) (setq txt nil))))
  txt)

(defun bsca-object-point (ent / data obj p)
  (setq data (entget ent))
  (cond
    ((assoc 10 data) (bsca-2d (cdr (assoc 10 data))))
    (T
      (setq obj (vlax-ename->vla-object ent))
      (setq p (vl-catch-all-apply 'vla-get-InsertionPoint (list obj)))
      (if (vl-catch-all-error-p p) nil (vlax-safearray->list (vlax-variant-value p))))))

(defun bsca-existing-callout-p (text pt / ss i ent txt ept found)
  (setq ss (ssget "_X" (list (cons 8 *bsca-callout-layer*)))
        found nil)
  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i)
              txt (bsca-object-text ent)
              ept (bsca-object-point ent))
        (if (and txt ept
                 (= (bsca-up txt) (bsca-up text))
                 (<= (distance ept pt) *bsca-dup-radius*))
          (setq found T))
        (setq i (1+ i)))))
  found)

(defun bsca-existing-text-on-layer-p (text pt layer / ss i ent txt ept found)
  (setq ss (ssget "_X" (list (cons 8 layer)))
        found nil)
  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i)
              txt (bsca-object-text ent)
              ept (bsca-object-point ent))
        (if (and txt ept
                 (= (bsca-up txt) (bsca-up text))
                 (<= (distance ept pt) *bsca-dup-radius*))
          (setq found T))
        (setq i (1+ i)))))
  found)

;;; ------------------------------------------------------------
;;; Entity creation
;;; ------------------------------------------------------------

(defun bsca-ensure-callout-layer ( / )
  (bs-ensure-layer *bsca-callout-layer* 7))

(defun bsca-ensure-station-layer ( / )
  (bs-ensure-layer *bsca-station-layer* 7))

(defun bsca-set-prop-safe (obj prop value / )
  (vl-catch-all-apply 'vlax-put-property (list obj prop value)))

(defun bsca-apply-mleader-box (obj / )
  ;; Restore the earlier working look: filled callout with visible frame.
  (bsca-set-prop-safe obj 'TextBackgroundFill :vlax-true)
  (bsca-set-prop-safe obj 'TextBackgroundScaleFactor 1.1)
  (bsca-set-prop-safe obj 'TextFrameDisplay :vlax-true)
  (bsca-set-prop-safe obj 'EnableFrameText :vlax-true)
  (bsca-set-prop-safe obj 'BackgroundFill :vlax-true)
  obj)

(defun bsca-apply-mleader-rotation (obj angle / )
  (if angle
    (progn
      (bsca-set-prop-safe obj 'TextRotation angle)
      (bsca-set-prop-safe obj 'Rotation angle)))
  obj)

(defun bsca-leader-landing-point (arrow-pt text-pt text / width left-x right-x y)
  ;; Land the leader on the closest outside edge of the text background so the
  ;; leader does not run underneath the filled callout text.
  (setq width (bsca-text-box-width text))
  (setq left-x (- (car text-pt) 2.0))
  (setq right-x (+ (car text-pt) width 2.0))
  (setq y (cadr text-pt))
  (if (< (car arrow-pt) (car text-pt))
    (list left-x y 0.0)
    (list right-x y 0.0)))

(defun bsca-make-mleader (arrow-pt text-pt text / doc ms arr arr2 obj made old-layer landing)
  (bsca-ensure-callout-layer)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms  (vla-get-ModelSpace doc))
  (setq landing (bsca-leader-landing-point arrow-pt text-pt text))
  (setq arr (vlax-make-safearray vlax-vbDouble '(0 . 8)))
  (vlax-safearray-fill arr
    (list (car arrow-pt) (cadr arrow-pt) 0.0
          (car landing)  (cadr landing)  0.0
          (car text-pt)  (cadr text-pt)  0.0))
  (setq obj (vl-catch-all-apply 'vla-AddMLeader (list ms arr 0)))
  (if (vl-catch-all-error-p obj)
    (progn
      ;; Some AutoCAD builds only accept a 2-point array through ActiveX.
      ;; Retry before falling back to plain line/text.
      (setq arr2 (vlax-make-safearray vlax-vbDouble '(0 . 5)))
      (vlax-safearray-fill arr2
        (list (car arrow-pt) (cadr arrow-pt) 0.0
              (car text-pt)  (cadr text-pt)  0.0))
      (setq obj (vl-catch-all-apply 'vla-AddMLeader (list ms arr2 0)))))
  (if (vl-catch-all-error-p obj)
    (progn
      ;; Fallback keeps the workflow usable if an AutoCAD edition rejects
      ;; AddMLeader from ActiveX. The audit will still flag this for cleanup.
      (bs-make-leader-line arrow-pt text-pt *bsca-callout-layer*)
      (bs-make-text text-pt *bsca-text-height* *bsca-callout-layer* text)
      nil)
    (progn
      (bsca-set-prop-safe obj 'Layer *bsca-callout-layer*)
      (bsca-set-prop-safe obj 'TextString text)
      (bsca-set-prop-safe obj 'TextHeight *bsca-text-height*)
      (bsca-set-prop-safe obj 'ArrowheadSize *bsca-arrow-size*)
      (bsca-set-prop-safe obj 'ArrowSymbol "Closed filled")
      (bsca-set-prop-safe obj 'LandingGap *bsca-landing-dist*)
      (bsca-set-prop-safe obj 'DoglegLength *bsca-landing-dist*)
      (bsca-apply-mleader-box obj)
      obj)))

(defun bsca-insert-aubs (pt angle text / ent obj props prop pname)
  (if (bsca-existing-aubs-p pt)
    nil
    (if (tblsearch "BLOCK" *bsca-aubs-block*)
    (progn
      (setq ent
        (entmakex
          (list
            '(0 . "INSERT")
            (cons 2 *bsca-aubs-block*)
            (cons 8 "0")
            (cons 10 (list (car pt) (cadr pt) 0.0))
            (cons 41 *bsca-aubs-scale*)
            (cons 42 *bsca-aubs-scale*)
            (cons 43 *bsca-aubs-scale*)
            (cons 50 angle))))
      (if ent
        (progn
          (setq obj (vlax-ename->vla-object ent))
          (setq props (vl-catch-all-apply 'vlax-invoke (list obj 'GetDynamicBlockProperties)))
          (if (not (vl-catch-all-error-p props))
            (foreach prop props
              (setq pname (vlax-get-property prop 'PropertyName))
              (if (= (bsca-up pname) "SL")
                (vl-catch-all-apply 'vlax-put-property (list prop 'Value text)))))))
      ent)
    (bsca-make-mleader pt (bs-vadd pt (list 15.0 10.0 0.0)) text))))

(defun bsca-make-station-mtext (ins-pt text angle / doc ms obj)
  (bsca-ensure-station-layer)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms  (vla-get-ModelSpace doc))
  (setq obj (vla-AddMText ms (vlax-3d-point ins-pt) 0.0 text))
  (bsca-set-prop-safe obj 'Layer *bsca-station-layer*)
  (bsca-set-prop-safe obj 'TextHeight *bsca-text-height*)
  (bsca-set-prop-safe obj 'AttachmentPoint 5)
  (bsca-set-prop-safe obj 'BackgroundFill :vlax-true)
  (bsca-set-prop-safe obj 'UseBackgroundColor :vlax-true)
  (if angle
    (bsca-set-prop-safe obj 'Rotation angle))
  obj)

(defun bsca-add-station-callout-if-new (text arrow-pt text-pt angle / line mt)
  (if (bsca-existing-text-on-layer-p text text-pt *bsca-station-layer*)
    nil
    (progn
      (setq line (bs-make-leader-line arrow-pt text-pt *bsca-callout-layer*))
      (setq mt (bsca-make-station-mtext text-pt text angle))
      (if mt mt line))))

(defun bsca-existing-aubs-p (pt / ss i ent ip found)
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 *bsca-aubs-block*)))
        found nil)
  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i)
              ip  (bsca-2d (cdr (assoc 10 (entget ent)))))
        (if (and ip (<= (distance ip pt) *bsca-dup-radius*))
          (setq found T))
        (setq i (1+ i)))))
  found)

;;; ------------------------------------------------------------
;;; Label placement helpers
;;; ------------------------------------------------------------

(defun bsca-label-side (ent pt / tan perp)
  (setq tan (bs-tangent-at-pt ent pt))
  (if tan
    (bs-vperp-left tan)
    (list 0.0 1.0 0.0)))

(defun bsca-text-point (ent arrow-pt / side)
  (setq side (bsca-label-side ent arrow-pt))
  (bs-vadd arrow-pt (bs-vscale side *bsca-label-offset*)))

(defun bsca-curve-side-dir (ent pt / tan side)
  (setq tan (bs-tangent-at-pt ent pt))
  (if tan
    (bs-vunit (bs-vperp-left tan))
    (list 0.0 1.0 0.0)))

(defun bsca-road-side-dir (ent pt / roads road cp v fallback)
  ;; Prefer the side from nearest road centerline to fiber. That keeps the
  ;; label on the same side of the road/ROW as the buried fiber.
  (setq fallback (bsca-curve-side-dir ent pt))
  (setq roads (bsca-curves-on-layers *bsca-road-layers*))
  (setq road (if roads (bsca-nearest-curve pt roads) nil))
  (if road
    (progn
      (setq cp (bsca-closest-on-ent road pt))
      (setq v (bs-vsub pt cp))
      (if (> (bs-vlen v) 0.01)
        (bs-vunit v)
        fallback))
    fallback))

(defun bsca-text-box-width (text / )
  (max 70.0 (* (strlen text) *bsca-text-height* 0.72)))

(defun bsca-text-anchor-for-side (desired text side / width)
  ;; MLeader text grows to the right from its insertion point. Move that
  ;; insertion point so the full rectangle stays on the requested side.
  (setq width (bsca-text-box-width text))
  (cond
    ((< (car side) -0.15)
      (list (- (car desired) width) (cadr desired) 0.0))
    ((> (car side) 0.15)
      desired)
    (T
      (list (- (car desired) (/ width 2.0)) (cadr desired) 0.0))))

(defun bsca-rect-from-textpt (textpt text / width height pad)
  ;; Approximate an unrotated callout text box. The actual MLeader frame is
  ;; created by AutoCAD; this rectangle is for collision testing only.
  (setq width (bsca-text-box-width text))
  (setq height (* *bsca-text-height* 2.6))
  (setq pad *bsca-label-clear-pad*)
  (list
    (list (- (car textpt) pad) (- (cadr textpt) (+ (/ height 2.0) pad)) 0.0)
    (list (+ (car textpt) width pad) (- (cadr textpt) (+ (/ height 2.0) pad)) 0.0)
    (list (+ (car textpt) width pad) (+ (cadr textpt) (+ (/ height 2.0) pad)) 0.0)
    (list (- (car textpt) pad) (+ (cadr textpt) (+ (/ height 2.0) pad)) 0.0)))

(defun bsca-rect-inside-border-p (rect border / ok corner)
  (if (not border)
    T
    (progn
      (setq ok T)
      (foreach corner rect
        (if (not (bsca-point-in-poly corner (cadr border)))
          (setq ok nil)))
      ok)))

(defun bsca-rect-window (rect / xs ys)
  (setq xs (mapcar 'car rect))
  (setq ys (mapcar 'cadr rect))
  (list
    (list (apply 'min xs) (apply 'min ys) 0.0)
    (list (apply 'max xs) (apply 'max ys) 0.0)))

(defun bsca-ignored-blocker-p (ent source-ent / data typ layer)
  (setq data (entget ent)
        typ (cdr (assoc 0 data))
        layer (bsca-up (cdr (assoc 8 data))))
  (or (= (bsca-handle ent) (bsca-handle source-ent))
      (= typ "IMAGE")
      (= typ "RASTERIMAGE")
      (= typ "WIPEOUT")
      (= typ "VIEWPORT")
      (= layer (bsca-up *bsca-border-layer*))))

(defun bsca-label-blocked-p (textpt text source-ent / rect win ss i ent blocked)
  (setq rect (bsca-rect-from-textpt textpt text))
  (setq win (bsca-rect-window rect))
  (setq ss (ssget "_C" (car win) (cadr win)))
  (setq blocked nil)
  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (not blocked))
        (setq ent (ssname ss i))
        (if (not (bsca-ignored-blocker-p ent source-ent))
          (setq blocked T))
        (setq i (1+ i)))))
  blocked)

(defun bsca-clear-buried-text-point (ent arrow-pt text border / side tan shift off desired candidate rect best fallback)
  ;; Try several same-side offsets and along-line shifts. First clear
  ;; rectangle wins; fallback remains on the fiber side if every spot is busy.
  (setq side (bsca-road-side-dir ent arrow-pt))
  (setq tan (bs-tangent-at-pt ent arrow-pt))
  (setq tan (if tan (bs-vunit tan) (list 1.0 0.0 0.0)))
  (setq best nil fallback nil)
  (foreach off *bsca-label-offsets*
    (foreach shift *bsca-label-shifts*
      (if (not best)
        (progn
          (setq candidate
            (progn
              (setq desired
                (bs-vadd
                  (bs-vadd arrow-pt (bs-vscale side off))
                  (bs-vscale tan shift)))
              (bsca-text-anchor-for-side desired text side)))
          (setq rect (bsca-rect-from-textpt candidate text))
          (if (bsca-rect-inside-border-p rect border)
            (progn
              (setq fallback candidate)
              (if (not (bsca-label-blocked-p candidate text ent))
                (setq best candidate))))))))
  (if best
    best
    (if fallback
      fallback
      (bsca-text-anchor-for-side
        (bs-vadd arrow-pt (bs-vscale side *bsca-label-offset*))
        text
        side))))

(defun bsca-add-mleader-if-new (text arrow-pt text-pt / )
  (if (bsca-existing-callout-p text text-pt)
    nil
    (bsca-make-mleader arrow-pt text-pt text)))

(defun bsca-add-mleader-if-new-rot (text arrow-pt text-pt angle / obj)
  (if (bsca-existing-callout-p text text-pt)
    nil
    (progn
      (setq obj (bsca-make-mleader arrow-pt text-pt text))
      (if obj (bsca-apply-mleader-rotation obj angle))
      obj)))

;;; ------------------------------------------------------------
;;; Structure callouts
;;; ------------------------------------------------------------

(defun bsca-borepit-p (ent / layer bname)
  (setq layer (bsca-up (cdr (assoc 8 (entget ent)))))
  (setq bname (bsca-up (cdr (assoc 2 (entget ent)))))
  (or (= layer (bsca-up *bsca-bore-layer*))
      (vl-string-search "BORE" bname)))

(defun bsca-handhole-p (ent / layer bname)
  (setq layer (bsca-up (cdr (assoc 8 (entget ent)))))
  (setq bname (bsca-up (cdr (assoc 2 (entget ent)))))
  (or (= layer (bsca-up *bsca-hh-layer*))
      (= layer "HANDHOLES")
      (vl-string-search "HANDHOLE" bname)
      (vl-string-search "HH" bname)))

(defun bsca-structure-inserts ( / ss out i ent)
  (setq ss (ssget "_X" '((0 . "INSERT")))
        out nil)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if (or (bsca-handhole-p ent) (bsca-borepit-p ent))
          (setq out (append out (list ent))))
        (setq i (1+ i)))))
  out)

(defun bsca-structure-text (ent station / layer bname)
  (setq layer (bsca-up (cdr (assoc 8 (entget ent)))))
  (setq bname (bsca-up (cdr (assoc 2 (entget ent)))))
  (cond
    ((bsca-borepit-p ent)
      (strcat station " PL\\P36\"x36\" BORE PIT"))
    (T
      (strcat station " PL\\PHANDHOLE"))))

(defun bsca-structure-point (ent / p)
  (setq p (cdr (assoc 10 (entget ent))))
  (bsca-2d p))

(defun bsca-structure-rotation (ent / rot)
  (setq rot (cdr (assoc 50 (entget ent))))
  (if rot rot 0.0))

(defun bsca-structure-text-point (ent pt / angle along side)
  (setq angle (bsca-structure-rotation ent))
  (setq along (list (cos angle) (sin angle) 0.0))
  (setq side (bs-vperp-left along))
  (bs-vadd (bs-vadd pt (bs-vscale along 12.0)) (bs-vscale side 14.0)))

(defun bsca-place-structure-callouts ( / structs curves ent pt station txt textpt angle placed skipped)
  (setq structs (bsca-structure-inserts))
  (setq curves  (bsca-curves-on-layers (list *bsca-buried-layer* *bsca-aerial-layer* *bsca-elash-layer*)))
  (setq placed 0 skipped 0)
  (foreach ent structs
    (setq pt (bsca-structure-point ent))
    (if (and pt curves)
      (progn
        (setq station (bsca-format-sta (bsca-cumulative-station-by-tech pt)))
        (setq txt (bsca-structure-text ent station))
        (setq textpt (bsca-structure-text-point ent pt))
        (setq angle (if (or (bsca-borepit-p ent) (bsca-handhole-p ent))
                      (bsca-structure-rotation ent)
                      nil))
        (if (bsca-add-station-callout-if-new txt pt textpt angle)
          (setq placed (1+ placed))
          (setq skipped (1+ skipped))))
      (setq skipped (1+ skipped))))
  (list placed skipped))

(defun c:BSCALLOUTS-STRUCTURES ( / old-cmdecho result)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (setq result (bsca-place-structure-callouts))
  (command "_.UNDO" "_E")
  (setvar "CMDECHO" old-cmdecho)
  (princ (strcat "\n[BSCALLOUTS-STRUCTURES] placed="
                 (itoa (car result)) " skipped=" (itoa (cadr result))))
  (princ))

;;; ------------------------------------------------------------
;;; Buried fiber callouts
;;; ------------------------------------------------------------

(defun bsca-projected-structures-on-curve (ent structs / out s pt d cp sd)
  (setq out nil)
  (foreach s structs
    (setq pt (bsca-structure-point s))
    (if pt
      (progn
        (setq cp (bsca-closest-on-ent ent pt))
        (setq d (distance pt cp))
        (if (<= d *bsca-structure-tol*)
          (progn
            (setq sd (bsca-dist-at-pt ent cp))
            (setq out (append out (list (list sd s cp)))))))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

(defun bsca-intervals-from-structure-dists (len hits / vals out i a b)
  (setq vals nil)
  (foreach h hits (setq vals (append vals (list (car h)))))
  (if (not vals)
    (setq vals (list 0.0 len))
    (progn
      (if (> (car vals) 1.0) (setq vals (cons 0.0 vals)))
      (if (< (car (last vals)) (- len 1.0)) (setq vals (append vals (list len))))))
  (setq out nil i 0)
  (while (< i (1- (length vals)))
    (setq a (nth i vals)
          b (nth (1+ i) vals))
    (if (> (- b a) 1.0)
      (setq out (append out (list (list a b)))))
    (setq i (1+ i)))
  out)

(defun bsca-buried-arrow-point (ent d1 d2 preferred / seg clear low high pd)
  ;; Keep HDD bore leader tips on the fiber, but never inside the structure
  ;; block at either end. For short segments, use the midpoint.
  (setq seg (- d2 d1))
  (setq clear (min *bsca-arrow-structure-clearance* (/ seg 3.0)))
  (setq low (+ d1 clear))
  (setq high (- d2 clear))
  (if (<= high low)
    (bsca-pt-at-dist ent (/ (+ d1 d2) 2.0))
    (progn
      (setq pd (if preferred (bsca-dist-at-pt ent preferred) (/ (+ d1 d2) 2.0)))
      (bsca-pt-at-dist ent (bsca-clamp pd low high)))))

(defun bsca-place-buried-callouts ( / ss structs borders i ent len hits intervals interval
                                      d1 d2 seglen mid arrow text textpt border-hits bh border
                                      placed skipped)
  (setq ss (bsca-layer-ss *bsca-buried-layer* "LWPOLYLINE,POLYLINE"))
  (setq placed 0 skipped 0)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq len (bsca-curve-len ent))
        (if (> len 1.0)
          (progn
            (setq mid (/ len 2.0)
                  arrow (bsca-pt-at-dist ent mid)
                  text (strcat "HDD BORE " (itoa (bsca-round-ft len)) "' FIBER IN 2\" DUCT"))
            (if arrow
              (progn
                ;; Legacy stable placement: one label per buried segment.
                ;; Avoids the sheet/structure split path that caused cons errors.
                (setq textpt (bsca-clear-buried-text-point ent arrow text nil))
                (if (bsca-add-mleader-if-new text arrow textpt)
                  (setq placed (1+ placed))
                  (setq skipped (1+ skipped))))
              (setq skipped (1+ skipped))))
          (setq skipped (1+ skipped)))
        (setq i (1+ i)))))
  (list placed skipped))

(defun c:BSCALLOUTS-BURIED ( / old-cmdecho result)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (setq result (bsca-place-buried-callouts))
  (command "_.UNDO" "_E")
  (setvar "CMDECHO" old-cmdecho)
  (princ (strcat "\n[BSCALLOUTS-BURIED] placed="
                 (itoa (car result)) " skipped=" (itoa (cadr result))))
  (princ))

;;; ------------------------------------------------------------
;;; Aerial / elash callouts and AUBS footage markers
;;; ------------------------------------------------------------

(defun bsca-aerial-text (ent / layer)
  (setq layer (bsca-up (cdr (assoc 8 (entget ent)))))
  (if (= layer (bsca-up *bsca-elash-layer*))
    "AERIAL FIBER ELASHED TO EXISTING"
    "NEW AERIAL FIBER STRAND"))

(defun bsca-poles-on-curve (ent / poles out i p pt cp d sd)
  (setq poles (ssget "_X" '((0 . "INSERT"))))
  (setq out nil)
  (if poles
    (progn
      (setq i 0)
      (while (< i (sslength poles))
        (setq p (ssname poles i))
        (if (vl-string-search "POLE" (bsca-up (cdr (assoc 2 (entget p)))))
          (progn
            (setq pt (bsca-structure-point p))
            (setq cp (bsca-closest-on-ent ent pt))
            (setq d (distance pt cp))
            (if (<= d *bsca-structure-tol*)
              (progn
                (setq sd (bsca-dist-at-pt ent cp))
                (setq out (append out (list (list sd p cp))))))))
        (setq i (1+ i)))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

(defun bsca-aerial-intervals (len poles / vals out i a b)
  (setq vals nil)
  (foreach p poles (setq vals (append vals (list (car p)))))
  (if (< (length vals) 2)
    (setq vals (list 0.0 len)))
  (setq out nil i 0)
  (while (< i (1- (length vals)))
    (setq a (nth i vals)
          b (nth (1+ i) vals))
    (if (> (- b a) 1.0)
      (setq out (append out (list (list a b)))))
    (setq i (1+ i)))
  out)

(defun bsca-place-aerial-callouts ( / curves borders ent len poles intervals interval
                                     d1 d2 mid seglen arrow text textpt border-hits bh
                                     marker-pt tan angle placed skipped markers)
  (setq curves (bsca-curves-on-layers (list *bsca-aerial-layer* *bsca-elash-layer*)))
  (setq borders (bsca-border-list))
  (setq placed 0 skipped 0 markers 0)
  (foreach ent curves
    (setq len (bsca-curve-len ent))
    (setq poles (bsca-poles-on-curve ent))
    (setq intervals (bsca-aerial-intervals len poles))
    (foreach interval intervals
      (setq d1 (car interval)
            d2 (cadr interval)
            seglen (- d2 d1)
            mid (/ (+ d1 d2) 2.0)
            text (bsca-aerial-text ent)
            border-hits (bsca-borders-for-curve-range ent d1 d2 borders))
      (if (not border-hits) (setq border-hits (list nil)))
      (foreach bh border-hits
        (setq arrow (if bh (cadr bh) (bsca-pt-at-dist ent mid)))
        (if arrow
          (progn
            (setq textpt (bsca-text-point ent arrow))
            (if (bsca-add-mleader-if-new text arrow textpt)
              (setq placed (1+ placed))
              (setq skipped (1+ skipped)))
            (setq marker-pt (bs-vadd arrow (bs-vscale (bsca-label-side ent arrow) 12.0)))
            (setq tan (bs-tangent-at-pt ent arrow))
            (setq angle (if tan (atan (cadr tan) (car tan)) 0.0))
            (if (bsca-insert-aubs marker-pt angle
                  (strcat (itoa (bsca-round-ft seglen)) "'"))
              (setq markers (1+ markers))))
          (setq skipped (1+ skipped))))))
  (list placed skipped markers))

(defun c:BSCALLOUTS-AERIAL ( / old-cmdecho result)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (setq result (bsca-place-aerial-callouts))
  (command "_.UNDO" "_E")
  (setvar "CMDECHO" old-cmdecho)
  (princ (strcat "\n[BSCALLOUTS-AERIAL] callouts="
                 (itoa (car result)) " skipped=" (itoa (cadr result))
                 " markers=" (itoa (caddr result))))
  (princ))

;;; ------------------------------------------------------------
;;; Master and audit
;;; ------------------------------------------------------------

(defun bsca-count-structures (structs / hh bore other)
  (setq hh 0 bore 0 other 0)
  (foreach ent structs
    (cond
      ((bsca-borepit-p ent) (setq bore (1+ bore)))
      ((bsca-handhole-p ent) (setq hh (1+ hh)))
      (T (setq other (1+ other)))))
  (list hh bore other))

(defun bsca-count-callout-texts ( / ss i ent txt hh bore)
  (setq ss (ssget "_X" (list (cons 8 *bsca-station-layer*)))
        i 0
        hh 0
        bore 0)
  (if ss
    (while (< i (sslength ss))
      (setq ent (ssname ss i))
      (setq txt (bsca-up (bsca-object-text ent)))
      (if (vl-string-search "HANDHOLE" txt)
        (setq hh (1+ hh)))
      (if (vl-string-search "BORE PIT" txt)
        (setq bore (1+ bore)))
      (setq i (1+ i))))
  (list hh bore))

(defun c:BSCALLOUTS-RUN ( / r1 r2 r3 old-cmdecho)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (setq r1 (bsca-place-structure-callouts))
  (setq r2 (bsca-place-buried-callouts))
  (setq r3 (bsca-place-aerial-callouts))
  (command "_.UNDO" "_E")
  (setvar "CMDECHO" old-cmdecho)
  (princ "\n[BSCALLOUTS-RUN] Complete.")
  (princ (strcat "\n  Structures placed/skipped: " (itoa (car r1)) "/" (itoa (cadr r1))))
  (princ (strcat "\n  Buried placed/skipped:     " (itoa (car r2)) "/" (itoa (cadr r2))))
  (princ (strcat "\n  Aerial placed/skipped:     " (itoa (car r3)) "/" (itoa (cadr r3))))
  (princ (strcat "\n  Aerial markers placed:     " (itoa (caddr r3))))
  (princ))

(defun c:BSCALLOUTS-AUDIT ( / structs buried aerial elash callouts sc cc)
  (setq structs (bsca-structure-inserts))
  (setq buried (bsca-layer-ss *bsca-buried-layer* "LWPOLYLINE,POLYLINE"))
  (setq aerial (bsca-layer-ss *bsca-aerial-layer* "LWPOLYLINE,POLYLINE"))
  (setq elash  (bsca-layer-ss *bsca-elash-layer* "LWPOLYLINE,POLYLINE"))
  (setq callouts (ssget "_X" (list (cons 8 *bsca-callout-layer*))))
  (setq sc (bsca-count-structures structs))
  (setq cc (bsca-count-callout-texts))
  (princ "\n[BSCALLOUTS-AUDIT] Counts:")
  (princ (strcat "\n  Structures: " (itoa (length structs))))
  (princ (strcat "\n    Handholes found/callouts: " (itoa (car sc)) "/" (itoa (car cc))))
  (princ (strcat "\n    Bore pits found/callouts: " (itoa (cadr sc)) "/" (itoa (cadr cc))))
  (if (/= (car sc) (car cc))
    (princ "\n    WARNING: handhole callout count does not match handhole blocks."))
  (if (/= (cadr sc) (cadr cc))
    (princ "\n    WARNING: bore pit callout count does not match bore pit blocks."))
  (princ (strcat "\n  Buried fiber: " (if buried (itoa (sslength buried)) "0")))
  (princ (strcat "\n  Aerial fiber: " (if aerial (itoa (sslength aerial)) "0")))
  (princ (strcat "\n  Elash fiber: " (if elash (itoa (sslength elash)) "0")))
  (princ (strcat "\n  Existing CABLE CALLOUTS objects: " (if callouts (itoa (sslength callouts)) "0")))
  (princ))

(princ "\n[BSCALLOUTS_AUTO] Loaded. Commands: BSCALLOUTS-RUN, BSCALLOUTS-STRUCTURES, BSCALLOUTS-BURIED, BSCALLOUTS-AERIAL, BSCALLOUTS-AUDIT.")
(princ)
