import gleam/dict
import gleam/list
import helpers
import server/db
import shared

fn universe(config: db.Config, name: String) -> String {
  helpers.owned_universe(config, name)
}

pub fn create_returns_node_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(node) =
    db.create_node(config, u, "Shire", "Place", dict.new())
  assert node.name == "Shire"
  assert node.universe == u
  assert node.kind == "Place"
  assert node.fields == dict.new()
  assert node.id != ""
}

pub fn create_with_fields_round_trips_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let fields =
    dict.from_list([
      #("gender", shared.StringValue("male")),
      #("dob", shared.StringValue("Third Age 2968")),
    ])
  let assert Ok(node) = db.create_node(config, u, "Frodo", "Person", fields)
  assert node.kind == "Person"
  assert node.fields == fields
  let assert Ok(fetched) = db.get_node(config, u, node.id)
  assert fetched == node
}

pub fn create_typed_fields_round_trip_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let fields =
    dict.from_list([
      #("glows", shared.BoolValue(True)),
      #("length", shared.IntValue(22)),
    ])
  let assert Ok(node) = db.create_node(config, u, "Sting", "Generic", fields)
  let assert Ok(fetched) = db.get_node(config, u, node.id)
  assert fetched.fields == fields
}

pub fn list_is_scoped_and_ordered_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let assert Ok(_) = db.create_node(config, a, "Shire", "Place", dict.new())
  let assert Ok(_) = db.create_node(config, a, "Bree", "Place", dict.new())
  let assert Ok(_) = db.create_node(config, b, "Tatooine", "Place", dict.new())

  let assert Ok(nodes) = db.list_nodes(config, a)
  assert list.map(nodes, fn(n) { n.name }) == ["Bree", "Shire"]
}

pub fn get_wrong_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let assert Ok(node) = db.create_node(config, a, "Shire", "Place", dict.new())
  assert db.get_node(config, b, node.id) == Error(db.NotFound)
}

pub fn update_changes_kind_and_fields_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(created) =
    db.create_node(config, u, "Aragorn", "Place", dict.new())
  let fields = dict.from_list([#("gender", shared.StringValue("male"))])
  let assert Ok(updated) =
    db.update_node(config, u, created.id, "Aragorn", "Person", fields)
  assert updated.id == created.id
  assert updated.kind == "Person"
  assert updated.fields == fields
}

pub fn delete_removes_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(created) =
    db.create_node(config, u, "Boromir", "Place", dict.new())
  let assert Ok(deleted) = db.delete_node(config, u, created.id)
  assert deleted.id == created.id
  assert db.get_node(config, u, created.id) == Error(db.NotFound)
}

pub fn delete_wrong_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let assert Ok(node) = db.create_node(config, a, "Shire", "Place", dict.new())
  assert db.delete_node(config, b, node.id) == Error(db.NotFound)
  let assert Ok(_) = db.get_node(config, a, node.id)
}
