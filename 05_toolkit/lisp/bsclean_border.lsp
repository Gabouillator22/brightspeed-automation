;;; ============================================================
;;; BSCLEAN_BORDER - Safe border-based cleanup
;;;
;;; Public workflow:
;;;   1. BSCLEANRECT -> draw one cleanup rectangle.
;;;   2. BSCLEAN     -> auto keep via BORDER rectangles.
;;;      BSCLEANPICK -> manual keep selection (recommended fallback).
;;;
;;; Rule:
;;;   Inside BS-CLEAN-LIMIT, linework outside BORDER rectangles is hidden.
;;;   Linework outside BS-CLEAN-LIMIT is not touched.
;;;
;;; Safety:
;;;   No deletes. Originals are moved to BS-CLEAN-HIDDEN and frozen.
;;;   Kept portions are recreated as new entities, so Ctrl+Z restores all.
;;; ============================================================

(vl-load-com)

;;; --------------------------
;;; Settings
;;; --------------------------

(setq bscl-limit-layer "BS-CLEAN-LIMIT")
(setq bscl-hidden-layer "BS-CLEAN-HIDDEN")
(setq bscl-border-layer "BORDER")
(setq bscl-vpimg-layer "VIEWPORT IMAGE")
(setq bscl-mask-layer "BS-CLEAN-MASK")
(setq bscl-sample-step 5.0)
(setq bscl-maptrim-source-types "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE")

;;; --------------------------
;;; Public commands
;;; --------------------------

