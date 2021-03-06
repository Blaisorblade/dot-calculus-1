
Set Implicit Arguments.

(* CoqIDE users: Run open.sh (in ./ln) to start coqide, then open this file. *)
Require Import LibLN.


(* ###################################################################### *)
(* ###################################################################### *)
(** * Definitions *)

(* ###################################################################### *)
(** ** Syntax *)

Parameter typ_label: Set.
Parameter mtd_label: Set.

Inductive label: Set :=
| label_typ: typ_label -> label
| label_mtd: mtd_label -> label.

Inductive avar : Set :=
  | avar_b : nat -> avar  (* bound var (de Bruijn index) *)
  | avar_f : var -> avar. (* free var ("name"), refers to store or ctx *)

Inductive typ : Set :=
  | typ_top  : typ
  | typ_bot  : typ
  | typ_rcd  : dec -> typ (* { D } *)
  | typ_sel  : avar -> typ_label -> typ (* x.L *)
  | typ_and  : typ -> typ -> typ
  | typ_or   : typ -> typ -> typ
with dec : Set :=
  | dec_typ  : typ_label -> typ -> typ -> dec (* L: S..U *)
  | dec_mtd  : mtd_label -> typ -> typ -> dec (* m: S->U *).

Inductive trm: Set :=
  | trm_var : avar -> trm
  | trm_new : defs -> trm -> trm (* val x = new {...} in t *)
  | trm_call: trm -> mtd_label -> trm -> trm (* t1.m(t2) *)
with def : Set :=
  | def_typ : typ_label -> typ -> typ -> def (* same as dec_typ *)
  | def_mtd : mtd_label -> typ -> typ -> trm -> def (* one nameless argument *)
with defs : Set :=
  | defs_nil : defs
  | defs_cons : defs -> def -> defs.

(** *** Typing environment ("Gamma") *)
Definition ctx := env typ.

(** *** Value environment ("store") *)
Definition sto := env defs.

(** *** TODO Syntactic sugar *)


(* ###################################################################### *)
(** ** Definition list membership *)

Definition label_of_def(d: def): label := match d with
| def_typ L _ _ => label_typ L
| def_mtd m _ _ _ => label_mtd m
end.

Definition label_of_dec(D: dec): label := match D with
| dec_typ L _ _ => label_typ L
| dec_mtd m _ _ => label_mtd m
end.

Fixpoint get_def(l: label)(ds: defs): option def :=
match ds with
| defs_nil => None
| defs_cons ds' d => If label_of_def d = l then Some d else get_def l ds'
end.

Definition defs_has(ds: defs)(d: def) := get_def (label_of_def d) ds = Some d.
Definition defs_hasnt(ds: defs)(l: label) := get_def l ds = None.


(* ###################################################################### *)
(** ** Opening *)

(** Opening replaces in some syntax a bound variable with dangling index (k) 
   by a free variable x. *)

Definition open_rec_avar (k: nat) (u: var) (a: avar) : avar :=
  match a with
  | avar_b i => If k = i then avar_f u else avar_b i
  | avar_f x => avar_f x
  end.

Fixpoint open_rec_typ (k: nat) (u: var) (T: typ): typ :=
  match T with
  | typ_top        => typ_top
  | typ_bot        => typ_bot
  | typ_rcd D      => typ_rcd (open_rec_dec k u D)
  | typ_sel x L    => typ_sel (open_rec_avar k u x) L
  | typ_and T1 T2  => typ_and (open_rec_typ k u T1) (open_rec_typ k u T2)
  | typ_or  T1 T2  => typ_or  (open_rec_typ k u T1) (open_rec_typ k u T2)
  end
with open_rec_dec (k: nat) (u: var) (D: dec): dec :=
  match D with
  | dec_typ L T U => dec_typ L (open_rec_typ k u T) (open_rec_typ k u U)
  | dec_mtd m T U => dec_mtd m (open_rec_typ k u T) (open_rec_typ k u U)
  end.

Fixpoint open_rec_trm (k: nat) (u: var) (t: trm): trm :=
  match t with
  | trm_var a      => trm_var (open_rec_avar k u a)
  | trm_call o m a => trm_call (open_rec_trm k u o) m (open_rec_trm k u a)
  | trm_new ds t   => trm_new (open_rec_defs (S k) u ds) (* self ref *)
                              (open_rec_trm (S k) u t)
  end
with open_rec_def (k: nat) (u: var) (d: def): def :=
  match d with
  | def_typ L Lo Hi => def_typ L (open_rec_typ k u Lo) (open_rec_typ k u Hi)
  | def_mtd m T1 T2 e => def_mtd m (open_rec_typ k u T1) (open_rec_typ k u T2)
                         (open_rec_trm (S k) u e)
  end
with open_rec_defs (k: nat) (u: var) (ds: defs): defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons tl d => defs_cons (open_rec_defs k u tl) (open_rec_def k u d)
  end.

Definition open_avar u a := open_rec_avar  0 u a.
Definition open_typ  u t := open_rec_typ   0 u t.
Definition open_dec  u D := open_rec_dec   0 u D.
Definition open_trm  u e := open_rec_trm   0 u e.
Definition open_def  u d := open_rec_def   0 u d.
Definition open_defs u l := open_rec_defs  0 u l.


(* ###################################################################### *)
(** ** Free variables *)

Definition fv_avar (a: avar) : vars :=
  match a with
  | avar_b i => \{}
  | avar_f x => \{x}
  end.

Fixpoint fv_typ (T: typ) : vars :=
  match T with
  | typ_top        => \{}
  | typ_bot        => \{}
  | typ_rcd D      => (fv_dec D)
  | typ_sel x L    => (fv_avar x)
  | typ_and T U    => (fv_typ T) \u (fv_typ U)
  | typ_or  T U    => (fv_typ T) \u (fv_typ U)
  end
with fv_dec (D: dec) : vars :=
  match D with
  | dec_typ L T U => (fv_typ T) \u (fv_typ U)
  | dec_mtd m T U => (fv_typ T) \u (fv_typ U)
  end.

(* Since we define defs ourselves instead of using [list def], we don't have any
   termination proof problems: *)
Fixpoint fv_trm (t: trm) : vars :=
  match t with
  | trm_var x        => (fv_avar x)
  | trm_new ds t     => (fv_defs ds) \u (fv_trm t)
  | trm_call t1 m t2 => (fv_trm t1) \u (fv_trm t2)
  end
with fv_def (d: def) : vars :=
  match d with
  | def_typ _ T U   => (fv_typ T) \u (fv_typ U)
  | def_mtd _ T U u => (fv_typ T) \u (fv_typ U) \u (fv_trm u)
  end
with fv_defs(ds: defs) : vars :=
  match ds with
  | defs_nil         => \{}
  | defs_cons tl d   => (fv_defs tl) \u (fv_def d)
  end.

Definition fv_ctx_types(G: ctx): vars := (fv_in_values (fun T => fv_typ T) G).


(* ###################################################################### *)
(** ** Operational Semantics *)

(** Note: Terms given by user are closed, so they only contain avar_b, no avar_f.
    Whenever we introduce a new avar_f (only happens in red_new), we choose one
    which is not in the store, so we never have name clashes. *)
Inductive red : trm -> sto -> trm -> sto -> Prop :=
  (* computation rules *)
  | red_call: forall s x y m T U ds body,
      binds x ds s ->
      defs_has ds (def_mtd m T U body) ->
      red (trm_call (trm_var (avar_f x)) m (trm_var (avar_f y))) s
          (open_trm y body) s
  | red_new: forall s ds t x,
      x # s ->
      red (trm_new ds t) s
          (open_trm x t) (s & x ~ (open_defs x ds))
  (* congruence rules *)
  | red_call1 : forall s o m a s' o',
      red o s o' s' ->
      red (trm_call o  m a) s
          (trm_call o' m a) s'
  | red_call2 : forall s x m a s' a',
      red a s a' s' ->
      red (trm_call (trm_var (avar_f x)) m a ) s
          (trm_call (trm_var (avar_f x)) m a') s'.


(* ###################################################################### *)
(** ** Typing *)

(* "optimization" of typ_and (makes some proofs simpler, but others more
    complicated!!).
   If intersect_dec and thus typ_has uses intersect_typ instead of typ_and, 
   we know that if a decl returned by typ_has is "equivalent" to a bottom-decl,
   it's actually also structurally equal.
   Or in other words: Instead of returning (dec_fld l (typ_and typ_bot T)),
   typ_has will return just (dec_fld l typ_bot).
Definition intersect_typ(T1 T2: typ): typ := If T1 = T2 then T1 else
match T1, T2 with
| typ_top, _ => T2
| _, typ_top => T1
| typ_bot, _ => typ_bot
| _, typ_bot => typ_bot
| _, _       => typ_and T1 T2
end.

Definition union_typ(T1 T2: typ): typ := If T1 = T2 then T1 else
match T1, T2 with
| typ_top, _ => typ_top
| _, typ_top => typ_top
| typ_bot, _ => T2
| _, typ_bot => T1
| _, _       => typ_or T1 T2
end.
*)

(* returns (option dec) because it's not total. *)
Definition intersect_dec(D1 D2: dec): option dec :=
  If label_of_dec D1 = label_of_dec D2 then
    match D1, D2 with
    | (dec_typ L S1 U1), (dec_typ _ S2 U2)
      => Some (dec_typ L (typ_or S1 S2) (typ_and U1 U2))
    | (dec_mtd m S1 U1), (dec_mtd _ S2 U2)
      => Some (dec_mtd m (typ_or S1 S2) (typ_and U1 U2))
    | _, _ => None
    end
  else
    None.

Definition union_dec(D1 D2: dec): option dec :=
  If label_of_dec D1 = label_of_dec D2 then
    match D1, D2 with
    | (dec_typ L S1 U1), (dec_typ _ S2 U2)
      => Some (dec_typ L (typ_and S1 S2) (typ_or U1 U2))
    | (dec_mtd m S1 U1), (dec_mtd _ S2 U2)
      => Some (dec_mtd m (typ_and S1 S2) (typ_or U1 U2))
    | _, _ => None
    end
  else
    None.

(*
Definition intersect_dec(D1 D2: dec): option dec :=
  If label_of_dec D1 = label_of_dec D2 then
    match D1, D2 with
    | (dec_typ L S1 U1), (dec_typ _ S2 U2)
      => Some (dec_typ L (union_typ S1 S2) (intersect_typ U1 U2))
    | (dec_mtd m S1 U1), (dec_mtd _ S2 U2)
      => Some (dec_mtd m (union_typ S1 S2) (intersect_typ U1 U2))
    | _, _ => None
    end
  else
    None.

Definition union_dec(D1 D2: dec): option dec :=
  If label_of_dec D1 = label_of_dec D2 then
    match D1, D2 with
    | (dec_typ L S1 U1), (dec_typ _ S2 U2)
      => Some (dec_typ L (intersect_typ S1 S2) (union_typ U1 U2))
    | (dec_mtd m S1 U1), (dec_mtd _ S2 U2)
      => Some (dec_mtd m (intersect_typ S1 S2) (union_typ U1 U2))
    | _, _ => None
    end
  else
    None.
*)

Notation "D1 && D2 == D3" := (intersect_dec D1 D2 = Some D3) (at level 40).
Notation "D1 || D2 == D3" := (union_dec D1 D2 = Some D3) (at level 40).

Definition dec_bot(l: label): dec := match l with
  | label_typ L => dec_typ L typ_top typ_bot
  | label_mtd m => dec_mtd m typ_top typ_bot
end.

(*
Definition dec_top(l: label): dec := match l with
  | label_typ L => dec_typ L typ_bot typ_top
  | label_mtd m => dec_mtd m typ_bot typ_top
end.
*)

Inductive typ_has: ctx -> typ -> dec -> Prop :=
(*| typ_top_has: typ_top has nothing *)
  | typ_bot_has: forall G l,
      typ_has G typ_bot (dec_bot l)
  | typ_rcd_has: forall G D,
      typ_has G (typ_rcd D) D
  | typ_sel_has: forall G x T L Lo Hi D,
      binds x T G ->
      typ_has  G T (dec_typ L Lo Hi) ->
      typ_has  G Hi D ->
      typ_has G (typ_sel (avar_f x) L) D
  | typ_and_has_1: forall G T1 T2 D,
      typ_has G T1 D ->
      typ_hasnt G T2 (label_of_dec D) ->
      typ_has G (typ_and T1 T2) D
  | typ_and_has_2: forall G T1 T2 D,
      typ_hasnt G T1 (label_of_dec D) ->
      typ_has G T2 D ->
      typ_has G (typ_and T1 T2) D
  | typ_and_has_12: forall G T1 T2 D1 D2 D3,
      typ_has G T1 D1 ->
      typ_has G T2 D2 ->
      D1 && D2 == D3 ->
      typ_has G (typ_and T1 T2) D3
  | typ_or_has: forall G T1 T2 D1 D2 D3,
      typ_has G T1 D1 ->
      typ_has G T2 D2 ->
      D1 || D2 == D3 ->
      typ_has G (typ_or T1 T2) D3
with typ_hasnt: ctx -> typ -> label -> Prop :=
  | typ_top_hasnt: forall G l,
      typ_hasnt G typ_top l
(*| typ_bot_hasnt: There's no label that typ_bot hasn't. *)
  | typ_rcd_hasnt: forall G D l,
      l <> label_of_dec D ->
      typ_hasnt G (typ_rcd D) l
  | typ_sel_hasnt: forall G x T L Lo Hi l,
      binds x T G ->
      typ_has    G T (dec_typ L Lo Hi) ->
      typ_hasnt  G Hi l ->
      typ_hasnt G (typ_sel (avar_f x) L) l
  | typ_and_hasnt: forall G T1 T2 l, 
      typ_hasnt G T1 l ->
      typ_hasnt G T2 l ->
      typ_hasnt G (typ_and T1 T2) l
  | typ_or_hasnt_1: forall G T1 T2 l,
      typ_hasnt G T1 l ->
      typ_hasnt G (typ_or T1 T2) l
  | typ_or_hasnt_2: forall G T1 T2 l,
      typ_hasnt G T2 l ->
      typ_hasnt G (typ_or T1 T2) l.

(* wf means "well-formed", not "well-founded" ;-) *)
CoInductive wf_typ: ctx -> typ -> Prop :=
  | wf_top: forall G,
      wf_typ G typ_top
  | wf_bot: forall G,
      wf_typ G typ_bot
  | wf_rcd: forall G D,
      wf_dec G D ->
      wf_typ G (typ_rcd D)
  | wf_sel: forall G x X L T U,
      binds x X G ->
      typ_has G X (dec_typ L T U) ->
      wf_typ G T ->
      wf_typ G U ->
      wf_typ G (typ_sel (avar_f x) L)
  | wf_and: forall G T1 T2,
      wf_typ G T1 ->
      wf_typ G T2 ->
      wf_typ G (typ_and T1 T2)
  | wf_or: forall G T1 T2,
      wf_typ G T1 ->
      wf_typ G T2 ->
      wf_typ G (typ_or T1 T2)
with wf_dec: ctx -> dec -> Prop :=
  | wf_tmem: forall G L Lo Hi,
      wf_typ G Lo ->
      wf_typ G Hi ->
      wf_dec G (dec_typ L Lo Hi)
  | wf_mtd: forall G m A R,
      wf_typ G A ->
      wf_typ G R ->
      wf_dec G (dec_mtd m A R).

Inductive subtyp: ctx -> typ -> typ -> Prop :=
  | subtyp_refl: forall G T,
      wf_typ G T ->
      subtyp G T T
  | subtyp_top: forall G T,
      wf_typ G T ->
      subtyp G T typ_top
  | subtyp_bot: forall G T,
      wf_typ G T ->
      subtyp G typ_bot T
  | subtyp_rcd: forall G D1 D2,
      subdec G D1 D2 ->
      subtyp G (typ_rcd D1) (typ_rcd D2)
  | subtyp_sel_l: forall G x X L T U,
      binds x X G ->
      typ_has G X (dec_typ L T U) ->
      subtyp G T U -> (* <-- probably not needed, but keep for symmetry with subtyp_sel_r *)
      subtyp G (typ_sel (avar_f x) L) U
  | subtyp_sel_r: forall G x X L T U,
      binds x X G ->
      typ_has G X (dec_typ L T U) ->
      subtyp G T U -> (* <-- makes proofs a lot easier!! *)
      subtyp G T (typ_sel (avar_f x) L)
  | subtyp_and: forall G T U1 U2,
      subtyp G T U1 ->
      subtyp G T U2 ->
      subtyp G T (typ_and U1 U2)
  | subtyp_and_l: forall G T1 T2,
      wf_typ G T1 ->
      wf_typ G T2 ->
      subtyp G (typ_and T1 T2) T1
  | subtyp_and_r: forall G T1 T2,
      wf_typ G T1 ->
      wf_typ G T2 ->
      subtyp G (typ_and T1 T2) T2
  | subtyp_or: forall G T1 T2 U,
      subtyp G T1 U ->
      subtyp G T2 U ->
      subtyp G (typ_or T1 T2) U
  | subtyp_or_l: forall G T1 T2,
      wf_typ G T1 ->
      wf_typ G T2 ->
      subtyp G T1 (typ_or T1 T2)
  | subtyp_or_r: forall G T1 T2,
      wf_typ G T1 ->
      wf_typ G T2 ->
      subtyp G T2 (typ_or T1 T2)
  | subtyp_trans: forall G T1 T2 T3,
      subtyp G T1 T2 ->
      subtyp G T2 T3 ->
      subtyp G T1 T3
with subdec: ctx -> dec -> dec -> Prop :=
  | subdec_typ: forall G L Lo1 Hi1 Lo2 Hi2,
      subtyp G Lo2 Lo1 ->
      subtyp G Hi1 Hi2 ->
      subdec G (dec_typ L Lo1 Hi1) (dec_typ L Lo2 Hi2)
  | subdec_mtd: forall m G S1 T1 S2 T2,
      subtyp G S2 S1 ->
      subtyp G T1 T2 ->
      subdec G (dec_mtd m S1 T1) (dec_mtd m S2 T2).

Inductive ty_trm: ctx -> trm -> typ -> Prop :=
  | ty_var: forall G x T,
      binds x T G ->
      wf_typ G T ->
      ty_trm G (trm_var (avar_f x)) T
  | ty_call: forall G t T m U1 U2 V u,
      ty_trm G t T ->
      typ_has G T (dec_mtd m U2 V) ->
      ty_trm G u U1 ->
      subtyp G U1 U2 -> (* <-- explicit subsumption *)
      wf_typ G V ->
      ty_trm G (trm_call t m u) V
  | ty_new: forall L G ds T u U,
      (forall x, x \notin L ->
         ty_defs (G & x ~ (open_typ x T)) (open_defs x ds) (open_typ x T)) ->
      (forall x, x \notin L ->
         ty_trm (G & x ~ (open_typ x T)) (open_trm x u) U) ->
      wf_typ G U -> (* <-- even stronger than x \notin fv_typ U *)
      ty_trm G (trm_new ds u) U
with ty_def: ctx -> def -> dec -> Prop :=
  | ty_tdef: forall G L T U,
      subtyp G T U -> (* <-- only allow realizable bounds *)
      ty_def G (def_typ L T U) (dec_typ L T U)
  | ty_mdef: forall L m G T U1 U2 u,
      wf_typ G T ->
      (forall x, x \notin L -> ty_trm (G & x ~ T) (open_trm x u) U1) ->
      subtyp G U1 U2 ->  (* <-- explicit subsumption *)
      ty_def G (def_mtd m T U2 u) (dec_mtd m T U2)
with ty_defs: ctx -> defs -> typ -> Prop :=
  | ty_defs_nil: forall G,
      ty_defs G defs_nil typ_top
  | ty_defs_cons: forall G ds d T D,
      ty_defs G ds T ->
      ty_def G d D ->
      defs_hasnt ds (label_of_def d) -> (* <-- no duplicates *)
      ty_defs G (defs_cons ds d) (typ_and T (typ_rcd D)).

(** *** Well-formed store *)
Inductive wf_sto: sto -> ctx -> Prop :=
  | wf_sto_empty: wf_sto empty empty
  | wf_sto_push: forall s G x ds T,
      wf_sto s G ->
      x # s ->
      x # G ->
      (* Note that ds and T were already opened with x. *)
      ty_defs (G & x ~ T) ds T ->
      wf_sto (s & x ~ ds) (G & x ~ T).


(* ###################################################################### *)
(** ** Statements we want to prove *)

Definition progress := forall s G e T,
  wf_sto s G ->
  ty_trm G e T -> 
  (
    (* can step *)
    (exists e' s', red e s e' s') \/
    (* or is a value *)
    (exists x o, e = (trm_var (avar_f x)) /\ binds x o s)
  ).

Definition preservation := forall s G e T e' s',
  wf_sto s G -> ty_trm G e T -> red e s e' s' ->
  (exists G', wf_sto s' G' /\ ty_trm G' e' T).


(* ###################################################################### *)
(* ###################################################################### *)
(** * Infrastructure *)

(* ###################################################################### *)
(** ** Induction principles *)

Scheme typ_mut := Induction for typ Sort Prop
with   dec_mut := Induction for dec Sort Prop.
Combined Scheme typ_mutind from typ_mut, dec_mut.

Scheme trm_mut  := Induction for trm  Sort Prop
with   def_mut  := Induction for def  Sort Prop
with   defs_mut := Induction for defs Sort Prop.
Combined Scheme trm_mutind from trm_mut, def_mut, defs_mut.

Scheme typ_has_mut := Induction for typ_has Sort Prop
with typ_hasnt_mut := Induction for typ_hasnt Sort Prop.
Combined Scheme typ_has_mutind from typ_has_mut, typ_hasnt_mut.

Scheme subtyp_mut := Induction for subtyp Sort Prop
with   subdec_mut := Induction for subdec Sort Prop.
Combined Scheme subtyp_mutind from subtyp_mut, subdec_mut.

Scheme ty_trm_mut    := Induction for ty_trm    Sort Prop
with   ty_def_mut    := Induction for ty_def    Sort Prop
with   ty_defs_mut   := Induction for ty_defs   Sort Prop.
Combined Scheme ty_mutind from ty_trm_mut, ty_def_mut, ty_defs_mut.


(* ###################################################################### *)
(** ** Tactics *)

Ltac gather_vars :=
  let A := gather_vars_with (fun x : vars      => x         ) in
  let B := gather_vars_with (fun x : var       => \{ x }    ) in
  let C := gather_vars_with (fun x : ctx       => (dom x) \u (fv_ctx_types x)) in
  let D := gather_vars_with (fun x : sto       => dom x     ) in
  let E := gather_vars_with (fun x : avar      => fv_avar  x) in
  let F := gather_vars_with (fun x : trm       => fv_trm   x) in
  let G := gather_vars_with (fun x : def       => fv_def   x) in
  let H := gather_vars_with (fun x : defs      => fv_defs  x) in
  let I := gather_vars_with (fun x : typ       => fv_typ   x) in
  constr:(A \u B \u C \u D \u E \u F \u G \u H \u I).

Ltac pick_fresh x :=
  let L := gather_vars in (pick_fresh_gen L x).

Ltac destruct_wf :=
  repeat match goal with
  | W: wf_dec _ (dec_typ _ _ _) |- _ => inversions W
  | W: wf_dec _ (dec_mtd _ _ _) |- _ => inversions W
  | W: wf_typ _ (typ_rcd _)     |- _ => inversions W
  | W: wf_typ _ (typ_and _ _)   |- _ => inversions W
  | W: wf_typ _ (typ_or _ _)    |- _ => inversions W
  end.

Tactic Notation "apply_fresh" constr(T) "as" ident(x) :=
  apply_fresh_base T gather_vars x.

Hint Constructors
  typ_has typ_hasnt
  wf_typ wf_dec
  subtyp subdec
  ty_trm ty_def ty_defs.
Hint Constructors wf_sto.

Lemma fresh_push_eq_inv: forall A x a (E: env A),
  x # (E & x ~ a) -> False.
Proof.
  intros. rewrite dom_push in H. false H. rewrite in_union.
  left. rewrite in_singleton. reflexivity.
Qed.

(* Coinduction: See http://adam.chlipala.net/cpdt/html/Coinductive.html *)

Section wf_coind.
  Variable RT : ctx -> typ -> Prop.
  Variable RD : ctx -> dec -> Prop.

  Hypothesis CaseRcd: forall G D,
    RT G (typ_rcd D) -> RD G D.

  Hypothesis CaseSel: forall G a L,
    RT G (typ_sel a L) -> 
    exists x X T U, 
      a = avar_f x /\
      binds x X G /\
      typ_has G X (dec_typ L T U) /\
      RT G T /\
      RT G U.

  Hypothesis CaseAnd: forall G T1 T2,
    RT G (typ_and T1 T2) ->
    RT G T1 /\ RT G T2.

  Hypothesis CaseOr: forall G T1 T2,
    RT G (typ_or T1 T2) ->
    RT G T1 /\ RT G T2.

  Hypothesis CaseTmem: forall G L T U,
    RD G (dec_typ L T U) ->
    RT G T /\ RT G U.

  Hypothesis CaseMtd: forall G m T U,
    RD G (dec_mtd m T U) ->
    RT G T /\ RT G U.

  Theorem wf_typ_coind: forall G T,
    RT G T -> wf_typ G T
  with wf_dec_coind: forall G D,
    RD G D -> wf_dec G D.
  Proof.
  - intros. destruct T.
    + (* case wf_top *)
      apply wf_top.
    + (* case wf_bot *)
      apply wf_bot.
    + (* case wf_rcd *)
      lets P: (CaseRcd H). apply wf_rcd. apply (wf_dec_coind _ _ P).
    + (* case wf_sel *)
      lets P: (CaseSel H). destruct P as [x [X [T [U [Eq [Bi [Has [R1 R2]]]]]]]].
      subst a.
      apply (wf_sel Bi Has).
      * apply (wf_typ_coind _ _ R1).
      * apply (wf_typ_coind _ _ R2).
    + (* case wf_and *)
      lets P: (CaseAnd H). destruct P as [R1 R2].
      apply (wf_and (wf_typ_coind _ _ R1) (wf_typ_coind _ _ R2)).
    + (* case wf_or *)
      lets P: (CaseOr H). destruct P as [R1 R2].
      apply (wf_or (wf_typ_coind _ _ R1) (wf_typ_coind _ _ R2)).
  - intros. destruct D.
    + (* case wf_tmem *)
      lets P: (CaseTmem H). destruct P as [R1 R2].
      apply (wf_tmem _ (wf_typ_coind _ _ R1) (wf_typ_coind _ _ R2)).
    + (* case wf_mtd *)
      lets P: (CaseMtd H). destruct P as [R1 R2].
      apply (wf_mtd _ (wf_typ_coind _ _ R1) (wf_typ_coind _ _ R2)).
  Qed.

  Theorem wf_mut_coind:
    (forall G T, RT G T -> wf_typ G T) /\
    (forall G D, RD G D -> wf_dec G D).
  Proof.
    split; introv H.
    - apply (wf_typ_coind H).
    - apply (wf_dec_coind H).
  Qed.
End wf_coind.


(* ###################################################################### *)
(** ** Examples *)

Ltac do_open :=
  repeat match goal with
  | _: _ |- context[open_avar _ _] => unfold open_avar; simpl
  | _: _ |- context[open_typ  _ _] => unfold open_typ ; simpl
  | _: _ |- context[open_dec  _ _] => unfold open_dec ; simpl
  | _: _ |- context[open_trm  _ _] => unfold open_trm ; simpl
  | _: _ |- context[open_def  _ _] => unfold open_def ; simpl
  | _: _ |- context[open_defs _ _] => unfold open_defs; simpl
  | _: _ |- context[(If _ = _ then _ else _)] => case_if; simpl
  end.

Ltac prove_defs_hasnt := solve [
  repeat match goal with
  | _: _ |- defs_hasnt _ _ => unfold defs_hasnt; simpl; auto
  | _: _ |- context[(If _ = _ then _ else _)] => case_if; simpl; auto
  end].

Ltac split_ty_defs :=
  repeat (prove_defs_hasnt || apply ty_defs_cons || apply ty_defs_nil).

Ltac prove_binds := solve [
  unfold binds; rewrite EnvOps.get_def; unfold get_impl;
  repeat (rewrite <- cons_to_push || case_if); auto].

(*
val glob = new {
  E: Top..Top,
  Stream: Bot..{head: Top -> glob.E} /\ {tail: Top -> glob.Stream}
};
val unit = new {};
val stream = new { head(x: Top): glob.E = unit, tail(x: Top): glob.Stream = stream };
stream.tail(unit).tail(unit).head(unit)
*)

Module Examples1.

Parameter E: typ_label.
Parameter Stream: typ_label.
Axiom E_ne_Stream: E <> Stream.
Parameter head: mtd_label.
Parameter tail: mtd_label.
Axiom head_ne_tail: head <> tail.

Definition ex1: trm :=
trm_new (defs_cons (defs_cons defs_nil
  (def_typ E typ_top typ_top))
  (def_typ Stream typ_bot (typ_and
       (typ_rcd (dec_mtd head typ_top (typ_sel (avar_b 0) E)))
       (typ_rcd (dec_mtd tail typ_top (typ_sel (avar_b 0) Stream)))))
)
(trm_new defs_nil
(trm_var (avar_b 0))).

Fact tc1: ty_trm empty ex1 typ_top.
Proof.
  assert (ne1: label_typ E <> label_typ Stream). {
    intro. inversions H. apply E_ne_Stream. assumption.
  }
  assert (ne2: label_mtd head <> label_mtd tail). {
    intro. inversions H. apply head_ne_tail. assumption.
  }
  unfold ex1.
  apply ty_new with \{} (typ_and (typ_and typ_top
    (typ_rcd (dec_typ E typ_top typ_top)))
    (typ_rcd (dec_typ Stream typ_bot (typ_and
       (typ_rcd (dec_mtd head typ_top (typ_sel (avar_b 0) E)))
       (typ_rcd (dec_mtd tail typ_top (typ_sel (avar_b 0) Stream))))))).
  + intros glob _. do_open.
    split_ty_defs.
    - auto.
    - apply ty_tdef. apply subtyp_bot.
      rewrite concat_empty_l in *.
      (* TStream = (typ_and
              (typ_rcd (dec_mtd head typ_top (typ_sel (avar_f glob) E)))
              (typ_rcd (dec_mtd tail typ_top (typ_sel (avar_f glob) Stream)))) *)
      cofix. (* <--- coinduction *)
      (* apply tc1. Guarded. <-- rejected, as expected *)
      apply wf_and.
      { apply wf_rcd. apply (wf_mtd _ (wf_top _)). eapply (wf_sel ((binds_single_eq _ _))).
        + eauto.
        + apply wf_top.
        + apply wf_top. }
      { apply wf_rcd. apply (wf_mtd _ (wf_top _)). eapply (wf_sel ((binds_single_eq _ _))).
        + eauto.
        + apply wf_bot.
        + (* now we have to prove wf-ness of TStream again, but we're "guarded" now: *)
          apply tc1. Guarded.
          (* Note: If you want to make this proof nicer using
              remember ...bla..long..type... as TName eqn: E
             it won't work any more because of Coq's restrictions on where co-recursive
             calls may occur (citing Chlipala):
             "a co-recursive call must be a direct argument to a constructor, nested only
              inside of other constructor calls or fun or match expressions"
             So tc1 must not be passed to a normal function, but that's what the
             "remember" tactic does.
            *)
      }
 + intros glob _. do_open. apply ty_new with \{ glob } typ_top.
   - intros unit N. split_ty_defs.
   - intros unit N. do_open. apply ty_var.
     * prove_binds.
     * apply wf_top.
   - apply wf_top.
 + apply wf_top.
Qed.

End Examples1.


(* ###################################################################### *)
(** ** Definition of var-by-var substitution *)

(** Note that substitution is not part of the definitions, because for the
    definitions, opening is sufficient. For the proofs, however, we also
    need substitution, but only var-by-var substitution, not var-by-term
    substitution. That's why we don't need a judgment asserting that a term
    is locally closed. *)

Definition subst_avar (z: var) (u: var) (a: avar) : avar :=
  match a with
  | avar_b i => avar_b i
  | avar_f x => If x = z then (avar_f u) else (avar_f x)
  end.

Fixpoint subst_typ (z: var) (u: var) (T: typ) { struct T } : typ :=
  match T with
  | typ_top        => typ_top
  | typ_bot        => typ_bot
  | typ_rcd D      => typ_rcd (subst_dec z u D)
  | typ_sel x L    => typ_sel (subst_avar z u x) L
  | typ_and T1 T2  => typ_and (subst_typ z u T1) (subst_typ z u T2)
  | typ_or  T1 T2  => typ_or  (subst_typ z u T1) (subst_typ z u T2)
  end
with subst_dec (z: var) (u: var) (D: dec) { struct D } : dec :=
  match D with
  | dec_typ L T U => dec_typ L (subst_typ z u T) (subst_typ z u U)
  | dec_mtd m T U => dec_mtd m (subst_typ z u T) (subst_typ z u U)
  end.

Fixpoint subst_trm (z: var) (u: var) (t: trm) : trm :=
  match t with
  | trm_var x        => trm_var (subst_avar z u x)
  | trm_new ds t     => trm_new (subst_defs z u ds) (subst_trm z u t)
  | trm_call t1 m t2 => trm_call (subst_trm z u t1) m (subst_trm z u t2)
  end
with subst_def (z: var) (u: var) (d: def) : def :=
  match d with
  | def_typ L T1 T2   => def_typ L (subst_typ z u T1) (subst_typ z u T2)
  | def_mtd m T1 T2 b => def_mtd m (subst_typ z u T1) (subst_typ z u T2) (subst_trm z u b)
  end
with subst_defs (z: var) (u: var) (ds: defs) : defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons rest d => defs_cons (subst_defs z u rest) (subst_def z u d)
  end.

Definition subst_ctx (z: var) (u: var) (G: ctx) : ctx := map (subst_typ z u) G.


(* ###################################################################### *)
(** ** Lemmas for var-by-var substitution *)

Lemma subst_fresh_avar: forall x y,
  (forall a: avar, x \notin fv_avar a -> subst_avar x y a = a).
Proof.
  intros. destruct* a. simpl. case_var*. simpls. notin_false.
Qed.

Lemma subst_fresh_typ_dec: forall x y,
  (forall T : typ , x \notin fv_typ  T  -> subst_typ  x y T  = T ) /\
  (forall D : dec , x \notin fv_dec  D  -> subst_dec  x y D  = D ).
Proof.
  intros x y. apply typ_mutind; intros; simpls; f_equal*. apply* subst_fresh_avar.
Qed.

Lemma subst_fresh_trm_def_defs: forall x y,
  (forall t : trm , x \notin fv_trm  t  -> subst_trm  x y t  = t ) /\
  (forall d : def , x \notin fv_def  d  -> subst_def  x y d  = d ) /\
  (forall ds: defs, x \notin fv_defs ds -> subst_defs x y ds = ds).
Proof.
  intros x y. apply trm_mutind; intros; simpls; f_equal*;
    (apply* subst_fresh_avar || apply* subst_fresh_typ_dec).
Qed.

Lemma invert_fv_ctx_types_push: forall x z T G,
  x \notin fv_ctx_types (G & z ~ T) -> x \notin fv_typ T /\ x \notin (fv_ctx_types G).
Proof.
  introv N.
  unfold fv_ctx_types in *.
  unfold fv_in_values in *.
  rewrite <- cons_to_push in *.
  rewrite values_def in *.
  unfold LibList.map in *.
  do 2 rewrite LibList.fold_right_cons in *.
  simpl in *.
  apply notin_union in N. exact N.
Qed.

Lemma subst_fresh_ctx: forall x y G,
  x \notin fv_ctx_types G -> subst_ctx x y G = G.
Proof.
  intros x y.
  apply (env_ind (fun G => x \notin fv_ctx_types G -> subst_ctx x y G = G)).
  + intro N. unfold subst_ctx. apply map_empty.
  + intros G z T IH N.
    apply invert_fv_ctx_types_push in N. destruct N as [N1 N2].
    unfold subst_ctx in *. rewrite map_push.
    rewrite (IH N2).
    rewrite ((proj1 (subst_fresh_typ_dec _ _)) _ N1).
    reflexivity.
Qed.

Definition subst_fvar(x y z: var): var := If x = z then y else z.

Lemma subst_open_commute_avar: forall x y u,
  (forall a: avar, forall n: Datatypes.nat,
    subst_avar x y (open_rec_avar n u a) 
    = open_rec_avar n (subst_fvar x y u) (subst_avar  x y a)).
Proof.
  intros. unfold subst_fvar, subst_avar, open_avar, open_rec_avar. destruct a.
  + repeat case_if; auto.
  + case_var*.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_typ_dec: forall x y u,
  (forall t : typ, forall n: nat,
     subst_typ x y (open_rec_typ n u t)
     = open_rec_typ n (subst_fvar x y u) (subst_typ x y t)) /\
  (forall D : dec, forall n: nat,
     subst_dec x y (open_rec_dec n u D)
     = open_rec_dec n (subst_fvar x y u) (subst_dec x y D)).
Proof.
  intros. apply typ_mutind; intros; simpl; f_equal*. apply subst_open_commute_avar.
Qed.

Lemma subst_open_commute_typ: forall x y u T,
  subst_typ x y (open_typ u T) = open_typ (subst_fvar x y u) (subst_typ x y T).
Proof.
  intros. apply* subst_open_commute_typ_dec.
Qed.

Lemma subst_open_commute_dec: forall x y u D,
  subst_dec x y (open_dec u D) = open_dec (subst_fvar x y u) (subst_dec x y D).
Proof.
  intros. apply* subst_open_commute_typ_dec.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_trm_def_defs: forall x y u,
  (forall t : trm, forall n: Datatypes.nat,
     subst_trm x y (open_rec_trm n u t)
     = open_rec_trm n (subst_fvar x y u) (subst_trm x y t)) /\
  (forall d : def , forall n: Datatypes.nat, 
     subst_def x y (open_rec_def n u d)
     = open_rec_def n (subst_fvar x y u) (subst_def x y d)) /\
  (forall ds: defs, forall n: Datatypes.nat, 
     subst_defs x y (open_rec_defs n u ds)
     = open_rec_defs n (subst_fvar x y u) (subst_defs x y ds)).
Proof.
  intros. apply trm_mutind; intros; simpl; f_equal*;
    (apply* subst_open_commute_avar || apply* subst_open_commute_typ_dec).
Qed.

Lemma subst_open_commute_trm: forall x y u t,
  subst_trm x y (open_trm u t) = open_trm (subst_fvar x y u) (subst_trm x y t).
Proof.
  intros. apply* subst_open_commute_trm_def_defs.
Qed.

Lemma subst_open_commute_defs: forall x y u ds,
  subst_defs x y (open_defs u ds) = open_defs (subst_fvar x y u) (subst_defs x y ds).
Proof.
  intros. apply* subst_open_commute_trm_def_defs.
Qed.

(* "Introduce a substitution after open": Opening a term t with a var u is the
   same as opening t with x and then replacing x by u. *)
Lemma subst_intro_trm: forall x u t, x \notin (fv_trm t) ->
  open_trm u t = subst_trm x u (open_trm x t).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_trm.
  destruct (@subst_fresh_trm_def_defs x u) as [Q _]. rewrite* (Q t).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_defs: forall x u ds, x \notin (fv_defs ds) ->
  open_defs u ds = subst_defs x u (open_defs x ds).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_defs.
  destruct (@subst_fresh_trm_def_defs x u) as [_ [_ Q]]. rewrite* (Q ds).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_typ: forall x u T, x \notin (fv_typ T) ->
  open_typ u T = subst_typ x u (open_typ x T).
Proof.
  introv Fr. unfold open_typ. rewrite* subst_open_commute_typ.
  destruct (@subst_fresh_typ_dec x u) as [Q _]. rewrite* (Q T).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_dec: forall x u D, x \notin (fv_dec D) ->
  open_dec u D = subst_dec x u (open_dec x D).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_dec.
  destruct (@subst_fresh_typ_dec x u) as [_ Q]. rewrite* (Q D).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_undo_avar: forall x y,
  (forall a, y \notin fv_avar a -> (subst_avar y x (subst_avar x y a)) = a).
Proof.
  intros. unfold subst_avar, subst_fvar, open_avar, open_rec_avar; destruct a.
  + reflexivity.
  + unfold fv_avar in H. assert (y <> v) by auto. repeat case_if; reflexivity.
Qed.

Lemma subst_undo_typ_dec: forall x y,
   (forall T , y \notin fv_typ  T  -> (subst_typ  y x (subst_typ  x y T )) = T )
/\ (forall D , y \notin fv_dec  D  -> (subst_dec  y x (subst_dec  x y D )) = D ).
Proof.
  intros.
  apply typ_mutind; intros; simpl; unfold fv_typ, fv_dec in *; f_equal*.
  apply* subst_undo_avar.
Qed.

Lemma subst_undo_trm_def_defs: forall x y,
   (forall t , y \notin fv_trm  t  -> (subst_trm  y x (subst_trm  x y t )) = t )
/\ (forall d , y \notin fv_def  d  -> (subst_def  y x (subst_def  x y d )) = d )
/\ (forall ds, y \notin fv_defs ds -> (subst_defs y x (subst_defs x y ds)) = ds).
Proof.
  intros.
  apply trm_mutind; intros; simpl; unfold fv_trm, fv_def, fv_defs in *; f_equal*;
    (apply* subst_undo_avar || apply* subst_undo_typ_dec).
Qed.

Lemma subst_typ_undo: forall x y T,
  y \notin fv_typ T -> (subst_typ y x (subst_typ x y T)) = T.
Proof.
  apply* subst_undo_typ_dec.
Qed.

Lemma subst_trm_undo: forall x y t,
  y \notin fv_trm t -> (subst_trm y x (subst_trm x y t)) = t.
Proof.
  apply* subst_undo_trm_def_defs.
Qed.


(* ###################################################################### *)
(** ** Regularity of Typing *)

(*
Lemma wf_deep_to_any: forall m G T,
  wf_typ deep G T ->
  wf_typ m G T.
Proof.
  introv WfT. gen_eq m20: deep. induction WfT; intro Eq; subst; destruct m; eauto.
  discriminate.
Qed.

Hint Resolve wf_deep_to_any.
*)

(* If a type is involved in a subtyping judgment, it is (deeply) well-formed. *)
Lemma subtyping_regular:
   (forall G T1 T2, subtyp G T1 T2 -> wf_typ G T1 /\ wf_typ G T2)
/\ (forall G D1 D2, subdec G D1 D2 -> wf_dec G D1 /\ wf_dec G D2).
Proof.
  apply subtyp_mutind; intros; split; subst;
  repeat match goal with
  | H: _ /\ _ |- _ => destruct H
  | H: wf_dec _ (dec_typ _ _ _) |- _ => inversions H
  | H: wf_dec _ (dec_mtd _ _ _) |- _ => inversions H
  end;
  eauto.
Qed.

Definition subtyp_regular := proj1 subtyping_regular.
Definition subdec_regular := proj2 subtyping_regular.

(*
Lemma strengthen_wf:
   (forall m G T, wf_typ m G T -> forall G1 x U G2,
    G = G1 & x ~ U & G2 ->
    x \notin fv_typ T ->
    wf_typ m (G1 & G2) T)
/\ (forall G D, wf_dec G D -> forall G1 x U G2,
    G = G1 & x ~ U & G2 ->
    x \notin fv_dec D ->
    wf_dec (G1 & G2) D).
Proof.
  apply wf_mutind.
  + (* case wf_top *) eauto.
  + (* case wf_bot *) eauto.
  + (* case wf_rcd_deep *) eauto.
  + (* case wf_rcd_shallow *) eauto.
  + (* case wf_sel *)
    introv Bi Has WfT IHT WfU IHU Eq N. subst.
    specialize (IHT _ _ _ _ eq_refl).
    specialize (IHU _ _ _ _ eq_refl).
    (* Does not hold because x0 \notin x.L does not imply x0 \notin T, U *)
Abort.
*)

Lemma typing_regular:
   (forall G t T, ty_trm G t T ->
      wf_typ G T)
/\ (forall G d D, ty_def G d D ->
      wf_dec G D)
/\ (forall G ds T, ty_defs G ds T ->
      wf_typ G T).
Proof.
  apply ty_mutind; intros; subst;
  repeat match goal with
  | H: _ /\ _ |- _ => destruct H
  | H: wf_dec _ (dec_typ _ _ _) |- _ => inversions H
  | H: wf_dec _ (dec_mtd _ _ _) |- _ => inversions H
  | H: subtyp _ _ _ |- _ => apply subtyp_regular in H
  end;
  eauto.
Qed.

Definition ty_trm_regular  := proj1        typing_regular.
Definition ty_def_regular  := proj1 (proj2 typing_regular).
Definition ty_defs_regular := proj2 (proj2 typing_regular).


(* ###################################################################### *)
(** ** Weakening *)

Lemma weaken_has:
   (forall G T D, typ_has G T D -> forall G1 G2 G3,
    G = G1 & G3 ->
    ok (G1 & G2 & G3) ->
    typ_has (G1 & G2 & G3) T D)
/\ (forall G T l, typ_hasnt G T l -> forall G1 G2 G3,
    G = G1 & G3 ->
    ok (G1 & G2 & G3) ->
    typ_hasnt (G1 & G2 & G3) T l).
Proof.
  apply typ_has_mutind.
  + (* case typ_bot_has *) eauto.
  + (* case typ_rcd_has *) eauto.
  + (* case typ_sel_has *)
    introv Bi THas IH1 HiHas IH2 Eq Ok. subst. lets Bi': (binds_weaken Bi Ok). eauto.
  + (* case typ_and_has_1 *) eauto.
  + (* case typ_and_has_2 *) eauto.
  + (* case typ_and_has_12 *) eauto.
  + (* case typ_or_has *) eauto.
  + (* case typ_top_hasnt *) eauto.
  + (* case typ_rcd_hasnt *) eauto.
  + (* case typ_sel_hasnt *)
    introv Bi THas IH1 HiHasnt IH2 Eq Ok. subst. lets Bi': (binds_weaken Bi Ok). eauto.
  + (* case typ_and_hasnt *) eauto.
  + (* case typ_or_hasnt_1 *) eauto.
  + (* case typ_or_hasnt_2 *) eauto.
Qed.

Lemma test_wf_mut_coind:
   (forall G T, False -> wf_typ G T)
/\ (forall G D, False -> wf_dec G D).
Proof.
  apply wf_mut_coind.
  (* case wf_rcd *)
  - auto.
  (* case wf_sel *)
  - intros. exfalso. auto.
  (* case wf_and *)
  - intros. auto.
  (* case wf_or *)
  - intros. auto.
  (* case wf_tmem *)
  - intros. auto.
  (* case wf_mtd *)
  - intros. auto.
Qed.

Lemma weaken_wf:
   (forall G T, (exists G1 G2 G3,
      G = G1 & G2 & G3 /\
      ok (G1 & G2 & G3) /\
      wf_typ (G1 & G3) T) ->
    wf_typ G T)
/\ (forall G D, (exists G1 G2 G3,
      G = G1 & G2 & G3 /\
      ok (G1 & G2 & G3) /\
      wf_dec (G1 & G3) D) ->
    wf_dec G D).
Proof.
  apply wf_mut_coind;
    introv H; destruct H as [G1 [G2 [G3 [Eq [Ok Wf]]]]]; subst; inversions Wf.
  (* case wf_rcd *)
  - do 3 eexists. eauto.
  (* case wf_sel *)
  - do 4 eexists.
    lets Bi': (binds_weaken H1 Ok).
    lets XHas': ((proj1 weaken_has) _ _ _ H2 _ _ _ eq_refl Ok).
    repeat split; repeat eexists; eauto.
  (* case wf_and *)
  - split; repeat eexists; eauto.
  (* case wf_or *)
  - split; repeat eexists; eauto.
  (* case wf_tmem *)
  - split; repeat eexists; eauto.
  (* case wf_mtd *)
  - split; repeat eexists; eauto.
Qed.

Lemma weaken_wf_typ: forall G1 G2 G3 T,
  wf_typ (G1 & G3) T ->
  ok (G1 & G2 & G3) ->
  wf_typ (G1 & G2 & G3) T.
Proof.
  introv Wf Ok. apply (proj1 weaken_wf). do 3 eexists; eauto.
Qed.

Print Assumptions weaken_wf_typ.

Lemma weaken_wf_dec: forall G1 G2 G3 D,
  wf_dec (G1 & G3) D ->
  ok (G1 & G2 & G3) ->
  wf_dec (G1 & G2 & G3) D.
Proof.
  introv Wf Ok. apply (proj2 weaken_wf). repeat eexists; eauto.
Qed.

Lemma weaken_subtyp_end: forall G1 G2 S U,
  ok (G1 & G2) -> 
  subtyp G1        S U ->
  subtyp (G1 & G2) S U.
Admitted.


(* ###################################################################### *)
(** ** More stuff *)

Lemma intersect_dec_total: forall D1 D2,
  label_of_dec D1 = label_of_dec D2 ->
  exists D12, D1 && D2 == D12.
Proof.
  introv Eq.
  destruct D1; destruct D2; inversions Eq; unfold intersect_dec; simpl; case_if; eauto.
Qed.

Lemma union_dec_total: forall D1 D2,
  label_of_dec D1 = label_of_dec D2 ->
  exists D12, D1 || D2 == D12.
Proof.
  introv Eq.
  destruct D1; destruct D2; inversions Eq; unfold union_dec; simpl; case_if; eauto.
Qed.

Lemma intersect_dec_label_eq: forall D1 D2 D12,
  D1 && D2 == D12 ->
  label_of_dec D1 = label_of_dec D2 /\
  label_of_dec D1 = label_of_dec D12 /\
  label_of_dec D2 = label_of_dec D12.
Proof.
  intros. destruct D1; destruct D2; unfold intersect_dec in H; simpl; case_if; 
  inversions H; auto.
Qed.

Lemma union_dec_label_eq: forall D1 D2 D12,
  D1 || D2 == D12 ->
  label_of_dec D1 = label_of_dec D2 /\
  label_of_dec D1 = label_of_dec D12 /\
  label_of_dec D2 = label_of_dec D12.
Proof.
  intros. destruct D1; destruct D2; unfold union_dec in H; simpl; case_if; 
  inversions H; auto.
Qed.

Lemma subdec_to_label_of_dec_eq: forall G D1 D2,
  subdec G D1 D2 -> label_of_dec D1 = label_of_dec D2.
Proof.
  introv Sd. inversions Sd; reflexivity.
Qed.

Lemma invert_subdec_typ_sync_left: forall G D L Lo2 Hi2,
   subdec G D (dec_typ L Lo2 Hi2) ->
   exists Lo1 Hi1, D = (dec_typ L Lo1 Hi1) /\
                   subtyp G Lo2 Lo1 /\
                   subtyp G Hi1 Hi2.
Proof.
  introv Sd. inversions Sd. exists Lo1 Hi1. auto.
Qed.

Lemma invert_subdec_mtd_sync_left: forall G D m T2 U2,
   subdec G D (dec_mtd m T2 U2) ->
   exists T1 U1, D = (dec_mtd m T1 U1) /\
                 subtyp G T2 T1 /\
                 subtyp G U1 U2.
Proof.
  introv Sd. inversions Sd. exists S1 T1. auto.
Qed.


(* ###################################################################### *)
(** ** typ_has/hasnt total *)

Lemma typ_has_total: forall G T, wf_typ G T ->
  forall l, typ_hasnt G T l \/ exists D, l = label_of_dec D /\ typ_has G T D.
Proof.
  introv Wf.
(* Oh no! We cannot do induction on wf_typ, because it's defined coinductively.
   And we cannot do coinduction on the typ_has/hasnt in the conclusion, because
   it's defined inductively.
   --> ??? *)
Admitted.
(*
  induction Wf; intro l.
  + (* case wf_top *)
    left. apply typ_top_hasnt.
  + (* case wf_bot *)
    right. exists (dec_bot l). split.
    - destruct l; reflexivity.
    - apply typ_bot_has.
  + (* case wf_rcd_deep *)
    destruct (classicT (l = label_of_dec D)) as [Eq | Ne].
    - right. exists D. split.
      * apply Eq.
      * apply typ_rcd_has.
    - left. apply (typ_rcd_hasnt _ _ Ne).
  + (* case wf_rcd_shallow  *)
    destruct (classicT (l = label_of_dec D)) as [Eq | Ne].
    - right. exists D. split.
      * apply Eq.
      * apply typ_rcd_has.
    - left. apply (typ_rcd_hasnt _ _ Ne).
  + (* case wf_sel *)
    specialize (IHWf2 l). destruct IHWf2 as [UHasnt | [D [Eq UHas]]].
    - left. apply (typ_sel_hasnt H H0 UHasnt).
    - right. exists D. split.
      * apply Eq.
      * apply (typ_sel_has H H0 UHas).
  + (* case wf_and *)
    specialize (IHWf1 l). specialize (IHWf2 l).
    destruct IHWf1 as [T1Hasnt | [D1 [Eq1 T1Has]]];
    destruct IHWf2 as [T2Hasnt | [D2 [Eq2 T2Has]]].
    - left. apply (typ_and_hasnt T1Hasnt T2Hasnt).
    - right. exists D2. apply (conj Eq2).
      rewrite Eq2 in T1Hasnt. apply (typ_and_has_2 T1Hasnt T2Has).
    - right. exists D1. apply (conj Eq1).
      rewrite Eq1 in T2Hasnt. apply (typ_and_has_1 T1Has T2Hasnt).
    - right.
      lets Eq12: Eq2. rewrite Eq1 in Eq12.
      destruct (intersect_dec_total D1 D2 Eq12) as [D12 Eq].
      exists D12. rewrite Eq1.
      apply (conj (proj32 (intersect_dec_label_eq _ _ Eq))).
      apply (typ_and_has_12 T1Has T2Has Eq).
  + (* case wf_or *)
    specialize (IHWf1 l). specialize (IHWf2 l).
    destruct IHWf1 as [T1Hasnt | [D1 [Eq1 T1Has]]];
    destruct IHWf2 as [T2Hasnt | [D2 [Eq2 T2Has]]].
    - left. apply (typ_or_hasnt_1 _ T1Hasnt).
    - left. apply (typ_or_hasnt_1 _ T1Hasnt).
    - left. apply (typ_or_hasnt_2 _ T2Hasnt).
    - right.
      lets Eq12: Eq2. rewrite Eq1 in Eq12.
      destruct (union_dec_total D1 D2 Eq12) as [D12 Eq].
      exists D12. rewrite Eq1.
      apply (conj (proj32 (union_dec_label_eq _ _ Eq))).
      apply (typ_or_has T1Has T2Has Eq).
Qed.

Print Assumptions typ_has_total.
*)

(* ###################################################################### *)
(** ** Uniqueness *)

Lemma intersect_dec_unique: forall D1 D2 D3 D4,
  D1 && D2 == D3 ->
  D1 && D2 == D4 ->
  D3 = D4.
Proof.
  introv Eq3 Eq4. rewrite Eq3 in Eq4. inversions Eq4. reflexivity.
Qed.

Lemma union_dec_unique: forall D1 D2 D3 D4,
  D1 || D2 == D3 ->
  D1 || D2 == D4 ->
  D3 = D4.
Proof.
  introv Eq3 Eq4. rewrite Eq3 in Eq4. inversions Eq4. reflexivity.
Qed.

(* need to prove the same things several times to make sure we always have an IH *)
Lemma typ_has_unique_and_not_hasnt:
   (forall G T D1, typ_has G T D1 ->
        (forall D2, typ_has G T D2 -> label_of_dec D1 = label_of_dec D2 -> D1 = D2)
     /\ (typ_hasnt G T (label_of_dec D1) -> False))
/\ (forall G T l, typ_hasnt G T l ->
      forall D, l = label_of_dec D -> typ_has G T D -> False).
Proof.
  apply typ_has_mutind; try split.
  + (* case typ_bot_has *)
    introv Has Eq. inversions Has; simpl in Eq; try discriminate.
    destruct l; destruct l0; simpl in *; inversions Eq; reflexivity.
  + (* case typ_bot_has *)
    introv Hasnt. inversions Hasnt.
  + (* case typ_rcd_has *)
    introv Has Eq. inversions Has. reflexivity.
  + (* case typ_rcd_has *)
    introv Hasnt. inversions Hasnt. apply H1. reflexivity.
  + (* case typ_sel_has *)
    rename b into Bi, t into THas, H into IH1, t0 into HiHas, H0 into IH2.
    introv Has' Eq.
    inversions Has'. rename T0 into T', H1 into Bi', H3 into THas', H5 into HiHas'.
    lets EqT: (binds_func Bi' Bi). subst T'. clear Bi'.
    destruct IH1 as [IH1 _]. destruct IH2 as [IH2 _].
    specialize (IH1 _ THas' eq_refl). symmetry in IH1. inversions IH1.
    apply (IH2 _ HiHas' Eq).
  + (* case typ_sel_has *)
    rename b into Bi, t into THas, H into IH1, t0 into HiHas, H0 into IH2.
    introv Hasnt.
    destruct IH2 as [_ IH2]. inversions Hasnt.
    rename T0 into T', H1 into Bi', H3 into THas', H5 into HiHasnt.
    lets EqT: (binds_func Bi' Bi). subst T'. clear Bi'.
    destruct IH1 as [IH1 _]. specialize (IH1 _ THas' eq_refl).
    symmetry in IH1. inversions IH1. apply (IH2 HiHasnt).
  + (* case typ_and_has_1 *)
    rename t into T1Has, H into IH1, t0 into T2Hasnt, H0 into IH2.
    introv Has' Eq. destruct IH1 as [IH1 _].
    inversions Has'.
    - eauto.
    - exfalso. apply (IH2 _ Eq H4).
    - exfalso. refine (IH2 _ _ H3).
      rewrite Eq. symmetry. apply (proj33 (intersect_dec_label_eq _ _ H5)).
  + (* case typ_and_has_1 *)
    rename t into T1Has, H into IH1, t0 into T2Has, H0 into IH2.
    introv T12Hasnt. inversions T12Hasnt. destruct IH1 as [_ IH1]. apply (IH1 H2).
  + (* case typ_and_has_2 *)
    rename t into T1Hasnt, H into IH1, t0 into T2Has, H0 into IH2.
    introv Has' Eq. destruct IH2 as [IH2 _].
    inversions Has'.
    - exfalso. refine (IH1 _ Eq H2).
    - eauto.
    - exfalso. refine (IH1 _ _ H1).
      rewrite Eq. symmetry. apply (proj32 (intersect_dec_label_eq _ _ H5)).
  + (* case typ_and_has_2 *)
    rename t into T1Hasnt, H into IH1, t0 into T2Has, H0 into IH2.
    introv T12Hasnt. inversions T12Hasnt. destruct IH2 as [_ IH2]. apply (IH2 H4).
  + (* case typ_and_has_12 *)
    rename t into T1Has, H into IH1, t0 into T2Has, H0 into IH2.
    introv Has' Eq.
    remember (label_of_dec D0) as l eqn: Eq0.
    symmetry in Eq. rename Eq into Eq3.
    destruct (intersect_dec_label_eq _ _ e) as [Eq12 [Eq13 Eq23]].
    rewrite <- Eq3 in Eq23. symmetry in Eq23; rename Eq23 into Eq2.
    rewrite <- Eq3 in Eq13. symmetry in Eq13; rename Eq13 into Eq1. clear Eq12.
    lets Eq: (conj Eq0 (conj Eq1 (conj Eq2 Eq3))). clear Eq0 Eq1 Eq2 Eq3.
    inversions Has'.
    - exfalso. rewrite <- (proj41 Eq) in H4. rewrite (proj43 Eq) in H4.
      destruct IH2 as [_ IH2]. apply (IH2 H4).
    - exfalso. rewrite <- (proj41 Eq) in H2. rewrite (proj42 Eq) in H2.
      destruct IH1 as [_ IH1]. apply (IH1 H2).
    - destruct (intersect_dec_label_eq _ _ H5) as [Eq45 [Eq40 Eq50]].
      destruct IH1 as [IH1 _]. specialize (IH1 D4).
      rewrite Eq40 in IH1. rewrite <- (proj41 Eq) in IH1. rewrite <- (proj42 Eq) in IH1.
      specialize (IH1 H1 eq_refl). subst D4.
      destruct IH2 as [IH2 _]. specialize (IH2 D5).
      rewrite Eq50 in IH2. rewrite <- (proj41 Eq) in IH2. rewrite <- (proj43 Eq) in IH2.
      specialize (IH2 H3 eq_refl). subst D5.
      apply (intersect_dec_unique _ _ e H5).
  + (* case typ_and_has_12 *)
    rename t into T1Hasnt, H into IH1, t0 into T2Has, H0 into IH2.
    introv T12Hasnt. inversions T12Hasnt. destruct IH2 as [_ IH2].
    destruct (intersect_dec_label_eq _ _ e) as [Eq12 [Eq13 Eq23]].
    rewrite Eq23 in IH2. apply (IH2 H4).
  + (* case typ_or_has *)
    rename t into T1Has, H into IH1, t0 into T2Has, H0 into IH2.
    introv T12Has Eq. inversions T12Has.
    remember (label_of_dec D0) as l eqn: Eq0.
    symmetry in Eq. rename Eq into Eq3.
    destruct (union_dec_label_eq _ _ e) as [Eq12 [Eq13 Eq23]].
    destruct (union_dec_label_eq _ _ H5) as [Eq45 [Eq40 Eq50]].
    destruct IH1 as [IH1 _]. specialize (IH1 D4).
    rewrite Eq40 in IH1. rewrite <- Eq0 in IH1. rewrite Eq3 in IH1.
    specialize (IH1 H1 Eq13). subst D4.
    destruct IH2 as [IH2 _]. specialize (IH2 D5).
    rewrite Eq50 in IH2. rewrite <- Eq0 in IH2. rewrite Eq3 in IH2.
    specialize (IH2 H3 Eq23). subst D5.
    apply (union_dec_unique _ _ e H5).
  + (* case typ_or_has *)
    rename t into T1Has, H into IH1, t0 into T2Has, H0 into IH2.
    destruct (union_dec_label_eq _ _ e) as [Eq12 [Eq13 Eq23]].
    introv T12Hasnt. inversions T12Hasnt.
    - destruct IH1 as [_ IH1].
      rewrite Eq13 in IH1. apply (IH1 H3).
    - destruct IH2 as [_ IH2].
      rewrite Eq23 in IH2. apply (IH2 H3).
  + (* case typ_top_hasnt *)
    introv Eq Has. inversions Has.
  + (* case typ_rcd_hasnt *)
    introv Ne Eq Has. inversions Has. apply Ne. reflexivity.
  + (* case typ_sel_hasnt *)
    introv Bi THas IH1 HiHasnt IH2 Eq Has'.
    inversions Has'. rename T0 into T', H1 into Bi', H3 into THas', H5 into HiHas.
    lets EqT: (binds_func Bi' Bi). subst T'. clear Bi'.
    destruct IH1 as [IH1 _]. specialize (IH1 _ THas' eq_refl).
    symmetry in IH1. inversions IH1. apply (IH2 _ eq_refl HiHas).
  + (* case typ_and_hasnt *)
    introv T1Hasnt IH1 T2Hasnt IH2 Eq Has'.
    inversions Has'.
    - eauto.
    - eauto.
    - destruct (intersect_dec_label_eq _ _ H5) as [Eq12 [Eq1 Eq2]].
      rewrite <- Eq1 in *. apply (IH1 _ eq_refl H1).
  + (* case typ_or_hasnt_1 *)
    introv T1Hasnt IH Eq Has'. inversions Has'.
    destruct (union_dec_label_eq _ _ H5) as [Eq12 [Eq1 Eq2]].
    rewrite <- Eq1 in *. apply (IH _ eq_refl H1).
  + (* case typ_or_hasnt_2 *)
    introv T2Hasnt IH Eq Has'. inversions Has'.
    destruct (union_dec_label_eq _ _ H5) as [Eq12 [Eq1 Eq2]].
    rewrite <- Eq2 in *. apply (IH _ eq_refl H3).
Qed.

Print Assumptions typ_has_unique_and_not_hasnt.

Lemma typ_has_unique: forall G T D1 D2,
  typ_has G T D1 ->
  typ_has G T D2 ->
  label_of_dec D1 = label_of_dec D2 ->
  D1 = D2.
Proof.
  introv H1 H2 Eq.
  destruct typ_has_unique_and_not_hasnt as [P _].
  specialize (P G T D1 H1). destruct P as [P _]. apply (P _ H2 Eq).
Qed.

Lemma not_typ_has_and_hasnt: forall G T D,
  typ_has G T D -> typ_hasnt G T (label_of_dec D) -> False.
Proof.
  introv Has Hasnt.
  destruct typ_has_unique_and_not_hasnt as [_ P].
  apply (P G T (label_of_dec D) Hasnt D eq_refl Has).
Qed.


(* ###################################################################### *)
(** ** Looks like rules, but follows from the rules *)

(* take subtyp_and/or rules and replace "and" by "intersect", "or" by "union":

Lemma subtyp_intersect : forall (G : ctx) (S T1 T2 : typ),
  subtyp G S T1 -> subtyp G S T2 -> subtyp G S (intersect_typ T1 T2).
Proof.
  intros. destruct T1; destruct T2; unfold intersect_typ; case_if; simpl; auto.
Qed.

(*
Lemma subtyp_intersect_l : forall (G : ctx) (T1 T2 S : typ),
  subtyp G T1 S ->
  subtyp G (intersect_typ T1 T2) S.
Proof.
  intros. destruct (subtyp_regular H) as [WfT1 WfS].
  destruct T1; destruct T2; destruct S; simpl; unfold intersect_typ; case_if; auto.
  refine (subtyp_trans (subtyp_top _) H); auto.
Qed.

Lemma subtyp_intersect_r : forall (G : ctx) (T1 T2 S : typ),
  subtyp G T2 S -> subtyp G (intersect_typ T1 T2) S.
Proof.
  intros.
  destruct T1; destruct T2; destruct S; simpl; auto;
  apply (subtyp_trans (subtyp_top _ _) H).
Qed.
*)

Lemma subtyp_union : forall (G : ctx) (T1 T2 S : typ),
  subtyp G T1 S -> subtyp G T2 S -> subtyp G (union_typ T1 T2) S.
Proof.
  intros.
  destruct T1; destruct T2; destruct S; unfold union_typ; case_if; simpl; auto.
Qed.

(*
Lemma subtyp_union_l : forall (G : ctx) (S T1 T2 : typ),
  subtyp G S T1 -> subtyp G S (union_typ T1 T2).
Proof.
  intros.
  destruct T1; destruct T2; destruct S; simpl; auto;
  apply (subtyp_trans H (subtyp_bot _ _)).
Qed.

Lemma subtyp_union_r: forall (G : ctx) (S T1 T2 : typ),
  subtyp G S T2 -> subtyp G S (union_typ T1 T2).
Proof.
  intros.
  destruct T1; destruct T2; destruct S; simpl; auto;
  apply (subtyp_trans H (subtyp_bot _ _)).
Qed.

Hint Resolve subtyp_intersect subtyp_intersect_l subtyp_intersect_r
             subtyp_union     subtyp_union_l     subtyp_union_r.
*)

Hint Resolve subtyp_intersect subtyp_union.
*)

Lemma subdec_refl: forall G D,
  wf_dec G D ->
  subdec G D D.
Proof.
  introv Wf. inversions Wf; eauto.
Qed.

Lemma subdec_bot: forall G D,
  wf_dec G D ->
  subdec G (dec_bot (label_of_dec D)) D.
Proof.
  introv Wf. inversions Wf; simpl; eauto.
Qed.

Lemma subdec_intersect: forall G D0 D1 D2 D12,
  subdec G D0 D1 ->
  subdec G D0 D2 ->
  D1 && D2 == D12 ->
  subdec G D0 D12.
Proof.
  introv Sd01 Sd02 I. inversions Sd01; inversions Sd02;
  unfold intersect_dec in I; case_if; inversions I; auto.
Qed.

Lemma subdec_union: forall G D D1 D2 D12,
  subdec G D1 D ->
  subdec G D2 D ->
  D1 || D2 == D12 ->
  subdec G D12 D.
Proof.
  introv Sd01 Sd02 I. inversions Sd01; inversions Sd02;
  unfold union_dec in I; case_if; inversions I; auto.
Qed.

Lemma subdec_intersect_l: forall G D1 D2 D12,
  D1 && D2 == D12 ->
  wf_dec G D1 ->
  wf_dec G D12 ->
  subdec G D12 D1.
Proof.
  introv Eq WfD1 WfD12. unfold intersect_dec in Eq. case_if.
  destruct D1 as [L1 S1 U1 | m1 S1 U1];
  destruct D2 as [L2 S2 U2 | m2 S2 U2];
  inversions Eq;
  destruct_wf;
  eauto.
Qed.

Lemma subdec_intersect_r: forall G D1 D2 D12,
  D1 && D2 == D12 ->
  wf_dec G D2 ->
  wf_dec G D12 ->
  subdec G D12 D2.
Proof.
  introv Eq WfD2 WfD12. unfold intersect_dec in Eq. case_if.
  destruct D1 as [L1 S1 U1 | m1 S1 U1];
  destruct D2 as [L2 S2 U2 | m2 S2 U2];
  inversions Eq;
  inversions H;
  destruct_wf;
  eauto.
Qed.

Lemma subdec_union_l: forall G D1 D2 D12,
  D1 || D2 == D12 ->
  wf_dec G D1 ->
  wf_dec G D2 ->
  subdec G D1 D12.
Proof.
  introv Eq Wf1 Wf2. unfold union_dec in Eq. case_if.
  destruct D1 as [L1 S1 U1 | m1 S1 U1];
  destruct D2 as [L2 S2 U2 | m2 S2 U2];
  inversions Eq;
  inversions H;
  destruct_wf;
  eauto.
Qed.

Lemma subdec_union_r: forall G D1 D2 D12,
  D1 || D2 == D12 ->
  wf_dec G D1 ->
  wf_dec G D2 ->
  subdec G D2 D12.
Proof.
  introv Eq Wf1 Wf2. unfold union_dec in Eq. case_if.
  destruct D1 as [L1 S1 U1 | m1 S1 U1];
  destruct D2 as [L2 S2 U2 | m2 S2 U2];
  inversions Eq;
  inversions H;
  destruct_wf;
  eauto.
Qed.


(* ###################################################################### *)
(** ** subtyp-and-then-lookup_tdec to lookup_tdec-and-then-subdec *)

Lemma intersect_dec_preserves_wf: forall G D1 D2 D3,
  D1 && D2 == D3 ->
  wf_dec G D1 ->
  wf_dec G D2 ->
  wf_dec G D3.
Proof.
  introv Eq Wf1 Wf2. unfold intersect_dec in Eq. case_if.
  destruct D1 as [L1 S1 U1 | m1 S1 U1];
  destruct D2 as [L2 S2 U2 | m2 S2 U2];
  inversions Eq;
  inversions Wf1; inversions Wf2;
  eauto.
Qed.

Lemma union_dec_preserves_wf: forall G D1 D2 D3,
  D1 || D2 == D3 ->
  wf_dec G D1 ->
  wf_dec G D2 ->
  wf_dec G D3.
Proof.
  introv Eq Wf1 Wf2. unfold union_dec in Eq. case_if.
  destruct D1 as [L1 S1 U1 | m1 S1 U1];
  destruct D2 as [L2 S2 U2 | m2 S2 U2];
  inversions Eq;
  inversions Wf1; inversions Wf2;
  eauto.
Qed.

Lemma typ_has_preserves_wf: forall G T D,
  typ_has G T D ->
  wf_typ G T ->
  wf_dec G D.
Proof.
  introv Has. induction Has; introv Wf.
  + (* case typ_bot_has *)
    destruct l; simpl; eauto.
  + (* case typ_rcd_has *)
    inversions Wf. eauto.
  + (* case typ_sel_has *)
    inversions Wf. (* <-- gives us full wf-ness of bounds, wouldn't be possible with
      induction, so that's why we need to define wf_typ/wf_dec coinductively. *)
    lets Eq: (binds_func H H2). subst T.
    lets Eq: (typ_has_unique H3 Has1 eq_refl). inversions Eq.
    apply IHHas2. assumption.
  + (* case typ_and_has_1 *)
    inversions Wf. eauto.
  + (* case typ_and_has_2 *)
    inversions Wf. eauto.
  + (* case typ_and_has_12 *)
    inversions Wf. apply (intersect_dec_preserves_wf H); auto.
  + (* case typ_or_has *)
    inversions Wf. apply (union_dec_preserves_wf H); auto.
Qed.

Print Assumptions typ_has_preserves_wf.

Lemma subdec_trans: forall G D1 D2 D3,
  subdec G D1 D2 -> subdec G D2 D3 -> subdec G D1 D3.
Proof.
  introv H12 H23. inversions H12; inversions H23; constructor;
  solve [ assumption | (eapply subtyp_trans; eassumption)].
Qed.

Lemma swap_sub_and_typ_has: forall G T1 T2 D2,
  subtyp G T1 T2 ->
  typ_has G T2 D2 ->
  exists D1,
    typ_has G T1 D1 /\
    subdec G D1 D2.
Proof.
  introv St. gen D2. induction St; introv T2Has.
  + (* case subtyp_refl *)
    eexists. apply (conj T2Has). apply subdec_refl.
    apply (typ_has_preserves_wf T2Has H).
  + (* case subtyp_top *)
    inversions T2Has.
  + (* case subtyp_bot *)
    rename T into T2.
    exists (dec_bot (label_of_dec D2)). split.
    - auto.
    - apply subdec_bot. apply (typ_has_preserves_wf T2Has H).
  + (* case subtyp_rcd *)
    inversions T2Has. rename D0 into D2. exists D1. auto.
  + (* case subtyp_sel_l *)
    rename H into Bi, H0 into XHas.
    exists D2. split.
    - eauto.
    - apply subdec_refl. apply (typ_has_preserves_wf T2Has).
      apply (proj2 (subtyp_regular St)).
  + (* case subtyp_sel_r *)
    rename H into Bi, H0 into XHas.
    inversions T2Has.
    lets Eq: (binds_func H1 Bi). subst T0.
    apply IHSt. clear IHSt.
    lets Eq: (typ_has_unique H3 XHas eq_refl). inversions Eq.
    exact H5.
  + (* case subtyp_and *)
    inversions T2Has.
    - eauto.
    - eauto.
    - rename H1 into U1Has, H3 into U2Has, H5 into Eq, D1 into DU1, D0 into DU2.
      specialize (IHSt1 _ U1Has). destruct IHSt1 as [D1 [THas Sd1]].
      specialize (IHSt2 _ U2Has). destruct IHSt2 as [D1' [THas' Sd2]].
      destruct (intersect_dec_label_eq _ _ Eq) as [Eq1 _].
      lets Eql1: (subdec_to_label_of_dec_eq Sd1).
      lets Eql2: (subdec_to_label_of_dec_eq Sd2).
      rewrite <- Eq1 in Eql2. rewrite <- Eql1 in Eql2.
      lets Eq': (typ_has_unique THas' THas Eql2). subst D1'. clear THas'.
      exists D1. apply (conj THas).
      apply (subdec_intersect Sd1 Sd2 Eq).
  + (* case subtyp_and_l *)
    rename T2Has into T1Has, D2 into D1, H into WfT1, H0 into WfT2.
    lets T2Has: (typ_has_total WfT2). specialize (T2Has (label_of_dec D1)).
                (*************)
    destruct T2Has as [T2Hasnt | [D2 [Eq T2Has]]].
    - exists D1. split.
      * auto.
      * apply subdec_refl. apply (typ_has_preserves_wf T1Has WfT1).
    - destruct (intersect_dec_total _ _ Eq) as [D12 Eq12]. exists D12. split.
      * eauto.
      * lets WfD1: (typ_has_preserves_wf T1Has WfT1).
        lets WfD2: (typ_has_preserves_wf T2Has WfT2).
        lets WfD12: (intersect_dec_preserves_wf Eq12 WfD1 WfD2).
        apply (subdec_intersect_l _ Eq12 WfD1 WfD12).
  + (* case subtyp_and_r *)
    rename H into WfT1, H0 into WfT2.
    lets T1Has: (typ_has_total WfT1). specialize (T1Has (label_of_dec D2)).
                (*************)
    destruct T1Has as [T1Hasnt | [D1 [Eq T1Has]]].
    - exists D2. split.
      * auto.
      * apply subdec_refl. apply (typ_has_preserves_wf T2Has WfT2).
    - symmetry in Eq.
      destruct (intersect_dec_total _ _ Eq) as [D12 Eq12]. exists D12. split.
      * eauto.
      * lets WfD1: (typ_has_preserves_wf T1Has WfT1).
        lets WfD2: (typ_has_preserves_wf T2Has WfT2).
        lets WfD12: (intersect_dec_preserves_wf Eq12 WfD1 WfD2).
        apply (subdec_intersect_r _ Eq12 WfD2 WfD12).
  + (* case subtyp_or *)
    rename T2Has into UHas.
    specialize (IHSt1 _ UHas). destruct IHSt1 as [D01 [T1Has Sd1]].
    specialize (IHSt2 _ UHas). destruct IHSt2 as [D02 [T2Has Sd2]].
    lets Eql1: (subdec_to_label_of_dec_eq Sd1).
    lets Eql2: (subdec_to_label_of_dec_eq Sd2).
    rewrite <- Eql2 in Eql1.
    destruct (union_dec_total _ _ Eql1) as [D12 Eq12]. exists D12. split.
    - apply (typ_or_has T1Has T2Has Eq12).
    - apply (subdec_union Sd1 Sd2 Eq12).
  + (* case subtyp_or_l *)
    inversions T2Has. rename H3 into T1Has, H5 into T2Has, D2 into D12, D0 into D2.
    exists D1. apply (conj T1Has). apply (subdec_union_l H7).
    - apply (typ_has_preserves_wf T1Has H).
    - apply (typ_has_preserves_wf T2Has H0).
  + (* case subtyp_or_r *)
    inversions T2Has. rename H3 into T1Has, H5 into T2Has, D2 into D12, D0 into D2.
    exists D2. apply (conj T2Has). apply (subdec_union_r H7).
    - apply (typ_has_preserves_wf T1Has H).
    - apply (typ_has_preserves_wf T2Has H0).
  + (* case subtyp_trans *)
    rename D2 into D3, T2Has into T3Has.
    specialize (IHSt2 _ T3Has).
    destruct IHSt2 as [D2 [T2Has Sd23]].
    specialize (IHSt1 _ T2Has).
    destruct IHSt1 as [D1 [T1Has Sd12]].
    exists D1. apply (conj T1Has). apply (subdec_trans Sd12 Sd23).
Qed.

Print Assumptions swap_sub_and_typ_has. (* typ_has_total!! *)


(* ###################################################################### *)
(** ** Narrowing *)

Lemma narrow_binds: forall G1 x0 S1 S2 G2 x T2,
  binds x T2 (G1 & x0 ~ S2 & G2) ->
  subtyp (G1 & x0 ~ S1 & G2) S1 S2 ->
  exists T1,
    binds x T1 (G1 & x0 ~ S1 & G2) /\
    (subtyp (G1 & x0 ~ S1 & G2) T1 T2 \/ T1 = T2).
Proof.
  introv Bi StS.
  apply binds_middle_inv in Bi.
  destruct Bi as [Bi | [[xG2 [Eq1 Eq2]]|[xG2 [Ne Bi]]]].
  - (* case x in G2 *)
    apply (binds_concat_right (G1 & x0 ~ S1)) in Bi.
    exists T2. auto.
  - (* case x = x0 *)
    subst x0 T2. exists S1.
    apply (conj (binds_middle_eq _ _ xG2)).
    left. apply StS.
  - (* case x in G1 *)
    exists T2. refine (conj _ (or_intror eq_refl)).
    assert (xx0: x # (x0 ~ S1)) by auto.
    apply (binds_concat_left (binds_concat_left Bi xx0) xG2).
Qed.

Print Assumptions narrow_binds.

(* Note: narrowing for typ_hasnt doesn't hold. *)

Lemma narrow_typ_has:
    forall G T D2, typ_has G T D2 -> forall G1 x S1 S2 G2,
    G = G1 & x ~ S2 & G2 ->
    subtyp (G1 & x ~ S1 & G2) S1 S2 ->
    exists D1,
      typ_has (G1 & x ~ S1 & G2) T D1 /\
      (subdec (G1 & x ~ S1 & G2) D1 D2 \/ D1 = D2).
Proof.
  introv Has. induction Has; introv Eq St; subst.
  + (* case typ_bot_has *)
    exists (dec_bot l). split; [eauto | destruct l; simpl; eauto].
  + (* case typ_rcd_has *)
    exists D. eauto.
  + (* case typ_sel_has *)
    rename Lo into Lo2, Hi into Hi2, D into D2, T into X2.
    specialize (IHHas1 _ _ _ _ _ eq_refl St). destruct IHHas1 as [D0 [X2Has Sd0]].
    specialize (IHHas2 _ _ _ _ _ eq_refl St). destruct IHHas2 as [D1 [HiHas Sd]].
    destruct Sd0 as [Sd0 | Eq].
    - apply invert_subdec_typ_sync_left in Sd0.
      destruct Sd0 as [Lo1 [Hi1 [Eq [StLo StHi]]]]. subst D0.
      destruct Sd as [Sd | Eq].
      * lets N: (narrow_binds H St). destruct N as [X1 [Bi1 StX]].
        destruct StX as [StX | Eq].
        { admit. (* TODO needs exp_preserves_sub *) }
        { subst X1. rename X2 into X. exists D1. split; auto.
          (* TODO also needs exp_preserves_sub *) admit. }
      * subst D1. rename D2 into D. exists D.

    exists D1.

  + (* case typ_and_has_1 *) eauto.
  + (* case typ_and_has_2 *) eauto.
  + (* case typ_and_has_12 *) eauto.
  + (* case typ_or_has *) eauto.

Qed.


Lemma narrow_typ_has_tdec: forall G1 x S1 S2 G2 T L Lo2 Hi2,
  typ_has_tdec (G1 & x ~ S2 & G2) T L Lo2 Hi2 ->
  subtyp (G1 & x ~ S1) S1 S2 ->
  exists Lo1 Hi1,
    typ_has_tdec (G1 & x ~ S1 & G2) T L Lo1 Hi1 /\
    subtyp (G1 & x ~ S1 & G2) Lo2 Lo1 /\
    subtyp (G1 & x ~ S1 & G2) Hi1 Hi2.
(*
Proof.
  introv THas2 StS. unfold typ_has_tdec in THas2. destruct THas2 as [minF THas2].
  gen StS. gen THas2. gen G1 x S1 S2 G2 T L Lo2 Hi2. induction minF; introv THas2 StS.
  - specialize (THas2 0 (Le.le_refl _)). unfold lookup_tdec in THas2. inversions THas2.
    lets THas1: (typ_has_tdec_total (G1 & x ~ S1 & G2) T L).
                (******************)
    destruct THas1 as [Lo1 [Hi1 THas1]].
    exists Lo1 Hi1. apply (conj THas1). auto. 
  - 
*)
Proof.
  introv THas2 StS. unfold typ_has_tdec in THas2. destruct THas2 as [minF THas2].
  induction minF.
  - specialize (THas2 0 (Le.le_refl _)). unfold lookup_tdec in THas2. inversions THas2.
    lets THas1: (typ_has_tdec_total (G1 & x ~ S1 & G2) T L).
                (******************)
    destruct THas1 as [Lo1 [Hi1 THas1]].
    exists Lo1 Hi1. apply (conj THas1). auto.
  - apply IHminF. intros. destruct (classicT (minF = fuel)) as [Eq | Ne].
    * admit. (*???*)
    * assert (C: S minF <= fuel) by omega. apply (THas2 _ C).   
Qed.

Lemma narrow_subtyp: forall G T1 T2, subtyp G T1 T2 ->
  forall G1 x S1 S2 G2,
    G = G1 & x ~ S2 & G2 ->
    subtyp (G1 & x ~ S1) S1 S2 ->
    subtyp (G1 & x ~ S1 & G2) T1 T2.
Proof.
  introv St. induction St; introv Eq StS; subst.
  + (* case subtyp_refl *) eauto.
  + (* case subtyp_top *) eauto.
  + (* case subtyp_bot *) eauto.
  + (* case subtyp_tdec *) eauto.
  + (* case subtyp_mdec *) eauto.
  + (* case subtyp_sel_l *)
    rename H into Bi2, H0 into X2Has2, X into X2.
    specialize (IHSt _ _ _ _ _ eq_refl StS).
    assert (Ok2: ok (G1 & x0 ~ S2 & G2)) by admit.
    assert (Ok1: ok (G1 & x0 ~ S1 & G2)) by admit.
    lets P: (narrow_binds Bi2 StS). destruct P as [X1 [Bi1 StX]].
    destruct (narrow_typ_has_tdec X2Has2 StS) as [T' [U' [X2Has1 [StT StU]]]].
    lets P: (swap_sub_and_typ_has_tdec StX X2Has1).
    destruct P as [T'' [U'' [X1Has [StT' StU']]]].
    assert (St': subtyp (G1 & x0 ~ S1 & G2) T'' U'') by admit. (* <--- !!! Will have
        to add good-bounds hyp to env, but do we always have this?? *)
    refine (subtyp_trans _ StU).
    refine (subtyp_trans _ StU').
    apply (subtyp_sel_l Bi1 X1Has St').
  + (* case subtyp_sel_r *)
    rename H into Bi2, H0 into X2Has2, X into X2.
    specialize (IHSt _ _ _ _ _ eq_refl StS).
    assert (Ok2: ok (G1 & x0 ~ S2 & G2)) by admit.
    assert (Ok1: ok (G1 & x0 ~ S1 & G2)) by admit.
    lets P: (narrow_binds Bi2 StS). destruct P as [X1 [Bi1 StX]].
    destruct (narrow_typ_has_tdec X2Has2 StS) as [T' [U' [X2Has1 [StT StU]]]].
    lets P: (swap_sub_and_typ_has_tdec StX X2Has1).
    destruct P as [T'' [U'' [X1Has [StT' StU']]]].
    assert (St': subtyp (G1 & x0 ~ S1 & G2) T'' U'') by admit. (* <--- !!! Will have
        to add good-bounds hyp to env, but do we always have this?? *)
    refine (subtyp_trans StT _).
    refine (subtyp_trans StT' _).
    apply (subtyp_sel_r Bi1 X1Has St').
  + (* case subtyp_and *) eauto.
  + (* case subtyp_and_l *) eauto.
  + (* case subtyp_and_r *) eauto.
  + (* case subtyp_or *) eauto.
  + (* case subtyp_or_l *) eauto.
  + (* case subtyp_or_r *) eauto.
  + (* case subtyp_trans *)
    apply subtyp_trans with T2; eauto.
Qed.

