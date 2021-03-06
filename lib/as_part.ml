(*
 * Copyright (c) 2014 Thomas Gazagnaire <thomas@gazagnaire.org>
 * Copyright (c) 2014 Daniel C. Bünzli
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Astring
open Bos

(* Part kinds *)

type kind = [ `Base | `Unit | `Lib | `Bin | `Pkg | `Run | `Doc | `Dir ]
let pp_kind ppf k = As_ctx.pp_kind ppf (k :> kind) (* weird *)

let err_coerce k exp =
  Format.asprintf "part has kind %a not %a" pp_kind k pp_kind exp

(* Usage *)

type usage = [ `Dev | `Test | `Build | `Doc | `Outcome | `Other of string ]
let pp_usage = As_ctx.pp_usage

(* Metadata *)

type meta = As_univ.t
let meta_key = As_univ.create
let meta_nil = fst (meta_key ()) ()

(* Part definition, sets and maps *)

type +'a t =
  { id : int;                                   (* a unique id for the part. *)
    kind : kind;                                         (* the part's kind. *)
    name : string;                      (* the part name, may not be unique. *)
    usage : usage;                                      (* the part's usage. *)
    exists : bool As_conf.value;              (* [true] if exists in config. *)
    args : As_args.t;                           (* end user argument bundle. *)
    meta : meta;                         (* part's metadata (kind specific). *)
    needs : kind t list;          (* part's need, n.b. unique and *ordered*. *)
    root : path As_conf.value;               (* part's build root directory. *)
    action_defs :                                      (* action definition. *)
      kind t -> As_action.t list As_conf.value ;
    actions :                          (* part's actions (via actions_defs). *)
      As_action.t list As_conf.value Lazy.t;
    check : kind t -> bool As_conf.value; } (* part's sanity check function. *)
  constraint 'a = [< kind ]

module Part = struct
  type part = kind t
  type t = part
  let compare p p' = (compare : int -> int -> int) p.id p'.id
end

module Set = struct
  include Set.Make (Part)
  let of_list = List.fold_left (fun acc s -> add s acc) empty
end

module Map = struct
  include Map.Make (Part)
  let dom m = fold (fun k _ acc -> Set.add k acc) m Set.empty
end


(* Part *)

let part_id =
  let count = ref (-1) in
  fun () -> incr count; !count

let alloc_root =
  (* We intercept and resolve duplicate default part directory roots
     at part *creation* time. This allows two parts of the same
     kind/name to coexist. We can't do it later e.g. at project
     creation time by using [with_root] since if the part is being
     consulted by others they won't refer to the part newly allocated
     by [with_root]. The [with_root] mecanism can only be used for
     parts that are integrated in others as in this case their build
     products should not be referenced by other parts except through
     the integrating part. *)
  let allocated = ref String.Set.empty in
  fun kind usage name ->
    let part_root =
      let root = match usage with
      | `Outcome -> strf "%a-%s" pp_kind kind name
      | u -> strf "%a-%a-%s" pp_kind kind pp_usage u name
      in
      let root = String.make_unique_in !allocated root in
      allocated := String.Set.add root !allocated;
      root
    in
    let in_build_dir build = Path.(build / part_root) in
    As_conf.(const in_build_dir $ (value As_conf.build_dir))

let list_uniquify ps =           (* uniquify part list while keeping order. *)
  let add (seen, ps as acc) p =
    if Set.mem p seen then acc else (Set.add p seen), (p :: ps)
  in
  List.rev (snd (List.fold_left add (Set.empty, []) ps))

let ctx p =                                      (* a context for the part. *)
  As_ctx.(add (`Part (`Name p.name)) @@
          add ((`Part p.kind) :> As_ctx.elt) @@
          add ((`Part p.usage) :> As_ctx.elt) @@
          empty)

let compute_actions p = (* gets actions from defining fun, adds ctx and args *)
  (* args contains values, we need to take their deps into account. *)
  let args = As_conf.manual_value (As_args.deps p.args) p.args in
  let ctx = ctx p in
  let actions exists args actions =
    if not exists then [] else
    let add acc a = As_action.add_ctx_args ctx args a :: acc in
    List.rev (List.fold_left add [] actions)
  in
  As_conf.(const actions $ p.exists $ args $ p.action_defs p)

let no_action = fun _ -> As_conf.const []

let v_kind ?(usage = `Outcome) ?(exists = As_conf.true_) ?(args = As_args.empty)
    ?(meta = meta_nil) ?(needs = []) ?root ?(actions = no_action)
    ?(check = fun _ -> As_conf.true_) name kind =
  (* Man it's coercion hell in there. *)
  let needs = list_uniquify (needs :> Set.elt list) in
  let root = match root with
  | None -> alloc_root (kind :> kind) (usage :> usage) name
  | Some r -> r
  in
  let rec part =
    { id = part_id (); kind = (kind :> kind);
      name; usage = usage; exists; args;
      meta; needs = (needs :> kind t list); root;
      action_defs = (actions :> kind t -> As_action.t list As_conf.value);
      actions = lazy (compute_actions (part :> kind t));
      check = (check :> kind t -> bool As_conf.value); }
  in
  part

let v ?usage ?exists ?args ?meta ?needs ?root ?actions ?check name =
  v_kind ?usage ?exists ?args ?meta ?needs ?root ?actions ?check name `Base

let id p = p.id
let kind p = p.kind
let name p = p.name
let usage p = p.usage
let exists p = p.exists
let args p = p.args
let meta p = p.meta
let needs p = p.needs
let root p = p.root
let root_path p = p.root
let actions p = Lazy.force (p.actions)
let check p = p.check (p :> kind t)

let get_meta proj p =  match proj p.meta with
| None -> assert false | Some m -> m

let deps p =
  (* Only p.actions' dependencies need to be consulted:
     - For [p.needs], [p.meta] and [p.root]'s deps. If they are
       really needed they will have propagated in the part's actions.
     - [p.exists] enters in the definition of p.actions (see [compute_actions]).
     - [p.args] deps were integrated into p.actions by the special handling
       peformed in [compute_actions]. *)
  As_conf.deps (actions p)

let equal p p' = p.id = p'.id
let compare = Part.compare

let redefine ?check ?actions old =
  let check = match check with None -> old.check | Some f -> f in
  let action_defs = match actions with None -> old.action_defs | Some f -> f in
  let rec newp =
    { old with
      action_defs; check;
      actions = lazy (compute_actions (newp :> kind t)); }
  in
  newp

(* File part *)

let file ?usage:usage ?exists p =
  let actions _ =
    As_conf.const ([As_action.v ~ctx:As_ctx.empty ~inputs:[p] ~outputs:[] []])
  in
  v ?usage ?exists ~actions (Path.filename p)

(* Part integration *)

let integrate ?(add_need = fun _ -> false) i p =
  let needs = List.(rev_append (rev (filter add_need (needs p))) (needs i)) in
  let usage = usage p in
  let root = root p in
  let rec newp =
    { i with usage; root; needs = (needs :> kind t list);
             actions = lazy (compute_actions (newp :> kind t)) }
  in
  newp

(* Coercing *)

let coerce (#kind as k) ({kind} as p) =
  if p.kind = k then p else invalid_arg (err_coerce p.kind k)

let coerce_if (#kind as k) ({kind} as p) =
  if p.kind = k then Some p else None

(* Part lists *)

let list_actions ps =
  let add_actions acc p =
    As_conf.(const List.rev_append $ (const List.rev $ actions p) $ acc)
  in
  List.fold_left add_actions (As_conf.const []) (List.rev ps)

let list_keep pred ps =
  let keep acc p = if pred p then p :: acc else acc in
  List.rev (List.fold_left keep [] ps)

let list_keep_map fn ps =
  let add acc p = match fn p with None -> acc | Some v -> v :: acc in
  List.rev (List.fold_left add [] ps)

let list_keep_kind kind ps = list_keep_map (coerce_if kind) ps
let list_keep_kinds kinds ps = list_keep (fun p -> List.mem (kind p) kinds) ps
let list_fold f acc ps = List.fold_left f acc ps
let list_fold_kind kind f acc ps =
  let f acc p = match coerce_if kind p with None -> acc | Some p -> f acc p in
  list_fold f acc ps

let list_fold_rec f acc ps =
  let rec loop (seen, r as acc) = function
  | (next :: todo) :: todo' ->
      if Set.mem next seen then loop acc (todo :: todo') else
      loop (Set.add next seen, f r next) ((needs next) :: todo :: todo')
  | [] :: [] -> r
  | [] :: todo -> loop acc todo
  | [] -> assert false
  in
  loop (Set.empty, acc) [ps]

let list_fold_kind_rec kind f acc ps =
  let f acc p = match coerce_if kind p with None -> acc | Some p -> f acc p in
  list_fold_rec f acc ps
