import envoy
import gleam/erlang/process
import mist
import server/db
import server/passwords
import server/router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  let config = db.default_config()
  let _ = db.apply_schema(config)
  seed_admin(config)
  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(config, _), secret_key_base)
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

fn seed_admin(config: db.Config) -> Nil {
  case db.count_users(config), envoy.get("ADMIN_EMAIL"), envoy.get("ADMIN_PASSWORD") {
    Ok(0), Ok(email), Ok(password) -> {
      let _ = db.create_user(config, email, passwords.hash(password), True)
      Nil
    }
    _, _, _ -> Nil
  }
}
