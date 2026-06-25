;;; Clean_poly (gile)
;;; Supprime tous les sommets superposés des polylignes, optimisées, 2D et 3D


;;; TRUNC (gile)
;;; Retourne la liste tronquée à partir de la première occurrence
;;; de l'expression (liste complémentaire de celle retournée par MEMBER)

(defun trunc (expr lst)
  (if (and lst
	   (not (equal (car lst) expr))
      )
    (cons (car lst) (trunc expr (cdr lst)))
  )
)

;;; Fonction principale

(defun c:clean_poly (/ ent e_lst p_lst vtx1 vtx2)
  (while (not
	   (setq ent (car (entsel "\nSélectionnez une polyligne: ")))
	 )
  )
  (setq e_lst (entget ent))
  (cond
    ((= "LWPOLYLINE" (cdr (assoc 0 e_lst)))
     (setq p_lst (vl-remove-if-not
		   '(lambda (x)
		      (or (= (car x) 10)
			  (= (car x) 40)
			  (= (car x) 41)
			  (= (car x) 42)
		      )
		    )
		   e_lst
		 )
	   e_lst (vl-remove-if
		   '(lambda (x)
		      (member x p_lst)
		    )
		   e_lst
		 )
     )
     (if (= 1 (cdr (assoc 70 e_lst)))
       (while (equal (car p_lst) (assoc 10 (reverse p_lst)))
	 (setq p_lst (reverse (cdr (member (assoc 10 (reverse p_lst))
					   (reverse p_lst)
				   )
			      )
		     )
	 )
       )
     )
     (while p_lst
       (setq e_lst (append e_lst (trunc (assoc 10 (cdr p_lst)) p_lst))
	     p_lst (member (assoc 10 (cdr p_lst)) (cdr p_lst))
       )
     )
     (entmod e_lst)
    )
    ((and (= "POLYLINE" (cdr (assoc 0 e_lst)))
	  (zerop (logand 240 (cdr (assoc 70 e_lst))))
     )
     (setq e_lst (cons e_lst nil)
	   vtx1	 (entnext ent)
	   vtx2	 (entnext vtx1)
     )
     (while (= (cdr (assoc 0 (entget vtx1))) "VERTEX")
       (if (= (cdr (assoc 0 (entget vtx2))) "SEQEND")
	 (if
	   (or (not
		 (equal	(assoc 10 (entget vtx1))
			(assoc 10 (last (reverse (cdr (reverse e_lst)))))
		 )
	       )
	       (zerop (logand 1 (cdr (assoc 70 (last e_lst)))))
	   )
	    (setq e_lst (cons (entget vtx1) e_lst))
	 )
	 (if
	   (not
	     (equal (assoc 10 (entget vtx1)) (assoc 10 (entget vtx2)) 1e-9)
	   )
	    (setq e_lst (cons (entget vtx1) e_lst))
	 )
       )
       (setq vtx1 vtx2
	     vtx2 (entnext vtx1)
       )
     )
     (setq e_lst (reverse (cons (entget vtx1) e_lst)))
     (entdel ent)
     (mapcar 'entmake e_lst)
    )
    (T (princ "\nEntité non valide."))
  )
  (princ)
)