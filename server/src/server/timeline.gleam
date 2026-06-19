import gleam/http.{Get}
import gleam/json
import server/db
import shared
import wisp.{type Request, type Response}

pub fn handle(config: db.Config, req: Request, universe: String) -> Response {
  use <- wisp.require_method(req, Get)
  case db.timeline(config, universe) {
    Ok(graph) ->
      graph
      |> shared.graph_to_json
      |> json.to_string
      |> wisp.json_response(200)
    Error(_) -> wisp.internal_server_error()
  }
}
