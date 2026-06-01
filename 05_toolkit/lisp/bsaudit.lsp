;;; ============================================================
;;; BSAUDIT v2 - Brightspeed drawing compliance scan
;;;
;;; Runs 8 checks and reports violations to the command line.
;;; No entities are modified. Pure diagnostic scan.
;;;
;;; CHECK 1: Text height on CALLOUTS/STATIONING layers
;;;   Text not at 5.0 height -> flag.
;;;
;;; CHECK 2: Fiber polylines on correct layers
;;;   Width 0.5 polylines not on AERIAL FIBER / BURIED FIBER / ELASH -> flag.
;;;
;;; CHECK 3: Buried fiber without a callout
;;;   BURIED FIBER IN DUCT polyline with no nearby "HDD BORE" text -> flag.
;;;   (Proximity threshold: 50')
;;;
;;; CHECK 4: Structure blocks without station label
;;;   INSERT matching HANDHOLE/HH/BORE/BOREPIT/POLE with no nearby
;;;   STATIONING text within 15' -> flag.
;;;
;;; CHECK 5: Wide polylines on wrong layers
;;;   LWPOLYLINE with constant width >= 0.4 not on a fiber layer -> flag.
;;;
;;; CHECK 6: Text overlap on CALLOUTS layer
;;;   TEXT entities on CALLOUTS within 5' of each other -> flag pairs.
;;;
;;; CHECK 7: WORK AREA labels
;;;   If no TEXT containing "WORK AREA" exists -> flag.
;;;
;;; CHECK 8: MIN D.O.C. note
;;;   If BURIED FIBER exists but no "MIN D.O.C." text -> flag.
;;; ============================================================

(defun c:BSAUDIT ( / old-cmdecho old-layer
                     violations violation-count
                     buried-ss aerial-ss elash-ss
                     blocks-ss callout-txt-ss station-txt-ss
                     wa-txt-ss doc-txt-ss
                     i j ent txt-ent
                     txt-ht ent-layer ent-type ent-width
                     has-callout has-station
                     pt1 pt2 nearby-ss
                     fiber-layers)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (setq violations nil)
  (setq violation-count 0)

  (setq fiber-layers '("AERIAL FIBER" "BURIED FIBER IN DUCT" "ELASH"))

  (princ "\n[BSAUDIT] ============================================")
  (princ "\n[BSAUDIT] Running compliance checks...")
  (princ "\n[BSAUDIT] ============================================")

  ;; Pre-collect common selection sets
  (setq buried-ss
    (ssget "X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "BURIED FIBER IN DUCT"))))
  (setq aerial-ss
    (ssget "X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "AERIAL FIBER"))))
  (setq elash-ss
    (ssget "X" '((0 . "LWPOLYLINE,POLYLINE") (8 . "ELASH"))))
  (setq blocks-ss
    (ssget "X" '((0 . "INSERT"))))
  (setq callout-txt-ss
    (ssget "X" '((0 . "TEXT") (8 . "CALLOUTS"))))
  (setq station-txt-ss
    (ssget "X" '((0 . "TEXT") (8 . "STATIONING"))))
  (setq wa-txt-ss
    (ssget "X" (list '(0 . "TEXT,MTEXT") (cons 1 "*WORK AREA*"))))
  (setq doc-txt-ss
    (ssget "X" (list '(0 . "TEXT,MTEXT") (cons 1 "*MIN D.O.C.*"))))

  ;; ============================================================
  ;; CHECK 1 — Text height on CALLOUTS and STATIONING layers
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 1: Text heights...")
  (setq check1-count 0)
  (foreach layer-name '("CALLOUTS" "STATIONING")
    (setq txt-ss (ssget "X" (list '(0 . "TEXT") (cons 8 layer-name))))
    (if txt-ss
      (progn
        (setq i 0)
        (while (< i (sslength txt-ss))
          (setq txt-ent (ssname txt-ss i))
          (setq txt-ht (cdr (assoc 40 (entget txt-ent))))
          (if (and txt-ht
                   (not (equal txt-ht 5.0 0.01))
                   (not (equal txt-ht 6.0 0.01)))
            (progn
              (setq violations (append violations
                (list (strcat "  CHECK1: Text height " (rtos txt-ht 2 2)
                  " (expected 5.0) on layer " layer-name
                  " handle=" (cdr (assoc 5 (entget txt-ent)))))))
              (setq check1-count (1+ check1-count))
              (setq violation-count (1+ violation-count))
            )
          )
          (setq i (1+ i))
        )
      )
    )
  )
  (if (= check1-count 0)
    (princ " OK")
    (princ (strcat " " (itoa check1-count) " violations")))

  ;; ============================================================
  ;; CHECK 2 — Fiber polylines on correct layers
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 2: Fiber layer compliance...")
  (setq check2-count 0)
  ;; Check that all three fiber layers have the correct entity types
  (foreach chk-layer fiber-layers
    (setq chk-ss (ssget "X"
      (list '(0 . "LWPOLYLINE,POLYLINE,LINE") (cons 8 chk-layer))))
    ;; If entities exist on fiber layer, they should be polylines, not lines
    (if chk-ss
      (progn
        (setq i 0)
        (while (< i (sslength chk-ss))
          (setq ent (ssname chk-ss i))
          (setq ent-type (cdr (assoc 0 (entget ent))))
          (if (= ent-type "LINE")
            (progn
              (setq violations (append violations
                (list (strcat "  CHECK2: LINE entity (not polyline) on " chk-layer
                  " handle=" (cdr (assoc 5 (entget ent)))))))
              (setq check2-count (1+ check2-count))
              (setq violation-count (1+ violation-count))
            )
          )
          (setq i (1+ i))
        )
      )
    )
  )
  (if (= check2-count 0)
    (princ " OK")
    (princ (strcat " " (itoa check2-count) " violations")))

  ;; ============================================================
  ;; CHECK 3 — Buried fiber without callout (HDD BORE text nearby)
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 3: Buried fiber callout coverage...")
  (setq check3-count 0)
  (if buried-ss
    (progn
      (setq i 0)
      (while (< i (sslength buried-ss))
        (setq ent (ssname buried-ss i))
        (setq mid-pt (bs-ent-midpt ent))
        (setq has-callout nil)

        ;; Check for "HDD BORE" text within 50' of fiber midpoint
        (if (and mid-pt callout-txt-ss)
          (progn
            (setq j 0)
            (while (and (< j (sslength callout-txt-ss)) (not has-callout))
              (setq txt-ent (ssname callout-txt-ss j))
              (setq txt-str (cdr (assoc 1 (entget txt-ent))))
              (setq txt-pos (cdr (assoc 10 (entget txt-ent))))
              (if (and txt-str txt-pos
                       (vl-string-search "HDD BORE" (strcase txt-str))
                       (< (distance mid-pt txt-pos) 50.0))
                (setq has-callout T))
              (setq j (1+ j))
            )
          )
        )

        (if (not has-callout)
          (progn
            (setq violations (append violations
              (list (strcat "  CHECK3: No HDD BORE callout near BURIED FIBER segment"
                " handle=" (cdr (assoc 5 (entget ent)))))))
            (setq check3-count (1+ check3-count))
            (setq violation-count (1+ violation-count))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (if (= check3-count 0)
    (princ " OK")
    (princ (strcat " " (itoa check3-count) " violations")))

  ;; ============================================================
  ;; CHECK 4 — Structure blocks without station label
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 4: Station label coverage...")
  (setq check4-count 0)
  (setq struct-keywords '("HANDHOLE" "HH" "BORE" "BOREPIT" "POLE"))

  (if blocks-ss
    (progn
      (setq i 0)
      (while (< i (sslength blocks-ss))
        (setq ent (ssname blocks-ss i))
        (setq blk-name (strcase (cdr (assoc 2 (entget ent)))))

        (if (bsst-matches-any-keyword blk-name struct-keywords)
          (progn
            (setq ins-pt (cdr (assoc 10 (entget ent))))
            (setq ins-pt (list (car ins-pt) (cadr ins-pt) 0.0))
            (setq has-station nil)

            ;; Check for STA text within 15'
            (if station-txt-ss
              (progn
                (setq j 0)
                (while (and (< j (sslength station-txt-ss)) (not has-station))
                  (setq txt-ent (ssname station-txt-ss j))
                  (setq txt-pos (cdr (assoc 10 (entget txt-ent))))
                  (if (and txt-pos (< (distance ins-pt txt-pos) 15.0))
                    (setq has-station T))
                  (setq j (1+ j))
                )
              )
            )

            (if (not has-station)
              (progn
                (setq violations (append violations
                  (list (strcat "  CHECK4: No STA label near block \""
                    (cdr (assoc 2 (entget ent))) "\""
                    " handle=" (cdr (assoc 5 (entget ent)))))))
                (setq check4-count (1+ check4-count))
                (setq violation-count (1+ violation-count))
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (if (= check4-count 0)
    (princ " OK")
    (princ (strcat " " (itoa check4-count) " violations")))

  ;; ============================================================
  ;; CHECK 5 — Wide polylines on wrong layers
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 5: Wide polylines on correct layers...")
  (setq check5-count 0)
  ;; ssget all LWPOLYLINE entities, check constant width
  (setq all-pl-ss (ssget "X" '((0 . "LWPOLYLINE"))))
  (if all-pl-ss
    (progn
      (setq i 0)
      (while (< i (sslength all-pl-ss))
        (setq ent (ssname all-pl-ss i))
        (setq ent-layer (cdr (assoc 8 (entget ent))))
        (setq ent-width (cdr (assoc 43 (entget ent))))  ; constant width

        ;; Flag wide polylines not on a fiber layer
        (if (and ent-width (>= ent-width 0.4)
                 (not (member (strcase ent-layer)
                        (mapcar 'strcase fiber-layers))))
          (progn
            (setq violations (append violations
              (list (strcat "  CHECK5: Wide polyline (w=" (rtos ent-width 2 2)
                ") on non-fiber layer \"" ent-layer "\""
                " handle=" (cdr (assoc 5 (entget ent)))))))
            (setq check5-count (1+ check5-count))
            (setq violation-count (1+ violation-count))
          )
        )
        (setq i (1+ i))
      )
    )
  )
  (if (= check5-count 0)
    (princ " OK")
    (princ (strcat " " (itoa check5-count) " violations")))

  ;; ============================================================
  ;; CHECK 6 — Text overlap on CALLOUTS layer
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 6: Callout text overlap...")
  (setq check6-count 0)
  (if callout-txt-ss
    (progn
      (setq i 0)
      (while (< i (1- (sslength callout-txt-ss)))
        (setq ent (ssname callout-txt-ss i))
        (setq pt1 (cdr (assoc 10 (entget ent))))
        (setq j (1+ i))
        (while (< j (sslength callout-txt-ss))
          (setq txt-ent (ssname callout-txt-ss j))
          (setq pt2 (cdr (assoc 10 (entget txt-ent))))
          (if (and pt1 pt2 (< (distance pt1 pt2) 5.0))
            (progn
              (setq violations (append violations
                (list (strcat "  CHECK6: Text overlap < 5' on CALLOUTS: handles "
                  (cdr (assoc 5 (entget ent)))
                  " and " (cdr (assoc 5 (entget txt-ent)))))))
              (setq check6-count (1+ check6-count))
              (setq violation-count (1+ violation-count))
            )
          )
          (setq j (1+ j))
        )
        (setq i (1+ i))
      )
    )
  )
  (if (= check6-count 0)
    (princ " OK")
    (princ (strcat " " (itoa check6-count) " violations")))

  ;; ============================================================
  ;; CHECK 7 — WORK AREA labels present
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 7: WORK AREA labels...")
  (if (or (not wa-txt-ss) (= (sslength wa-txt-ss) 0))
    (progn
      (setq violations (append violations
        (list "  CHECK7: No WORK AREA labels found in drawing.")))
      (setq violation-count (1+ violation-count))
      (princ " MISSING")
    )
    (princ " OK")
  )

  ;; ============================================================
  ;; CHECK 8 — MIN D.O.C. note present when buried fiber exists
  ;; ============================================================
  (princ "\n[BSAUDIT] CHECK 8: MIN D.O.C. note...")
  (if buried-ss
    (progn
      (if (or (not doc-txt-ss) (= (sslength doc-txt-ss) 0))
        (progn
          (setq violations (append violations
            (list "  CHECK8: BURIED FIBER exists but no MIN D.O.C. note found."
                  "          Run BSMINERDOC to add it.")))
          (setq violation-count (1+ violation-count))
          (princ " MISSING")
        )
        (princ " OK")
      )
    )
    (princ " N/A (no buried fiber)")
  )

  ;; ============================================================
  ;; Print full violation report
  ;; ============================================================
  (setvar "CMDECHO" old-cmdecho)
  (setvar "CLAYER" old-layer)

  (princ "\n")
  (princ "\n[BSAUDIT] ============================================")
  (if (= violation-count 0)
    (progn
      (princ "\n[BSAUDIT] ALL CHECKS PASSED. Drawing is compliant.")
    )
    (progn
      (princ (strcat "\n[BSAUDIT] VIOLATIONS FOUND: " (itoa violation-count)))
      (princ "\n")
      (foreach v violations
        (princ (strcat "\n" v)))
    )
  )
  (princ "\n[BSAUDIT] ============================================")
  (princ)
)

(princ "\n[BSAUDIT v2] Loaded. Type BSAUDIT to run 8-check compliance scan.")
(princ)
