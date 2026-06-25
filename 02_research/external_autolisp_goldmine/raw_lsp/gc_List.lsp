;; let
;; Lie des valeurs à des symboles et les passe en arguments à une expression
;; http://www.theswamp.org/index.php?topic=26792
;;
;; Arguments
;; bindings : liste de paires (symbole valeur)
;; body     : expression à évaluer
;;
;; Exemple
;; (let '((a 3) (b 5)) '(* a b))
;; => ((lambda (a b) (* a b)) 3 5)
;; => 15
(defun let (bindings body)
  (eval
    (cons
      (list 'lambda (mapcar 'car bindings) body)
      (mapcar 'cadr bindings)
    )
  )
)

;; let*
;; Lie séquentiellement des valeurs à des symboles et les passe en arguments à une expression
;; http://www.theswamp.org/index.php?topic=26792
;;
;; Arguments
;; bindings : liste de paires (symbole valeur)
;; body     : expression à évaluer
;;
;; Exemple
;; (let* '((a 3) (b (+ a 2))) '(* a b))
;; => ((lambda (a) ((lambda (b) (* a b)) (+ a 2))) 3)
;; => 15
(defun let* (bindings body / bind)
  (defun bind (bindings)
    (if	bindings
      (cons
	(list 'lambda
	      (list (caar bindings))
	      (bind (cdr bindings) )
	)
	(cdar bindings)
      )
      body
    )
  )
  (eval (bind bindings))
)

;; gc:butLast
;; Retourne la liste privée du dernier élément
;;
;; Argument
;; l : une liste
(defun gc:butLast (l) (reverse (cdr (reverse l))))

;; gc:massoc
;; Retourne la liste de toutes les valeurs pour le code spécifié dans une liste d'association
;;
;; Arguments
;; key : la clé à rechercher dans la liste
;; alst : une liste d'association
(defun gc:massoc (key alst)
  (if (setq alst (member (assoc key alst) alst))
    (cons (cdar alst) (gc:massoc key (cdr alst)))
  )
)

;; gc:breakAt
;; Retourne une liste de deux sous listes,
;; la première contenant les n premiers éléments, la seconde les éléments restants
;;
;; Arguments
;; n : le nombre d'éléments pour la première sous liste
;; l : une liste
(defun gc:breakAt (n l / r)
  (while (and l (< 0 n))
    (setq r (cons (car l) r)
	  l (cdr l)
	  n (1- n)
    )
  )
  (list (reverse r) l)
)

;; gc:take
;; Retourne les n premiers éléments de la liste
;;
;; Arguments
;; n : le nombre d'éléments
;; l : une liste
(defun gc:take (n l)
  (if (and l (< 0 n))
    (cons (car l) (gc:take (1- n) (cdr l)))
  )
)

;; gc:skip
;; Retourne la liste moins les n premiers éléments
;;
;; Arguments
;; n : le nombre d'éléments
;; l : une liste
(defun gc:skip (n l)
  (if (and l (< 0 n))
    (gc:skip (1- n) (cdr l))
    l
  )
)

;; gc:split
;; Divise une liste en sous-listes de la longueur spécifiée
;;
;; Arguments
;; n : le nombre d'éléments de chaque sous liste
;; l : une liste
(defun gc:split	(n l / s)
  (if (and l (setq s (gc:breakat n l)))
       (cons (car s) (gc:split n (cadr s)))
  )
)

;; gc:split2
;; Convertit une liste de coordonnées 2D en liste de points 2D
;;
;; Argument
;; l : une liste
(defun gc:split2 (l)
  (if l
    (cons (list (car l) (cadr l))
	  (gc:split2 (cddr l))
    )
  )
)

;; gc:split3
;; Convertit une liste de coordonnées 3D en liste de points
;;
;; Argument
;; l : une liste
(defun gc:split3 (l)
  (if l
    (cons (list (car l) (cadr l) (caddr l))
	  (gc:split3 (cdddr l))
    )
  )
)

