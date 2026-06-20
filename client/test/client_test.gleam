import client
import client/model
import client/view
import gleam/dict
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

fn blank() -> model.Model {
  model.Model(
    universes: model.Loading,
    form: model.Form("", ""),
    editing: None,
    selected: None,
    nodes: model.Loading,
    node_form: model.NodeForm("", "", []),
    editing_node: None,
    descriptions: model.Loaded([]),
    description_form: "",
    edges: model.Loading,
    edge_form: model.EdgeForm("", "", ""),
    graph: model.Loading,
    graph_filter: model.GraphFilter("", "", "", "", ""),
    timeline: model.Loading,
  )
}

fn universe(id: String, name: String) -> shared.Universe {
  shared.Universe(id, name, "")
}

fn node(id: String, name: String, kind: String) -> shared.Node {
  shared.Node(id, "u:1", name, kind, dict.new())
}

fn node_f(
  id: String,
  name: String,
  kind: String,
  fields: List(#(String, shared.FieldValue)),
) -> shared.Node {
  shared.Node(id, "u:1", name, kind, dict.from_list(fields))
}

fn edge(id: String, relationship: String) -> shared.Edge {
  shared.Edge(id, "u:1", relationship, "node:1", "node:2")
}

pub fn loaded_sets_universes_test() {
  let #(m, _) =
    client.update(blank(), model.UniversesLoaded(Ok([universe("u:1", "A")])))
  assert m.universes == model.Loaded([universe("u:1", "A")])
}

pub fn load_error_sets_failed_test() {
  let #(m, _) =
    client.update(blank(), model.UniversesLoaded(Error(rsvp.BadBody)))
  assert m.universes == model.Failed
}

pub fn name_change_updates_form_test() {
  let #(m, _) = client.update(blank(), model.NameChanged("Dune"))
  assert m.form.name == "Dune"
}

pub fn edit_started_fills_form_test() {
  let #(m, _) =
    client.update(blank(), model.EditStarted(universe("u:7", "Narnia")))
  assert m.editing == Some("u:7")
  assert m.form.name == "Narnia"
}

pub fn edit_cancelled_clears_form_test() {
  let editing =
    model.Model(..blank(), form: model.Form("x", "y"), editing: Some("u:7"))
  let #(m, _) = client.update(editing, model.EditCancelled)
  assert m.editing == None
  assert m.form == model.Form("", "")
}

pub fn saved_clears_form_test() {
  let editing =
    model.Model(..blank(), form: model.Form("x", "y"), editing: Some("u:7"))
  let #(m, _) = client.update(editing, model.Saved(Ok(universe("u:7", "x"))))
  assert m.editing == None
  assert m.form == model.Form("", "")
}

// ---- node management ----

pub fn selecting_universe_sets_selected_and_loads_test() {
  let #(m, _) =
    client.update(blank(), model.UniverseSelected(universe("u:1", "A")))
  assert m.selected == Some(universe("u:1", "A"))
  assert m.nodes == model.Loading
}

pub fn deselect_clears_selected_test() {
  let opened = model.Model(..blank(), selected: Some(universe("u:1", "A")))
  let #(m, _) = client.update(opened, model.UniverseDeselected)
  assert m.selected == None
}

pub fn nodes_loaded_sets_nodes_test() {
  let n = node("node:1", "Shire", "Place")
  let #(m, _) = client.update(blank(), model.NodesLoaded(Ok([n])))
  assert m.nodes == model.Loaded([n])
}

pub fn kind_change_updates_form_test() {
  let #(m, _) = client.update(blank(), model.NodeKindChanged("Person"))
  assert m.node_form.kind == "Person"
}

pub fn generic_field_edit_test() {
  let #(m, _) =
    blank()
    |> client.update(model.GenericFieldAdded)
    |> fn(p) { client.update(p.0, model.GenericKeyChanged(0, "faction")) }
  let #(m, _) = client.update(m, model.GenericValueChanged(0, "fellowship"))
  assert m.node_form.fields == [#("faction", "fellowship")]
}

pub fn generic_add_and_remove_test() {
  let #(m, _) =
    blank()
    |> client.update(model.GenericFieldAdded)
    |> fn(p) { client.update(p.0, model.GenericFieldAdded) }
  assert m.node_form.fields == [#("", ""), #("", "")]
  let #(m, _) = client.update(m, model.GenericFieldRemoved(0))
  assert m.node_form.fields == [#("", "")]
}

pub fn node_edit_started_fills_form_test() {
  let n =
    node_f("node:1", "Frodo", "Person", [#("gender", shared.StringValue("male"))])
  let #(m, _) = client.update(blank(), model.NodeEditStarted(n))
  assert m.editing_node == Some("node:1")
  assert m.node_form.name == "Frodo"
  assert m.node_form.kind == "Person"
  assert m.node_form.fields == [#("gender", "male")]
  assert m.descriptions == model.Loading
}

pub fn node_body_test() {
  let form = model.NodeForm("Frodo", "Person", [#("gender", "male")])
  let expected =
    json.object([
      #("name", json.string("Frodo")),
      #("kind", json.string("Person")),
      #("fields", json.object([#("gender", json.string("male"))])),
    ])
  assert json.to_string(model.node_body(form)) == json.to_string(expected)
}

pub fn node_body_drops_empty_keys_test() {
  let form =
    model.NodeForm("Sting", "Generic", [#("glows", "true"), #("", "junk")])
  let expected =
    json.object([
      #("name", json.string("Sting")),
      #("kind", json.string("Generic")),
      #("fields", json.object([#("glows", json.string("true"))])),
    ])
  assert json.to_string(model.node_body(form)) == json.to_string(expected)
}

// ---- descriptions ----

fn editing(node_id: String) -> model.Model {
  model.Model(
    ..blank(),
    selected: Some(universe("u:1", "A")),
    editing_node: Some(node_id),
  )
}

pub fn descriptions_loaded_sets_descriptions_test() {
  let d = shared.Description("description:1", "node:1", 0, "It is green.")
  let #(m, _) =
    client.update(blank(), model.DescriptionsLoaded(Ok([d])))
  assert m.descriptions == model.Loaded([d])
}

pub fn description_body_change_updates_form_test() {
  let #(m, _) = client.update(blank(), model.DescriptionBodyChanged("hello"))
  assert m.description_form == "hello"
}

pub fn description_saved_clears_form_test() {
  let m0 = model.Model(..editing("node:1"), description_form: "draft")
  let d = shared.Description("description:1", "node:1", 0, "draft")
  let #(m, _) = client.update(m0, model.DescriptionSaved(Ok(d)))
  assert m.description_form == ""
}

pub fn empty_description_does_not_submit_test() {
  let m0 = model.Model(..editing("node:1"), description_form: "")
  let #(m, _) = client.update(m0, model.DescriptionSubmitted)
  assert m == m0
}

pub fn editing_node_renders_descriptions_test() {
  let n = node("node:1", "Shire", "Place")
  let d = shared.Description("description:1", "node:1", 0, "It is green.")
  let sim =
    start()
    |> simulate.message(model.UniverseSelected(universe("u:1", "Middle Earth")))
    |> simulate.message(model.NodesLoaded(Ok([n])))
    |> simulate.message(model.NodeEditStarted(n))
    |> simulate.message(model.DescriptionsLoaded(Ok([d])))
  assert query.has(simulate.view(sim), query.test_id("descriptions"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("description-body"), query.text("It is green.")),
  )
}

// ---- edge management ----

pub fn selecting_universe_loads_edges_test() {
  let #(m, _) =
    client.update(blank(), model.UniverseSelected(universe("u:1", "A")))
  assert m.edges == model.Loading
}

pub fn edges_loaded_sets_edges_test() {
  let e = edge("relationship:1", "knows")
  let #(m, _) = client.update(blank(), model.EdgesLoaded(Ok([e])))
  assert m.edges == model.Loaded([e])
}

pub fn edge_form_changes_apply_test() {
  let #(m, _) =
    blank()
    |> client.update(model.EdgeRelationshipChanged("was_at"))
    |> fn(p) { client.update(p.0, model.EdgeFromSelected("node:1")) }
  let #(m, _) = client.update(m, model.EdgeToSelected("node:2"))
  assert m.edge_form == model.EdgeForm("was_at", "node:1", "node:2")
}

pub fn edge_saved_clears_form_test() {
  let opened =
    model.Model(
      ..blank(),
      selected: Some(universe("u:1", "A")),
      edge_form: model.EdgeForm("knows", "node:1", "node:2"),
    )
  let #(m, _) =
    client.update(opened, model.EdgeSaved(Ok(edge("relationship:1", "knows"))))
  assert m.edge_form == model.EdgeForm("", "", "")
}

pub fn edge_body_test() {
  let form = model.EdgeForm("was_at", "node:1", "node:2")
  let expected =
    json.object([
      #("relationship", json.string("was_at")),
      #("from", json.string("node:1")),
      #("to", json.string("node:2")),
    ])
  assert json.to_string(model.edge_body(form)) == json.to_string(expected)
}

pub fn edge_submittable_requires_relationship_from_and_to_test() {
  assert model.edge_submittable(model.EdgeForm("knows", "node:1", "node:2"))
  assert !model.edge_submittable(model.EdgeForm("", "node:1", "node:2"))
  assert !model.edge_submittable(model.EdgeForm("knows", "", "node:2"))
  assert !model.edge_submittable(model.EdgeForm("knows", "node:1", ""))
  assert !model.edge_submittable(model.EdgeForm("knows", "", ""))
}

pub fn edge_selects_have_placeholder_option_test() {
  let sim =
    start()
    |> simulate.message(model.UniverseSelected(universe("u:1", "A")))
    |> simulate.message(
      model.NodesLoaded(Ok([node("node:1", "Alice", "Place")])),
    )
  assert query.has(
    simulate.view(sim),
    query.and(query.tag("option"), query.attribute("value", "")),
  )
}

// ---- filterable graph ----

pub fn selecting_universe_loads_graph_test() {
  let #(m, _) =
    client.update(blank(), model.UniverseSelected(universe("u:1", "A")))
  assert m.graph == model.Loading
  assert m.graph_filter == model.GraphFilter("", "", "", "", "")
}

pub fn graph_loaded_sets_graph_test() {
  let g = shared.Graph([node("node:1", "Shire", "Place")], [])
  let #(m, _) = client.update(blank(), model.GraphLoaded(Ok(g)))
  assert m.graph == model.Loaded(g)
}

pub fn graph_filter_changes_apply_test() {
  let #(m, _) =
    blank()
    |> client.update(model.GraphFromChanged("Gandalf"))
    |> fn(p) { client.update(p.0, model.GraphRelationshipChanged("befriends")) }
  let #(m, _) =
    m
    |> client.update(model.GraphToChanged("Person"))
    |> fn(p) { client.update(p.0, model.GraphFieldChanged("gender")) }
  let #(m, _) = client.update(m, model.GraphValueChanged("female"))
  assert m.graph_filter
    == model.GraphFilter("Gandalf", "befriends", "Person", "gender", "female")
}

pub fn graph_filter_applied_reloads_test() {
  let opened = model.Model(..blank(), selected: Some(universe("u:1", "A")))
  let #(m, _) = client.update(opened, model.GraphFilterApplied)
  assert m.graph == model.Loading
}

pub fn graph_filter_cleared_resets_and_reloads_test() {
  let filter = model.GraphFilter("Gandalf", "befriends", "Person", "", "")
  let opened =
    model.Model(
      ..blank(),
      selected: Some(universe("u:1", "A")),
      graph_filter: filter,
    )
  let #(m, _) = client.update(opened, model.GraphFilterCleared)
  assert m.graph == model.Loading
  assert m.graph_filter == model.empty_graph_filter
}

pub fn graph_query_only_includes_set_fields_test() {
  assert model.graph_query(model.GraphFilter("", "", "", "", "")) == ""
  assert model.graph_query(model.GraphFilter(
      "Gandalf",
      "befriends",
      "Person",
      "gender",
      "male",
    ))
    == "?from=Gandalf&relationship=befriends&to=Person&field=gender&value=male"
}

// ---- timeline ----

pub fn selecting_universe_loads_timeline_test() {
  let #(m, _) =
    client.update(blank(), model.UniverseSelected(universe("u:1", "A")))
  assert m.timeline == model.Loading
}

pub fn timeline_loaded_sets_timeline_test() {
  let ev =
    node_f("node:e1", "Fall", "Event", [#("when", shared.StringValue("3019"))])
  let g = shared.Graph([ev], [])
  let #(m, _) = client.update(blank(), model.TimelineLoaded(Ok(g)))
  assert m.timeline == model.Loaded(g)
}

pub fn selected_view_shows_timeline_test() {
  let ev =
    node_f("node:e1", "Fall of Sauron", "Event", [
      #("when", shared.StringValue("3019-03-25")),
    ])
  let shire = node("node:p1", "Shire", "Place")
  let link =
    shared.Edge("relationship:1", "u:1", "happened_at", "node:e1", "node:p1")
  let g = shared.Graph([ev], [link])
  let sim =
    start()
    |> simulate.message(model.UniverseSelected(universe("u:1", "Middle Earth")))
    |> simulate.message(model.NodesLoaded(Ok([ev, shire])))
    |> simulate.message(model.TimelineLoaded(Ok(g)))
  assert query.has(simulate.view(sim), query.test_id("timeline"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("timeline-name"), query.text("Fall of Sauron")),
  )
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("timeline-when"), query.text("3019-03-25")),
  )
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("timeline-link"), query.text("happened_at → Shire")),
  )
}

fn start() {
  simulate.application(client.init, client.update, view.view)
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
      model.UniversesLoaded(
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
    |> simulate.message(model.UniversesLoaded(Error(rsvp.BadBody)))
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
  let n = node("node:1", "Shire", "Place")
  let sim =
    start()
    |> simulate.message(model.UniverseSelected(universe("u:1", "Middle Earth")))
    |> simulate.message(model.NodesLoaded(Ok([n])))
  assert query.has(simulate.view(sim), query.test_id("node-form"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("node-name"), query.text("Shire")),
  )
}

pub fn selected_view_shows_graph_filter_and_container_test() {
  let g = shared.Graph([node("node:1", "Shire", "Place")], [])
  let sim =
    start()
    |> simulate.message(model.UniverseSelected(universe("u:1", "Middle Earth")))
    |> simulate.message(model.GraphLoaded(Ok(g)))
  assert query.has(simulate.view(sim), query.test_id("graph-filter"))
  assert query.has(simulate.view(sim), query.test_id("graph"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("graph-summary"), query.text("1 nodes, 0 edges")),
  )
}

// ---- smart graph-filter autocomplete ----

fn linked(id: String, relationship: String, from: String, to: String) -> shared.Edge {
  shared.Edge(id, "u:1", relationship, from, to)
}

fn graph_model(filter: model.GraphFilter) -> model.Model {
  let nodes = [
    node_f("n:g", "Gandalf", "Person", [#("gender", shared.StringValue("male"))]),
    node_f("n:f", "Frodo", "Person", [#("gender", shared.StringValue("male"))]),
    node("n:s", "Shire", "Place"),
    node_f("n:t", "Sting", "Generic", [
      #("material", shared.StringValue("elvish")),
    ]),
  ]
  let edges = [
    linked("e:1", "befriends", "n:g", "n:f"),
    linked("e:2", "visits", "n:g", "n:s"),
    linked("e:3", "forged", "n:g", "n:t"),
  ]
  model.Model(
    ..blank(),
    nodes: model.Loaded(nodes),
    edges: model.Loaded(edges),
    graph_filter: filter,
  )
}

pub fn from_options_offer_source_names_and_kinds_test() {
  let opts = model.graph_from_options(graph_model(model.empty_graph_filter))
  assert opts == ["Gandalf", "Person"]
}

pub fn to_options_are_limited_by_relationship_test() {
  let m = graph_model(model.GraphFilter("", "visits", "", "", ""))
  assert model.graph_to_options(m) == ["Place", "Shire"]
}

pub fn relationship_options_are_limited_by_endpoints_test() {
  let m = graph_model(model.GraphFilter("", "", "Frodo", "", ""))
  assert model.graph_relationship_options(m) == ["befriends"]
}

pub fn field_options_come_from_candidate_nodes_test() {
  let all = model.graph_field_options(graph_model(model.empty_graph_filter))
  assert all == ["gender", "material"]
  let scoped =
    model.graph_field_options(graph_model(model.GraphFilter(
      "",
      "visits",
      "",
      "",
      "",
    )))
  assert scoped == ["gender"]
}

pub fn value_options_follow_selected_field_test() {
  assert model.graph_value_options(graph_model(model.empty_graph_filter)) == []
  let m = graph_model(model.GraphFilter("", "", "", "material", ""))
  assert model.graph_value_options(m) == ["elvish"]
}

pub fn from_options_are_limited_by_destination_test() {
  let m = graph_model(model.GraphFilter("", "", "Person", "", ""))
  assert model.graph_from_options(m) == ["Gandalf", "Person"]
}

pub fn selected_view_shows_edge_form_and_list_test() {
  let e = edge("relationship:1", "was_at")
  let sim =
    start()
    |> simulate.message(model.UniverseSelected(universe("u:1", "Middle Earth")))
    |> simulate.message(model.EdgesLoaded(Ok([e])))
  assert query.has(simulate.view(sim), query.test_id("edge-form"))
  assert query.has(
    simulate.view(sim),
    query.and(query.test_id("edge-relationship"), query.text("was_at")),
  )
}
