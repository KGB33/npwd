import server/auth
import server/db

pub fn conflict_is_409_test() {
  assert auth.create_user_status(db.Conflict) == 409
}

pub fn query_error_is_server_error_test() {
  assert auth.create_user_status(db.QueryError("Parse error: unexpected token"))
    == 500
}

pub fn transport_error_is_server_error_test() {
  assert auth.create_user_status(db.TransportError) == 500
}
