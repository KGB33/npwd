import gleam/dict
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

  let assert Ok(g) = db.subgraph(config, u, None, None, None, None, None)
  assert names(g.nodes) == ["Frodo", "Shire"]
  assert rels(g.edges) == ["lives_in"]
}

pub fn filters_by_field_and_keeps_isolated_nodes_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = person(config, u, "Frodo", "male")
  let _ = place(config, u, "Shire")

  let assert Ok(g) =
    db.subgraph(config, u, None, None, None, Some("kind"), Some("Place"))
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

  let assert Ok(g) = db.subgraph(config, u, None, Some("knows"), None, None, None)
  assert rels(g.edges) == ["knows"]
  assert list.length(g.nodes) == 2
}

pub fn filters_by_endpoint_kind_to_named_node_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let frodo = person(config, u, "Frodo", "male")
  let sam = person(config, u, "Sam", "male")
  let fall = place(config, u, "Fall of Sauron")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "at", frodo, fall)
  let assert Ok(_) = db.create_edge(config, u, "at", sam, fall)
  let assert Ok(_) = db.create_edge(config, u, "lives_in", frodo, shire)

  let assert Ok(g) =
    db.subgraph(config, u, Some("Person"), None, Some("Fall of Sauron"), None, None)
  assert names(g.nodes) == ["Fall of Sauron", "Frodo", "Sam"]
  assert rels(g.edges) == ["at", "at"]
}

pub fn filters_by_named_endpoint_to_kind_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let gandalf = person(config, u, "Gandalf", "male")
  let frodo = person(config, u, "Frodo", "male")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "befriends", gandalf, frodo)
  let assert Ok(_) = db.create_edge(config, u, "visits", gandalf, shire)

  let assert Ok(g) =
    db.subgraph(config, u, Some("Gandalf"), Some("befriends"), Some("Person"), None, None)
  assert names(g.nodes) == ["Frodo", "Gandalf"]
  assert rels(g.edges) == ["befriends"]
}

pub fn path_and_field_intersect_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let frodo = person(config, u, "Frodo", "male")
  let eowyn = person(config, u, "Eowyn", "female")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "lives_in", frodo, shire)
  let assert Ok(_) = db.create_edge(config, u, "lives_in", eowyn, shire)

  let assert Ok(g) =
    db.subgraph(
      config,
      u,
      Some("Person"),
      None,
      Some("Place"),
      Some("gender"),
      Some("female"),
    )
  assert names(g.nodes) == ["Eowyn", "Shire"]
  assert rels(g.edges) == ["lives_in"]
}

pub fn filters_by_generic_field_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let assert Ok(_) =
    db.create_node(
      config,
      u,
      "Sting",
      "",
      shared.Generic(dict.from_list([#("material", shared.StringValue("elvish"))])),
    )
  let assert Ok(_) =
    db.create_node(
      config,
      u,
      "Glamdring",
      "",
      shared.Generic(dict.from_list([#("material", shared.StringValue("steel"))])),
    )

  let assert Ok(g) =
    db.subgraph(config, u, None, None, None, Some("material"), Some("elvish"))
  assert names(g.nodes) == ["Sting"]
}

pub fn filters_by_arbitrary_field_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = person(config, u, "Frodo", "male")
  let eowyn = person(config, u, "Eowyn", "female")
  let _ = person(config, u, "Sam", "male")

  let assert Ok(g) =
    db.subgraph(config, u, None, None, None, Some("gender"), Some("female"))
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

  let assert Ok(g) = db.subgraph(config, a, None, None, None, None, None)
  assert names(g.nodes) == ["a1", "a2"]
  assert rels(g.edges) == ["knows"]
}
