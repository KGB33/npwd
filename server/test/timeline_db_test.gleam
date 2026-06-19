import gleam/list
import helpers
import server/db
import shared

fn universe(config: db.Config, name: String) -> String {
  let assert Ok(u) = db.create_universe(config, name, "")
  u.id
}

fn event(config: db.Config, u: String, name: String, when: shared.Date) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "", shared.Event(when))
  n.id
}

fn place(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "", shared.Place)
  n.id
}

fn names(nodes: List(shared.Node)) -> List(String) {
  list.map(nodes, fn(n) { n.name })
}

pub fn orders_events_by_when_and_excludes_non_events_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = event(config, u, "Late", shared.Date(3019, 3, 25))
  let _ = event(config, u, "Early", shared.Date(1, 1, 1))
  let _ = event(config, u, "Mid", shared.Date(1000, 6, 15))
  let _ = place(config, u, "Shire")

  let assert Ok(t) = db.timeline(config, u)
  assert names(t.nodes) == ["Early", "Mid", "Late"]
}

pub fn includes_incident_edges_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let fall = event(config, u, "Fall of Sauron", shared.Date(3019, 3, 25))
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
  let _ = event(config, a, "a1", shared.Date(1, 1, 1))
  let _ = event(config, b, "b1", shared.Date(1, 1, 1))

  let assert Ok(t) = db.timeline(config, a)
  assert names(t.nodes) == ["a1"]
}
