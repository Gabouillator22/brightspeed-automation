;;; ============================================================
;;; BRIGHTSPEED CORE - v1.0
;;; Run BSSETUP once per drawing, then BSROW on a centerline.
;;; ============================================================

(defun bs-ensure-layer (lname color / )
  (if (not (tblsearch "LAYER" lname))
    (command "_-LAYER" "_M" lname "_C" color lname "")
  )
  (princ)
)

;;; Create all Brightspeed layers
(defun c:BSSETUP ( / )
  (princ "\n[Brightspeed] Creating layer set...")
  (bs-ensure-layer "AERIAL FIBER" "1")
  (bs-ensure-layer "BURIED FIBER IN DUCT" "5")
  (bs-ensure-layer "ELASH" "6")
  (bs-ensure-layer "R/W" "2")
  (bs-ensure-layer "EOP" "3")
  (bs-ensure-layer "CENTERLINE" "4")
  (bs-ensure-layer "POLES" "1")
  (bs-ensure-layer "HANDHOLES" "5")
  (bs-ensure-layer "BOREPITS" "2")
  (bs-ensure-layer "CALLOUTS" "7")
  (bs-ensure-layer "VIEWPORT IMAGE" "8")
  (bs-ensure-layer "BORDER" "7")
  (princ "\n[Brightspeed] Layers ready.")
  (princ)
)

;;; Quick layer switches
(defun c:BSFIBER ( / )
  (bs-ensure-layer "AERIAL FIBER" "1")
  (setvar "CLAYER" "AERIAL FIBER")
  (setvar "PLINEWID" 0.5)
  (princ "\n[Brightspeed] Layer: AERIAL FIBER | Width: 0.5")
  (princ)
)

(defun c:BSBURIED ( / )
  (bs-ensure-layer "BURIED FIBER IN DUCT" "5")
  (setvar "CLAYER" "BURIED FIBER IN DUCT")
  (setvar "PLINEWID" 0.5)
  (princ "\n[Brightspeed] Layer: BURIED FIBER IN DUCT | Width: 0.5")
  (princ)
)

(defun c:BSCL ( / )
  (bs-ensure-layer "CENTERLINE" "4")
  (setvar "CLAYER" "CENTERLINE")
  (setvar "PLINEWID" 0)
  (princ "\n[Brightspeed] Layer: CENTERLINE")
  (princ)
)

;;; ============================================================
;;; BSROW - Auto-draw R/W and EOP from selected centerline(s)
;;; Default: 30' R/W from CL, 10' EOP from CL (20' inside R/W)
;;; ============================================================
(defun c:BSROW ( / ss row-dist eop-dist old-layer i ent ent-type pt-on-line side-pt)
  (princ "\n[Brightspeed] BSROW - Auto-offset R/W and EOP.")
  (princ "\nSelect centerline(s) (polyline or line): ")
  (setq ss (ssget '((0 . "LWPOLYLINE,LINE,POLYLINE"))))
  
  (if (not ss)
    (progn
      (princ "\n[Brightspeed] Nothing selected. Aborting.")
      (princ)
    )
    (progn
      (initget 6)
      (setq row-dist (getreal "\nR/W offset from centerline <30.0>: "))
      (if (not row-dist) (setq row-dist 30.0))
      
      (initget 6)
      (setq eop-dist (getreal "\nEOP offset from centerline <10.0>: "))
      (if (not eop-dist) (setq eop-dist 10.0))
      
      (princ (strcat "\n[Brightspeed] Processing " (itoa (sslength ss)) " centerline(s)..."))
      
      (setq old-layer (getvar "CLAYER"))
      (bs-ensure-layer "R/W" "2")
      (bs-ensure-layer "EOP" "3")
      
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (setq ent-type (cdr (assoc 0 (entget ent))))
        
        ; Get a point ON the entity to use as a base for offset direction
        (setq pt-on-line 
          (cond
            ((= ent-type "LWPOLYLINE") (vlax-curve-getPointAtParam ent 0))
            ((= ent-type "LINE") (cdr (assoc 10 (entget ent))))
            ((= ent-type "POLYLINE") (vlax-curve-getPointAtParam ent 0))
          )
        )
        
        ; Offset R/W both sides
        (setvar "CLAYER" "R/W")
        ; Side 1: offset to the "left" (large positive Y from line)
        (command "_.OFFSET" row-dist ent (list (+ (car pt-on-line) 100000.0) (+ (cadr pt-on-line) 100000.0) 0.0) "")
        ; Side 2: offset to the "right"
        (command "_.OFFSET" row-dist ent (list (- (car pt-on-line) 100000.0) (- (cadr pt-on-line) 100000.0) 0.0) "")
        
        ; Offset EOP both sides
        (setvar "CLAYER" "EOP")
        (command "_.OFFSET" eop-dist ent (list (+ (car pt-on-line) 100000.0) (+ (cadr pt-on-line) 100000.0) 0.0) "")
        (command "_.OFFSET" eop-dist ent (list (- (car pt-on-line) 100000.0) (- (cadr pt-on-line) 100000.0) 0.0) "")
        
        (setq i (1+ i))
      )
      
      (setvar "CLAYER" old-layer)
      (princ "\n[Brightspeed] Done. R/W on yellow, EOP on green.")
      (princ)
    )
  )
)

;;; Load message
(princ "\n=============================================")
(princ "\n  BRIGHTSPEED CORE LOADED")
(princ "\n  BSSETUP  - Create layers (run once)")
(princ "\n  BSROW    - Auto-draw R/W + EOP from CL")
(princ "\n  BSFIBER  - Switch to AERIAL FIBER")
(princ "\n  BSBURIED - Switch to BURIED FIBER")
(princ "\n  BSCL     - Switch to CENTERLINE")
(princ "\n=============================================")
(princ)
