import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Delete, Get, Post}
import server/auth
import server/db
import server/web
import shared
import wisp.{type Request, type Response}

pub fn handle(
  config: db.Config,
  req: Request,
  universe: String,
  segments: List(String),
) -> Response {
  case segments {
    [] ->
      case req.method {
        Get -> list(config, universe)
        Post -> {
          use _ <- auth.require_owner(req, config, universe)
          create(config, req, universe)
        }
        _ -> wisp.method_not_allowed([Get, Post])
      }
    [id] ->
      case req.method {
        Get ->
          web.respond(
            db.get_edge(config, universe, id),
            shared.edge_to_json,
            200,
          )
        Delete -> {
          use _ <- auth.require_owner(req, config, universe)
          delete(config, universe, id)
        }
        _ -> wisp.method_not_allowed([Get, Delete])
      }
    _ -> wisp.not_found()
  }
}

type Input {
  Input(relationship: String, from: String, to: String)
}

fn input_decoder() -> Decoder(Input) {
  use relationship <- decode.field("relationship", decode.string)
  use from <- decode.field("from", decode.string)
  use to <- decode.field("to", decode.string)
  decode.success(Input(relationship:, from:, to:))
}

fn list(config: db.Config, universe: String) -> Response {
  web.collection(db.list_edges(config, universe), shared.edge_to_json)
}

fn create(config: db.Config, req: Request, universe: String) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      web.respond(
        db.create_edge(
          config,
          universe,
          input.relationship,
          input.from,
          input.to,
        ),
        shared.edge_to_json,
        201,
      )
    Error(_) -> wisp.bad_request("invalid edge")
  }
}

fn delete(config: db.Config, universe: String, id: String) -> Response {
  case db.delete_edge(config, universe, id) {
    Ok(_) -> wisp.no_content()
    Error(e) -> web.db_error(e)
  }
}