(defun c:BSCLEANRECT ( / old-layer old-cmdecho p1 p2)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (bscl-layer bscl-limit-layer 30)
  (setq p1 (getpoint "\n[BSCLEANRECT] First corner of cleanup rectangle: "))
  (if p1
    (progn
      (setq p2 (getcorner p1 "\n[BSCLEANRECT] Opposite corner: "))
      (if p2
        (progn
          (bscl-make-rect bscl-limit-layer p1 p2)
          (princ "\n[BSCLEANRECT] Cleanup rectangle created on BS-CLEAN-LIMIT.")))))
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEAN ( / old-layer old-cmdecho limit-ent limit-rect keep-data keep-rects ss i ent result
                     total in-limit skipped hidden made errors border-count vpimg-count)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)

  (setq total 0
        in-limit 0
        skipped 0
        hidden 0
        made 0
        errors 0)

  (setq limit-ent (bscl-latest-limit))
  (cond
    ((not limit-ent)
      (princ "\n[BSCLEAN] No BS-CLEAN-LIMIT rectangle found. Run BSCLEANRECT first."))

    ((not (setq limit-rect (bscl-entity-rect limit-ent)))
      (princ "\n[BSCLEAN] Could not read the cleanup rectangle. Draw it again with BSCLEANRECT."))

    (T
      (setq keep-data (bscl-collect-keep-rects limit-rect nil))
      (setq keep-rects (car keep-data))
      (setq border-count (cadr keep-data))
      (setq vpimg-count (caddr keep-data))
      (if (not keep-rects)
        (princ "\n[BSCLEAN] No keep rectangles found on BORDER or VIEWPORT IMAGE inside cleanup rectangle.")
        (progn
          (princ
            (strcat
              "\n[BSCLEAN] Cleanup rectangle found. BORDER keeps: " (itoa border-count)
              " | VIEWPORT IMAGE keeps: " (itoa vpimg-count)))
          ;; First pass: directly grab linework crossing the cleanup rectangle polygon.
          (setq ss
            (ssget "_CP"
              (bscl-rect->polypts limit-rect)
              '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE"))))
          ;; Fallback: if CP fails in this drawing state, scan all linework.
          (if (not ss)
            (setq ss (ssget "X" '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE")))))
          (if ss
            (progn
              (princ (strcat "\n[BSCLEAN] Scanning " (itoa (sslength ss)) " linework entities..."))
              (setq i 0)
              (while (< i (sslength ss))
                (setq ent (ssname ss i))
                (setq total (1+ total))
                (if (not (bscl-entity-crosses-rect-p ent limit-rect))
                  (setq skipped (1+ skipped))
                  (progn
                    (setq in-limit (1+ in-limit))
                    (setq result (vl-catch-all-apply 'bscl-clean-entity (list ent limit-rect keep-rects)))
                    (if (vl-catch-all-error-p result)
                      (progn
                        (setq errors (1+ errors))
                        (setq skipped (1+ skipped)))
                      (progn
                        (setq made (+ made (car result)))
                        (setq hidden (+ hidden (cadr result)))
                        (setq skipped (+ skipped (caddr result)))))))
                (if (and (> i 0) (= 0 (rem i 1000)))
                  (princ (strcat "\n[BSCLEAN] Reviewed " (itoa i) " entities...")))
                (setq i (1+ i)))))
          (command "_.LAYER" "F" bscl-hidden-layer "")
          (princ "\n")
          (princ "\n[BSCLEAN] ===== RESULTS =====")
          (princ (strcat "\n  Total linework scanned : " (itoa total)))
          (princ (strcat "\n  Inside cleanup checked : " (itoa in-limit)))
          (princ (strcat "\n  Originals hidden       : " (itoa hidden)))
          (princ (strcat "\n  Kept pieces created    : " (itoa made)))
          (princ (strcat "\n  Skipped/protected      : " (itoa skipped)))
          (princ (strcat "\n  Entity errors skipped  : " (itoa errors)))
          (princ (strcat "\n  Keep masks (BORDER)    : " (itoa border-count)))
          (princ (strcat "\n  Keep masks (VP IMAGE)  : " (itoa vpimg-count)))
          (princ "\n  Hidden layer           : BS-CLEAN-HIDDEN (frozen)")
          (princ "\n  No entities deleted.")
          (princ "\n[BSCLEAN] ===================")))))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANPICK ( / old-layer old-cmdecho pick limit-ent limit-rect keep-ss keep-data keep-rects
                         ss i ent result total in-limit skipped hidden made errors border-count vpimg-count)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)

  (setq total 0 in-limit 0 skipped 0 hidden 0 made 0 errors 0 border-count 0 vpimg-count 0)

  (setq pick (entsel "\n[BSCLEANPICK] Select cleanup rectangle (BS-CLEAN-LIMIT): "))
  (if pick
    (setq limit-ent (car pick))
    (setq limit-ent (bscl-latest-limit)))

  (cond
    ((not limit-ent)
      (princ "\n[BSCLEANPICK] No cleanup rectangle found. Run BSCLEANRECT first."))
    ((not (setq limit-rect (bscl-entity-rect limit-ent)))
      (princ "\n[BSCLEANPICK] Could not read cleanup rectangle."))
    (T
      (princ "\n[BSCLEANPICK] Select keep objects (BORDER rectangles and/or VIEWPORT IMAGE objects), then Enter.")
      (setq keep-ss (ssget))
      (if (not keep-ss)
        (princ "\n[BSCLEANPICK] Nothing selected. Aborting.")
        (progn
          (setq keep-data (bscl-collect-keep-rects limit-rect keep-ss))
          (setq keep-rects (car keep-data))
          (setq border-count (cadr keep-data))
          (setq vpimg-count (caddr keep-data))
          (if (not keep-rects)
            (princ "\n[BSCLEANPICK] Selected keep set produced no valid masks.")
            (progn
              (princ (strcat "\n[BSCLEANPICK] Keep masks: BORDER=" (itoa border-count) " VIEWPORT=" (itoa vpimg-count)))
              (setq ss
                (ssget "_CP"
                  (bscl-rect->polypts limit-rect)
                  '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE"))))
              (if (not ss)
                (setq ss (ssget "X" '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE")))))
              (if ss
                (progn
                  (princ (strcat "\n[BSCLEANPICK] Scanning " (itoa (sslength ss)) " linework entities..."))
                  (setq i 0)
                  (while (< i (sslength ss))
                    (setq ent (ssname ss i))
                    (setq total (1+ total))
                    (if (not (bscl-entity-crosses-rect-p ent limit-rect))
                      (setq skipped (1+ skipped))
                      (progn
                        (setq in-limit (1+ in-limit))
                        (setq result (vl-catch-all-apply 'bscl-clean-entity (list ent limit-rect keep-rects)))
                        (if (vl-catch-all-error-p result)
                          (progn
                            (setq errors (1+ errors))
                            (setq skipped (1+ skipped)))
                          (progn
                            (setq made (+ made (car result)))
                            (setq hidden (+ hidden (cadr result)))
                            (setq skipped (+ skipped (caddr result)))))))
                    (setq i (1+ i)))))
              (command "_.LAYER" "F" bscl-hidden-layer "")
              (princ "\n")
              (princ "\n[BSCLEANPICK] ===== RESULTS =====")
              (princ (strcat "\n  Total linework scanned : " (itoa total)))
              (princ (strcat "\n  Inside cleanup checked : " (itoa in-limit)))
              (princ (strcat "\n  Originals hidden       : " (itoa hidden)))
              (princ (strcat "\n  Kept pieces created    : " (itoa made)))
              (princ (strcat "\n  Skipped/protected      : " (itoa skipped)))
              (princ (strcat "\n  Entity errors skipped  : " (itoa errors)))
              (princ "\n  No entities deleted.")
              (princ "\n[BSCLEANPICK] ===================")))))))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANOUT ( / old-layer old-cmdecho limit-ent limit-rect keep-data keep-rects ss i ent ed layer er total in-limit kept hidden skipped)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)

  (setq total 0 in-limit 0 kept 0 hidden 0 skipped 0)
  (setq limit-ent (bscl-latest-limit))
  (cond
    ((not limit-ent)
      (princ "\n[BSCLEANOUT] No BS-CLEAN-LIMIT rectangle found. Run BSCLEANRECT first."))
    ((not (setq limit-rect (bscl-entity-rect limit-ent)))
      (princ "\n[BSCLEANOUT] Could not read cleanup rectangle. Draw it again with BSCLEANRECT."))
    (T
      (setq keep-data (bscl-collect-keep-rects limit-rect nil))
      (setq keep-rects (car keep-data))
      (if (not keep-rects)
        (princ "\n[BSCLEANOUT] No BORDER rectangles found inside cleanup rectangle.")
        (progn
          (setq ss (ssget "X"))
          (if ss
            (progn
              (setq i 0)
              (while (< i (sslength ss))
                (setq ent (ssname ss i))
                (setq ed (entget ent))
                (setq layer (cdr (assoc 8 ed)))
                (setq total (1+ total))
                (cond
                  ((or (not layer) (bscl-protected-layer-p layer))
                    (setq skipped (1+ skipped)))
                  ((not (setq er (bscl-entity-rect ent)))
                    (setq skipped (1+ skipped)))
                  ((not (bscl-rect-intersects-p er limit-rect))
                    (setq skipped (1+ skipped)))
                  (T
                    (setq in-limit (1+ in-limit))
                    (if (bscl-rect-intersects-any-p er keep-rects)
                      (setq kept (1+ kept))
                      (progn
                        (bscl-move-to-hidden ent)
                        (setq hidden (1+ hidden))))))
                (setq i (1+ i)))))
          (command "_.LAYER" "F" bscl-hidden-layer "")
          (princ "\n")
          (princ "\n[BSCLEANOUT] ===== RESULTS =====")
          (princ (strcat "\n  Total entities scanned : " (itoa total)))
          (princ (strcat "\n  Inside cleanup checked : " (itoa in-limit)))
          (princ (strcat "\n  Kept by BORDER overlap : " (itoa kept)))
          (princ (strcat "\n  Hidden outside BORDER  : " (itoa hidden)))
          (princ (strcat "\n  Skipped/protected      : " (itoa skipped)))
          (princ "\n  Hidden layer           : BS-CLEAN-HIDDEN (frozen)")
          (princ "\n  No entities deleted.")
          (princ "\n[BSCLEANOUT] ====================")))))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANLINES ( / old-layer old-cmdecho limit-ent limit-rect keep-data keep-rects ss i ent ed layer er result total in-limit hidden made skipped errors)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)

  (setq total 0 in-limit 0 hidden 0 made 0 skipped 0 errors 0)
  (setq limit-ent (bscl-latest-limit))
  (cond
    ((not limit-ent)
      (princ "\n[BSCLEANLINES] No BS-CLEAN-LIMIT rectangle found. Run BSCLEANRECT first."))
    ((not (setq limit-rect (bscl-entity-rect limit-ent)))
      (princ "\n[BSCLEANLINES] Could not read cleanup rectangle. Draw it again with BSCLEANRECT."))
    (T
      (setq keep-data (bscl-collect-keep-rects limit-rect nil))
      (setq keep-rects (car keep-data))
      (if (not keep-rects)
        (princ "\n[BSCLEANLINES] No BORDER rectangles found inside cleanup rectangle.")
        (progn
          (setq ss (ssget "X" '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,SPLINE"))))
          (if ss
            (progn
              (setq i 0)
              (while (< i (sslength ss))
                (setq ent (ssname ss i))
                (setq ed (entget ent))
                (setq layer (cdr (assoc 8 ed)))
                (setq total (1+ total))
                (cond
                  ((or (not layer) (bscl-protected-layer-p layer))
                    (setq skipped (1+ skipped)))
                  ((not (setq er (bscl-entity-rect ent)))
                    (setq skipped (1+ skipped)))
                  ((not (bscl-rect-intersects-p er limit-rect))
                    (setq skipped (1+ skipped)))
                  ((not (bscl-rect-intersects-any-p er keep-rects))
                    (setq skipped (1+ skipped)))
                  (T
                    (setq in-limit (1+ in-limit))
                    (setq result (vl-catch-all-apply 'bscl-clean-entity (list ent limit-rect keep-rects)))
                    (if (vl-catch-all-error-p result)
                      (progn
                        (setq errors (1+ errors))
                        (setq skipped (1+ skipped)))
                      (progn
                        (setq made (+ made (car result)))
                        (setq hidden (+ hidden (cadr result)))
                        (setq skipped (+ skipped (caddr result)))))))
                (setq i (1+ i)))))
          (command "_.LAYER" "F" bscl-hidden-layer "")
          (princ "\n")
          (princ "\n[BSCLEANLINES] ===== RESULTS =====")
          (princ (strcat "\n  Total linework scanned : " (itoa total)))
          (princ (strcat "\n  Crossing candidates    : " (itoa in-limit)))
          (princ (strcat "\n  Originals hidden       : " (itoa hidden)))
          (princ (strcat "\n  Kept pieces created    : " (itoa made)))
          (princ (strcat "\n  Skipped/protected      : " (itoa skipped)))
          (princ (strcat "\n  Entity errors skipped  : " (itoa errors)))
          (princ "\n  Hidden layer           : BS-CLEAN-HIDDEN (frozen)")
          (princ "\n  No entities deleted.")
          (princ "\n[BSCLEANLINES] =====================")))))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANTRIMSEL ( / old-layer old-cmdecho keep-data keep-rects ss i ent ed typ layer limit-rect result total hidden made skipped errors)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)

  (setq total 0 hidden 0 made 0 skipped 0 errors 0)
  (setq keep-data (bscl-collect-keep-rects nil nil))
  (setq keep-rects (car keep-data))
  (cond
    ((not keep-rects)
      (princ "\n[BSCLEANTRIMSEL] No BORDER rectangles found. Accept sheets to BORDER first."))
    (T
      (princ "\n[BSCLEANTRIMSEL] Select the bad incoming linework, then Enter.")
      (setq ss (ssget))
      (if (not ss)
        (princ "\n[BSCLEANTRIMSEL] Nothing selected.")
        (progn
          (setq limit-rect (bscl-selection-rect ss))
          (if (not limit-rect)
            (princ "\n[BSCLEANTRIMSEL] Could not read selected objects.")
            (progn
              (setq i 0)
              (while (< i (sslength ss))
                (setq ent (ssname ss i))
                (setq ed (entget ent))
                (setq typ (cdr (assoc 0 ed)))
                (setq layer (cdr (assoc 8 ed)))
                (setq total (1+ total))
                (cond
                  ((or (not layer) (bscl-protected-layer-p layer))
                    (setq skipped (1+ skipped)))
                  ((not (member typ '("LINE" "LWPOLYLINE" "POLYLINE" "ARC" "SPLINE")))
                    (setq skipped (1+ skipped)))
                  (T
                    (setq result (vl-catch-all-apply 'bscl-clean-entity (list ent limit-rect keep-rects)))
                    (if (vl-catch-all-error-p result)
                      (progn
                        (setq errors (1+ errors))
                        (setq skipped (1+ skipped)))
                      (progn
                        (setq made (+ made (car result)))
                        (setq hidden (+ hidden (cadr result)))
                        (setq skipped (+ skipped (caddr result)))))))
                (setq i (1+ i)))
              (command "_.LAYER" "F" bscl-hidden-layer "")
              (princ "\n")
              (princ "\n[BSCLEANTRIMSEL] ===== RESULTS =====")
              (princ (strcat "\n  Selected objects       : " (itoa total)))
              (princ (strcat "\n  Originals hidden       : " (itoa hidden)))
              (princ (strcat "\n  Kept pieces created    : " (itoa made)))
              (princ (strcat "\n  Skipped/protected      : " (itoa skipped)))
              (princ (strcat "\n  Entity errors skipped  : " (itoa errors)))
              (princ "\n  No entities deleted.")
              (princ "\n[BSCLEANTRIMSEL] =====================")))))))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANBAD ( / old-layer old-cmdecho ss i ent ed layer total hidden skipped)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)

  (setq total 0 hidden 0 skipped 0)
  (princ "\n[BSCLEANBAD] Select bad incoming objects to hide, then Enter.")
  (setq ss (ssget))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq ed (entget ent))
        (setq layer (cdr (assoc 8 ed)))
        (setq total (1+ total))
        (if (or (not layer) (bscl-protected-layer-p layer))
          (setq skipped (1+ skipped))
          (progn
            (bscl-move-to-hidden ent)
            (setq hidden (1+ hidden))))
        (setq i (1+ i)))
      (command "_.LAYER" "F" bscl-hidden-layer "")
      (princ "\n")
      (princ "\n[BSCLEANBAD] ===== RESULTS =====")
      (princ (strcat "\n  Selected objects       : " (itoa total)))
      (princ (strcat "\n  Hidden                 : " (itoa hidden)))
      (princ (strcat "\n  Skipped/protected      : " (itoa skipped)))
      (princ "\n  No entities deleted.")
      (princ "\n[BSCLEANBAD] ====================="))
    (princ "\n[BSCLEANBAD] Nothing selected."))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANCLEARMASK ( / old-cmdecho ss i ent total)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)
  (setq total 0)
  (setq ss (ssget "_X" (list (cons 8 bscl-mask-layer))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (bscl-move-to-hidden ent)
        (setq total (1+ total))
        (setq i (1+ i)))
      (command "_.LAYER" "F" bscl-hidden-layer "")
      (princ (strcat "\n[BSCLEANCLEARMASK] Hid " (itoa total) " old mask object(s).")))
    (princ "\n[BSCLEANCLEARMASK] No old mask objects found."))
  (command "_.UNDO" "_END")
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANMASK ( / old-layer old-cmdecho limit-ent limit-rect keep-data keep-rects xvals yvals xi yi x1 x2 y1 y2 cx cy made mask-ss)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-mask-layer 255)

  (setq made 0)
  (setq limit-ent (bscl-latest-limit))
  (cond
    ((not limit-ent)
      (princ "\n[BSCLEANMASK] No BS-CLEAN-LIMIT rectangle found. Run BSCLEANRECT first."))
    ((not (setq limit-rect (bscl-entity-rect limit-ent)))
      (princ "\n[BSCLEANMASK] Could not read cleanup rectangle. Draw it again with BSCLEANRECT."))
    (T
      (setq keep-data (bscl-collect-keep-rects limit-rect nil))
      (setq keep-rects (car keep-data))
      (if (not keep-rects)
        (princ "\n[BSCLEANMASK] No BORDER rectangles found inside cleanup rectangle.")
        (progn
          (setq xvals (bscl-mask-coords limit-rect keep-rects T))
          (setq yvals (bscl-mask-coords limit-rect keep-rects nil))
          (setq xi 0)
          (while (< (1+ xi) (length xvals))
            (setq x1 (nth xi xvals) x2 (nth (1+ xi) xvals))
            (setq yi 0)
            (while (< (1+ yi) (length yvals))
              (setq y1 (nth yi yvals) y2 (nth (1+ yi) yvals))
              (if (and (> (- x2 x1) 0.01) (> (- y2 y1) 0.01))
                (progn
                  (setq cx (/ (+ x1 x2) 2.0))
                  (setq cy (/ (+ y1 y2) 2.0))
                  (if (not (bscl-point-in-any-rect-p (list cx cy 0.0) keep-rects))
                    (progn
                      (bscl-make-mask-rect x1 y1 x2 y2)
                      (setq made (1+ made))))))
              (setq yi (1+ yi)))
            (setq xi (1+ xi)))
          (setq mask-ss (ssget "_X" (list (cons 8 bscl-mask-layer))))
          (if mask-ss
            (command "_.DRAWORDER" mask-ss "" "_F"))
          (princ (strcat "\n[BSCLEANMASK] Created " (itoa made) " outside-sheet mask rectangle(s)."))))))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSCLEANMASK ( / )
  (princ "\n[BSCLEANMASK] Disabled. Use BSCLEANTRIMSEL to clip selected linework, or BSCLEANBAD to hide selected bad objects.")
  (princ)
)

(defun c:BSCLEANALL ( / )
  (princ "\n[BSCLEANALL] Starting full sheet cleanup.")
  (princ "\n[BSCLEANALL] Step 1/3: clear old mask artifacts.")
  (c:BSCLEANCLEARMASK)
  (princ "\n[BSCLEANALL] Step 2/3: hide whole objects outside accepted sheets.")
  (c:BSCLEANOUT)
  (princ "\n[BSCLEANALL] Step 3/3: trim linework crossing accepted sheet borders.")
  (c:BSCLEANLINES)
  (princ "\n[BSCLEANALL] Done. If something looks wrong, Ctrl+Z reverses the cleanup passes.")
  (princ)
)

(defun c:BSCLEANMAP ( / old-layer old-cmdecho limit-ent limit-rect border-data source-list source-count
                        made trim-ok hidden skipped errors bdata border-ent border-rect copy-ss copy-count
                        ent ed layer er new-ent result)
  (setq old-layer (getvar "CLAYER"))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bscl-layer bscl-hidden-layer 8)
  (bscl-hide-old-masks)

  (setq made 0 trim-ok 0 hidden 0 skipped 0 errors 0)
  (cond
    ((not (setq limit-ent (bscl-latest-limit)))
      (princ "\n[BSCLEANMAP] No BS-CLEAN-LIMIT rectangle found. Run BSCLEANRECT first."))
    ((not (setq limit-rect (bscl-entity-rect limit-ent)))
      (princ "\n[BSCLEANMAP] Could not read cleanup rectangle. Draw it again with BSCLEANRECT."))
    (T
      (setq border-data (bscl-collect-border-data limit-rect))
      (cond
        ((not border-data)
          (princ "\n[BSCLEANMAP] No accepted BORDER rectangles found inside cleanup rectangle."))
        (T
          (setq source-list (bscl-maptrim-source-list limit-rect))
          (setq source-count (length source-list))
          (if (= source-count 0)
            (princ "\n[BSCLEANMAP] No source linework found inside cleanup rectangle.")
            (progn
              (princ (strcat "\n[BSCLEANMAP] Source linework found: " (itoa source-count)))
              (princ (strcat "\n[BSCLEANMAP] BORDER sheets found: " (itoa (length border-data))))
              (foreach bdata border-data
                (setq border-ent (car bdata))
                (setq border-rect (cadr bdata))
                (setq copy-ss (ssadd))
                (setq copy-count 0)
                (foreach ent source-list
                  (setq er (bscl-entity-rect ent))
                  (if (and er (bscl-rect-intersects-p er border-rect))
                    (progn
                      (setq new-ent (bscl-copy-entity ent))
                      (if new-ent
                        (progn
                          (ssadd new-ent copy-ss)
                          (setq copy-count (1+ copy-count)))
                        (setq errors (1+ errors))))))
                (if (> copy-count 0)
                  (progn
                    (setq made (+ made copy-count))
                    (setq result (vl-catch-all-apply 'map_dwgtrimobj (list copy-ss border-ent 1 1 0 1)))
                    (if (vl-catch-all-error-p result)
                      (progn
                        (setq errors (1+ errors))
                        (bscl-hide-selection copy-ss))
                      (setq trim-ok (1+ trim-ok)))))))
              (if (> trim-ok 0)
                (progn
                  (foreach ent source-list
                    (setq ed (entget ent))
                    (setq layer (cdr (assoc 8 ed)))
                    (if (or (not layer) (bscl-protected-layer-p layer))
                      (setq skipped (1+ skipped))
                      (progn
                        (bscl-move-to-hidden ent)
                        (setq hidden (1+ hidden)))))
                  (command "_.LAYER" "F" bscl-hidden-layer ""))
                (princ "\n[BSCLEANMAP] No successful Map trims. Originals were not hidden."))
              (princ "\n")
              (princ "\n[BSCLEANMAP] ===== RESULTS =====")
              (princ (strcat "\n  Source originals       : " (itoa source-count)))
              (princ (strcat "\n  Sheet copy candidates  : " (itoa made)))
              (princ (strcat "\n  Sheets trimmed by Map  : " (itoa trim-ok)))
              (princ (strcat "\n  Originals hidden       : " (itoa hidden)))
              (princ (strcat "\n  Skipped/protected      : " (itoa skipped)))
              (princ (strcat "\n  Errors                 : " (itoa errors)))
              (princ "\n  Visible copies keep their original layers.")
              (princ "\n  No entities deleted.")
              (princ "\n[BSCLEANMAP] ====================="))))))

  (command "_.UNDO" "_END")
  (setvar "CLAYER" old-layer)
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

(defun c:BSMAP ( / ) (c:BSCLEANMAP))
(defun c:BCMAP ( / ) (c:BSCLEANMAP))
(defun c:BSCLMAP ( / ) (c:BSCLEANMAP))

;;; Backward-compatible names, but both route to the two-command workflow.
(defun c:BSCLEANLIMIT ( / ) (c:BSCLEANRECT))
(defun c:TRIMAGE ( / ) (c:BSCLEANRECT))
(defun c:BSCLEANVP ( / ) (c:BSCLEAN))
(defun c:BSCLEANAUTO ( / ) (c:BSCLEANALL))
(defun c:BSCLEANFINAL ( / ) (c:BSCLEANALL))

;;; --------------------------
;;; Layers and rectangles
;;; --------------------------

(defun bscl-layer (lname color / )
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "C" (itoa color) lname ""))
  (command "_.LAYER" "ON" lname "T" lname "")
  (princ)
)

(defun bscl-make-rect (layer p1 p2 / x1 y1 x2 y2 xmin ymin xmax ymax)
  (setq x1 (car p1) y1 (cadr p1))
  (setq x2 (car p2) y2 (cadr p2))
  (setq xmin (min x1 x2) ymin (min y1 y2))
  (setq xmax (max x1 x2) ymax (max y1 y2))
  (entmakex
    (list
      '(0 . "LWPOLYLINE")
      '(100 . "AcDbEntity")
      (cons 8 layer)
      '(100 . "AcDbPolyline")
      '(90 . 4)
      '(70 . 1)
      (cons 10 (list xmin ymin 0.0))
      (cons 10 (list xmax ymin 0.0))
      (cons 10 (list xmax ymax 0.0))
      (cons 10 (list xmin ymax 0.0))))
)

(defun bscl-latest-limit ( / ent best ed layer)
  (setq ent (entnext))
  (while ent
    (setq ed (entget ent))
    (setq layer (cdr (assoc 8 ed)))
    (if (and layer
             (= (strcase layer) (strcase bscl-limit-layer))
             (bscl-closed-poly-p ent)
             (bscl-entity-rect ent))
      (setq best ent))
    (setq ent (entnext ent)))
  best
)

(defun bscl-rect->polypts (rect / xmin ymin xmax ymax)
  (setq xmin (nth 0 rect))
  (setq ymin (nth 1 rect))
  (setq xmax (nth 2 rect))
  (setq ymax (nth 3 rect))
  (list
    (list xmin ymin 0.0)
    (list xmax ymin 0.0)
    (list xmax ymax 0.0)
    (list xmin ymax 0.0))
)

(defun bscl-collect-keep-rects (limit-rect keep-ss / ss i ent ed layer etype rect out border-count vpimg-count)
  (if keep-ss
    (setq ss keep-ss)
    (setq ss (ssget "X")))
  (setq out nil)
  (setq border-count 0)
  (setq vpimg-count 0)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq ed (entget ent))
        (setq layer (cdr (assoc 8 ed)))
        (setq etype (cdr (assoc 0 ed)))
        (if (and layer
                 (member (strcase layer) (list (strcase bscl-border-layer) (strcase bscl-vpimg-layer)))
                 (or (= etype "LWPOLYLINE") (= etype "POLYLINE") (= etype "IMAGE")))
          (progn
            (if (and (or (= etype "LWPOLYLINE") (= etype "POLYLINE"))
                     (not (bscl-rectlike-poly-p ent)))
              (setq rect nil)
              (setq rect (bscl-entity-rect ent)))
            (if (and rect (or (not limit-rect) (bscl-rect-intersects-p rect limit-rect)))
              (progn
                (setq out (cons rect out))
                (if (= (strcase layer) (strcase bscl-border-layer))
                  (setq border-count (1+ border-count))
                  (setq vpimg-count (1+ vpimg-count)))))))
        (setq i (1+ i)))))
  (list out border-count vpimg-count)
)

(defun bscl-selection-rect (ss / i ent er out)
  (setq i 0)
  (setq out nil)
  (if ss
    (while (< i (sslength ss))
      (setq ent (ssname ss i))
      (setq er (bscl-entity-rect ent))
      (if er
        (if out
          (setq out
            (list
              (min (nth 0 out) (nth 0 er))
              (min (nth 1 out) (nth 1 er))
              (max (nth 2 out) (nth 2 er))
              (max (nth 3 out) (nth 3 er))))
          (setq out er)))
      (setq i (1+ i))))
  out
)

(defun bscl-maptrim-available-p ( / atoms)
  (setq atoms (atoms-family 1))
  (or (member "MAP_DWGTRIMOBJ" atoms)
      (member "map_dwgtrimobj" atoms))
)

(defun bscl-collect-border-data (limit-rect / ss i ent ed layer etype rect out)
  (setq out nil)
  (setq ss (ssget "_X" (list '(-4 . "<OR") '(0 . "LWPOLYLINE") '(0 . "POLYLINE") '(-4 . "OR>") (cons 8 bscl-border-layer))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq ed (entget ent))
        (setq layer (cdr (assoc 8 ed)))
        (setq etype (cdr (assoc 0 ed)))
        (setq rect nil)
        (if (and layer
                 (= (strcase layer) (strcase bscl-border-layer))
                 (member etype '("LWPOLYLINE" "POLYLINE"))
                 (bscl-rectlike-poly-p ent))
          (setq rect (bscl-entity-rect ent)))
        (if (and rect (or (not limit-rect) (bscl-rect-intersects-p rect limit-rect)))
          (setq out (cons (list ent rect) out)))
        (setq i (1+ i)))))
  (reverse out)
)

(defun bscl-maptrim-source-list (limit-rect / ss i ent ed layer er out)
  (setq out nil)
  (setq ss (ssget "_X" (list (cons 0 bscl-maptrim-source-types))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq ed (entget ent))
        (setq layer (cdr (assoc 8 ed)))
        (setq er (bscl-entity-rect ent))
        (if (and layer
                 er
                 (not (bscl-protected-layer-p layer))
                 (bscl-rect-intersects-p er limit-rect))
          (setq out (cons ent out)))
        (setq i (1+ i)))))
  (reverse out)
)

(defun bscl-copy-entity (ent / obj newobj result)
  (setq obj (vlax-ename->vla-object ent))
  (setq result (vl-catch-all-apply 'vla-copy (list obj)))
  (if (vl-catch-all-error-p result)
    nil
    (progn
      (setq newobj result)
      (vlax-vla-object->ename newobj)))
)

(defun bscl-hide-selection (ss / i ent)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if ent (bscl-move-to-hidden ent))
        (setq i (1+ i)))))
  (princ)
)

