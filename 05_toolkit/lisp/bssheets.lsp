;;; ============================================================
;;; BSSHEETS - Proposed sheet rectangle review workflow
;;; Commands:
;;;   BSSHEETRECT   - measure/save sample sheet size
;;;   BSSHEETLOAD   - load bssheet_plan.lsp or bssheet_plan.csv
;;;   BSSHEETMAKE   - make rectangles from loaded CSV plan
;;;   BSSHEETACCEPT - move selected proposed rectangles to BORDER
;;;   BSSHEETCLEAR  - hide proposed sheet geometry without deleting
;;; ============================================================

(vl-load-com)

(setq *bssheet-proposed-layer* "BS-SHEET-PROPOSED")
(setq *bssheet-label-layer* "BS-SHEET-LABELS")
(setq *bssheet-hidden-layer* "BS-SHEET-HIDDEN")
(setq *bssheet-border-layer* "BORDER")
(setq *bssheet-plan* nil)

(defun bssheet-dir ( / )
  (cond
    ((and (boundp '*bs-toolkit-dir*) *bs-toolkit-dir*) *bs-toolkit-dir*)
    ((findfile "bssheets.lsp") (vl-filename-directory (findfile "bssheets.lsp")))
    (T (vl-filename-directory (findfile "bs_helpers.lsp")))))

(defun bssheet-path (fname / )
  (strcat (bssheet-dir) "\\" fname))

(defun bssheet-config-path (fname / root cfgdir)
  (setq root (vl-filename-directory (bssheet-dir)))
  (setq cfgdir (strcat root "\\config"))
  (if (not (vl-file-directory-p cfgdir))
    (vl-mkdir cfgdir))
  (strcat cfgdir "\\" fname))

(defun bssheet-ensure-layer (lname color / )
  (if (not (tblsearch "LAYER" lname))
    (command "_.LAYER" "N" lname "C" (itoa color) lname ""))
  (command "_.LAYER" "ON" lname "T" lname "")
  (princ))

(defun bssheet-set-bylayer (ent / elist)
  (if (and ent (entget ent))
    (progn
      (setq elist (entget ent))
      (if (assoc 62 elist) (setq elist (subst '(62 . 256) (assoc 62 elist) elist)))
      (entmod elist)
      (entupd ent)))
  (princ))

(defun bssheet-force-layer (ent lname / elist)
  (if (and ent (entget ent))
    (progn
      (setq elist (entget ent))
      (setq elist (subst (cons 8 lname) (assoc 8 elist) elist))
      (entmod elist)
      (entupd ent)))
  (princ))

(defun bssheet-split (s sep / lst cur i slen seplen)
  (setq lst '() cur "" i 1 slen (strlen s) seplen (strlen sep))
  (while (<= i slen)
    (if (and (<= (+ i seplen -1) slen) (= (substr s i seplen) sep))
      (progn (setq lst (cons cur lst) cur "" i (+ i seplen)))
      (progn (setq cur (strcat cur (substr s i 1)) i (1+ i)))))
  (reverse (cons cur lst)))

(defun bssheet-join (items sep / out)
  (setq out "")
  (foreach item items
    (setq out (if (= out "") item (strcat out sep item))))
  out)

(defun bssheet-write-default-config (width height / path f)
  (setq path (bssheet-config-path "bssheet_config.json"))
  (setq f (open path "w"))
  (if f
    (progn
      (write-line "{" f)
      (write-line (strcat "  \"sheet_width_ft\": " (rtos width 2 3) ",") f)
      (write-line (strcat "  \"sheet_height_ft\": " (rtos height 2 3) ",") f)
      (write-line "  \"overlap_ft\": 0," f)
      (write-line "  \"side_margin_ft\": 75," f)
      (write-line "  \"road_buffer_left_ft\": 150," f)
      (write-line "  \"road_buffer_right_ft\": 150," f)
      (write-line "  \"required_edge_clearance_ft\": 20," f)
      (write-line "  \"endpoint_inset_ratio\": 0.6667," f)
      (write-line "  \"fixed_sheet_angle_deg\": 0," f)
      (write-line "  \"target_epsg\": 2264," f)
      (write-line "  \"border_layer\": \"BORDER\"," f)
      (write-line "  \"proposed_layer\": \"BS-SHEET-PROPOSED\"," f)
      (write-line "  \"label_layer\": \"BS-SHEET-LABELS\"," f)
      (write-line "  \"hidden_layer\": \"BS-SHEET-HIDDEN\"," f)
      (write-line "  \"sample_interval_ft\": 25," f)
      (write-line "  \"label_height_ft\": 60" f)
      (write-line "}" f)
      (close f)
      (princ (strcat "\n[BSSHEETRECT] Saved sheet size to " path)))
    (princ (strcat "\n[BSSHEETRECT] Could not write " path)))
  (princ))

(defun bssheet-lwpoly-verts (ent / data verts pair)
  (setq data (entget ent) verts '())
  (foreach pair data
    (if (= (car pair) 10)
      (setq verts (append verts (list (cdr pair))))))
  verts)

(defun bssheet-sample-size (ent / verts dists a b)
  (setq verts (bssheet-lwpoly-verts ent) dists '())
  (if (>= (length verts) 4)
    (progn
      (setq a (nth 0 verts) b (nth 1 verts) dists (append dists (list (distance a b))))
      (setq a (nth 1 verts) b (nth 2 verts) dists (append dists (list (distance a b))))
      (list (apply 'max dists) (apply 'min dists)))
    nil))

(defun bssheet-make-rect (verts layer / )
  (entmakex
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
            '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1))
      (mapcar '(lambda (p) (cons 10 p)) verts))))

(defun bssheet-make-text (pt angle text layer height / )
  (entmakex
    (list
      '(0 . "TEXT")
      (cons 8 layer)
      (cons 10 pt)
      (cons 11 pt)
      (cons 40 height)
      (cons 1 text)
      (cons 50 angle)
      '(72 . 1)
      '(73 . 2)
      '(7 . "STANDARD"))))

(defun bssheet-csv-row-to-plan (cols / label cx cy angle width height verts)
  (if (>= (length cols) 18)
    (progn
      (setq label (nth 0 cols)
            cx (atof (nth 2 cols))
            cy (atof (nth 3 cols))
            angle (atof (nth 4 cols))
            width (atof (nth 6 cols))
            height (atof (nth 7 cols))
            verts (list
                    (list (atof (nth 10 cols)) (atof (nth 11 cols)) 0.0)
                    (list (atof (nth 12 cols)) (atof (nth 13 cols)) 0.0)
                    (list (atof (nth 14 cols)) (atof (nth 15 cols)) 0.0)
                    (list (atof (nth 16 cols)) (atof (nth 17 cols)) 0.0)))
      (list label (list cx cy 0.0) angle width height verts))
    nil))

(defun bssheet-read-csv-plan (path / f line cols plan row)
  (setq plan '())
  (setq f (open path "r"))
  (if f
    (progn
      (read-line f)
      (while (setq line (read-line f))
        (setq cols (bssheet-split line ","))
        (setq row (bssheet-csv-row-to-plan cols))
        (if row (setq plan (append plan (list row)))))
      (close f)))
  plan)

(defun bssheet-make-loaded-plan ( / rec)
  (bssheet-ensure-layer *bssheet-proposed-layer* 30)
  (bssheet-ensure-layer *bssheet-label-layer* 30)
  (foreach rec *bssheet-plan*
    (bssheet-make-rect (nth 5 rec) *bssheet-proposed-layer*)
    (bssheet-make-text (nth 1 rec) (nth 2 rec) (car rec) *bssheet-label-layer* 60.0))
  (princ (strcat "\n[BSSHEETMAKE] Created " (itoa (length *bssheet-plan*)) " proposed sheet rectangle(s)."))
  (princ))

(defun bssheet-restore-env (old-clayer old-cmdecho / )
  (if old-clayer (setvar "CLAYER" old-clayer))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))

(defun c:BSSHEETRECT ( / *error* old-clayer old-cmdecho sel ent size p1 p2 width height verts)
  (setq old-clayer (getvar "CLAYER") old-cmdecho (getvar "CMDECHO"))
  (defun *error* (msg)
    (command "_.UNDO" "_E")
    (bssheet-restore-env old-clayer old-cmdecho)
    (if (and msg (/= (strcase msg) "*CANCEL*"))
      (princ (strcat "\n[BSSHEETRECT] ERROR: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (princ "\n[BSSHEETRECT] Select sample BORDER rectangle, or press Enter to pick two corners.")
  (setq sel (entsel "\nSample rectangle: "))
  (cond
    (sel
      (setq ent (car sel) size (bssheet-sample-size ent))
      (if size
        (progn
          (setq width (car size) height (cadr size))
          (bssheet-write-default-config width height)
          (princ (strcat "\n[BSSHEETRECT] Width=" (rtos width 2 3) " Height=" (rtos height 2 3))))
        (princ "\n[BSSHEETRECT] Selected entity is not a usable four-vertex LWPOLYLINE.")))
    (T
      (setq p1 (getpoint "\nFirst corner: "))
      (if p1
        (progn
          (setq p2 (getcorner p1 "\nOpposite corner: "))
          (if p2
            (progn
              (setq width (abs (- (car p2) (car p1))) height (abs (- (cadr p2) (cadr p1))))
              (setq verts
                (list
                  (list (car p1) (cadr p1) 0.0)
                  (list (car p2) (cadr p1) 0.0)
                  (list (car p2) (cadr p2) 0.0)
                  (list (car p1) (cadr p2) 0.0)))
              (bssheet-ensure-layer *bssheet-proposed-layer* 30)
              (bssheet-make-rect verts *bssheet-proposed-layer*)
              (bssheet-write-default-config width height)
              (princ (strcat "\n[BSSHEETRECT] Width=" (rtos width 2 3) " Height=" (rtos height 2 3)))))))))
  (command "_.UNDO" "_E")
  (bssheet-restore-env old-clayer old-cmdecho)
  (princ))

(defun c:BSSHEETLOAD ( / *error* old-clayer old-cmdecho lsp csvpath)
  (setq old-clayer (getvar "CLAYER") old-cmdecho (getvar "CMDECHO"))
  (defun *error* (msg)
    (bssheet-restore-env old-clayer old-cmdecho)
    (if (and msg (/= (strcase msg) "*CANCEL*"))
      (princ (strcat "\n[BSSHEETLOAD] ERROR: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (setq lsp (bssheet-path "bssheet_plan.lsp"))
  (setq csvpath (bssheet-path "bssheet_plan.csv"))
  (cond
    ((findfile lsp)
      (load lsp)
      (princ "\n[BSSHEETLOAD] Loaded bssheet_plan.lsp. Run BSSHEETMAKEPLAN, or BSSHEETLOAD again after regenerating."))
    ((findfile csvpath)
      (setq *bssheet-plan* (bssheet-read-csv-plan csvpath))
      (princ (strcat "\n[BSSHEETLOAD] Loaded " (itoa (length *bssheet-plan*)) " row(s) from bssheet_plan.csv. Run BSSHEETMAKE.")))
    (T
      (princ "\n[BSSHEETLOAD] No bssheet_plan.lsp or bssheet_plan.csv found next to bssheets.lsp.")))
  (bssheet-restore-env old-clayer old-cmdecho)
  (princ))

(defun c:BSSHEETMAKE ( / *error* old-clayer old-cmdecho)
  (setq old-clayer (getvar "CLAYER") old-cmdecho (getvar "CMDECHO"))
  (defun *error* (msg)
    (command "_.UNDO" "_E")
    (bssheet-restore-env old-clayer old-cmdecho)
    (if (and msg (/= (strcase msg) "*CANCEL*"))
      (princ (strcat "\n[BSSHEETMAKE] ERROR: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (if (not *bssheet-plan*)
    (progn
      (setq *bssheet-plan* (bssheet-read-csv-plan (bssheet-path "bssheet_plan.csv")))))
  (if *bssheet-plan*
    (progn
      (command "_.UNDO" "_BE")
      (bssheet-make-loaded-plan)
      (command "_.UNDO" "_E"))
    (princ "\n[BSSHEETMAKE] No CSV plan loaded. Run BSSHEETLOAD or generate bssheet_plan.csv."))
  (bssheet-restore-env old-clayer old-cmdecho)
  (princ))

(defun c:BSSHEETACCEPT ( / *error* old-clayer old-cmdecho ss i ent data moved)
  (setq old-clayer (getvar "CLAYER") old-cmdecho (getvar "CMDECHO") moved 0)
  (defun *error* (msg)
    (command "_.UNDO" "_E")
    (bssheet-restore-env old-clayer old-cmdecho)
    (if (and msg (/= (strcase msg) "*CANCEL*"))
      (princ (strcat "\n[BSSHEETACCEPT] ERROR: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (bssheet-ensure-layer *bssheet-border-layer* 7)
  (setq ss (ssget "_:L" (list '(0 . "LWPOLYLINE") (cons 8 *bssheet-proposed-layer*))))
  (if ss
    (progn
      (command "_.UNDO" "_BE")
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i) data (entget ent))
        (if (= (cdr (assoc 8 data)) *bssheet-proposed-layer*)
          (progn
            (bssheet-force-layer ent *bssheet-border-layer*)
            (bssheet-set-bylayer ent)
            (setq moved (1+ moved))))
        (setq i (1+ i)))
      (command "_.UNDO" "_E")
      (princ (strcat "\n[BSSHEETACCEPT] Moved " (itoa moved) " rectangle(s) to BORDER.")))
    (princ "\n[BSSHEETACCEPT] Nothing selected on BS-SHEET-PROPOSED."))
  (bssheet-restore-env old-clayer old-cmdecho)
  (princ))

(defun c:BSSHEETCLEAR ( / *error* old-clayer old-cmdecho restore-clayer ss i ent moved)
  (setq old-clayer (getvar "CLAYER") old-cmdecho (getvar "CMDECHO") moved 0)
  (setq restore-clayer old-clayer)
  (defun *error* (msg)
    (command "_.UNDO" "_E")
    (if (and restore-clayer (/= (strcase restore-clayer) (strcase *bssheet-hidden-layer*)))
      (setvar "CLAYER" restore-clayer))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if (and msg (/= (strcase msg) "*CANCEL*"))
      (princ (strcat "\n[BSSHEETCLEAR] ERROR: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (bssheet-ensure-layer *bssheet-hidden-layer* 8)
  (setq ss (ssget "_X" (list '(-4 . "<OR") (cons 8 *bssheet-proposed-layer*) (cons 8 *bssheet-label-layer*) '(-4 . "OR>"))))
  (if ss
    (progn
      (command "_.UNDO" "_BE")
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i))
        (bssheet-force-layer ent *bssheet-hidden-layer*)
        (setq moved (1+ moved))
        (setq i (1+ i)))
      (if (= (strcase old-clayer) (strcase *bssheet-hidden-layer*))
        (progn (setvar "CLAYER" "0") (setq restore-clayer "0")))
      (command "_.LAYER" "F" *bssheet-hidden-layer* "")
      (command "_.UNDO" "_E")
      (princ (strcat "\n[BSSHEETCLEAR] Moved " (itoa moved) " proposed sheet item(s) to frozen BS-SHEET-HIDDEN.")))
    (princ "\n[BSSHEETCLEAR] No proposed sheet geometry found."))
  (if restore-clayer (setvar "CLAYER" restore-clayer))
  (setvar "CMDECHO" old-cmdecho)
  (princ))

(princ "\n[BSSHEETS] Loaded. Commands: BSSHEETRECT, BSSHEETLOAD, BSSHEETMAKE, BSSHEETACCEPT, BSSHEETCLEAR.")
(princ)
