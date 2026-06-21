import gleam/dict
import gleam/list
import helpers
import server/db

fn universe(config: db.Config, name: String) -> String {
  helpers.owned_universe(config, name)
}

fn node(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "Place", dict.new())
  n.id
}

pub fn create_returns_edge_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let frodo = node(config, u, "Frodo")
  let shire = node(config, u, "Shire")
  let assert Ok(edge) = db.create_edge(config, u, "was_at", frodo, shire)
  assert edge.relationship == "was_at"
  assert edge.universe == u
  assert edge.from == frodo
  assert edge.to == shire
  assert edge.id != ""
}

pub fn create_round_trips_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let a = node(config, u, "A")
  let b = node(config, u, "B")
  let assert Ok(edge) = db.create_edge(config, u, "knows", a, b)
  let assert Ok(fetched) = db.get_edge(config, u, edge.id)
  assert fetched == edge
}

pub fn list_is_scoped_and_ordered_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let a1 = node(config, a, "a1")
  let a2 = node(config, a, "a2")
  let b1 = node(config, b, "b1")
  let assert Ok(_) = db.create_edge(config, a, "knows", a1, a2)
  let assert Ok(_) = db.create_edge(config, a, "born_at", a1, a2)
  let assert Ok(_) = db.create_edge(config, b, "knows", b1, b1)

  let assert Ok(edges) = db.list_edges(config, a)
  assert list.map(edges, fn(e) { e.relationship }) == ["born_at", "knows"]
}

pub fn get_wrong_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let n1 = node(config, a, "n1")
  let n2 = node(config, a, "n2")
  let assert Ok(edge) = db.create_edge(config, a, "knows", n1, n2)
  assert db.get_edge(config, b, edge.id) == Error(db.NotFound)
}

pub fn delete_removes_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let n1 = node(config, u, "n1")
  let n2 = node(config, u, "n2")
  let assert Ok(edge) = db.create_edge(config, u, "knows", n1, n2)
  let assert Ok(deleted) = db.delete_edge(config, u, edge.id)
  assert deleted.id == edge.id
  assert db.get_edge(config, u, edge.id) == Error(db.NotFound)
}

pub fn delete_wrong_universe_is_not_found_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let n1 = node(config, a, "n1")
  let n2 = node(config, a, "n2")
  let assert Ok(edge) = db.create_edge(config, a, "knows", n1, n2)
  assert db.delete_edge(config, b, edge.id) == Error(db.NotFound)
  let assert Ok(_) = db.get_edge(config, a, edge.id)
}
