import gleam/http.{Get}
import server/db
import server/web
import shared
import wisp.{type Request, type Response}

pub fn handle(config: db.Config, req: Request, universe: String) -> Response {
  use <- wisp.require_method(req, Get)
  web.respond(db.timeline(config, universe), shared.graph_to_json, 200)
}
