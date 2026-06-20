import gleam/dict
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
  let fields = dict.from_list([#("gender", shared.StringValue(gender))])
  let assert Ok(n) = db.create_node(config, u, name, "Person", fields)
  n.id
}

fn place(config: db.Config, u: String, name: String) -> String {
  let assert Ok(n) = db.create_node(config, u, name, "Place", dict.new())
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

pub fn filters_by_endpoint_pattern_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let gandalf = person(config, u, "Gandalf", "male")
  let frodo = person(config, u, "Frodo", "male")
  let shire = place(config, u, "Shire")
  let assert Ok(_) = db.create_edge(config, u, "befriends", gandalf, frodo)
  let assert Ok(_) = db.create_edge(config, u, "visits", gandalf, shire)
  let g = get(config, "/universes/" <> u <> "/graph?from=Gandalf&to=Person")
  assert list.map(g.nodes, fn(n) { n.name }) == ["Frodo", "Gandalf"]
  assert list.map(g.edges, fn(e) { e.relationship }) == ["befriends"]
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
  let g = get(config, "/universes/" <> u <> "/graph?from=")
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

pub fn malformed_universe_is_400_test() {
  let config = helpers.fresh_db()
  let response =
    simulate.request(http.Get, "/universes/garbage/graph")
    |> router.handle_request(config, _)
  assert response.status == 400
}

pub fn wrong_method_is_405_test() {
  let config = helpers.fresh_db()
  let u = universe(config, "Middle Earth")
  let response =
    simulate.request(http.Post, "/universes/" <> u <> "/graph")
    |> router.handle_request(config, _)
  assert response.status == 405
}
