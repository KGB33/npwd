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

fn person(config: db.Config, u: String, name: String, gender: String) -> String {
  let assert Ok(n) =
    db.create_node(config, u, name, "", shared.Person(shared.Date(1, 1, 1), gender))
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

pub fn returns_full_subgraph_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let frodo = person(config, u, "Frodo", "male")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "lives_in", frodo, shire)
  let g = get(config, "/universes/" <> u <> "/graph")
  assert list.length(g.nodes) == 2
  assert list.length(g.edges) == 1
}

pub fn filters_by_kind_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let frodo = person(config, u, "Frodo", "male")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "lives_in", frodo, shire)
  let g = get(config, "/universes/" <> u <> "/graph?kind=Place")
  assert list.map(g.nodes, fn(n) { n.name }) == ["Shire"]
  assert g.edges == []
}

pub fn filters_by_arbitrary_field_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = person(config, u, "Frodo", "male")
  let _ = person(config, u, "Eowyn", "female")
  let g = get(config, "/universes/" <> u <> "/graph?field=gender&value=female")
  assert list.map(g.nodes, fn(n) { n.name }) == ["Eowyn"]
}

pub fn empty_param_is_no_filter_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let _ = person(config, u, "Frodo", "male")
  let _ = place(config, u, "Shire")
  let g = get(config, "/universes/" <> u <> "/graph?kind=")
  assert list.length(g.nodes) == 2
}

pub fn is_universe_scoped_test() {
  let config = helpers.fresh_db()
  let a = universe(config, "A")
  let b = universe(config, "B")
  let _ = person(config, a, "a1", "male")
  let _ = person(config, b, "b1", "male")
  let g = get(config, "/universes/" <> a <> "/graph")
  assert list.map(g.nodes, fn(n) { n.name }) == ["a1"]
}

pub fn wrong_method_is_405_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/graph")
    |> router.handle_request(config, _)
  assert response.status == 405
}
