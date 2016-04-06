(* Ocsigen
 * http://www.ocsigen.org
 * Copyright (C) 2007-2010 Vincent Balat
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

(* Manipulation of services - this code can be use on server or client side. *)

{shared{

open Eliom_lib
open Eliom_parameter

include Eliom_service_types

(** Typed services *)
type suff = [ `WithSuffix | `WithoutSuffix ]
(* TODO: replace poly variant like for other type parameters (involves
   Eliom_parameter) *)

type 'a reload_fun =
  | Rf_keep
  | Rf_some of
      (unit -> ('a -> unit -> unit Lwt.t) option)
        Eliom_client_value.t ref

type att = {
  prefix          : string;   (* name of the server and protocol for
                                 external links
                                 e.g., http://ocsigen.org *)
  subpath         : Url.path; (* name of the service without
                                 parameters *)
  fullpath        : Url.path; (* full path of the service =
                                 site_dir@subpath *)
  get_name        : Eliom_common.att_key_serv;
  post_name       : Eliom_common.att_key_serv;
  redirect_suffix : bool;
  priority        : int;
}

type non_att = {
  na_name            : Eliom_common.na_key_serv;
  keep_get_na_params : bool
  (* bool is used only for post and means "keep_get_na_params": do we
     keep GET non-attached parameters in links (if any) (31/12/2007 -
     experimental - WAS: 'a, but may be removed (was not used)) *)
}

type 'a attached_info =
  | Attached : att -> att attached_info
  | Nonattached : non_att -> non_att attached_info

type send_appl_content =
  | XNever
  | XAlways
  | XSame_appl of string * string option
  (* the string is the name of the application to which the service
     belongs and the option is the name of template *)
(** Whether the service is capable to send application content or not.
    (application content has type Eliom_service.eliom_appl_answer:
    content of the application container, or xhr redirection ...).  A
    link towards a service with send_appl_content = XNever will always
    answer a regular http frame (this will stop the application if
    used in a regular link or form, but not with XHR).  XAlways means
    "for all applications" (like redirections/actions).  XSame_appl
    means "only for this application".  If there is a client side
    application, and the service has XAlways or XSame_appl when it is
    the same application, then the link (or form or change_page) will
    expect application content. *)

type service_kind =
  [ `Service
  | `AttachedCoservice
  | `NonattachedCoservice
  | `External ]

(* 'return is the value returned by the service *)
type ('get, 'post, 'meth, 'attached, 'co, 'ext, 'reg,
      +'tipo, 'getnames, 'postnames, +'rt) service = {
  pre_applied_parameters:
    (string * Eliommod_parameters.param) list String.Table.t
    (* non localized parameters *) *
    (string * Eliommod_parameters.param) list (* regular parameters *);
  get_params_type:
    ('get, 'tipo, 'getnames) Eliom_parameter.params_type;
  post_params_type:
    ('post, [`WithoutSuffix], 'postnames) Eliom_parameter.params_type;
  max_use: int option;   (* Max number of use of this service *)
  timeout: float option; (* Timeout for this service (the service will
                            disappear if it has not been used during
                            this amount of seconds) *)
  meth: 'meth which_meth;
  kind: service_kind;
  info: 'attached attached_info;

  https: bool; (* force https *)
  keep_nl_params: [ `All | `Persistent | `None ];
  mutable send_appl_content : send_appl_content;
  (* XNever when we create the service, then changed at registration
     :/ *)

  (* If the service has a client-side implementation, we put the
     generating function here: *)
  client_fun:
    (unit -> ('get -> 'post -> unit Lwt.t) option)
      Eliom_client_value.t ref;

  reload_fun: 'get reload_fun;

  service_mark :
    (unit, unit, 'meth,
     'attached, 'co, 'ext, 'reg,
     suff, unit, unit, unit)
      service Eliom_common.wrapper;
}
  constraint 'tipo = [< suff ]

let pre_wrap s = {
  s with
  get_params_type = Eliom_parameter.wrap_param_type s.get_params_type;
  post_params_type = Eliom_parameter.wrap_param_type s.post_params_type;
  service_mark = Eliom_common.empty_wrapper ();
}

let service_mark () = Eliom_common.make_wrapper pre_wrap

let get_info {info} = info

let get_pre_applied_parameters_ s = s.pre_applied_parameters
let get_get_params_type_ s = s.get_params_type
let get_post_params_type_ s = s.post_params_type
let get_prefix_ s = s.prefix
let get_sub_path_ s = s.subpath
let get_redirect_suffix_ s = s.redirect_suffix
let get_full_path_ s = s.fullpath
let get_get_name_ s = s.get_name
let get_post_name_ s = s.post_name
let get_na_name_ s = s.na_name
let get_na_keep_get_na_params_ s = s.keep_get_na_params
let get_max_use_ s = s.max_use
let get_timeout_ s = s.timeout
let get_https s = s.https
let get_priority_ s = s.priority
let get_client_fun_ s = !(s.client_fun)
let has_client_fun_lazy s =
  let f = get_client_fun_ s in
  {unit -> bool{
     fun () ->
       match %f () with
       | Some _ ->
         true
       | None ->
         false
   }}

let internal_set_client_fun_ ~service:s f = s.client_fun := f
let set_client_fun_ ?app ~service:s f =
  Eliom_lib.Option.iter
    (fun app_name -> s.send_appl_content <- XSame_appl (app_name, None))
    app;
  s.client_fun := {{ fun () -> Some %f }}

let is_external = function
  | {kind=`External} -> true
  | _ -> false

let default_priority = 0

let which_meth {meth} = meth

let change_get_num service attser n = {
  service with
  service_mark = service_mark ();
  info = Attached {attser with get_name = n}
}

(** Static directories **)
let static_dir_ ?(https = false) () =
  let client_fun = ref {_ -> _{ fun () -> None}} in {
    pre_applied_parameters = String.Table.empty, [];
    get_params_type = Eliom_parameter.suffix
        (Eliom_parameter.all_suffix Eliom_common.eliom_suffix_name);
    post_params_type = Eliom_parameter.unit;
    max_use= None;
    timeout= None;
    kind = `Service;
    meth = Get';
    info = Attached {
      prefix = "";
      subpath = [""];
      fullpath = (Eliom_request_info.get_site_dir ()) @
                 [Eliom_common.eliom_suffix_internal_name];
      get_name = Eliom_common.SAtt_no;
      post_name = Eliom_common.SAtt_no;
      redirect_suffix = true;
      priority = default_priority;
    };
    https = https;
    keep_nl_params = `None;
    service_mark = service_mark ();
    send_appl_content = XNever;
    client_fun;
    reload_fun = Rf_some client_fun;
  }

let static_dir () = static_dir_ ()

let https_static_dir () = static_dir_ ~https:true ()

let get_static_dir_ ?(https = false)
    ?(keep_nl_params = `None) ~get_params () =
  let client_fun = ref {_ -> _{ fun () -> None}} in {
    pre_applied_parameters = String.Table.empty, [];
    get_params_type =
      Eliom_parameter.suffix_prod
        (Eliom_parameter.all_suffix Eliom_common.eliom_suffix_name)
        get_params;
    post_params_type = Eliom_parameter.unit;
    max_use= None;
    timeout= None;
    kind = `Service;
    meth = Get';
    info = Attached {
      prefix = "";
      subpath = [""];
      fullpath = (Eliom_request_info.get_site_dir ()) @
                 [Eliom_common.eliom_suffix_internal_name];
      get_name = Eliom_common.SAtt_no;
      post_name = Eliom_common.SAtt_no;
      redirect_suffix = true;
      priority = default_priority;
    };
    https = https;
    keep_nl_params = keep_nl_params;
    service_mark = service_mark ();
    send_appl_content = XNever;
    client_fun;
    reload_fun = Rf_some client_fun;
  }

let static_dir_with_params ?keep_nl_params ~get_params () =
  get_static_dir_ ?keep_nl_params ~get_params ()

let https_static_dir_with_params ?keep_nl_params ~get_params () =
  get_static_dir_ ~https:true ?keep_nl_params ~get_params ()


(****************************************************************************)
let get_send_appl_content s = s.send_appl_content
let set_send_appl_content s n = s.send_appl_content <- n

(****************************************************************************)

type clvpreapp = {
  mutable clvpreapp_f :
    'a 'b.
         (('a -> 'b -> [ `Html ] Eliom_content_core.Html5.elt Lwt.t)
            Eliom_client_value.t ->
          'a ->
          (unit -> 'b -> [ `Html ] Eliom_content_core.Html5.elt Lwt.t)
            Eliom_client_value.t)
}

let preapply_client_fun = {
  clvpreapp_f = fun f getparams -> failwith "preapply_client_fun"
}
(* will be initialized later (in Eliom_content for now), when client
   syntax is available, with: fun f getparams -> {{ fun _ pp -> %f
   %getparams pp }} *)

let rec append_suffix l m =
  match l with
  | [] ->
    m
  | [eliom_suffix_internal_name] ->
    m
  | a :: ll ->
    a :: append_suffix ll m

let preapply ~service getparams =
  let nlp, preapp = service.pre_applied_parameters in
  let suff, nlp, params =
    Eliom_parameter.construct_params_list_raw
      nlp service.get_params_type getparams
  in {
    service with
    service_mark = service_mark ();
    pre_applied_parameters = nlp, params @ preapp;
    get_params_type = Eliom_parameter.unit;
    info =
      (match service.info with
       | Attached k ->
         Attached
           {k with
            subpath =
              (match suff with
               | Some suff -> append_suffix k.subpath suff
               | _ -> k.subpath);
            fullpath =
              (match suff with
               | Some suff -> append_suffix k.fullpath suff
               | _ -> k.fullpath);
           };
       | k -> k);
    client_fun =
      ref {{ fun () ->
        match (! %(service.client_fun)) () with
        | None -> None
        | Some f -> Some (fun _ pp -> f %getparams pp)
      }};
    reload_fun =
      match service.reload_fun with
      | Rf_keep -> Rf_keep
      | Rf_some fr ->
        Rf_some (ref {{ fun () ->
          match ! %fr () with
          | None -> None
          | Some f -> Some (fun _ pp -> f %getparams pp) }})
  }


let void_coservice'_aux https =
  let client_fun = ref {_ -> _{ fun () -> None }} in {
    max_use = None;
    timeout = None;
    pre_applied_parameters = String.Table.empty, [];
    get_params_type = Eliom_parameter.unit;
    post_params_type = Eliom_parameter.unit;
    kind = `NonattachedCoservice;
    meth = Get';
    info = Nonattached {
      na_name = Eliom_common.SNa_void_dontkeep;
      keep_get_na_params= true;
    };
    https = false;
    keep_nl_params = `All;
    service_mark = service_mark ();
    send_appl_content = XAlways;
    client_fun;
    reload_fun = Rf_some client_fun;
  }

let void_coservice' = void_coservice'_aux false

let https_void_coservice' = void_coservice'_aux true

let void_hidden_coservice'_aux https = {
  void_coservice' with
  kind = `NonattachedCoservice;
  meth = Get';
  info = Nonattached {
    na_name = Eliom_common.SNa_void_keep;
    keep_get_na_params=true;
  };
}

let void_hidden_coservice' = void_hidden_coservice'_aux false

let https_void_hidden_coservice' = void_hidden_coservice'_aux true

(*VVV Non localized parameters not implemented for client side services *)
let add_non_localized_get_parameters ~params ~service = {
  service with
  get_params_type =
    Eliom_parameter.nl_prod service.get_params_type params;
  client_fun =
    (let r = service.client_fun in
     ref {{ fun () ->
       match (! %r) () with
       | None -> None
       | Some f -> Some (fun (g, _) p -> f g p) }});
  reload_fun =
    match service.reload_fun with
    | Rf_keep -> Rf_keep
    | Rf_some fr ->
      Rf_some (ref {{ fun () ->
        match (! %fr) () with
        | None -> None
        | Some f -> Some (fun (g, _) p -> f g p) }})
}

let add_non_localized_post_parameters ~params ~service = {
  service with
  post_params_type =
    Eliom_parameter.nl_prod service.post_params_type params;
  client_fun = ref {{ fun () ->
    match (! %(service.client_fun)) () with
    | None -> None
    | Some f -> Some (fun g (p, _) -> f g p) }}
}

let keep_nl_params s = s.keep_nl_params

let register_delayed_get_or_na_coservice ~sp s =
  failwith "CSRF coservice not implemented client side for now"

let register_delayed_post_coservice  ~sp s getname =
  failwith "CSRF coservice not implemented client side for now"

(* external services *)
(** Create a main service (not a coservice) internal or external, get
    only *)
let service_aux_aux
    ~https
    ~prefix
    ~(path : Url.path)
    ~site_dir
    ~kind
    ~meth
    ?(redirect_suffix = true)
    ?(keep_nl_params = `None)
    ?(priority = default_priority)
    ~get_params
    (type pp) ~(post_params : (pp, _, _) Eliom_parameter.params_type)
    ~(cf : (unit -> (_ -> pp -> unit Lwt.t) option)
          Eliom_client_value.t ref)
    ~rf
    () = {
  pre_applied_parameters = String.Table.empty, [];
  get_params_type = get_params;
  post_params_type = post_params;
  max_use= None;
  timeout= None;
  meth;
  kind = kind;
  info = Attached {
    prefix = prefix;
    subpath = path;
    fullpath = site_dir @ path;
    get_name = Eliom_common.SAtt_no;
    post_name = Eliom_common.SAtt_no;
    redirect_suffix;
    priority;
  };
  https = https;
  keep_nl_params = keep_nl_params;
  service_mark = service_mark ();
  send_appl_content = XNever;
  client_fun = cf;
  reload_fun = rf;
}

let external_service_aux
    (type gp) (type pp)
    ~prefix
    ~path
    ?keep_nl_params
    ~rt
    ~(get_params : (gp, _, _) Eliom_parameter.params_type)
    ~(post_params : (pp, _, _) Eliom_parameter.params_type)
    meth =
  ignore rt;
  let suffix = Eliom_parameter.contains_suffix get_params in
  service_aux_aux
    ~https:false (* not used for external links *)
    ~prefix
    ~path:
      (Url.remove_internal_slash
         (match suffix with
          | None -> path
          | _ -> path @ [Eliom_common.eliom_suffix_internal_name]))
    ~site_dir:[]
    ~kind:`External
    ~meth
    ?keep_nl_params
    ~redirect_suffix:false
    ~get_params
    ~post_params
    ~cf:(Obj.magic (ref {_ -> _{ fun () -> None }}))
    ~rf:Rf_keep
    ()

let external_service
    (type gp) (type pp)
    ~prefix
    ~path
    ?keep_nl_params
    ~rt
    (type m) (type gp) (type gn) (type pp) (type pn) (type mf)
    (type gp')
    ~(meth : (m, gp, gn, pp, pn, _, mf, gp') meth)
    ()
  : (gp, pp, m, _, _, _, _, _, gn, pn, _) service =
  match meth with
  | Get get_params ->
    external_service_aux
      ~prefix ~path ?keep_nl_params ~rt
      ~get_params ~post_params:Eliom_parameter.unit
      Get'
  | Post (get_params, post_params) ->
    external_service_aux
      ~prefix ~path ?keep_nl_params ~rt
      ~get_params ~post_params
      Post'
  | Put get_params ->
    external_service_aux
      ~prefix ~path ?keep_nl_params ~rt
      ~get_params ~post_params:Eliom_parameter.unit
      Put'
  | Delete get_params ->
    external_service_aux
      ~prefix ~path ?keep_nl_params ~rt
      ~get_params ~post_params:Eliom_parameter.unit
      Delete'

let untype_service_ s =
  (s
   : ('get, 'post, 'meth, 'attached, 'co, 'ext,
      'tipo, 'getnames, 'postnames, 'register, _) service
   :> ('get, 'post, 'meth, 'attached, 'co, 'ext,
       'tipo, 'getnames, 'postnames,'register, _) service)

let eliom_appl_answer_content_type = "application/x-eliom"

let uniqueid =
  let r = ref (-1) in
  fun () -> r := !r + 1; !r

let new_state () =
  (* FIX: we should directly produce a string of the right length *)
  (* 72bit of entropy is large enough: CSRF-safe services are
     short-lived; with 65536 services, the probability of a collision
     is about 2^-41.  *)
  make_cryptographic_safe_string ~len:12 ()

let default_csrf_scope = function
  (* We do not use the classical syntax for default
     value. Otherwise, the type for csrf_scope was:
     [< Eliom_common.user_scope > `Session] *)
  | None -> `Session Eliom_common_base.Default_ref_hier
  | Some c -> (c :> [Eliom_common.user_scope])

exception Unreachable_exn

let get_attached_info = function
  | {info = Attached k} ->
    k
  | _ ->
    failwith "get_attached_info"

let get_non_attached_info = function
  | {info = Nonattached k} ->
    k
  | _ ->
    failwith "get_non_attached_info"

let coservice'
    ?name
    ?(csrf_safe = false)
    ?csrf_scope
    ?csrf_secure
    ?max_use
    ?timeout
    ?(https = false)
    ?(keep_nl_params = `Persistent)
    ~rt
    ~get_params
    () =
  ignore rt;
  let csrf_scope = default_csrf_scope csrf_scope in
  (* (match Eliom_common.global_register_allowed () with
     | Some _ -> Eliom_common.add_unregistered_na n;
     | _ -> () (* Do we accept unregistered non-attached coservices? *)); *)
  (* (* Do we accept unregistered non-attached named coservices? *)
     match sp with
     | None ->
     ...
  *)
  let client_fun = ref {_ -> _{ fun () -> None }} in {
    (*VVV allow timeout and max_use for named coservices? *)
    max_use= max_use;
    timeout= timeout;
    pre_applied_parameters = String.Table.empty, [];
    get_params_type =
      add_pref_params Eliom_common.na_co_param_prefix get_params;
    post_params_type = unit;
    kind = `NonattachedCoservice;
    meth = Get';
    info = Nonattached
        {na_name =
           (if csrf_safe
            then Eliom_common.SNa_get_csrf_safe (uniqueid (),
                                                 (csrf_scope:>Eliom_common.user_scope),
                                                 csrf_secure)
            else
              match name with
              | None -> Eliom_common.SNa_get' (new_state ())
              | Some name -> Eliom_common.SNa_get_ name);
         keep_get_na_params= true
        };
    https = https;
    keep_nl_params = keep_nl_params;
    send_appl_content = XNever;
    service_mark = service_mark ();
    client_fun;
    reload_fun = Rf_some client_fun
  }


let attach_coservice' :
  fallback:
  (unit, unit, get, att, _, non_ext, 'rg1,
   [< suff ], unit, unit, 'return1) service ->
  service:
  ('get, 'post, 'gp, non_att, co, non_ext, 'rg2,
   [< `WithoutSuffix] as 'sf, 'gn, 'pn, 'return) service ->
  ('get, 'post, 'gp, att, co, non_ext, non_reg,
   'sf, 'gn, 'pn, 'return) service =
  fun ~fallback ~service ->
    let {na_name} = get_non_attached_info service in
    let fallbackkind = get_attached_info fallback in
    let open Eliom_common in
    {
      pre_applied_parameters = service.pre_applied_parameters;
      get_params_type = service.get_params_type;
      post_params_type = service.post_params_type;
      https = service.https;
      keep_nl_params = service.keep_nl_params;
      service_mark = service_mark ();
      send_appl_content = service.send_appl_content;
      max_use = service.max_use;
      timeout = service.timeout;
      client_fun = service.client_fun;
      reload_fun = service.reload_fun;
      kind = `AttachedCoservice;
      meth = service.meth;
      info = Attached {
        prefix = fallbackkind.prefix;
        subpath = fallbackkind.subpath;
        fullpath = fallbackkind.fullpath;
        priority = fallbackkind.priority;
        redirect_suffix = fallbackkind.redirect_suffix;
        get_name = (match na_name with
          | SNa_get_ s -> SAtt_na_named s
          | SNa_get' s -> SAtt_na_anon s
          | SNa_get_csrf_safe a -> SAtt_na_csrf_safe a
          | SNa_post_ s -> fallbackkind.get_name (*VVV check *)
          | SNa_post' s -> fallbackkind.get_name (*VVV check *)
          | SNa_post_csrf_safe a -> fallbackkind.get_name (*VVV check *)
          | _ -> failwith "attach_coservice' non implemented for this kind of non-attached coservice. Please send us an email if you need this.");
        (*VVV Do we want to make possible to attach POST na coservices
          on GET attached coservices? *)
        post_name = (match na_name with
          | SNa_get_ s -> SAtt_no
          | SNa_get' s -> SAtt_no
          | SNa_get_csrf_safe a -> SAtt_no
          | SNa_post_ s -> SAtt_na_named s
          | SNa_post' s -> SAtt_na_anon s
          | SNa_post_csrf_safe a -> SAtt_na_csrf_safe a
          | _ -> failwith "attach_coservice' non implemented for this kind of non-attached coservice. Please send us an email if you need this.");
      };
    }

let service_aux
    ?(https = false)
    ~path
    ?keep_nl_params
    ?priority
    ~rt
    ~get_params
    (type pp) ~(post_params : (pp, _, _) Eliom_parameter.params_type)
    meth =
  ignore rt;
  let path =
    Url.remove_internal_slash
      (Url.change_empty_list
         (Url.remove_slash_at_beginning path))
  in
  let site_dir =
    match Eliom_common.get_sp_option () with
    | Some sp ->
      Eliom_request_info.get_site_dir_sp sp
    | None ->
      (match Eliom_common.global_register_allowed () with
       | Some get_current_site_data ->
         let sitedata = get_current_site_data () in
         Eliom_common.add_unregistered sitedata path;
         Eliom_common.get_site_dir sitedata
       | None ->
         raise (Eliom_common.Eliom_site_information_not_available
                  "service"))
  and redirect_suffix = contains_suffix get_params in
  let cf = Obj.magic (ref {_ -> _{ fun () -> None }}) in
  let rf = (Rf_some cf) in
  service_aux_aux
    ~https
    ~prefix:""
    ~path
    ~site_dir
    ~kind:`Service
    ~meth
    ?redirect_suffix
    ?keep_nl_params
    ?priority
    ~get_params
    ~post_params
    ~cf
    ~rf
    ()

let service :
  type m gp gn pp pn mf pg_ .
  ?https:bool ->
  ?keep_nl_params:[ `All | `Persistent | `None ] ->
  ?priority:int ->
  path:Eliom_lib.Url.path ->
  rt:('rt, _) rt ->
  meth:
  (m, gp, gn, pp, pn, [< `WithSuffix | `WithoutSuffix],
   mf, pg_) meth ->
  unit ->
  (gp, pp, m, att, non_co, non_ext, reg, 'tipo, gn, pn, 'rt)
    service =
  fun
    ?https
    ?keep_nl_params
    ?priority
    ~path
    ~rt
    ~meth
    () ->
    match meth with
    | Get get_params ->
      service_aux
        ?https ~path ?keep_nl_params ?priority ~rt
        ~get_params ~post_params:Eliom_parameter.unit
        Get'
    | Post (get_params, post_params) ->
      service_aux
        ?https ~path ?keep_nl_params ?priority ~rt
        ~get_params ~post_params
        Post'
    | Put get_params ->
      service_aux
        ?https ~path ?keep_nl_params ?priority ~rt
        ~get_params ~post_params:Eliom_parameter.unit
        Put'
    | Delete get_params ->
      service_aux
        ?https ~path ?keep_nl_params ?priority ~rt
        ~get_params ~post_params:Eliom_parameter.unit
        Delete'

let coservice_aux
    ?name
    ?(csrf_safe = false)
    ?csrf_scope
    ?csrf_secure
    ?max_use
    ?timeout
    ?(https = false)
    ~rt
    (type gp) (type gp') (type pp)
    ~(fallback : (gp', _, _, _, _, _, _, _, _, _, _) service)
    ?keep_nl_params
    ~(get_params : (gp, _, _) Eliom_parameter.params_type)
    ~(post_params : (pp, _, _) Eliom_parameter.params_type)
    meth
  : (gp, pp, _, _, _, _, _, _, _, _, _) service =
  ignore rt;
  let csrf_scope = default_csrf_scope csrf_scope in
  let k = get_attached_info fallback
  and client_fun = Obj.magic (ref {_ -> _{ fun () -> None }}) in {
    pre_applied_parameters = fallback.pre_applied_parameters;
    post_params_type = post_params;
    send_appl_content = fallback.send_appl_content;
    service_mark = service_mark ();
    max_use= max_use;
    timeout= timeout;
    get_params_type =
      add_pref_params Eliom_common.co_param_prefix get_params;
    meth;
    kind = `AttachedCoservice;
    info = Attached {
      k with
      get_name =
        if csrf_safe then
          Eliom_common.SAtt_csrf_safe
            (uniqueid (),
             (csrf_scope :> Eliom_common.user_scope),
             csrf_secure)
        else
          match name with
          | None -> Eliom_common.SAtt_anon (new_state ())
          | Some name -> Eliom_common.SAtt_named name
    };
    https = https || fallback.https;
    keep_nl_params =
      (match keep_nl_params with
       | None -> fallback.keep_nl_params
       | Some k -> k);
    client_fun;
    reload_fun = Rf_some client_fun
  }

let coservice
    ?name
    ?csrf_safe
    ?csrf_scope
    ?csrf_secure
    ?max_use
    ?timeout
    ?https
    ?keep_nl_params
    ?priority
    ~rt
    (type m)  (type gp)  (type gn)  (type pp) (type pn) (type mf)
    ~(meth : (m, gp, gn, pp, pn, _, mf, unit) meth)
    ~(fallback :
        (unit, unit, mf, _, _, _, _, _, unit, unit, _) service)
    ()
  : (gp, pp, m, _, _, _, _, _, gn, pn, _) service =
  match meth with
  | Get get_params ->
    coservice_aux
      ?name ?csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout ?https
      ~rt ~fallback ?keep_nl_params
      ~get_params ~post_params:Eliom_parameter.unit
      Get'
  | Post (get_params, post_params) ->
    coservice_aux
      ?name ?csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout ?https
      ~rt ~fallback ?keep_nl_params
      ~get_params ~post_params
      Post'
  | Put get_params ->
    coservice_aux
      ?name ?csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout ?https
      ~rt ~fallback ?keep_nl_params ~get_params ~post_params:unit
      Put'
  | Delete get_params ->
    coservice_aux
      ?name ?csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout ?https
      ~rt ~fallback ?keep_nl_params
      ~get_params ~post_params:Eliom_parameter.unit
      Delete'

(* Warning: here no GET parameters for the fallback.
   Preapply services if you want fallbacks with GET parameters *)

let coservice'_aux
    ?name
    ?(csrf_safe = false)
    ?csrf_scope
    ?csrf_secure
    ?max_use
    ?timeout
    ?(https = false)
    ?(keep_nl_params = `Persistent)
    (type gp) (type gn)
    ~(get_params : (gp, _, gn) Eliom_parameter.params_type)
    (type pp) (type pn)
    ~(post_params : (pp, _, pn) Eliom_parameter.params_type)
    (type m) (meth : m which_meth)
  : (gp, pp, m, _, _, _, _, _, gn, pn, _) service =
  let csrf_scope = default_csrf_scope csrf_scope
  and is_post = match meth with Post' -> true | _ -> false
  and client_fun = Obj.magic (ref {_ -> _{ fun () -> None}}) in {
    max_use;
    timeout;
    pre_applied_parameters = String.Table.empty, [];
    get_params_type =
      add_pref_params Eliom_common.na_co_param_prefix get_params;
    post_params_type = post_params;
    meth;
    kind = `NonattachedCoservice;
    info = Nonattached {
      na_name =
        (if csrf_safe then
           if is_post then
             Eliom_common.SNa_post_csrf_safe
               (uniqueid (),
                (csrf_scope :> Eliom_common.user_scope),
                csrf_secure)
           else
             Eliom_common.SNa_get_csrf_safe
               (uniqueid (),
                (csrf_scope :> Eliom_common.user_scope),
                csrf_secure)
         else
           match name, is_post with
           | None      , true  -> Eliom_common.SNa_post' (new_state ())
           | None      , false -> Eliom_common.SNa_get' (new_state ())
           | Some name , true  -> Eliom_common.SNa_post_ name
           | Some name , false -> Eliom_common.SNa_get_ name);
      keep_get_na_params = true
    };
    https;
    keep_nl_params;
    send_appl_content = XNever;
    service_mark = service_mark ();
    client_fun;
    reload_fun = Rf_some client_fun
  }

let coservice'
    ?name
    ?(csrf_safe = false)
    ?csrf_scope
    ?csrf_secure
    ?max_use
    ?timeout
    ?(https = false)
    ?(keep_nl_params = `Persistent)
    ~rt
    (type m)  (type gp)  (type gn)  (type pp) (type pn) (type mf)
    ~(meth : (m, gp, gn, pp, pn, _, mf, unit) meth)
    ()
  : (gp, pp, m, _, _, _, _, _, gn, pn, _) service =
  ignore rt;
  match meth with
  | Get get_params ->
    coservice'_aux
      ?name ~csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout
      ~https ~keep_nl_params
      ~get_params ~post_params:Eliom_parameter.unit
      Get'
  | Post (get_params, post_params) ->
    coservice'_aux
      ?name ~csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout
      ~https ~keep_nl_params
      ~get_params ~post_params
      Post'
  | Put get_params ->
    coservice'_aux
      ?name ~csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout
      ~https ~keep_nl_params
      ~get_params ~post_params:Eliom_parameter.unit
      Put'
  | Delete get_params ->
    coservice'_aux
      ?name ~csrf_safe ?csrf_scope ?csrf_secure ?max_use ?timeout
      ~https ~keep_nl_params
      ~get_params ~post_params:Eliom_parameter.unit
      Delete'

}}
