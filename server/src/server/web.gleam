import gleam/json.{type Json}
import server/db
import wisp.{type Response}

pub fn db_error(error: db.DbError) -> Response {
  case error {
    db.NotFound -> wisp.not_found()
    db.InvalidInput -> wisp.bad_request("invalid id")
    _ -> wisp.internal_server_error()
  }
}

/// Encode a value as a JSON response at `status`.
pub fn json(value: a, encode: fn(a) -> Json, status: Int) -> Response {
  encode(value) |> json.to_string |> wisp.json_response(status)
}

/// Render a db result as JSON at `status`, mapping db errors to HTTP errors.
pub fn respond(
  result: Result(a, db.DbError),
  encode: fn(a) -> Json,
  status: Int,
) -> Response {
  case result {
    Ok(value) -> json(value, encode, status)
    Error(e) -> db_error(e)
  }
}

/// Render a db result holding a list as a 200 JSON array.
pub fn collection(
  result: Result(List(a), db.DbError),
  encode: fn(a) -> Json,
) -> Response {
  respond(result, fn(items) { json.array(items, encode) }, 200)
}
