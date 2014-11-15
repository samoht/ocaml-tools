(*
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

(* Types *)

open As_acmd.Args

type includes = As_path.t list
type name = As_path.t

(* Global options

let debug_opt =
  let opt debug = add_if debug "-g" [] in
  As_conf.(const opt $ (value debug))

let compile_common =
  let opts warn_error ocaml_annot debug =
    adds_if warn_error [ "-warn-error"; "+a" ] @@
    add_if ocaml_annot "-bin_annot" @@
    debug
  in
  As_conf.(const opts $ (value warn_error) $ (value ocaml_annot) $ debug_opt)

let compile_with_incs incs rest =
  add compile_common @@ add (paths_args ~opt:"-I" incs) @@ rest

let mli_compiler = (* don't fail if ocamlc is not available *)
  let open As_conf in
  let comp = pick_if (value ocaml_native) (value ocamlopt) (value ocamlc) in
  key ~public:false "ocamlc-mli" string comp

let c_compiler = (* don't fail if ocamlc is not available *)
  let open As_conf in
  let comp = pick_if (value ocaml_native) (value ocamlopt) (value ocamlc) in
  key ~public:false "ocamlc-c" string comp

*)


(* Preprocess *)

let compile_src_ast ?(needs = []) ?(args = []) ~dumpast src_kind ~src () =
  let ctx = As_ctx.v [ `OCaml; `Pp; `Src (src_kind :> As_path.ext)] in
  let ext = match src_kind with `Ml -> `Ml_pp | `Mli -> `Mli_pp in
  let out = path src ~ext in
  let inputs = add src @@ needs  in
  let outputs = [out] in
  let args = adds args @@ path_arg src @@ path_arg ~opt:"-o" out @@ [] in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v dumpast args]

(* Compile *)

let compile_mli
    ?(needs = []) ?(args = []) ~ocamlc ~annot ~incs ~src () =
  let ctx = As_ctx.v [`OCaml; `Compile; `Src `Mli] in
  let inputs = add src @@ needs in
  let outputs = add_if annot (path src ~ext:`Cmti) @@ [path src ~ext:`Cmi] in
  let args =
    adds args @@ add_if annot "-bin-annot" @@
    adds [ "-c"; "-intf"] @@ path_arg src @@ path_args ~opt:"-I" incs @@ []
  in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlc args]

let compile_ml_byte
    ?(needs = []) ?(args = []) ~ocamlc ~annot ~has_mli ~incs ~src () =
  let ctx = As_ctx.v [`OCaml; `Compile; `Src `Ml; `Target `Byte] in
  let cmi = path src ~ext:`Cmi in
  let inputs = add src @@ add_if has_mli cmi @@ needs in
  let outputs =
    add_if (not has_mli) cmi @@
    add_if annot (path src ~ext:`Cmt) @@
    [path src ~ext:`Cmo]
  in
  let args =
    adds args @@ add_if annot "-bin-annot" @@
    adds ["-c"; "-impl"] @@ path_arg src @@ path_args ~opt:"-I" incs @@ []
  in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlc args]

let compile_ml_native
    ?(needs = []) ?(args = []) ~ocamlopt ~annot ~has_mli ~incs ~src () =
  let ctx = As_ctx.v [`OCaml; `Compile; `Src `Ml; `Target `Native] in
  let cmi = path src ~ext:`Cmi in
  let inputs = add src @@ add_if has_mli cmi @@ needs in
  let outputs =
    add_if (not has_mli) cmi @@
    add_if annot (path src ~ext:`Cmt) @@
    [path src ~ext:`Cmx]
  in
  let args =
    adds args @@ add_if annot "-bin-annot" @@
    adds ["-c"; "-impl"] @@ path_arg src @@ path_args ~opt:"-I" incs @@ []
  in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlopt args]

let compile_c
    ?(needs = []) ?(args = []) ~ocamlc ~src () =
  let ctx = As_ctx.v [`OCaml; `C; `Compile; `Src `C] in
  let inputs = add src @@ needs in
  let outputs = [path src ~ext:`O] in
  let args = adds args @@ add "-c" @@ path_arg src @@ [] in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlc args]

(* Archive *)

let archive_byte
    ?(needs = []) ?(args = []) ~ocamlc ~cmos ~name () =
  let ctx = As_ctx.v [`OCaml; `Archive `Static; `Target `Byte] in
  let cma = path name ~ext:`Cma in
  let inputs = adds cmos @@ needs in
  let outputs = [cma] in
  let args =
    adds args @@ adds ["-a"; "-o"] @@ path_arg cma @@
    path_args cmos @@ []
  in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlc args]

let archive_native
    ?(needs = []) ?(args = []) ~ocamlopt ~cmx_s ~name () =
  let ctx = As_ctx.v [`OCaml; `Archive `Static; `Target `Native] in
  let cmxa = path name ~ext:`Cmxa in
  let inputs = adds cmx_s @@ needs in
  let outputs = add (path name ~ext:`A) @@ [cmxa] in
  let args =
    adds args @@ adds ["-a"; "-o"] @@ path_arg cmxa @@
    path_args cmx_s @@ []
  in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlopt args]

let archive_shared
  ?(needs = []) ?(args = []) ~ocamlopt ~cmx_s ~name () =
  let ctx = As_ctx.v [`OCaml; `Archive `Shared; `Target `Native] in
  let cmxs = path name ~ext:`Cmxs in
  let inputs = adds cmx_s @@ needs in
  let outputs = [cmxs] in
  let args =
    adds args @@ adds ["-shared"; "-o"] @@ path_arg cmxs @@
    path_args cmx_s @@ []
  in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlopt args]

let archive_c
    ?(needs = []) ?(args = []) ~ocamlmklib ~objs ~name () =
  let ctx = As_ctx.v [`OCaml; `C; `Archive `Shared; `Target `Native] in
  let inputs = adds objs @@ needs in
  let outputs = add (path name ~ext:`A) @@ [path name ~ext:`So] in
  let args = adds args @@ add "-o" @@ path_arg name @@ path_args objs @@ [] in
  As_action.v ~ctx ~inputs ~outputs [As_acmd.v ocamlmklib args]
