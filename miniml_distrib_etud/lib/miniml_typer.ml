open Miniml_types

(* signature minimale pour définir des variables *)
module type VariableSpec =
  sig
    (* type abstrait des variables      *)
    type t

    (* création d'une variable fraîche  *)
    val fraiche : unit -> t

    (* fonctions de comparaison         *)
    (* permet de définir des conteneurs *)
    (* (hash-table, etc) de variables   *)
    val compare : t -> t -> int
    val equal : t -> t -> bool
    val hash : t -> int

    (* fonction d'affichage             *)
    (* on utilise Format.std_formatter  *)
    (* comme premier paramètre          *)
    (* pour la sortie standard          *) 
    val fprintf : Format.formatter -> t -> unit
  end

(* implantation de la spécification     *)
module TypeVariable : VariableSpec =
  struct
    type t = int

    let fraiche =
      let cpt = ref 0 in
      (fun () -> incr cpt; !cpt)

    let compare a b = a - b
    let equal a b = a = b
    let hash a = Hashtbl.hash a

    let fprintf fmt a = Format.fprintf fmt "t{%d}" a
  end


(* ******** à compléter ********* *)

(*Signature pour définir l'environnement*)
module type EnvironnementSpec =
  sig
    (*Le type de l'environnement*)
    type env
    (*Le module des variables*)
    module ModuleVar : VariableSpec

    type var = ModuleVar.t
    (*Le type des identifiants*)
    type identif
    (*Le type du type des variables*)
    type 'a typEnv
    (*Créer l'environement initial*)
    val nouveau: unit -> env

    (*Ajouter un couple (variable:type) à l'environnement*)
    val ajouterCouple: env -> identif -> var typEnv -> env

    (*Ajouter une equation (type1 ≡ type2) à l'environnement*)
    val ajouterEquation: env -> var typEnv -> var typEnv -> env

    (*Obtenir le type associé à une variable si elle est présente dans l'environnement*)
    val obtenirType: env -> identif -> var typEnv option

end

module TypeEnvironnement : EnvironnementSpec = 
  struct
      module ModuleVar = TypeVariable

      type var = ModuleVar.t

      type 'a typEnv = 'a typ

      type identif = ident

      type env = ((identif, var typEnv) Hashtbl.t) * ((var typEnv * var typEnv) list)

      (*Taille de la table arbitraire*)
      let nouveau : unit -> env = fun () -> (Hashtbl.create 128,[])

      let ajouterCouple : env -> identif -> var typEnv -> env = fun (tableType, listeEquation) variable typeVar ->
        let newTable = Hashtbl.add tableType variable typeVar
          in (newTable, listeEquation)

      let ajouterEquation : env -> var typEnv -> var typEnv -> env = fun (tableType,listeEquation) type1 type2 -> 
        (tableType,(type1, type2)::listeEquation)

      let obtenirType : env -> identif -> var typEnv option = fun (tableType, _) identifiant ->
        Hashtbl.find_opt tableType identifiant
      

end

(*Signature du typer*)
module type TyperSpec =
  sig
    (*Le type des expression à typer*)
    type expression

    (*Le module de l'environnement*)
    module ModuleEnv : EnvironnementSpec

    (*Le type de l'environnement*)
    type environnement = ModuleEnv.env

    type typeExpr = ModuleEnv.var ModuleEnv.typEnv

    (*Fonction d'inférence des types, prend un environnement initial et une expression, et renvoie l'environnement et le type final après inférence*)
    val inference : environnement -> expression -> environnement * typeExpr

    (*Fonction de normalisation des equations de type. Renvoie le type final ainsi que une liste des logs à afficher.*)
    val normalisation : environnement -> typeExpr -> (string list * typeExpr option)
end

(*Typer sans polymorphisme*)
module TypeTyper : TyperSpec =
  struct
    type expression = expr

    module ModuleEnv = TypeEnvironnement

    type environnement = ModuleEnv.env

    type typeExpr = ModuleEnv.var ModuleEnv.typEnv

    let rec inference : environnement -> expression -> environnement * typeExpr = fun env express -> 
      match express with
            (*Si on tombe sur une constante, on ne change pas l'environnement et on renvoie le bon type*)
          | EConstant(constante) -> ( match constante with 
              |CBooleen(_) -> (env, TBool)
              |CEntier(_) -> (env, TInt)
              |CNil -> let alpha = ModuleEnv.ModuleVar.fraiche () in (env, TList(TVar(alpha)))
              |CUnit -> (env, TUnit)
              )

          | EIdent(identifiant) -> let alpha = ModuleEnv.ModuleVar.fraiche () in 
              let newEnv = ModuleEnv.ajouterCouple env identifiant TVar(alpha) in 
              (env, TVar(alpha))

          | EProd(expr1, expr2) -> let (newEnv1, tau1) = inference env expr1 in
              let (newEnv2, tau2) = inference newEnv1 expr2 in 
              (newEnv2, TProd(tau1,tau2))

          | ECons(expr1, expr2) -> let (newEnv1, tau1) = inference env expr1 in
              let (newEnv2, tau2) = inference newEnv1 expr2 in 
              let newEnv3 = ModuleEnv.ajouterEquation env tau2 TList(tau1) in
              (newEnv3, tau2)

          | EFun(identifiant, expr1) -> let alpha = ModuleEnv.ModuleVar.fraiche () in 
          let newEnv1 = ModuleEnv.ajouterCouple env identifiant TVar(alpha) in 
              let (newEnv2, tau) = inference newEnv1 expr1 in
              (newEnv2, TFun(TVar(alpha),tau))

          | EIf(exprBool,exprThen,exprElse) -> let (newEnv1, tau) = inference env exprBool in
              let (newEnv2, tau1) = inference newEnv1 exprThen in
              let (newEnv3, tau2) = inference newEnv2 exprElse in
              let newEnv4 = ModuleEnv.ajouterEquation tau TBool in
              let newEnv5 = ModuleEnv.ajouterEquation tau1 tau2 in
              (newEnv5, tau1)

          | EApply(exprFun,exprVar) -> let alpha = ModuleEnv.ModuleVar.fraiche () in 
              let (newEnv1, tau1) = inference env exprFun in
              let (newEnv2, tau2) = inference newEnv1 exprVar in
              let newEnv3 = ModuleEnv.ajouterEquation newEnv2 tau1 TFun(tau2, Tvar(alpha)) in
              (newEnv3, alpha) 

          | EBinop(tokenOP) -> match tokenOP with
              |CONCAT -> let alpha1 = ModuleEnv.ModuleVar.fraiche () in 
                  (env, TFun(TList(TVar(alpha)), TFun(TList(TVar(alpha)), TList(TVar(alpha)))))
              |PLUS | MOINS |MULT |DIV -> (env, TFun(TInt, TFun(TInt, TInt)))
              |AND | OR -> (env, TFun(TBool, TFun(TBool, TBool)))
              |EQU |NOTEQ |INF |INFEQ |SUP |SUPEQ -> let alpha = ModuleEnv.ModuleVar.fraiche () in 
                  (env, TFun(TVar(alpha), TFun(TVar(alpha), TBool)))

          | ELet(identifiant,exprLet, exprIn) -> let (newEnv1, tau1) = inference env exprLet in
              let newEnv2 = ModuleEnv.ajouterCouple newEnv1 identifiant tau in 
              let (newEnv3, tau2) = inference newEnv2 exprIn in
              (newEnv3, tau2)

          | ELetrec(identifiant,exprLet,exprin) -> let alpha = ModuleEnv.ModuleVar.fraiche () in 
              let newEnv1 = ModuleEnv.ajouterCouple env identifiant TVar(alpha) in 
              let (newEnv2, tau1) = inference newEnv1 exprLet in
              let (newEnv3, tau2) = inference newEnv2 exprIn in
              let newEnv4 = ModuleEnv.ajouterEquation TVar(alpha) tau1 in
              (newEnv4, tau2)


    let normalisation : environnement -> typeExpr -> (string list *typeExpr option) = fun (_,listeExpr) typeExpression -> failwith "TODO"

end