(defun bscl-hide-old-masks ( / ss i ent count)
  (setq count 0)
  (setq ss (ssget "_X" (list (cons 8 bscl-mask-layer))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (if ent
          (progn
            (bscl-move-to-hidden ent)
            (setq count (1+ count))))
        (setq i (1+ i)))))
  count
)

(defun bscl-rectlike-poly-p (ent / ed typ flags pts bbox xmin ymin xmax ymax ok)
  (setq ed (entget ent))
  (setq typ (cdr (assoc 0 ed)))
  (setq flags (cdr (assoc 70 ed)))
  (if (or (not (member typ '("LWPOLYLINE" "POLYLINE")))
          (not flags)
          (/= 1 (logand 1 flags)))
    nil
    (progn
      (setq pts (bscl-poly-pts ent))
      (if (/= (length pts) 4)
        nil
        (progn
          (setq bbox (bscl-entity-rect ent))
          (if (not bbox)
            nil
            (progn
              (setq xmin (nth 0 bbox) ymin (nth 1 bbox) xmax (nth 2 bbox) ymax (nth 3 bbox))
              (setq ok T)
              (foreach p pts
                (if (not (and (or (bscl-near (car p) xmin) (bscl-near (car p) xmax))
                              (or (bscl-near (cadr p) ymin) (bscl-near (cadr p) ymax))))
                  (setq ok nil)))
              ok)))))))

(defun bscl-poly-pts (ent / ed typ pts vla coords idx)
  (setq ed (entget ent))
  (setq typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LWPOLYLINE")
      (setq pts nil)
      (foreach pair ed
        (if (= (car pair) 10)
          (setq pts (append pts (list (list (cadr pair) (caddr pair) 0.0))))))
      pts)
    ((= typ "POLYLINE")
      (setq vla (vlax-ename->vla-object ent))
      (setq coords (vlax-safearray->list (vlax-variant-value (vla-get-Coordinates vla))))
      (setq pts nil idx 0)
      (while (< idx (length coords))
        (setq pts (append pts (list (list (nth idx coords) (nth (1+ idx) coords) 0.0))))
        (setq idx (+ idx 2)))
      pts)
    (T nil)))

(defun bscl-near (a b / )
  (< (abs (- a b)) 0.01)
)

(defun bscl-closed-poly-p (ent / ed typ flags)
  (setq ed (entget ent))
  (setq typ (cdr (assoc 0 ed)))
  (setq flags (cdr (assoc 70 ed)))
  (and (member typ '("LWPOLYLINE" "POLYLINE"))
       flags
       (= 1 (logand 1 flags)))
)

(defun bscl-entity-rect (ent / obj minp maxp minl maxl result)
  (setq obj (vlax-ename->vla-object ent))
  (setq result (vl-catch-all-apply 'vla-getboundingbox (list obj 'minp 'maxp)))
  (if (vl-catch-all-error-p result)
    nil
    (progn
      (setq minl (vlax-safearray->list minp))
      (setq maxl (vlax-safearray->list maxp))
      (list (car minl) (cadr minl) (car maxl) (cadr maxl))))
)

(defun bscl-entity-crosses-rect-p (ent rect / er)
  (setq er (bscl-entity-rect ent))
  (and er (bscl-rect-intersects-p er rect))
)

(defun bscl-rect-intersects-p (a b / )
  (not (or (< (nth 2 a) (nth 0 b))
           (> (nth 0 a) (nth 2 b))
           (< (nth 3 a) (nth 1 b))
           (> (nth 1 a) (nth 3 b))))
)

(defun bscl-rect-intersects-any-p (rect rects / hit r)
  (setq hit nil)
  (foreach r rects
    (if (and (not hit) (bscl-rect-intersects-p rect r))
      (setq hit T)))
  hit
)

(defun bscl-mask-coords (limit-rect rects use-x / vals r lo hi)
  (setq vals
    (if use-x
      (list (nth 0 limit-rect) (nth 2 limit-rect))
      (list (nth 1 limit-rect) (nth 3 limit-rect))))
  (foreach r rects
    (if (bscl-rect-intersects-p r limit-rect)
      (progn
        (if use-x
          (progn
            (setq lo (max (nth 0 limit-rect) (nth 0 r)))
            (setq hi (min (nth 2 limit-rect) (nth 2 r))))
          (progn
            (setq lo (max (nth 1 limit-rect) (nth 1 r)))
            (setq hi (min (nth 3 limit-rect) (nth 3 r)))))
        (setq vals (append vals (list lo hi))))))
  (bscl-unique-sorted vals)
)

(defun bscl-unique-sorted (vals / sorted out v lastv)
  (setq sorted (vl-sort vals '<))
  (setq out nil)
  (setq lastv nil)
  (foreach v sorted
    (if (or (not lastv) (> (abs (- v lastv)) 0.01))
      (progn
        (setq out (append out (list v)))
        (setq lastv v))))
  out
)

(defun bscl-point-in-rect-p (pt rect / x y)
  (setq x (car pt))
  (setq y (cadr pt))
  (and (>= x (nth 0 rect))
       (<= x (nth 2 rect))
       (>= y (nth 1 rect))
       (<= y (nth 3 rect)))
)

(defun bscl-point-in-any-rect-p (pt rects / hit r)
  (setq hit nil)
  (foreach r rects
    (if (and (not hit) (bscl-point-in-rect-p pt r))
      (setq hit T)))
  hit
)

(defun bscl-make-mask-rect (x1 y1 x2 y2 / ent)
  (setq ent
    (entmakex
      (list
        '(0 . "SOLID")
        '(100 . "AcDbEntity")
        (cons 8 bscl-mask-layer)
        '(62 . 255)
        '(100 . "AcDbTrace")
        (cons 10 (list x1 y1 0.0))
        (cons 11 (list x2 y1 0.0))
        (cons 12 (list x1 y2 0.0))
        (cons 13 (list x2 y2 0.0)))))
  ent
)

;;; --------------------------
;;; Entity cleanup
;;; --------------------------

(defun bscl-clean-entity (ent limit-rect borders / ed typ segs seg made changed)
  (setq ed (entget ent))
  (setq typ (cdr (assoc 0 ed)))
  (setq made 0)
  (setq changed nil)

  (cond
    ((bscl-protected-layer-p (cdr (assoc 8 ed)))
      (list 0 0 1))

    (T
      (setq segs (bscl-entity-segments ent typ))
      (foreach seg segs
        (setq made (+ made (bscl-make-kept-pieces ed (car seg) (cadr seg) limit-rect borders)))
        (if (not (bscl-segment-fully-kept-p (car seg) (cadr seg) limit-rect borders))
          (setq changed T)))
      (if changed
        (progn
          (bscl-move-to-hidden ent)
          (list made 1 0))
        (list 0 0 1)))))

(defun bscl-protected-layer-p (layer / u)
  (setq u (strcase layer))
  (or (= u (strcase bscl-border-layer))
      (= u (strcase bscl-limit-layer))
      (= u (strcase bscl-hidden-layer))
      (= u (strcase bscl-mask-layer))
      (= u "PROPERTY LINE-HIDDEN")
      (= u (strcase bscl-vpimg-layer)))
)

(defun bscl-move-to-hidden (ent / ed old)
  (setq ed (entget ent))
  (setq old (assoc 8 ed))
  (if old
    (progn
      (entmod (subst (cons 8 bscl-hidden-layer) old ed))
      (entupd ent)))
)

(defun bscl-entity-segments (ent typ / ed p1 p2 pts idx out)
  (cond
    ((= typ "LINE")
      (setq ed (entget ent))
      (list (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)))))

    (T
      (setq pts (bscl-sample-curve ent bscl-sample-step))
      (setq out nil)
      (setq idx 0)
      (while (< idx (1- (length pts)))
        (setq p1 (nth idx pts))
        (setq p2 (nth (1+ idx) pts))
        (if (> (distance p1 p2) 0.0001)
          (setq out (cons (list p1 p2) out)))
        (setq idx (1+ idx)))
      (reverse out)))
)

(defun bscl-sample-curve (ent step / end-param total d pt pts endpt err)
  (setq pts nil)
  (setq end-param (vl-catch-all-apply 'vlax-curve-getEndParam (list ent)))
  (if (vl-catch-all-error-p end-param)
    nil
    (progn
      (setq total (vl-catch-all-apply 'vlax-curve-getDistAtParam (list ent end-param)))
      (if (or (vl-catch-all-error-p total) (not total) (<= total 0.0001))
        nil
        (progn
          (setq d 0.0)
          (while (< d total)
            (setq pt (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent d)))
            (if (not (vl-catch-all-error-p pt))
              (setq pts (append pts (list pt))))
            (setq d (+ d step)))
          (setq endpt (vl-catch-all-apply 'vlax-curve-getPointAtDist (list ent total)))
          (if (not (vl-catch-all-error-p endpt))
            (setq pts (append pts (list endpt))))))))
  pts
)

;;; --------------------------
;;; Clipping math
;;; --------------------------

(defun bscl-make-kept-pieces (src-ed p1 p2 limit-rect borders / intervals count int q1 q2)
  (setq intervals (bscl-keep-intervals p1 p2 limit-rect borders))
  (setq count 0)
  (foreach int intervals
    (if (> (- (cadr int) (car int)) 0.0001)
      (progn
        (setq q1 (bscl-point-at p1 p2 (car int)))
        (setq q2 (bscl-point-at p1 p2 (cadr int)))
        (if (> (distance q1 q2) 0.0001)
          (progn
            (bscl-entmake-piece src-ed q1 q2)
            (setq count (1+ count)))))))
  count
)

(defun bscl-segment-fully-kept-p (p1 p2 limit-rect borders / intervals)
  (setq intervals (bscl-keep-intervals p1 p2 limit-rect borders))
  (and (= (length intervals) 1)
       (<= (abs (- (caar intervals) 0.0)) 0.000001)
       (<= (abs (- (cadar intervals) 1.0)) 0.000001))
)

(defun bscl-keep-intervals (p1 p2 limit-rect borders / limit-int keep-in-limit hidden keep)
  (setq limit-int (bscl-line-rect-interval p1 p2 limit-rect))
  (if (not limit-int)
    (list (list 0.0 1.0))
    (progn
      (setq keep-in-limit (bscl-border-intervals p1 p2 limit-int borders))
      (setq hidden (bscl-subtract (list limit-int) keep-in-limit))
      (setq keep (bscl-subtract (list (list 0.0 1.0)) hidden))
      (bscl-merge keep)))
)

(defun bscl-border-intervals (p1 p2 limit-int borders / out r int)
  (setq out nil)
  (foreach r borders
    (setq int (bscl-line-rect-interval p1 p2 r))
    (if int
      (setq out (append out (bscl-intersect int limit-int)))))
  (bscl-merge out)
)

(defun bscl-line-rect-interval (p1 p2 rect / dx dy t0 t1 r)
  (setq dx (- (car p2) (car p1)))
  (setq dy (- (cadr p2) (cadr p1)))
  (setq t0 0.0 t1 1.0)
  (setq r (bscl-clip-test (- dx) (- (car p1) (nth 0 rect)) t0 t1))
  (if r (progn (setq t0 (car r) t1 (cadr r)) (setq r (bscl-clip-test dx (- (nth 2 rect) (car p1)) t0 t1))))
  (if r (progn (setq t0 (car r) t1 (cadr r)) (setq r (bscl-clip-test (- dy) (- (cadr p1) (nth 1 rect)) t0 t1))))
  (if r (progn (setq t0 (car r) t1 (cadr r)) (setq r (bscl-clip-test dy (- (nth 3 rect) (cadr p1)) t0 t1))))
  (if r
    (progn
      (setq t0 (max 0.0 (car r)))
      (setq t1 (min 1.0 (cadr r)))
      (if (< t0 t1) (list t0 t1) nil))
    nil)
)

(defun bscl-clip-test (p q t0 t1 / r)
  (cond
    ((= p 0.0)
      (if (< q 0.0) nil (list t0 t1)))
    (T
      (setq r (/ q p))
      (cond
        ((< p 0.0)
          (if (> r t1) nil (list (max t0 r) t1)))
        ((> p 0.0)
          (if (< r t0) nil (list t0 (min t1 r))))
        (T (list t0 t1)))))
)

(defun bscl-intersect (a b / lo hi)
  (setq lo (max (car a) (car b)))
  (setq hi (min (cadr a) (cadr b)))
  (if (< lo hi) (list (list lo hi)) nil)
)

(defun bscl-subtract (base cuts / result cut)
  (setq result (bscl-merge base))
  (foreach cut (bscl-merge cuts)
    (setq result (bscl-subtract-one result cut)))
  (bscl-merge result)
)

(defun bscl-subtract-one (intervals cut / out int a b c d)
  (setq out nil)
  (setq c (car cut))
  (setq d (cadr cut))
  (foreach int intervals
    (setq a (car int))
    (setq b (cadr int))
    (cond
      ((or (<= d a) (>= c b))
        (setq out (append out (list int))))
      (T
        (if (< a c) (setq out (append out (list (list a c)))))
        (if (< d b) (setq out (append out (list (list d b))))))))
  out
)

(defun bscl-merge (intervals / sorted out int cur new)
  (setq sorted
    (vl-sort
      (vl-remove-if-not
        '(lambda (x) (and (listp x) (numberp (car x)) (numberp (cadr x)) (< (car x) (cadr x))))
        intervals)
      '(lambda (a b) (< (car a) (car b)))))
  (setq out nil)
  (foreach int sorted
    (if (not out)
      (setq out (list int))
      (progn
        (setq cur (car (last out)))
        (if (<= (car int) (+ (cadr cur) 0.000001))
          (progn
            (setq new (list (car cur) (max (cadr cur) (cadr int))))
            (setq out (append (reverse (cdr (reverse out))) (list new))))
          (setq out (append out (list int)))))))
  out
)

(defun bscl-point-at (p1 p2 ratio / )
  (list (+ (car p1) (* ratio (- (car p2) (car p1))))
        (+ (cadr p1) (* ratio (- (cadr p2) (cadr p1))))
        0.0)
)

;;; --------------------------
;;; Entity creation
;;; --------------------------

(defun bscl-entmake-piece (src-ed p1 p2 / typ common pair width flags)
  (setq typ (cdr (assoc 0 src-ed)))
  (setq common (bscl-copy-common-props src-ed))
  (if (= typ "LINE")
    (entmakex
      (append
        (list '(0 . "LINE") (cons 8 (cdr (assoc 8 src-ed))))
        common
        (list (cons 10 p1) (cons 11 p2))))
    (progn
      (setq width (assoc 43 src-ed))
      (setq flags (assoc 70 src-ed))
      (entmakex
        (append
          (list
            '(0 . "LWPOLYLINE")
            '(100 . "AcDbEntity")
            (cons 8 (cdr (assoc 8 src-ed))))
          common
          (list
            '(100 . "AcDbPolyline")
            '(90 . 2)
            (cons 70 (if flags (logand (cdr flags) 128) 0))
            (cons 10 p1)
            (cons 10 p2))
          (if width (list width) nil)
          )))))

(defun bscl-copy-common-props (ed / codes out pair)
  (setq codes '(6 7 8 39 48 62 67 370 420 430 440))
  (setq out nil)
  (foreach code codes
    (setq pair (assoc code ed))
    (if (and pair (/= code 8))
      (setq out (append out (list pair)))))
  out
)

(princ "\n[BSCLEAN_BORDER] Loaded v7. Commands: BSMAP, BCMAP, BSCLMAP, BSCLEANMAP, BSCLEANRECT, BSCLEANALL, BSCLEANOUT, BSCLEANLINES.")
(princ)
