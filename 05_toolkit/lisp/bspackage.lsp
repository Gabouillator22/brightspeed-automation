(vl-load-com)

;;; ============================================================
;;; BSPACKAGE - Brightspeed packaged layout builder
;;;
;;; Commands:
;;;   BSPACKAGEINDEX - Scan model-space sheets and write dry-run reports
;;;   BSPACKAGEBUILD - Build a packaged DWG from layout template 2
;;;
;;; Standalone command file. APPLOAD this file directly.
;;; AutoCAD Map 3D 2027
;;; ============================================================

(setq *bspkg-default-config*
  (list
    (cons "plan_template_layout" "2")
    (cons "number_layer" "BORDER")
    (cons "sheet_rectangle_layers" (list "BS-SHEET-PROPOSED" "BORDER"))
    (cons "hidden_layer" "BS-SHEET-HIDDEN")
    (cons "output_suffix" "_PACKAGED")
    (cons "viewport_padding_ft" 50.0)
    (cons "require_clean_index" T)
    (cons "layout_name_mode" "sheet_number")
    (cons "allow_sheet_number_gaps" nil)
    (cons "freeze_border_in_plan_viewports" T)
    (cons "sheet_map_layouts" (list "1" "Map" "MAP"))
    (cons "profile_layouts" '())
    (cons "max_pages_per_permit" 25)
    (cons "sectioning_enabled" nil)
    (cons "first_plan_page_in_section" 2)
    (cons "plan_slots_per_full_section" 24)
    (cons "titleblock_update_enabled" T)
    (cons "titleblock_block_name_patterns" (list "*TITLE*" "*BORDER*" "*SQUAN*" "*BRIGHTSPEED*"))
    (cons "titleblock_sheet_attribute_tags" (list "SHEET" "SHT" "SHEET_NO" "SHEET_NUMBER" "PAGE"))
    (cons "titleblock_total_attribute_tags" (list "OF" "TOTAL" "TOTAL_SHEETS" "SHEET_TOTAL"))
    (cons "titleblock_project_attribute_tags" (list "PROJECT" "PROJECT_NO" "PERMIT" "PERMIT_NO"))
    (cons "dry_run_default" T)
  ))

(setq *bspkg-last-index* nil)

(defun bspkg-lisp-dir ( / )
  (cond
    ((findfile "bspackage.lsp") (vl-filename-directory (findfile "bspackage.lsp")))
    (T nil)))

(defun bspkg-root-dir ( / )
  (vl-filename-directory (bspkg-lisp-dir)))

(defun bspkg-config-path ( / )
  (strcat (bspkg-root-dir) "\\config\\bspackage_config.json"))

(defun bspkg-python-script-path ( / )
  (strcat (bspkg-root-dir) "\\python\\bspackage.py"))

(defun bspkg-q (value / )
  (strcat "\"" value "\""))

(defun bspkg-path-join (a b / )
  (strcat a "\\" b))

(defun bspkg-save-env ( / )
  (list
    (cons "CMDECHO" (getvar "CMDECHO"))
    (cons "OSMODE" (getvar "OSMODE"))
    (cons "CLAYER" (getvar "CLAYER"))))

(defun bspkg-restore-env (env / item)
  (foreach item env
    (if (cdr item)
      (setvar (car item) (cdr item))))
  (princ))

(defun bspkg-assoc-get (key alist / item)
  (setq item (assoc key alist))
  (if item (cdr item) nil))

(defun bspkg-string-trim (value / )
  (vl-string-trim " \t\r\n" value))

(defun bspkg-string-replace (text old new / pos out start oldlen)
  (setq out "" start 1 oldlen (strlen old))
  (while (setq pos (vl-string-search old text (1- start)))
    (setq pos (1+ pos))
    (setq out (strcat out (substr text start (- pos start)) new))
    (setq start (+ pos oldlen)))
  (strcat out (substr text start)))

(defun bspkg-normalize-space (text / out prev-space ch i)
  (setq out "" prev-space nil i 1)
  (while (<= i (strlen text))
    (setq ch (substr text i 1))
    (if (or (= ch " ") (= ch "\t") (= ch "\n") (= ch "\r"))
      (if (not prev-space)
        (progn
          (setq out (strcat out " "))
          (setq prev-space T)))
      (progn
        (setq out (strcat out ch))
        (setq prev-space nil)))
    (setq i (1+ i)))
  (bspkg-string-trim out))

(defun bspkg-json-escape (value / out ch i)
  (setq out "" i 1)
  (while (<= i (strlen value))
    (setq ch (substr value i 1))
    (setq out
      (strcat out
        (cond
          ((= ch "\\") "\\\\")
          ((= ch "\"") "\\\"")
          ((= ch "\n") "\\n")
          ((= ch "\r") "")
          (T ch))))
    (setq i (1+ i)))
  out)

(defun bspkg-json-quote (value / )
  (strcat "\"" (bspkg-json-escape value) "\""))

(defun bspkg-json-bool (value / )
  (if value "true" "false"))

(defun bspkg-read-file (path / handle lines line)
  (if (not (findfile path))
    nil
    (progn
      (setq handle (open path "r"))
      (setq lines '())
      (if handle
        (progn
          (while (setq line (read-line handle))
            (setq lines (cons line lines)))
          (close handle)
          (apply 'strcat (reverse (mapcar '(lambda (s) (strcat s "\n")) lines))))
        nil))))

