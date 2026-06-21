import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Delete, Get, Post, Put}
import gleam/json
import server/auth
import server/db
import server/web
import shared
import wisp.{type Request, type Response}

pub fn handle(
  config: db.Config,
  req: Request,
  universe: String,
  node: String,
  segments: List(String),
) -> Response {
  case segments {
    [] ->
      case req.method {
        Get -> list(config, universe, node)
        Post -> {
          use _ <- auth.require_owner(req, config, universe)
          create(config, req, universe, node)
        }
        _ -> wisp.method_not_allowed([Get, Post])
      }
    [id] ->
      case req.method {
        Put -> {
          use _ <- auth.require_owner(req, config, universe)
          update(config, req, universe, id)
        }
        Delete -> {
          use _ <- auth.require_owner(req, config, universe)
          delete(config, universe, id)
        }
        _ -> wisp.method_not_allowed([Put, Delete])
      }
    _ -> wisp.not_found()
  }
}

type Input {
  Input(body: String)
}

fn input_decoder() -> Decoder(Input) {
  use body <- decode.field("body", decode.string)
  decode.success(Input(body:))
}

fn list(config: db.Config, universe: String, node: String) -> Response {
  case db.list_descriptions(config, universe, node) {
    Ok(ds) ->
      json.array(ds, shared.description_to_json)
      |> json.to_string
      |> wisp.json_response(200)
    Error(e) -> web.db_error(e)
  }
}

fn create(
  config: db.Config,
  req: Request,
  universe: String,
  node: String,
) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      case db.create_description(config, universe, node, input.body) {
        Ok(d) -> single(d, 201)
        Error(e) -> web.db_error(e)
      }
    Error(_) -> wisp.bad_request("invalid description")
  }
}

fn update(
  config: db.Config,
  req: Request,
  universe: String,
  id: String,
) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      respond_one(db.update_description(config, universe, id, input.body))
    Error(_) -> wisp.bad_request("invalid description")
  }
}

fn delete(config: db.Config, universe: String, id: String) -> Response {
  case db.delete_description(config, universe, id) {
    Ok(_) -> wisp.no_content()
    Error(e) -> web.db_error(e)
  }
}

fn respond_one(result: Result(shared.Description, db.DbError)) -> Response {
  case result {
    Ok(d) -> single(d, 200)
    Error(e) -> web.db_error(e)
  }
}

fn single(d: shared.Description, status: Int) -> Response {
  d
  |> shared.description_to_json
  |> json.to_string
  |> wisp.json_response(status)
}
