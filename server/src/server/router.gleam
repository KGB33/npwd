import gleam/http.{Get}
import gleam/json
import server/auth
import server/db
import server/descriptions
import server/edges
import server/graph
import server/nodes
import server/timeline
import server/universes
import simplifile
import wisp.{type Request, type Response}

pub fn handle_request(config: db.Config, req: Request) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/", from: static_directory())

  case wisp.path_segments(req) {
    [] -> index(req)
    ["health"] -> health(req)
    ["me"] -> auth.me(config, req)
    ["auth", ..rest] -> auth.handle(config, req, rest)
    ["universes", uid, "nodes", nid, "descriptions", ..rest] ->
      descriptions.handle(config, req, uid, nid, rest)
    ["universes", uid, "nodes", ..rest] -> nodes.handle(config, req, uid, rest)
    ["universes", uid, "edges", ..rest] -> edges.handle(config, req, uid, rest)
    ["universes", uid, "graph"] -> graph.handle(config, req, uid)
    ["universes", uid, "timeline"] -> timeline.handle(config, req, uid)
    ["universes", ..rest] -> universes.handle(config, req, rest)
    _ -> wisp.not_found()
  }
}

fn index(req: Request) -> Response {
  use <- wisp.require_method(req, Get)
  case simplifile.read(static_directory() <> "/index.html") {
    Ok(html) -> wisp.html_response(html, 200)
    Error(_) -> wisp.not_found()
  }
}

fn static_directory() -> String {
  let assert Ok(priv) = wisp.priv_directory("server")
  priv <> "/static"
}

fn health(req: Request) -> Response {
  use <- wisp.require_method(req, Get)
  json.object([#("status", json.string("ok"))])
  |> json.to_string
  |> wisp.json_response(200)
}
