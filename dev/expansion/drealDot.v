
Set Implicit Arguments.

(* CoqIDE users: Run open.sh (in ./ln) to start coqide, then open this file. *)
Require Import LibLN.


(* ###################################################################### *)
(* ###################################################################### *)
(** * Definitions *)

(* ###################################################################### *)
(** ** Syntax *)

(** If it's clear whether a type, field or method is meant, we use nat, 
    if not, we use label: *)
Inductive label: Type :=
| label_typ: nat -> label
| label_fld: nat -> label
| label_mtd: nat -> label.

Inductive avar : Type :=
  | avar_b : nat -> avar  (* bound var (de Bruijn index) *)
  | avar_f : var -> avar. (* free var ("name"), refers to tenv or venv *)

Inductive pth : Type :=
  | pth_var : avar -> pth
(*| pth_sel : pth -> label -> pth*).

Inductive typ : Type :=
  | typ_top : typ
  | typ_bot : typ
  | typ_rfn : typ -> decs -> typ (* T { z => Ds } *)
  | typ_sel : pth -> label -> typ (* p.L *)
  | typ_and : typ -> typ -> typ
  | typ_or  : typ -> typ -> typ
with dec : Type :=
  | dec_typ  : typ -> typ -> dec
  | dec_fld  : typ -> dec
  | dec_mtd : typ -> typ -> dec
with decs : Type :=
  | decs_nil : decs
  | decs_cons : nat -> dec -> decs -> decs.

Inductive trm : Type :=
  | trm_var  : avar -> trm
  | trm_new  : typ -> defs -> trm
  | trm_sel  : trm -> nat -> trm
  | trm_call : trm -> nat -> trm -> trm
with def : Type :=
  | def_typ : def (* just a placeholder *)
  | def_fld : avar -> def (* cannot have term here, need to assign first *)
  | def_mtd : trm -> def (* one nameless argument *)
with defs : Type :=
  | defs_nil : defs
  | defs_cons : nat -> def -> defs -> defs.

Inductive obj : Type :=
  | object : typ -> defs -> obj. (* T { z => ds } *)

(** *** Typing environment ("Gamma") *)
Definition ctx := env typ.

(** *** Value environment ("store") *)
Definition sto := env obj.

(** *** Syntactic sugar *)
Definition trm_fun(T U: typ)(body: trm) := 
  trm_new (typ_rfn typ_top (decs_cons 0 (dec_mtd T U)  decs_nil))
                           (defs_cons 0 (def_mtd body) defs_nil).
Definition trm_app(func arg: trm) := trm_call func 0 arg.
Definition trm_let(T U: typ)(rhs body: trm) := trm_app (trm_fun T U body) rhs.
Definition typ_arrow(T1 T2: typ) := typ_rfn typ_top (decs_cons 0 (dec_mtd T1 T2) decs_nil).


(* ###################################################################### *)
(** ** Declaration and definition lists *)

Definition label_for_def(n: nat)(d: def): label := match d with
| def_typ     => label_typ n
| def_fld _   => label_fld n
| def_mtd _   => label_mtd n
end.
Definition label_for_dec(n: nat)(D: dec): label := match D with
| dec_typ _ _ => label_typ n
| dec_fld _   => label_fld n
| dec_mtd _ _ => label_mtd n
end.

Fixpoint get_def(l: label)(ds: defs): option def := match ds with
| defs_nil => None
| defs_cons n d ds' => If l = label_for_def n d then Some d else get_def l ds'
end.
Fixpoint get_dec(l: label)(Ds: decs): option dec := match Ds with
| decs_nil => None
| decs_cons n D Ds' => If l = label_for_dec n D then Some D else get_dec l Ds'
end.

Definition defs_has(ds: defs)(l: label)(d: def): Prop := (get_def l ds = Some d).
Definition decs_has(Ds: decs)(l: label)(D: dec): Prop := (get_dec l Ds = Some D).

Definition defs_hasnt(ds: defs)(l: label): Prop := (get_def l ds = None).
Definition decs_hasnt(Ds: decs)(l: label): Prop := (get_dec l Ds = None).


(* ###################################################################### *)
(** ** Opening *)

(** Opening replaces in some syntax a bound variable with dangling index (k) 
   by a free variable x. *)

Definition open_rec_avar (k: nat) (u: var) (a: avar) : avar :=
  match a with
  | avar_b i => If k = i then avar_f u else avar_b i
  | avar_f x => avar_f x
  end.

Definition open_rec_pth (k: nat) (u: var) (p: pth) : pth :=
  match p with
  | pth_var a => pth_var (open_rec_avar k u a)
  end.

Fixpoint open_rec_typ (k: nat) (u: var) (T: typ) { struct T } : typ :=
  match T with
  | typ_top       => typ_top
  | typ_bot       => typ_bot
  | typ_rfn T Ds  => typ_rfn (open_rec_typ k u T) (open_rec_decs (S k) u Ds)
  | typ_sel p L   => typ_sel (open_rec_pth k u p) L
  | typ_and T1 T2 => typ_and (open_rec_typ k u T1) (open_rec_typ k u T2)
  | typ_or  T1 T2 => typ_or  (open_rec_typ k u T1) (open_rec_typ k u T2)
  end
with open_rec_dec (k: nat) (u: var) (D: dec) { struct D } : dec :=
  match D with
  | dec_typ T U => dec_typ (open_rec_typ k u T) (open_rec_typ k u U)
  | dec_fld T   => dec_fld (open_rec_typ k u T)
  | dec_mtd T U => dec_mtd (open_rec_typ k u T) (open_rec_typ k u U)
  end
with open_rec_decs (k: nat) (u: var) (Ds: decs) { struct Ds } : decs :=
  match Ds with
  | decs_nil          => decs_nil
  | decs_cons n D Ds' => decs_cons n (open_rec_dec k u D) (open_rec_decs k u Ds')
  end.

Fixpoint open_rec_trm (k: nat) (u: var) (t: trm) { struct t } : trm :=
  match t with
  | trm_var a      => trm_var (open_rec_avar k u a)
  | trm_new T ds   => trm_new (open_rec_typ k u T) (open_rec_defs (S k) u ds)
  | trm_sel e n    => trm_sel (open_rec_trm k u e) n
  | trm_call o m a => trm_call (open_rec_trm k u o) m (open_rec_trm k u a)
  end
with open_rec_def (k: nat) (u: var) (d: def) { struct d } : def :=
  match d with
  | def_typ   => def_typ
  | def_fld a => def_fld (open_rec_avar k u a)
  | def_mtd e => def_mtd (open_rec_trm (S k) u e)
  end
with open_rec_defs (k: nat) (u: var) (ds: defs) { struct ds } : defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons n d tl => defs_cons n (open_rec_def k u d) (open_rec_defs k u tl)
  end.

Definition open_avar u a := open_rec_avar  0 u a.
Definition open_pth  u p := open_rec_pth   0 u p.
Definition open_typ  u t := open_rec_typ   0 u t.
Definition open_dec  u d := open_rec_dec   0 u d.
Definition open_decs u l := open_rec_decs  0 u l.
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

Definition fv_pth (p: pth) : vars :=
  match p with
  | pth_var a => fv_avar a
  end.

Fixpoint fv_typ (T: typ) { struct T } : vars :=
  match T with
  | typ_top       => \{}
  | typ_bot       => \{}
  | typ_rfn T Ds  => (fv_typ T) \u (fv_decs Ds)
  | typ_sel p L   => (fv_pth p)
  | typ_and T1 T2 => (fv_typ T1) \u (fv_typ T2)
  | typ_or  T1 T2 => (fv_typ T1) \u (fv_typ T2)
  end
with fv_dec (D: dec) { struct D } : vars :=
  match D with
  | dec_typ T U => (fv_typ T) \u (fv_typ U)
  | dec_fld T   => (fv_typ T)
  | dec_mtd T U => (fv_typ T) \u (fv_typ U)
  end
with fv_decs (Ds: decs) { struct Ds } : vars :=
  match Ds with
  | decs_nil          => \{}
  | decs_cons n D Ds' => (fv_dec D) \u (fv_decs Ds')
  end.

(* Since we define defs ourselves instead of using [list def], we don't have any
   termination proof problems: *)
Fixpoint fv_trm (t: trm) : vars :=
  match t with
  | trm_var x        => (fv_avar x)
  | trm_new T ds     => (fv_typ T) \u (fv_defs ds)
  | trm_sel t l      => (fv_trm t)
  | trm_call t1 m t2 => (fv_trm t1) \u (fv_trm t2)
  end
with fv_def (d: def) : vars :=
  match d with
  | def_typ   => \{}
  | def_fld x => fv_avar x
  | def_mtd u => fv_trm u
  end
with fv_defs(ds: defs) : vars :=
  match ds with
  | defs_nil         => \{}
  | defs_cons n d tl => (fv_def d) \u (fv_defs tl)
  end.


(* ###################################################################### *)
(** ** Operational Semantics *)

(** Note: Terms given by user are closed, so they only contain avar_b, no avar_f.
    Whenever we introduce a new avar_f (only happens in red_new), we choose one
    which is not in the store, so we never have name clashes. *) 
Inductive red : trm -> sto -> trm -> sto -> Prop :=
  (* computation rules *)
  | red_call : forall s x y m Ds ds body,
      binds x (object Ds ds) s ->
      defs_has ds (label_mtd m) (def_mtd body) ->
      red (trm_call (trm_var (avar_f x)) m (trm_var (avar_f y))) s
          (open_trm y body) s
  | red_sel : forall s x y l Ds ds,
      binds x (object Ds ds) s ->
      defs_has ds (label_fld l) (def_fld y) ->
      red (trm_sel (trm_var (avar_f x)) l) s
          (trm_var y) s
  | red_new : forall s T ds x,
      x # s ->
      red (trm_new T ds) s
          (trm_var (avar_f x)) (s & x ~ (object T ds))
  (* congruence rules *)
  | red_call1 : forall s o m a s' o',
      red o s o' s' ->
      red (trm_call o  m a) s
          (trm_call o' m a) s'
  | red_call2 : forall s x m a s' a',
      red a s a' s' ->
      red (trm_call (trm_var (avar_f x)) m a ) s
          (trm_call (trm_var (avar_f x)) m a') s'
  | red_sel1 : forall s o l s' o',
      red o s o' s' ->
      red (trm_sel o  l) s
          (trm_sel o' l) s'.


(* ###################################################################### *)
(** ** Specification of declaration intersection (not yet used) *)

Module Type Decs.

Parameter intersect: decs -> decs -> decs.
Parameter union: decs -> decs -> decs.

Axiom intersect_spec_1: forall l D Ds1 Ds2,
  decs_has    Ds1                l D ->
  decs_hasnt  Ds2                l   ->
  decs_has   (intersect Ds1 Ds2) l D .

Axiom intersect_spec_2: forall l D Ds1 Ds2,
  decs_hasnt Ds1                 l   ->
  decs_has   Ds2                 l D ->
  decs_has   (intersect Ds1 Ds2) l D.

Axiom intersect_spec_12_typ: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_typ n) (dec_typ S1 T1) ->
  decs_has Ds2                 (label_typ n) (dec_typ S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_typ n) (dec_typ (typ_or S1 S2) (typ_and T1 T2)).

Axiom intersect_spec_12_fld: forall n T1 T2 Ds1 Ds2,
  decs_has Ds1                 (label_fld n) (dec_fld T1) ->
  decs_has Ds2                 (label_fld n) (dec_fld T2) ->
  decs_has (intersect Ds1 Ds2) (label_fld n) (dec_fld (typ_and T1 T2)).

Axiom intersect_spec_12_mtd: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_mtd n) (dec_mtd S1 T1) ->
  decs_has Ds2                 (label_mtd n) (dec_mtd S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_mtd n) (dec_mtd (typ_or S1 S2) (typ_and T1 T2)).

Axiom intersect_spec_hasnt: forall l Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_hasnt Ds2 l ->
  decs_hasnt (intersect Ds1 Ds2) l.

End Decs.


(* ###################################################################### *)
(** ** Typing *)

Module Typing (DecsImpl: Decs).
Import DecsImpl.

(* The store is not an argument of the typing judgment because
   * it's only needed in typing_trm_var_s
   * we must allow types in Gamma to depend on values in the store, which seems complicated
   * how can we ensure that the store is well-formed? By requiring it in the "leaf"
     typing rules (those without typing assumptions)? Typing rules become unintuitive,
     and maybe to prove that store is wf, we need to prove what we're about to prove...
*)

(* mode = "is transitivity at top level accepted?" *)
Inductive mode : Type := notrans | oktrans.

(* expansion returns a set of decs without opening them *)
Inductive exp : ctx -> typ -> decs -> Prop :=
  | exp_top : forall G, 
      exp G typ_top decs_nil
(*| exp_bot : typ_bot has no expansion *)
  | exp_rfn : forall G T Ds1 Ds2,
      exp G T Ds1 ->
      exp G (typ_rfn T Ds2) (intersect Ds1 Ds2)
  | exp_sel : forall G x L Lo Hi Ds,
      var_has G x L (dec_typ Lo Hi) ->
      exp G Hi Ds ->
      exp G (typ_sel (pth_var (avar_f x)) L) Ds
  | exp_and : forall G T1 T2 Ds1 Ds2,
      exp G T1 Ds1 ->
      exp G T2 Ds2 ->
      exp G (typ_and T1 T2) (intersect Ds1 Ds2)
  | exp_or : forall G T1 T2 Ds1 Ds2,
      exp G T1 Ds1 ->
      exp G T2 Ds2 ->
      exp G (typ_or T1 T2) (union Ds1 Ds2)
with var_has : ctx -> var -> label -> dec -> Prop :=
  | var_has_dec : forall G x T Ds l D,
      binds x T G ->
      exp G T Ds ->
      decs_has (open_decs x Ds) l D ->
      var_has G x l D.

Inductive subtyp : mode -> ctx -> typ -> typ -> Prop :=
  | subtyp_refl : forall G T,
      subtyp notrans G T T
  | subtyp_top : forall G T,
      subtyp notrans G T typ_top
  | subtyp_bot : forall G T,
      subtyp notrans G typ_bot T
  | subtyp_rfn_l : forall G T Ds S,
      subtyp oktrans G T S ->
      subtyp notrans G (typ_rfn T Ds) S
  | subtyp_rfn_r : forall L G S T DsS DsT,
      subtyp oktrans G S T ->
      exp G S DsS ->
      (forall z, z \notin L ->
                 subdecs oktrans (G & z ~ T) (open_decs z DsS) (open_decs z DsT)) ->
      subtyp notrans G S (typ_rfn T DsT)
  | subtyp_sel_l : forall G x L S U T,
      var_has G x L (dec_typ S U) ->
      subtyp oktrans G U T ->
      subtyp notrans G (typ_sel (pth_var (avar_f x)) L) T
  | subtyp_sel_r : forall G x L S U T,
      var_has G x L (dec_typ S U) ->
      subtyp oktrans G S U -> (* <--- makes proofs a lot easier!! *)
      subtyp oktrans G T S ->
      subtyp notrans G T (typ_sel (pth_var (avar_f x)) L)
  | subtyp_and : forall G S T1 T2,
      subtyp oktrans G S T1 ->
      subtyp oktrans G S T2 ->
      subtyp notrans G S (typ_and T1 T2)
  | subtyp_and_l : forall G T1 T2 S,
      subtyp oktrans G T1 S ->
      subtyp notrans G (typ_and T1 T2) S
  | subtyp_and_r : forall G T1 T2 S,
      subtyp oktrans G T2 S ->
      subtyp notrans G (typ_and T1 T2) S
  | subtyp_or : forall G T1 T2 S,
      subtyp oktrans G T1 S ->
      subtyp oktrans G T2 S ->
      subtyp notrans G (typ_or T1 T2) S
  | subtyp_or_l : forall G S T1 T2,
      subtyp oktrans G S T1 ->
      subtyp notrans G S (typ_or T1 T2)
  | subtyp_or_r : forall G S T1 T2,
      subtyp oktrans G S T2 ->
      subtyp notrans G S (typ_or T1 T2)
  | subtyp_mode : forall G T1 T2,
      subtyp notrans G T1 T2 ->
      subtyp oktrans G T1 T2
  | subtyp_trans : forall G T1 T2 T3,
      subtyp oktrans G T1 T2 ->
      subtyp oktrans G T2 T3 ->
      subtyp oktrans G T1 T3
with subdec : mode -> ctx -> dec -> dec -> Prop :=
  | subdec_refl : forall m G D,
      subdec m G D D
  | subdec_typ : forall m G Lo1 Hi1 Lo2 Hi2,
      (* only allow implementable decl *)
      subtyp m G Lo1 Hi1 ->
      subtyp m G Lo2 Hi2 ->
      (* lhs narrower range than rhs *)
      subtyp m G Lo2 Lo1 ->
      subtyp m G Hi1 Hi2 ->
      (* conclusion *)
      subdec m G (dec_typ Lo1 Hi1) (dec_typ Lo2 Hi2)
  | subdec_fld : forall m G T1 T2,
      subtyp m G T1 T2 ->
      subdec m G (dec_fld T1) (dec_fld T2)
  | subdec_mtd : forall m G S1 T1 S2 T2,
      subtyp m G S2 S1 ->
      subtyp m G T1 T2 ->
      subdec m G (dec_mtd S1 T1) (dec_mtd S2 T2)
with subdecs : mode -> ctx -> decs -> decs -> Prop :=
  | subdecs_empty : forall m G Ds,
      subdecs m G Ds decs_nil
  | subdecs_push : forall m G n Ds1 Ds2 D1 D2,
      decs_has   Ds1 (label_for_dec n D2) D1 ->
      (* decs_hasnt Ds2 (label_for_dec n D2) -> (* we don't accept duplicates in rhs *)*)
      subdec m G D1 D2 ->
      subdecs m G Ds1 Ds2 ->
      subdecs m G Ds1 (decs_cons n D2 Ds2).

Inductive trm_has : ctx -> trm -> label -> dec -> Prop :=
  | trm_has_dec : forall G t T l D Ds,
      ty_trm G t T ->
      exp G T Ds ->
      decs_has Ds l D ->
      (forall z, (open_dec z D) = D) ->
      trm_has G t l D
with ty_trm : ctx -> trm -> typ -> Prop :=
  | ty_var : forall G x T,
      binds x T G ->
      ty_trm G (trm_var (avar_f x)) T
  | ty_sel : forall G e l T,
      trm_has G e (label_fld l) (dec_fld T) ->
      ty_trm G (trm_sel e l) T
  | ty_call : forall G t m U V u,
      trm_has G t (label_mtd m) (dec_mtd U V) ->
      ty_trm G u U ->
      ty_trm G (trm_call t m u) V
  | ty_new : forall L G T ds Ds,
      exp G T Ds ->
      (forall x, x \notin L ->
                 ty_defs (G & x ~ T) (open_defs x ds) (open_decs x Ds) /\
                 forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) -> 
                               subtyp notrans (G & x ~ T) S U) ->
      ty_trm G (trm_new T ds) T
  | ty_sbsm : forall G t T U,
      ty_trm G t T ->
      subtyp notrans G T U ->
      ty_trm G t U
with ty_def : ctx -> def -> dec -> Prop :=
  | ty_typ : forall G S T,
      ty_def G def_typ (dec_typ S T)
  | ty_fld : forall G v T,
      ty_trm G (trm_var v) T ->
      ty_def G (def_fld v) (dec_fld T)
  | ty_mtd : forall L G S T t,
      (forall x, x \notin L -> ty_trm (G & x ~ S) (open_trm x t) T) ->
      ty_def G (def_mtd t) (dec_mtd S T)
with ty_defs : ctx -> defs -> decs -> Prop :=
  | ty_dsnil : forall G,
      ty_defs G defs_nil decs_nil
  | ty_dscons : forall G ds d Ds D n,
      ty_defs G ds Ds ->
      ty_def  G d D ->
      ty_defs G (defs_cons n d ds) (decs_cons n D Ds).

End Typing.


(* ###################################################################### *)
(** ** Statements we want to prove *)

Module Type Claims(DecsImpl: Decs).
Import DecsImpl.
Module TypingImpl := Typing(DecsImpl).
Import TypingImpl.

(* Additional invariant which is preserved during reduction of well-typed
   terms. Can be chosen by the proofs, as long as it holds for the empty store/ctx. *)
Parameter wf_sto: sto -> ctx -> Prop.

Axiom empty_wf_sto: wf_sto empty empty.

Axiom progress: forall s G e T,
  wf_sto s G ->
  ty_trm G e T -> 
  (
    (* can step *)
    (exists e' s', red e s e' s') \/
    (* or is a value *)
    (exists x o, e = (trm_var (avar_f x)) /\ binds x o s)
  ).

Axiom preservation: forall s G e T e' s',
  wf_sto s G -> ty_trm G e T -> red e s e' s' ->
  (exists G', wf_sto s' G' /\ ty_trm G' e' T).

End Claims.


(* ###################################################################### *)
(* ###################################################################### *)
(** * Infrastructure *)

(* ###################################################################### *)
(** ** Helper lemmas for definition/declaration lists *)

Lemma defs_has_fld_sync: forall n d ds,
  defs_has ds (label_fld n) d -> exists x, d = (def_fld x).
Proof.
  introv Hhas. induction ds; unfolds defs_has, get_def. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_def in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma defs_has_mtd_sync: forall n d ds,
  defs_has ds (label_mtd n) d -> exists e, d = (def_mtd e).
Proof.
  introv Hhas. induction ds; unfolds defs_has, get_def. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_def in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma decs_has_fld_sync: forall n d ds,
  decs_has ds (label_fld n) d -> exists x, d = (dec_fld x).
Proof.
  introv Hhas. induction ds; unfolds decs_has, get_dec. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_dec in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma decs_has_mtd_sync: forall n d ds,
  decs_has ds (label_mtd n) d -> exists T U, d = (dec_mtd T U).
Proof.
  introv Hhas. induction ds; unfolds decs_has, get_dec. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_dec in H. destruct* d; discriminate.
    - apply* IHds.
Qed.


(* ###################################################################### *)
(** ** Implementation of declaration intersection *)

(* We give any implementation of `intersect`, and prove that it satisfies
   the specification. *)
Module DecsImpl : Decs.

Fixpoint refine_dec(n1: nat)(D1: dec)(Ds2: decs): dec := match Ds2 with
| decs_nil => D1
| decs_cons n2 D2 tail2 => match D1, D2 with
    | dec_typ T1 S1, dec_typ T2 S2 => If n1 = n2
                                      then dec_typ (typ_or T1 T2) (typ_and S1 S2) 
                                      else refine_dec n1 D1 tail2
    | dec_fld T1   , dec_fld T2    => If n1 = n2
                                      then dec_fld (typ_and T1 T2) 
                                      else refine_dec n1 D1 tail2
    | dec_mtd T1 S1, dec_mtd T2 S2 => If n1 = n2
                                      then dec_mtd (typ_or T1 T2) (typ_and S1 S2) 
                                      else refine_dec n1 D1 tail2
    | _, _ => refine_dec n1 D1 tail2
    end
end.

Lemma refine_dec_spec_typ: forall Ds2 n T1 S1 T2 S2,
  decs_has Ds2 (label_typ n) (dec_typ T2 S2) ->
  refine_dec n (dec_typ T1 S1) Ds2 = dec_typ (typ_or T1 T2) (typ_and S1 S2).
Proof. 
  intro Ds2. induction Ds2; intros.
  + inversion H.
  + unfold decs_has, get_dec in H. case_if; fold get_dec in H.
    - inversions H. unfold label_for_dec in H0. inversions H0. simpl. case_if. reflexivity.
    - simpl. destruct d.
      * simpl in H0. case_if.
        apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
Qed.

Lemma refine_dec_spec_fld: forall Ds2 n T1 T2,
  decs_has Ds2 (label_fld n) (dec_fld T2) ->
  refine_dec n (dec_fld T1) Ds2 = dec_fld (typ_and T1 T2).
Proof.
  intro Ds2. induction Ds2; intros.
  + inversion H.
  + unfold decs_has, get_dec in H. case_if; fold get_dec in H.
    - inversions H. unfold label_for_dec in H0. inversions H0. simpl. case_if. reflexivity.
    - simpl. destruct d.
      * apply IHDs2. unfold decs_has. assumption.
      * simpl in H0. case_if.
        apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
Qed.

Lemma refine_dec_spec_mtd: forall Ds2 n T1 S1 T2 S2,
  decs_has Ds2 (label_mtd n) (dec_mtd T2 S2) ->
  refine_dec n (dec_mtd T1 S1) Ds2 = dec_mtd (typ_or T1 T2) (typ_and S1 S2).
Proof. 
  intro Ds2. induction Ds2; intros.
  + inversion H.
  + unfold decs_has, get_dec in H. case_if; fold get_dec in H.
    - inversions H. unfold label_for_dec in H0. inversions H0. simpl. case_if. reflexivity.
    - simpl. destruct d.
      * apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
      * simpl in H0. case_if.
        apply IHDs2. unfold decs_has. assumption.
Qed.

Lemma refine_dec_spec_unbound: forall n D1 Ds2, 
  decs_hasnt Ds2 (label_for_dec n D1) ->
  refine_dec n D1 Ds2 = D1.
Proof. 
  intros. induction Ds2.
  + reflexivity.
  + unfold decs_hasnt, get_dec in H. fold get_dec in H. case_if. destruct D1.
    - destruct d; simpl in H0; unfold refine_dec.
      * case_if. fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
    - destruct d; simpl in H0; unfold refine_dec.
      * fold refine_dec. apply IHDs2. assumption.
      * case_if. fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
    - destruct d; simpl in H0; unfold refine_dec.
      * fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
      * case_if. fold refine_dec. apply IHDs2. assumption.
Qed.

Lemma refine_dec_preserves_label: forall n D1 Ds2,
  label_for_dec n (refine_dec n D1 Ds2) = label_for_dec n D1.
Proof.
  intros. induction Ds2.
  + reflexivity.
  + destruct D1; destruct d; unfold refine_dec in *; fold refine_dec in *; 
    solve [ assumption | case_if* ].
Qed.

Fixpoint refine_decs(Ds1: decs)(Ds2: decs): decs := match Ds1 with
| decs_nil => decs_nil
| decs_cons n D1 Ds1tail => decs_cons n (refine_dec n D1 Ds2) (refine_decs Ds1tail Ds2)
end.

Lemma refine_decs_spec_unbound: forall l D Ds1 Ds2,
  decs_has    Ds1                  l D ->
  decs_hasnt  Ds2                  l   ->
  decs_has   (refine_decs Ds1 Ds2) l D .
Proof.
  intros l D Ds1 Ds2. induction Ds1; introv Has Hasnt.
  + inversion Has.
  + unfold refine_decs; fold refine_decs. rename d into D'. unfold decs_has, get_dec.
    rewrite refine_dec_preserves_label. case_if.
    - unfold decs_has, get_dec in Has. case_if.
      inversions Has. f_equal. apply refine_dec_spec_unbound. assumption.
    - fold get_dec. unfold decs_has in *. unfold get_dec in Has. case_if.
      fold get_dec in Has. apply* IHDs1. 
Qed.

Lemma refine_decs_spec_unbound_preserved: forall l Ds1 Ds2,
  decs_hasnt Ds1                   l ->
  decs_hasnt (refine_decs Ds1 Ds2) l .
Proof. 
  introv Hasnt. induction Ds1.
  + simpl. assumption.
  + unfold refine_decs; fold refine_decs. rename d into D'. unfold decs_hasnt, get_dec.
    rewrite refine_dec_preserves_label. case_if.
    - unfold decs_hasnt, get_dec in Hasnt. case_if. (* contradiction *)
    - fold get_dec. unfold decs_has in *. apply IHDs1.
      unfold decs_hasnt, get_dec in Hasnt. case_if. fold get_dec in Hasnt. apply Hasnt.
Qed.

Lemma refine_decs_spec_typ: forall n Ds1 Ds2 T1 S1 T2 S2,
  decs_has  Ds1                  (label_typ n) (dec_typ T1 S1) ->
  decs_has  Ds2                  (label_typ n) (dec_typ T2 S2) ->
  decs_has (refine_decs Ds1 Ds2) (label_typ n) (dec_typ (typ_or T1 T2) (typ_and S1 S2)).
Proof.
  introv Has1 Has2. induction Ds1.
  + inversion Has1.
  + unfold decs_has, get_dec in Has1. case_if.
    - inversions Has1. simpl in H. inversions H. simpl. 
      rewrite (refine_dec_spec_typ _ _ Has2). unfold decs_has, get_dec. simpl.
      case_if. reflexivity.
    - fold get_dec in Has1. simpl. unfold decs_has, get_dec.
      rewrite refine_dec_preserves_label. case_if. fold get_dec.
      unfold decs_has in IHDs1. apply IHDs1. assumption.
Qed.

Lemma refine_decs_spec_fld: forall n Ds1 Ds2 T1 T2,
  decs_has  Ds1                  (label_fld n) (dec_fld T1) ->
  decs_has  Ds2                  (label_fld n) (dec_fld T2) ->
  decs_has (refine_decs Ds1 Ds2) (label_fld n) (dec_fld (typ_and T1 T2)).
Proof. 
  introv Has1 Has2. induction Ds1.
  + inversion Has1.
  + unfold decs_has, get_dec in Has1. case_if.
    - inversions Has1. simpl in H. inversions H. simpl. 
      rewrite (refine_dec_spec_fld _ Has2). unfold decs_has, get_dec. simpl.
      case_if. reflexivity.
    - fold get_dec in Has1. simpl. unfold decs_has, get_dec.
      rewrite refine_dec_preserves_label. case_if. fold get_dec.
      unfold decs_has in IHDs1. apply IHDs1. assumption.
Qed.

Lemma refine_decs_spec_mtd: forall n Ds1 Ds2 T1 S1 T2 S2,
  decs_has  Ds1                  (label_mtd n) (dec_mtd T1 S1) ->
  decs_has  Ds2                  (label_mtd n) (dec_mtd T2 S2) ->
  decs_has (refine_decs Ds1 Ds2) (label_mtd n) (dec_mtd (typ_or T1 T2) (typ_and S1 S2)).
Proof.
  introv Has1 Has2. induction Ds1.
  + inversion Has1.
  + unfold decs_has, get_dec in Has1. case_if.
    - inversions Has1. simpl in H. inversions H. simpl. 
      rewrite (refine_dec_spec_mtd _ _ Has2). unfold decs_has, get_dec. simpl.
      case_if. reflexivity.
    - fold get_dec in Has1. simpl. unfold decs_has, get_dec.
      rewrite refine_dec_preserves_label. case_if. fold get_dec.
      unfold decs_has in IHDs1. apply IHDs1. assumption.
Qed.

Fixpoint decs_concat(Ds1 Ds2: decs) {struct Ds1}: decs := match Ds1 with
| decs_nil => Ds2
| decs_cons n D1 Ds1tail => decs_cons n D1 (decs_concat Ds1tail Ds2)
end.

(* Refined decs shadow the outdated decs of Ds2. *)
Definition intersect(Ds1 Ds2: decs): decs := decs_concat (refine_decs Ds1 Ds2) Ds2.

Definition union(Ds1 Ds2: decs): decs. (* TODO *) Admitted.

Lemma decs_has_concat_left : forall l D Ds1 Ds2,
  decs_has Ds1 l D ->
  decs_has (decs_concat Ds1 Ds2) l D.
Proof.
  introv Has. induction Ds1.
  + inversion Has.
  + simpl. unfold decs_has, get_dec in *. fold get_dec in *. case_if.
    - assumption.
    - apply IHDs1. assumption.
Qed. 

Lemma decs_has_concat_right : forall l D Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_has Ds2 l D ->
  decs_has (decs_concat Ds1 Ds2) l D.
Proof.
  introv Hasnt Has. induction Ds1.
  + simpl. assumption.
  + simpl. unfold decs_has, get_dec. case_if.
    - unfold decs_hasnt, get_dec in Hasnt. case_if. (* contradiction *)
    - fold get_dec. apply IHDs1. unfold decs_hasnt, get_dec in Hasnt. case_if.
      apply Hasnt.
Qed.

Lemma decs_hasnt_concat : forall l Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_hasnt Ds2 l ->
  decs_hasnt (decs_concat Ds1 Ds2) l.
Proof.
  introv Hasnt1 Hasnt2. induction Ds1.
  + simpl. assumption.
  + simpl. unfold decs_hasnt, get_dec. case_if.
    - unfold decs_hasnt, get_dec in Hasnt1. case_if. (* contradiction *)
    - fold get_dec. apply IHDs1. unfold decs_hasnt, get_dec in Hasnt1. case_if.
      apply Hasnt1.
Qed.

Lemma intersect_spec_1: forall l D Ds1 Ds2,
  decs_has    Ds1                l D ->
  decs_hasnt  Ds2                l   ->
  decs_has   (intersect Ds1 Ds2) l D .
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_unbound; assumption.
Qed.

Lemma intersect_spec_2: forall l D Ds1 Ds2,
  decs_hasnt Ds1                 l   ->
  decs_has   Ds2                 l D ->
  decs_has   (intersect Ds1 Ds2) l D.
Proof.
  introv Hasnt Has. unfold intersect.
  apply (@decs_has_concat_right l D (refine_decs Ds1 Ds2) Ds2).
  apply (@refine_decs_spec_unbound_preserved l Ds1 Ds2 Hasnt).
  assumption. 
Qed.

Lemma intersect_spec_12_typ: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_typ n) (dec_typ S1 T1) ->
  decs_has Ds2                 (label_typ n) (dec_typ S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_typ n) (dec_typ (typ_or S1 S2) (typ_and T1 T2)).
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_typ; assumption.
Qed.

Lemma intersect_spec_12_fld: forall n T1 T2 Ds1 Ds2,
  decs_has Ds1                 (label_fld n) (dec_fld T1) ->
  decs_has Ds2                 (label_fld n) (dec_fld T2) ->
  decs_has (intersect Ds1 Ds2) (label_fld n) (dec_fld (typ_and T1 T2)).
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_fld; assumption.
Qed.

Lemma intersect_spec_12_mtd: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_mtd n) (dec_mtd S1 T1) ->
  decs_has Ds2                 (label_mtd n) (dec_mtd S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_mtd n) (dec_mtd (typ_or S1 S2) (typ_and T1 T2)).
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_mtd; assumption.
Qed.

Lemma intersect_spec_hasnt: forall l Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_hasnt Ds2 l ->
  decs_hasnt (intersect Ds1 Ds2) l.
Proof.
  introv Hasnt1 Hasnt2. unfold intersect. apply decs_hasnt_concat.
  + apply (refine_decs_spec_unbound_preserved _ Hasnt1).
  + apply Hasnt2.
Qed.

End DecsImpl.


(* ###################################################################### *)
Module Proofs: Claims(DecsImpl).
Import DecsImpl.
Module TypingImpl := Typing(DecsImpl).
Import TypingImpl.


(* ###################################################################### *)
(** ** Induction principles *)

Scheme trm_mut  := Induction for trm  Sort Prop
with   def_mut  := Induction for def  Sort Prop
with   defs_mut := Induction for defs Sort Prop.
Combined Scheme trm_mutind from trm_mut, def_mut, defs_mut.

Scheme typ_mut  := Induction for typ  Sort Prop
with   dec_mut  := Induction for dec  Sort Prop
with   decs_mut := Induction for decs Sort Prop.
Combined Scheme typ_mutind from typ_mut, dec_mut, decs_mut.

Scheme exp_mut     := Induction for exp     Sort Prop
with   var_has_mut := Induction for var_has Sort Prop.
Combined Scheme exp_var_has_mutind from exp_mut, var_has_mut.

Scheme subtyp_mut  := Induction for subtyp  Sort Prop
with   subdec_mut  := Induction for subdec  Sort Prop
with   subdecs_mut := Induction for subdecs Sort Prop.
Combined Scheme subtyp_mutind from subtyp_mut, subdec_mut, subdecs_mut.

Scheme trm_has_mut := Induction for trm_has Sort Prop
with   ty_trm_mut  := Induction for ty_trm  Sort Prop
with   ty_def_mut  := Induction for ty_def  Sort Prop
with   ty_defs_mut := Induction for ty_defs Sort Prop.
Combined Scheme ty_mutind from trm_has_mut, ty_trm_mut, ty_def_mut, ty_defs_mut.


(* ###################################################################### *)
(** ** Tactics *)

Ltac auto_specialize :=
  repeat match goal with
  | Impl: ?Cond ->            _ |- _ => let HC := fresh in 
      assert (HC: Cond) by auto; specialize (Impl HC); clear HC
  | Impl: forall (_ : ?Cond), _ |- _ => match goal with
      | p: Cond |- _ => specialize (Impl p)
      end
  end.

Ltac gather_vars :=
  let A := gather_vars_with (fun x : vars      => x         ) in
  let B := gather_vars_with (fun x : var       => \{ x }    ) in
  let C := gather_vars_with (fun x : ctx       => dom x     ) in
  let D := gather_vars_with (fun x : sto       => dom x     ) in
  let E := gather_vars_with (fun x : avar      => fv_avar  x) in
  let F := gather_vars_with (fun x : trm       => fv_trm   x) in
  let G := gather_vars_with (fun x : def      => fv_def  x) in
  let H := gather_vars_with (fun x : defs     => fv_defs x) in
  let I := gather_vars_with (fun x : def       => fv_def   x) in
  constr:(A \u B \u C \u D \u E \u F \u G \u H \u I).

Ltac pick_fresh x :=
  let L := gather_vars in (pick_fresh_gen L x).

Tactic Notation "apply_fresh" constr(T) "as" ident(x) :=
  apply_fresh_base T gather_vars x.

Hint Constructors subtyp.
Hint Constructors subdec.
(*Hint Constructors notsel.*)


(* ###################################################################### *)

(** *** Well-formed store *)
Inductive wf_store: sto -> ctx -> Prop :=
  | wf_sto_empty : wf_store empty empty
  | wf_sto_push : forall L s G x T ds Ds,
      wf_store s G ->
      x # s ->
      x # G ->
      (* What's below is the same as the ty_new rule, but we don't use ty_trm,
         because it could be subsumption *)
      exp G T Ds ->
      (forall x, x \notin L ->
                 ty_defs (G & x ~ T) (open_defs x ds) (open_decs x Ds) /\
                 forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) -> 
                               subtyp notrans (G & x ~ T) S U) ->
      wf_store (s & x ~ (object T ds)) (G & x ~ T).

Definition wf_sto(s: sto)(G: ctx): Prop := wf_store s G.

(*
ty_trm_new does not check for good bounds recursively inside the types, but that's
not a problem because when creating an object x which has (L: S..U), we have two cases:
Case 1: The object x has a field x.f = y of type x.L: Then y has a type
        Y <: x.L, and when checking the creation of y, we checked that
        the type members of Y are good, so the those of S and U are good as well,
        because S and U are supertypes of Y.
Case 2: The object x has no field of type x.L: Then we can only refer to the
        type x.L, but not to possibly bad type members of the type x.L.
*)

Lemma empty_wf_sto: wf_sto empty empty.
Proof. apply wf_sto_empty. Qed.


(* ###################################################################### *)
(** ** Realizability *)

(** dreal = "definitely realizable" (an approximation of realizability) *)

(* typ_bot, typ_rfn of non-top, and typ_and are not definitely realizable *)
Inductive dreal_typ : ctx -> typ -> Prop :=
  | dreal_top: forall G,
      dreal_typ G typ_top
  | dreal_rfn: forall L G Ds,
      (* be careful, we're putting a possibly non-dreal type into the env! *)
      (forall z, z \notin L -> 
                 dreal_decs (G & z ~ (typ_rfn typ_top Ds)) (open_decs z Ds)) ->
      dreal_typ G (typ_rfn typ_top Ds)
  | dreal_sel : forall G v L S U,
      var_has G v L (dec_typ S U) ->
      dreal_dec G (dec_typ S U) ->
      dreal_typ G (typ_sel (pth_var (avar_f v)) L)
  | dreal_or_l : forall G T1 T2,
      dreal_typ G T1 ->
      dreal_typ G (typ_or T1 T2)
  | dreal_or_r : forall G T1 T2,
      dreal_typ G T2 ->
      dreal_typ G (typ_or T1 T2)
with dreal_dec : ctx -> dec -> Prop :=
  | dreal_tm : forall G S U,
      subtyp oktrans G S U ->
      dreal_typ G U ->
      dreal_dec G (dec_typ S U)
  | dreal_fld : forall G T,
      dreal_typ G T ->
      dreal_dec G (dec_fld T)
  | dreal_mtd : forall G S U,
      dreal_dec G (dec_mtd S U)
with dreal_decs : ctx -> decs -> Prop :=
  | dreal_nil : forall G,
      dreal_decs G decs_nil
  | dreal_cons : forall G n D Ds,
      dreal_decs G Ds ->
      dreal_dec G D ->
      dreal_decs G (decs_cons n D Ds).

Inductive dreal_ctx : ctx -> Prop :=
  | dreal_empty:
      dreal_ctx empty
  | dreal_push: forall G x T,
      dreal_ctx G ->
      dreal_typ G T ->
      dreal_ctx (G & x ~ T).

Inductive subctx0 : ctx -> ctx -> Prop :=
  | subctx0_empty:
      subctx0 empty empty
  | subctx0_push: forall G1 G2 x T1 T2,
      subctx0 G1 G2 ->
      (* nominal subtyping *)
      subtyp oktrans G1 T1 T2 ->
      subctx0 (G1 & x ~ T1) (G2 & x ~ T2).

(* a more precise definition of realizability: G can contain intersection types,
   provided they have a dreal subtype *)
Definition real_ctx0(G: ctx): Prop := exists G', subctx0 G' G /\ dreal_ctx G'.

Lemma wf_sto_real0: forall s G,
  wf_sto s G -> real_ctx0 G.
Proof.
  introv Wf. induction Wf; unfold real_ctx0 in *.
  + exists (@empty typ). split. apply subctx0_empty. apply dreal_empty.
  + destruct IHWf as [G' [Sc Drc]].
    (* cannot choose T instead of (typ_rfn typ_top Ds), because T might not be dreal *)
    exists (G' & x ~ (typ_rfn typ_top Ds)). split.
    - apply subctx0_push.
      * apply Sc.
      * (* Only holds structurally. Nominally, it's the other way round! *)
Abort.

Inductive subctx1 : ctx -> ctx -> Prop :=
  | subctx1_empty:
      subctx1 empty empty
  | subctx1_push: forall L G1 G2 x T1 T2 Ds1 Ds2,
      subctx1 G1 G2 ->
      (* structural subtyping: *)
      exp G1 T1 Ds1 ->
      exp G2 T2 Ds2 -> (* G1 or G2 here? *)
      (forall y, y \notin L -> subdecs oktrans (G1 & y ~ (typ_rfn typ_top Ds1)) 
                                               (open_decs y Ds1)
                                               (open_decs y Ds2)) ->
      subctx1 (G1 & x ~ T1) (G2 & x ~ T2).

(* a more precise definition of realizability: G can contain intersection types,
   provided they have a dreal subtype *)
Definition real_ctx1(G: ctx): Prop := exists G', subctx1 G' G /\ dreal_ctx G'.

Lemma wf_sto_real1: forall s G,
  wf_sto s G -> real_ctx1 G.
Proof.
  introv Wf. induction Wf; unfold real_ctx1 in *.
  + exists (@empty typ). split. apply subctx1_empty. apply dreal_empty.
  + destruct IHWf as [G' [Sc Drc]].
    (* cannot choose T instead of (typ_rfn typ_top Ds), because T might not be dreal *)
    exists (G' & x ~ (typ_rfn typ_top Ds)). split.
    - apply subctx1_push with L (intersect decs_nil Ds) Ds.
      * apply Sc.
      * apply exp_rfn. apply exp_top.
      * apply H1.
      * intros y Fry. admit. (* TODO, but basically just reflexivity *)
    - apply (dreal_push _ Drc).
      apply dreal_rfn with L. intros z zL. specialize (H2 z zL).
      (* We have [exp G T Ds], so [T <: (typ_rfn typ_top Ds)].
         Use this to weaken in the goal.
         Then use [subctx G' G] to weaken in H2. <-- only works if subctx is nominal!!!
         Then H2 says that for all fields we have a variable the well-formed store
         s, and that all type members have good bounds
      *)
Abort.

(* alternative definition of realizable context which does not need subctx judgment,
   because it's baked into real_push *)
Inductive real_ctx2 : ctx -> Prop :=
  | real_empty:
      real_ctx2 empty
  | real_push: forall G x R T,
      real_ctx2 G ->
      dreal_typ G R ->
      subtyp oktrans G R T ->
      real_ctx2 (G & x ~ T).

Lemma wf_sto_real2: forall s G,
  wf_sto s G -> real_ctx2 G.
Proof.
  introv Wf. induction Wf.
  + apply real_empty.
  + apply real_push with (typ_rfn typ_top Ds).
    - apply IHWf.
    - admit. (* should follow from H2...*)
    - (* Only holds structurally. Nominally, it's the other way round! *)
Abort.


(* ###################################################################### *)
(** ** Definition of var-by-var substitution *)

(** Note that substitution is not part of the definitions, because for the
    definitions, opening is sufficient. For the proofs, however, we also
    need substitution, but only var-by-var substitution, not var-by-term
    substitution. That's why we don't need a judgment asserting that a term
    is locally closed. *)

Fixpoint subst_avar (z: var) (u: var) (a: avar) { struct a } : avar :=
  match a with
  | avar_b i => avar_b i
  | avar_f x => If x = z then (avar_f u) else (avar_f x)
  end.

Definition subst_pth (z: var) (u: var) (p: pth) : pth :=
  match p with
  | pth_var a => pth_var (subst_avar z u a)
  end.

Fixpoint subst_typ (z: var) (u: var) (T: typ) { struct T } : typ :=
  match T with
  | typ_top     => typ_top
  | typ_bot     => typ_bot
  | typ_bind Ds => typ_bind (subst_decs z u Ds)
  | typ_sel p L => typ_sel (subst_pth z u p) L
  end
with subst_dec (z: var) (u: var) (D: dec) { struct D } : dec :=
  match D with
  | dec_typ T U => dec_typ (subst_typ z u T) (subst_typ z u U)
  | dec_fld T   => dec_fld (subst_typ z u T)
  | dec_mtd T U => dec_mtd (subst_typ z u T) (subst_typ z u U)
  end
with subst_decs (z: var) (u: var) (Ds: decs) { struct Ds } : decs :=
  match Ds with
  | decs_nil          => decs_nil
  | decs_cons n D Ds' => decs_cons n (subst_dec z u D) (subst_decs z u Ds')
  end.

Fixpoint subst_trm (z: var) (u: var) (t: trm) : trm :=
  match t with
  | trm_var x => trm_var (subst_avar z u x)
  | trm_new Ds ds => trm_new (subst_decs z u Ds) (subst_defs z u ds)
  | trm_sel t l => trm_sel (subst_trm z u t) l
  | trm_call t1 m t2 => trm_call (subst_trm z u t1) m (subst_trm z u t2)
  end
with subst_def (z: var) (u: var) (d: def) : def :=
  match d with
  | def_typ => def_typ
  | def_fld x => def_fld (subst_avar z u x)
  | def_mtd b => def_mtd (subst_trm z u b)
  end
with subst_defs (z: var) (u: var) (ds: defs) : defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons n d rest => defs_cons n (subst_def z u d) (subst_defs z u rest)
  end.


(* ###################################################################### *)
(** ** Lemmas for var-by-var substitution *)

Lemma subst_fresh_avar: forall x y,
  (forall a: avar, x \notin fv_avar a -> subst_avar x y a = a).
Proof.
  intros. destruct* a. simpl. case_var*. simpls. notin_false.
Qed.

Lemma subst_fresh_pth: forall x y,
  (forall p: pth, x \notin fv_pth p -> subst_pth x y p = p).
Proof.
  intros. destruct p. simpl. f_equal. apply* subst_fresh_avar.
Qed.

Lemma subst_fresh_typ_dec_decs: forall x y,
  (forall T : typ , x \notin fv_typ  T  -> subst_typ  x y T  = T ) /\
  (forall d : dec , x \notin fv_dec  d  -> subst_dec  x y d  = d ) /\
  (forall ds: decs, x \notin fv_decs ds -> subst_decs x y ds = ds).
Proof.
  intros x y. apply typ_mutind; intros; simpls; f_equal*. apply* subst_fresh_pth.
Qed.

Lemma subst_fresh_trm_def_defs: forall x y,
  (forall t : trm , x \notin fv_trm  t  -> subst_trm  x y t  = t ) /\
  (forall d : def , x \notin fv_def  d  -> subst_def  x y d  = d ) /\
  (forall ds: defs, x \notin fv_defs ds -> subst_defs x y ds = ds).
Proof.
  intros x y. apply trm_mutind; intros; simpls; f_equal*.
  + apply* subst_fresh_avar.
  + apply* subst_fresh_typ_dec_decs.
  + apply* subst_fresh_avar.
Qed.

Definition subst_fvar(x y z: var): var := If x = z then y else z.

Lemma subst_open_commute_avar: forall x y u,
  (forall a: avar, forall n: nat,
    subst_avar x y (open_rec_avar n u a) 
    = open_rec_avar n (subst_fvar x y u) (subst_avar  x y a)).
Proof.
  intros. unfold subst_fvar, subst_avar, open_avar, open_rec_avar. destruct a.
  + repeat case_if; auto.
  + case_var*.
Qed.

Lemma subst_open_commute_pth: forall x y u,
  (forall p: pth, forall n: nat,
    subst_pth x y (open_rec_pth n u p) 
    = open_rec_pth n (subst_fvar x y u) (subst_pth x y p)).
Proof.
  intros. unfold subst_pth, open_pth, open_rec_pth. destruct p.
  f_equal. apply subst_open_commute_avar.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_typ_dec_decs: forall x y u,
  (forall t : typ, forall n: nat,
     subst_typ x y (open_rec_typ n u t)
     = open_rec_typ n (subst_fvar x y u) (subst_typ x y t)) /\
  (forall d : dec , forall n: nat, 
     subst_dec x y (open_rec_dec n u d)
     = open_rec_dec n (subst_fvar x y u) (subst_dec x y d)) /\
  (forall ds: decs, forall n: nat, 
     subst_decs x y (open_rec_decs n u ds)
     = open_rec_decs n (subst_fvar x y u) (subst_decs x y ds)).
Proof.
  intros. apply typ_mutind; intros; simpl; f_equal*. apply subst_open_commute_pth.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_trm_def_defs: forall x y u,
  (forall t : trm, forall n: nat,
     subst_trm x y (open_rec_trm n u t)
     = open_rec_trm n (subst_fvar x y u) (subst_trm x y t)) /\
  (forall d : def , forall n: nat, 
     subst_def x y (open_rec_def n u d)
     = open_rec_def n (subst_fvar x y u) (subst_def x y d)) /\
  (forall ds: defs, forall n: nat, 
     subst_defs x y (open_rec_defs n u ds)
     = open_rec_defs n (subst_fvar x y u) (subst_defs x y ds)).
Proof.
  intros. apply trm_mutind; intros; simpl; f_equal*.
  + apply* subst_open_commute_avar.
  + apply* subst_open_commute_typ_dec_decs.
  + apply* subst_open_commute_avar.
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


(* ###################################################################### *)
(** ** Inversion lemmas *)

(** *** Inversion lemmas for [wf_sto] *)

Lemma wf_sto_to_ok_s: forall s G,
  wf_sto s G -> ok s.
Proof. intros. induction H; jauto. Qed.

Lemma wf_sto_to_ok_G: forall s G,
  wf_sto s G -> ok G.
Proof. intros. induction H; jauto. Qed.

Hint Resolve wf_sto_to_ok_s wf_sto_to_ok_G.

Lemma ctx_binds_to_sto_binds: forall s G x T,
  wf_sto s G ->
  binds x T G ->
  exists ds, binds x ds s.
Proof.
  introv Wf Bi. gen x T Bi. induction Wf; intros.
  + false* binds_empty_inv.
  + unfolds binds. rewrite get_push in *. case_if.
    - eauto.
    - eauto.
Qed.

Lemma fresh_push_eq_inv: forall A x a (E: env A),
  x # (E & x ~ a) -> False.
Proof.
  intros. rewrite dom_push in H. false H. rewrite in_union.
  left. rewrite in_singleton. reflexivity.
Qed.

Lemma sto_unbound_to_ctx_unbound: forall s G x,
  wf_sto s G ->
  x # s ->
  x # G.
Proof.
  introv Wf Ub_s.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub_s). 
    - auto.
Qed.

Lemma ctx_unbound_to_sto_unbound: forall s G x,
  wf_sto s G ->
  x # G ->
  x # s.
Proof.
  introv Wf Ub.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub). 
    - auto.
Qed.

Lemma invert_wf_sto: forall s G,
  wf_sto s G -> 
    forall x ds Ds, 
      binds x (object Ds ds) s -> 
      binds x (typ_bind Ds) G ->
      exists G1 G2, G = G1 & x ~ (typ_bind Ds) & G2 /\ 
                    ty_defs (G1 & x ~ (typ_bind Ds)) (open_defs x ds) (open_decs x Ds).
Proof.
  intros s G Wf. induction Wf; intros.
  + false* binds_empty_inv.
  + unfold binds in *. rewrite get_push in *.
    case_if.
    - inversions H2. inversions H3. exists G (@empty typ). rewrite concat_empty_r. auto.
    - specialize (IHWf x0 ds0 Ds0 H2 H3).
      destruct IHWf as [G1 [G2 [Eq Ty]]]. rewrite Eq.
      exists G1 (G2 & x ~ typ_bind Ds).
      rewrite concat_assoc. auto.
Qed.

(** *** Inverting [var_has] *)

(*
Lemma invert_var_has: forall G x l D,
  var_has G x l D ->
  exists T Ds D', binds x T G /\
                  exp G T Ds /\
                  decs_has Ds l D' /\
                  open_dec x D' = D.
Proof.
  intros. inversions H. exists T Ds D0. auto.
Qed.
*)
Lemma invert_var_has: forall G x l D,
  var_has G x l D ->
  exists T Ds, binds x T G /\
               exp G T Ds /\
               decs_has (open_decs x Ds) l D.
Proof.
  intros. inversion H. eauto.
Qed.

(*** Inverting [subdec] *)

Lemma subdec_to_label_for_eq: forall m G D1 D2 n,
  subdec m G D1 D2 ->
  (label_for_dec n D1) = (label_for_dec n D2).
Proof.
  introv Sd. inversions Sd; unfold label_for_dec; reflexivity.
Qed.

(** *** Inverting [subdecs] *)

Lemma invert_subdecs_push: forall m G Ds1 Ds2 n D2,
  subdecs m G Ds1 (decs_cons n D2 Ds2) -> 
    exists D1, decs_has Ds1 (label_for_dec n D2) D1
            /\ subdec m G D1 D2
            /\ subdecs m G Ds1 Ds2.
Proof.
  intros. inversions H. eauto.
Qed.

(** *** Inverting [trm_has] *)

Lemma invert_trm_has: forall G t l D,
  trm_has G t l D ->
  exists T Ds, ty_trm G t T /\ 
               exp G T Ds /\ 
               decs_has Ds l D /\
               (forall z : var, open_dec z D = D).
Proof.
  intros. inversions H. exists T Ds. auto.
Qed.

(** *** Inverting [ty_trm] *)

Lemma invert_ty_var: forall G x T,
  ty_trm G (trm_var (avar_f x)) T ->
  binds x T G.
Proof.
  intros. inversions H. 
  + assumption.
  + admit. (* subsumption case *)
Qed.

Lemma invert_ty_sel: forall G e l T,
  ty_trm G (trm_sel e l) T ->
  trm_has G e (label_fld l) (dec_fld T).
Proof.
  intros. inversions H. 
  + assumption.
  + admit. (* subsumption case *)
Qed.

Lemma invert_ty_call: forall G t m V u,
  ty_trm G (trm_call t m u) V ->
  exists U, trm_has G t (label_mtd m) (dec_mtd U V) /\ ty_trm G u U.
Proof.
  intros. inversions H.
  + eauto.
  + admit. (* subsumption case *)
Qed.


Lemma invert_ty_new: forall G T ds,
  ty_trm G (trm_new T ds) T ->
  exists L Ds,
    exp G T Ds /\
    forall x, x \notin L ->
      ty_defs (G & x ~ T) (open_defs x ds) (open_decs x Ds) /\
      (forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) ->
                     subtyp notrans (G & x ~ T) S U).
Proof.
  introv Ty. inversions Ty.
  + (* no subsumption *)
    exists L Ds. auto.
  + (* subsumption (which kept type because (trm_new **T** ds) T *)


Lemma invert_ty_new: forall G T ds,
  ty_trm G (trm_new T ds) T ->
  exists L Ds T',
    subtyp oktrans G T' T /\
    exp G T' Ds /\
    forall x, x \notin L ->
      ty_defs (G & x ~ T') (open_defs x ds) (open_decs x Ds) /\
      (forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) ->
                     subtyp notrans (G & x ~ T') S U).
Proof.
  intros. gen_eq T0: T. gen_eq tn: (trm_new T0 ds). gen T ds.
  induction H; intros T0 ds0 Eqtn EqT; try discriminate.
  + (* base case: no subsumption *)
    subst T0. inversions Eqtn.
    exists L Ds T. split.
    - apply subtyp_mode. apply subtyp_refl.
    - auto.
  + (* step: subsumption *)
    rename IHty_trm into IH.
    subst T0. subst t. specialize (IH T ds0). 
Abort.

(*
Lemma invert_ty_new: forall G Ds ds T,
  ty_trm G (trm_new Ds ds) T ->
  exists L Ds, T = typ_bind Ds /\
               (forall x, x \notin L -> 
                          ty_defs (G & x ~ typ_bind Ds) (open_defs x ds) Ds).
Proof.
  intros. inversions H.
  + exists L Ds. auto.
  + admit. (* subsumption case *)
Qed.
*)

(** *** Inverting [ty_def] *)

Lemma ty_def_to_label_for_eq: forall G d D n, 
  ty_def G d D ->
  label_for_def n d = label_for_dec n D.
Proof.
  intros. inversions H; reflexivity.
Qed.

(** *** Inverting [ty_defs] *)

Lemma extract_ty_def_from_ty_defs: forall G l d ds D Ds,
  ty_defs G ds Ds ->
  defs_has ds l d ->
  decs_has Ds l D ->
  ty_def G d D.
Proof.
  introv HdsDs. induction HdsDs.
  + intros. inversion H.
  + introv dsHas DsHas. unfolds defs_has, decs_has, get_def, get_dec. 
    rewrite (ty_def_to_label_for_eq n H) in dsHas. case_if.
    - inversions dsHas. inversions DsHas. assumption.
    - apply* IHHdsDs.
Qed.

Lemma invert_ty_mtd_inside_ty_defs: forall G ds Ds m S T body,
  ty_defs G ds Ds ->
  defs_has ds (label_mtd m) (def_mtd body) ->
  decs_has Ds (label_mtd m) (dec_mtd S T) ->
  (* conclusion is the premise needed to construct a ty_mtd: *)
  exists L, forall x, x \notin L -> ty_trm (G & x ~ S) (open_trm x body) T.
Proof.
  introv HdsDs dsHas DsHas.
  lets H: (extract_ty_def_from_ty_defs HdsDs dsHas DsHas).
  inversions* H. 
Qed.

Lemma invert_ty_fld_inside_ty_defs: forall G ds Ds l v T,
  ty_defs G ds Ds ->
  defs_has ds (label_fld l) (def_fld v) ->
  decs_has Ds (label_fld l) (dec_fld T) ->
  (* conclusion is the premise needed to construct a ty_fld: *)
  ty_trm G (trm_var v) T.
Proof.
  introv HdsDs dsHas DsHas.
  lets H: (extract_ty_def_from_ty_defs HdsDs dsHas DsHas).
  inversions* H. 
Qed.

Lemma get_def_cons : forall l n d ds,
  get_def l (defs_cons n d ds) = If l = (label_for_def n d) then Some d else get_def l ds.
Proof.
  intros. unfold get_def. case_if~.
Qed.

Lemma get_dec_cons : forall l n D Ds,
  get_dec l (decs_cons n D Ds) = If l = (label_for_dec n D) then Some D else get_dec l Ds.
Proof.
  intros. unfold get_dec. case_if~.
Qed.

Lemma decs_has_to_defs_has: forall G l ds Ds D,
  ty_defs G ds Ds ->
  decs_has Ds l D ->
  exists d, defs_has ds l d.
Proof.
  introv Ty Bi. induction Ty; unfolds decs_has, get_dec. 
  + discriminate.
  + unfold defs_has. folds get_dec. rewrite get_def_cons. case_if.
    - exists d. reflexivity.
    - rewrite <- (ty_def_to_label_for_eq n H) in Bi. case_if. apply (IHTy Bi).
Qed.


(* ###################################################################### *)
(** ** Uniqueness *)

Lemma exp_var_has_unique:
  (forall G T Ds1 , exp G T Ds1      -> forall Ds2, exp G T Ds2      -> Ds1 = Ds2) /\ 
  (forall G v l D1, var_has G v l D1 -> forall D2 , var_has G v l D2 -> D1  = D2 ).
Proof.
  apply exp_var_has_mutind; intros.
  + inversions H. reflexivity.
  + inversions H. reflexivity.
  + inversions H1. specialize (H _ H5). inversions H. apply* H0.
  + inversions H0. unfold decs_has in *.
    lets Eq: (binds_func b H1). subst.
    specialize (H _ H2). subst.
    rewrite d in H3. 
    inversion H3. reflexivity.
Qed.

(* That would be so nice...
Lemma exp_unique: forall G T z Ds1 Ds2,
  exp G T z Ds1 -> exp G T z Ds2 -> Ds1 = Ds2
with var_has_unique: forall G v X D1 D2, 
  var_has G v X D1 -> var_has G v X D2 -> D1 = D2.
Proof.
  + introv H1 H2.
    inversions H1; inversions H2.
    - reflexivity.
    - reflexivity.
    - lets Eq: (var_has_unique _ _ _ _ _ H H5). inversions Eq.
      apply* exp_unique.
  + introv H1 H2.
    apply invert_var_has in H1. destruct H1 as [T1 [Ds1 [Bi1 [Exp1 Has1]]]].
    apply invert_var_has in H2. destruct H2 as [T2 [Ds2 [Bi2 [Exp2 Has2]]]].
    unfold decs_has in *.
    lets Eq: (binds_func Bi1 Bi2). subst.
    lets Eq: (exp_unique _ _ _ _ _ Exp1 Exp2). subst.
    rewrite Has2 in Has1. 
    inversion Has1. reflexivity.
Qed. (* Error: Cannot guess decreasing argument of fix. *)
*)

(* ###################################################################### *)
(** ** Transitivity *)

Inductive notsel: typ -> Prop :=
  | notsel_top  : notsel typ_top
  | notsel_bot  : notsel typ_bot
  | notsel_bind : forall ds, notsel (typ_bind ds).

(*
(* "reflexive subdec", just subdec+reflexivity *)
Definition rsubdec(G: ctx)(D1 D2: dec): Prop :=
  D1 = D2 \/ subdec oktrans G D1 D2.
Definition rsubdecs(G: ctx)(Ds1 Ds2: decs): Prop :=
  Ds1 = Ds2 \/ subdecs oktrans G Ds1 Ds2.
*)

Hint Constructors exp var_has.
Hint Constructors subtyp subdec subdecs.

Lemma subdecs_add_left_new: forall m n G Ds2 D1 Ds1,
  decs_hasnt Ds2 (label_for_dec n D1) ->
  subdecs m G Ds1 Ds2 ->
  subdecs m G (decs_cons n D1 Ds1) Ds2.
Proof.
  introv Hasnt. induction Ds2; intro Sds.
  + apply subdecs_empty.
  + rename d into D2. inversions Sds.
    unfold decs_hasnt, get_dec in Hasnt. case_if. fold get_dec in Hasnt.
    apply subdecs_push with D0.
    - unfold decs_has, get_dec. case_if. fold get_dec. apply H5.
    - assumption. 
    - apply IHDs2; assumption.
Qed.

Lemma subdecs_add_left_dupl: forall m n G Ds2 D1 Ds1,
  decs_has Ds1 (label_for_dec n D1) D1 ->
  subdecs m G Ds1 Ds2 ->
  subdecs m G (decs_cons n D1 Ds1) Ds2.
Proof.
Admitted.

(* that's subdecs_push+subdec_refl:
Lemma subdecs_add_right_eq: forall m n G 
  decs_has Ds1 (label_for_dec n D) D ->
  subdecs m G Ds1 Ds2 ->
  subdecs m G Ds1 (decs_cons n D Ds2).
*)

Lemma subdecs_remove_left: forall m n G Ds2 D1 Ds1,
  decs_hasnt Ds2 (label_for_dec n D1) ->
  subdecs m G (decs_cons n D1 Ds1) Ds2 ->
  subdecs m G Ds1 Ds2.
Proof.
  introv Hasnt. induction Ds2; intro Sds.
  + apply subdecs_empty.
  + rename d into D2. inversions Sds.
    unfold decs_hasnt, get_dec in Hasnt. case_if. fold get_dec in Hasnt.
    apply subdecs_push with D0.
    - unfold decs_has, get_dec in H5. case_if. fold get_dec in H5. apply H5.
    - assumption.
    - apply IHDs2; assumption.
Qed.

Lemma subdecs_remove_right: forall m n G Ds2 D2 Ds1,
  (* need Ds2 hasn't n, because it might shadow something conflicting *)
  decs_hasnt Ds2 (label_for_dec n D2) ->
  subdecs m G Ds1 (decs_cons n D2 Ds2) ->
  subdecs m G Ds1 Ds2.
Proof.
  introv Hasnt. induction Ds2; intro Sds.
  + apply subdecs_empty.
  + rename d into D0. inversions Sds. assumption.
Qed.

(*
Lemma subdecs_skip: forall m G Ds n D,
  decs_hasnt Ds (label_for_dec n D) ->
  subdecs m G (decs_cons n D Ds) Ds.
Proof.
  intros m G Ds. induction Ds; intros.
  + apply subdecs_empty.
  + rename D into D0, d into D.
    unfold decs_hasnt, get_dec in H. case_if. fold get_dec in H.
    apply subdecs_push with D.
    - unfold decs_has, get_dec. case_if. case_if. reflexivity.
    - apply subdec_refl.
    - apply IHDs. 
*)

Lemma decide_decs_has: forall Ds l,
  decs_hasnt Ds l \/ exists D, decs_has Ds l D.
Admitted.

Lemma invert_subdecs: forall m G Ds1 Ds2,
  subdecs m G Ds1 Ds2 -> 
  forall l D2, decs_has Ds2 l D2 -> 
               (exists D1, decs_has Ds1 l D1 /\ subdec m G D1 D2).
Proof.
  introv Sds. induction Ds2; introv Has.
  + inversion Has.
  + inversions Sds.
    unfold decs_has, get_dec in Has. case_if.
    - inversions Has.
      exists D1. split; assumption.
    - fold get_dec in Has. apply IHDs2; assumption.
Qed.

(* subdecs_refl does not hold, because subdecs requires that for each dec in rhs
   (including hidden ones), there is an unhidden one in lhs *)
(* or that there are no hidden decs in rhs *)
Lemma subdecs_refl: forall m G Ds,
  subdecs m G Ds Ds.
Proof.
Admitted. (* TODO does not hold!! *)

Lemma narrow_binds: forall x T G1 y (S1 S2: typ) G2,
  x <> y ->
  binds x T (G1 & y ~ S1 & G2) ->
  binds x T (G1 & y ~ S2 & G2).
Proof.
  introv Ne Bi. apply binds_middle_inv in Bi.
  destruct Bi as [Bi | [[Fr [Eq1 Eq2]] | [Fr [Neq Bi]]]]; subst; auto. false* Ne.
Qed.

Definition vars_empty: vars := \{}.

Lemma narrow_decs_has: forall G Ds1 Ds2 l D2,
  decs_has Ds2 l D2 ->
  subdecs oktrans G Ds1 Ds2 ->
  exists D1, decs_has Ds1 l D1 /\ subdec oktrans G D1 D2.
Proof.
  introv Has Sds. induction Ds2.
  + inversion Has.
  + unfold decs_has, get_dec in Has. inversions Sds. case_if.
    - inversions Has. exists D1. auto.
    - fold get_dec in Has. apply* IHDs2.
Qed.

(** transitivity in oktrans mode (trivial) *)
Lemma subtyp_trans_oktrans: forall G T1 T2 T3,
  subtyp oktrans G T1 T2 -> subtyp oktrans G T2 T3 -> subtyp oktrans G T1 T3.
Proof.
  introv H12 H23.
  apply (subtyp_trans H12 H23).
Qed.

Lemma subdec_trans_oktrans: forall G d1 d2 d3,
  subdec oktrans G d1 d2 -> subdec oktrans G d2 d3 -> subdec oktrans G d1 d3.
Proof.
  introv H12 H23. inversions H12; inversions H23; constructor;
  solve [ assumption | (eapply subtyp_trans_oktrans; eassumption)].
Qed.

Lemma subdecs_trans_oktrans: forall G Ds1 Ds2 Ds3,
  subdecs oktrans G Ds1 Ds2 ->
  subdecs oktrans G Ds2 Ds3 ->
  subdecs oktrans G Ds1 Ds3.
Proof.
  introv H12 H23.
  induction Ds3.
  + apply subdecs_empty.
  + rename d into D3.
    apply invert_subdecs_push in H23.
    destruct H23 as [D2 [H23a [H23b H23c]]].
    lets H12': (invert_subdecs H12).
    specialize (H12' _ _ H23a).
    destruct H12' as [D1 [Has Sd]].
    apply subdecs_push with D1.
    - assumption.
    - apply subdec_trans_oktrans with D2; assumption.
    - apply (IHDs3 H23c).
Qed.

Lemma subtyp_trans_oktrans_n: forall G x T1 T2 T3 Ds1 Ds2,
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds2 ->
  subtyp oktrans (G & x ~ typ_bind Ds1) T1 T2 -> 
  subtyp oktrans (G & x ~ typ_bind Ds2) T2 T3 -> 
  subtyp oktrans (G & x ~ typ_bind Ds1) T1 T3.
Proof.
  introv Sds H12 H23.
  (* for T1=T2, this is narrowing *)
Abort.

Lemma subdec_trans_oktrans_n: forall G x D1 D2 D3 Ds1 Ds2,
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds2 ->
  subdec oktrans (G & x ~ typ_bind Ds1) D1 D2 ->
  subdec oktrans (G & x ~ typ_bind Ds2) D2 D3 ->
  subdec oktrans (G & x ~ typ_bind Ds1) D1 D3.
Proof.
Admitted.

Lemma subdecs_trans_oktrans_n: forall G x Ds1 Ds2 Ds3,
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds2 ->
  subdecs oktrans (G & x ~ typ_bind Ds2) Ds2 Ds3 ->
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds3.
Proof.
  introv H12 H23.
  induction Ds3.
  + apply subdecs_empty.
  + rename d into D3.
    apply invert_subdecs_push in H23.
    destruct H23 as [D2 [H23a [H23b H23c]]].
    lets H12': (invert_subdecs H12).
    specialize (H12' _ _ H23a).
    destruct H12' as [D1 [Has Sd]].
    apply subdecs_push with D1.
    - assumption.
    - apply subdec_trans_oktrans_n with D2 Ds2; assumption.
    - apply (IHDs3 H23c).
Qed. (* does not work because it doesn't work for types *)

Lemma exp_preserves_sub: forall G T1 T2 Ds2,
  subtyp oktrans G T1 T2 ->
  exp G T2 Ds2 ->
  exists Ds1, exp G T1 Ds1 /\ subdecs oktrans G Ds1 Ds2.
Proof.
Abort. (* what if T1 is bottom? *)

(* 
narrowing expansion does not work if we have precise var_has, Bot in upper bounds 
and no expansion for Bot

   If  [G2 |- p has L:Bot..U]
   and [G1 |- p has L:Bot..Bot]
   then to narrow 
   [exp G2 p.L Ds2] into 
   [exp G1 p.L Ds1]
   we need either need imprecise [has] to say [G1 |- p.L has L:Bot..U]
   or we need an expansion for Bot.

But why does narrow-lk in oopsla/dot.elf work? Because
* narrow-lk is only proved for the case where all types of the
  environment which are narrowed are typ_bind (judgment "sev").
* there is no Bot, but lower bounds have a topt

Note: narrow-lk depends on extend-wf-mem and extend-wf-xp (= weakening for var_has/exp)

xp and has-mem are unique

And why does narrowing has work in DotTransitivity?
* Because has only defined for variables of type typ_bind => no expansion needed.

Note that imprecise has means non-unique has => problems in transitivity pushing proof.
So we need an expansion for Bot.
*)

Lemma narrow_exp_var_has:
   (forall G T DsB, exp G T DsB -> 
     forall G1 G2 x S1 S2, 
       G = (G1 & x ~ S2 & G2) -> 
       ok G ->
       subtyp oktrans (G1 & x ~ S1) S1 S2 -> 
       exists   DsA, (forall z, 
                      subdecs oktrans (G1 & x ~ S1) (open_decs z DsA) (open_decs z DsB)) /\
                     exp (G1 & x ~ S1 & G2) T DsA)
/\ (forall G v l DB, var_has G v l DB -> 
     forall G1 G2 x S1 S2, 
       G = (G1 & x ~ S2 & G2) ->
       ok G ->
       subtyp oktrans (G1 & x ~ S1) S1 S2 -> 
       exists DA, subdec oktrans (G1 & x ~ S1) DA DB /\
                  var_has (G1 & x ~ S1 & G2) v l DA).
Proof.
  apply exp_var_has_mutind.
  (* case exp_top *)
  + intros. exists decs_nil. auto.
  (* case exp_bind *)
  + intros. exists Ds. split. 
    - intro. apply subdecs_refl. (* does not hold! *)
    - apply exp_bind.
  (* case exp_sel *)
  + intros G x L Lo Hi Ds Has IH1 Exp IH2 G1 G2 y S1 S2 Eq OkG SubS1S2. subst G.
    specialize (IH1 G1 G2 y S1 S2 eq_refl OkG SubS1S2).
    destruct IH1 as [DA [Sd Has']].
    lets IH2': (IH2 G1 G2 y S1 S2 eq_refl OkG SubS1S2).
    destruct IH2' as [DsA [Sds Exp']].
    inversions Sd. 
    (* case subdec_refl *)
    - exists DsA. split. apply Sds. apply (exp_sel Has' Exp').
    (* case subdec_typ *)
    - exists DsA. split. assumption.
      apply (exp_sel Has'). (* apply Exp'.*) admit.
  
  (* case var_has_dec *)
  + intros G x T Ds l D Bi Exp IH Has G1 G2 y S1 S2 Eq OkG SubS1S2. subst G.
    specialize (IH G1 G2 y S1 S2 eq_refl OkG SubS1S2).
    destruct IH as [DsA [Sds Exp']].
    specialize (Sds x).
    destruct (narrow_decs_has Has Sds) as [DA [Has' Sd]].
    exists DA. split. assumption.
    assert (Ne: x <> y) by admit.
    lets Bi': (narrow_binds S1 Ne Bi).
    apply (var_has_dec Bi' Exp' Has').
Qed.

Lemma subdec_mode: forall G d1 d2,
  subdec notrans G d1 d2 -> subdec oktrans G d1 d2.
Proof.
  intros.
  inversion H; subst; auto.
Qed.

Lemma subtyp_and_subdec_and_subdecs_weaken:
   (forall m G T1 T2 (Hst : subtyp m G T1 T2),
      forall G1 G2 G3, ok (G1 & G2 & G3) ->
                       G1 & G3 = G ->
                       subtyp oktrans (G1 & G2 & G3) T1 T2)
/\ (forall m G d1 d2 (Hsd : subdec m G d1 d2),
      forall G1 G2 G3, ok (G1 & G2 & G3) ->
                       G1 & G3 = G ->
                       subdec oktrans (G1 & G2 & G3) d1 d2)
/\ (forall m G ds1 ds2 (Hsds : subdecs m G ds1 ds2),
      forall G1 G2 G3, ok (G1 & G2 & G3) ->
                       G1 & G3 = G ->
                       subdecs oktrans (G1 & G2 & G3) ds1 ds2).
Proof.
  apply subtyp_mutind.

  (* subtyp *)
  + (* case refl *)
    introv Hok123 Heq; subst.
    apply (subtyp_mode (subtyp_refl _ _)).
  + (* case top *)
    introv Hok123 Heq; subst.
    apply (subtyp_mode (subtyp_top _ _)).
  + (* case bot *)
    introv Hok123 Heq; subst.
    apply (subtyp_mode (subtyp_bot _ _)).
  + (* case bind *)
    introv Hc IH Hok123 Heq; subst. apply subtyp_mode.
    apply_fresh subtyp_bind as z.
    rewrite <- concat_assoc.
    refine (IH z _ G1 G2 (G3 & z ~ typ_bind (open_decs z Ds1)) _ _).
    - auto.
    - rewrite concat_assoc. auto.
    - rewrite <- concat_assoc. reflexivity.
  + (* case asel_l *)
    introv Hhas Hst IH Hok123 Heq; subst.
    apply subtyp_mode.
    apply subtyp_sel_l with (S := S) (U := U).
    (*apply weaken_has; assumption.*) admit.
    apply (IH G1 G2 G3 Hok123).
    trivial.
  + (* case asel_r *)
    introv Hhas Hst_SU IH_SU Hst_TS IH_TS Hok123 Heq; subst.
    apply subtyp_mode.
    apply subtyp_sel_r with (S := S) (U := U).
    (*apply weaken_has; assumption.*) admit.
    apply IH_SU; auto.
    apply IH_TS; auto.
  + (* case trans *)
    introv Hst IH Hok Heq.
    apply subtyp_trans with (T2 := T2).
    apply IH; auto.
    apply (subtyp_mode (subtyp_refl _ T2)).
  + (* case mode *)
    introv Hst12 IH12 Hst23 IH23 Hok123 Heq.
    specialize (IH12 G1 G2 G3 Hok123 Heq).
    specialize (IH23 G1 G2 G3 Hok123 Heq).
    apply (subtyp_trans IH12 IH23).

  (* subdec *)
  + (* case subdec_refl *)
    intros.
    apply subdec_refl.
  + (* case subdec_typ *)
    intros.
    apply subdec_typ; gen G1 G2 G3; assumption.
  + (* case subdec_fld *)
    intros.
    apply subdec_fld; gen G1 G2 G3; assumption.
  + (* case subdec_mtd *)
    intros.
    apply subdec_mtd; gen G1 G2 G3; assumption.

  (* subdecs *)
  + (* case subdecs_empty *)
    intros.
    apply subdecs_empty.
  + (* case subdecs_push *)
    introv Hb Hsd IHsd Hsds IHsds Hok123 Heq.
    apply (subdecs_push n Hb).
    apply (IHsd _ _ _ Hok123 Heq).
    apply (IHsds _ _ _ Hok123 Heq).
Qed.

Lemma subtyp_weaken: forall G1 G2 G3 S U,
  ok (G1 & G2 & G3) -> 
  subtyp oktrans (G1      & G3) S U ->
  subtyp oktrans (G1 & G2 & G3) S U.
Proof.
  destruct subtyp_and_subdec_and_subdecs_weaken as [W _].
  introv Hok123 Hst.
  specialize (W oktrans (G1 & G3) S U Hst).
  specialize (W G1 G2 G3 Hok123).
  apply W.
  trivial.
Qed.

Lemma env_add_empty: forall (P: ctx -> Prop) (G: ctx), P G -> P (G & empty).
Proof.
  intros.
  assert ((G & empty) = G) by apply concat_empty_r.
  rewrite -> H0. assumption.
Qed.  

Lemma env_remove_empty: forall (P: ctx -> Prop) (G: ctx), P (G & empty) -> P G.
Proof.
  intros.
  assert ((G & empty) = G) by apply concat_empty_r.
  rewrite <- H0. assumption.
Qed.

Lemma subtyp_weaken_2: forall G1 G2 S U,
  ok (G1 & G2) -> 
  subtyp oktrans G1        S U ->
  subtyp oktrans (G1 & G2) S U.
Proof.
  introv Hok Hst.
  apply (env_remove_empty (fun G0 => subtyp oktrans G0 S U) (G1 & G2)).
  apply subtyp_weaken.
  apply (env_add_empty (fun G0 => ok G0) (G1 & G2) Hok).
  apply (env_add_empty (fun G0 => subtyp oktrans G0 S U) G1 Hst).
Qed.

(*
Lemma subtyp_and_subdec_and_subdecs_narrow:
   (forall m G T1 T2 (Hst : subtyp m G T1 T2),
      forall G1 G2 z dsA dsB, 
         ok              (G1 & z ~ typ_bind dsB & G2)         ->
         G       =       (G1 & z ~ typ_bind dsB & G2)         ->
         subdecs oktrans (G1 & z ~ typ_bind dsA     ) dsA dsB ->
         subtyp  oktrans (G1 & z ~ typ_bind dsA & G2) T1 T2)
/\ (forall m G d1 d2 (Hsd : subdec m G d1 d2),
      forall G1 G2 z dsA dsB, 
         ok              (G1 & z ~ typ_bind dsB & G2)         ->
         G       =       (G1 & z ~ typ_bind dsB & G2)         ->
         subdecs oktrans (G1 & z ~ typ_bind dsA     ) dsA dsB ->
         subdec  oktrans (G1 & z ~ typ_bind dsA & G2) d1 d2)
/\ (forall m G ds1 ds2 (Hsds : subdecs m G ds1 ds2),
      forall G1 G2 z dsA dsB, 
         ok              (G1 & z ~ typ_bind dsB & G2)         ->
         G       =       (G1 & z ~ typ_bind dsB & G2)         ->
         subdecs oktrans (G1 & z ~ typ_bind dsA     ) dsA dsB ->
         subdecs oktrans (G1 & z ~ typ_bind dsA & G2) ds1 ds2).
Proof.
  apply subtyp_mutind; try (intros; solve [auto]).

  (* subtyp *)
  (* cases refl, top, bot: auto *)
  + (* case bind *)
    introv Hc IH Hok123 Heq HAB; subst. apply subtyp_mode.
    apply_fresh subtyp_bind as z0.
    rewrite <- concat_assoc.
    refine (IH z0 _ G1 (G2 & z0 ~ typ_bind (open_decs z0 Ds1)) _ dsA dsB _ _ _).
    - auto. 
    - rewrite concat_assoc. auto.
    - rewrite <- concat_assoc. reflexivity. 
    - assumption.
  + (* case sel_l *)
    introv Hhas Hst IH Hok Heq HAB; subst.
    apply subtyp_mode.
    lets Hn: (@narrow_has _ _ _ dsA dsB _ _ _ Hok Hhas HAB).
    destruct Hn as [dA [Hrsd Hh]].
    inversions Hrsd.
    (* case refl *)
    - apply subtyp_sel_l with (S := S) (U := U).
      * assumption.
      * apply IH with (dsB0 := dsB); auto.
    (* case not-refl *)
    - inversions H.
      apply subtyp_sel_l with (S := Lo1) (U := Hi1).
      assumption.
      assert (Hok': ok (G1 & z ~ typ_bind dsA & G2)).
      apply (ok_middle_change _ Hok).
      refine (subtyp_trans (subtyp_weaken_2 Hok' H8) _).
      apply IH with (dsB0 := dsB); auto.
  + (* case asel_r *)
    introv Hhas Hst_SU IH_SU Hst_TS IH_TS Hok Heq HAB; subst.
    apply subtyp_mode.
    assert (Hok': ok (G1 & z ~ typ_bind dsA & G2)).
    apply (ok_middle_change _ Hok).
    set (Hn := @narrow_has _ _ _ dsA dsB _ _ _ Hok Hhas HAB).
    destruct Hn as [dA [Hrsd Hh]].
    inversions Hrsd.
    (* case refl *)
    - apply subtyp_sel_r with (S := S) (U := U).
      * assumption.
      * apply IH_SU with (dsB0 := dsB); auto.
      * apply IH_TS with (dsB0 := dsB); auto.
    (* case not-refl *)
    - inversions H.
      apply subtyp_sel_r with (S := Lo1) (U := Hi1).
      assumption.
      apply (subtyp_weaken_2 Hok' H2).
      refine (subtyp_trans _ (subtyp_weaken_2 Hok' H7)).
      apply IH_TS with (dsB0 := dsB); auto.
  (* case trans *)
  + introv Hst IH Hok Heq HAB.
    apply subtyp_trans with (T2 := T2).
    - apply IH with (dsB := dsB); auto.
    - apply (subtyp_mode (subtyp_refl _ T2)).
  (* case mode *)
  + introv Hst12 IH12 Hst23 IH23 Hok123 Heq HAB.
    specialize (IH12 G1 G2 z dsA dsB Hok123 Heq HAB).
    specialize (IH23 G1 G2 z dsA dsB Hok123 Heq HAB).
    apply (subtyp_trans IH12 IH23).

  (* subdec *)
  (* case subdec_typ *)
  + intros.
    apply subdec_typ; gen G1 G2 z dsA dsB; assumption.
  (* case subdec_fld *)
  + intros.
    apply subdec_fld; gen G1 G2 z dsA dsB; assumption.
  (* case subdec_mtd *)
  + intros.
    apply subdec_mtd; gen G1 G2 z dsA dsB; assumption.

  (* subdecs *)
  (* case subdecs_empty *)
  + intros.
    apply subdecs_empty.
  (* case subdecs_push *)
  + introv Hb Hsd IHsd Hsds IHsds Hok123 Heq HAB.
    apply (subdecs_push n Hb).
    apply (IHsd  _ _ _ _ _ Hok123 Heq HAB).
    apply (IHsds _ _ _ _ _ Hok123 Heq HAB).
Qed.

Lemma subdec_narrow: forall G1 G2 z ds1 ds2 dA dB,
  ok              (G1 & z ~ typ_bind ds2 & G2) ->
  subdec  oktrans (G1 & z ~ typ_bind ds2 & G2) dA dB ->
  subdecs oktrans (G1 & z ~ typ_bind ds1     ) ds1 ds2 ->
  subdec  oktrans (G1 & z ~ typ_bind ds1 & G2) dA dB.
Proof.
  introv Hok HAB Hsds.
  destruct subtyp_and_subdec_and_subdecs_narrow as [_ [N _]].
  specialize (N oktrans (G1 & z ~ typ_bind ds2 & G2) dA dB).
  specialize (N HAB G1 G2 z ds1 ds2 Hok).
  apply N.
  trivial.
  assumption.
Qed.

Lemma subdecs_narrow: forall G1 G2 z ds1 ds2 dsA dsB,
  ok              (G1 & z ~ typ_bind ds2 & G2) ->
  subdecs oktrans (G1 & z ~ typ_bind ds2 & G2) dsA dsB ->
  subdecs oktrans (G1 & z ~ typ_bind ds1     ) ds1 ds2 ->
  subdecs oktrans (G1 & z ~ typ_bind ds1 & G2) dsA dsB.
Proof.
  introv Hok HAB Hsds.
  destruct subtyp_and_subdec_and_subdecs_narrow as [_ [_ N]].
  specialize (N oktrans (G1 & z ~ typ_bind ds2 & G2) dsA dsB).
  specialize (N HAB G1 G2 z ds1 ds2 Hok).
  apply N.
  trivial.
  assumption.
Qed.

Lemma subdec_narrow_last: forall G z ds1 ds2 dA dB,
  ok              (G & z ~ typ_bind ds2) ->
  subdec  oktrans (G & z ~ typ_bind ds2) dA dB ->
  subdecs oktrans (G & z ~ typ_bind ds1) ds1 ds2 ->
  subdec  oktrans (G & z ~ typ_bind ds1) dA dB.
Proof.
  introv Hok HAB H12.
  apply (env_remove_empty (fun G0 => subdec oktrans G0 dA dB) (G & z ~ typ_bind ds1)).
  apply subdec_narrow with (ds2 := ds2).
  apply (env_add_empty (fun G0 => ok G0) (G & z ~ typ_bind ds2) Hok).
  apply (env_add_empty (fun G0 => subdec oktrans G0 dA dB)
                             (G & z ~ typ_bind ds2) HAB).
  assumption.
Qed.

Print Assumptions subdec_narrow_last.

Lemma subdecs_narrow_last: forall G z ds1 ds2 dsA dsB,
  ok              (G & z ~ typ_bind ds2) ->
  subdecs oktrans (G & z ~ typ_bind ds2) dsA dsB ->
  subdecs oktrans (G & z ~ typ_bind ds1) ds1 ds2 ->
  subdecs oktrans (G & z ~ typ_bind ds1) dsA dsB.
Proof.
  introv Hok H2AB H112.
  apply (env_remove_empty (fun G0 => subdecs oktrans G0 dsA dsB) (G & z ~ typ_bind ds1)).
  apply subdecs_narrow with (ds2 := ds2).
  apply (env_add_empty (fun G0 => ok G0) (G & z ~ typ_bind ds2) Hok).
  apply (env_add_empty (fun G0 => subdecs oktrans G0 dsA dsB)
                             (G & z ~ typ_bind ds2) H2AB).
  assumption.
Qed.
*)

(* ... transitivity in notrans mode, but no p.L in middle ... *)

Lemma subtyp_trans_notrans: forall G T1 T2 T3,
  ok G -> notsel T2 -> subtyp notrans G T1 T2 -> subtyp notrans G T2 T3 -> 
  subtyp notrans G T1 T3.
Proof.
  introv Hok Hnotsel H12 H23.

  inversion Hnotsel; subst.
  (* case top *)
  + inversion H23; subst.
    apply (subtyp_top G T1).
    apply (subtyp_top G T1).
    apply (subtyp_sel_r H H0 (subtyp_trans (subtyp_mode H12) H1)).
  (* case bot *)
  + inversion H12; subst.
    apply (subtyp_bot G T3).
    apply (subtyp_bot G T3).
    apply (subtyp_sel_l H (subtyp_trans H0 (subtyp_mode H23))).
  (* case bind *)
  + inversion H12; inversion H23; subst; (
      assumption ||
      apply subtyp_refl ||
      apply subtyp_top ||
      apply subtyp_bot ||
      idtac
    ).
    (* bind <: bind <: bind *)
    - apply_fresh subtyp_bind as z.
      assert (zL: z \notin L) by auto.
      assert (zL0: z \notin L0) by auto.
      specialize (H0 z zL).
      specialize (H4 z zL0).
      assert (Hok'': ok (G & z ~ typ_bind (open_decs z ds))) by auto.
      (* with narrowing: *)
      (*
      lets H4' : (subdecs_narrow_last Hok'' H4 H0). 
      apply (subdecs_trans H0 H4').
      *)
      (* without narrowing (i.e. narrowing baked into subdecs_trans_oktrans_n
         which does not hold *)
      apply (subdecs_trans_oktrans_n H0 H4).
    - (* bind <: bind <: sel  *)
      assert (H1S: subtyp oktrans G (typ_bind Ds1) S).
      apply (subtyp_trans_oktrans (subtyp_mode H12) H5).
      apply (subtyp_sel_r H3 H4 H1S).
    - (* sel  <: bind <: bind *)
      assert (HU2: subtyp oktrans G U (typ_bind Ds2)).
      apply (subtyp_trans_oktrans H0 (subtyp_mode H23)).
      apply (subtyp_sel_l H HU2). 
    - (* sel  <: bind <: sel  *)
      apply (subtyp_sel_r H1 H5).
      apply (subtyp_trans_oktrans (subtyp_mode H12) H6).
Qed.

Print Assumptions subtyp_trans_notrans.

(**
(follow_ub G p1.X1 T) means that there exists a chain

    (p1.X1: _ .. p2.X2), (p2.X2: _ .. p3.X3), ... (pN.XN: _ .. T)

which takes us from p1.X1 to T
*)
Inductive follow_ub : ctx -> typ -> typ -> Prop :=
  | follow_ub_nil : forall G T,
      follow_ub G T T
  | follow_ub_cons : forall G v X Lo Hi T,
      has G (trm_var v) X (dec_typ Lo Hi) ->
      follow_ub G Hi T ->
      follow_ub G (typ_sel (pth_var v) X) T.

(**
(follow_lb G T pN.XN) means that there exists a chain

    (p1.X1: T .. _), (p2.X2: p1.X1 .. _), (p3.X3: p2.X2 .. _),  (pN.XN: pN-1.XN-1 .. _)

which takes us from T to pN.XN
*)
Inductive follow_lb: ctx -> typ -> typ -> Prop :=
  | follow_lb_nil : forall G T,
      follow_lb G T T
  | follow_lb_cons : forall G v X Lo Hi U,
      has G (trm_var v) X (dec_typ Lo Hi) ->
      subtyp oktrans G Lo Hi -> (* <-- realizable bounds *)
      follow_lb G (typ_sel (pth_var v) X) U ->
      follow_lb G Lo U.

Hint Constructors follow_ub.
Hint Constructors follow_lb.

Lemma invert_follow_lb: forall G T1 T2,
  follow_lb G T1 T2 -> 
  T1 = T2 \/ 
    exists v1 X1 v2 X2 Hi, (typ_sel (pth_var v2) X2) = T2 /\
      has G (trm_var v1) X1 (dec_typ T1 Hi) /\
      subtyp oktrans G T1 Hi /\
      follow_lb G (typ_sel (pth_var v1) X1) (typ_sel (pth_var v2) X2).
Proof.
  intros.
  induction H.
  auto.
  destruct IHfollow_lb as [IH | IH].
  subst.
  right. exists v X v X Hi. auto.
  right.
  destruct IH as [p1 [X1 [p2 [X2 [Hi' [Heq [IH1 [IH2 IH3]]]]]]]].
  subst.  
  exists v X p2 X2 Hi.
  auto.
Qed.

(* Note: No need for a invert_follow_ub lemma because inversion is smart enough. *)

Definition st_middle (G: ctx) (B C: typ): Prop :=
  B = C \/
  subtyp notrans G typ_top C \/
  (notsel B /\ subtyp notrans G B C).

(* linearize a derivation that uses transitivity *)

Definition chain (G: ctx) (A D: typ): Prop :=
   (exists B C, follow_ub G A B /\ st_middle G B C /\ follow_lb G C D).

Lemma empty_chain: forall G T, chain G T T.
Proof.
  intros.
  unfold chain. unfold st_middle.
  exists T T.
  auto.
Qed.

Lemma chain3subtyp: forall G C1 C2 D, 
  subtyp notrans G C1 C2 ->
  follow_lb G C2 D -> 
  subtyp notrans G C1 D.
Proof.
  introv Hst Hflb.
  induction Hflb.
  assumption.
  apply IHHflb.
  apply (subtyp_sel_r H H0 (subtyp_mode Hst)).
Qed.

Lemma chain2subtyp: forall G B1 B2 C D,
  ok G ->
  subtyp notrans G B1 B2 ->
  st_middle G B2 C ->
  follow_lb G C D ->
  subtyp notrans G B1 D.
Proof.
  introv Hok Hst Hm Hflb.
  unfold st_middle in Hm.
  destruct Hm as [Hm | [Hm | [Hm1 Hm2]]]; subst.
  apply (chain3subtyp Hst Hflb).
  apply (chain3subtyp (subtyp_trans_notrans Hok notsel_top (subtyp_top G B1) Hm) Hflb).
  apply (chain3subtyp (subtyp_trans_notrans Hok Hm1 Hst Hm2) Hflb).
Qed.

Lemma chain1subtyp: forall G A B C D,
  ok G ->
  follow_ub G A B ->
  st_middle G B C ->
  follow_lb G C D ->
  subtyp notrans G A D.
Proof.
  introv Hok Hfub Hm Hflb.
  induction Hfub.
  apply (chain2subtyp Hok (subtyp_refl G T) Hm Hflb).
  apply (subtyp_sel_l H).
  apply subtyp_mode.
  apply (IHHfub Hok Hm Hflb).
Qed.

(* prepend an oktrans to chain ("utrans0*") *)
Lemma prepend_chain: forall G A1 A2 D,
  ok G ->
  subtyp oktrans G A1 A2 ->
  chain G A2 D ->
  chain G A1 D.
Proof.
  fix 6.
  introv Hok Hokt Hch.
  unfold chain in *. unfold st_middle in *.
  inversion Hokt; inversion H; subst.
  (* case refl *)
  assumption.
  (* case top *)
  destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
  inversion Hch1; subst.
  destruct Hch2 as [Hch2 | [Hch2 | [Hch2a Hch2b]]]; subst.
  exists A1 typ_top.
  auto 10.
  exists A1 C.
  auto 10.
  exists A1 C.
  auto 10.
  (* case bot *)
  destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
  exists typ_bot C.
  auto 10.
  (* case bind *)
  destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
  inversion Hch1; subst.
  exists (typ_bind Ds1) C.
  destruct Hch2 as [Hch2 | [Hch2 | [Hch2a Hch2b]]].
  subst.
  auto 10. (* <- search depth *)
  auto 10.
  set (Hst := (subtyp_trans_notrans Hok (notsel_bind _) H Hch2b)).
  auto 10.
  (* case asel_l *)
  set (IH := (prepend_chain G U A2 D Hok H4 Hch)).
  destruct IH as [B [C [IH1 [IH2 IH3]]]].
  exists B C.
  split. 
  apply (follow_ub_cons H0 IH1).
  split; assumption.
  (* case asel_r *) 
  set (Hch' := Hch).
  destruct Hch' as [B [C [Hch1 [Hch2 Hch3]]]].
  inversion Hch1; subst.
    (* case follow_ub_nil *)
    destruct Hch2 as [Hch2 | [Hch2 | [Hch2a Hch2b]]].
    subst.
    apply (prepend_chain G A1 S D Hok H5).
    exists S S. 
    set (Hflb := (follow_lb_cons H0 H4 Hch3)).
    auto.
    exists A1 C.
    auto.
    inversion Hch2a. (* contradiction *)
    (* case follow_ub_cons *)
    apply (prepend_chain G A1 S D Hok H5).
    apply (prepend_chain G S U D Hok H4).
    assert (HdecEq: dec_typ Lo Hi = dec_typ S U) by admit (*apply (has_var_unique H6 H0)*).
    injection HdecEq; intros; subst.
    exists B C.
    split. assumption. split. assumption. assumption.
  (* case mode *)
  apply (prepend_chain G _ _ _ Hok H (prepend_chain G _ _ _ Hok H0 Hch)).
  (* case trans *)
  apply (prepend_chain G _ _ _ Hok H (prepend_chain G _ _ _ Hok H0 Hch)).
Admitted. (* TODO termination! *)

Lemma oktrans_to_notrans: forall G T1 T3,
  ok G -> subtyp oktrans G T1 T3 -> subtyp notrans G T1 T3.
Proof.
  introv Hok Hst.
  assert (Hch: chain G T1 T3).
  apply (prepend_chain Hok Hst (empty_chain _ _)).
  unfold chain in Hch.
  destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
  apply (chain1subtyp Hok Hch1 Hch2 Hch3).
Qed.

Print Assumptions oktrans_to_notrans.


(* ###################################################################### *)
(* ###################################################################### *)
(** * Soundness Proofs *)

(* ###################################################################### *)
(** ** Progress *)

Theorem progress_result: progress.
Proof.
  introv Wf Ty. gen G e T Ty s Wf.
  set (progress_for := fun s e =>
                         (exists e' s', red e s e' s') \/
                         (exists x ds, e = (trm_var (avar_f x)) /\ binds x ds s)).
  apply (ty_trm_mut
    (fun G e l d (Hhas: has G e l d)         => forall s, wf_sto s G -> progress_for s e)
    (fun G e T   (Hty: ty_trm G e T)     => forall s, wf_sto s G -> progress_for s e)
    (fun G i d   (Htyp: ty_def G i d)    => True)
    (fun G is Ds (Htyp: ty_defs G is Ds) => True));
  unfold progress_for; clear progress_for; intros; try apply I; auto_specialize.
  (* case has_trm *)
  + assumption. 
  (* case ty_var *)
  + right. destruct (ctx_binds_to_sto_binds H b) as [is Hbv].
    exists x is. auto.
  (* case ty_sel *)
  + left. destruct H as [IH | IH].
    (* receiver is an expression *)
    - destruct IH as [s' [e' IH]]. do 2 eexists. apply (red_sel1 l IH). 
    (* receiver is a var *)
    - destruct IH as [x [is [Heq Hbv]]]. subst.
      destruct (invert_has h) as [ds [Hty Hbd]].
      lets Hbt: (invert_ty_var Hty).
      destruct (invert_wf_sto H0 Hbv Hbt) as [G1 [G2 [Eq Hty2]]].
      destruct (decs_has_to_defs_has Hty2 Hbd) as [i Hbi].
      destruct (defs_has_fld_sync Hbi) as [y Heq]. subst.
      exists (trm_var y) s.
      apply (red_sel Hbv Hbi).
  (* case ty_call *)
  + left. destruct H as [IHrec | IHrec].
    (* case receiver is an expression *)
    - destruct IHrec as [s' [e' IHrec]]. do 2 eexists. apply (red_call1 m _ IHrec).
    (* case receiver is  a var *)
    - destruct IHrec as [x [is [Heqx Hbv]]]. subst.
      destruct H0 as [IHarg | IHarg].
      (* arg is an expression *)
      * destruct IHarg as [s' [e' IHarg]]. do 2 eexists. apply (red_call2 x m IHarg).
      (* arg is a var *)
      * destruct IHarg as [y [is' [Heqy Hbv']]]. subst. 
        destruct (invert_has h) as [ds [Hty Hbd]].
        lets Hbt: (invert_ty_var Hty).
        destruct (invert_wf_sto H1 Hbv Hbt) as [G1 [G2 [Eq Hty2]]].
        destruct (decs_has_to_defs_has Hty2 Hbd) as [i Hbi].
        destruct (defs_has_mtd_sync Hbi) as [U' [e Heq]]. subst.
        exists (open_trm y e) s.
        apply (red_call y Hbv Hbi).
  (* case ty_new *)
  + left. pick_fresh x.
    exists (trm_var (avar_f x)) (s & x ~ (open_defs x ds)).
    apply* red_new.
Qed.

Print Assumptions progress_result.


(* ###################################################################### *)
(** ** Weakening lemmas *)

(* If we only weaken at the end, i.e. from [G1] to [G1 & G2], the IH for the 
   [ty_new] case adds G2 to the end, so it takes us from [G1, x: Ds] 
   to [G1, x: Ds, G2], but we need [G1, G2, x: Ds].
   So we need to weaken in the middle, i.e. from [G1 & G3] to [G1 & G2 & G3].
   Then, the IH for the [ty_new] case inserts G2 in the middle, so it
   takes us from [G1 & G3, x: Ds] to [G1 & G2 & G3, x: Ds], which is what we
   need. *)

Lemma weakening:
   (forall G e l d (Hhas: has G e l d)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)),
           has (G1 & G2 & G3) e l d ) 
/\ (forall G e T (Hty: ty_trm G e T)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)),
           ty_trm (G1 & G2 & G3) e T) 
/\ (forall G i d (Hty: ty_def G i d)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)), 
           ty_def (G1 & G2 & G3) i d)
/\ (forall G is Ds (Hisds: ty_defs G is Ds)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)), 
           ty_defs (G1 & G2 & G3) is Ds).
Proof.
  apply ty_mutind; intros; subst.
  + apply* has_trm.
  + apply ty_var. apply* binds_weaken.
  + apply* ty_sel.
  + apply* ty_call.
  + apply_fresh ty_new as x.
    rewrite <- concat_assoc.
    refine (H x _ G1 G2 (G3 & x ~ typ_bind Ds) _ _).
    - auto.
    - rewrite concat_assoc. reflexivity.
    - rewrite concat_assoc. auto.
  + apply* ty_fld.
  + rename H into IH.
    apply_fresh ty_mtd as x.
    rewrite <- concat_assoc.
    refine (IH x _ G1 G2 (G3 & x ~ S) _ _).
    - auto.
    - symmetry. apply concat_assoc.
    - rewrite concat_assoc. auto.
  + apply ty_dsnil.
  + apply* ty_dscons.
Qed.

Print Assumptions weakening.

Lemma weaken_has: forall G1 G2 e l d,
  has G1 e l d -> ok (G1 & G2) -> has (G1 & G2) e l d.
Proof.
  intros.
  destruct weakening as [W _].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_trm: forall G1 G2 e T,
  ty_trm G1 e T -> ok (G1 & G2) -> ty_trm (G1 & G2) e T.
Proof.
  intros.
  destruct weakening as [_ [W _]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_def: forall G1 G2 i d,
  ty_def G1 i d -> ok (G1 & G2) -> ty_def (G1 & G2) i d.
Proof.
  intros.
  destruct weakening as [_ [_ [W _]]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_defs: forall G1 G2 is Ds,
  ty_defs G1 is Ds -> ok (G1 & G2) -> ty_defs (G1 & G2) is Ds.
Proof.
  intros.
  destruct weakening as [_ [_ [_ W]]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.


(* ###################################################################### *)
(** ** Inversion lemmas which depend on weakening *)

Lemma invert_wf_sto_with_weakening: forall s G,
  wf_sto s G -> 
    forall x ds Ds, 
      binds x ds s -> 
      binds x (typ_bind Ds) G ->
      ty_defs G ds Ds.
Proof.
  introv Wf Bs BG.
  lets P: (invert_wf_sto Wf).
  specialize (P x ds Ds Bs BG).
  destruct P as [G1 [G2 [Eq Ty]]]. subst.
  apply* weaken_ty_defs.
Qed.


(* ###################################################################### *)
(** ** The substitution principle *)


(*

                  G, x: S |- e : T      G |- u : S
                 ----------------------------------
                            G |- [u/x]e : T

Note that in general, u is a term, but for our purposes, it suffices to consider
the special case where u is a variable.
*)

Lemma raw_subst_principles: forall y S,
  (forall (G0 : ctx) (t : trm) (l : label) (d : dec) (Hhas : has G0 t l d),
    (fun G0 e0 l d (Hhas: has G0 e0 l d) => 
      forall G1 G2 x, G0 = (G1 & (x ~ S) & G2) ->
                      ty_trm (G1 & G2) (trm_var (avar_f y)) S ->
                      ok (G1 & (x ~ S) & G2) ->
                      has (G1 & G2) (subst_trm x y t) l d)
    G0 t l d Hhas) /\
  (forall (G0 : ctx) (t : trm) (T : typ) (Hty : ty_trm G0 t T),
    (fun G0 t T (Hty: ty_trm G0 t T) => 
      forall G1 G2 x, G0 = (G1 & (x ~ S) & G2) ->
                      ty_trm (G1 & G2) (trm_var (avar_f y)) S ->
                      ok (G1 & (x ~ S) & G2) ->
                      ty_trm (G1 & G2) (subst_trm x y t) T)
    G0 t T Hty) /\
  (forall (G0 : ctx) (d : def) (D : dec) (Hty : ty_def G0 d D),
    (fun G d D (Htyp: ty_def G d D) => 
      forall G1 G2 x, G0 = (G1 & (x ~ S) & G2) ->
                      ty_trm (G1 & G2) (trm_var (avar_f y)) S ->
                      ok (G1 & (x ~ S) & G2) ->
                      ty_def (G1 & G2) (subst_def x y d) D)
    G0 d D Hty) /\
  (forall (G0 : ctx) (ds : defs) (Ds : decs) (Hty : ty_defs G0 ds Ds),
    (fun G ds Ds (Hty: ty_defs G ds Ds) => 
      forall G1 G2 x, G0 = (G1 & (x ~ S) & G2) ->
                      ty_trm (G1 & G2) (trm_var (avar_f y)) S ->
                      ok (G1 & (x ~ S) & G2) ->
                      ty_defs (G1 & G2) (subst_defs x y ds) Ds)
    G0 ds Ds Hty).
Proof.
  intros y S.
  apply ty_mutind; intros;
  (* renaming: *)
  lazymatch goal with
    (* 2 IHs *)
    | H1: context[forall (_ _ : env typ) (_ : var), _], 
      H2: context[forall (_ _ : env typ) (_ : var), _] |- _ 
      => rename H1 into IH1, H2 into IH2
    (* 1 IH *)
    | H : context[forall (_ _ : env typ) (_ : var), _] |- _ 
      => rename H into IH
    (* no IH *)
    | _ => idtac
  end;
  match goal with
    | H: @eq ctx _ _ |- _ => rename H into EqG
  end;
  match goal with
    | H: ok _ |- _ => rename H into Hok
  end.
  (* case has_trm *)
  + apply* has_trm.
  (* case ty_var *)
  + subst. rename x into z, x0 into x. unfold subst_trm, subst_avar. case_var.
    (* case z = x *)
    - assert (EqST: T = S) by apply (binds_middle_eq_inv b Hok). subst. assumption.
    (* case z <> x *)
    - apply ty_var. apply* binds_remove.
  (* case ty_sel *)
  + apply* ty_sel.
  (* case ty_call *)
  + apply* ty_call.
  (* case ty_new *)
  + apply_fresh ty_new as z.
    fold subst_defs.
    lets C: (@subst_open_commute_defs x y z ds).
    unfolds open_defs. unfold subst_fvar in C. case_var.
    rewrite <- C.
    rewrite <- concat_assoc.
    subst G.
    assert (zL: z \notin L) by auto.
    refine (IH z zL G1 (G2 & z ~ typ_bind Ds) x _ _ _); rewrite concat_assoc.
    - reflexivity.
    - apply* weaken_ty_trm.
    - auto.
  (* case ty_fld *)
  + apply* ty_fld.
  (* case ty_mtd *)
  + apply_fresh ty_mtd as z. fold subst_trm.
    lets C: (@subst_open_commute_trm x y z t).
    unfolds open_trm. unfold subst_fvar in C. case_var.
    rewrite <- C.
    rewrite <- concat_assoc.
    refine (IH z _ G1 (G2 & z ~ S0) _ _ _ _).
    - auto.
    - subst. rewrite concat_assoc. reflexivity.
    - subst. rewrite concat_assoc.
      apply* weaken_ty_trm.
    - rewrite concat_assoc. auto.
  (* case ty_dsnil *)
  + apply ty_dsnil.
  (* case ty_dscons *)
  + apply* ty_dscons.
Qed.

Print Assumptions raw_subst_principles.

Lemma subst_principle: forall G x y t S T,
  ok (G & x ~ S) ->
  ty_trm (G & x ~ S) t T ->
  ty_trm G (trm_var (avar_f y)) S ->
  ty_trm G (subst_trm x y t) T.
Proof.
  introv Hok tTy yTy. destruct (raw_subst_principles y S) as [_ [P _]].
  specialize (P _ t T tTy G empty x).
  repeat (progress (rewrite concat_empty_r in P)).
  apply* P.
Qed.

Lemma ty_open_trm_change_var: forall x y G e S T,
  ok (G & x ~ S) ->
  ok (G & y ~ S) ->
  x \notin fv_trm e ->
  ty_trm (G & x ~ S) (open_trm x e) T ->
  ty_trm (G & y ~ S) (open_trm y e) T.
Proof.
  introv Hokx Hoky xFr Ty.
  destruct (classicT (x = y)) as [Eq | Ne]. subst. assumption.
  assert (Hokxy: ok (G & x ~ S & y ~ S)) by destruct* (ok_push_inv Hoky).
  assert (Ty': ty_trm (G & x ~ S & y ~ S) (open_trm x e) T).
  apply (weaken_ty_trm Ty Hokxy).
  rewrite* (@subst_intro_trm x y e).
  lets yTy: (ty_var (binds_push_eq y S G)).
  destruct (raw_subst_principles y S) as [_ [P _]].
  apply (P _ (open_trm x e) T Ty' G (y ~ S) x eq_refl yTy Hokxy).
Qed.

Lemma ty_open_defs_change_var: forall x y G ds S T,
  ok (G & x ~ S) ->
  ok (G & y ~ S) ->
  x \notin fv_defs ds ->
  ty_defs (G & x ~ S) (open_defs x ds) T ->
  ty_defs (G & y ~ S) (open_defs y ds) T.
Proof.
  introv Hokx Hoky xFr Ty.
  destruct (classicT (x = y)) as [Eq | Ne]. subst. assumption.
  assert (Hokxy: ok (G & x ~ S & y ~ S)) by destruct* (ok_push_inv Hoky).
  assert (Ty': ty_defs (G & x ~ S & y ~ S) (open_defs x ds) T).
  apply (weaken_ty_defs Ty Hokxy).
  rewrite* (@subst_intro_defs x y ds).
  lets yTy: (ty_var (binds_push_eq y S G)).
  destruct (raw_subst_principles y S) as [_ [_ [_ P]]].
  apply (P _ (open_defs x ds) T Ty' G (y ~ S) x eq_refl yTy Hokxy).
Qed.


(* ###################################################################### *)
(** ** Preservation *)

Theorem preservation_proof:
  forall e s e' s' (Hred: red e s e' s') G T (Hwf: wf_sto s G) (Hty: ty_trm G e T),
  (exists H, wf_sto s' (G & H) /\ ty_trm (G & H) e' T).
Proof.
  intros s e s' e' Hred. induction Hred; intros.
  (* red_call *)
  + rename H into Hvbx. rename H0 into Hibm. rename T0 into U.
    exists (@empty typ). rewrite concat_empty_r. split. apply Hwf.
    (* Grab "ctx binds x" hypothesis: *)
    apply invert_ty_call in Hty. 
    destruct Hty as [T' [Hhas Htyy]].
    apply invert_has in Hhas. 
    destruct Hhas as [Ds [Htyx Hdbm]].
    apply invert_ty_var in Htyx. rename Htyx into Htbx.
    (* Feed "binds x" and "ctx binds x" to invert_wf_sto: *)
    lets HdsDs: (invert_wf_sto_with_weakening Hwf Hvbx Htbx).
    destruct (invert_ty_mtd_inside_ty_defs HdsDs Hibm Hdbm) as [L Hmtd].
    pick_fresh y'.
    rewrite* (@subst_intro_trm y' y body).
    apply* (@subst_principle G y' y ((open_trm y' body)) T' U).
  (* red_sel *)
  + rename H into Hvbx. rename H0 into Hibl.
    exists (@empty typ). rewrite concat_empty_r. split. apply Hwf.
    apply invert_ty_sel in Hty.
    apply invert_has in Hty.
    destruct Hty as [Ds [Htyx Hdbl]].
    apply invert_ty_var in Htyx. rename Htyx into Htbx.
    (* Feed "binds x" and "ctx binds x" to invert_wf_sto: *)
    lets HdsDs: (invert_wf_sto_with_weakening Hwf Hvbx Htbx).
    apply (invert_ty_fld_inside_ty_defs HdsDs Hibl Hdbl).
  (* red_new *)
  + rename H into Hvux.
    apply invert_ty_new in Hty.
    destruct Hty as [L [Ds [Eq HdsDs]]]. subst T.
    exists (x ~ typ_bind Ds).
    pick_fresh x'. assert (Frx': x' \notin L) by auto.
    specialize (HdsDs x' Frx').
    assert (xG: x # G) by apply* sto_unbound_to_ctx_unbound.
    split.
    - apply (wf_sto_push Hwf Hvux xG). apply* (@ty_open_defs_change_var x').
    - apply ty_var. apply binds_push_eq.
  (* red_call1 *)
  + rename T into Tr.
    apply invert_ty_call in Hty.
    destruct Hty as [Ta [Hhas Htya]].
    apply invert_has in Hhas.
    destruct Hhas as [Ds [Htyo Hdbm]].
    specialize (IHHred G (typ_bind Ds) Hwf Htyo).
    destruct IHHred as [H [Hwf' Htyo']].
    exists H. split. assumption. apply (@ty_call (G & H) o' m Ta Tr a).
    - apply (has_trm Htyo' Hdbm).
    - lets Hok: wf_sto_to_ok_G Hwf'.
      apply (weaken_ty_trm Htya Hok).
  (* red_call2 *)
  + rename T into Tr.
    apply invert_ty_call in Hty.
    destruct Hty as [Ta [Hhas Htya]].
    specialize (IHHred G Ta Hwf Htya).
    destruct IHHred as [H [Hwf' Htya']].
    exists H. split. assumption. apply (@ty_call (G & H) _ m Ta Tr a').
    - lets Hok: wf_sto_to_ok_G Hwf'.
      apply (weaken_has Hhas Hok).
    - assumption.
  (* red_sel1 *)
  + apply invert_ty_sel in Hty.
    apply invert_has in Hty.
    destruct Hty as [Ds [Htyo Hdbl]].
    specialize (IHHred G (typ_bind Ds) Hwf Htyo).
    destruct IHHred as [H [Hwf' Htyo']].
    exists H. split. assumption. apply (@ty_sel (G & H) o' l T).
    apply (has_trm Htyo' Hdbl).
Qed.

Theorem preservation_result: preservation.
Proof.
  introv Hwf Hty Hred.
  destruct (preservation_proof Hred Hwf Hty) as [H [Hwf' Hty']].
  exists (G & H). split; assumption.
Qed.

Print Assumptions preservation_result.

End Proofs.
