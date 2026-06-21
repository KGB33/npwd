import gleam/dict
import gleam/list
import helpers
import server/db
import shared

fn universe(config: db.Config, name: String) -> String {
  helpers.owned_universe(config, name)
}

fn event(config: db.Config, u: String, name: String, when: String) -> String {
  let fields = dict.from_list([#("when", shared.StringValue(when))])
  let assert Ok(n) = db.create_node(config, u, name, "Event", fields)
  n.id
}

fn place(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "Place", dict.new())
  n.id
}

fn names(nodes: List(shared.Node)) -> List(String) {
  list.map(nodes, fn(n) { n.name })
}

pub fn orders_by_when_and_excludes_dateless_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = event(config, u, "Late", "3019-03-25")
  let _ = event(config, u, "Early", "0001-01-01")
  let _ = event(config, u, "Mid", "1000-06-15")
  let _ = place(config, u, "Shire")

  let assert Ok(t) = db.timeline(config, u)
  assert names(t.nodes) == ["Early", "Mid", "Late"]
}

pub fn includes_incident_edges_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let fall = event(config, u, "Fall of Sauron", "3019-03-25")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "happened_at", fall, shire)

  let assert Ok(t) = db.timeline(config, u)
  assert names(t.nodes) == ["Fall of Sauron"]
  assert list.map(t.edges, fn(e) { e.relationship }) == ["happened_at"]
}

pub fn is_universe_scoped_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let _ = event(config, a, "a1", "0001-01-01")
  let _ = event(config, b, "b1", "0001-01-01")

  let assert Ok(t) = db.timeline(config, a)
  assert names(t.nodes) == ["a1"]
}
