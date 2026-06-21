import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/application
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
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
  InvalidInput
}

pub fn error_to_string(error: DbError) -> String {
  case error {
    TransportError -> "transport error: could not reach SurrealDB"
    ResponseError(status, body) ->
      "unexpected HTTP " <> int.to_string(status) <> ": " <> body
    QueryError(detail) -> "query error: " <> detail
    ResultDecodeError -> "could not decode SurrealDB response"
    NoResult -> "query returned no result"
    NotFound -> "record not found"
    SchemaError -> "schema error"
    InvalidInput -> "invalid input"
  }
}

const id_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

pub fn valid_id(s: String) -> Bool {
  case string.split_once(s, ":") {
    Ok(#(table, id)) -> is_ident(table) && is_ident(id)
    Error(_) -> False
  }
}

fn is_ident(s: String) -> Bool {
  s != ""
  && list.all(string.to_graphemes(s), fn(c) { string.contains(id_chars, c) })
}

fn require_valid(
  ids: List(String),
  then: fn() -> Result(a, DbError),
) -> Result(a, DbError) {
  case list.all(ids, valid_id) {
    True -> then()
    False -> Error(InvalidInput)
  }
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
    |> request.set_header("accept", "application/json")
    |> request.set_header("content-type", "text/plain")
    |> request.set_header("surreal-ns", config.namespace)
    |> request.set_header("surreal-db", config.database)
    |> request.set_header("authorization", "Basic " <> credentials)
    |> request.set_body(let_prelude(vars) <> surql)

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

fn let_prelude(vars: List(#(String, Json))) -> String {
  list.fold(vars, "", fn(acc, v) {
    acc <> "LET $" <> v.0 <> " = " <> json.to_string(v.1) <> ";\n"
  })
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
  query_vars(config, surql, [], decoder)
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

pub type Credentials {
  Credentials(user: shared.User, hash: String)
}

pub fn count_users(config: Config) -> Result(Int, DbError) {
  query(config, "RETURN count(SELECT id FROM user)", decode.int)
}

pub fn create_user(
  config: Config,
  email: String,
  hash: String,
  admin: Bool,
) -> Result(shared.User, DbError) {
  query_first(
    config,
    "CREATE user CONTENT { email: $email, hash: $hash, admin: $admin } RETURN id, email, admin",
    [
      #("email", json.string(email)),
      #("hash", json.string(hash)),
      #("admin", json.bool(admin)),
    ],
    shared.user_decoder(),
  )
}

pub fn get_user(config: Config, id: String) -> Result(shared.User, DbError) {
  use <- require_valid([id])
  query_first(
    config,
    "SELECT id, email, admin FROM type::thing($id)",
    [#("id", json.string(id))],
    shared.user_decoder(),
  )
}

pub fn find_credentials(
  config: Config,
  email: String,
) -> Result(Credentials, DbError) {
  query_first(
    config,
    "SELECT id, email, admin, hash FROM user WHERE email = $email",
    [#("email", json.string(email))],
    credentials_decoder(),
  )
}

fn credentials_decoder() -> Decoder(Credentials) {
  use user <- decode.then(shared.user_decoder())
  use hash <- decode.field("hash", decode.string)
  decode.success(Credentials(user, hash))
}

pub fn list_universes(
  config: Config,
  owner: String,
) -> Result(List(shared.Universe), DbError) {
  use <- require_valid([owner])
  query_vars(
    config,
    "SELECT * FROM universe WHERE owner = type::thing($o) ORDER BY name",
    [#("o", json.string(owner))],
    decode.list(shared.universe_decoder()),
  )
}

pub fn create_universe(
  config: Config,
  name: String,
  description: String,
  owner: String,
) -> Result(shared.Universe, DbError) {
  use <- require_valid([owner])
  query_first(
    config,
    "CREATE universe SET name = $name, description = $description, owner = type::thing($o)",
    [
      #("name", json.string(name)),
      #("description", json.string(description)),
      #("o", json.string(owner)),
    ],
    shared.universe_decoder(),
  )
}

pub fn get_universe(
  config: Config,
  id: String,
) -> Result(shared.Universe, DbError) {
  use <- require_valid([id])
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
  use <- require_valid([id])
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
  use <- require_valid([id])
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
  use <- require_valid([universe])
  query_vars(
    config,
    "SELECT * FROM node WHERE universe = type::thing($u) ORDER BY name",
    [#("u", json.string(universe))],
    decode.list(shared.node_decoder()),
  )
}

fn node_vars(
  universe: String,
  name: String,
  kind: String,
  fields: dict.Dict(String, shared.FieldValue),
) -> List(#(String, Json)) {
  [
    #("u", json.string(universe)),
    #("name", json.string(name)),
    #("kind", json.string(kind)),
    #("fields", shared.fields_to_json(fields)),
  ]
}

pub fn create_node(
  config: Config,
  universe: String,
  name: String,
  kind: String,
  fields: dict.Dict(String, shared.FieldValue),
) -> Result(shared.Node, DbError) {
  use <- require_valid([universe])
  query_first(
    config,
    "CREATE node CONTENT { universe: type::thing($u), name: $name, kind: $kind, fields: $fields }",
    node_vars(universe, name, kind, fields),
    shared.node_decoder(),
  )
}

pub fn get_node(
  config: Config,
  universe: String,
  id: String,
) -> Result(shared.Node, DbError) {
  use <- require_valid([id, universe])
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
  kind: String,
  fields: dict.Dict(String, shared.FieldValue),
) -> Result(shared.Node, DbError) {
  use <- require_valid([id, universe])
  query_first(
    config,
    "UPDATE type::thing($id) CONTENT { universe: type::thing($u), name: $name, kind: $kind, fields: $fields } WHERE universe = type::thing($u)",
    [#("id", json.string(id)), ..node_vars(universe, name, kind, fields)],
    shared.node_decoder(),
  )
}

pub fn delete_node(
  config: Config,
  universe: String,
  id: String,
) -> Result(shared.Node, DbError) {
  use <- require_valid([id, universe])
  query_first(
    config,
    "DELETE type::thing($id) WHERE universe = type::thing($u) RETURN BEFORE",
    [#("id", json.string(id)), #("u", json.string(universe))],
    shared.node_decoder(),
  )
}

pub fn list_descriptions(
  config: Config,
  universe: String,
  node: String,
) -> Result(List(shared.Description), DbError) {
  use <- require_valid([universe, node])
  query_vars(
    config,
    "SELECT * FROM description WHERE node.universe = type::thing($u) AND node = type::thing($n) ORDER BY position",
    [#("u", json.string(universe)), #("n", json.string(node))],
    decode.list(shared.description_decoder()),
  )
}

pub fn create_description(
  config: Config,
  universe: String,
  node: String,
  body: String,
) -> Result(shared.Description, DbError) {
  use <- require_valid([universe, node])
  use _ <- result.try(get_node(config, universe, node))
  query_first(
    config,
    "CREATE description CONTENT {
       node: type::thing($n),
       position: count(SELECT id FROM description WHERE node = type::thing($n)),
       body: $body
     } RETURN id, node, position, body;",
    [#("n", json.string(node)), #("body", json.string(body))],
    shared.description_decoder(),
  )
}

pub fn update_description(
  config: Config,
  universe: String,
  id: String,
  body: String,
) -> Result(shared.Description, DbError) {
  use <- require_valid([universe, id])
  query_first(
    config,
    "UPDATE type::thing($id) SET body = $body WHERE node.universe = type::thing($u) RETURN id, node, position, body",
    [
      #("id", json.string(id)),
      #("u", json.string(universe)),
      #("body", json.string(body)),
    ],
    shared.description_decoder(),
  )
}

pub fn delete_description(
  config: Config,
  universe: String,
  id: String,
) -> Result(shared.Description, DbError) {
  use <- require_valid([universe, id])
  query_first(
    config,
    "DELETE type::thing($id) WHERE node.universe = type::thing($u) RETURN BEFORE",
    [#("id", json.string(id)), #("u", json.string(universe))],
    shared.description_decoder(),
  )
}

pub fn list_edges(
  config: Config,
  universe: String,
) -> Result(List(shared.Edge), DbError) {
  use <- require_valid([universe])
  query_vars(
    config,
    "SELECT id, in AS from, out AS to, relationship, universe FROM relationship WHERE universe = type::thing($u) ORDER BY relationship",
    [#("u", json.string(universe))],
    decode.list(shared.edge_decoder()),
  )
}

pub fn create_edge(
  config: Config,
  universe: String,
  relationship: String,
  from: String,
  to: String,
) -> Result(shared.Edge, DbError) {
  use <- require_valid([universe, from, to])
  use _ <- result.try(get_node(config, universe, from))
  use _ <- result.try(get_node(config, universe, to))
  query_first(
    config,
    "LET $f = type::thing($from); LET $t = type::thing($to); RELATE $f->relationship->$t CONTENT { universe: type::thing($u), relationship: $rel } RETURN id, in AS from, out AS to, relationship, universe",
    [
      #("u", json.string(universe)),
      #("rel", json.string(relationship)),
      #("from", json.string(from)),
      #("to", json.string(to)),
    ],
    shared.edge_decoder(),
  )
}

pub fn get_edge(
  config: Config,
  universe: String,
  id: String,
) -> Result(shared.Edge, DbError) {
  use <- require_valid([id, universe])
  query_first(
    config,
    "SELECT id, in AS from, out AS to, relationship, universe FROM type::thing($id) WHERE universe = type::thing($u)",
    [#("id", json.string(id)), #("u", json.string(universe))],
    shared.edge_decoder(),
  )
}

pub fn delete_edge(
  config: Config,
  universe: String,
  id: String,
) -> Result(shared.Edge, DbError) {
  use <- require_valid([id, universe])
  query_first(
    config,
    "DELETE type::thing($id) WHERE universe = type::thing($u) RETURN BEFORE",
    [#("id", json.string(id)), #("u", json.string(universe))],
    edge_before_decoder(),
  )
}

fn edge_before_decoder() -> Decoder(shared.Edge) {
  use id <- decode.field("id", decode.string)
  use universe <- decode.field("universe", decode.string)
  use relationship <- decode.field("relationship", decode.string)
  use from <- decode.field("in", decode.string)
  use to <- decode.field("out", decode.string)
  decode.success(shared.Edge(id, universe, relationship, from, to))
}

pub fn subgraph(
  config: Config,
  universe: String,
  from: Option(String),
  relationship: Option(String),
  to: Option(String),
  field: Option(String),
  value: Option(String),
) -> Result(shared.Graph, DbError) {
  use <- require_valid([universe])
  query_vars(
    config,
    "LET $pattern = $src != NULL OR $dst != NULL OR $rel != NULL;
     LET $matchns = SELECT * FROM node WHERE universe = type::thing($u) AND ($field = NULL OR $this[$field] = $value OR $this.fields[$field] = $value) ORDER BY name;
     LET $matchids = $matchns.id;
     LET $es = SELECT id, in AS from, out AS to, relationship, universe FROM relationship WHERE universe = type::thing($u) AND ($rel = NULL OR relationship = $rel) AND ($src = NULL OR in.kind = $src OR in.name = $src) AND ($dst = NULL OR out.kind = $dst OR out.name = $dst) AND ($field = NULL OR (in IN $matchids AND out IN $matchids) OR ($pattern AND (in IN $matchids OR out IN $matchids))) ORDER BY relationship;
     LET $eids = array::distinct(array::concat($es.from, $es.to));
     LET $ns = IF $pattern THEN (SELECT * FROM node WHERE id IN $eids ORDER BY name) ELSE $matchns END;
     RETURN { nodes: $ns, edges: $es };",
    [
      #("u", json.string(universe)),
      #("src", opt_string(from)),
      #("rel", opt_string(relationship)),
      #("dst", opt_string(to)),
      #("field", opt_string(field)),
      #("value", opt_string(value)),
    ],
    shared.graph_decoder(),
  )
}

pub fn timeline(
  config: Config,
  universe: String,
) -> Result(shared.Graph, DbError) {
  use <- require_valid([universe])
  query_vars(
    config,
    "LET $ns = SELECT * FROM node WHERE universe = type::thing($u) AND fields.when != NONE ORDER BY fields.when;
     LET $ids = $ns.id;
     LET $es = SELECT id, in AS from, out AS to, relationship, universe FROM relationship WHERE universe = type::thing($u) AND (in IN $ids OR out IN $ids) ORDER BY relationship;
     RETURN { nodes: $ns, edges: $es };",
    [#("u", json.string(universe))],
    shared.graph_decoder(),
  )
}

fn opt_string(value: Option(String)) -> Json {
  case value {
    Some(s) -> json.string(s)
    None -> json.null()
  }
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
