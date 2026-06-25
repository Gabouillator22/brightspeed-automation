;;; ============================================================
;;; BSCALLOUT_PLACE - Standalone MLeader creator for Python
;;;
;;; Public helper:
;;;   (bscw-place-mleader ax ay tx ty text layer)
;;;
;;; AutoCAD Map 3D 2027
;;; ============================================================

(vl-load-com)

(setq BSCW_LAST_HANDLE nil)
(setq BSCW_LAST_STATUS "INIT")
(setq BSCW_LAST_TEXT_BOX nil)

(defun bscw-safe-set (obj prop val / res)
  (setq res (vl-catch-all-apply 'vlax-put-property (list obj prop val)))
  (not (vl-catch-all-error-p res)))

(defun bscw-safe-get (obj prop / res)
  (setq res (vl-catch-all-apply 'vlax-get-property (list obj prop)))
  (if (vl-catch-all-error-p res) nil res))

(defun bscw-strcase (val /)
  (if val (strcase val) ""))

(defun bscw-ensure-layer (name / doc layers lay)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layers (vla-get-Layers doc))
  (setq lay (vl-catch-all-apply 'vla-Item (list layers name)))
  (if (vl-catch-all-error-p lay)
    (progn
      (setq lay (vla-Add layers name))
      (bscw-safe-set lay 'Color 7)))
  (bscw-safe-set lay 'LayerOn :vlax-true)
  (bscw-safe-set lay 'Freeze :vlax-false)
  (bscw-safe-set lay 'Lock :vlax-false)
  lay)

(defun bscw-vunit (x y / len)
  (setq len (sqrt (+ (* x x) (* y y))))
  (if (> len 0.000001)
    (list (/ x len) (/ y len))
    (list 1.0 0.0)))

(defun bscw-landing (ax ay tx ty / unit gap)
  (setq gap 5.0)
  (setq unit (bscw-vunit (- tx ax) (- ty ay)))
  (list (- tx (* gap (car unit))) (- ty (* gap (cadr unit)))))

(defun bscw-make-array (vals / arr)
  (setq arr (vlax-make-safearray vlax-vbDouble (cons 0 (1- (length vals)))))
  (vlax-safearray-fill arr vals)
  arr)

(defun bscw-apply-mleader-props (obj text layer / ann)
  (bscw-safe-set obj 'Layer layer)
  (bscw-safe-set obj 'TextString text)
  (bscw-safe-set obj 'TextHeight 5.0)
  (bscw-safe-set obj 'ArrowheadSize 8.5)
  (bscw-safe-set obj 'ArrowSymbol "Closed filled")
  (bscw-safe-set obj 'LandingGap 5.0)
  (bscw-safe-set obj 'DoglegLength 5.0)
  (bscw-safe-set obj 'TextBackgroundFill :vlax-true)
  (bscw-safe-set obj 'BackgroundFill :vlax-true)
  (bscw-safe-set obj 'UseBackgroundColor :vlax-true)
  (bscw-safe-set obj 'BackgroundScaleFactor 1.1)
  (bscw-safe-set obj 'EntityTransparency "0")
  (bscw-safe-set obj 'EnableFrameText :vlax-false)
  (bscw-safe-set obj 'TextFrameDisplay :vlax-false)
  (setq ann (bscw-safe-get obj 'Annotation))
  (if ann
    (progn
      (bscw-safe-set ann 'BackgroundFill :vlax-true)
      (bscw-safe-set ann 'EntityTransparency "0")
      (bscw-safe-set ann 'Height 5.0)))
  obj)

(defun bscw-store-text-box (handle / ent obj ann target bbox-res lo hi mn mx)
  (setq BSCW_LAST_TEXT_BOX nil)
  (setq ent (if handle (handent handle) nil))
  (if ent
    (progn
      (setq obj (vlax-ename->vla-object ent))
      (setq ann (bscw-safe-get obj 'Annotation))
      (setq target (if ann ann obj))
      (setq bbox-res (vl-catch-all-apply 'vla-GetBoundingBox (list target 'lo 'hi)))
      (if (not (vl-catch-all-error-p bbox-res))
        (progn
          (setq mn (vlax-safearray->list lo))
          (setq mx (vlax-safearray->list hi))
          (setq BSCW_LAST_TEXT_BOX (list (car mn) (cadr mn) (car mx) (cadr mx)))))))
  BSCW_LAST_TEXT_BOX)

(defun bscw-last-text-box ()
  BSCW_LAST_TEXT_BOX)

(defun bscw-valid-mleader-p (handle expected-text expected-layer / ent obj name text layer bbox-res)
  (setq ent (handent handle))
  (if (not ent)
    nil
    (progn
      (setq obj (vlax-ename->vla-object ent))
      (setq name (bscw-strcase (bscw-safe-get obj 'ObjectName)))
      (setq text (bscw-safe-get obj 'TextString))
      (setq layer (bscw-strcase (bscw-safe-get obj 'Layer)))
      (setq bbox-res (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'lo 'hi)))
      (and
        (= name "ACDBMLEADER")
        (= text expected-text)
        (= layer (strcase expected-layer))
        (not (vl-catch-all-error-p bbox-res))))))

(defun bscw-place-mleader (ax ay tx ty text layer / doc ms landing arr obj)
  (setq BSCW_LAST_HANDLE nil)
  (setq BSCW_LAST_STATUS "START")
  (setq BSCW_LAST_TEXT_BOX nil)
  (bscw-ensure-layer layer)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq ms (vla-get-ModelSpace doc))
  (setq landing (bscw-landing ax ay tx ty))
  (setq arr
    (bscw-make-array
      (list ax ay 0.0
            (car landing) (cadr landing) 0.0
            tx ty 0.0)))
  (setq obj (vl-catch-all-apply 'vla-AddMLeader (list ms arr 0)))
  (if (vl-catch-all-error-p obj)
    (progn
      (setq BSCW_LAST_STATUS
        (strcat "FAIL " (vl-catch-all-error-message obj)))
      (princ (strcat "\n[BSCW] FAIL " BSCW_LAST_STATUS))
      nil)
    (progn
      (bscw-apply-mleader-props obj text layer)
      (setq BSCW_LAST_HANDLE (vla-get-Handle obj))
      (if (bscw-valid-mleader-p BSCW_LAST_HANDLE text layer)
        (progn
          (bscw-store-text-box BSCW_LAST_HANDLE)
          (setq BSCW_LAST_STATUS "SUCCESS")
          (princ (strcat "\n[BSCW] SUCCESS handle=" BSCW_LAST_HANDLE))
          BSCW_LAST_HANDLE)
        (progn
          (vl-catch-all-apply 'vla-Delete (list obj))
          (setq BSCW_LAST_HANDLE nil)
          (setq BSCW_LAST_STATUS "FAIL validation")
          (princ "\n[BSCW] FAIL validation")
          nil)))))

(defun c:BSCWPLACEHELPER ()
  (princ "\n[BSCW] bscallout_place.lsp loaded. Use bscw-place-mleader from Python.")
  (princ))

(princ "\n[BSCW] Loaded bscallout_place.lsp. Helper: bscw-place-mleader")
(princ)
