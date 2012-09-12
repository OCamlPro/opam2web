open Cow.Html

(* Returns the latest version of a list containing multiple versions of the same
   package *)
let latest: Types.NV.t list -> Types.NV.t = function
  | h :: _ -> h
  | [] -> failwith "Repository.to_html: error building unique_packages"

(* Returns a HTML description of the given package *)
let to_html (repository: Path.R.t) (versions: Types.NV.t list)
    (pkg: Types.NV.t): Cow.Html.t =
  let pkg_name = Types.N.to_string (Types.NV.name pkg) in
  let pkg_version = Types.V.to_string (Types.NV.version pkg) in
  let pkg_descr_markdown =
    File.Descr.full (File.Descr.read (Path.R.descr repository pkg))
  in
  let pkg_descr =
    Cow.Markdown.to_html (Cow.Markdown.of_string pkg_descr_markdown)
  in
  let pkg_url =
    try
      let url_file = File.URL.read (Path.R.url repository pkg) in
      let kind = match File.URL.kind url_file with
        | Some k -> <:xml< [$str: k$] >>
        | None -> <:xml< >>
      in
      let checksum = match File.URL.checksum url_file with
        | Some c -> <:xml< <small>$str: c$</small> >>
        | None -> <:xml< >>
      in
      let url = File.URL.url url_file in
      <:xml<
        <tr>
          <th>Source $kind$</th>
          <td>
            <a href="$str: url$" title="Download source">$str: url$</a><br />
            $checksum$
          </td>
        </tr>
      >>
    with
      Globals.Exit 66 -> <:xml< >>
  in
  let opam_file = File.OPAM.read (Path.R.opam repository pkg) in
  let version_links = List.map (fun (pkg: Types.NV.t) ->
      let version = Types.V.to_string (Types.NV.version pkg) in
      let href = Printf.sprintf "%s.%s.html" pkg_name version in
      if pkg_version = version then
        <:xml<
          <li class="active">
            <a href="#">version $str: pkg_version$</a>
          </li>
        >>
      else
        <:xml< <li><a href="$str: href$">$str: version$</a></li> >>)
    versions
  in
  let pkg_maintainer = File.OPAM.maintainer opam_file in
  <:xml<
    <h2>$str: pkg_name$</h2>

    <div>
      <ul class="nav nav-pills">
        $list: version_links$
      </ul>
    </div>

    <table class="table">
      <tbody>
        <tr>
          <th>Maintainer</th>
          <td>
            $str: pkg_maintainer$
          </td>
        </tr>
        $pkg_url$
<!--
        <tr>
          <th>Dependencies</th>
          <td></td>
        </tr>
        <tr>
          <th>Optional dependencies</th>
          <td></td>
        </tr>
-->
      </tbody>
    </table>

    <div class="well">$pkg_descr$</div>
  >>
