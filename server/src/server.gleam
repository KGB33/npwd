import context
import db
import gleam/erlang/process
import glogg/handler
import glogg/logger
import mist
import router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  handler.set_default_handler_json_formatting()
  let log = logger.new("npwd")
  let secret_key = wisp.random_string(64)
  let database = db.connect("DB_NAME")

  let assert Ok(priv_dir) = wisp.priv_directory("server")
  let static_dir = priv_dir <> "/static"

  let assert Ok(_) =
    router.handle_request(_, fn() {
      context.Context(db: database, static_dir: static_dir, logger: log)
    })
    |> wisp_mist.handler(secret_key)
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
