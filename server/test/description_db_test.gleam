import gleam/dict
import gleam/list
import helpers
import server/db
import shared

fn universe(config: db.Config, name: String) -> String {
  helpers.owned_universe(config, name)
}

fn node(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "Place", dict.new())
  n.id
}

fn bodies(ds: List(shared.Description)) -> List(String) {
  list.map(ds, fn(d) { d.body })
}

pub fn create_appends_and_lists_in_order_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let assert Ok(first) = db.create_description(config, u, n, "It is green.")
  let assert Ok(second) =
    db.create_description(config, u, n, "Hobbits live here.")
  assert first.position == 0
  assert second.position == 1

  let assert Ok(ds) = db.list_descriptions(config, u, n)
  assert bodies(ds) == ["It is green.", "Hobbits live here."]
}

pub fn update_changes_body_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let assert Ok(created) = db.create_description(config, u, n, "old")
  let assert Ok(updated) = db.update_description(config, u, created.id, "new")
  assert updated.id == created.id
  assert updated.body == "new"
}

pub fn delete_removes_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let assert Ok(created) = db.create_description(config, u, n, "gone")
  let assert Ok(deleted) = db.delete_description(config, u, created.id)
  assert deleted.id == created.id
  let assert Ok(ds) = db.list_descriptions(config, u, n)
  assert ds == []
}

pub fn create_on_node_in_other_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let n = node(config, a, "Shire")
  assert db.create_description(config, b, n, "x") == Error(db.NotFound)
}

pub fn list_is_scoped_to_universe_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let n = node(config, a, "Shire")
  let assert Ok(_) = db.create_description(config, a, n, "x")
  let assert Ok(ds) = db.list_descriptions(config, b, n)
  assert ds == []
}

pub fn update_in_other_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let n = node(config, a, "Shire")
  let assert Ok(created) = db.create_description(config, a, n, "x")
  assert db.update_description(config, b, created.id, "y") == Error(db.NotFound)
}

pub fn body_with_plus_round_trips_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n = node(config, u, "Shire")
  let assert Ok(d) = db.create_description(config, u, n, "1 + 1 = 2")
  assert d.body == "1 + 1 = 2"
  let assert Ok(ds) = db.list_descriptions(config, u, n)
  assert bodies(ds) == ["1 + 1 = 2"]
}
