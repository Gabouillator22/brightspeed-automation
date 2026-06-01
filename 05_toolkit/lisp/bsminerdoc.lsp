;;; ============================================================
;;; BSMINERDOC - Place MIN D.O.C. note on sheets with buried fiber
;;;
;;; Brightspeed standard: every sheet that shows underground work
;;; must include the note "MIN D.O.C. UNDER NATURAL GROUND 60\""
;;; with a directional arrow below it.
;;;
;;; Usage: BSMINERDOC
;;;   -> Checks if BURIED FIBER IN DUCT objects exist in drawing.
;;;   -> Checks if "MIN D.O.C." text already exists.
;;;   -> If not found, places the note at the lower-left of the
;;;      current view (LIMMIN), or prompts for placement point.
;;;   -> Draws a right-pointing arrow beneath the text.
;;;
;;; Note format (3 stacked TEXT lines):
;;;   Line 1: "MIN D.O.C."
;;;   Line 2: "UNDER NATURAL GROUND"
;;;   Line 3: "60\""
;;;   Line 4: -----> (arrow drawn as PLINE with arrowhead)
;;;
;;; Text height  : 5.0
;;; Layer        : CALLOUTS
;;; Arrow layer  : CALLOUTS
;;; Safety       : Adds entities only. No deletes. Undo-safe.
;;; ============================================================

(defun c:BSMINERDOC ( / old-cmdecho old-layer
                        buried-ss existing-txt-ss
                        place-pt
                        txt1-pt txt2-pt txt3-pt arrow-base arrow-tip
                        line-spacing text-height arrow-len arrowhead-size)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "CALLOUTS" 7)

  (setq text-height    5.0)
  (setq line-spacing   7.0)   ; vertical gap between text lines
  (setq arrow-len      30.0)  ; length of the arrow shaft
  (setq arrowhead-size 3.0)   ; arrowhead triangle size

  ;; Check for buried fiber
  (setq buried-ss
    (ssget "X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "BURIED FIBER IN DUCT"))))

  (if (not buried-ss)
    (progn
      (princ "\n[BSMINERDOC] No BURIED FIBER IN DUCT found in drawing.")
      (princ "\n[BSMINERDOC] Note is only required where underground work exists.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      ;; Check if MIN D.O.C. note already exists
      (setq existing-txt-ss
        (ssget "X"
          (list '(0 . "TEXT,MTEXT")
                (cons 1 "*MIN D.O.C.*"))))

      (if (and existing-txt-ss (> (sslength existing-txt-ss) 0))
        (progn
          (princ "\n[BSMINERDOC] \"MIN D.O.C.\" note already exists in drawing. No action taken.")
          (setvar "CMDECHO" old-cmdecho)
          (setvar "CLAYER" old-layer))
        (progn
          ;; Determine placement point
          ;; Default: lower-left of current view limits + small margin
          (setq place-pt (bsmd-default-placement-pt))

          (setvar "CMDECHO" 1)
          (setq place-pt
            (getpoint place-pt
              "\n[BSMINERDOC] Pick placement point (Enter=default lower-left): "))
          (setvar "CMDECHO" 0)

          (if (not place-pt)
            (setq place-pt (bsmd-default-placement-pt)))

          (setq place-pt (list (car place-pt) (cadr place-pt) 0.0))

          ;; Calculate positions for each text line (stacking upward)
          (setq txt1-pt place-pt)
          (setq txt2-pt (list (car place-pt) (+ (cadr place-pt) line-spacing)   0.0))
          (setq txt3-pt (list (car place-pt) (+ (cadr place-pt) (* 2 line-spacing)) 0.0))

          ;; Text lines (from bottom: line 3 at bottom, line 1 at top)
          ;; Brightspeed standard stacking (top to bottom):
          ;;   MIN D.O.C.             <- top
          ;;   UNDER NATURAL GROUND   <- middle
          ;;   60"                    <- bottom
          ;; Place from bottom upward:
          (bs-make-text txt1-pt text-height "CALLOUTS" "60\"")
          (bs-make-text txt2-pt text-height "CALLOUTS" "UNDER NATURAL GROUND")
          (bs-make-text txt3-pt text-height "CALLOUTS" "MIN D.O.C.")

          ;; Arrow: right-pointing, below the bottom text line
          (setq arrow-base
            (list (car place-pt) (- (cadr place-pt) line-spacing) 0.0))
          (setq arrow-tip
            (list (+ (car arrow-base) arrow-len) (cadr arrow-base) 0.0))

          ;; Shaft
          (bs-make-line arrow-base arrow-tip "CALLOUTS")

          ;; Arrowhead (filled triangle as closed LWPOLYLINE)
          (bsmd-make-arrowhead arrow-tip arrowhead-size "CALLOUTS")

          (setvar "CMDECHO" old-cmdecho)
          (setvar "CLAYER" old-layer)
          (princ "\n[BSMINERDOC] MIN D.O.C. note placed.")
          (princ "\n[BSMINERDOC] Layer: CALLOUTS. Undo with Ctrl+Z.")
        )
      )
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bsmd-default-placement-pt ( / limmin)
  ;; Return a point at the lower-left of LIMMIN + margin.
  (setq limmin (getvar "LIMMIN"))
  (if limmin
    (list (+ (car limmin) 10.0) (+ (cadr limmin) 10.0) 0.0)
    '(0.0 0.0 0.0)))

(defun bsmd-make-arrowhead (tip size layer-name / p1 p2 p3)
  ;; Draw a right-pointing closed triangle arrowhead at tip point.
  ;; tip = rightmost point of arrow. Triangle opens to the left.
  (setq p1 tip)
  (setq p2 (list (- (car tip) size)  (+ (cadr tip) (/ size 2.0)) 0.0))
  (setq p3 (list (- (car tip) size)  (- (cadr tip) (/ size 2.0)) 0.0))
  (entmakex
    (list
      '(0 . "LWPOLYLINE")
      (cons 8 layer-name)
      '(100 . "AcDbEntity")
      '(100 . "AcDbPolyline")
      '(90 . 3)   ; 3 vertices
      '(70 . 1)   ; closed
      (cons 10 (list (car p1) (cadr p1)))
      (cons 10 (list (car p2) (cadr p2)))
      (cons 10 (list (car p3) (cadr p3))))))

(princ "\n[BSMINERDOC] Loaded. Type BSMINERDOC to place MIN D.O.C. note.")
(princ)
