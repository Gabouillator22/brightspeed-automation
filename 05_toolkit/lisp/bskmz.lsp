;;; ============================================================
;;; BSKMZ — Import KMZ field data into AutoCAD
;;;
;;; Reads a KMZ (Google Earth) file produced by the field team and
;;; auto-draws every point and line on the correct Brightspeed layer.
;;;
;;;   Point Documents  -> INSERT block at converted XY
;;;   Line  Documents  -> LWPOLYLINE through every vertex
;;;
;;; Coordinate conversion: GPS (WGS84 lat/lon) -> NC State Plane
;;; NAD83 US Survey Foot (EPSG:2264 / "NC83F"). Lambert Conformal
;;; Conic 2SP, parameters baked in — no Map 3D API dependency.
;;;
;;; Companion file: bskmz.ps1 (unzip + KML parse + status sentinel)
;;; Depends on: *bs-toolkit-dir* set by bs_loader.lsp
;;; ============================================================

;; ---------- folder-name -> (kind layer block scale) map ----------
(setq *bskmz-map*
  '(
    ("HANDHOLE"    "BLOCK" "HANDHOLE"             "NDS_HH"          60.0)
    ("CO"          "BLOCK" "HANDHOLE"             "NDS_HH"          60.0)
    ("BORE"        "BLOCK" "BORE PIT"             "BORE PIT"        60.0)
    ("POLE"        "BLOCK" "Pole"                 "TELPOLE1262023"  60.0)
    ("UNDERGROUND" "PLINE" "Buried Fiber in Duct" nil               nil )
    ("BURIED"      "PLINE" "Buried Fiber in Duct" nil               nil )
    ("OVERLASH"    "PLINE" "E-LASH"               nil               nil )
    ("NEW STRAND/NEW BUILD" "PLINE" "AERIAL FIBER" nil              nil )
    ("NEW STRAND"  "PLINE" "AERIAL FIBER"         nil               nil )
    ("NEW BUILD"   "PLINE" "AERIAL FIBER"         nil               nil )
    ("AERIAL"      "PLINE" "AERIAL FIBER"         nil               nil )
    ("ELASH"       "PLINE" "E-LASH"               nil               nil )
    ("E-LASH"      "PLINE" "E-LASH"               nil               nil )
  )
)

;; ---------- string helpers ----------
(defun bskmz-contains (haystack needle / hi ni hlen nlen i found)
  (setq hi (strcase haystack) ni (strcase needle)
        hlen (strlen hi)      nlen (strlen ni)
        i 1                   found nil)
  (while (and (not found) (<= (+ i nlen -1) hlen))
    (if (= (substr hi i nlen) ni) (setq found T))
    (setq i (1+ i)))
  found)

