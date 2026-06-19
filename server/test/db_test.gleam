import gleam/dynamic/decode
import gleam/int
import server/db

fn fresh_config() -> db.Config {
  db.Config(
    host: "127.0.0.1",
    port: 8001,
    namespace: "test",
    database: "t" <> int.to_string(int.random(1_000_000_000)),
    user: "root",
    password: "root",
  )
}

fn names_decoder() {
  decode.list(decode.at(["name"], decode.string))
}

pub fn apply_schema_test() {
  let config = fresh_config()
  assert db.apply_schema(config) == Ok(Nil)
}

pub fn create_and_select_test() {
  let config = fresh_config()
  assert db.apply_schema(config) == Ok(Nil)

  let created =
    db.execute(
      config,
      "CREATE universe SET name = 'Middle Earth', description = 'Tolkien';",
    )
  assert created == Ok(Nil)

  let names = db.query(config, "SELECT name FROM universe;", names_decoder())
  assert names == Ok(["Middle Earth"])
}

pub fn isolation_between_databases_test() {
  let a = fresh_config()
  let b = fresh_config()
  let assert Ok(Nil) = db.apply_schema(a)
  let assert Ok(Nil) = db.apply_schema(b)
  let assert Ok(Nil) =
    db.execute(a, "CREATE universe SET name = 'A', description = '';")

  let in_b = db.query(b, "SELECT name FROM universe;", names_decoder())
  assert in_b == Ok([])
}

pub fn query_error_surfaces_test() {
  let config = fresh_config()
  let assert Ok(Nil) = db.apply_schema(config)
  let result = db.execute(config, "THIS IS NOT VALID SURQL;")
  assert result != Ok(Nil)
}

pub fn bound_param_select_test() {
  let config = fresh_config()
  let assert Ok(Nil) = db.apply_schema(config)
  let assert Ok(Nil) =
    db.execute(config, "CREATE universe SET name = 'Narnia', description = '';")
  let assert Ok(Nil) =
    db.execute(config, "CREATE universe SET name = 'Dune', description = '';")

  let names =
    db.query(
      config,
      "SELECT name FROM universe WHERE name = 'Dune';",
      names_decoder(),
    )
  assert names == Ok(["Dune"])
}
