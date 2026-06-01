;;; ============================================================
;;; BRIGHTSPEED TOOLKIT - Master Loader v2
;;;
;;; APPLOAD this file only — loads everything at once.
;;; All .lsp files must be in the same folder as this file.
;;;
;;; Load order:
;;;   1. bs_helpers.lsp  — shared math/entity helpers (MUST be first)
;;;   2. All command files in dependency order
;;; ============================================================

;; Capture the toolkit directory ONCE at load time. Every command file
;; can read *bs-toolkit-dir* later without re-running findfile (which
;; can return nil at command-time if the support path shifted, and even
;; at load-time under Map 3D's APPLOAD which does not always prepend
;; the file's folder to the search path).
;;
;; Discovery order:
;;   1. existing *bs-toolkit-dir* from this session
;;   2. findfile against this file's name
;;   3. findfile against a sibling file
;;   4. prompt for bs_loader.lsp or bs_helpers.lsp if AutoCAD cannot resolve it
(defun bs-norm-dir (dir / out)
  (if dir
    (progn
      (setq out (vl-string-translate "/" "\\" dir))
      (while (and (> (strlen out) 1) (= (substr out (strlen out) 1) "\\"))
        (setq out (substr out 1 (1- (strlen out)))))
      out)
    nil))

(defun bs-dir-has-toolkit-p (dir / d)
  (setq d (bs-norm-dir dir))
  (and d
       (findfile (strcat d "\\bs_loader.lsp"))
       (findfile (strcat d "\\bs_helpers.lsp"))))

(defun bs-find-toolkit-dir ( / probe try candidates picked)
  ;; Try every reasonable source for the folder path. If AutoCAD cannot
  ;; resolve the APPLOAD folder, ask for one known file and remember that
  ;; folder for the session.
  (setq candidates
    (list
      (if (and (boundp '*bs-toolkit-dir*) *bs-toolkit-dir*) *bs-toolkit-dir*)
      (if (findfile "bs_loader.lsp")  (vl-filename-directory (findfile "bs_loader.lsp")))
      (if (findfile "bs_helpers.lsp") (vl-filename-directory (findfile "bs_helpers.lsp")))
      (getvar "DWGPREFIX")))
  (setq probe nil)
  (foreach try candidates
    (if (and (not probe) (bs-dir-has-toolkit-p try))
      (setq probe (bs-norm-dir try))))
  (if (not probe)
    (progn
      (princ "\n[BRIGHTSPEED] Could not auto-detect the toolkit folder.")
      (princ "\n[BRIGHTSPEED] Pick bs_loader.lsp or bs_helpers.lsp from the same lisp folder...")
      (setq picked (getfiled "Locate Brightspeed lisp folder" "" "lsp" 0))
      (if picked
        (setq probe (bs-norm-dir (vl-filename-directory picked))))))
  (if (bs-dir-has-toolkit-p probe) probe nil))

(defun bs-path-list-contains-p (path-list dir / needle hay)
  (setq needle (strcat ";" (strcase (bs-norm-dir dir)) ";"))
  (setq hay (strcat ";" (strcase (vl-string-translate "/" "\\" path-list)) ";"))
  (if (vl-string-search needle hay) T nil))

(defun bs-add-to-support-path (dir / pref files cur)
  ;; Add dir to AutoCAD's live support path so findfile works for the session.
  (setq pref (vl-catch-all-apply 'vla-get-Preferences (list (vlax-get-acad-object))))
  (if (not (vl-catch-all-error-p pref))
    (progn
      (setq files (vl-catch-all-apply 'vla-get-Files (list pref)))
      (if (not (vl-catch-all-error-p files))
        (progn
          (setq cur (vl-catch-all-apply 'vla-get-SupportPath (list files)))
          (if (and (not (vl-catch-all-error-p cur))
                   (not (bs-path-list-contains-p cur dir)))
            (vl-catch-all-apply 'vla-put-SupportPath
              (list files (strcat cur ";" dir)))))))))

(defun bs-add-to-trusted-paths (dir / trusted new)
  ;; Some AutoCAD installs block LISP from untrusted folders. This adds the
  ;; toolkit folder for the current user profile when TRUSTEDPATHS is writable.
  (setq trusted (vl-catch-all-apply 'getvar (list "TRUSTEDPATHS")))
  (if (not (vl-catch-all-error-p trusted))
    (if (not (bs-path-list-contains-p trusted dir))
      (progn
        (setq new (if (= trusted "") dir (strcat trusted ";" dir)))
        (vl-catch-all-apply 'setvar (list "TRUSTEDPATHS" new))))))

(defun bs-required-files ( / )
  '("bs_helpers.lsp" "bsrow.lsp" "bsfillet_all.lsp" "bscallout.lsp"
    "bsaerial.lsp" "bsstation.lsp" "bsdrive.lsp" "bsworkarea.lsp"
    "bsminerdoc.lsp" "bsaudit.lsp" "bscleanup.lsp" "bsparcels.lsp"
    "bsparsnap.lsp" "bsrowdims.lsp" "bskmz.lsp" "bskmz.ps1"
    "bskmz_snap.lsp" "bssheets.lsp" "bssheet_kmz.lsp"
    "bscallouts_auto.lsp"
    "bsclean_border.lsp"))

(defun bs-missing-files (dir / missing f)
  (setq missing '())
  (foreach f (bs-required-files)
    (if (not (findfile (strcat dir "\\" f)))
      (setq missing (append missing (list f)))))
  missing)

(defun c:BSINSTALLCHECK ( / missing)
  (setq *bs-toolkit-dir* (bs-find-toolkit-dir))
  (if *bs-toolkit-dir*
    (progn
      (bs-add-to-support-path *bs-toolkit-dir*)
      (bs-add-to-trusted-paths *bs-toolkit-dir*)
      (princ (strcat "\n[BRIGHTSPEED] Toolkit folder: " *bs-toolkit-dir*))
      (setq missing (bs-missing-files *bs-toolkit-dir*))
      (if missing
        (progn
          (princ "\n[BRIGHTSPEED] Missing required files:")
          (foreach f missing (princ (strcat "\n  - " f)))
          (princ "\n[BRIGHTSPEED] Copy the whole 05_toolkit\\lisp folder, not only bs_loader.lsp."))
        (princ "\n[BRIGHTSPEED] Install check passed. APPLOAD bs_loader.lsp from this folder.")))
    (princ "\n[BRIGHTSPEED] Install check failed: toolkit folder not found."))
  (princ))

(setq *bs-toolkit-dir* (bs-find-toolkit-dir))

;; If auto-discovery failed, ask the user to pick any file from the AUTOMATION folder.
(if (and nil (not *bs-toolkit-dir*))
  (progn
    (princ "\n[BRIGHTSPEED] Could not auto-detect toolkit folder.")
    (princ "\n[BRIGHTSPEED] Pick any .lsp file from the AUTOMATION folder...")
    (setq *bs-loader-picked*
      (getfiled "Locate AUTOMATION folder — pick any .lsp file inside it" "" "lsp" 0))
    (if *bs-loader-picked*
      (setq *bs-toolkit-dir* (vl-filename-directory *bs-loader-picked*)))
    (setq *bs-loader-picked* nil)))

(if *bs-toolkit-dir*
  (progn
    (bs-add-to-support-path *bs-toolkit-dir*)
    (bs-add-to-trusted-paths *bs-toolkit-dir*)
    (princ (strcat "\n  [TOOLKIT DIR] " *bs-toolkit-dir*)))
  (princ "\n  [WARN] could not locate toolkit folder — file loads will fail"))

(defun bs-load-file (fname / full-path)
  (if (not *bs-toolkit-dir*)
    (princ (strcat "\n  [SKIP] " fname " (toolkit dir unknown)"))
    (progn
      (setq full-path (strcat *bs-toolkit-dir* "\\" fname))
      (if (findfile full-path)
        (progn (load full-path)
               (princ (strcat "\n  [OK] " fname)))
        (princ (strcat "\n  [MISSING] " fname))))))

(defun bs-load-clean-border-now ( / target)
  (setq target (strcat *bs-toolkit-dir* "\\bsclean_border.lsp"))
  (if (findfile target)
    (load target)
    (princ (strcat "\n[BSMAP] Missing cleanup file: " target)))
  (princ)
)

(defun c:BSMAP ( / )
  (bs-load-clean-border-now)
  (if c:BSCLEANMAP
    (c:BSCLEANMAP)
    (princ "\n[BSMAP] BSCLEANMAP did not load."))
  (princ)
)

(defun c:BCMAP ( / ) (c:BSMAP))
(defun c:BSCLMAP ( / ) (c:BSMAP))

(defun bs-load-rowdims-now ( / target)
  (setq target (strcat *bs-toolkit-dir* "\\bsrowdims.lsp"))
  (if (findfile target)
    (load target)
    (princ (strcat "\n[BSDIMS] Missing row dimensions file: " target)))
  (princ)
)

(defun c:BSDIMS ( / )
  (bs-load-rowdims-now)
  (if c:BSROWDIMS
    (c:BSROWDIMS)
    (princ "\n[BSDIMS] BSROWDIMS did not load."))
  (princ)
)

(defun c:BSDIM1 ( / )
  (bs-load-rowdims-now)
  (if c:BSROWDIMS1
    (c:BSROWDIMS1)
    (princ "\n[BSDIM1] BSROWDIMS1 did not load."))
  (princ)
)

(defun c:BSDIMC ( / )
  (bs-load-rowdims-now)
  (if c:BSROWDIMSC
    (c:BSROWDIMSC)
    (princ "\n[BSDIMC] BSROWDIMSC did not load."))
  (princ)
)

(defun c:BSDIAG ( / )
  (bs-load-rowdims-now)
  (if c:BSROWDIMS-DIAG
    (c:BSROWDIMS-DIAG)
    (princ "\n[BSDIAG] BSROWDIMS-DIAG did not load."))
  (princ)
)

(princ "\n============================================================")
(princ "\n  BRIGHTSPEED TOOLKIT v2 — Loading...")
(princ "\n============================================================")

;; MUST load first — all command files depend on bs- helpers
(bs-load-file "bs_helpers.lsp")

;; Core ROW workflow (v5.1 = latest with TRAP direction bug fix)
(bs-load-file "bsrow.lsp")

;; Corner filleting
(bs-load-file "bsfillet_all.lsp")

;; Callout commands (buried fiber length labels)
(bs-load-file "bscallout.lsp")

;; Aerial fiber callout commands
(bs-load-file "bsaerial.lsp")

;; Stationing labels
(bs-load-file "bsstation.lsp")

;; Driveway drafting
(bs-load-file "bsdrive.lsp")

;; Work area labels with coordinates
(bs-load-file "bsworkarea.lsp")

;; Minimum depth-of-cover note
(bs-load-file "bsminerdoc.lsp")

;; Compliance audit
(bs-load-file "bsaudit.lsp")

;; Pre-submission cleanup
(bs-load-file "bscleanup.lsp")

;; Parcel cleanup (depends on bsrow.lsp for ROW-TRAP layer)
(bs-load-file "bsparcels.lsp")

;; Snap perpendicular property line endpoints to ROW
(bs-load-file "bsparsnap.lsp")

;; Road cross-section dimension arrows
(bs-load-file "bsrowdims.lsp")

;; KMZ field-data importer (GPS lat/lon -> NC State Plane)
(bs-load-file "bskmz.lsp")

;; KMZ post-import snappers (4'-from-ROW, HH align, aerial pole-to-pole)
(bs-load-file "bskmz_snap.lsp")

;; Automated proposed sheet rectangles from KMZ route exports
(bs-load-file "bssheets.lsp")

;; One-step KMZ import + proposed sheet placement
(bs-load-file "bssheet_kmz.lsp")

;; Sheet-aware multileader callout automation
(bs-load-file "bscallouts_auto.lsp")

;; Border cleanup loaded last so it owns BSCLEAN/BSCLEANRECT command names
(bs-load-file "bsclean_border.lsp")
(if c:BSCLEANMAP
  (princ "\n  [READY] BSCLEANMAP command is defined")
  (princ "\n  [WARN] BSCLEANMAP command is NOT defined - bsclean_border.lsp did not load correctly"))

(princ "\n============================================================")
(princ "\n  COMMANDS - INSTALL:")
(princ "\n  BSINSTALLCHECK - Verify support/trusted path and required toolkit files")
(princ "\n")
(princ "\n  COMMANDS — ROW / ROAD:")
(princ "\n  BSROW         - ROW + EOP + TRAP lines from centerlines")
(princ "\n  BSADDTRAP     - Add TRAP lines to existing ROW lines")
(princ "\n  BSFILLET-ALL  - Fillet all ROW/EOP corners (R=25')")
(princ "\n  BSDRIVE       - Draw driveway, trim to ROW/EOP")
(princ "\n")
(princ "\n  COMMANDS — FIBER CALLOUTS:")
(princ "\n  BSCALLOUT     - Buried fiber callout (pick fiber + point)")
(princ "\n  BSCALLOUT-AUTO- Auto-callout all BURIED FIBER IN DUCT")
(princ "\n  BSAERIAL      - Aerial fiber callout (pick fiber + point)")
(princ "\n  BSAERIAL-AUTO - Auto-callout all AERIAL FIBER + ELASH")
(princ "\n  BSCALLOUTS-RUN        - Sheet-aware structures + buried + aerial callouts")
(princ "\n  BSCALLOUTS-STRUCTURES - Handhole/bore pit multileader callouts")
(princ "\n  BSCALLOUTS-BURIED     - Buried fiber segment multileader callouts")
(princ "\n  BSCALLOUTS-AERIAL     - Aerial callouts + AUBS footage markers")
(princ "\n  BSCALLOUTS-AUDIT      - Count callout source objects")
(princ "\n")
(princ "\n  COMMANDS — LABELING:")
(princ "\n  BSSTATION     - Auto-station HH/borepits/poles")
(princ "\n  BSWORKAREA    - Place WORK AREA START/END labels")
(princ "\n  BSMINERDOC    - Place MIN D.O.C. note")
(princ "\n")
(princ "\n  COMMANDS — PROPERTY LINE CLEANUP:")
(princ "\n  BSPARCELS     - Clean property lines using TRAP zone")
(princ "\n  BSPARHIDE     - Hide parallel PROPERTY LINE fragments only")
(princ "\n  BSPARSNAP     - Snap perpendicular PROPERTY LINE endpoints to ROW")
(princ "\n")
(princ "\n  COMMANDS — DIMENSIONS:")
(princ "\n  BSROWDIMS     - Auto road cross-section arrows in all BORDER viewports")
(princ "\n  BSROWDIMS1    - Same, but pick one BORDER rectangle to process")
(princ "\n  BSROWDIMSC    - Pick a centerline; auto-finds its BORDER")
(princ "\n  BSDIMS        - Short alias for BSROWDIMS")
(princ "\n  BSDIM1        - Short alias for BSROWDIMS1")
(princ "\n  BSDIMC        - Short alias for BSROWDIMSC")
(princ "\n  BSDIAG        - Diagnose layers inside one BORDER rectangle")
(princ "\n")
(princ "\n  COMMANDS — KMZ IMPORT:")
(princ "\n  BSKMZ            - Import KMZ field data onto correct layers (raw GPS)")
(princ "\n  BSKMZ-FIBERSNAP  - Buried fiber -> 4' from ROW (toward CL)")
(princ "\n  BSKMZ-HHALIGN    - HH blocks red, perpendicular to CL, 4' from ROW")
(princ "\n  BSKMZ-AERIALSNAP - Aerial fiber vertices -> nearest pole (80' radius)")
(princ "\n  BSKMZ-SNAP       - Run all three snappers in order")
(princ "\n")
(princ "\n  COMMANDS - SHEET PLANNING:")
(princ "\n  BSSHEETRECT   - Measure/save sample sheet rectangle size")
(princ "\n  BSSHEETLOAD   - Load generated bssheet_plan.lsp or bssheet_plan.csv")
(princ "\n  BSSHEETMAKE   - Create proposed sheets from loaded CSV plan")
(princ "\n  BSSHEETACCEPT - Move selected proposed rectangles to BORDER")
(princ "\n  BSSHEETCLEAR  - Hide proposed sheet geometry without deleting")
(princ "\n  BSSHEETKMZ    - Import KMZ and create proposed sheets from its running lines")
(princ "\n")
(princ "\n  COMMANDS — QUALITY / FINAL:")
(princ "\n  BSAUDIT       - Compliance scan + 8-check violation report")
(princ "\n  BSCLEANUP     - Pre-submission cleanup (widths, images, dups)")
(princ "\n  BSCLEANRECT   - Draw cleanup rectangle on BS-CLEAN-LIMIT")
(princ "\n  BSCLEANMAP    - Copy per sheet, Map-trim copies, hide originals")
(princ "\n  BSMAP         - Short alias for BSCLEANMAP")
(princ "\n  BCMAP         - Short alias for BSCLEANMAP")
(princ "\n  BSCLEANALL    - One-command cleanup after sheets are accepted")
(princ "\n  BSCLEAN       - Clean linework inside limit but outside BORDER rectangles")
(princ "\n  BSCLEANOUT    - Hide whole objects outside BORDER rectangles")
(princ "\n  BSCLEANLINES  - Trim crossing linework to BORDER rectangles")
(princ "\n  BSCLEANTRIMSEL- Trim selected bad linework to BORDER rectangles")
(princ "\n  BSCLEANBAD    - Hide selected bad incoming objects")
(princ "\n  BSCLEANCLEARMASK - Hide old BS-CLEAN-MASK artifacts")
(princ "\n  BSCLEANPICK   - Manual keep-mask selection cleanup (most robust)")
(princ "\n  BSCLEANLIMIT  - Alias for BSCLEANRECT")
(princ "\n  TRIMAGE       - Alias for BSCLEANRECT")
(princ "\n  BSCLEANVP     - Alias for BSCLEAN")
(princ "\n  BSCLEANAUTO   - Alias for BSCLEANALL")
(princ "\n  BSCLEANFINAL  - Alias for BSCLEANALL")
(princ "\n============================================================\n")
(princ)
