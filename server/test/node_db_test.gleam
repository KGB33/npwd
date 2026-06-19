import gleam/dict
import gleam/list
import helpers
import server/db
import shared

fn universe(config: db.Config, name: String) -> String {
  let assert Ok(u) = db.create_universe(config, name, "")
  u.id
}

pub fn create_returns_node_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(node) =
    db.create_node(config, u, "Shire", "Hobbit homeland", shared.Place)
  assert node.name == "Shire"
  assert node.universe == u
  assert node.kind == shared.Place
  assert node.id != ""
}

pub fn create_person_round_trips_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let kind = shared.Person(shared.Date(2968, 9, 22), "male")
  let assert Ok(node) =
    db.create_node(config, u, "Frodo", "Ring-bearer", kind)
  assert node.kind == kind
  let assert Ok(fetched) = db.get_node(config, u, node.id)
  assert fetched == node
}

pub fn create_generic_round_trips_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let fields =
    dict.from_list([
      #("glows", shared.BoolValue(True)),
      #("length", shared.IntValue(22)),
    ])
  let kind = shared.Generic(fields)
  let assert Ok(node) = db.create_node(config, u, "Sting", "A sword", kind)
  let assert Ok(fetched) = db.get_node(config, u, node.id)
  assert fetched.kind == kind
}

pub fn list_is_scoped_and_ordered_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let assert Ok(_) = db.create_node(config, a, "Shire", "", shared.Place)
  let assert Ok(_) = db.create_node(config, a, "Bree", "", shared.Place)
  let assert Ok(_) = db.create_node(config, b, "Tatooine", "", shared.Place)

  let assert Ok(nodes) = db.list_nodes(config, a)
  assert list.map(nodes, fn(n) { n.name }) == ["Bree", "Shire"]
}

pub fn get_wrong_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let assert Ok(node) = db.create_node(config, a, "Shire", "", shared.Place)
  assert db.get_node(config, b, node.id) == Error(db.NotFound)
}

pub fn update_changes_kind_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(created) =
    db.create_node(config, u, "Aragorn", "ranger", shared.Place)
  let kind = shared.Person(shared.Date(2931, 3, 1), "male")
  let assert Ok(updated) =
    db.update_node(config, u, created.id, "Aragorn", "king", kind)
  assert updated.id == created.id
  assert updated.kind == kind
  assert updated.description == "king"
}

pub fn delete_removes_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(created) =
    db.create_node(config, u, "Boromir", "", shared.Place)
  let assert Ok(deleted) = db.delete_node(config, u, created.id)
  assert deleted.id == created.id
  assert db.get_node(config, u, created.id) == Error(db.NotFound)
}

pub fn delete_wrong_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let assert Ok(node) = db.create_node(config, a, "Shire", "", shared.Place)
  assert db.delete_node(config, b, node.id) == Error(db.NotFound)
  let assert Ok(_) = db.get_node(config, a, node.id)
}
