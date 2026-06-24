import gleam/dynamic/decode
import gleam/http
import gleam/json.{type Json}
import gleam/list
import helpers
import server/db
import server/router
import shared
import wisp/simulate

fn input(name: String, description: String) -> Json {
  json.object([
    #("name", json.string(name)),
    #("description", json.string(description)),
  ])
}

fn create(
  config: db.Config,
  owner: shared.User,
  name: String,
  description: String,
) -> shared.Universe {
  let response =
    simulate.request(http.Post, "/universes")
    |> simulate.json_body(input(name, description))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  universe
}

pub fn create_returns_201_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let response =
    simulate.request(http.Post, "/universes")
    |> simulate.json_body(input("Middle Earth", "Tolkien"))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 201
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  assert universe.name == "Middle Earth"
  assert universe.owner == owner.id
}

pub fn create_requires_auth_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Post, "/universes")
    |> simulate.json_body(input("Middle Earth", "Tolkien"))
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn list_is_scoped_to_owner_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let _ = create(config, owner, "Narnia", "Lewis")
  let _ = create(config, helpers.owner(config), "Discworld", "Pratchett")
  let response =
    simulate.request(http.Get, "/universes")
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(universes) =
    json.parse(
      simulate.read_body(response),
      decode.list(shared.universe_decoder()),
    )
  assert list.map(universes, fn(u) { u.name }) == ["Narnia"]
}

pub fn list_requires_auth_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Get, "/universes")
    |> router.handle_request(config, _)
  assert response.status == 401
}

pub fn get_unknown_is_404_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Get, "/universes/universe:nope")
    |> router.handle_request(config, _)
  assert response.status == 404
}

pub fn get_is_public_but_hides_owner_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let created = create(config, owner, "Earthsea", "Le Guin")
  let response =
    simulate.request(http.Get, "/universes/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  assert universe == shared.Universe(..created, owner: "")
}

pub fn get_by_owner_includes_owner_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let created = create(config, owner, "Roke", "Le Guin")
  let response =
    simulate.request(http.Get, "/universes/" <> created.id)
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  assert universe.owner == owner.id
}

pub fn update_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let created = create(config, owner, "Discworld", "draft")
  let response =
    simulate.request(http.Put, "/universes/" <> created.id)
    |> simulate.json_body(input("Discworld", "Pratchett"))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  assert universe.description == "Pratchett"
}

pub fn update_by_non_owner_is_403_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let created = create(config, owner, "Discworld", "draft")
  let response =
    simulate.request(http.Put, "/universes/" <> created.id)
    |> simulate.json_body(input("Discworld", "stolen"))
    |> helpers.auth(helpers.owner(config))
    |> router.handle_request(config, _)
  assert response.status == 403
}

pub fn delete_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let created = create(config, owner, "Hyperion", "Simmons")
  let response =
    simulate.request(http.Delete, "/universes/" <> created.id)
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 204

  let after =
    simulate.request(http.Get, "/universes/" <> created.id)
    |> router.handle_request(config, _)
  assert after.status == 404
}

pub fn create_invalid_body_is_400_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let response =
    simulate.request(http.Post, "/universes")
    |> simulate.json_body(json.object([#("nope", json.string("x"))]))
    |> helpers.auth(owner)
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn malformed_id_is_400_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Get, "/universes/garbage")
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn wrong_method_is_405_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Patch, "/universes")
    |> router.handle_request(config, _)
  assert response.status == 405
}
