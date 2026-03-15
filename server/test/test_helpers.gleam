import context
import db
import glogg/logger
import pog
import wisp

pub fn create_test_context() -> context.Context {
  let assert Ok(priv_dir) = wisp.priv_directory("server")
  context.Context(
    db: db.connect("TEST_DB_NAME"),
    static_dir: priv_dir <> "/static",
    logger: logger.new("npwd-test"),
  )
}

pub fn refresh_database(db: pog.Connection) -> Nil {
  let assert Ok(_) =
    pog.query("DELETE FROM characters;")
    |> pog.execute(db)
  Nil
}
