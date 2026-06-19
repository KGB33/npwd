import gleam/int
import server/db

pub fn fresh_config() -> db.Config {
  db.Config(
    host: "127.0.0.1",
    port: 8001,
    namespace: "test",
    database: "t" <> int.to_string(int.random(1_000_000_000)),
    user: "root",
    password: "root",
  )
}

pub fn fresh_db() -> db.Config {
  let config = fresh_config()
  let assert Ok(Nil) = db.apply_schema(config)
  config
}
