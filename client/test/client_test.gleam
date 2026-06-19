import client
import gleam/json
import gleam/option.{None, Some}
import gleeunit
import lustre/dev/query
import lustre/dev/simulate
import rsvp
import shared

pub fn main() -> Nil {
  gleeunit.main()
}

fn model() -> client.Model {
  client.Model(
    universes: client.Loading,
    form: client.Form("", ""),
    editing: None,
    selected: None,
    nodes: client.Loading,
    node_form: client.NodeForm("", "", client.PlaceForm),
    editing_node: None,
    edges: client.Loading,
    edge_form: client.EdgeForm("", "", ""),
    graph: client.Loading,
    graph_filter: client.GraphFilter("", "", "", ""),
    timeline: client.Loading,
  )
}

fn universe(id: String, name: String) -> shared.Universe {
  shared.Universe(id, name, "")
}

fn node(id: String, name: String, kind: shared.NodeKind) -> shared.Node {
  shared.Node(id, "u:1", kind, name, "")
}

fn edge(id: String, relationship: String) -> shared.Edge {
  shared.Edge(id, "u:1", relationship, "node:1", "node:2")
}

pub fn loaded_sets_universes_test() {
  let #(m, _) =
    client.update(model(), client.UniversesLoaded(Ok([universe("u:1", "A")])))
  assert m.universes == client.Loaded([universe("u:1", "A")])
}

pub fn load_error_sets_failed_test() {
  let #(m, _) =
    client.update(model(), client.UniversesLoaded(Error(rsvp.BadBody)))
  assert m.universes == client.Failed
}

pub fn name_change_updates_form_test() {
  let #(m, _) = client.update(model(), client.NameChanged("Dune"))
  assert m.form.name == "Dune"
}

pub fn edit_started_fills_form_test() {
  let #(m, _) =
    client.update(model(), client.EditStarted(universe("u:7", "Narnia")))
  assert m.editing == Some("u:7")
  assert m.form.name == "Narnia"
}

pub fn edit_cancelled_clears_form_test() {
  let editing =
    client.Model(..model(), form: client.Form("x", "y"), editing: Some("u:7"))
  let #(m, _) = client.update(editing, client.EditCancelled)
  assert m.editing == None
  assert m.form == client.Form("", "")
}

pub fn saved_clears_form_test() {
  let editing =
    client.Model(..model(), form: client.Form("x", "y"), editing: Some("u:7"))
  let #(m, _) = client.update(editing, client.Saved(Ok(universe("u:7", "x"))))
  assert m.editing == None
  assert m.form == client.Form("", "")
}

// ---- M2: node management ----

pub fn selecting_universe_sets_selected_and_loads_test() {
  let #(m, _) =
    client.update(model(), client.UniverseSelected(universe("u:1", "A")))
  assert m.selected == Some(universe("u:1", "A"))
  assert m.nodes == client.Loading
}

pub fn deselect_clears_selected_test() {
  let opened = client.Model(..model(), selected: Some(universe("u:1", "A")))
  let #(m, _) = client.update(opened, client.UniverseDeselected)
  assert m.selected == None
}

pub fn nodes_loaded_sets_nodes_test() {
  let n = node("node:1", "Shire", shared.Place)
  let #(m, _) = client.update(model(), client.NodesLoaded(Ok([n])))
  assert m.nodes == client.Loaded([n])
}

pub fn kind_selected_switches_form_test() {
  let #(m, _) = client.update(model(), client.KindSelected("Person"))
  assert m.node_form.kind == client.PersonForm("", "", "", "")
}

pub fn date_changes_apply_to_person_test() {
  let #(m, _) =
    model()
    |> client.update(client.KindSelected("Person"))
    |> fn(pair) { client.update(pair.0, client.YearChanged("2968")) }
  assert m.node_form.kind == client.PersonForm("2968", "", "", "")
}

