import gleam/int
import server/db
import shared
import wisp
import wisp/simulate

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

pub fn owner(config: db.Config) -> shared.User {
  let n = int.to_string(int.random(1_000_000_000))
  let assert Ok(user) =
    db.create_user(config, "u" <> n <> "@test", "secret", True)
  user
}

pub fn owned_universe(config: db.Config, name: String) -> String {
  let assert Ok(u) = db.create_universe(config, name, "", owner(config).id)
  u.id
}

pub fn auth(req: wisp.Request, user: shared.User) -> wisp.Request {
  simulate.cookie(req, "session", user.id, wisp.Signed)
}
