import gleam/http.{Get}
import gleam/json
import server/db
import server/nodes
import server/universes
import wisp.{type Request, type Response}

pub fn handle_request(config: db.Config, req: Request) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: static_directory())

  case wisp.path_segments(req) {
    ["health"] -> health(req)
    ["universes", uid, "nodes", ..rest] -> nodes.handle(config, req, uid, rest)
    ["universes", ..rest] -> universes.handle(config, req, rest)
    _ -> wisp.not_found()
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