(defun bskmz-split (s sep / lst cur i slen seplen)
  (setq lst '() cur "" i 1 slen (strlen s) seplen (strlen sep))
  (while (<= i slen)
    (if (and (<= (+ i seplen -1) slen) (= (substr s i seplen) sep))
      (progn (setq lst (cons cur lst) cur "" i (+ i seplen)))
      (progn (setq cur (strcat cur (substr s i 1)) i (1+ i)))))
  (reverse (cons cur lst)))

;; ---------- coordinate transform ----------
;; Lambert Conformal Conic 2SP forward, NAD83 NC US Survey Foot.
(defun bskmz-ll-to-ncsp (lat lon /
                         a e phi1 phi2 phi0 lambda0 FE FN
                         phi lambda m1 m2 tt t1 t2 t0 n F
                         rho rho0 theta x y mtoft)
  (setq a       6378137.0
        e       0.0818191910435
        phi1    (/ (* (+ 36.0 (/ 10.0 60.0)) pi) 180.0)
        phi2    (/ (* (+ 34.0 (/ 20.0 60.0)) pi) 180.0)
        phi0    (/ (* 33.75 pi) 180.0)
        lambda0 (/ (* -79.0 pi) 180.0)
        FE      609601.22
        FN      0.0
        phi     (/ (* lat pi) 180.0)
        lambda  (/ (* lon pi) 180.0))
  (setq m1 (/ (cos phi1) (sqrt (- 1.0 (* e e (sin phi1) (sin phi1)))))
        m2 (/ (cos phi2) (sqrt (- 1.0 (* e e (sin phi2) (sin phi2))))))
  (setq tt (/ (/ (sin (- (/ pi 4.0) (/ phi  2.0))) (cos (- (/ pi 4.0) (/ phi  2.0))))
              (expt (/ (- 1.0 (* e (sin phi )))  (+ 1.0 (* e (sin phi )))) (/ e 2.0)))
        t1 (/ (/ (sin (- (/ pi 4.0) (/ phi1 2.0))) (cos (- (/ pi 4.0) (/ phi1 2.0))))
              (expt (/ (- 1.0 (* e (sin phi1)))  (+ 1.0 (* e (sin phi1)))) (/ e 2.0)))
        t2 (/ (/ (sin (- (/ pi 4.0) (/ phi2 2.0))) (cos (- (/ pi 4.0) (/ phi2 2.0))))
              (expt (/ (- 1.0 (* e (sin phi2)))  (+ 1.0 (* e (sin phi2)))) (/ e 2.0)))
        t0 (/ (/ (sin (- (/ pi 4.0) (/ phi0 2.0))) (cos (- (/ pi 4.0) (/ phi0 2.0))))
              (expt (/ (- 1.0 (* e (sin phi0)))  (+ 1.0 (* e (sin phi0)))) (/ e 2.0))))
  (setq n     (/ (- (log m1) (log m2)) (- (log t1) (log t2)))
        F     (/ m1 (* n (expt t1 n)))
        rho   (* a F (expt tt n))
        rho0  (* a F (expt t0 n))
        theta (* n (- lambda lambda0))
        x     (+ FE (* rho (sin theta)))
        y     (+ FN (- rho0 (* rho (cos theta))))
        mtoft (/ 3937.0 1200.0))
  (list (* x mtoft) (* y mtoft)))

;; ---------- folder lookup ----------
(defun bskmz-lookup (doc-name / hit)
  (setq hit nil)
  (foreach m *bskmz-map*
    (if (and (not hit) (bskmz-contains doc-name (car m))) (setq hit m)))
  hit)

;; ---------- placement ----------
(defun bskmz-place-block (layer blkname scale x y / old-clayer)
  (bs-ensure-layer layer 7)
  (setq old-clayer (getvar "CLAYER"))
  (setvar "CLAYER" layer)
  (command "_.-INSERT" blkname (list x y 0.0) scale scale 0.0)
  (setvar "CLAYER" old-clayer))

(defun bskmz-place-pline (layer verts /)
  (bs-ensure-layer layer 7)
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
            '(100 . "AcDbPolyline") (cons 90 (length verts))
            '(70 . 0) '(43 . 0.0))
      (mapcar (function (lambda (v) (list 10 (car v) (cadr v)))) verts))))

