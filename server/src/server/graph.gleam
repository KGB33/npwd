import gleam/http.{Get}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import server/db
import shared
import wisp.{type Request, type Response}

pub fn handle(config: db.Config, req: Request, universe: String) -> Response {
  use <- wisp.require_method(req, Get)
  let query = wisp.get_query(req)
  case
    db.subgraph(
      config,
      universe,
      param(query, "kind"),
      param(query, "relationship"),
      param(query, "field"),
      param(query, "value"),
    )
  {
    Ok(graph) ->
      graph
      |> shared.graph_to_json
      |> json.to_string
      |> wisp.json_response(200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn param(query: List(#(String, String)), key: String) -> Option(String) {
  case list.key_find(query, key) {
    Ok("") | Error(_) -> None
    Ok(value) -> Some(value)
  }
}
