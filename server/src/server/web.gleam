import server/db
import wisp.{type Response}

pub fn db_error(error: db.DbError) -> Response {
  case error {
    db.NotFound -> wisp.not_found()
    db.InvalidInput -> wisp.bad_request("invalid id")
    _ -> wisp.internal_server_error()
  }
}
