import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/application
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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

fn run(config: Config, surql: String) -> Result(List(Statement), DbError) {
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

pub fn execute(config: Config, surql: String) -> Result(Nil, DbError) {
  use statements <- result.try(run(config, surql))
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
  use statements <- result.try(run(config, surql))
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