;; gc:sublist
;; Retourne la sous liste de n éléments à partir de i
;;
;; Arguments
;; i : index du premier élément
;; n : nombre d'éléments
;; l : une liste
(defun gc:sublist (i n l)
  (gc:take n (gc:skip i l))
)

;; gc:intersect
;; Retourne la liste des éléments communs à l1 et l2
;;
;; Arguments
;; l1 : une liste
;; l2 : une liste
(defun gc:intersect (l1 l2)
  (if l1
    (if	(member (car l1) l2)
      (cons (car l1) (gc:intersect (cdr l1) l2))
      (gc:intersect (cdr l1) l2)
    )
  )
)

;; gc:substract
;; Retourne une liste contenant les éléments appartenant exclusivement à l1
;;
;; Arguments
;; l1 : une liste
;; l2 : une liste
(defun gc:substract (l1 l2)
  (if l1
    (if	(member (car l1) l2)
      (gc:substract (cdr l1) l2)
      (cons (car l1) (gc:substract (cdr l1) l2))
    )
  )
)

;; gc:distinct
;; Suprime tous les doublons d'une liste
;;
;; Argument
;; l : une liste
;;
;;https://www.theswamp.org/index.php?topic=19128.msg232513#msg232513
(defun gc:distinct (l)
  (if l
    (cons (car l) (gc:distinct (vl-remove (car l) l)))
  )
)

;; gc:removeFirst
;; Retourne la liste sans la première occurence de l'expression
;;
;; Arguments
;; ele : l'élément à supprimer
;; lst : la liste
(defun gc:removeFirst (ele lst)
  (if (equal ele (car lst))
    (cdr lst)
    (cons (car lst) (gc:removeFirst ele (cdr lst)))
  )
)

;; gc:insertAt
;; Insère l'élément dans la liste à l'indice
;;
;; Arguments
;; ele : l'élément à insérer
;; ind : l'index auquel insérer l'élément
;; lst : la liste
(defun gc:insertAt (ele ind lst)
  (cond
    ((null lst) (list ele))
    ((zerop ind) (cons ele lst))
    ((cons (car lst) (gc:insertAt ele (1- ind) (cdr lst))))
  )
)

;; gc:insertRange
;; Insère les éléments dans la liste à partir l'indice
;;
;; Arguments
;; new : la liste d'éléments à insérer
;; ind : l'index auquel insérer l'élément
;; lst : la liste
(defun gc:insertRange (new ind lst)
  (cond
    ((null lst) new)
    ((zerop ind) (append new lst))
    ((cons (car lst) (gc:insertRange new (1- ind) (cdr lst))))
  )
)

;; gc:removeAt
;; Retourne la liste privée de l'élément à l'indice spécifié
;;
;; Arguments
;; ind : l'index de l'élément à supprimer
;; lst : la liste
(defun gc:removeAt (ind lst)
  (if (or (zerop ind) (null lst))
    (cdr lst)
    (cons (car lst) (gc:removeAt (1- ind) (cdr lst)))
  )
)

;; gc:removeRange
;; Supprime le nombre d'éléments de la liste à partir de l'indice
;;
;; Arguments
;; ind : l'index à partir duquel supprimer les éléments
;; cnt : le nombre d'éléments à supprimer
;; lst : la liste
(defun gc:removeRange (from cnt lst)
  (cond
    ((or (null lst) (zerop cnt)) lst)
    ((< 0 from) (cons (car lst) (gc:removeRange (1- from) cnt (cdr lst))))
    ((gc:removeRange from (1- cnt) (cdr lst)))
  )
)

;; gc:substAt
;; Remplace l'élément à l'indice dans la liste
;;
;; Arguments
;; ele : l'élément à substituer
;; ind : l'index auquel substituer l'élément
;; lst : la liste
(defun gc:SubstAt (ele ind lst)
  (cond
    ((null lst) nil)
    ((zerop ind) (cons ele (cdr lst)))
    ((cons (car lst) (gc:substAt ele (1- ind) (cdr lst))))
  )
)

