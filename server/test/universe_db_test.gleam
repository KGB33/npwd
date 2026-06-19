import gleam/list
import helpers
import server/db

pub fn create_returns_universe_test() {
  let config = helpers.fresh_db()
  let assert Ok(universe) =
    db.create_universe(config, "Middle Earth", "Tolkien")
  assert universe.name == "Middle Earth"
  assert universe.description == "Tolkien"
  assert universe.id != ""
}

pub fn list_returns_created_ordered_test() {
  let config = helpers.fresh_db()
  let assert Ok(_) = db.create_universe(config, "Narnia", "Lewis")
  let assert Ok(_) = db.create_universe(config, "Dune", "Herbert")

  let assert Ok(universes) = db.list_universes(config)
  let names = list.map(universes, fn(u) { u.name })
  assert names == ["Dune", "Narnia"]
}

pub fn get_by_id_test() {
  let config = helpers.fresh_db()
  let assert Ok(created) = db.create_universe(config, "Earthsea", "Le Guin")
  let assert Ok(fetched) = db.get_universe(config, created.id)
  assert fetched == created
}

pub fn get_unknown_is_not_found_test() {
  let config = helpers.fresh_db()
  assert db.get_universe(config, "universe:does_not_exist")
    == Error(db.NotFound)
}

pub fn update_changes_fields_test() {
  let config = helpers.fresh_db()
  let assert Ok(created) = db.create_universe(config, "Discworld", "draft")
  let assert Ok(updated) =
    db.update_universe(config, created.id, "Discworld", "Pratchett")
  assert updated.id == created.id
  assert updated.description == "Pratchett"
}

pub fn delete_removes_test() {
  let config = helpers.fresh_db()
  let assert Ok(created) = db.create_universe(config, "Hyperion", "Simmons")
  let assert Ok(deleted) = db.delete_universe(config, created.id)
  assert deleted.id == created.id
  assert db.get_universe(config, created.id) == Error(db.NotFound)
}

pub fn name_that_looks_numeric_stays_string_test() {
  let config = helpers.fresh_db()
  let assert Ok(universe) = db.create_universe(config, "1984", "Orwell")
  assert universe.name == "1984"
  let assert Ok(fetched) = db.get_universe(config, universe.id)
  assert fetched.name == "1984"
}

pub fn isolation_test() {
  let a = helpers.fresh_db()
  let b = helpers.fresh_db()
  let assert Ok(_) = db.create_universe(a, "OnlyInA", "")
  let assert Ok(in_b) = db.list_universes(b)
  assert in_b == []
}
