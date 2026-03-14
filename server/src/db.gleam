import envoy
import gleam/erlang/process
import gleam/int
import gleam/option
import pog

pub type DbError {
  NotFound
  QueryError(pog.QueryError)
}

pub fn connect(db_name_var: String) -> pog.Connection {
  let assert Ok(host) = envoy.get("DB_HOST")
  let assert Ok(port_str) = envoy.get("DB_PORT")
  let assert Ok(port) = int.parse(port_str)
  let assert Ok(user) = envoy.get("DB_USER")
  let assert Ok(db_name) = envoy.get(db_name_var)
  let password = envoy.get("DB_PASSWORD") |> option.from_result

  let name = process.new_name("db-pool")
  let assert Ok(actor) =
    pog.default_config(name)
    |> pog.host(host)
    |> pog.port(port)
    |> pog.user(user)
    |> pog.password(password)
    |> pog.database(db_name)
    |> pog.pool_size(15)
    |> pog.start

  actor.data
}
