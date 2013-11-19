(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2013 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved.This file is distributed under the terms of the   *)
(*  GNU Lesser General Public License version 3.0 with linking            *)
(*  exception.                                                            *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

open Cmdliner
open Cow
open Cow.Html
open O2wTypes
open OpamTypes

exception Unknown_repository of string

type repo_enum =
| Path_enum
| Local_enum
| Opam_enum

(* Options *)
type options = {
  out_dir: string;
  files_dir: string;
  content_dir: string;
  logfiles: filename list;
  repositories: O2wTypes.repository list;
}

let version = Version.string

let include_files (path: string) files_path : unit =
  let subpathes = ["doc"; "pkg"] in
  let pathes =
    if String.length path > 0 then
      path :: List.map (fun p -> Printf.sprintf "%s/%s" path p) subpathes
    else
      subpathes
  in
  (* Check if output directory exists, create it if it doesn't *)
  List.iter (fun dir -> OpamFilename.mkdir (OpamFilename.Dir.of_string dir)) pathes

let make_stats user_options universe =
  let statistics = O2wStatistics.statistics_set user_options.logfiles in
  let popularity =
    match statistics with
    | None   -> OpamPackage.Name.Map.empty
    | Some s -> O2wStatistics.aggregate_package_popularity
                  s.month_stats.pkg_stats universe.pkg_idx in
  let _ = match statistics with
    | None   -> ()
    | Some s ->
      let popularity = s.month_stats.pkg_stats in
      O2wStatistics.to_csv popularity "stats.csv";
      O2wStatistics.to_json popularity "stats.json" in
  statistics, popularity

(* Generate a whole static website using the given repository stack *)
let make_website user_options universe =
  Printf.printf "++ Building the new stats from %s.\n%!"
    (OpamMisc.string_of_list OpamFilename.prettify user_options.logfiles);
  let statistics, popularity = make_stats user_options universe in
  let content_dir = user_options.content_dir in
  Printf.printf "++ Building the package pages.\n%!";
  let pages = O2wUniverse.to_pages ~statistics universe in
  Printf.printf "++ Building the documentation pages.\n%!";
  let menu_of_doc = O2wDocumentation.to_menu ~content_dir in
  let criteria = ["name"; "popularity"; "date"] in
  let criteria_nostats = ["name"; "date"] in
  let sortby_links = match statistics with
    | None   ->
      O2wUniverse.sortby_links ~links:criteria_nostats ~default:"name"
    | Some _ ->
      O2wUniverse.sortby_links ~links:criteria ~default:"name" in
  let to_html = O2wUniverse.to_html ~content_dir ~sortby_links ~popularity in
  Printf.printf "++ Building the package indexes.\n%!";
  let package_links =
    let compare_pkg = O2wPackage.compare_date ~reverse:true universe.pkgs_dates in
    let date = {
      menu_link = { text="Packages"; href="pkg/index-date.html" };
      menu_item = No_menu (1, to_html ~active:"date" ~compare_pkg universe);
    } in
    match statistics with
    | None -> [ date ]
    | Some s ->
      let compare_pkg = O2wPackage.compare_popularity ~reverse:true popularity in
      let popularity = {
        menu_link = { text="Packages"; href="pkg/index-popularity.html" };
        menu_item = No_menu (1, to_html ~active:"popularity" ~compare_pkg universe);
      } in
      [ popularity; date ]
  in
  include_files user_options.out_dir user_options.files_dir;
  let about_page =
    let filename = Printf.sprintf "%s/doc/About.md" content_dir in
    try
      let filename = OpamFilename.of_string filename in
      let contents = OpamFilename.read filename in
      let contents = Cow.Markdown_github.of_string contents in
      let contents = Cow.Markdown.to_html contents in
      <:html<
        <div class="container">
        $contents$
        </div>
      >>
    with _ ->
      OpamGlobals.warning "%s is not available." filename;
      <:html< >> in
  let home_index = O2wHome.to_html
    ~content_dir ~statistics ~popularity universe in
  let package_index =
    to_html ~active:"name" ~compare_pkg:O2wPackage.compare_alphanum universe in
  let doc_menu = menu_of_doc ~pages:O2wGlobals.documentation_pages in
  O2wTemplate.generate
    ~content_dir ~out_dir:user_options.out_dir
    ([
      { menu_link = { text="Home"; href="" };
        menu_item = Internal (0, home_index) };

      { menu_link = { text="Packages"; href="pkg/" };
        menu_item = Internal (1, package_index) };

      { menu_link = { text="Documentation"; href="doc/" };
        menu_item = Submenu doc_menu; };

      { menu_link = { text="About"; href="about.html" };
        menu_item = Internal (0, Template.serialize about_page) };

    ] @ package_links)
    pages

let normalize d =
  let len = String.length d in
  if len <> 0 && d.[len - 1] <> '/' then
    d ^ "/"
  else
    d

let log_files = Arg.(
  value & opt_all string [] & info ["s"; "statistics"]
    ~docv:"LOG_FILE"
    ~doc:"An Apache server log file containing download statistics of packages")

let out_dir = Arg.(
  value & opt string (Sys.getcwd ()) & info ["o"; "output"]
    ~docv:"OUT_DIR"
    ~doc:"The directory where to write the generated HTML files")

let content_dir = Arg.(
  value & opt string "content" & info ["c"; "content"]
    ~docv:"CONTENT_DIR"
    ~doc:"The directory where to find documentation to include")

let pred = Arg.(
  value & opt_all (list string) [] & info ["where"]
    ~docv:"WHERE_OR"
    ~doc:"Satisfaction of all of the predicates in any comma-separated list implies inclusion")

let index = Arg.(
  value & opt (enum [
    "all", Index_all;
    "where", Index_pred;
  ]) Index_pred & info ["index"]
  ~docv:"INDEX"
  ~doc:"Changes the set of packages for which indices are generated: 'all' or 'where'")

let repositories =
  let namespaces = Arg.enum [
    "path", Path_enum;
    "local", Local_enum;
    "opam", Opam_enum
  ] in
  Arg.(
    value & pos_all (pair ~sep:':' namespaces string) [Opam_enum,""] & info []
      ~docv:"REPOSITORY"
      ~doc:"The repositories to consider as the universe. Available namespaces are 'path' for local directories, 'local' for named opam remotes, and 'opam' for the current local opam universe.")

let stats_only =
  Arg.(value & flag & info ["stats-only"]
         ~doc:"Only generate stats.csv and stats.json, not a full website")

let rec parse_pred = function
  | "not"::more -> Not (parse_pred more)
  | "tag"::more -> Tag (String.concat ":" more)
  | "repo"::more -> Repo (String.concat ":" more)
  | "pkg"::more -> Pkg (String.concat ":" more)
  | ["depopt"]  -> Depopt
  | []   -> failwith "filter predicate empty"
  | p::_ -> failwith ("unknown predicate "^p)

let build logfiles out_dir content_dir repositories stats_only preds index =
  let preds = List.rev_map (fun pred ->
    List.rev_map (fun pred ->
      parse_pred Re_str.(split (regexp_string ":") pred)
    ) pred
  ) preds in
  let out_dir = normalize out_dir in
  let logfiles = List.map OpamFilename.of_string logfiles in
  let repositories = List.map (function
    | Path_enum, path ->
      Printf.printf "=== Repository: %s ===\n%!" path;
      Path path
    | Local_enum, local ->
      Printf.printf "=== Repository: %s [opam] ===\n%!" local;
      O2wTypes.Local local
    | Opam_enum, _ ->
      Printf.printf "=== Universe: current opam universe ===\n%!";
      Opam
  ) repositories
  in
  let user_options = {
    out_dir;
    files_dir = "";
    content_dir;
    logfiles;
    repositories;
  } in
  let universe = O2wUniverse.of_repositories ~preds index repositories in
  if stats_only then
    ignore (make_stats user_options universe)
  else
    make_website user_options universe

let default_cmd =
  let doc = "generate a web site from an opam universe" in
  let man = [
    `S "DESCRIPTION";
    `P "$(b,opam2web) generates a web site from an opam universe.";
    `S "BUGS";
    `P "Report bugs on the web at <https://github.com/OCamlPro/opam2web>.";
  ] in
  Term.(pure build $ log_files $ out_dir $ content_dir
          $ repositories $ stats_only $ pred $ index),
  Term.info "opam2web" ~version ~doc ~man

;;

match Term.eval default_cmd with
| `Error _ -> exit 1
| _ -> exit 0
