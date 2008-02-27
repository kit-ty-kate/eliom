(* Ocsigen
 * http://www.ocsigen.org
 * Module parseconfig.ml
 * Copyright (C) 2005 Vincent Balat, Nataliya Guts
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

(** Config file parsing *)

val parse_size : string -> int64 option
val parse_string : Simplexmlparser.xml list -> string

(**/**)

val parser_config : Simplexmlparser.xml list ->
  Simplexmlparser.xml list list
val parse_server : bool -> Simplexmlparser.xml list -> unit
val extract_info :
  Simplexmlparser.xml list ->
  (string option * string option) *
  ((string option * string option) option * 
     int list * int list) * (int * int)
val parse_config :
  unit ->
  Simplexmlparser.xml list list