pub fn generic_field_edit_test() {
  let #(m, _) =
    model()
    |> client.update(client.KindSelected("Generic"))
    |> fn(p) { client.update(p.0, client.GenericKeyChanged(0, "faction")) }
  let #(m, _) = client.update(m, client.GenericValueChanged(0, "fellowship"))
  assert m.node_form.kind == client.GenericForm([#("faction", "fellowship")])
}

pub fn generic_add_and_remove_test() {
  let #(m, _) =
    model()
    |> client.update(client.KindSelected("Generic"))
    |> fn(p) { client.update(p.0, client.GenericFieldAdded) }
  assert m.node_form.kind == client.GenericForm([#("", ""), #("", "")])
  let #(m, _) = client.update(m, client.GenericFieldRemoved(0))
  assert m.node_form.kind == client.GenericForm([#("", "")])
}

pub fn node_edit_started_fills_form_test() {
  let n =
    node("node:1", "Frodo", shared.Person(shared.Date(2968, 9, 22), "male"))
  let #(m, _) = client.update(model(), client.NodeEditStarted(n))
  assert m.editing_node == Some("node:1")
  assert m.node_form.name == "Frodo"
  assert m.node_form.kind == client.PersonForm("2968", "9", "22", "male")
}

pub fn node_body_person_test() {
  let form =
    client.NodeForm(
      "Frodo",
      "Ring-bearer",
      client.PersonForm("2968", "9", "22", "male"),
    )
  let expected =
    json.object([
      #("name", json.string("Frodo")),
      #("description", json.string("Ring-bearer")),
      #("kind", json.string("Person")),
      #("dob", shared.date_to_json(shared.Date(2968, 9, 22))),
      #("gender", json.string("male")),
    ])
  assert json.to_string(client.node_body(form)) == json.to_string(expected)
}

pub fn node_body_generic_drops_empty_keys_test() {
  let form =
    client.NodeForm(
      "Sting",
      "",
      client.GenericForm([#("glows", "true"), #("", "junk")]),
    )
  let expected =
    json.object([
      #("name", json.string("Sting")),
      #("description", json.string("")),
      #("kind", json.string("Generic")),
      #("fields", json.object([#("glows", json.string("true"))])),
    ])
  assert json.to_string(client.node_body(form)) == json.to_string(expected)
}

// ---- M3: edge management ----

pub fn selecting_universe_loads_edges_test() {
  let #(m, _) =
    client.update(model(), client.UniverseSelected(universe("u:1", "A")))
  assert m.edges == client.Loading
}

pub fn edges_loaded_sets_edges_test() {
  let e = edge("relationship:1", "knows")
  let #(m, _) = client.update(model(), client.EdgesLoaded(Ok([e])))
  assert m.edges == client.Loaded([e])
}

pub fn edge_form_changes_apply_test() {
  let #(m, _) =
    model()
    |> client.update(client.EdgeRelationshipChanged("was_at"))
    |> fn(p) { client.update(p.0, client.EdgeFromSelected("node:1")) }
  let #(m, _) = client.update(m, client.EdgeToSelected("node:2"))
  assert m.edge_form == client.EdgeForm("was_at", "node:1", "node:2")
}

pub fn edge_saved_clears_form_test() {
  let opened =
    client.Model(
      ..model(),
      selected: Some(universe("u:1", "A")),
      edge_form: client.EdgeForm("knows", "node:1", "node:2"),
    )
  let #(m, _) =
    client.update(opened, client.EdgeSaved(Ok(edge("relationship:1", "knows"))))
  assert m.edge_form == client.EdgeForm("", "", "")
}

pub fn edge_body_test() {
  let form = client.EdgeForm("was_at", "node:1", "node:2")
  let expected =
    json.object([
      #("relationship", json.string("was_at")),
      #("from", json.string("node:1")),
      #("to", json.string("node:2")),
    ])
  assert json.to_string(client.edge_body(form)) == json.to_string(expected)
}

pub fn edge_submittable_requires_from_and_to_test() {
  assert client.edge_submittable(client.EdgeForm("knows", "node:1", "node:2"))
  assert !client.edge_submittable(client.EdgeForm("knows", "", "node:2"))
  assert !client.edge_submittable(client.EdgeForm("knows", "node:1", ""))
  assert !client.edge_submittable(client.EdgeForm("knows", "", ""))
}

pub fn edge_selects_have_placeholder_option_test() {
  let sim =
    start()
    |> simulate.message(client.UniverseSelected(universe("u:1", "A")))
    |> simulate.message(
      client.NodesLoaded(Ok([node("node:1", "Alice", shared.Place)])),
    )
  assert query.has(
    simulate.view(sim),
    query.and(query.tag("option"), query.attribute("value", "")),
  )
}

// ---- M4: filterable graph ----

pub fn selecting_universe_loads_graph_test() {
  let #(m, _) =
    client.update(model(), client.UniverseSelected(universe("u:1", "A")))
  assert m.graph == client.Loading
  assert m.graph_filter == client.GraphFilter("", "", "", "")
}

pub fn graph_loaded_sets_graph_test() {
  let g = shared.Graph([node("node:1", "Shire", shared.Place)], [])
  let #(m, _) = client.update(model(), client.GraphLoaded(Ok(g)))
  assert m.graph == client.Loaded(g)
}

pub fn graph_filter_changes_apply_test() {
  let #(m, _) =
    model()
    |> client.update(client.GraphKindChanged("Person"))
    |> fn(p) { client.update(p.0, client.GraphRelationshipChanged("knows")) }
  let #(m, _) =
    m
    |> client.update(client.GraphFieldChanged("gender"))
    |> fn(p) { client.update(p.0, client.GraphValueChanged("female")) }
  assert m.graph_filter == client.GraphFilter("Person", "knows", "gender", "female")
}

pub fn graph_filter_applied_reloads_test() {
  let opened = client.Model(..model(), selected: Some(universe("u:1", "A")))
  let #(m, _) = client.update(opened, client.GraphFilterApplied)
  assert m.graph == client.Loading
}

pub fn graph_query_only_includes_set_fields_test() {
  assert client.graph_query(client.GraphFilter("", "", "", "")) == ""
  assert client.graph_query(client.GraphFilter("Person", "", "gender", "male"))
    == "?kind=Person&field=gender&value=male"
}

// ---- M5: timeline ----

pub fn selecting_universe_loads_timeline_test() {
  let #(m, _) =
    client.update(model(), client.UniverseSelected(universe("u:1", "A")))
  assert m.timeline == client.Loading
}

pub fn timeline_loaded_sets_timeline_test() {
  let ev =
    node("node:e1", "Fall", shared.Event(shared.Date(3019, 3, 25)))
  let g = shared.Graph([ev], [])
  let #(m, _) = client.update(model(), client.TimelineLoaded(Ok(g)))
  assert m.timeline == client.Loaded(g)
}

pub fn selected_view_shows_timeline_test() {
  let ev =
    node("node:e1", "Fall of Sauron", shared.Event(shared.Date(3019, 3, 25)))
  let shire = node("node:p1", "Shire", shared.Place)
  let link =
    shared.Edge("relationship:1", "u:1", "happened_at", "node:e1", "node:p1")
  let g = shared.Graph([ev], [link])
  let sim =
    start()
    |> simulate.message(client.UniverseSelected(universe("u:1", "Middle Earth")))
    |> simulate.message(client.NodesLoaded(Ok([ev, shire])))
    |> simulate.message(client.TimelineLoaded(Ok(g)))
  assert query.has(simulate.view(sim), query.test_id("timeline"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("timeline-name"), query.text("Fall of Sauron")),
  )
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("timeline-when"), query.text("3019-3-25")),
  )
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("timeline-link"), query.text("happened_at → Shire")),
  )
}

fn start() {
  simulate.application(client.init, client.update, client.view)
  |> simulate.start(Nil)
}

pub fn initial_view_is_loading_test() {
  let sim = start()
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("status"), query.text("Loading universes…")),
  )
}

pub fn loaded_view_lists_names_test() {
  let sim =
    start()
    |> simulate.message(
      client.UniversesLoaded(
        Ok([universe("u:1", "Narnia"), universe("u:2", "Dune")]),
      ),
    )
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("universe-name"), query.text("Narnia")),
  )
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("universe-name"), query.text("Dune")),
  )
}

