import client
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
  )
}

fn universe(id: String, name: String) -> shared.Universe {
  shared.Universe(id, name, "")
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
    client.Model(
      universes: client.Loading,
      form: client.Form("x", "y"),
      editing: Some("u:7"),
    )
  let #(m, _) = client.update(editing, client.EditCancelled)
  assert m.editing == None
  assert m.form == client.Form("", "")
}

pub fn saved_clears_form_test() {
  let editing =
    client.Model(
      universes: client.Loading,
      form: client.Form("x", "y"),
      editing: Some("u:7"),
    )
  let #(m, _) = client.update(editing, client.Saved(Ok(universe("u:7", "x"))))
  assert m.editing == None
  assert m.form == client.Form("", "")
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
