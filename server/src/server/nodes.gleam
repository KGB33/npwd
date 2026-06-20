import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Delete, Get, Post, Put}
import gleam/json
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
        Post -> create(config, req, universe)
        _ -> wisp.method_not_allowed([Get, Post])
      }
    [id] ->
      case req.method {
        Get -> respond_one(db.get_node(config, universe, id))
        Put -> update(config, req, universe, id)
        Delete -> delete(config, universe, id)
        _ -> wisp.method_not_allowed([Get, Put, Delete])
      }
    _ -> wisp.not_found()
  }
}

type Input {
  Input(name: String, kind: String, fields: dict.Dict(String, shared.FieldValue))
}

fn input_decoder() -> Decoder(Input) {
  use name <- decode.field("name", decode.string)
  use kind <- decode.field("kind", decode.string)
  use fields <- decode.optional_field(
    "fields",
    dict.new(),
    decode.dict(decode.string, shared.field_value_decoder()),
  )
  decode.success(Input(name:, kind:, fields:))
}

fn list(config: db.Config, universe: String) -> Response {
  case db.list_nodes(config, universe) {
    Ok(nodes) ->
      json.array(nodes, shared.node_to_json)
      |> json.to_string
      |> wisp.json_response(200)
    Error(e) -> web.db_error(e)
  }
}

fn create(config: db.Config, req: Request, universe: String) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      case
        db.create_node(config, universe, input.name, input.kind, input.fields)
      {
        Ok(node) -> single(node, 201)
        Error(e) -> web.db_error(e)
      }
    Error(_) -> wisp.bad_request("invalid node")
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
      respond_one(db.update_node(
        config,
        universe,
        id,
        input.name,
        input.kind,
        input.fields,
      ))
    Error(_) -> wisp.bad_request("invalid node")
  }
}

fn delete(config: db.Config, universe: String, id: String) -> Response {
  case db.delete_node(config, universe, id) {
    Ok(_) -> wisp.no_content()
    Error(e) -> web.db_error(e)
  }
}

fn respond_one(result: Result(shared.Node, db.DbError)) -> Response {
  case result {
    Ok(node) -> single(node, 200)
    Error(e) -> web.db_error(e)
  }
}

fn single(node: shared.Node, status: Int) -> Response {
  node
  |> shared.node_to_json
  |> json.to_string
  |> wisp.json_response(status)
}
