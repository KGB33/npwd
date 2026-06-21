import gleam/list
import helpers
import server/db

pub fn create_returns_universe_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let assert Ok(universe) =
    db.create_universe(config, "Middle Earth", "Tolkien", owner.id)
  assert universe.name == "Middle Earth"
  assert universe.description == "Tolkien"
  assert universe.owner == owner.id
  assert universe.id != ""
}

pub fn list_returns_created_ordered_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let assert Ok(_) = db.create_universe(config, "Narnia", "Lewis", owner.id)
  let assert Ok(_) = db.create_universe(config, "Dune", "Herbert", owner.id)

  let assert Ok(universes) = db.list_universes(config, owner.id)
  let names = list.map(universes, fn(u) { u.name })
  assert names == ["Dune", "Narnia"]
}

pub fn get_by_id_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let assert Ok(created) =
    db.create_universe(config, "Earthsea", "Le Guin", owner.id)
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
  let owner = helpers.owner(config)
  let assert Ok(created) =
    db.create_universe(config, "Discworld", "draft", owner.id)
  let assert Ok(updated) =
    db.update_universe(config, created.id, "Discworld", "Pratchett")
  assert updated.id == created.id
  assert updated.description == "Pratchett"
  assert updated.owner == owner.id
}

pub fn delete_removes_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let assert Ok(created) =
    db.create_universe(config, "Hyperion", "Simmons", owner.id)
  let assert Ok(deleted) = db.delete_universe(config, created.id)
  assert deleted.id == created.id
  assert db.get_universe(config, created.id) == Error(db.NotFound)
}

pub fn name_that_looks_numeric_stays_string_test() {
  let config = helpers.fresh_db()
  let owner = helpers.owner(config)
  let assert Ok(universe) =
    db.create_universe(config, "1984", "Orwell", owner.id)
  assert universe.name == "1984"
  let assert Ok(fetched) = db.get_universe(config, universe.id)
  assert fetched.name == "1984"
}

pub fn list_is_scoped_to_owner_test() {
  let config = helpers.fresh_db()
  let alice = helpers.owner(config)
  let bob = helpers.owner(config)
  let assert Ok(_) = db.create_universe(config, "AlicesWorld", "", alice.id)
  let assert Ok(bobs) = db.list_universes(config, bob.id)
  assert bobs == []
}

pub fn isolation_test() {
  let a = helpers.fresh_db()
  let b = helpers.fresh_db()
  let owner = helpers.owner(a)
  let assert Ok(_) = db.create_universe(a, "OnlyInA", "", owner.id)
  let assert Ok(in_b) = db.list_universes(b, helpers.owner(b).id)
  assert in_b == []
}
