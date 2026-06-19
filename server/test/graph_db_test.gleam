import gleam/list
import gleam/option.{None, Some}
import helpers
import server/db
import shared

fn universe(config: db.Config, name: String) -> String {
  let assert Ok(u) = db.create_universe(config, name, "")
  u.id
}

fn person(config: db.Config, u: String, name: String, gender: String) -> String {
  let assert Ok(n) =
    db.create_node(config, u, name, "", shared.Person(shared.Date(1, 1, 1), gender))
  n.id
}

fn place(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "", shared.Place)
  n.id
}

fn names(nodes: List(shared.Node)) -> List(String) {
  list.map(nodes, fn(n) { n.name })
}

fn rels(edges: List(shared.Edge)) -> List(String) {
  list.map(edges, fn(e) { e.relationship })
}

pub fn all_returns_full_subgraph_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let frodo = person(config, u, "Frodo", "male")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "lives_in", frodo, shire)

  let assert Ok(g) = db.subgraph(config, u, None, None, None, None)
  assert names(g.nodes) == ["Frodo", "Shire"]
  assert rels(g.edges) == ["lives_in"]
}

pub fn filters_by_kind_and_prunes_dangling_edges_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let frodo = person(config, u, "Frodo", "male")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "lives_in", frodo, shire)

  let assert Ok(g) = db.subgraph(config, u, Some("Place"), None, None, None)
  assert names(g.nodes) == ["Shire"]
  assert g.edges == []
}

pub fn filters_by_relationship_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let a = person(config, u, "A", "male")
  let b = person(config, u, "B", "male")
  let assert Ok(_) = db.create_edge(config, u, "knows", a, b)
  let assert Ok(_) = db.create_edge(config, u, "hates", a, b)

  let assert Ok(g) = db.subgraph(config, u, None, Some("knows"), None, None)
  assert rels(g.edges) == ["knows"]
  assert list.length(g.nodes) == 2
}

pub fn filters_by_arbitrary_field_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = person(config, u, "Frodo", "male")
  let eowyn = person(config, u, "Eowyn", "female")
  let _ = person(config, u, "Sam", "male")

  let assert Ok(g) =
    db.subgraph(config, u, None, None, Some("gender"), Some("female"))
  assert names(g.nodes) == ["Eowyn"]
  let assert [n] = g.nodes
  assert n.id == eowyn
}

pub fn is_universe_scoped_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let a1 = person(config, a, "a1", "male")
  let a2 = person(config, a, "a2", "male")
  let _ = person(config, b, "b1", "male")
  let assert Ok(_) = db.create_edge(config, a, "knows", a1, a2)

  let assert Ok(g) = db.subgraph(config, a, None, None, None, None)
  assert names(g.nodes) == ["a1", "a2"]
  assert rels(g.edges) == ["knows"]
}