;; gc:substRange
;; Remplace les éléments de la liste à partir de l'indice
;;
;; Arguments
;; new : la liste d'éléments à substituer
;; ind : l'index à partir duquel substituer les éléments
;; lst : la liste
(defun gc:substRange (new ind lst)
  (cond
    ((or (null lst) (null new)) lst)
    ((zerop ind) (cons (car new) (gc:substRange (cdr new) ind (cdr lst))))
    ((cons (car lst) (gc:substRange new (1- ind) (cdr lst))))
  )
)

;; gc:trunc
;; Retourne la liste tronquée à partir de la première occurrence
;; de l'expression (liste complémentaire de celle retournée par MEMBER)
;;
;; Arguments
;; expr : l'expression recherchée
;; lst : la liste
(defun gc:trunc	(expr lst)
  (if (and lst
	   (not (equal (car lst) expr))
      )
    (cons (car lst) (gc:trunc expr (cdr lst)))
  )
)

;; gc:truncIf
;; Retourne la liste tronquée à partir de la première occurrence qui
;; retourne T à la fonction (complémentaire de celle retournée par VL-MEMBER-IF)
;;
;; Arguments
;; fun : la fonction prédicat
;; lst : la liste
(defun gc:truncIf (fun lst)
  (if (and lst
	   (not ((eval fun) (car lst)))
      )
    (cons (car lst) (gc:truncIf fun (cdr lst)))
  )
)

;; gc:truncFuzz
;; Comme gc:Trunc avec une tolérance dans la comparaison
;;
;; Arguments
;; expr : l'expression recherchée
;; lst : la liste
;; fuzz : la tolérance
(defun gc:truncFuzz (expr lst fuzz)
  (if (and lst
	   (not (equal (car lst) expr))
      )
    (cons (car lst) (gc:truncFuzz expr (cdr lst) fuzz))
  )
)

;;; gc:memberFuzz
;; Comme member avec une tolérance dans la comparaison
;;
;; Arguments
;; expr : l'expression recherchée
;; lst : la liste
;; fuzz : la tolérance
(defun gc:memberFuzz (expr lst fuzz)
  (while (and lst (not (equal (car lst) expr fuzz)))
    (setq lst (cdr lst))
  )
  lst
)

;; gc:str2lst
;; Transforme un chaine avec séparateur en liste de chaines
;;
;; Arguments
;; str : la chaîne
;; sep : le séparateur
(defun gc:str2lst (str sep / pos)
  (if (setq pos (vl-string-search sep str))
    (cons (substr str 1 pos) (gc:str2lst (substr str (+ (strlen sep) pos 1)) sep))
    (list str)
  )
)

;; gc:lst2str
;; Concatène une liste de chaînes et un séparateur en une chaine
;;
;; Arguments
;; lst : la liste
;; sep : le séparateur
(defun gc:lst2str (lst sep)
  (apply 'strcat
	 (cons (car lst)
	       (mapcar (function (lambda (x) (strcat sep x))) (cdr lst))
	 )
  )
)

;; gc:fold
;; Retourne l'état final d'un accumulateur dont l'état initial est modifié
;; par l'application d'une fonction à chacun des éléments d'une liste
;;
;; Arguments
;; fun : la fonction à appliquer à chaque élément
;; acc : l'accumulateur
;; lst : la liste
(defun gc:fold (fun acc lst / f)
  (setq f (eval fun))
  (foreach n lst (setq acc (f acc n)))
)

;; gc:unfold
;; Génère une liste à partir d'une fonction de calcul qui prend un état
;; et le modifie pour produire chaque élément suivant de la séquence
;;
;; Arguments
;; fun : la fonction de calculer à chaque élément
;; state : l'état initial
(defun gc:unfold (fun state)
  ((lambda (pair)
     (if pair
       (cons (car pair) (gc:unfold fun (cdr pair)))
     )
   )
    ((eval fun) state)
  )
)

