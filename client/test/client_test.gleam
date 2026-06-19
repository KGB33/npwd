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
  )
}

fn universe(id: String, name: String) -> shared.Universe {
  shared.Universe(id, name, "")
}

fn node(id: String, name: String, kind: shared.NodeKind) -> shared.Node {
  shared.Node(id, "u:1", kind, name, "")
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
