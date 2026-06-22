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

fn node_input(
  name: String,
  kind: String,
  fields: List(#(String, Json)),
) -> Json {
  json.object([
    #("name", json.string(name)),
    #("kind", json.string(kind)),
    #("fields", json.object(fields)),
  ])
}

fn create(
  config: db.Config,
  owner: shared.User,
  universe: String,
  body: Json,
) -> shared.Node {
  let response =
    simulate.request(http.Post, "/universes/" <> universe <> "/nodes")
    |> simulate.json_body(body)
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  let assert Ok(node) =
    json.parse(simulate.read_body(response), shared.node_decoder())
  node
}

pub fn create_returns_201_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/nodes")
    |> simulate.json_body(node_input("Shire", "Place", []))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 201
  let assert Ok(node) =
    json.parse(simulate.read_body(response), shared.node_decoder())
  assert node.name == "Shire"
  assert node.universe == u
}

pub fn create_requires_auth_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/nodes")
    |> simulate.json_body(node_input("Shire", "Place", []))
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn create_by_non_owner_is_403_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/nodes")
    |> simulate.json_body(node_input("Shire", "Place", []))
    |> helpers.auth(helpers.owner(config))
    |> router.handle_request(config, _)
  assert response.status == 403
}

pub fn create_with_fields_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let body =
    node_input("Frodo", "Person", [
      #("gender", json.string("male")),
      #("dob", json.string("Third Age 2968")),
    ])
  let node = create(config, owner, u, body)
  assert node.kind == "Person"
  assert node.fields
    == dict.from_list([
      #("gender", shared.StringValue("male")),
      #("dob", shared.StringValue("Third Age 2968")),
    ])
}

pub fn list_is_scoped_and_public_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let a = universe(config, owner, "A")
  let b = universe(config, owner, "B")
  let _ = create(config, owner, a, node_input("Shire", "Place", []))
  let _ = create(config, owner, b, node_input("Tatooine", "Place", []))
  let response =
    simulate.request(http.Get, "/universes/" <> a <> "/nodes")
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(nodes) =
    json.parse(simulate.read_body(response), decode.list(shared.node_decoder()))
  assert list.map(nodes, fn(n) { n.name }) == ["Shire"]
}

pub fn get_existing_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Earthsea")
  let created = create(config, owner, u, node_input("Roke", "Place", []))
  let response =
    simulate.request(http.Get, "/universes/" <> u <> "/nodes/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(node) =
    json.parse(simulate.read_body(response), shared.node_decoder())
  assert node == created
}

pub fn get_wrong_universe_is_404_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let a = universe(config, owner, "A")
  let b = universe(config, owner, "B")
  let created = create(config, owner, a, node_input("Shire", "Place", []))
  let response =
    simulate.request(http.Get, "/universes/" <> b <> "/nodes/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 404
}

pub fn update_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let created = create(config, owner, u, node_input("Aragorn", "Place", []))
  let body = node_input("Aragorn", "Person", [#("gender", json.string("male"))])
  let response =
    simulate.request(http.Put, "/universes/" <> u <> "/nodes/" <> created.id)
    |> simulate.json_body(body)
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(node) =
    json.parse(simulate.read_body(response), shared.node_decoder())
  assert node.kind == "Person"
  assert node.fields
    == dict.from_list([#("gender", shared.StringValue("male"))])
}

pub fn delete_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let created = create(config, owner, u, node_input("Boromir", "Place", []))
  let response =
    simulate.request(http.Delete, "/universes/" <> u <> "/nodes/" <> created.id)
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 204
  let after =
    simulate.request(http.Get, "/universes/" <> u <> "/nodes/" <> created.id)
    |> router.handle_request(config, _)
  assert after.status == 404
}

pub fn create_invalid_body_is_400_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/nodes")
    |> simulate.json_body(json.object([#("name", json.string("x"))]))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn malformed_id_is_400_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Get, "/universes/" <> u <> "/nodes/garbage")
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn wrong_method_is_405_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let u = universe(config, owner, "Middle Earth")
  let response =
    simulate.request(http.Patch, "/universes/" <> u <> "/nodes")
    |> router.handle_request(config, _)
  assert response.status == 405
}
