import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Delete, Get, Post, Put}
import gleam/json
import server/db
import shared
import wisp.{type Request, type Response}

pub fn handle(
  config: db.Config,
  req: Request,
  segments: List(String),
) -> Response {
  case segments {
    [] ->
      case req.method {
        Get -> list(config)
        Post -> create(config, req)
        _ -> wisp.method_not_allowed([Get, Post])
      }
    [id] ->
      case req.method {
        Get -> respond_one(db.get_universe(config, id))
        Put -> update(config, req, id)
        Delete -> delete(config, id)
        _ -> wisp.method_not_allowed([Get, Put, Delete])
      }
    _ -> wisp.not_found()
  }
}

type Input {
  Input(name: String, description: String)
}

fn input_decoder() -> Decoder(Input) {
  use name <- decode.field("name", decode.string)
  use description <- decode.field("description", decode.string)
  decode.success(Input(name:, description:))
}

fn list(config: db.Config) -> Response {
  case db.list_universes(config) {
    Ok(universes) ->
      json.array(universes, shared.universe_to_json)
      |> json.to_string
      |> wisp.json_response(200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn create(config: db.Config, req: Request) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      case db.create_universe(config, input.name, input.description) {
        Ok(universe) -> single(universe, 201)
        Error(_) -> wisp.internal_server_error()
      }
    Error(_) -> wisp.bad_request("invalid universe")
  }
}

fn update(config: db.Config, req: Request, id: String) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      respond_one(db.update_universe(config, id, input.name, input.description))
    Error(_) -> wisp.bad_request("invalid universe")
  }
}

fn delete(config: db.Config, id: String) -> Response {
  case db.delete_universe(config, id) {
    Ok(_) -> wisp.no_content()
    Error(db.NotFound) -> wisp.not_found()
    Error(db.InvalidInput) -> wisp.bad_request("invalid id")
    Error(_) -> wisp.internal_server_error()
  }
}

fn respond_one(result: Result(shared.Universe, db.DbError)) -> Response {
  case result {
    Ok(universe) -> single(universe, 200)
    Error(db.NotFound) -> wisp.not_found()
    Error(db.InvalidInput) -> wisp.bad_request("invalid id")
    Error(_) -> wisp.internal_server_error()
  }
}

fn single(universe: shared.Universe, status: Int) -> Response {
  universe
  |> shared.universe_to_json
  |> json.to_string
  |> wisp.json_response(status)
}
