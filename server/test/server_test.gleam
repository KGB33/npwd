import gleam/http
import gleam/json
import gleeunit
import server/router
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn health_ok_test() {
  let response =
    simulate.request(http.Get, "/health")
    |> router.handle_request
  assert response.status == 200
  assert simulate.read_body(response)
    == json.to_string(json.object([#("status", json.string("ok"))]))
}

pub fn health_rejects_post_test() {
  let response =
    simulate.request(http.Post, "/health")
    |> router.handle_request
  assert response.status == 405
}

pub fn unknown_route_404_test() {
  let response =
    simulate.request(http.Get, "/nope")
    |> router.handle_request
  assert response.status == 404
}
