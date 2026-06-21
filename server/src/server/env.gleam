import gleam/int
import gleam/result
import server/db

pub type Env {
  Env(config: db.Config, secret_key_base: String, port: Int)
}

fn require(
  get: fn(String) -> Result(String, Nil),
  name: String,
) -> Result(String, String) {
  get(name) |> result.replace_error(name <> " is required")
}

fn require_int(
  get: fn(String) -> Result(String, Nil),
  name: String,
) -> Result(Int, String) {
  use raw <- result.try(require(get, name))
  int.parse(raw) |> result.replace_error(name <> " must be an integer")
}

pub fn load(get: fn(String) -> Result(String, Nil)) -> Result(Env, String) {
  use host <- result.try(require(get, "SURREAL_HOST"))
  use db_port <- result.try(require_int(get, "SURREAL_PORT"))
  use namespace <- result.try(require(get, "SURREAL_NAMESPACE"))
  use database <- result.try(require(get, "SURREAL_DATABASE"))
  use user <- result.try(require(get, "SURREAL_USER"))
  use password <- result.try(require(get, "SURREAL_PASSWORD"))
  use secret_key_base <- result.try(require(get, "SECRET_KEY_BASE"))
  use http_port <- result.try(require_int(get, "PORT"))
  Ok(Env(
    config: db.Config(
      host:,
      port: db_port,
      namespace:,
      database:,
      user:,
      password:,
    ),
    secret_key_base:,
    port: http_port,
  ))
}
