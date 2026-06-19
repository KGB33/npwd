import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Delete, Get, Post}
import gleam/json
import server/db
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
        Post -> create(config, req, universe)
        _ -> wisp.method_not_allowed([Get, Post])
      }
    [id] ->
      case req.method {
        Get -> respond_one(db.get_edge(config, universe, id))
        Delete -> delete(config, universe, id)
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
  case db.list_edges(config, universe) {
    Ok(edges) ->
      json.array(edges, shared.edge_to_json)
      |> json.to_string
      |> wisp.json_response(200)
    Error(db.InvalidInput) -> wisp.bad_request("invalid id")
    Error(_) -> wisp.internal_server_error()
  }
}

fn create(config: db.Config, req: Request, universe: String) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      case
        db.create_edge(
          config,
          universe,
          input.relationship,
          input.from,
          input.to,
        )
      {
        Ok(edge) -> single(edge, 201)
        Error(db.InvalidInput) -> wisp.bad_request("invalid id")
        Error(_) -> wisp.internal_server_error()
      }
    Error(_) -> wisp.bad_request("invalid edge")
  }
}

fn delete(config: db.Config, universe: String, id: String) -> Response {
  case db.delete_edge(config, universe, id) {
    Ok(_) -> wisp.no_content()
    Error(db.NotFound) -> wisp.not_found()
    Error(db.InvalidInput) -> wisp.bad_request("invalid id")
    Error(_) -> wisp.internal_server_error()
  }
}

fn respond_one(result: Result(shared.Edge, db.DbError)) -> Response {
  case result {
    Ok(edge) -> single(edge, 200)
    Error(db.NotFound) -> wisp.not_found()
    Error(db.InvalidInput) -> wisp.bad_request("invalid id")
    Error(_) -> wisp.internal_server_error()
  }
}

fn single(edge: shared.Edge, status: Int) -> Response {
  edge
  |> shared.edge_to_json
  |> json.to_string
  |> wisp.json_response(status)
}
