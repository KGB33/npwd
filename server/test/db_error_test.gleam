import server/db

pub fn query_error_includes_detail_test() {
  assert db.error_to_string(db.QueryError("boom")) == "query error: boom"
}

pub fn response_error_includes_status_and_body_test() {
  assert db.error_to_string(db.ResponseError(500, "nope"))
    == "unexpected HTTP 500: nope"
}

pub fn transport_error_is_described_test() {
  assert db.error_to_string(db.TransportError)
    == "transport error: could not reach SurrealDB"
}
