;; BSC -Gilles Chanteau- (maj 12/06/10)
;; Dessiner une ligne sur la bissectrice de l'angle des segments spécifiés
;; ou de l'angle défini par 3 points
;; La longueur de la ligne est entrée au clavier ou à l'aide du pointeur.

(defun c:bsc (/		*error*	  Set2Points	      PointsFromSegment
	      p1	p2	  p3	    p4	      e1
	      e2	v1	  v2	    st
	     )
  (vl-load-com)
  (or *acdoc*
      (setq *acdoc* (vla-get-ActiveDocument (vlax-get-acad-object)))
  )

  ;; Redéfiniton de *error*
  (defun *error* (msg)
    (and msg
	 (/= msg "Fonction annulée")
	 (princ (strcat "\nErreur: " msg))
    )
    (grtext)
    (vla-EndUndoMark *acdoc*)
    (princ)
  )

  ;; Points par segment
  (defun PointsFromSegment (e1 sym1 sym2 / ob pt pa vc)
    (setq ob (vlax-ename->vla-object (car e1)))
    (cond
      ((= (vla-get-ObjectName ob) "AcDbLine")
       (set sym1 (trans (osnap (cadr e1) "_nea") 1 0))
       (set sym2 (vlax-get ob 'StartPoint))
      )
      ((member (vla-get-ObjectName ob) '("AcDbRay" "AcDbXline"))
       (setq pt	(trans (osnap (cadr e1) "_nea") 1 0)
	     vc	(vlax-get ob 'DirectionVector)
       )
       (set sym1 pt)
       (set sym2 (mapcar '+ pt vc))
      )
      ((and (member (vla-get-ObjectName ob)
		    '("AcDbPolyline" "AcDb2dPolyline")
	    )
	    (setq pt (vlax-curve-getClosestPointToProjection
		       ob
		       (trans (cadr e1) 1 0)
		       (getvar 'viewdir)
		     )
	    )
	    (setq pa (fix (vlax-curve-getParamAtPoint ob pt)))
	    (= 0 (vla-GetBulge ob pa))
       )
       (set sym1 pt)
       (set sym2 (vlax-curve-getPointAtParam ob pa))
      )
      ((= (vla-get-ObjectName ob) "AcDb3dPolyline")
       (setq pt	(trans (osnap (cadr e1) "_nea") 1 0)
	     pa	(fix (vlax-curve-getParamAtPoint ob pt))
       )
       (set sym1 pt)
       (set sym2 (vlax-curve-getPointAtParam ob pa))
      )
      (T (princ "\nSegment non valide."))
    )
  )

  ;; Fonction principale
  (vla-StartUndoMark *acdoc*)
  (while (not p1)
    (initget "3points")
    (setq e1
	   (entsel
	     "\nSélectionnez le premier segment ou [3points] <3>: "
	   )
    )
    (if	(vl-consp e1)
      (PointsFromSegment e1 'p1 'p2)
      (progn
	(initget 1)
	(setq p1 (getpoint "\nSpécifiez le sommet: "))
	(initget 1)
	(setq p2 (getpoint p1 "\nSpécifiez le second point: "))
	(while (equal p1 p2 1e-9)
	  (setq
	    p2 (getpoint
		 p1
		 "Points confondus.\nSpécifiez le second point: "
	       )
	  )
	)
	(setq p3 (getpoint p1 "\nSpécifiez le troisième point: "))
	(while (or (equal p1 p3 1e-9) (equal p2 p3 1e-9))
	  (setq
	    p3 (getpoint
		 p1
		 "Points confondus.\nSpécifiez le troisième point: "
	       )
	  )
	)
	(setq st (trans p1 1 0)
	      p2 (trans p2 1 0)
	      p3 (trans p3 1 0)
	      v1 (gc:Normalize (mapcar '- p2 st))
	      v2 (gc:Normalize (mapcar '- p3 st))
	)
      )
    )
  )
  (while (not p3)
    (initget 1)
    (setq e2
	   (entsel
	     "\nSélectionnez le second segment: "
	   )
    )
    (PointsFromSegment e2 'p3 'p4)
  )
  (if st
    (gc:grDrawLine st (gc:Normalize (mapcar '+ v1 v2)))
    (if	(setq st (inters p1 p2 p3 p4 nil))
      (progn
	(setq v1 (gc:Normalize (mapcar '- p1 st))
	      v2 (gc:Normalize (mapcar '- p3 st))
	)
	(gc:grDrawLine st (gc:Normalize (mapcar '+ v1 v2)))
      )
      (princ "\nSegments non sécants")
    )
  )
  (*error* nil)
)

;;====================================================================;;

;; MED -Gilles Chanteau- (maj 12/06/10)
;; Dessiner une ligne sur la médiatrice du segment défini par 2 points
;; La longueur de la ligne est entrée au clavier ou à l'aide du pointeur.

(defun c:med (/ *error* pt1 pt2 mid vec)
  (vl-load-com)
  (or *acdoc*
      (setq *acdoc* (vla-get-ActiveDocument (vlax-get-acad-object)))
  )

  (defun *error* (msg)
    (and msg
	 (/= msg "Fonction annulée")
	 (princ (strcat "\nErreur: " msg))
    )
    (grtext)
    (vla-EndUndoMark *acdoc*)
    (princ)
  )

  (vla-StartUndoMark *acdoc*)
  (initget 1)
  (setq pt1 (getpoint "\nPremier point: "))
  (initget 1)
  (setq	pt2 (getpoint pt1 "\nSecond point: ")
	mid (mapcar (function (lambda (x1 x2) (/ (+ x1 x2) 2.)))
		    pt1
		    pt2
	    )
	vec (mapcar '- pt2 pt1)
  )
  (if (and (equal (car pt1) (car pt2) 1e-9) (equal (cadr pt1) (cadr pt2) 1e-9))
    (princ
      "Le segment est perpendiculaire au plan du SCU courant."
    )
    (gc:grDrawLine
      (trans mid 1 0)
      (gc:Normalize (trans (list (- (cadr vec)) (car vec) 0.) 1 0 T))
    )
  )
  (*error* nil)
  (princ)
)

;;====================================================================;;

;; PER -Gilles Chanteau- (maj 12/06/10)
;; Dessiner des lignes perpendiculaires au segment spécifié ou défini par 2 points
;; La longueur de chaque ligne est entrée au clavier ou à l'aide du pointeur.

(defun c:per (/ *error* PointsFromSegment ent p1 p2 vec pt)
  (vl-load-com)
  (or *acdoc*
      (setq *acdoc* (vla-get-ActiveDocument (vlax-get-acad-object)))
  )

  ;; Redéfiniton de *error*
  (defun *error* (msg)
    (and msg
	 (/= msg "Fonction annulée")
	 (princ (strcat "\nErreur: " msg))
    )
    (grtext)
    (vla-EndUndoMark *acdoc*)
    (princ)
  )

  ;; Points par segment
  (defun PointsFromSegment (e1 sym1 sym2 / ob pt pa vc)
    (setq ob (vlax-ename->vla-object (car e1)))
    (cond
      ((= (vla-get-ObjectName ob) "AcDbLine")
       (set sym1 (trans (osnap (cadr e1) "_nea") 1 0))
       (set sym2 (vlax-get ob 'StartPoint))
      )
      ((member (vla-get-ObjectName ob) '("AcDbRay" "AcDbXline"))
       (setq pt	(trans (osnap (cadr e1) "_nea") 1 0)
	     vc	(vlax-get ob 'DirectionVector)
       )
       (set sym1 pt)
       (set sym2 (mapcar '+ pt vc))
      )
      ((and (member (vla-get-ObjectName ob)
		    '("AcDbPolyline" "AcDb2dPolyline")
	    )
	    (setq pt (vlax-curve-getClosestPointToProjection
		       ob
		       (trans (cadr e1) 1 0)
		       (getvar 'viewdir)
		     )
	    )
	    (setq pa (fix (vlax-curve-getParamAtPoint ob pt)))
	    (= 0 (vla-GetBulge ob pa))
       )
       (set sym1 pt)
       (set sym2 (vlax-curve-getPointAtParam ob pa))
      )
      ((= (vla-get-ObjectName ob) "AcDb3dPolyline")
       (setq pt	(trans (osnap (cadr e1) "_nea") 1 0)
	     pa	(fix (vlax-curve-getParamAtPoint ob pt))
       )
       (set sym1 pt)
       (set sym2 (vlax-curve-getPointAtParam ob pa))
      )
      (T (princ "\nSegment non valide."))
    )
  )

  ;; Fonction principale
  (vla-StartUndoMark *acdoc*)
  (while (not p1)
    (initget "2points")
    (setq ent
	   (entsel
	     "\nSélectionnez le segment de référence ou [2points] <2>: "
	   )
    )
    (if	(vl-consp ent)
      (progn
	(PointsFromSegment ent 'p1 'p2)
	(if p1
	  (setq	p1 (trans p1 0 1)
		p2 (trans p2 0 1)
	  )
	)
      )
      (progn
	(initget 1)
	(setq p1 (getpoint "\nSpécifiez le premier point: "))
	(initget 1)
	(setq p2 (getpoint p1 "\nSpécifiez le second point: "))
	(while (equal p1 p2 1e-9)
	  (setq
	    p2 (getpoint
		 p1
		 "Points confondus.\nSpécifiez le second point: "
	       )
	  )
	)
      )
    )
  )
  (if p1
    (if	(and (equal (car p1) (car p2) 1e-9) (equal (cadr p1) (cadr p2) 1e-9))
      (princ
	"La droite de référence est perpendiculaire au plan du SCU courant."
      )
      (progn
	(setq vec (mapcar '- p2 p1)
	      vec (gc:Normalize
		    (trans (list (- (cadr vec)) (car vec) 0.0) 1 0 T)
		  )
	)
	(while (setq pt (getpoint "\nSpécifiez un point: "))
	  (gc:grDrawLine (trans pt 1 0) vec)
	)
      )
    )
  )
  (*error* nil)
)

;;====================================================================;;

;; TAN -Gilles Chanteau- (maj 12/06/10)
;; Dessiner des lignes tangentes à la courbe spécifiée
;; La longueur de chaque ligne est entrée au clavier ou à l'aide du pointeur.

(defun c:tan (/ obj)
  (vl-load-com)
  (or *acdoc*
      (setq *acdoc* (vla-get-ActiveDocument (vlax-get-acad-object)))
  )

  ;; Redéfiniton de *error*
  (defun *error* (msg)
    (and msg
	 (/= msg "Fonction annulée")
	 (princ (strcat "\nErreur: " msg))
    )
    (grtext)
    (vla-EndUndoMark *acdoc*)
    (princ)
  )

  ;; Fonction principale
  (vla-StartUndoMark *acdoc*)
  (if (and
	(setq obj (car (entsel "\nSélectionnez une courbe: ")))
	(not
	  (vl-catch-all-error-p
	    (vl-catch-all-apply 'vlax-curve-getEndParam (list obj))
	  )
	)
      )
    (while (setq pt (getpoint "\nSpécifiez le point de départ: "))
      (if (setq	pa
		 (vlax-curve-getParamAtPoint obj (setq pt (trans pt 1 0)))
	  )
	(gc:grDrawLine
	  pt
	  (gc:Normalize (vlax-curve-getFirstDeriv obj pa))
	)
      )
    )
    (princ "\nEntité non valide")
  )
  (*error* nil)
)

;;====================================================================;;

;; gc:grDrawLine (gile)
;; Utilisation de grread pour dessiner une ligne à partir d'un point et
;; d'un vecteur directeur
;;
;; Arguments
;; startPt : point de départ de la ligne (coordonnées SCG)
;; direction : vecteur directeur de la ligne (coordonnées SCG)

(defun gc:grDrawLine (startPt direction / dist pt ratio line elst loop)
  (if (/= 0
	  (setq	dist (distance (gc:UCSProjectAboutView '(0 0 0))
			       (gc:UCSProjectAboutView direction)
		     )
	  )
      )
    (progn
      (setq
	;; projection du point sur le plan du SCU
	pt    (trans (gc:UCSProjectAboutView startPt) 0 1)

	;; rapport entre la longueur du vecteur et celle de sa projection sur le SCU
	ratio (/ 1 dist)
	;; ligne de longueur 0
	line  (entmakex
		(list
		  '(0 . "LINE")
		  (cons 10 startPt)
		  (cons 11 startPt)
		)
	      )
	elst  (entget line)
	loop  T
      )
      (princ "\nSpécifiez la longueur ou [annUler]: ")

      (if
	(vl-catch-all-error-p
	  (vl-catch-all-apply
	    '(lambda (/ gr len end str)
	       (while
		 (and (setq gr (grread T 12 0)) (/= (car gr) 3) loop)
		  (cond
		    ;; modification de la ligne en fonction de la position du pointeur
		    ((= 5 (car gr))
		     (if (minusp
			   (gc:DotProduct
			     (gc:3dTo2dPoint (trans direction 0 2 T))
			     (gc:3dTo2dPoint (trans (mapcar '- (cadr gr) pt) 1 2 T))
			   )
			 )
		       (setq direction (mapcar '- direction))
		     )
		     (setq len (* ratio (distance pt (cadr gr)))
			   end (mapcar
				 (function
				   (lambda (x1 x2)
				     (+ x1 (* len x2))
				   )
				 )
				 startPt
				 direction
			       )
		     )
		     (entmod (subst (cons 11 end)
				    (assoc 11 elst)
				    elst
			     )
		     )

		     ;; affichage dynamique de la longueur dans la barre d'état
		     (grtext -1 (rtos len))
		    )

		    ;; clic droit
		    ((member (car gr) '(11 25))
		     (entdel line)
		     (setq loop	nil
			   line	nil
		     )
		    )

		    ;; Entrée ou Espace
		    ((member (cadr gr) '(13 32))
		     (cond
		       ;; longueur valide
		       ((and str (numberp (distof str)))
			(setq end  (mapcar
				     (function
				       (lambda (x1 x2)
					 (+ x1 (* (distof str) x2))
				       )
				     )
				     startPt
				     direction
				   )
			      loop nil
			)
			(entmod	(subst (cons 11 end)
				       (assoc 11 elst)
				       elst
				)
			)
		       )

		       ;; annUler
		       ((= (strcase str) "U")
			(entdel line)
			(setq loop nil
			      line nil
			)
		       )

		       ;; entrée non valide
		       (T
			(princ
			  "\nNécessite un nombre valide ou une saisie au pointeur.
				     \nSpécifiez la longueur ou [annUler]: "
			)
			(setq str "")
		       )
		     )
		    )

		    ;; Récupération des entrée au clavier
		    (T
		     ;; retour/effacer
		     (if (= (cadr gr) 8)
		       (or
			 (and
			   str
			   (/= str "")
			   (setq str (substr str 1 (1- (strlen str))))
			   (princ (chr 8))
			   (princ (chr 32))
			 )
			 (setq str nil)
		       )
		       (or
			 (and str
			      (setq str (strcat str (chr (cadr gr))))
			 )
			 (setq str (chr (cadr gr)))
		       )
		     )

		     ;; affichage sur la ligne commande
		     (and str (princ (chr (cadr gr))))
		    )
		  )
	       )
	     )
	  )
	)
	 (and (entdel line) (setq line nil))
      )
    )
    (princ "\nLa direction est perpendiculaire à la vue")
  )
  (grtext)
  line
)

;;====================================================================;;

;;gc:3dTo2dPoint
;; Retourne le point 2d (x y)
;;
;; Argument: un point 3d (x y z)

(defun gc:3dTo2dPoint (p) (list (car p) (cadr p)))

;;====================================================================;;

;;gc:DotProduct Retourne le produit scalaire (réel) de deux vecteurs

(defun gc:DotProduct (v1 v2)
  (apply '+ (mapcar '* v1 v2))
)

;;====================================================================;;

;;; gc:Normalize Retourne le vecteur unitaire d'un vecteur

(defun gc:Normalize (v)
  ((lambda (l)
     (if (/= 0 l)
       (mapcar (function (lambda (x) (/ x l))) v)
     )
   )
    (distance '(0 0 0) v)
  )
)

;;====================================================================;;

;;; gc:IntersLinePlane Retourne le point d'intersection de la droite définie par p1 p2
;;; et du plan défini par un point et sa normale.

(defun gc:IntersLinePlane (p1 p2 org nor / scl)
  (if (and
	(/= 0 (setq scl (gc:DotProduct nor (mapcar '- p2 p1))))
	(setq scl (/ (gc:DotProduct nor (mapcar '- p1 org)) scl))
      )
    (mapcar (function (lambda (x1 x2) (+ (* scl (- x1 x2)) x1)))
	    p1
	    p2
    )
  )
)

;;====================================================================;;

;; gc:UCSProjectAboutView
;; Projette un point sur le plan du SCU courant suivant la vue courante
;;
;; Argument
;; pt : le point à projeter (coordonneés SCG)
;;
;; Retour : le point sur le plan du SCU courant (coordonneés SCG)

(defun gc:UCSProjectAboutView (pt)
  (gc:IntersLinePlane
    pt
    ((lambda (p)
       (trans
	 (list (car p) (cadr p) (1+ (caddr p)))
	 2
	 0
       )
     )
      (trans pt 0 2)
    )
    (trans '(0 0 0) 1 0)
    (trans '(0 0 1) 1 0 T)
  )
)