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
  name: String,
  description: String,
) -> shared.Universe {
  let response =
    simulate.request(http.Post, "/universes")
    |> simulate.json_body(input(name, description))
    |> router.handle_request(config, _)
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  universe
}

pub fn create_returns_201_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Post, "/universes")
    |> simulate.json_body(input("Middle Earth", "Tolkien"))
    |> router.handle_request(config, _)
  assert response.status == 201
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  assert universe.name == "Middle Earth"
}

pub fn list_returns_universes_test() {
  let config = helpers.fresh_db()
  let _ = create(config, "Narnia", "Lewis")
  let response =
    simulate.request(http.Get, "/universes")
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(universes) =
    json.parse(
      simulate.read_body(response),
      decode.list(shared.universe_decoder()),
    )
  assert list.map(universes, fn(u) { u.name }) == ["Narnia"]
}

pub fn get_unknown_is_404_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Get, "/universes/universe:nope")
    |> router.handle_request(config, _)
  assert response.status == 404
}

pub fn get_existing_test() {
  let config = helpers.fresh_db()
  let created = create(config, "Earthsea", "Le Guin")
  let response =
    simulate.request(http.Get, "/universes/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  assert universe == created
}

pub fn update_test() {
  let config = helpers.fresh_db()
  let created = create(config, "Discworld", "draft")
  let response =
    simulate.request(http.Put, "/universes/" <> created.id)
    |> simulate.json_body(input("Discworld", "Pratchett"))
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(universe) =
    json.parse(simulate.read_body(response), shared.universe_decoder())
  assert universe.description == "Pratchett"
}

pub fn delete_test() {
  let config = helpers.fresh_db()
  let created = create(config, "Hyperion", "Simmons")
  let response =
    simulate.request(http.Delete, "/universes/" <> created.id)
    |> router.handle_request(config, _)
  assert response.status == 204

  let after =
    simulate.request(http.Get, "/universes/" <> created.id)
    |> router.handle_request(config, _)
  assert after.status == 404
}

pub fn create_invalid_body_is_400_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Post, "/universes")
    |> simulate.json_body(json.object([#("nope", json.string("x"))]))
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
