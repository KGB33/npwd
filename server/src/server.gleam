import context
import gleam/erlang/process
import mist
import pog
import router
import wisp
import wisp/wisp_mist

fn setup_pog() {
  let name = process.new_name("db-pool")
  let assert Ok(actor) =
    pog.default_config(name)
    |> pog.host("localhost")
    |> pog.database("dev")
    |> pog.user("kgb33")
    |> pog.pool_size(15)
    |> pog.start

  actor.data
}

pub fn main() -> Nil {
  wisp.configure_logger()
  let secret_key = wisp.random_string(64)
  let db = setup_pog()

  let assert Ok(priv_dir) = wisp.priv_directory("server")
  let static_dir = priv_dir <> "/static"

  let assert Ok(_) =
    router.handle_request(_, fn() {
      context.Context(db: db, static_dir: static_dir)
    })
    |> wisp_mist.handler(secret_key)
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
