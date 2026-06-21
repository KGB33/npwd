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

fn universe(config: db.Config, owner: shared.User, name: String) -> String {
  let assert Ok(u) = db.create_universe(config, name, "", owner.id)
  u.id
}

fn node(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "Place", dict.new())
  n.id
}

fn edge_input(relationship: String, from: String, to: String) -> Json {
  json.object([
    #("relationship", json.string(relationship)),
    #("from", json.string(from)),
    #("to", json.string(to)),
  ])
}

fn post(
  config: db.Config,
  owner: shared.User,
  u: String,
  body: Json,
) -> shared.Edge {
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/edges")
    |> simulate.json_body(body)
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  let assert Ok(edge) =
    json.parse(simulate.read_body(response), shared.edge_decoder())
  edge
}

pub fn create_returns_201_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let frodo = node(config, u, "Frodo")
  let shire = node(config, u, "Shire")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/edges")
    |> simulate.json_body(edge_input("was_at", frodo, shire))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 201
  let assert Ok(edge) =
    json.parse(simulate.read_body(response), shared.edge_decoder())
  assert edge.relationship == "was_at"
  assert edge.from == frodo
  assert edge.to == shire
}

pub fn create_requires_auth_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let frodo = node(config, u, "Frodo")
  let shire = node(config, u, "Shire")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/edges")
    |> simulate.json_body(edge_input("was_at", frodo, shire))
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn list_is_scoped_and_public_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let a = universe(config, owner, "A")
  let b = universe(config, owner, "B")
  let a1 = node(config, a, "a1")
  let a2 = node(config, a, "a2")
  let b1 = node(config, b, "b1")
  let _ = post(config, owner, a, edge_input("knows", a1, a2))
  let _ = post(config, owner, b, edge_input("knows", b1, b1))
  let response =
    simulate.request(http.Get, "/universes/" <> a <> "/edges")
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(edges) =
    json.parse(simulate.read_body(response), decode.list(shared.edge_decoder()))
  assert list.length(edges) == 1
}

pub fn get_existing_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Earthsea")
  let a = node(config, u, "a")
  let b = node(config, u, "b")
  let created = post(config, owner, u, edge_input("knows", a, b))
  let response =
    simulate.request(http.Get, "/universes/" <> u <> "/edges/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(edge) =
    json.parse(simulate.read_body(response), shared.edge_decoder())
  assert edge == created
}

pub fn get_wrong_universe_is_404_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let a = universe(config, owner, "A")
  let b = universe(config, owner, "B")
  let n1 = node(config, a, "n1")
  let n2 = node(config, a, "n2")
  let created = post(config, owner, a, edge_input("knows", n1, n2))
  let response =
    simulate.request(http.Get, "/universes/" <> b <> "/edges/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 404
}

pub fn delete_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let n1 = node(config, u, "n1")
  let n2 = node(config, u, "n2")
  let created = post(config, owner, u, edge_input("knows", n1, n2))
  let response =
    simulate.request(http.Delete, "/universes/" <> u <> "/edges/" <> created.id)
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 204
  let after =
    simulate.request(http.Get, "/universes/" <> u <> "/edges/" <> created.id)
    |> router.handle_request(config, _)
  assert after.status == 404
}

pub fn create_invalid_body_is_400_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/edges")
    |> simulate.json_body(json.object([#("relationship", json.string("x"))]))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn create_empty_endpoints_is_400_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/edges")
    |> simulate.json_body(edge_input("knows", "", ""))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn create_malformed_endpoint_is_400_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let n = node(config, u, "n")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/edges")
    |> simulate.json_body(edge_input("knows", "not-an-id", n))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn wrong_method_is_405_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Patch, "/universes/" <> u <> "/edges")
    |> router.handle_request(config, _)
  assert response.status == 405
}
