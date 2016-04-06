(* Ocsigen
 * http://www.ocsigen.org
 * Module eliom_service.mli
 * Copyright (C) 2007 Vincent Balat
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)


(** Creation and manipulation of Eliom services. *)

(** See the Eliom manual for a detailed introduction to the concept of
    {% <<a_manual chapter="server-services"|Eliom services>>%}. *)

(** The main functions to create services are in {% <<a_api
    subproject="server"|module Eliom_service>>%}. *)

open Eliom_lib
open Eliom_parameter

include Eliom_service_sigs.S

(** {2 Static loading of Eliom modules} *)

(** This functionality allows one to register initialization functions
    for Eliom modules which will be executed when the corresponding
    module is loaded in [ocsigenserver.conf].  If the module is loaded
    dynamically, you probably don't need this.  But if the module is
    linked statically, some computations, like service registrations
    must be delayed. *)

(** The function [register_eliom_module mod f] is used to register the
    initialization function [f] to be executed when then module [mod]
    is loaded by Ocsigen server. The module [mod] could either be a
    dynamically loaded module or linked statically into the server: in
    each case, the [f] function will be invoked when the module is
    initialized in the configuration file using [<eliommodule ...>
    ... </eliommodule>]. If [register_eliom_module] is called twice
    with the same module name, the second initialization function will
    replace the previous one. *)
val register_eliom_module : string -> (unit -> unit) -> unit

(** The function [unregister service] unregister the service handler
    previously associated to [service] with
    {!Eliom_registration.Html5.register},
    {!Eliom_registration.App.register} or any other
    {!Eliom_registration}[.*.register] functions. See the
    documentation of those functions for a description of the [~scope]
    and [~secure] optional parameters. *)
val unregister :
  ?scope:[< Eliom_common.scope ] ->
  ?secure:bool ->
  ('a, 'b, _, _, _, non_ext,
   'e, 'f, 'g, 'h, 'return) service -> unit

(** Returns whether it is an external service or not. *)
val is_external :
  (_, _, _, _, _, _, _, _, _, _, _) service -> bool
(**/**)

val get_or_post_ :
  (_, _, _, _, _, _, _, _, _, _, _) service ->
  Ocsigen_http_frame.Http_header.http_method

val get_pre_applied_parameters_ :
  (_, _, _, _, _, _, _, _, _, _, _) service ->
  (string * string) list String.Table.t *
  (string * string) list

val new_state : unit -> string

val untype_service_ :
  ('a, 'b, 'meth, 'attached, 'co, 'ext, 'd, 'e, 'f, 'g, 'rr) service ->
  ('a, 'b, 'meth, 'attached, 'co, 'ext, 'd, 'e, 'f, 'g, 'return) service

(*****************************************************************************)

val set_delayed_get_or_na_registration_function :
  Eliom_common.tables ->
  int ->
  (sp:Eliom_common.server_params -> string) -> unit

val set_delayed_post_registration_function :
  Eliom_common.tables ->
  int ->
  (sp:Eliom_common.server_params -> Eliom_common.att_key_serv -> string) ->
  unit

val set_send_appl_content :
  (_, _, _, _, _, _, _, _, _, _, _) service ->
  send_appl_content -> unit

val pre_wrap :
  ('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i, 'j, 'k) service ->
  ('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i, 'j, 'k) service

exception Wrong_session_table_for_CSRF_safe_coservice

val eliom_appl_answer_content_type : string
