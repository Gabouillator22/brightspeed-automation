;;---------------------------- Définition de bloc ----------------------------;;

;; gc:GetBlockTableRecord
;; Renvoie le BlockTableRecord (BLOCK_RECORD).
;;
;; Argument
;; blockName : nom du bloc (STR)
(defun gc:GetBlockTableRecord (blockName / blk)
  (if (setq blk (tblobjname "BLOCK" blockName))
    (cdr (assoc 330 (entget blk)))
  )
)

;; gc:IsReferenced
;; Evalue si le bloc est référencé.
;;
;; Argument
;; blockName : nom du bloc (STR)
(defun gc:IsReferenced (blockName / btr brs)
  (and
    (setq btr (gc:GetBlockTableRecord blockName))
    (setq brs (vl-remove nil (mapcar 'entget (gc:massoc 331 (entget btr)))))
    (vl-some 'vl-consp (mapcar '(lambda (x) (entget (cdr (assoc 330 x)))) brs))
  )
)

;; gc:PurgeBlock
;; Purge les blocs dont le nom correspond au modèle (insensible à la casse)
;;
;; Argument
;; pattern : un modèle pour le nom de bloc (STR),
;;           accepte les caractères génériques ("*" pour tous)
(defun gc:PurgeBlock (pattern / blk name blst loop)
  (vl-load-com)
  (setq pattern (strcase pattern))
  (while (setq blk (tblnext "BLOCK" (not blk)))
    (if
      (and
	(wcmatch (strcase (setq name (cdr (assoc 2 blk)))) pattern)
	(< (cdr (assoc 70 (setq elst (entget (tblobjname "BLOCK" name))))) 4)
      )
       (setq blst (cons (cdr (assoc 330 elst)) blst))
    )
  )
  (setq loop T)
  (while (and loop blst)
    (setq loop nil)
    (foreach b blst
      (or (vl-some 'entget (gc:massoc 331 (entget b)))
	  (progn
	    (setq blk (vlax-ename->vla-object b))
	    (vlax-for o	blk
	      (if (= (vla-get-ObjectName o) "AcDbBlockReference")
		(vla-Delete o)
	      )
	    )
	    (vla-delete blk)
	    (setq blst (vl-remove b blst))
	    (setq loop T)
	  )
      )
    )
  )
)

;; gc:GetReferences
;; Renvoie la liste des références de bloc non effacées
;;
;; Arguments
;; blockName : nom du bloc (STR)
;; flag      : drapeau (INT)
;;             somme des codes binaires suivants
;;	       1 = imbriqués dans des blocs
;;	       2 = insérés dans l'espace objet
;;             4 = insérés dans un espace papier
(defun gc:GetReferences	(blockName flag / btr refs elst)
  (if
    (and
      (setq btr (gc:GetBlockTableRecord blockName))
      (setq refs
	     (vl-remove-if-not
	       'cdr
	       (mapcar
		 (function
		   (lambda (x)
		     (if (setq elst (entget x))
		       (cons x (entget (cdr (assoc 330 elst))))
		     )
		   )
		 )
		 (gc:massoc 331 (entget btr))
	       )
	     )
      )
    )
     (if (= 7 flag)
       (mapcar 'car refs)
       (if (< 0 flag 7)
	 (mapcar 'car
		 (vl-remove-if
		   (function
		     (lambda (x)
		       (wcmatch
			 (strcase (cdr (assoc 2 (cdr x))))
			 (cond
			   ((= 1 flag) "`**_SPACE*")
			   ((= 2 flag) "~`*MODEL_SPACE")
			   ((= 3 flag) "`*PAPER_SPACE*")
			   ((= 4 flag) "~`*PAPER_SPACE*")
			   ((= 5 flag) "`*MODEL_SPACE*")
			   ((= 6 flag) "~`**_SPACE*")
			 )
		       )
		     )
		   )
		   refs
		 )
	 )
       )
     )
  )
)

;; gc:GetAttributeDefinitions
;; Renvoie la liste des données DXF de toutes les définitions d'attribut
;;
;; Argumen
;; blockname : nom du bloc (STR)
(defun gc:GetAttributeDefinitions (blockname / blockdef ent elst attdefs)
  (if
    (and (setq blockdef (tblsearch "BLOCK" blockname))
	 (setq ent (cdr (assoc -2 blockdef)))
    )
     (while ent
       (setq elst (entget ent))
       (if (and	(= (cdr (assoc 0 elst)) "ATTDEF")
		(zerop (logand 2 (cdr (assoc 70 elst))))
	   )
	 (setq attdefs (cons elst attdefs))
       )
       (setq ent (entnext ent))
     )
  )
  attdefs
)

;;---------------------------- Bloc dynamique ----------------------------;;

;; gc:IsDynamicBlock
;; Evalue si le nom correspond à un bloc dynamique.
;;
;; Argument
;; blockName : nom du bloc (STR)
(defun gc:IsDynamicBlock (blockName / btr xdict)
  (and (setq btr (gc:GetBlockTableRecord blockName))
       (setq xdict (cdr
		     (assoc 360
			    (member '(102 . "{ACAD_XDICTIONARY") (entget btr))
		     )
		   )
       )
       (dictsearch xdict "ACAD_ENHANCEDBLOCK")
  )
)

;; gc:GetEffectiveName
;; Renvoie le nom de la définition d'un block dynamique
;;
;; Argument
;; br : nom d'entité de la référence de bloc (ENAME)
(defun gc:GetEffectiveName (br / elst name xdict blkrep repdata btr)
  (setq	elst (entget br)
	name (cdr (assoc 2 elst))
  )
  (if
    (and
      (wcmatch name "`*U*")
      (setq xdict (cdr (assoc 360 (member '(102 . "{ACAD_XDICTIONARY") elst))))
      (setq blkRep (cdr (assoc 360 (member '(3 . "AcDbBlockRepresentation") (entget xdict)))))
      (setq repData (cdr (assoc 360 (member '(3 . "AcDbRepData") (entget blkRep)))))
      (setq btr (cdr (assoc 340 (entget repData))))
    )
     (setq name (cdr (assoc 2 (entget btr))))
  )
  name
)

;; gc:GetAnonymousBlocks
;; Renvoie la liste des blocs anonymes (*Uxxx) dont le nom effectif est blockName.
;;
;; Argument
;; blockName : nom du bloc de base (STR)
(defun gc:GetAnonymousBlocks (blockName / block handle blk name xdata lst)
  (if
    (and
      (setq block (tblobjname "block" blockName))
      (setq handle (cdr (assoc 5 (entget (cdr (assoc 330 (entget block)))))))
    )
     (while (setq blk (tblnext "block" (not blk)))
       (if
	 (and
	   (setq name (cdr (assoc 2 blk)))
	   (wcmatch name "`*U*")
	   (setq xdata (assoc -3
			      (entget (cdr (assoc 330 (entget (tblobjname "block" name))))
				      '("AcDbBlockRepBTag")
			      )
		       )
	   )
	   (= handle (cdr (assoc 1005 (cdadr xdata))))
	 )
	  (setq lst (cons name lst))
       )
     )
  )
  (reverse lst)
)

;; gc:GetDynamicBlockReferences
;; Renvoie la liste des références de bloc dynamiques non effacées
;;
;; Arguments
;; blockName : nom du bloc (STR)
;; flag      : drapeau (INT)
;;             somme des codes binaires suivants
;;	       1 = imbriqués dans des blocs
;;	       2 = insérés dans l'espace objet
;;             4 = insérés dans un espace papier
(defun gc:GetDynamicBlockReferences (blockName flag)
  (apply 'append
	 (mapcar '(lambda (n) (gc:GetReferences n flag))
		 (cons blockName (gc:GetAnonymousBlocks blockName))
	 )
  )
)

;; gc:GetDynBlockRecord
;; Renvoie la liste DXF de la définition du bloc de base (BLOCK_RECORD).
;;
;; Argument
;; blockRef: référence de bloc (ENAME)
(defun gc:GetDynBlockRecord (blockRef / elst xDictionary blockRep repData blockRecord block)
  (if (= (cdr (assoc 0 (setq elst (entget blockRef)))) "INSERT")
    (if	(and (setq xDictionary (cdr (assoc 360 (member '(102 . "{ACAD_XDICTIONARY") elst))))
	     (setq blockRep
		    (cdr (assoc 360 (member '(3 . "AcDbBlockRepresentation") (entget xDictionary))))
	     )
	)
      (setq repData	(cdr (assoc 360 (member '(3 . "AcDbRepData") (entget blockRep))))
	    blockRecord	(entget (cdr (assoc 340 (entget repData))))
      )
      (setq block	(entget (tblobjname "block" (cdr (assoc 2 elst))))
	    blockRecord	(entget (cdr (assoc 330 block)))
      )
    )
  )
)

;; gc:GetDynPropParams
;; Renvoie une liste de sous-listes, une pour chaque paramètre dynamique
;; (parameterType parameterName1 [parameterName2] [(valueNames ...)])
;;
;; Argument
;; blockRecord : définition du bloc (BLOCK_RECORD)
(defun gc:GetDynPropParams (blockRecord / xDictionary enhancedBlock elst param)
  (if (and (setq xDictionary (cdr (assoc 360 (member '(102 . "{ACAD_XDICTIONARY") blockRecord))))
	   (setq enhancedBlock
		  (cdr (assoc 360 (member '(3 . "ACAD_ENHANCEDBLOCK") (entget xDictionary))))
	   )
      )
    (vl-remove
      nil
      (mapcar
	'(lambda (prop / elst)
	   (setq elst  (entget prop)
		 param (cdr (assoc 0 elst))
	   )
	   (cond
	     ((= param "BLOCKPOINTPARAMETER")
	      (list param
		    (cdr (assoc 303 elst))
	      )
	     )
	     ((= param "BLOCKLINEARPARAMETER")
	      (list param
		    (cdr (assoc 305 elst))
		    (list (cdr (assoc 141 elst)) (cdr (assoc 142 elst)) (cdr (assoc 143 elst)))
		    (gc:massoc 144 elst)
	      )
	     )
	     ((= param "BLOCKPOLARPARAMETER")
	      (list param
		    (cdr (assoc 305 elst))
		    (list (cdr (assoc 141 elst)) (cdr (assoc 142 elst)) (cdr (assoc 143 elst)))
		    (gc:massoc 144 elst)
		    (cdr (assoc 307 elst))
		    (list (cdr (assoc 145 elst)) (cdr (assoc 146 elst)) (cdr (assoc 147 elst)))
		    (gc:massoc 148 elst)
	      )
	     )
	     ((= param "BLOCKXYPARAMETER")
	      (list param
		    (cdr (assoc 305 elst))
		    (list (cdr (assoc 146 elst)) (cdr (assoc 147 elst)) (cdr (assoc 148 elst)))
		    (gc:massoc 149 elst)
		    (cdr (assoc 306 elst))
		    (list (cdr (assoc 142 elst)) (cdr (assoc 143 elst)) (cdr (assoc 144 elst)))
		    (gc:massoc 145 elst)
	      )
	     )
	     ((= param "BLOCKROTATIONPARAMETER")
	      (list param
		    (cdr (assoc 305 elst))
		    (list (cdr (assoc 141 elst)) (cdr (assoc 142 elst)) (cdr (assoc 143 elst)))
		    (gc:massoc 144 elst)
	      )
	     )
	     ((= param "BLOCKFLIPPARAMETER")
	      (list param
		    (cdr (assoc 305 elst))
		    (list (cdr (assoc 307 elst)) (cdr (assoc 308 elst)))
	      )
	     )
	     ((= param "BLOCKVISIBILITYPARAMETER")
	      (list param
		    (cdr (assoc 301 elst))
		    (gc:massoc 303 elst)
	      )
	     )
	     ((= param "BLOCKLOOKUPPARAMETER")
	      (list param
		    (cdr (assoc 303 elst))
	      )
	     )
	     ((= param "BLOCKALIGNMENTPARAMETER")
	      (list param
		    (cdr (assoc 300 elst))
		    (cdr (assoc 1010 elst))
		    (cdr (assoc 1011 elst))
		    (cdr (assoc 280 (member '(100 . "AcDbBlockAlignmentParameter") elst)))
	      )
	     )
	   )
	 )
	(gc:massoc 360 (entget enhancedBlock))
      )
    )
  )
)

;;---------------------------- Référence de bloc ----------------------------;;

;; gc:IsAssociativeArray
;; Renvoie T, si le ename passé en argument est celui d'un réseau associatif ; nil, sinon.
;;
;; Argument
;; br: ename de l'entité (ENAME)
(defun gc:IsAssociativeArray (br)
  (wcmatch (getpropertyvalue br "ClassName") "AcDbAssociative*Array")
)

;; gc:GetBlockTableRecordName
;; Obtient le nom effectif d'une référence de bloc (dynamique ou statique)
;; Renvoie nil si br n'est pas une référence de bloc
;;
;; Argument
;; br: ename de l'entité (ENAME)
(defun gc:GetBlockTableRecordName (br)
  (if
    (and
      (= (cdr (assoc 0 (entget br))) "INSERT")
      (not (gc:IsAssociativeArray br))
    )
     (getpropertyvalue
       (getpropertyvalue br "BlockTableRecord")
       "Name"
     )
  )
)

;; gc:GetAttributeValue
;; Renvoie la valeur d'attribut ou nil, si non trouvé.
;;
;; Arguments
;; block : nom d'entité du bloc (ENAME)
;; tag   : étiquette de l'attribut (STR)
(defun gc:GetAttributeValue (block tag / value)
  (vl-catch-all-apply
    '(lambda () (setq value (getpropertyvalue block tag)))
  )
  value
)

;; gc:SetAttributeValue
;; Définit la valeur de l'attribut. Renvoie T en cas de succès, nil en cas d'échec.
;;
;; Arguments
;; block : nom d'entité du bloc (ENAME)
;; tag   : étiquette de l'attribut (STR)
;; value : valeur de l'attribut (STR)
(defun gc:SetAttributeValue (block tag value)
  (not
    (vl-catch-all-error-p
      (vl-catch-all-apply
	'(lambda ()
	   (setpropertyvalue block tag value)
	 )
      )
    )
  )
)

;; gc:GetDynPropValue
;; Renvoie la valeur de la propriété dynamique ou nil, si non trouvée.
;;
;; Arguments
;; block    : nom d'entité du bloc (ENAME)
;; propName : nom de la propriété dynamique (STR)
(defun gc:GetDynPropValue (block propName / value)
  (vl-catch-all-apply
    '(lambda ()
       (setq value (getpropertyvalue block (strcat "AcDbDynBlockProperty" propName)))
     )
  )
  value
)

;; gc:SetDynPropValue
;; Définit la valeur de la propriété dynamique. Renvoie T en cas de succès, nil en cas d'échec.
;;
;; Arguments
;; block    : nom d'entité du bloc (ENAME)
;; propName : nom de la propriété dynamique (STR)
;; value    : valeur de la propriété dynamique (INT, REAL ou STR)
(defun gc:SetDynPropValue (block propName value)
  (not
    (vl-catch-all-error-p
      (vl-catch-all-apply
	'(lambda ()
	   (setpropertyvalue block (strcat "AcDbDynBlockProperty" propName) value)
	 )
      )
    )
  )
)

;; gc:InsertBlockReference
;; Insére une référence bloc sans attribut.
;; Renvoie le ename de la référence insérée ou nil.
;;
;; arguments :
;; blockname : nom du bloc (STR)
;; position  : point d'insertion ((REAL REAL [REAL]))
;; rotation  : rotation (REAL)
;; scale     : échelle globale (REAL)
(defun gc:InsertBlockReference (blockname position rotation scale)
  (if (setq blockdef (tblsearch "BLOCK" blockname))
    (entmakex
      (list
	(cons 0 "INSERT")
	(cons 100 "AcDbEntity")
	(cons 100 "AcDbBlockReference")
	(cons 2 blockname)
	(cons 10 position)
	(cons 41 scale)
	(cons 42 scale)
	(cons 43 scale)
	(cons 50 rotation)
      )
    )
  )
)

;; gc:InsertAttributedBlockReference
;; Insére une référence bloc et éventuellement ses attributs.
;; Renvoie le ename de la référence insérée ou nil.
;;
;; arguments :
;; blockname : nom du bloc (STR)
;; position  : point d'insertion ((REAL REAL [REAL]))
;; rotation  : rotation (REAL)
;; scale     : échelle globale (REAL)
;; attribs   : liste de paires pointées étiquette valeur (STR . STR) ou nil (LIST)
(defun gc:InsertAttributedBlockReference (
					  blockname
					  position
					  rotation
					  scale
					  attribs
					  /
					  mxv
					  rotvec
					  blockdef ; liste dxf de la définition de bloc
					  ent ; une entité
					  elst ; une liste dxf
					  attdefs ; liste des listes dxf des définitions d'attribut
					  blockref ; référence de bloc
					  tag ; étiquette d'attribut
					  vec ; déplacement du point d'alignement par rapport au point d'insertion
					  pt ; point d'alignement
					  ht ; hauteur de texte
					  val ; valeur d'attribut
					 )

  ;; on contrôle si la table des block contient une définition de bloc nommée 'blockname'
  (if (setq blockdef (tblsearch "BLOCK" blockname))
    (progn

      ;; collecte les définitons d'attribut dans la définition de bloc
      (setq attdefs (gc:GetAttributeDefinitions blockName))

      ;; si aucune définition d'attribut n'a été trouvée,
      (if (null attdefs)
	;; alors, création de la réference de bloc
	(setq blockref (gc:InsertBlockReference blockname position rotation scale))
	;; sinon, création de la réference de bloc et des références d'attribut
	(progn

	  ;; MXV
	  ;; Applique une matrice de transformation à un vecteur -Vladimir Nesterovsky-
	  ;;
	  ;; Arguments-
	  ;; m : une matrice
	  ;; v : un vecteur
	  (defun mxv (m v)
	    (mapcar (function (lambda (r) (apply '+ (mapcar '* r v)))) m)
	  )

	  ;; ROTSCALEVEC
	  ;; Applique une rotation 2d et une échelle à un vecteur
	  ;;
	  ;; Arguments
	  ;; v : vecteur
	  ;; a : angle en radians
	  ;; s : échelle
	  (defun rotscalevec (v a s)
	    (mxv (list (list (* s (cos a)) (* s (- (sin a))) 0.)
		       (list (* s (sin a)) (* s (cos a)) 0.)
		       '(0. 0. 1.)
		 )
		 v
	    )
	  )

	  (entmake
	    (list
	      (cons 0 "INSERT")
	      (cons 100 "AcDbEntity")
	      (cons 100 "AcDbBlockReference")
	      (cons 66 1)
	      (cons 2 blockname)
	      (cons 10 position)
	      (cons 41 scale)
	      (cons 42 scale)
	      (cons 43 scale)
	      (cons 50 rotation)
	    )
	  )
	  ;; création les definitions d'attributs
	  (foreach attdef attdefs
	    (setq tag (cdr (assoc 2 attdef))
		  vec (if (= (cdr (assoc 72 attdef)) (cdr (assoc 74 attdef)) 0)
			(rotscalevec (cdr (assoc 10 attdef)) rotation scale) ; bas gauche
			(rotscalevec (cdr (assoc 11 attdef)) rotation scale) ; autre
		      )
		  pt  (mapcar '+ position vec)
		  ht  (* scale (cdr (assoc 40 attdef)))
		  val (cond ((cdr (assoc tag attribs))) ; valeur dans la liste 'attribs'
			    (T (cdr (assoc 1 attdef))) ; valeur par défaut
		      )
	    )
	    (entmake
	      (vl-remove nil
			 (list
			   (cons 0 "ATTRIB") ; type d'entité
			   (cons 100 "AcDbEntity")
			   (assoc 8 attdef) ; calque
			   (assoc 62 attdef) ; couleur
			   (assoc 6 attdef) ; type de ligne
			   (assoc 370 attdef) ; épaisseur de ligne
			   (cons 100 "AcDbText")
			   (cons 10 pt)	; point d'insertion
			   (cons 40 ht)	; hauteur de texte
			   (cons 1 val)	; valeur d'attribut
			   (cons 50 rotation) ; rotation
			   (assoc 41 attdef) ; facteur de largeur
			   (assoc 51 attdef) ; inclinaison
			   (assoc 7 attdef) ; style de texte
			   (assoc 71 attdef) ; génération de texte
			   (assoc 72 attdef) ; justification horizontale
			   (cons 11 pt)	; point d'alignement
			   (assoc 210 attdef) ; direction d'extrusion
			   (cons 100 "AcDbAttribute")
			   (assoc 280 attdef) ; numéro de version
			   (cons 2 tag)	; étiquette
			   (assoc 70 attdef) ; drapeaux d'attribut
			   (assoc 73 attdef) ; style d'espacement des lignes de l'entité MTEXT
			   (assoc 74 attdef) ; justification verticale du texte
			   (assoc 280 (reverse attdef)) ; verrouillage de la position
			 )
	      )
	    )
	  )
	  ;; création de l'objet SEQEND
	  (entmake '((0 . "SEQEND")))
	  (setq blockref (entlast))
	)
      )
    )
  )
  ;; valeur de retour
  blockref
)

;;---------------------------- Référence d'attribut ----------------------------;;

;;; gc:GetAttribs
;;; Renvoie la liste de toutes les références d'attribut de la référence de bloc.
;;;
;;; Argument
;;; ename : nom d'entité de la référence de bloc (ENAME)
(defun gc:GetAttribs (ename)
  (if (and (setq ename (entnext ename))
	   (= (cdr (assoc 0 (entget ename))) "ATTRIB")
      )
    (cons ename (gc:getAttribs ename))
  )
)

;;; gc:MapAttribs
;;; Renvoie la liste des résultats de l'application de la fonction de projection
;;; sur chaque référence d'attribut de la référence de bloc.
;;;
;;; Arguments
;;; fun : fonction de projection à appliquer à chaque référence d'attribut (SUBR ou USUBR)
;;; br  : nom d'entité de la référence de bloc (ENAME)
(defun gc:MapAttribs (fun br / loop)
  (defun loop (fun ent)
    (if	(and (setq ent (entnext ent))
	     (= (cdr (assoc 0 (entget ent))) "ATTRIB")
	)
      (cons (fun ent) (loop fun ent))
    )
  )
  (loop (eval fun) br)
)

;;; gc:GetAttribsByTag
;;; Renvoie la liste de toutes les références d'attribut de la référence de bloc
;;; par étiquette sous la forme d'une liste de paires pointées (étiquette . nomEntité).
;;;
;;; Argument
;;; br : nom d'entité de la référence de bloc (ENAME)
(defun gc:GetAttribsByTag (br)
  (gc:MapAttribs
    '(lambda (x) (cons (getpropertyvalue x "Tag") x))
    br
  )
)

;;; gc:GetAttribValues
;;; Renvoie la liste de toutes les valeurs de références d'attribut de la référence de bloc
;;; sous la forme d'une liste de paires pointées (étiquette . valeur).
;;;
;;; Argument
;;; br : nom d'entité de la référence de bloc (ENAME)
(defun gc:GetAttribValues (br)
  (gc:MapAttribs
    '(lambda (x) (cons (getpropertyvalue x "Tag") (getpropertyvalue x "TextString")))
    br
  )
)

;;---------------------------- Liste d'association ----------------------------;;

;; gc:massoc
;; Renvoie la liste de toutes les valeurs pour le code spécifié dans une liste d'association
;;
;; Arguments
;; code : la clé recherchée (code de groupe pour les listes DXF)
;; alst : la liste d'association
(defun gc:massoc (code alst)
  (if (setq alst (member (assoc code alst) alst))
    (cons (cdar alst) (gc:massoc code (cdr alst)))
  )
)