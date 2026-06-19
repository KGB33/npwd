import gleam/http
import gleam/json
import gleam/list
import helpers
import server/db
import server/router
import shared
import wisp/simulate

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

fn get(config: db.Config, path: String) -> shared.Graph {
  let response =
    simulate.request(http.Get, path)
    |> router.handle_request(config, _)
  assert response.status == 200
  let assert Ok(graph) =
    json.parse(simulate.read_body(response), shared.graph_decoder())
  graph
}

pub fn returns_ordered_events_with_edges_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = event(config, u, "Late", shared.Date(3019, 3, 25))
  let fall = event(config, u, "Early", shared.Date(1, 1, 1))
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "happened_at", fall, shire)

  let t = get(config, "/universes/" <> u <> "/timeline")
  assert list.map(t.nodes, fn(n) { n.name }) == ["Early", "Late"]
  assert list.map(t.edges, fn(e) { e.relationship }) == ["happened_at"]
}

pub fn is_universe_scoped_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let _ = event(config, a, "a1", shared.Date(1, 1, 1))
  let _ = event(config, b, "b1", shared.Date(1, 1, 1))
  let t = get(config, "/universes/" <> a <> "/timeline")
  assert list.map(t.nodes, fn(n) { n.name }) == ["a1"]
}

pub fn wrong_method_is_405_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/timeline")
    |> router.handle_request(config, _)
  assert response.status == 405
}
