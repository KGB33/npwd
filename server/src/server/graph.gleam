import gleam/http.{Get}
import gleam/list
import gleam/option.{type Option, None, Some}
import server/db
import server/web
import shared
import wisp.{type Request, type Response}

pub fn handle(config: db.Config, req: Request, universe: String) -> Response {
  use <- wisp.require_method(req, Get)
  let query = wisp.get_query(req)
  web.respond(
    db.subgraph(
      config,
      universe,
      param(query, "from"),
      param(query, "relationship"),
      param(query, "to"),
      param(query, "field"),
      param(query, "value"),
    ),
    shared.graph_to_json,
    200,
  )
}

fn param(query: List(#(String, String)), key: String) -> Option(String) {
  case list.key_find(query, key) {
    Ok("") | Error(_) -> None
    Ok(value) -> Some(value)
  }
}
