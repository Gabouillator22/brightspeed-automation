;; DIST (gile)
;; Retourne sur la ligne de commande la distance entre 2 points ou celle
;; de l'objet sélectionné (plus la distance du segment pour les polylignes).

(defun c:dist (/ p1 p2 ent obj tot par)
  (vl-load-com)
  (if (setq p1
	     (getpoint
	       "\nSpécifiez le premier point ou < Sélectionnez un objet >: "
	     )
      )
    (progn
      (while
	(not (setq p2 (getpoint p1 "Spécifiez le deuxième point: "))
	)
      )
      (princ (strcat
	       "\nDistance : "
	       (rtos (distance p1 p2))
	     )
      )
    )
    (if	(and (setq ent (entsel))
	     (not (vl-catch-all-error-p
		    (setq p2
			   (vl-catch-all-apply
			     'vlax-curve-getEndParam
			     (list (setq obj (vlax-ename->vla-object (car ent))))
			   )
		    )
		  )
	     )
	)
      (progn
	(setq tot (vlax-curve-getDistAtParam obj p2))
	(if (wcmatch (vla-get-ObjectName obj) "*Polyline")
	  (progn
	    (if	(= (vla-get-ObjectName obj) "AcDb2dPolyline")
	      (setq p1 (vlax-curve-getClosestPointToProjection
			 obj
			 (trans (cadr ent) 1 0)
			 (trans '(0 0 1) 2 0 T)
		       )
	      )
	      (setq p1 (trans (osnap (cadr ent) "_nea") 1 0))
	    )
	    (setq par (vlax-curve-getParamAtPoint obj p1))
	    (princ
	      (strcat
		"\nDistance totale : "
		(rtos tot)
		" Segment sélectionné : "
		(rtos
		  (- (vlax-curve-getDistAtParam obj (1+ (fix par)))
		     (vlax-curve-getDistAtParam obj (fix par))
		  )
		)
	      )
	    )
	  )
	  (princ (strcat "\nDistance : " (rtos tot)))
	)
      )
      (princ "\nEntité non valide.")
    )
  )
  (princ)
)