(defun bspkg-json-key-raw (text key / marker pos start ch depth out)
  (setq marker (strcat "\"" key "\""))
  (setq pos (vl-string-search marker text))
  (if (null pos)
    nil
    (progn
      (setq pos (+ pos (strlen marker)))
      (setq pos (vl-string-search ":" text pos))
      (if (null pos)
        nil
        (progn
          (setq start (+ pos 2))
          (while (and (<= start (strlen text))
                      (member (substr text start 1) '(" " "\t" "\r" "\n")))
            (setq start (1+ start)))
          (setq ch (substr text start 1))
          (cond
            ((= ch "\"")
             (setq start (1+ start) out "")
             (while (<= start (strlen text))
               (setq ch (substr text start 1))
               (cond
                 ((= ch "\\")
                  (setq start (1+ start))
                  (if (<= start (strlen text))
                    (setq out (strcat out (substr text start 1)))))
                 ((= ch "\"")
                  (setq start (1+ (strlen text))))
                 (T
                  (setq out (strcat out ch))))
               (setq start (1+ start)))
             out)
            ((= ch "[")
             (setq depth 1 start (1+ start) out "")
             (while (and (> depth 0) (<= start (strlen text)))
               (setq ch (substr text start 1))
               (cond
                 ((= ch "[") (setq depth (1+ depth) out (strcat out ch)))
                 ((= ch "]")
                  (setq depth (1- depth))
                  (if (> depth 0)
                    (setq out (strcat out ch))))
                 (T (setq out (strcat out ch))))
               (setq start (1+ start)))
             out)
            (T
             (setq out "")
             (while (and (<= start (strlen text))
                         (not (member (substr text start 1) '("," "}" "\n" "\r"))))
               (setq out (strcat out (substr text start 1)))
               (setq start (1+ start)))
             (bspkg-string-trim out))))))))

(defun bspkg-json-string (text key default / raw)
  (setq raw (bspkg-json-key-raw text key))
  (if raw raw default))

(defun bspkg-json-number (text key default / raw)
  (setq raw (bspkg-json-key-raw text key))
  (if raw (atof raw) default))

(defun bspkg-json-int (text key default / raw)
  (setq raw (bspkg-json-key-raw text key))
  (if raw (atoi raw) default))

(defun bspkg-json-bool-read (text key default / raw upper)
  (setq raw (bspkg-json-key-raw text key))
  (if raw
    (progn
      (setq upper (strcase (bspkg-string-trim raw)))
      (if (= upper "TRUE") T nil))
    default))

(defun bspkg-json-string-array (text key default / raw chars i ch in-quote cur out)
  (setq raw (bspkg-json-key-raw text key))
  (if (not raw)
    default
    (progn
      (setq out '() in-quote nil cur "" i 1)
      (while (<= i (strlen raw))
        (setq ch (substr raw i 1))
        (cond
          ((= ch "\"")
           (if in-quote
             (progn
               (setq out (append out (list cur)))
               (setq cur "" in-quote nil))
             (setq in-quote T)))
          (in-quote
           (setq cur (strcat cur ch))))
        (setq i (1+ i)))
      (if out out default))))

(defun bspkg-load-config ( / text cfg)
  (setq cfg *bspkg-default-config*)
  (setq text (bspkg-read-file (bspkg-config-path)))
  (if text
    (progn
      (setq cfg
        (subst (cons "plan_template_layout" (bspkg-json-string text "plan_template_layout" (bspkg-assoc-get "plan_template_layout" cfg))) (assoc "plan_template_layout" cfg) cfg))
      (setq cfg
        (subst (cons "number_layer" (bspkg-json-string text "number_layer" (bspkg-assoc-get "number_layer" cfg))) (assoc "number_layer" cfg) cfg))
      (setq cfg
        (subst (cons "sheet_rectangle_layers" (bspkg-json-string-array text "sheet_rectangle_layers" (bspkg-assoc-get "sheet_rectangle_layers" cfg))) (assoc "sheet_rectangle_layers" cfg) cfg))
      (setq cfg
        (subst (cons "hidden_layer" (bspkg-json-string text "hidden_layer" (bspkg-assoc-get "hidden_layer" cfg))) (assoc "hidden_layer" cfg) cfg))
      (setq cfg
        (subst (cons "output_suffix" (bspkg-json-string text "output_suffix" (bspkg-assoc-get "output_suffix" cfg))) (assoc "output_suffix" cfg) cfg))
      (setq cfg
        (subst (cons "viewport_padding_ft" (bspkg-json-number text "viewport_padding_ft" (bspkg-assoc-get "viewport_padding_ft" cfg))) (assoc "viewport_padding_ft" cfg) cfg))
      (setq cfg
        (subst (cons "require_clean_index" (bspkg-json-bool-read text "require_clean_index" (bspkg-assoc-get "require_clean_index" cfg))) (assoc "require_clean_index" cfg) cfg))
      (setq cfg
        (subst (cons "layout_name_mode" (bspkg-json-string text "layout_name_mode" (bspkg-assoc-get "layout_name_mode" cfg))) (assoc "layout_name_mode" cfg) cfg))
      (setq cfg
        (subst (cons "allow_sheet_number_gaps" (bspkg-json-bool-read text "allow_sheet_number_gaps" (bspkg-assoc-get "allow_sheet_number_gaps" cfg))) (assoc "allow_sheet_number_gaps" cfg) cfg))
      (setq cfg
        (subst (cons "freeze_border_in_plan_viewports" (bspkg-json-bool-read text "freeze_border_in_plan_viewports" (bspkg-assoc-get "freeze_border_in_plan_viewports" cfg))) (assoc "freeze_border_in_plan_viewports" cfg) cfg))
      (setq cfg
        (subst (cons "sheet_map_layouts" (bspkg-json-string-array text "sheet_map_layouts" (bspkg-assoc-get "sheet_map_layouts" cfg))) (assoc "sheet_map_layouts" cfg) cfg))
      (setq cfg
        (subst (cons "profile_layouts" (bspkg-json-string-array text "profile_layouts" (bspkg-assoc-get "profile_layouts" cfg))) (assoc "profile_layouts" cfg) cfg))
      (setq cfg
        (subst (cons "max_pages_per_permit" (bspkg-json-int text "max_pages_per_permit" (bspkg-assoc-get "max_pages_per_permit" cfg))) (assoc "max_pages_per_permit" cfg) cfg))
      (setq cfg
        (subst (cons "sectioning_enabled" (bspkg-json-bool-read text "sectioning_enabled" (bspkg-assoc-get "sectioning_enabled" cfg))) (assoc "sectioning_enabled" cfg) cfg))
      (setq cfg
        (subst (cons "first_plan_page_in_section" (bspkg-json-int text "first_plan_page_in_section" (bspkg-assoc-get "first_plan_page_in_section" cfg))) (assoc "first_plan_page_in_section" cfg) cfg))
      (setq cfg
        (subst (cons "plan_slots_per_full_section" (bspkg-json-int text "plan_slots_per_full_section" (bspkg-assoc-get "plan_slots_per_full_section" cfg))) (assoc "plan_slots_per_full_section" cfg) cfg))
      (setq cfg
        (subst (cons "titleblock_update_enabled" (bspkg-json-bool-read text "titleblock_update_enabled" (bspkg-assoc-get "titleblock_update_enabled" cfg))) (assoc "titleblock_update_enabled" cfg) cfg))
      (setq cfg
        (subst (cons "titleblock_block_name_patterns" (bspkg-json-string-array text "titleblock_block_name_patterns" (bspkg-assoc-get "titleblock_block_name_patterns" cfg))) (assoc "titleblock_block_name_patterns" cfg) cfg))
      (setq cfg
        (subst (cons "titleblock_sheet_attribute_tags" (bspkg-json-string-array text "titleblock_sheet_attribute_tags" (bspkg-assoc-get "titleblock_sheet_attribute_tags" cfg))) (assoc "titleblock_sheet_attribute_tags" cfg) cfg))
      (setq cfg
        (subst (cons "titleblock_total_attribute_tags" (bspkg-json-string-array text "titleblock_total_attribute_tags" (bspkg-assoc-get "titleblock_total_attribute_tags" cfg))) (assoc "titleblock_total_attribute_tags" cfg) cfg))
      (setq cfg
        (subst (cons "dry_run_default" (bspkg-json-bool-read text "dry_run_default" (bspkg-assoc-get "dry_run_default" cfg))) (assoc "dry_run_default" cfg) cfg))))
  cfg)

(defun bspkg-local-drive-p (path / upper)
  (setq upper (strcase path))
  (and (/= (substr upper 1 2) "\\\\")
       (not (wcmatch upper "*\\MAC\\*"))
       (not (wcmatch upper "*//MAC/*"))
       (not (wcmatch upper "*/VOLUMES/*"))
       (not (wcmatch upper "Z:\\*"))))

(defun bspkg-current-dwg-path ( / prefix name)
  (setq prefix (getvar "DWGPREFIX") name (getvar "DWGNAME"))
  (if (and prefix name (/= name ""))
    (strcat prefix name)
    nil))

(defun bspkg-output-dwg-path (cfg / source suffix base path stamp)
  (setq source (bspkg-current-dwg-path))
  (setq suffix (bspkg-assoc-get "output_suffix" cfg))
  (setq base (strcat (vl-filename-directory source) "\\" (vl-filename-base source) suffix ".dwg"))
  (if (findfile base)
    (progn
      (setq stamp (menucmd "M=$(edtime,$(getvar,date),YYYYMMDD_HHMMSS)"))
      (setq path (strcat (vl-filename-directory source) "\\" (vl-filename-base source) suffix "_" stamp ".dwg")))
    (setq path base))
  path)

(defun bspkg-reports-dir (dwg-path / )
  (strcat (vl-filename-directory dwg-path) "\\" (vl-filename-base dwg-path) "_reports"))

(defun bspkg-ensure-dir (path / )
  (if (not (vl-file-directory-p path))
    (vl-mkdir path))
  path)

(defun bspkg-collect-lwpoly-verts (ent / data verts pair)
  (setq data (entget ent) verts '())
  (foreach pair data
    (if (= (car pair) 10)
      (setq verts (append verts (list (cdr pair))))))
  verts)

(defun bspkg-collect-poly-verts (ent / verts next data)
  (setq verts '())
  (setq next (entnext ent))
  (while next
    (setq data (entget next))
    (cond
      ((= (cdr (assoc 0 data)) "VERTEX")
       (setq verts (append verts (list (cdr (assoc 10 data))))))
      ((= (cdr (assoc 0 data)) "SEQEND")
       (setq next nil))
    )
    (if next (setq next (entnext next))))
  verts)

(defun bspkg-poly-closed-p (ent / data flags)
  (setq data (entget ent) flags (cdr (assoc 70 data)))
  (= 1 (logand 1 flags)))

(defun bspkg-rectangle-record (ent layer / verts cleaned pt minx miny maxx maxy tol ok)
  (setq tol 0.01)
  (setq verts
    (cond
      ((= (cdr (assoc 0 (entget ent))) "LWPOLYLINE") (bspkg-collect-lwpoly-verts ent))
      ((= (cdr (assoc 0 (entget ent))) "POLYLINE") (bspkg-collect-poly-verts ent))
      (T nil)))
  (if (and verts (> (length verts) 1)
           (equal (car verts) (car (last verts)) tol))
    (setq verts (reverse (cdr (reverse verts)))))
  (if (or (not verts) (/= (length verts) 4) (not (bspkg-poly-closed-p ent)))
    nil
    (progn
      (setq minx (car (car verts))
            maxx (car (car verts))
            miny (cadr (car verts))
            maxy (cadr (car verts)))
      (foreach pt (cdr verts)
        (setq minx (min minx (car pt))
              maxx (max maxx (car pt))
              miny (min miny (cadr pt))
              maxy (max maxy (cadr pt))))
      (setq ok T)
      (foreach pt verts
        (if (not (or (and (equal (car pt) minx tol) (equal (cadr pt) miny tol))
                     (and (equal (car pt) maxx tol) (equal (cadr pt) miny tol))
                     (and (equal (car pt) maxx tol) (equal (cadr pt) maxy tol))
                     (and (equal (car pt) minx tol) (equal (cadr pt) maxy tol))))
          (setq ok nil)))
      (if (or (not ok) (< (- maxx minx) 10.0) (< (- maxy miny) 10.0))
        nil
        (list
          (cons "handle" (cdr (assoc 5 (entget ent))))
          (cons "layer" layer)
          (cons "entity" ent)
          (cons "min_x" minx)
          (cons "min_y" miny)
          (cons "max_x" maxx)
          (cons "max_y" maxy)
          (cons "width" (- maxx minx))
          (cons "height" (- maxy miny))
          (cons "center_x" (/ (+ minx maxx) 2.0))
          (cons "center_y" (/ (+ miny maxy) 2.0))
          (cons "rotated" nil))))))

(defun bspkg-layer-member-p (layer layers / found)
  (setq found nil)
  (foreach item layers
    (if (= (strcase layer) (strcase item))
      (setq found T)))
  found)

(defun bspkg-scan-rectangles (cfg / ss i ent data layer out rect)
  (setq out '())
  (setq ss (ssget "_X" '((410 . "Model") (0 . "LWPOLYLINE,POLYLINE"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i) data (entget ent) layer (cdr (assoc 8 data)))
        (if (bspkg-layer-member-p layer (bspkg-assoc-get "sheet_rectangle_layers" cfg))
          (progn
            (setq rect (bspkg-rectangle-record ent layer))
            (if rect
              (setq out (append out (list rect))))))
        (setq i (1+ i)))))
  out)

(defun bspkg-text-value (ent / obj raw)
  (setq obj (vlax-ename->vla-object ent))
  (cond
    ((= (cdr (assoc 0 (entget ent))) "TEXT") (vla-get-TextString obj))
    ((= (cdr (assoc 0 (entget ent))) "MTEXT") (vla-get-TextString obj))
    (T "")))

(defun bspkg-point-of-entity (ent / data typ obj)
  (setq data (entget ent) typ (cdr (assoc 0 data)))
  (cond
    ((member typ '("TEXT" "MTEXT" "INSERT")) (cdr (assoc 10 data)))
    (T nil)))

(defun bspkg-digit-groups (text / upper groups cur ch i)
  (setq upper (strcase (bspkg-normalize-space text)) groups '() cur "" i 1)
  (while (<= i (strlen upper))
    (setq ch (substr upper i 1))
    (if (wcmatch ch "#")
      (setq cur (strcat cur ch))
      (if (/= cur "")
        (progn
          (setq groups (append groups (list cur)))
          (setq cur ""))))
    (setq i (1+ i)))
  (if (/= cur "") (setq groups (append groups (list cur))))
  groups)

(defun bspkg-parse-sheet-number (text / upper groups)
  (setq upper (strcase (bspkg-normalize-space text)))
  (if (or (= upper "") (vl-string-search "/" upper) (vl-string-search " OF " upper))
    nil
    (progn
      (setq groups (bspkg-digit-groups upper))
      (if (/= (length groups) 1)
        nil
        (atoi (car groups))))))

(defun bspkg-block-number-candidate (ent / obj attrs values attr parsed unique pt)
  (setq obj (vlax-ename->vla-object ent) values '())
  (if (and (= :vlax-true (vla-get-HasAttributes obj))
           (not (vl-catch-all-error-p (setq attrs (vl-catch-all-apply 'vlax-invoke (list obj 'GetAttributes))))))
    (progn
      (vlax-for attr attrs
        (setq parsed (bspkg-parse-sheet-number (vla-get-TextString attr)))
        (if parsed
          (setq values (append values (list parsed)))))
      (setq unique '())
      (foreach item values
        (if (not (member item unique))
          (setq unique (append unique (list item)))))
      (if (= (length unique) 1)
        (progn
          (setq pt (bspkg-point-of-entity ent))
          (list
            (cons "handle" (cdr (assoc 5 (entget ent))))
            (cons "entity_type" "INSERT")
            (cons "text" (itoa (car unique)))
            (cons "sheet_number" (car unique))
            (cons "x" (car pt))
            (cons "y" (cadr pt))
            (cons "entity" ent)))
        nil))
    nil))

(defun bspkg-scan-number-candidates (cfg / ss i ent data typ layer text parsed pt out cand)
  (setq out '())
  (setq ss
    (ssget "_X"
      (list
        (cons 410 "Model")
        (cons 8 (bspkg-assoc-get "number_layer" cfg))
        '(-4 . "<OR")
        '(0 . "TEXT")
        '(0 . "MTEXT")
        '(0 . "INSERT")
        '(-4 . "OR>"))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i) data (entget ent) typ (cdr (assoc 0 data)))
        (cond
          ((member typ '("TEXT" "MTEXT"))
           (setq text (bspkg-text-value ent))
           (setq parsed (bspkg-parse-sheet-number text))
           (setq pt (bspkg-point-of-entity ent))
           (if (and parsed pt)
             (setq out
               (append out
                 (list
                   (list
                     (cons "handle" (cdr (assoc 5 data)))
                     (cons "entity_type" typ)
                     (cons "text" text)
                     (cons "sheet_number" parsed)
                     (cons "x" (car pt))
                     (cons "y" (cadr pt))
                     (cons "entity" ent)))))))
          ((= typ "INSERT")
           (setq cand (bspkg-block-number-candidate ent))
           (if cand (setq out (append out (list cand))))))
        (setq i (1+ i)))))
  out)

(defun bspkg-point-in-rect-p (x y rect / )
  (and (<= (bspkg-assoc-get "min_x" rect) x (bspkg-assoc-get "max_x" rect))
       (<= (bspkg-assoc-get "min_y" rect) y (bspkg-assoc-get "max_y" rect))))

(defun bspkg-rects-containing-point (x y rects / out)
  (setq out '())
  (foreach rect rects
    (if (bspkg-point-in-rect-p x y rect)
      (setq out (append out (list rect)))))
  out)

(defun bspkg-sort-sheets (sheets / )
  (vl-sort sheets '(lambda (a b) (< (bspkg-assoc-get "sheet_number" a) (bspkg-assoc-get "sheet_number" b)))))

(defun bspkg-sheet-index (cfg / rects nums errors warnings byrect seennum cand contains rects-hit rect rectkey existing sheetnum sheets expected startnum endnum n missing)
  (setq rects (bspkg-scan-rectangles cfg))
  (setq nums (bspkg-scan-number-candidates cfg))
  (setq errors '() warnings '() byrect '() seennum '() sheets '())
  (foreach rect rects
    (setq byrect (append byrect (list (cons (bspkg-assoc-get "handle" rect) '())))))
  (foreach cand nums
    (setq sheetnum (bspkg-assoc-get "sheet_number" cand))
    (setq contains (bspkg-rects-containing-point (bspkg-assoc-get "x" cand) (bspkg-assoc-get "y" cand) rects))
    (cond
      ((= (length contains) 0)
       (setq errors (append errors (list (strcat "Number " (itoa sheetnum) " (" (bspkg-assoc-get "handle" cand) ") is outside every sheet rectangle.")))))
      ((> (length contains) 1)
       (setq errors (append errors (list (strcat "Number " (itoa sheetnum) " (" (bspkg-assoc-get "handle" cand) ") falls inside multiple sheet rectangles.")))))
      ((assoc sheetnum seennum)
       (setq errors
         (append errors
           (list
             (strcat "Duplicate sheet number " (itoa sheetnum) " on "
                     (cdr (assoc sheetnum seennum)) " and " (bspkg-assoc-get "handle" cand) ".")))))
      (T
       (setq seennum (append seennum (list (cons sheetnum (bspkg-assoc-get "handle" cand)))))
       (setq rect (car contains))
       (setq rectkey (bspkg-assoc-get "handle" rect))
       (setq byrect (subst (cons rectkey (append (cdr (assoc rectkey byrect)) (list cand))) (assoc rectkey byrect) byrect)))))
  (foreach rect rects
    (setq rectkey (bspkg-assoc-get "handle" rect))
    (setq rects-hit (cdr (assoc rectkey byrect)))
    (cond
      ((= (length rects-hit) 0)
       (setq errors (append errors (list (strcat "Rectangle " rectkey " has no manual BORDER number.")))))
      ((> (length rects-hit) 1)
       (setq errors (append errors (list (strcat "Rectangle " rectkey " has multiple manual numbers.")))))
      (T
       (setq cand (car rects-hit))
       (setq sheets
         (append sheets
           (list
             (list
               (cons "sheet_number" (bspkg-assoc-get "sheet_number" cand))
               (cons "rectangle_handle" rectkey)
               (cons "rectangle_layer" (bspkg-assoc-get "layer" rect))
               (cons "number_handle" (bspkg-assoc-get "handle" cand))
               (cons "number_entity_type" (bspkg-assoc-get "entity_type" cand))
               (cons "number_text" (bspkg-assoc-get "text" cand))
               (cons "confidence" "HIGH")
               (cons "min_x" (bspkg-assoc-get "min_x" rect))
               (cons "min_y" (bspkg-assoc-get "min_y" rect))
               (cons "max_x" (bspkg-assoc-get "max_x" rect))
               (cons "max_y" (bspkg-assoc-get "max_y" rect))
               (cons "center_x" (bspkg-assoc-get "center_x" rect))
               (cons "center_y" (bspkg-assoc-get "center_y" rect))
               (cons "width" (bspkg-assoc-get "width" rect))
               (cons "height" (bspkg-assoc-get "height" rect)))))))))
  (setq sheets (bspkg-sort-sheets sheets))
  (if (and sheets (not (bspkg-assoc-get "allow_sheet_number_gaps" cfg)))
    (progn
      (setq startnum (bspkg-assoc-get "sheet_number" (car sheets)))
      (setq endnum (bspkg-assoc-get "sheet_number" (car (last sheets))))
      (setq n startnum missing '())
      (while (<= n endnum)
        (if (not (vl-some '(lambda (sheet) (= (bspkg-assoc-get "sheet_number" sheet) n)) sheets))
          (setq missing (append missing (list (itoa n)))))
        (setq n (1+ n)))
      (if missing
        (setq errors (append errors (list (strcat "Missing sheet numbers: " (apply 'strcat (cons (car missing) (mapcar '(lambda (s) (strcat ", " s)) (cdr missing)))) ".")))))))
  (list
    (cons "rectangles" rects)
    (cons "numbers" nums)
    (cons "sheets" sheets)
    (cons "errors" errors)
    (cons "warnings" warnings)))

(defun bspkg-layout-names ( / doc layouts out)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layouts (vla-get-Layouts doc) out '())
  (vlax-for layout layouts
    (if (/= (strcase (vla-get-Name layout)) "MODEL")
      (setq out (append out (list (vla-get-Name layout))))))
  out)

(defun bspkg-layout-object (name / doc layouts item)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layouts (vla-get-Layouts doc))
  (setq item (vl-catch-all-apply 'vla-Item (list layouts name)))
  (if (vl-catch-all-error-p item) nil item))

(defun bspkg-largest-main-viewport (layout-name / layout block obj candidates num area width height best second diff)
  (setq layout (bspkg-layout-object layout-name))
  (if (not layout)
    nil
    (progn
      (setq block (vla-get-Block layout) candidates '())
      (vlax-for obj block
        (if (= (strcase (vla-get-ObjectName obj)) "ACDBVIEWPORT")
          (progn
            (setq num (vl-catch-all-apply 'vla-get-Number (list obj)))
            (if (or (vl-catch-all-error-p num) (/= num 1))
              (progn
                (setq width (vla-get-Width obj)
                      height (vla-get-Height obj)
                      area (* width height))
                (setq candidates
                  (append candidates
                    (list
                      (list
                        (cons "object" obj)
                        (cons "handle" (vla-get-Handle obj))
                        (cons "width" width)
                        (cons "height" height)
                        (cons "area" area))))))))))
      (if (= (length candidates) 0)
        nil
        (progn
          (setq candidates (vl-sort candidates '(lambda (a b) (> (bspkg-assoc-get "area" a) (bspkg-assoc-get "area" b)))))
          (setq best (car candidates) second (cadr candidates))
          (if (and second (> (bspkg-assoc-get "area" second) (* (bspkg-assoc-get "area" best) 0.90)))
            nil
            best))))))

(defun bspkg-sheet-map-layout-p (layout-name cfg / hit)
  (setq hit nil)
  (foreach item (bspkg-assoc-get "sheet_map_layouts" cfg)
    (if (= (strcase layout-name) (strcase item))
      (setq hit T)))
  hit)

(defun bspkg-title-page-values (sheet-number total cfg / slots first-page max-pages section index remaining planpages)
  (if (not (bspkg-assoc-get "sectioning_enabled" cfg))
    (list (cons "sheet_value" sheet-number) (cons "total_value" total))
    (progn
      (setq slots (bspkg-assoc-get "plan_slots_per_full_section" cfg))
      (setq first-page (bspkg-assoc-get "first_plan_page_in_section" cfg))
      (setq max-pages (bspkg-assoc-get "max_pages_per_permit" cfg))
      (setq section (+ 1 (fix (/ (- sheet-number 1) slots))))
      (setq index (+ 1 (rem (- sheet-number 1) slots)))
      (setq remaining (max 0 (- total (* (- section 1) slots))))
      (setq planpages (min slots remaining))
      (list
        (cons "sheet_value" (+ first-page index -1))
        (cons "total_value" (min max-pages (+ first-page planpages -1)))))))

(defun bspkg-wildcard-match-p (value patterns / hit)
  (setq hit nil)
  (foreach pattern patterns
    (if (wcmatch (strcase value) (strcase pattern))
      (setq hit T)))
  hit)

(defun bspkg-update-titleblocks (layout-name sheet-number total cfg / layout block obj updated values attrs tag)
  (setq updated 0)
  (if (not (bspkg-assoc-get "titleblock_update_enabled" cfg))
    0
    (progn
      (setq layout (bspkg-layout-object layout-name))
      (setq block (if layout (vla-get-Block layout) nil))
      (setq values (bspkg-title-page-values sheet-number total cfg))
      (if block
        (vlax-for obj block
          (if (and (= (strcase (vla-get-ObjectName obj)) "ACDBBLOCKREFERENCE")
                   (bspkg-wildcard-match-p (vla-get-EffectiveName obj) (bspkg-assoc-get "titleblock_block_name_patterns" cfg))
                   (= :vlax-true (vla-get-HasAttributes obj)))
            (progn
              (setq attrs (vlax-invoke obj 'GetAttributes))
              (vlax-for attr attrs
                (setq tag (strcase (vla-get-TagString attr)))
                (cond
                  ((member tag (mapcar 'strcase (bspkg-assoc-get "titleblock_sheet_attribute_tags" cfg)))
                   (vla-put-TextString attr (itoa (bspkg-assoc-get "sheet_value" values)))
                   (setq updated (1+ updated)))
                  ((member tag (mapcar 'strcase (bspkg-assoc-get "titleblock_total_attribute_tags" cfg)))
                   (vla-put-TextString attr (itoa (bspkg-assoc-get "total_value" values)))
                   (setq updated (1+ updated))))))))))
      updated)))

(defun bspkg-copy-layout (template-layout new-layout / result)
  (setq result (vl-catch-all-apply 'command-s (list "_.-LAYOUT" "_Copy" template-layout new-layout)))
  (not (vl-catch-all-error-p result)))

(defun bspkg-layout-taborder-sort (layout-name / value)
  (if (numberp (distof layout-name 2))
    (distof layout-name 2)
    1000000.0))

(defun bspkg-reorder-layouts ( / names sorted order layout)
  (setq names (bspkg-layout-names))
  (setq sorted (vl-sort names '(lambda (a b) (< (bspkg-layout-taborder-sort a) (bspkg-layout-taborder-sort b)))))
  (setq order 1)
  (foreach name sorted
    (setq layout (bspkg-layout-object name))
    (if layout
      (vl-catch-all-apply 'vla-put-TabOrder (list layout order)))
    (setq order (1+ order))))

(defun bspkg-activate-layout (layout-name / doc layout)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layout (bspkg-layout-object layout-name))
  (if layout
    (progn
      (vla-put-ActiveLayout doc layout)
      (setvar "CTAB" layout-name)
      T)
    nil))

(defun bspkg-set-viewport-view (layout-name viewport sheet cfg / doc vpobj minx miny maxx maxy pad ok)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq vpobj (bspkg-assoc-get "object" viewport))
  (setq pad (bspkg-assoc-get "viewport_padding_ft" cfg))
  (setq minx (- (bspkg-assoc-get "min_x" sheet) pad))
  (setq miny (- (bspkg-assoc-get "min_y" sheet) pad))
  (setq maxx (+ (bspkg-assoc-get "max_x" sheet) pad))
  (setq maxy (+ (bspkg-assoc-get "max_y" sheet) pad))
  (if (not (bspkg-activate-layout layout-name))
    nil
    (progn
      (vl-catch-all-apply 'vla-put-DisplayLocked (list vpobj :vlax-false))
      (vl-catch-all-apply 'vla-put-MSpace (list doc :vlax-false))
      (vl-catch-all-apply 'vla-put-ActivePViewport (list doc vpobj))
      (vl-catch-all-apply 'vla-put-MSpace (list doc :vlax-true))
      (setq ok (not (vl-catch-all-error-p (vl-catch-all-apply 'command-s (list "_.ZOOM" "_W" (list minx miny) (list maxx maxy))))))
      (vl-catch-all-apply 'vla-put-MSpace (list doc :vlax-false))
      (vl-catch-all-apply 'vla-put-DisplayLocked (list vpobj :vlax-true))
      ok)))

(defun bspkg-freeze-border-in-viewport (layout-name viewport cfg / doc vpobj res)
  (if (or (not (bspkg-assoc-get "freeze_border_in_plan_viewports" cfg))
          (bspkg-sheet-map-layout-p layout-name cfg))
    T
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (setq vpobj (bspkg-assoc-get "object" viewport))
      (if (not (bspkg-activate-layout layout-name))
        nil
        (progn
          (vl-catch-all-apply 'vla-put-MSpace (list doc :vlax-false))
          (vl-catch-all-apply 'vla-put-ActivePViewport (list doc vpobj))
          (vl-catch-all-apply 'vla-put-MSpace (list doc :vlax-true))
          (setq res (vl-catch-all-apply 'command-s (list "_.-VPLAYER" "_Freeze" (bspkg-assoc-get "number_layer" cfg) "_Current" "")))
          (vl-catch-all-apply 'vla-put-MSpace (list doc :vlax-false))
          (not (vl-catch-all-error-p res)))))))

(defun bspkg-python-report (mode input-json out-dir / script cfg log cmd sh rc)
  (setq script (bspkg-python-script-path))
  (setq cfg (bspkg-config-path))
  (setq log (strcat out-dir "\\" mode ".log"))
  (if (not (findfile script))
    nil
    (progn
      (setq sh (vlax-create-object "WScript.Shell"))
      (setq cmd
        (strcat "cmd.exe /c py -3 "
                (bspkg-q script) " " mode
                " --input " (bspkg-q input-json)
                " --config " (bspkg-q cfg)
                " --out-dir " (bspkg-q out-dir)
                " > " (bspkg-q log) " 2>&1"))
      (setq rc (vlax-invoke sh 'Run cmd 0 :vlax-true))
      (if (/= rc 0)
        (progn
          (setq cmd
            (strcat "cmd.exe /c python "
                    (bspkg-q script) " " mode
                    " --input " (bspkg-q input-json)
                    " --config " (bspkg-q cfg)
                    " --out-dir " (bspkg-q out-dir)
                    " > " (bspkg-q log) " 2>&1"))
          (setq rc (vlax-invoke sh 'Run cmd 0 :vlax-true))))
      (vlax-release-object sh)
      (= rc 0))))

(defun bspkg-write-sheet-index-json (path payload / handle first errors warnings sheets source cfg)
  (setq handle (open path "w"))
  (if handle
    (progn
      (setq source (bspkg-current-dwg-path))
      (setq cfg (bspkg-load-config))
      (setq errors (bspkg-assoc-get "errors" payload))
      (setq warnings (bspkg-assoc-get "warnings" payload))
      (setq sheets (bspkg-assoc-get "sheets" payload))
      (write-line "{" handle)
      (write-line (strcat "  \"source_dwg\": " (bspkg-json-quote source) ",") handle)
      (write-line (strcat "  \"plan_template_layout\": " (bspkg-json-quote (bspkg-assoc-get "plan_template_layout" cfg)) ",") handle)
      (write-line "  \"errors\": [" handle)
      (setq first T)
      (foreach item errors
        (write-line (strcat "    " (if first "" ",") (bspkg-json-quote item)) handle)
        (setq first nil))
      (write-line "  ]," handle)
      (write-line "  \"warnings\": [" handle)
      (setq first T)
      (foreach item warnings
        (write-line (strcat "    " (if first "" ",") (bspkg-json-quote item)) handle)
        (setq first nil))
      (write-line "  ]," handle)
      (write-line "  \"sheets\": [" handle)
      (setq first T)
      (foreach sheet sheets
        (if (not first) (write-line "    ," handle))
        (write-line "    {" handle)
        (write-line (strcat "      \"sheet_number\": " (itoa (bspkg-assoc-get "sheet_number" sheet)) ",") handle)
        (write-line (strcat "      \"rectangle_handle\": " (bspkg-json-quote (bspkg-assoc-get "rectangle_handle" sheet)) ",") handle)
        (write-line (strcat "      \"rectangle_layer\": " (bspkg-json-quote (bspkg-assoc-get "rectangle_layer" sheet)) ",") handle)
        (write-line (strcat "      \"number_handle\": " (bspkg-json-quote (bspkg-assoc-get "number_handle" sheet)) ",") handle)
        (write-line (strcat "      \"number_entity_type\": " (bspkg-json-quote (bspkg-assoc-get "number_entity_type" sheet)) ",") handle)
        (write-line (strcat "      \"number_text\": " (bspkg-json-quote (bspkg-assoc-get "number_text" sheet)) ",") handle)
        (write-line (strcat "      \"confidence\": " (bspkg-json-quote (bspkg-assoc-get "confidence" sheet)) ",") handle)
        (write-line (strcat "      \"bbox\": {\"min_x\": " (rtos (bspkg-assoc-get "min_x" sheet) 2 6)
                            ", \"min_y\": " (rtos (bspkg-assoc-get "min_y" sheet) 2 6)
                            ", \"max_x\": " (rtos (bspkg-assoc-get "max_x" sheet) 2 6)
                            ", \"max_y\": " (rtos (bspkg-assoc-get "max_y" sheet) 2 6) "},") handle)
        (write-line (strcat "      \"center\": {\"x\": " (rtos (bspkg-assoc-get "center_x" sheet) 2 6)
                            ", \"y\": " (rtos (bspkg-assoc-get "center_y" sheet) 2 6) "},") handle)
        (write-line (strcat "      \"width\": " (rtos (bspkg-assoc-get "width" sheet) 2 6) ",") handle)
        (write-line (strcat "      \"height\": " (rtos (bspkg-assoc-get "height" sheet) 2 6)) handle)
        (write-line "    }" handle)
        (setq first nil))
      (write-line "  ]" handle)
      (write-line "}" handle)
      (close handle)
      T)
    nil))

(defun bspkg-write-layout-plan-json (path layout-actions / handle first)
  (setq handle (open path "w"))
  (if handle
    (progn
      (write-line "{" handle)
      (write-line "  \"layout_actions\": [" handle)
      (setq first T)
      (foreach action layout-actions
        (if (not first) (write-line "    ," handle))
        (write-line "    {" handle)
        (write-line (strcat "      \"sheet_number\": " (itoa (bspkg-assoc-get "sheet_number" action)) ",") handle)
        (write-line (strcat "      \"layout_name\": " (bspkg-json-quote (bspkg-assoc-get "layout_name" action)) ",") handle)
        (write-line (strcat "      \"action\": " (bspkg-json-quote (bspkg-assoc-get "action" action)) ",") handle)
        (write-line (strcat "      \"viewport_handle\": " (bspkg-json-quote (or (bspkg-assoc-get "viewport_handle" action) ""))) handle)
        (write-line "    }" handle)
        (setq first nil))
      (write-line "  ]" handle)
      (write-line "}" handle)
      (close handle)
      T)
    nil))

(defun bspkg-write-build-json (path build-report / handle first)
  (setq handle (open path "w"))
  (if handle
    (progn
      (write-line "{" handle)
      (write-line (strcat "  \"source_dwg\": " (bspkg-json-quote (bspkg-assoc-get "source_dwg" build-report)) ",") handle)
      (write-line (strcat "  \"output_dwg\": " (bspkg-json-quote (bspkg-assoc-get "output_dwg" build-report)) ",") handle)
      (write-line (strcat "  \"plan_template_layout\": " (bspkg-json-quote (bspkg-assoc-get "plan_template_layout" build-report)) ",") handle)
      (write-line (strcat "  \"dry_run\": " (bspkg-json-bool (bspkg-assoc-get "dry_run" build-report)) ",") handle)
      (write-line (strcat "  \"sheet_count\": " (itoa (bspkg-assoc-get "sheet_count" build-report)) ",") handle)
      (write-line (strcat "  \"created_layout_count\": " (itoa (bspkg-assoc-get "created_layout_count" build-report)) ",") handle)
      (write-line (strcat "  \"updated_viewport_count\": " (itoa (bspkg-assoc-get "updated_viewport_count" build-report)) ",") handle)
      (write-line (strcat "  \"border_freeze_attempted\": " (bspkg-json-bool (bspkg-assoc-get "border_freeze_attempted" build-report)) ",") handle)
      (write-line (strcat "  \"titleblock_update_attempted\": " (bspkg-json-bool (bspkg-assoc-get "titleblock_update_attempted" build-report)) ",") handle)
      (write-line "  \"existing_layouts\": [" handle)
      (setq first T)
      (foreach name (bspkg-assoc-get "existing_layouts" build-report)
        (write-line (strcat "    " (if first "" ",") (bspkg-json-quote name)) handle)
        (setq first nil))
      (write-line "  ]," handle)
      (write-line "  \"errors\": [" handle)
      (setq first T)
      (foreach item (bspkg-assoc-get "errors" build-report)
        (write-line (strcat "    " (if first "" ",") (bspkg-json-quote item)) handle)
        (setq first nil))
      (write-line "  ]," handle)
      (write-line "  \"warnings\": [" handle)
      (setq first T)
      (foreach item (bspkg-assoc-get "warnings" build-report)
        (write-line (strcat "    " (if first "" ",") (bspkg-json-quote item)) handle)
        (setq first nil))
      (write-line "  ]," handle)
      (write-line "  \"layout_actions\": [" handle)
      (setq first T)
      (foreach action (bspkg-assoc-get "layout_actions" build-report)
        (if (not first) (write-line "    ," handle))
        (write-line "    {" handle)
        (write-line (strcat "      \"sheet_number\": " (itoa (bspkg-assoc-get "sheet_number" action)) ",") handle)
        (write-line (strcat "      \"layout_name\": " (bspkg-json-quote (bspkg-assoc-get "layout_name" action)) ",") handle)
        (write-line (strcat "      \"action\": " (bspkg-json-quote (bspkg-assoc-get "action" action)) ",") handle)
        (write-line (strcat "      \"viewport_handle\": " (bspkg-json-quote (or (bspkg-assoc-get "viewport_handle" action) ""))) handle)
        (write-line "    }" handle)
        (setq first nil))
      (write-line "  ]" handle)
      (write-line "}" handle)
      (close handle)
      T)
    nil))

(defun bspkg-required-layout-actions (index cfg / existing out action name)
  (setq existing (bspkg-layout-names) out '())
  (foreach sheet (bspkg-assoc-get "sheets" index)
    (setq name (itoa (bspkg-assoc-get "sheet_number" sheet)))
    (setq out
      (append out
        (list
          (list
            (cons "sheet_number" (bspkg-assoc-get "sheet_number" sheet))
            (cons "layout_name" name)
            (cons "action" (if (member name existing) "keep" "copy_template")))))))
  out)

(defun bspkg-build-packaged-layouts (index cfg dry-run / source output reports template existing errors warnings actions created updated freeze-ok title-updates layout-name viewport sheet result updated-actions)
  (setq source (bspkg-current-dwg-path))
  (setq output (if dry-run source (bspkg-output-dwg-path cfg)))
  (setq reports (bspkg-ensure-dir (bspkg-reports-dir output)))
  (setq template (bspkg-assoc-get "plan_template_layout" cfg))
  (setq existing (bspkg-layout-names))
  (setq errors (append '() (bspkg-assoc-get "errors" index)))
  (setq warnings (append '() (bspkg-assoc-get "warnings" index)))
  (setq actions (bspkg-required-layout-actions index cfg))
  (if (not (member template existing))
    (setq errors (append errors (list (strcat "Template layout " template " is missing.")))))
  (if (not (bspkg-largest-main-viewport template))
    (setq errors (append errors (list (strcat "Template layout " template " has no usable main viewport.")))))
  (if (and (not dry-run) (= (getvar "DWGTITLED") 0))
    (setq errors (append errors (list "Current DWG is unsaved. Save it before packaging."))))
  (if (and (not dry-run) (not (bspkg-local-drive-p (getvar "DWGPREFIX"))))
    (setq errors (append errors (list "Current DWG is on a non-local path. Package from a Windows local drive only."))))
  (if errors
    (list
      (cons "source_dwg" source)
      (cons "output_dwg" output)
      (cons "reports_dir" reports)
      (cons "plan_template_layout" template)
      (cons "dry_run" dry-run)
      (cons "sheet_count" (length (bspkg-assoc-get "sheets" index)))
      (cons "created_layout_count" 0)
      (cons "updated_viewport_count" 0)
      (cons "border_freeze_attempted" (bspkg-assoc-get "freeze_border_in_plan_viewports" cfg))
      (cons "titleblock_update_attempted" (bspkg-assoc-get "titleblock_update_enabled" cfg))
      (cons "existing_layouts" existing)
      (cons "errors" errors)
      (cons "warnings" warnings)
      (cons "layout_actions" actions))
    (progn
      (if (and (not dry-run) (/= (getvar "DBMOD") 0))
        (if (= (getkword "\n[BSPACKAGEBUILD] Current DWG has unsaved changes. Save before packaging? [Yes/No] <Yes>: ") "No")
          (setq errors (append errors (list "Packaging aborted because the source DWG was not saved first.")))
          (command-s "_.QSAVE")))
      (if errors
        (list
          (cons "source_dwg" source)
          (cons "output_dwg" output)
          (cons "reports_dir" reports)
          (cons "plan_template_layout" template)
          (cons "dry_run" dry-run)
          (cons "sheet_count" (length (bspkg-assoc-get "sheets" index)))
          (cons "created_layout_count" 0)
          (cons "updated_viewport_count" 0)
          (cons "border_freeze_attempted" (bspkg-assoc-get "freeze_border_in_plan_viewports" cfg))
          (cons "titleblock_update_attempted" (bspkg-assoc-get "titleblock_update_enabled" cfg))
          (cons "existing_layouts" existing)
          (cons "errors" errors)
          (cons "warnings" warnings)
          (cons "layout_actions" actions))
        (progn
          (if (not dry-run)
            (command-s "_.SAVEAS" "" output))
          (setq created 0 updated 0 title-updates 0)
          (setq updated-actions '())
          (foreach action actions
            (setq layout-name (bspkg-assoc-get "layout_name" action))
            (if (= (bspkg-assoc-get "action" action) "copy_template")
              (if (bspkg-copy-layout template layout-name)
                (setq created (1+ created))
                (setq errors (append errors (list (strcat "Failed to copy template layout " template " to " layout-name "."))))))
            (if (not errors)
              (progn
                (setq sheet
                  (car
                    (vl-remove-if-not
                      '(lambda (item) (= (bspkg-assoc-get "sheet_number" item) (bspkg-assoc-get "sheet_number" action)))
                      (bspkg-assoc-get "sheets" index))))
                (setq viewport (bspkg-largest-main-viewport layout-name))
                (if (not viewport)
                  (setq errors (append errors (list (strcat "Layout " layout-name " has no usable main viewport."))))
                  (progn
                    (if (assoc "viewport_handle" action)
                      (setq action (subst (cons "viewport_handle" (bspkg-assoc-get "handle" viewport)) (assoc "viewport_handle" action) action))
                      (setq action (append action (list (cons "viewport_handle" (bspkg-assoc-get "handle" viewport))))))
                    (if (or dry-run (bspkg-set-viewport-view layout-name viewport sheet cfg))
                      (progn
                        (setq updated (1+ updated))
                        (if (not dry-run)
                          (progn
                            (if (not (bspkg-freeze-border-in-viewport layout-name viewport cfg))
                              (setq warnings (append warnings (list (strcat "Could not confirm viewport-only BORDER freeze on layout " layout-name ".")))))
                            (setq title-updates (+ title-updates (bspkg-update-titleblocks layout-name (bspkg-assoc-get "sheet_number" sheet) (length (bspkg-assoc-get "sheets" index)) cfg)))))
                      (setq errors (append errors (list (strcat "Failed to set viewport for layout " layout-name "."))))))))
            (setq updated-actions (append updated-actions (list action))))
          (if (not errors)
            (bspkg-reorder-layouts))
          (list
            (cons "source_dwg" source)
            (cons "output_dwg" output)
            (cons "reports_dir" reports)
            (cons "plan_template_layout" template)
            (cons "dry_run" dry-run)
            (cons "sheet_count" (length (bspkg-assoc-get "sheets" index)))
            (cons "created_layout_count" created)
            (cons "updated_viewport_count" updated)
            (cons "border_freeze_attempted" (bspkg-assoc-get "freeze_border_in_plan_viewports" cfg))
            (cons "titleblock_update_attempted" (bspkg-assoc-get "titleblock_update_enabled" cfg))
            (cons "existing_layouts" existing)
            (cons "errors" errors)
            (cons "warnings" warnings)
            (cons "layout_actions" updated-actions))))))))

(defun bspkg-run-index-common ( / cfg index source output reports json-path)
  (setq cfg (bspkg-load-config))
  (setq index (bspkg-sheet-index cfg))
  (setq *bspkg-last-index* index)
  (setq output (bspkg-output-dwg-path cfg))
  (setq reports (bspkg-ensure-dir (bspkg-reports-dir output)))
  (setq json-path (strcat reports "\\sheet_index.json"))
  (bspkg-write-sheet-index-json json-path index)
  (if (not (bspkg-python-report "index-report" json-path reports))
    (princ "\n[BSPACKAGEINDEX] Python reporter was not available; JSON was still written."))
  (list
    (cons "config" cfg)
    (cons "index" index)
    (cons "reports_dir" reports)
    (cons "sheet_index_json" json-path)
    (cons "output_dwg" output)))

(defun c:BSPACKAGEINDEX ( / *error* env result index reports)
  (setq env (bspkg-save-env))
  (defun *error* (msg)
    (bspkg-restore-env env)
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort"))))
      (princ (strcat "\n[BSPACKAGEINDEX] Error: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BEGIN")
  (setq result (bspkg-run-index-common))
  (setq index (bspkg-assoc-get "index" result))
  (setq reports (bspkg-assoc-get "reports_dir" result))
  (command "_.UNDO" "_END")
  (bspkg-restore-env env)
  (princ (strcat "\n[BSPACKAGEINDEX] Sheets found: " (itoa (length (bspkg-assoc-get "sheets" index)))))
  (princ (strcat "\n[BSPACKAGEINDEX] Errors: " (itoa (length (bspkg-assoc-get "errors" index)))))
  (princ (strcat "\n[BSPACKAGEINDEX] Reports: " reports))
  (princ))

(defun c:BSPACKAGEBUILD ( / *error* env scan cfg mode dry-run build reports build-json layout-plan-json)
  (setq env (bspkg-save-env))
  (defun *error* (msg)
    (command "_.UNDO" "_END")
    (bspkg-restore-env env)
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort"))))
      (princ (strcat "\n[BSPACKAGEBUILD] Error: " msg)))
    (princ))
  (setvar "CMDECHO" 0)
  (princ "\n[BSPACKAGEBUILD] Make sure layout 2 is fully completed.")
  (princ "\n[BSPACKAGEBUILD] This command will create a packaged copy and duplicate layout 2 for missing plan sheets.")
  (setq cfg (bspkg-load-config))
  (initget "DryRun Apply")
  (setq mode (getkword "\n[BSPACKAGEBUILD] Mode [DryRun/Apply] <DryRun>: "))
  (setq dry-run (or (null mode) (= mode "DryRun")))
  (command "_.UNDO" "_BEGIN")
  (setq scan (bspkg-run-index-common))
  (setq build (bspkg-build-packaged-layouts (bspkg-assoc-get "index" scan) cfg dry-run))
  (setq reports (bspkg-assoc-get "reports_dir" build))
  (setq build-json (strcat reports "\\package_build_report.json"))
  (setq layout-plan-json (strcat reports "\\layout_plan.json"))
  (bspkg-write-layout-plan-json layout-plan-json (bspkg-assoc-get "layout_actions" build))
  (bspkg-write-build-json build-json build)
  (if (not (bspkg-python-report "build-report" build-json reports))
    (princ "\n[BSPACKAGEBUILD] Python build reporter was not available; JSON was still written."))
  (command "_.UNDO" "_END")
  (bspkg-restore-env env)
  (princ (strcat "\n[BSPACKAGEBUILD] Output DWG: " (bspkg-assoc-get "output_dwg" build)))
  (princ (strcat "\n[BSPACKAGEBUILD] Sheets found: " (itoa (bspkg-assoc-get "sheet_count" build))))
  (princ (strcat "\n[BSPACKAGEBUILD] Created layouts: " (itoa (bspkg-assoc-get "created_layout_count" build))))
  (princ (strcat "\n[BSPACKAGEBUILD] Updated viewports: " (itoa (bspkg-assoc-get "updated_viewport_count" build))))
  (princ (strcat "\n[BSPACKAGEBUILD] Errors: " (itoa (length (bspkg-assoc-get "errors" build)))))
  (princ (strcat "\n[BSPACKAGEBUILD] Reports: " reports))
  (princ))

(princ "\n[BSPACKAGE] Loaded. Commands: BSPACKAGEINDEX, BSPACKAGEBUILD.")
(princ)
