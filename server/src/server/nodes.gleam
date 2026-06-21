import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/http.{Delete, Get, Post, Put}
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
            db.get_node(config, universe, id),
            shared.node_to_json,
            200,
          )
        Put -> {
          use _ <- auth.require_owner(req, config, universe)
          update(config, req, universe, id)
        }
        Delete -> {
          use _ <- auth.require_owner(req, config, universe)
          delete(config, universe, id)
        }
        _ -> wisp.method_not_allowed([Get, Put, Delete])
      }
    _ -> wisp.not_found()
  }
}

type Input {
  Input(
    name: String,
    kind: String,
    fields: dict.Dict(String, shared.FieldValue),
  )
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
  web.collection(db.list_nodes(config, universe), shared.node_to_json)
}

fn create(config: db.Config, req: Request, universe: String) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, input_decoder()) {
    Ok(input) ->
      web.respond(
        db.create_node(config, universe, input.name, input.kind, input.fields),
        shared.node_to_json,
        201,
      )
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
      web.respond(
        db.update_node(
          config,
          universe,
          id,
          input.name,
          input.kind,
          input.fields,
        ),
        shared.node_to_json,
        200,
      )
    Error(_) -> wisp.bad_request("invalid node")
  }
}

fn delete(config: db.Config, universe: String, id: String) -> Response {
  case db.delete_node(config, universe, id) {
    Ok(_) -> wisp.no_content()
    Error(e) -> web.db_error(e)
  }
}
