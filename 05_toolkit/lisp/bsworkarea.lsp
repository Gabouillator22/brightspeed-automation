;;; ============================================================
;;; BSWORKAREA - Place WORK AREA start/end labels
;;;
;;; Usage:
;;;   BSWORKAREA
;;;   -> Enter work area number (e.g. 1)
;;;   -> Pick START point  -> places "WORK AREA 1 START" label
;;;   -> Pick END points one by one (A, B, C...) -> places "WORK AREA 1A END" etc.
;;;   -> Press Enter to finish end points.
;;;
;;; Label format:
;;;   Start: "WORK AREA [N] START"
;;;          "[lat], [lon]"        (second line)
;;;   End:   "WORK AREA [N][A/B/C...] END"
;;;          "[lat], [lon]"        (second line)
;;;
;;; Coordinates:
;;;   Attempts AutoCAD Map 3D coordinate transform (WCS -> lat/lon).
;;;   Falls back to prompting the user for lat/lon if Map API unavailable.
;;;   Coordinate format: "XX.XXXXXX, -XX.XXXXXX"
;;;
;;; Text height  : 5.0
;;; Layer        : WORK AREA (color 1 = red), created if missing.
;;; Safety       : Adds TEXT entities only. Undo-safe.
;;; ============================================================

(defun c:BSWORKAREA ( / old-cmdecho old-layer
                        wa-num wa-str
                        start-pt end-pt
                        end-idx end-letter
                        lat lon coord-str
                        label-line1 label-line2
                        placed-count
                        end-letters)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "WORK AREA" 1)

  ;; End-point suffix letters A, B, C ...
  (setq end-letters '("A" "B" "C" "D" "E" "F" "G" "H" "I" "J"
                       "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T"))

  (setvar "CMDECHO" 1)
  (initget 7)  ; no blank, no zero, no negative
  (setq wa-num (getint "\n[BSWORKAREA] Enter Work Area number (1, 2, 3...): "))
  (setvar "CMDECHO" 0)

  (if (not wa-num)
    (progn
      (princ "\n[BSWORKAREA] Cancelled.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer))
    (progn
      (setq wa-str (itoa wa-num))
      (setq placed-count 0)

      ;; ---- START POINT ----
      (setvar "CMDECHO" 1)
      (setq start-pt (getpoint
        (strcat "\n[BSWORKAREA] Pick WORK AREA " wa-str " START point: ")))
      (setvar "CMDECHO" 0)

      (if start-pt
        (progn
          (setq start-pt (list (car start-pt) (cadr start-pt) 0.0))
          (setq coord-str (bswa-get-coord start-pt))
          (setq label-line1 (strcat "WORK AREA " wa-str " START"))
          (setq label-line2 coord-str)

          ;; Place two TEXT lines, stacked vertically (spacing = 6.0)
          (bswa-place-label start-pt label-line1 label-line2)
          (setq placed-count (1+ placed-count))
          (princ (strcat "\n[BSWORKAREA] Placed: " label-line1))
        )
        (princ "\n[BSWORKAREA] No start point. Skipping START label.")
      )

      ;; ---- END POINTS (loop until Enter with no point) ----
      (setq end-idx 0)
      (setq end-pt T)  ; dummy to enter loop

      (while (and end-pt (< end-idx (length end-letters)))
        (setq end-letter (nth end-idx end-letters))
        (setvar "CMDECHO" 1)
        (setq end-pt (getpoint
          (strcat "\n[BSWORKAREA] Pick WORK AREA " wa-str end-letter
            " END point (Enter to finish): ")))
        (setvar "CMDECHO" 0)

        (if end-pt
          (progn
            (setq end-pt (list (car end-pt) (cadr end-pt) 0.0))
            (setq coord-str  (bswa-get-coord end-pt))
            (setq label-line1 (strcat "WORK AREA " wa-str end-letter " END"))
            (setq label-line2 coord-str)

            (bswa-place-label end-pt label-line1 label-line2)
            (setq placed-count (1+ placed-count))
            (princ (strcat "\n[BSWORKAREA] Placed: " label-line1))
            (setq end-idx (1+ end-idx))
          )
          ;; nil = user pressed Enter -> exit loop
          (setq end-pt nil)
        )
      )

      (setvar "CMDECHO" old-cmdecho)
      (setvar "CLAYER" old-layer)
      (princ (strcat "\n[BSWORKAREA] Done. " (itoa placed-count) " labels placed."))
    )
  )
  (princ)
)

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bswa-place-label (pt line1 line2 / pt2)
  ;; Place two TEXT entities stacked at pt.
  ;; Line 1 at pt, line 2 offset down by 1.2 * text_height.
  (bs-make-text pt 5.0 "WORK AREA" line1)
  (setq pt2 (list (car pt) (- (cadr pt) 6.0) 0.0))
  (bs-make-text pt2 5.0 "WORK AREA" line2))

(defun bswa-get-coord (pt / lat lon coord-str attempt)
  ;; Attempt to get lat/lon from drawing WCS point.
  ;; Tries AutoCAD Map 3D coordinate transform API first.
  ;; Falls back to user input if Map API is not available.

  ;; Try Map 3D transform
  (setq attempt (bswa-try-map-transform pt))

  (if attempt
    attempt
    (progn
      ;; Fallback: prompt user for coordinates
      (princ (strcat "\n[BSWORKAREA] No Map coordinate system detected."))
      (princ "\n[BSWORKAREA] Enter coordinates manually.")
      (setvar "CMDECHO" 1)
      (setq coord-str
        (getstring T
          (strcat "\n  Enter coords for " (bswa-pt-str pt)
            " (e.g. 35.123456, -80.654321): ")))
      (setvar "CMDECHO" 0)
      (if (or (not coord-str) (= coord-str ""))
        (strcat (rtos (car pt) 2 2) ", " (rtos (cadr pt) 2 2))  ; fallback to WCS
        coord-str))))

(defun bswa-try-map-transform (pt / tx-obj result lat-lon)
  ;; Try to transform WCS (x,y) to geographic lat/lon using Map 3D.
  ;; Returns "lat, lon" string or nil on failure.
  ;; Uses Map 3D ActiveX: AeccMapProduct.WcsToLl or similar.
  (setq result
    (vl-catch-all-apply
      '(lambda (wcs-pt)
         ;; Access the Map document coordinate system object.
         ;; The API path depends on Map 3D version.
         ;; Try Map 3D 2027 path first.
         (setq map-doc
           (vlax-get-property
             (vlax-get-acad-object) 'ActiveDocument))
         ;; Get the map object (Map 3D specific)
         (setq map-obj
           (vlax-get-property map-doc 'Map))
         ;; Transform WCS point to geographic
         (vlax-invoke map-obj 'WcsToLl
           (car wcs-pt) (cadr wcs-pt))
       )
      (list pt)))

  (if (vl-catch-all-error-p result)
    nil   ; Map API not available
    (if (and result (listp result) (>= (length result) 2))
      (strcat (rtos (car result) 2 6) ", " (rtos (cadr result) 2 6))
      nil)))

(defun bswa-pt-str (pt / )
  ;; Compact WCS coordinate string for user prompt.
  (strcat "(" (rtos (car pt) 2 1) ", " (rtos (cadr pt) 2 1) ")"))

(princ "\n[BSWORKAREA] Loaded. Type BSWORKAREA to place START/END work area labels.")
(princ)
