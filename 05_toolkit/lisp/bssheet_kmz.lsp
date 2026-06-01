;;; ============================================================
;;; BSSHEETKMZ - Import KMZ field data and place proposed sheets
;;;
;;; Stable version: runs the existing BSKMZ importer, finds the newly
;;; imported running-line polylines, then places parallel proposed sheets
;;; only near the route corridor.
;;; ============================================================

(vl-load-com)

(if (not (and (boundp '*bs-toolkit-dir*) *bs-toolkit-dir*))
  (setq *bs-toolkit-dir*
    (cond
      ((findfile "bssheet_kmz.lsp") (vl-filename-directory (findfile "bssheet_kmz.lsp")))
      ((findfile "bs_helpers.lsp")  (vl-filename-directory (findfile "bs_helpers.lsp")))
      (T nil))))

(defun bssheetkmz-ensure-layer (lname color / )
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "C" (itoa color) lname ""))
  (command "_.LAYER" "ON" lname "T" lname "")
  (princ))

(defun bssheetkmz-running-layer-p (layer / up)
  (setq up (strcase layer))
  (or (= up "BURIED FIBER IN DUCT")
      (= up "AERIAL FIBER")
      (= up "E-LASH")))

(defun bssheetkmz-lwpoly-verts (ent / data verts pair)
  (setq data (entget ent) verts '())
  (foreach pair data
    (if (= (car pair) 10)
      (setq verts (append verts (list (cdr pair))))))
  verts)

(defun bssheetkmz-new-entities-after (before / out ent)
  (setq out '())
  (setq ent (entnext before))
  (while ent
    (setq out (append out (list ent)))
    (setq ent (entnext ent)))
  out)

(defun bssheetkmz-running-entities (entities / out ent data layer typ)
  (setq out '())
  (foreach ent entities
    (setq data (entget ent))
    (setq typ (cdr (assoc 0 data)))
    (setq layer (cdr (assoc 8 data)))
    (if (and (= typ "LWPOLYLINE") layer (bssheetkmz-running-layer-p layer))
      (setq out (append out (list ent)))))
  out)

(defun bssheetkmz-make-rect (x1 y1 x2 y2 layer / )
  (entmakex
    (list
      '(0 . "LWPOLYLINE")
      '(100 . "AcDbEntity")
      (cons 8 layer)
      '(100 . "AcDbPolyline")
      '(90 . 4)
      '(70 . 1)
      (cons 10 (list x1 y1))
      (cons 10 (list x2 y1))
      (cons 10 (list x2 y2))
      (cons 10 (list x1 y2)))))

(defun bssheetkmz-make-text (x y label layer / )
  (entmakex
    (list
      '(0 . "TEXT")
      (cons 8 layer)
      (cons 10 (list x y 0.0))
      (cons 11 (list x y 0.0))
      '(40 . 60.0)
      (cons 1 label)
      '(50 . 0.0)
      '(72 . 1)
      '(73 . 2)
      '(7 . "STANDARD"))))

(defun bssheetkmz-dist2d (a b / dx dy)
  (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)))
  (sqrt (+ (* dx dx) (* dy dy))))

(defun bssheetkmz-interp (a b ratio / )
  (list
    (+ (car a) (* (- (car b) (car a)) ratio))
    (+ (cadr a) (* (- (cadr b) (cadr a)) ratio))))

(defun bssheetkmz-required-points-from-verts (verts sample buffer / pts i a b seglen d ratio p)
  (setq pts '() i 0)
  (while (< (1+ i) (length verts))
    (setq a (nth i verts) b (nth (1+ i) verts))
    (setq seglen (bssheetkmz-dist2d a b))
    (setq d 0.0)
    (while (<= d seglen)
      (setq ratio (if (> seglen 0.001) (/ d seglen) 0.0))
      (setq p (bssheetkmz-interp a b ratio))
      (setq pts
        (append pts
          (list
            p
            (list (car p) (+ (cadr p) buffer))
            (list (car p) (- (cadr p) buffer)))))
      (setq d (+ d sample)))
    (setq i (1+ i)))
  pts)

(defun bssheetkmz-required-points (run-ents sample buffer / pts ent verts)
  (setq pts '())
  (foreach ent run-ents
    (setq verts (bssheetkmz-lwpoly-verts ent))
    (if (>= (length verts) 2)
      (setq pts (append pts (bssheetkmz-required-points-from-verts verts sample buffer)))))
  pts)

(defun bssheetkmz-minmax-x (pts / minx maxx p started)
  (setq started nil)
  (foreach p pts
    (if (not started)
      (progn
        (setq minx (car p) maxx (car p) started T))
      (progn
        (setq minx (min minx (car p)))
        (setq maxx (max maxx (car p))))))
  (if started (list minx maxx) nil))

(defun bssheetkmz-slice-y-range (pts x1 x2 / p y miny maxy found)
  (setq found nil)
  (foreach p pts
    (if (and (>= (car p) x1) (<= (car p) x2))
      (progn
        (setq y (cadr p))
        (if (not found)
          (progn
            (setq miny y maxy y found T))
          (progn
            (setq miny (min miny y))
            (setq maxy (max maxy y)))))))
  (if found (list miny maxy) nil))

(defun bssheetkmz-ceil (value / whole)
  (setq whole (fix value))
  (if (> value whole) (1+ whole) whole))

(defun bssheetkmz-sheet-label (n / )
  (strcat "S" (if (< n 10) "00" (if (< n 100) "0" "")) (itoa n)))

(defun bssheetkmz-place-route-sheets (run-ents / width height buffer sample pts xr minx maxx x xEnd yr miny maxy span rows totalHeight y count row label)
  (setq width 900.0 height 600.0 buffer 150.0 sample 50.0)
  (setq pts (bssheetkmz-required-points run-ents sample buffer))
  (setq xr (bssheetkmz-minmax-x pts))
  (if (not xr)
    nil
    (progn
      (setq minx (- (car xr) (* width 0.6667)))
      (setq maxx (+ (cadr xr) (* width 0.3333)))
      (bssheetkmz-ensure-layer "BS-SHEET-PROPOSED" 30)
      (bssheetkmz-ensure-layer "BS-SHEET-LABELS" 30)
      (setq count 0 x minx)
      (while (< x maxx)
        (setq xEnd (+ x width))
        (setq yr (bssheetkmz-slice-y-range pts x xEnd))
        (if yr
          (progn
            (setq miny (car yr) maxy (cadr yr))
            (setq span (- maxy miny))
            (setq rows (max 1 (bssheetkmz-ceil (/ span height))))
            (setq totalHeight (* rows height))
            (setq y (- (/ (+ miny maxy) 2.0) (/ totalHeight 2.0)))
            (setq row 0)
            (while (< row rows)
              (setq count (1+ count))
              (setq label (bssheetkmz-sheet-label count))
              (bssheetkmz-make-rect x y xEnd (+ y height) "BS-SHEET-PROPOSED")
              (bssheetkmz-make-text (+ x (/ width 2.0)) (+ y (/ height 2.0)) label "BS-SHEET-LABELS")
              (setq y (+ y height))
              (setq row (1+ row)))))
        (setq x xEnd))
      count)))

(defun c:BSSHEETKMZ ( / *error* before new-ents run-ents count)
  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg) "*CANCEL*")
             (/= msg "Function cancelled")
             (not (wcmatch (strcase msg) "*QUIT*EXIT*")))
      (princ (strcat "\n[BSSHEETKMZ] ERROR: " msg)))
    (princ))

  (princ "\n[BSSHEETKMZ] Import KMZ, then sheet the imported running lines.")
  (if (and (boundp '*bs-toolkit-dir*) *bs-toolkit-dir*)
    (progn
      (if (findfile (strcat *bs-toolkit-dir* "\\bs_helpers.lsp"))
        (load (strcat *bs-toolkit-dir* "\\bs_helpers.lsp")))
      (if (findfile (strcat *bs-toolkit-dir* "\\bskmz.lsp"))
        (load (strcat *bs-toolkit-dir* "\\bskmz.lsp")))))

  (setq before (entlast))
  (c:BSKMZ)
  (setq new-ents (bssheetkmz-new-entities-after before))
  (setq run-ents (bssheetkmz-running-entities new-ents))
  (princ (strcat "\n[BSSHEETKMZ] Imported running line(s): " (itoa (length run-ents))))
  (if (or (null run-ents) (= (length run-ents) 0))
    (progn
      (princ "\n[BSSHEETKMZ] ERROR: No newly imported running-line polylines found.")
      (exit)))

  (setq count (bssheetkmz-place-route-sheets run-ents))
  (if (and count (> count 0))
    (princ (strcat "\n[BSSHEETKMZ] Created " (itoa count) " parallel proposed sheet(s). Review before accepting."))
    (princ "\n[BSSHEETKMZ] ERROR: Could not calculate running-line sheets."))
  (princ))

(princ "\n[BSSHEETKMZ] Loaded. Command: BSSHEETKMZ.")
(princ)