;; ---------- pre-flight: which blocks does this KMZ need? ----------
(defun bskmz-required-blocks (records / needed rec doc-name rule blk)
  (setq needed '())
  (foreach rec records
    (if (= (car rec) 'POINT)
      (progn
        (setq doc-name (cadr rec))
        (setq rule (bskmz-lookup doc-name))
        (if (and rule (= (nth 1 rule) "BLOCK"))
          (progn
            (setq blk (nth 3 rule))
            (if (not (member blk needed)) (setq needed (cons blk needed))))))))
  needed)

(defun bskmz-missing-blocks (block-names / missing b)
  (setq missing '())
  (foreach b block-names
    (if (not (tblsearch "BLOCK" b))
      (setq missing (cons b missing))))
  missing)

;; ---------- intermediate-file parser ----------
;; Returns a list of records:
;;   (POINT  doc-name lon lat)
;;   (LINE   doc-name ((lon lat) (lon lat) ...))
(defun bskmz-read-data (path / f line parts records vparts vlist v ll)
  (setq records '())
  (setq f (open path "r"))
  (if (not f) nil
    (progn
      (while (setq line (read-line f))
        (setq parts (bskmz-split line "|"))
        (cond
          ((and (= (car parts) "P") (>= (length parts) 4))
           (setq records
             (cons (list 'POINT (nth 1 parts)
                         (atof (nth 2 parts)) (atof (nth 3 parts)))
                   records)))
          ((and (= (car parts) "L") (>= (length parts) 3))
           (setq vparts (bskmz-split (nth 2 parts) ";") vlist '())
           (foreach v vparts
             (setq ll (bskmz-split v ","))
             (if (= (length ll) 2)
               (setq vlist (cons (list (atof (car ll)) (atof (cadr ll))) vlist))))
           (setq vlist (reverse vlist))
           (if (>= (length vlist) 2)
             (setq records (cons (list 'LINE (nth 1 parts) vlist) records))))))
      (close f)
      (reverse records))))

;; ---------- PowerShell launcher ----------
;; KMZ path is written to a temp parameter file instead of embedded in the
;; command string — this avoids all quoting / encoding / space issues.
(defun bskmz-run-ps (psscript kmz outtxt / paramfile f cmd sh statusfile statustxt)
  ;; Write KMZ path to a temp file with no special characters in its own path
  (setq paramfile (strcat (getenv "TEMP") "\\bskmz_param.txt"))
  (setq f (open paramfile "w"))
  (if f (progn (write-line kmz f) (close f)))
  ;; Command line only passes safe temp-file paths — no user path embedded
  (setq cmd (strcat "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \""
                    psscript "\" -ParamFile \"" paramfile "\" -OutPath \"" outtxt "\""))
  (vl-load-com)
  (setq sh (vlax-create-object "WScript.Shell"))
  (vlax-invoke sh 'Run cmd 0 :vlax-true)
  (vlax-release-object sh)
  ;; read status sentinel
  (setq statusfile (strcat outtxt ".status") statustxt "")
  (if (findfile statusfile)
    (progn
      (setq f (open statusfile "r"))
      (if f (progn (setq statustxt (read-line f)) (close f)))))
  statustxt)

;; ---------- main command ----------
(defun c:BSKMZ ( / *error* kmz outtxt psscript status records
                   needed missing nPts nLns nSkip skipped rec
                   doc-name rule layer blk scale lon lat xy
                   verts xyverts v xy0 dist drawing-ext drawing-min drawing-max)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg) "*CANCEL*")
             (/= msg "Function cancelled")
             (not (wcmatch (strcase msg) "*QUIT*EXIT*")))
      (princ (strcat "\n[BSKMZ] ERROR: " msg)))
    (princ))

  (princ "\n[BSKMZ] Brightspeed KMZ importer")

  ;; --- 1. locate companion script via *bs-toolkit-dir* ---
  (if (not *bs-toolkit-dir*)
    (progn
      (princ "\n[BSKMZ] ERROR: *bs-toolkit-dir* not set. Reload bs_loader.lsp.")
      (exit)))
  (setq psscript (strcat *bs-toolkit-dir* "\\bskmz.ps1"))
  (if (not (findfile psscript))
    (progn
      (princ (strcat "\n[BSKMZ] ERROR: bskmz.ps1 missing at: " psscript))
      (exit)))

  ;; --- 2. pick KMZ ---
  (setq kmz (getfiled "Select Field KMZ" "" "kmz" 8))
  (if (not kmz)
    (progn (princ "\n[BSKMZ] Cancelled.") (exit)))

  ;; Normalize: forward slashes → backslashes (AutoCAD sometimes returns / on Windows)
  (setq kmz (vl-string-translate "/" "\\" kmz))
  ;; If relative path (no drive letter, no UNC), anchor to drawing directory
  (if (not (or (and (>= (strlen kmz) 3) (= (substr kmz 2 2) ":\\"))
               (= (substr kmz 1 2) "\\\\")))
    (setq kmz (strcat (vl-string-translate "/" "\\" (getvar "DWGPREFIX")) kmz)))
  ;; Verify file is reachable before handing off to PowerShell
  (if (not (findfile kmz))
    (progn
      (princ (strcat "\n[BSKMZ] ERROR: Cannot find KMZ at: " kmz))
      (princ "\n[BSKMZ]   Use the Browse button in the dialog — do not type the filename manually.")
      (exit)))
  (princ (strcat "\n[BSKMZ] KMZ path: " kmz))

  ;; --- 3. intermediate file paths ---
  (setq outtxt (strcat (getenv "TEMP") "\\bskmz_data.txt"))
  (if (findfile outtxt)                  (vl-file-delete outtxt))
  (if (findfile (strcat outtxt ".status")) (vl-file-delete (strcat outtxt ".status")))

  ;; --- 4. run PowerShell ---
  (princ "\n[BSKMZ] Extracting and parsing KMZ...")
  (setq status (bskmz-run-ps psscript kmz outtxt))
  (cond
    ((= status "")
     (princ "\n[BSKMZ] ERROR: PowerShell produced no status. Check that PowerShell is on PATH.")
     (exit))
    ((/= (substr status 1 2) "OK")
     (princ (strcat "\n[BSKMZ] " status))
     (exit)))
  (if (not (findfile outtxt))
    (progn
      (princ "\n[BSKMZ] ERROR: status OK but data file is missing.")
      (exit)))

  ;; --- 5. parse records ---
  (setq records (bskmz-read-data outtxt))
  (if (or (null records) (= (length records) 0))
    (progn
      (princ "\n[BSKMZ] KMZ has no usable points or lines.")
      (exit)))
  (princ (strcat "\n[BSKMZ] Parsed " (itoa (length records)) " feature(s) from KMZ."))

  ;; --- 6. pre-flight: required blocks ---
  (setq needed (bskmz-required-blocks records))
  (setq missing (bskmz-missing-blocks needed))
  (if missing
    (progn
      (princ "\n[BSKMZ] ABORT: The following block(s) are not defined in this drawing:")
      (foreach b missing (princ (strcat "\n          - " b)))
      (princ "\n[BSKMZ] Insert one of each by hand (any location) so the block")
      (princ "\n        definitions exist, then re-run BSKMZ.")
      (exit)))

  ;; --- 7. import inside one undo group ---
  (command "_.UNDO" "_BE")
  (setq nPts 0 nLns 0 nSkip 0 skipped '())
  (foreach rec records
    (cond
      ((= (car rec) 'POINT)
       (setq doc-name (cadr rec) lon (nth 2 rec) lat (nth 3 rec))
       (setq rule (bskmz-lookup doc-name))
       (if (and rule (= (nth 1 rule) "BLOCK"))
         (progn
           (setq layer (nth 2 rule) blk (nth 3 rule) scale (nth 4 rule))
           (setq xy (bskmz-ll-to-ncsp lat lon))
           (bskmz-place-block layer blk scale (car xy) (cadr xy))
           (setq nPts (1+ nPts)))
         (progn
           (setq nSkip (1+ nSkip))
           (if (not (member doc-name skipped)) (setq skipped (cons doc-name skipped))))))
      ((= (car rec) 'LINE)
       (setq doc-name (cadr rec) verts (nth 2 rec))
       (setq rule (bskmz-lookup doc-name))
       (if (and rule (= (nth 1 rule) "PLINE"))
         (progn
           (setq layer (nth 2 rule) xyverts '())
           (foreach v verts
             (setq xy0 (bskmz-ll-to-ncsp (cadr v) (car v)))
             (setq xyverts (cons xy0 xyverts)))
           (setq xyverts (reverse xyverts))
           (bskmz-place-pline layer xyverts)
           (setq nLns (1+ nLns)))
         (progn
           (setq nSkip (1+ nSkip))
           (if (not (member doc-name skipped)) (setq skipped (cons doc-name skipped))))))))
  (command "_.UNDO" "_E")

  ;; --- 8. report ---
  (princ "\n============================================================")
  (princ (strcat "\n[BSKMZ] Source: " kmz))
  (princ (strcat "\n[BSKMZ] Imported: " (itoa nPts) " block(s), "
                 (itoa nLns) " polyline(s)."))
  (if (> nSkip 0)
    (progn
      (princ (strcat "\n[BSKMZ] Skipped " (itoa nSkip)
                     " feature(s) from unmapped folders:"))
      (foreach n skipped (princ (strcat "\n        - " n)))))
  (princ "\n[BSKMZ] Tip: type ZOOM E to see all imported geometry.")
  (princ "\n        Undo with Ctrl+Z (one step undoes the whole import).")
  (princ "\n============================================================")
  (princ))
