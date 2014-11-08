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


type kind = [ `OCamldoc ]
type meta = { kind : kind }

let inj, proj = As_part.meta_key ()
let get_meta p = As_part.get_meta proj p
let meta ?(kind = `OCamldoc) () = inj { kind }
let kind p = (get_meta p).kind

  (* Create *)

let create ?cond ?(args = As_args.empty) ?keep ?kind name ps =
  let meta = meta ?kind () in
  let args _ = args in
  As_part.create ?cond ~args name `Doc meta

  let of_base ?kind p =
    let meta = meta ?kind () in
    { p with As_part.kind = `Doc; meta }

  (* Documentation filters *)

  let default _ = failwith "TODO"
  let dev _ = failwith "TODO"