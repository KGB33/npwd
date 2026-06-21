import envoy
import gleam/erlang/process
import mist
import server/db
import server/env
import server/passwords
import server/router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  let loaded = case env.load(envoy.get) {
    Ok(e) -> e
    Error(message) -> panic as message
  }
  let config = loaded.config
  case db.apply_schema(config) {
    Ok(_) -> Nil
    Error(e) -> panic as { "schema apply failed: " <> db.error_to_string(e) }
  }
  seed_admin(config)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(config, _), loaded.secret_key_base)
    |> mist.new
    |> mist.port(loaded.port)
    |> mist.start

  process.sleep_forever()
}

fn seed_admin(config: db.Config) -> Nil {
  case db.count_users(config) {
    Ok(0) ->
      case envoy.get("ADMIN_EMAIL"), envoy.get("ADMIN_PASSWORD") {
        Ok(email), Ok(password) ->
          case db.create_user(config, email, passwords.hash(password), True) {
            Ok(_) -> Nil
            Error(e) ->
              panic as { "admin seed failed: " <> db.error_to_string(e) }
          }
        _, _ -> Nil
      }
    Ok(_) -> Nil
    Error(e) -> panic as { "user count failed: " <> db.error_to_string(e) }
  }
}
