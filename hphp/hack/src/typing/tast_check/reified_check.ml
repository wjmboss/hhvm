(**
 * Copyright (c) 2018, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the "hack" directory of this source tree.
 *
 *)

open Core_kernel
open Tast
open Typing_defs

let is_soft_reified tparam =
  List.exists tparam.tp_user_attributes ~f:(fun { Nast.ua_name = (_, n); _ } ->
    Naming_special_names.UserAttributes.uaSoft = n
  )

let tparams_has_reified tparams =
  List.exists ~f:(fun t -> t.tp_reified && not (is_soft_reified t)) tparams

let match_reified i (tparam, targ) =
  let { tp_reified; tp_name; _ } = tparam in
  let (targ_pos, _), targ_reified = targ in
  if (tp_reified && not (is_soft_reified tparam) && not targ_reified) then
    Errors.mismatched_reify tp_name targ_pos i

let verify_targs expr_pos decl_pos targs tparams =
  if tparams_has_reified tparams &&
     List.is_empty targs then
    Errors.require_args_reify decl_pos expr_pos;
  (* Unequal_lengths case handled elsewhere *)
  ignore Option.(
    List.zip tparams targs >>|
    List.iteri ~f:match_reified
  )

let handler = object
  inherit Tast_visitor.handler_base

  method! at_expr env x =
    (* only considering functions where one or more params are reified *)
    match x with
    | (pos, _), Call (_, ((_, (_, Tfun { ft_pos; ft_tparams; _ })), _), tal, _, _) ->
      let tparams = fst ft_tparams in
      verify_targs pos ft_pos tal tparams
    | (pos, _), New ((_, CI (_, class_id)), tal, _, _, _) ->
      begin match Tast_env.get_class env class_id with
      | Some cls ->
        let tparams = Typing_classes_heap.tparams cls in
        let class_pos = Typing_classes_heap.pos cls in
        verify_targs pos class_pos tal tparams
      | None -> () end
    | _ -> ()

  method! at_hint env = function
    | pos, Aast.Happly ((_, class_id), tal) ->
      begin match Tast_env.get_class env class_id with
      | Some tc ->
        let tparams = Typing_classes_heap.tparams tc in
        let tparams_length = List.length tparams in
        let targs_length = List.length tal in
        if tparams_length <> targs_length
        then begin
          if targs_length <> 0
          then Errors.type_arity pos class_id (string_of_int tparams_length)
          else if tparams_has_reified tparams then
            Errors.require_args_reify (Typing_classes_heap.pos tc) pos end
      | None -> ()
      end
    | _ ->
      ()

end
