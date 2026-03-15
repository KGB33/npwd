import components/character_form
import gleam/http/response
import gleam/json
import gleam/option
import lustre/dev/query
import lustre/dev/simulate
import rsvp
import shared/character
import youid/uuid

pub fn typing_updates_model_test() {
  let app =
    simulate.application(
      init: character_form.init,
      update: character_form.update,
      view: character_form.view,
    )
  let name_input = query.element(matching: query.tag("input"))

  let result =
    simulate.start(app, Nil)
    |> simulate.input(on: name_input, value: "Gandalf")
    |> simulate.model

  assert result.name == "Gandalf"
}

pub fn empty_submit_does_nothing_test() {
  let app =
    simulate.application(
      init: character_form.init,
      update: character_form.update,
      view: character_form.view,
    )
  let add_button = query.element(matching: query.tag("button"))

  let result =
    simulate.start(app, Nil)
    |> simulate.click(on: add_button)
    |> simulate.model

  assert result.name == ""
  assert result.io_wait == False
  assert result.error == option.None
}

pub fn submit_clears_form_on_success_test() {
  let app =
    simulate.application(
      init: character_form.init,
      update: character_form.update,
      view: character_form.view,
    )
  let name_input = query.element(matching: query.tag("input"))
  let add_button = query.element(matching: query.tag("button"))
  let created = character.Character(id: uuid.nil, name: "Gandalf")
  let body = character.character_to_json(created) |> json.to_string
  let resp = response.Response(200, [], body)

  let result =
    simulate.start(app, Nil)
    |> simulate.input(on: name_input, value: "Gandalf")
    |> simulate.click(on: add_button)
    |> simulate.message(character_form.CreateResponse(Ok(resp)))
    |> simulate.model

  assert result.name == ""
  assert result.error == option.None
}

pub fn submit_shows_error_on_failure_test() {
  let app =
    simulate.application(
      init: character_form.init,
      update: character_form.update,
      view: character_form.view,
    )
  let name_input = query.element(matching: query.tag("input"))
  let add_button = query.element(matching: query.tag("button"))

  let result =
    simulate.start(app, Nil)
    |> simulate.input(on: name_input, value: "Gandalf")
    |> simulate.click(on: add_button)
    |> simulate.message(character_form.CreateResponse(Error(rsvp.BadBody)))
    |> simulate.model

  assert result.error == option.Some("Failed to save")
}

pub fn button_disabled_during_io_test() {
  let app =
    simulate.application(
      init: character_form.init,
      update: character_form.update,
      view: character_form.view,
    )
  let name_input = query.element(matching: query.tag("input"))
  let disabled_button =
    query.element(
      matching: query.tag("button")
      |> query.and(query.attribute("disabled", "")),
    )

  let sim =
    simulate.start(app, Nil)
    |> simulate.input(on: name_input, value: "Gandalf")
    |> simulate.message(character_form.Create)

  assert simulate.model(sim).io_wait == True

  let assert Ok(_) =
    query.find(in: simulate.view(sim), matching: disabled_button)
}
