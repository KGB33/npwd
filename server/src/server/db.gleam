import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/application
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import shared
import simplifile

pub type Config {
  Config(
    host: String,
    port: Int,
    namespace: String,
    database: String,
    user: String,
    password: String,
  )
}

pub type DbError {
  TransportError
  ResponseError(status: Int, body: String)
  QueryError(detail: String)
  ResultDecodeError
  NoResult
  NotFound
  SchemaError
}

pub fn default_config() -> Config {
  Config(
    host: "127.0.0.1",
    port: 8000,
    namespace: "npwd",
    database: "npwd",
    user: "root",
    password: "root",
  )
}

type Statement {
  Statement(status: String, detail: String, result: Option(Dynamic))
}

fn statement_decoder() -> Decoder(Statement) {
  use status <- decode.field("status", decode.string)
  use detail <- decode.optional_field("detail", "", decode.string)
  use result <- decode.optional_field(
    "result",
    None,
    decode.map(decode.dynamic, Some),
  )
  decode.success(Statement(status:, detail:, result:))
}

fn run(
  config: Config,
  surql: String,
  vars: List(#(String, Json)),
) -> Result(List(Statement), DbError) {
  let credentials =
    bit_array.base64_encode(
      bit_array.from_string(config.user <> ":" <> config.password),
      True,
    )
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_scheme(http.Http)
    |> request.set_host(config.host)
    |> request.set_port(config.port)
    |> request.set_path("/sql")
    |> request.set_query(vars_query(vars))
    |> request.set_header("accept", "application/json")
    |> request.set_header("content-type", "text/plain")
    |> request.set_header("surreal-ns", config.namespace)
    |> request.set_header("surreal-db", config.database)
    |> request.set_header("authorization", "Basic " <> credentials)
    |> request.set_body(surql)

  use response <- result.try(
    httpc.send(req) |> result.replace_error(TransportError),
  )
  case response.status {
    200 ->
      json.parse(response.body, decode.list(statement_decoder()))
      |> result.replace_error(ResultDecodeError)
    status -> Error(ResponseError(status, response.body))
  }
}

fn vars_query(vars: List(#(String, Json))) -> List(#(String, String)) {
  list.map(vars, fn(v) { #(v.0, json.to_string(v.1)) })
}

fn last_result(
  statements: List(Statement),
  decoder: Decoder(a),
) -> Result(a, DbError) {
  use last <- result.try(
    list.last(statements) |> result.replace_error(NoResult),
  )
  case last.status, last.result {
    "OK", Some(value) ->
      decode.run(value, decoder) |> result.replace_error(ResultDecodeError)
    "OK", None -> Error(NoResult)
    _, _ -> Error(QueryError(last.detail))
  }
}

pub fn execute(config: Config, surql: String) -> Result(Nil, DbError) {
  use statements <- result.try(run(config, surql, []))
  case list.find(statements, fn(s) { s.status != "OK" }) {
    Ok(failed) -> Error(QueryError(failed.detail))
    Error(_) -> Ok(Nil)
  }
}

pub fn query(
  config: Config,
  surql: String,
  decoder: Decoder(a),
) -> Result(a, DbError) {
  use statements <- result.try(run(config, surql, []))
  last_result(statements, decoder)
}

fn query_vars(
  config: Config,
  surql: String,
  vars: List(#(String, Json)),
  decoder: Decoder(a),
) -> Result(a, DbError) {
  use statements <- result.try(run(config, surql, vars))
  last_result(statements, decoder)
}

fn query_first(
  config: Config,
  surql: String,
  vars: List(#(String, Json)),
  decoder: Decoder(a),
) -> Result(a, DbError) {
  use rows <- result.try(query_vars(config, surql, vars, decode.list(decoder)))
  case rows {
    [first, ..] -> Ok(first)
    [] -> Error(NotFound)
  }
}

pub fn list_universes(
  config: Config,
) -> Result(List(shared.Universe), DbError) {
  query(
    config,
    "SELECT * FROM universe ORDER BY name",
    decode.list(shared.universe_decoder()),
  )
}

pub fn create_universe(
  config: Config,
  name: String,
  description: String,
) -> Result(shared.Universe, DbError) {
  query_first(
    config,
    "CREATE universe SET name = $name, description = $description",
    [#("name", json.string(name)), #("description", json.string(description))],
    shared.universe_decoder(),
  )
}

pub fn get_universe(
  config: Config,
  id: String,
) -> Result(shared.Universe, DbError) {
  query_first(
    config,
    "SELECT * FROM type::thing($id)",
    [#("id", json.string(id))],
    shared.universe_decoder(),
  )
}

pub fn update_universe(
  config: Config,
  id: String,
  name: String,
  description: String,
) -> Result(shared.Universe, DbError) {
  query_first(
    config,
    "UPDATE type::thing($id) MERGE { name: $name, description: $description }",
    [
      #("id", json.string(id)),
      #("name", json.string(name)),
      #("description", json.string(description)),
    ],
    shared.universe_decoder(),
  )
}

pub fn delete_universe(
  config: Config,
  id: String,
) -> Result(shared.Universe, DbError) {
  query_first(
    config,
    "DELETE type::thing($id) RETURN BEFORE",
    [#("id", json.string(id))],
    shared.universe_decoder(),
  )
}

pub fn list_nodes(
  config: Config,
  universe: String,
) -> Result(List(shared.Node), DbError) {
  query_vars(
    config,
    "SELECT * FROM node WHERE universe = type::thing($u) ORDER BY name",
    [#("u", json.string(universe))],
    decode.list(shared.node_decoder()),
  )
}

pub fn create_node(
  config: Config,
  universe: String,
  name: String,
  description: String,
  kind: shared.NodeKind,
) -> Result(shared.Node, DbError) {
  query_first(
    config,
    "CREATE node CONTENT $data",
    [#("data", shared.node_content_to_json(universe, name, description, kind))],
    shared.node_decoder(),
  )
}

pub fn get_node(
  config: Config,
  universe: String,
  id: String,
) -> Result(shared.Node, DbError) {
  query_first(
    config,
    "SELECT * FROM type::thing($id) WHERE universe = type::thing($u)",
    [#("id", json.string(id)), #("u", json.string(universe))],
    shared.node_decoder(),
  )
}

pub fn update_node(
  config: Config,
  universe: String,
  id: String,
  name: String,
  description: String,
  kind: shared.NodeKind,
) -> Result(shared.Node, DbError) {
  query_first(
    config,
    "UPDATE type::thing($id) CONTENT $data WHERE universe = type::thing($u)",
    [
      #("id", json.string(id)),
      #("u", json.string(universe)),
      #("data", shared.node_content_to_json(universe, name, description, kind)),
    ],
    shared.node_decoder(),
  )
}

pub fn delete_node(
  config: Config,
  universe: String,
  id: String,
) -> Result(shared.Node, DbError) {
  query_first(
    config,
    "DELETE type::thing($id) WHERE universe = type::thing($u) RETURN BEFORE",
    [#("id", json.string(id)), #("u", json.string(universe))],
    shared.node_decoder(),
  )
}

pub fn apply_schema(config: Config) -> Result(Nil, DbError) {
  case load_schema() {
    Ok(surql) -> execute(config, surql)
    Error(_) -> Error(SchemaError)
  }
}

fn load_schema() -> Result(String, Nil) {
  use priv <- result.try(application.priv_directory("server"))
  simplifile.read(priv <> "/schema.surql") |> result.replace_error(Nil)
}
