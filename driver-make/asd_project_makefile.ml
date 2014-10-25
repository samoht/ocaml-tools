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

(* FIXME: make that tail-recursive *)

open Asd_makefile.Op
open Assemblage

let str = Printf.sprintf

let ocaml_pp dumpast =
  if not dumpast then None else
  begin
    Cmd.on_error ~use:None @@
    Cmd.(exists "ocaml-dumpast" >>= function
      | true -> ret (Some "$(DUMPAST) camlp4o")
      | false -> error "ocaml-dumpast is not installed")
  end

let env dumpast =
  let ocamlfind_pkgs = Asd_ocamlfind.pkgs_args ~mode:(`Dynamic `Makefile) in
  let pkg_config = Asd_pkg_config.pkgs_args ~mode:(`Dynamic `Makefile) in
  Env.create
    ~ocamlc:"$(OCAMLC)"
    ~ocamlopt:"$(OCAMLOPT)"
    ~ocamldep:"$(OCAMLDEP)"
    ~ocamlmklib:"$(OCAMLMKLIB)"
    ~ocamldoc:"$(OCAMLDOC)"
    ~ocaml_pp:(ocaml_pp dumpast)
    ~js_of_ocaml:"$(JS_OF_OCAML)"
    ~ln:"$(LN)"
    ~mkdir:"$(MKDIR)"
    ~build_dir:(Path.dir "$(B)")
    ~root_dir:(Path.dir "$(R)")
    ~ocamlfind_pkgs
    ~pkg_config
    ()

let header version p =
  let name = Project.name p in
  [ `Comment (str "%s %s" name version);
    `Comment "Generated by assemblage %%VERSION%%.";
    `Comment "Run `make help` to get the list of targets.";
    `Blank; ]

let dirs build_dir =
  [ "B" =?= [build_dir];
    "R" =?= [ "$(shell pwd)" ];
    `Blank; ]

let tools () =
  [ "OCAMLOPT" =?= ["ocamlopt"];
    "OCAMLC" =?= ["ocamlc"];
    "OCAMLDEP" =?= ["ocamldep"];
    "OCAMLMKLIB" =?= ["ocamlmklib"];
    "DUMPAST" =?= ["ocaml-dumpast"];
    "OCAMLDOC" =?= ["ocamldoc"];
    "JS_OF_OCAML" =?= ["js_of_ocaml"];
    "LN" =?= ["ln -sf"];
    "MKDIR" =?= ["mkdir -p"];
    `Blank ]

let mk_args ctx args =
  (* TODO need to number the vars this can happen per command *)
  (* TODO vars can happen per args *)
  let name = Context.to_string ctx in
  let var = name =:= List.flatten (List.map snd (Args.get ctx args)) in
  let args = [ str "$(%s)" name ] in
  var, args

let mk_cmd ctx (vars, cmds) (args, cmd) =
  let var, args = mk_args ctx args in
  (var :: vars, (cmd args) :: cmds)

let mk_product = function
| `Effect (name, _), _ -> name
| `File f, _ -> Path.to_string f

let mk_rule r =
  let ctx = Rule.context r in
  let targets = List.map mk_product (Rule.outputs r) in
  let prereqs = List.map mk_product (Rule.inputs r) in
  let vars, recipe = List.fold_left (mk_cmd ctx) ([], []) (Rule.action r) in
  let recipe = List.rev recipe in
  List.rev_append vars [Asd_makefile.rule ~targets ~prereqs ~recipe ()]

let mk_part env p = match Part.rules env p with
| [] -> []
| rules ->
    let name = Part.name p in
    let kind = Part.kind p in
    [ `Comment (str "%s-%s rules" (Part.kind_to_string kind) name);
      `Blank; ] @
    List.concat (List.rev_map mk_rule rules)

let of_project ?(buildir = "_build") ?(makefile = "Makefile")
    ?(clean_files = []) ~version p =
  let env = env false in
  header version p @ dirs buildir @ tools () @
  List.(concat (map (mk_part env) (Project.parts p)))
