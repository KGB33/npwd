import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/json.{type Json}
import gleam/list
import helpers
import server/db
import server/router
import shared
import wisp/simulate

fn universe(config: db.Config, name: String) -> String {
  let assert Ok(u) = db.create_universe(config, name, "")
  u.id
}

fn node(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "Place", dict.new())
  n.id
}

fn body_json(body: String) -> Json {
  json.object([#("body", json.string(body))])
}

fn base(u: String, n: String) -> String {
  "/universes/" <> u <> "/nodes/" <> n <> "/descriptions"
}

fn post(config: db.Config, u: String, n: String, body: String) -> shared.Description {
  let response =
    simulate.request(http.Post, base(u, n))
    |> simulate.json_body(body_json(body))
    |> router.handle_request(config, _)
  assert response.status == 201
  let assert Ok(d) =
    json.parse(simulate.read_body(response), shared.description_decoder())
  d
}

pub fn create_and_list_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let _ = post(config, u, n, "one")
  let _ = post(config, u, n, "two")

  let response =
    simulate.request(http.Get, base(u, n))
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(ds) =
    json.parse(
      simulate.read_body(response),
      decode.list(shared.description_decoder()),
    )
  assert list.map(ds, fn(d) { d.body }) == ["one", "two"]
}

pub fn update_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let created = post(config, u, n, "old")
  let response =
    simulate.request(http.Put, base(u, n) <> "/" <> created.id)
    |> simulate.json_body(body_json("new"))
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(d) =
    json.parse(simulate.read_body(response), shared.description_decoder())
  assert d.body == "new"
}

pub fn delete_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let created = post(config, u, n, "gone")
  let response =
    simulate.request(http.Delete, base(u, n) <> "/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 204
}

pub fn create_on_node_in_other_universe_is_404_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let n = node(config, a, "Shire")
  let response =
    simulate.request(http.Post, base(b, n))
    |> simulate.json_body(body_json("x"))
    |> router.handle_request(config, _)
  assert response.status == 404
}

pub fn invalid_body_is_400_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let response =
    simulate.request(http.Post, base(u, n))
    |> simulate.json_body(json.object([#("nope", json.string("x"))]))
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn wrong_method_is_405_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let response =
    simulate.request(http.Patch, base(u, n))
    |> router.handle_request(config, _)
  assert response.status == 405
}