;; gc:reduce
;; Retourne l'état final d'un accumulateur résultat de l'application
;; d'une fonction à chacun des éléments d'une liste
;;
;; Arguments
;; fun : la fonction à appliquer à chaque élément
;; lst : la liste
(defun gc:reduce (fun lst)
  (gc:fold fun (car lst) (cdr lst))
)

;; gc:groupBy
;; Regroupe les éléments d'une liste selon la clé générée par la fonction spécifiée.
;; Retourne un liste de sous listes dont le premier élément est la clé.
;;
;; Arguments
;; fun : la fonction génératrice de clé
;; lst : la liste
(defun gc:groupBy (fun lst / f key sub acc)
  (setq f (eval fun))
  (foreach x lst
    (setq acc
	   (if (setq sub (assoc (setq key (f x)) acc))
	     (subst (cons key (cons x (cdr sub))) sub acc)
	     (cons (list key x) acc)
	   )
    )
  )
)

;; gc:countBy
;; Compte les éléments d'une liste selon la clé générée par la fonction spécifiée.
;; Retourne un liste de paires pointées du type : (clé . nombre).
;;
;; Arguments
;; fun : la fonction génératrice de clé
;; lst : la liste
(defun gc:countBy (fun lst / f key sub acc)
  (setq f (eval fun))
  (foreach x lst
    (setq acc
	   (if (setq sub (assoc (setq key (f x)) acc))
	     (subst (cons key (1+ (cdr sub))) sub acc)
	     (cons (cons key 1) acc)
	   )
    )
  )
)

;; Partitionne les éléments d'une liste selon un prédicat.
;; Retourne un liste de deux listes dont la première contient
;; les éléments pour lesquels le prédicat est vrai.
;;
;; Arguments
;; pred : la fonction prédicat
;; lst  : la liste
(defun gc:partition (pred lst / f r)
  (setq	f (eval pred))
  (while lst
    (setq r   (if (f (car lst))
		(list (cons (car lst) (car r)) (cadr r))
		(list (car r) (cons (car lst) (cadr r)))
	      )
	  lst (cdr lst)
    )
  )
  (mapcar 'reverse r)
)

;; gc:minBy
;; Renvoie le plus petit de tous les éléments de la liste, comparés sur le résultat de la fonction.
;;
;; Arguments
;; fun : la fonction qui transforme les éléments en un type supportant la comparaison.
;; lst : la liste
(defun gc:minBy	(fun lst)
  ((lambda (l) (nth (vl-position (apply 'min l) l) lst))
    (mapcar fun lst)
  )
)

;; gc:maxBy
;; Renvoie le plus grand de tous les éléments de la liste, comparés sur le résultat de la fonction.
;;
;; Arguments
;; fun : la fonction qui transforme les éléments en un type supportant la comparaison.
;; lst : la liste
(defun gc:maxBy (fun lst)
  ((lambda (l) (nth (vl-position (apply 'max l) l) lst))
    (mapcar fun lst)
  )
)

;; gc:sortBy
;; Renvoie la liste triée en ordre croissant suivant le résultat de la fonction.
;;
;; Arguments
;; fun : la fonction qui transforme les éléments en un type supportant la comparaison.
;; lst : la liste
(defun gc:sortBy (fun lst)
  (mapcar (function (lambda (x) (nth x lst)))
	  (vl-sort-i (mapcar fun lst) '<)
  )
)

;; gc:sortByDescending
;; Renvoie la liste triée en ordre décroissant suivant le résultat de la fonction.
;;
;; Arguments
;; fun : la fonction qui transforme les éléments en un type supportant la comparaison.
;; lst : la liste
(defun gc:sortByDescending (fun lst)
  (mapcar (function (lambda (x) (nth x lst)))
	  (vl-sort-i (mapcar fun lst) '>)
  )
)