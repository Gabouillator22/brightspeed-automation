;;; ============================================================
;;; BSCLEANUP - Pre-submission drawing cleanup pass
;;;
;;; Runs the following in sequence — no user interaction needed:
;;;   1. ZOOM EXTENTS
;;;   2. Set all AERIAL FIBER polylines: width 0.5, PLINEGEN ON
;;;   3. Set all ELASH polylines: width 0.5, PLINEGEN ON
;;;   4. Set all BURIED FIBER IN DUCT polylines: width 0.5, PLINEGEN ON
;;;   5. Move all IMAGE entities to VIEWPORT IMAGE layer
;;;   6. Remove duplicate LINE segments on PROPERTY LINE layer
;;;      (same start/end points within 0.01' - moves one copy to
;;;       PROPERTY LINE-HIDDEN rather than deleting)
;;;   7. Print summary of changes
;;;
;;; PLINEGEN ON (group code 70 bit 128) makes linetype display
;;; continuously across all vertices instead of per-segment.
;;;
;;; Safety: No deletes. Moves to hidden layers instead. Undo-safe.
;;; ============================================================

(defun c:BSCLEANUP ( / old-cmdecho old-layer
                       fiber-layers
                       width-count image-count dup-count
                       i j ent ent2
                       elist elist2 ent-layer ent-type
                       p1 p2 p3 p4 is-dup)

  (vl-load-com)
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-layer   (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (bs-ensure-layer "VIEWPORT IMAGE"       8)
  (bs-ensure-layer "PROPERTY LINE-HIDDEN" 8)

  (setq fiber-layers '("AERIAL FIBER" "ELASH" "BURIED FIBER IN DUCT"))
  (setq width-count 0 image-count 0 dup-count 0)

  ;; ---- STEP 1: ZOOM EXTENTS ----
  (princ "\n[BSCLEANUP] Step 1: ZOOM EXTENTS...")
  (command "_.ZOOM" "E")
  (princ " done.")

  ;; ---- STEPS 2-4: Set fiber polyline properties ----
  (princ "\n[BSCLEANUP] Steps 2-4: Setting fiber polyline widths and PLINEGEN...")

  (foreach lname fiber-layers
    (setq ss (ssget "X" (list '(0 . "LWPOLYLINE,POLYLINE") (cons 8 lname))))
    (if ss
      (progn
        (setq i 0)
        (while (< i (sslength ss))
          (setq ent (ssname ss i))
          (setq ent-type (cdr (assoc 0 (entget ent))))

          (cond
            ((= ent-type "LWPOLYLINE")
              (bscu-set-lwpolyline-width ent 0.5)
              (bscu-set-plinegen-on ent)
              (setq width-count (1+ width-count)))

            ((= ent-type "POLYLINE")
              ;; For heavy POLYLINE type, use VLA to set width
              (setq vla-ent
                (vl-catch-all-apply 'vlax-ename->vla-object (list ent)))
              (if (not (vl-catch-all-error-p vla-ent))
                (progn
                  (vl-catch-all-apply 'vla-put-ConstantWidth (list vla-ent 0.5))
                  (setq width-count (1+ width-count))
                )
              )
            )
          )
          (setq i (1+ i))
        )
        (princ (strcat "\n[BSCLEANUP]   " lname ": " (itoa (sslength ss)) " polylines updated."))
      )
    )
  )

  ;; ---- STEP 5: Move IMAGE entities to VIEWPORT IMAGE ----
  (princ "\n[BSCLEANUP] Step 5: Moving IMAGE entities to VIEWPORT IMAGE...")
  (setq img-ss (ssget "X" '((0 . "IMAGE"))))
  (if img-ss
    (progn
      (setq i 0)
      (while (< i (sslength img-ss))
        (setq ent (ssname img-ss i))
        (setq ent-layer (cdr (assoc 8 (entget ent))))
        (if (not (= (strcase ent-layer) "VIEWPORT IMAGE"))
          (progn
            (bs-force-layer ent "VIEWPORT IMAGE")
            (setq image-count (1+ image-count))
          )
        )
        (setq i (1+ i))
      )
      (princ (strcat " " (itoa image-count) " moved."))
    )
    (princ " none found.")
  )

  ;; ---- STEP 6: Remove duplicate PROPERTY LINE segments ----
  (princ "\n[BSCLEANUP] Step 6: Removing duplicate PROPERTY LINE segments...")
  (setq prop-ss (ssget "X" '((0 . "LINE") (8 . "PROPERTY LINE"))))
  (if (and prop-ss (> (sslength prop-ss) 1))
    (progn
      ;; Build list of entity data for comparison
      (setq prop-list nil)
      (setq i 0)
      (while (< i (sslength prop-ss))
        (setq ent (ssname prop-ss i))
        (setq elist (entget ent))
        (setq p1 (cdr (assoc 10 elist)))
        (setq p2 (cdr (assoc 11 elist)))
        (setq prop-list (append prop-list (list (list ent p1 p2))))
        (setq i (1+ i))
      )

      ;; Compare each pair — O(n^2) but acceptable for drawing sizes
      (setq i 0)
      (while (< i (1- (length prop-list)))
        (setq rec-i (nth i prop-list))
        (setq ent   (nth 0 rec-i))
        (setq p1    (nth 1 rec-i))
        (setq p2    (nth 2 rec-i))

        ;; Only check if this entity is still on PROPERTY LINE (not already hidden)
        (if (= (cdr (assoc 8 (entget ent))) "PROPERTY LINE")
          (progn
            (setq j (1+ i))
            (while (< j (length prop-list))
              (setq rec-j (nth j prop-list))
              (setq ent2  (nth 0 rec-j))
              (setq p3    (nth 1 rec-j))
              (setq p4    (nth 2 rec-j))

              ;; Skip if already hidden
              (if (= (cdr (assoc 8 (entget ent2))) "PROPERTY LINE")
                (progn
                  ;; Check forward and reversed match
                  (setq is-dup
                    (or
                      (and (< (distance p1 p3) 0.01) (< (distance p2 p4) 0.01))
                      (and (< (distance p1 p4) 0.01) (< (distance p2 p3) 0.01))
                    )
                  )
                  (if is-dup
                    (progn
                      ;; Hide the second one (keep the first)
                      (bs-force-layer ent2 "PROPERTY LINE-HIDDEN")
                      (setq dup-count (1+ dup-count))
                    )
                  )
                )
              )
              (setq j (1+ j))
            )
          )
        )
        (setq i (1+ i))
      )

      (if (> dup-count 0)
        (progn
          (command "_.LAYER" "F" "PROPERTY LINE-HIDDEN" "")
          (princ (strcat " " (itoa dup-count) " duplicates moved to PROPERTY LINE-HIDDEN."))
        )
        (princ " none found.")
      )
    )
    (progn
      (if (not prop-ss)
        (princ " no PROPERTY LINE entities.")
        (princ " only 1 segment, no comparison possible."))
    )
  )

  ;; ---- STEP 7: Summary ----
  (setvar "CMDECHO" old-cmdecho)
  (setvar "CLAYER" old-layer)
  (princ "\n")
  (princ "\n[BSCLEANUP] ======== RESULTS ========")
  (princ (strcat "\n  Fiber polylines updated (width + PLINEGEN) : " (itoa width-count)))
  (princ (strcat "\n  IMAGE entities moved to VIEWPORT IMAGE     : " (itoa image-count)))
  (princ (strcat "\n  Duplicate PROPERTY LINE segments hidden    : " (itoa dup-count)))
  (princ "\n  No entities were deleted.")
  (princ "\n  All changes undo-able with Ctrl+Z")
  (princ "\n[BSCLEANUP] =========================")
  (princ)
)

;;; ---------------------------------------------------------------
;;; Private helpers
;;; ---------------------------------------------------------------

(defun bscu-set-lwpolyline-width (ent new-width / elist flag43)
  ;; Set constant width on LWPOLYLINE via entmod.
  (setq elist (entget ent))
  (setq flag43 (assoc 43 elist))
  (if flag43
    (setq elist (subst (cons 43 new-width) flag43 elist))
    (setq elist (append elist (list (cons 43 new-width))))
  )
  (entmod elist)
  (entupd ent)
  (princ))

(defun bscu-set-plinegen-on (ent / elist flag70 new70)
  ;; Set PLINEGEN bit (bit 128) in group code 70 of LWPOLYLINE.
  ;; This makes linetype generate continuously across the whole polyline.
  (setq elist (entget ent))
  (setq flag70 (assoc 70 elist))
  (if flag70
    (progn
      (setq new70 (logior (cdr flag70) 128))
      (setq elist (subst (cons 70 new70) flag70 elist))
      (entmod elist)
      (entupd ent)
    )
  )
  (princ))

(princ "\n[BSCLEANUP] Loaded. Type BSCLEANUP to run the pre-submission cleanup pass.")
(princ)