pub fn failed_view_shows_error_test() {
  let sim =
    start()
    |> simulate.message(client.UniversesLoaded(Error(rsvp.BadBody)))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("status"), query.text("Could not load universes")),
  )
}

pub fn typing_name_updates_model_test() {
  let sim =
    start()
    |> simulate.input(query.element(query.test_id("name-input")), "Arrakis")
  assert simulate.model(sim).form.name == "Arrakis"
}

pub fn selected_view_shows_node_form_and_list_test() {
  let n = node("node:1", "Shire", shared.Place)
  let sim =
    start()
    |> simulate.message(
      client.UniverseSelected(universe("u:1", "Middle Earth")),
    )
    |> simulate.message(client.NodesLoaded(Ok([n])))
  assert query.has(simulate.view(sim), query.test_id("node-form"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("node-name"), query.text("Shire")),
  )
}

pub fn selected_view_shows_graph_filter_and_container_test() {
  let g = shared.Graph([node("node:1", "Shire", shared.Place)], [])
  let sim =
    start()
    |> simulate.message(
      client.UniverseSelected(universe("u:1", "Middle Earth")),
    )
    |> simulate.message(client.GraphLoaded(Ok(g)))
  assert query.has(simulate.view(sim), query.test_id("graph-filter"))
  assert query.has(simulate.view(sim), query.test_id("graph"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("graph-summary"), query.text("1 nodes, 0 edges")),
  )
}

pub fn selected_view_shows_edge_form_and_list_test() {
  let e = edge("relationship:1", "was_at")
  let sim =
    start()
    |> simulate.message(
      client.UniverseSelected(universe("u:1", "Middle Earth")),
    )
    |> simulate.message(client.EdgesLoaded(Ok([e])))
  assert query.has(simulate.view(sim), query.test_id("edge-form"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("edge-relationship"), query.text("was_at")),
  )
}
