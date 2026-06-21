import server/auth
import server/db

pub fn query_error_is_conflict_test() {
  assert auth.create_user_status(db.QueryError("duplicate")) == 409
}

pub fn transport_error_is_server_error_test() {
  assert auth.create_user_status(db.TransportError) == 500
}
