import client
import gleam/option
import gleeunit
import lustre/dev/query
import lustre/dev/simulate
import shared/character
import youid/uuid

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn character_created_test() {
  let app =
    simulate.application(
      init: client.init,
      update: client.update,
      view: client.view,
    )
  let c = character.Character(id: uuid.nil, name: "Gandalf")

  let result =
    simulate.start(app, [])
    |> simulate.message(client.CharacterCreated(c))
    |> simulate.model

  assert result.characters == [c]
}

pub fn character_deleted_test() {
  let app =
    simulate.application(
      init: client.init,
      update: client.update,
      view: client.view,
    )
  let c = character.Character(id: uuid.nil, name: "Gandalf")

  let result =
    simulate.start(app, [])
    |> simulate.message(client.CharacterCreated(c))
    |> simulate.message(client.CharacterSelected(c))
    |> simulate.message(client.CharacterDeleted(c.id))
    |> simulate.model

  assert result.characters == []
  assert result.selected_character == option.None
}

pub fn character_selected_test() {
  let app =
    simulate.application(
      init: client.init,
      update: client.update,
      view: client.view,
    )
  let c = character.Character(id: uuid.nil, name: "Frodo")

  let result =
    simulate.start(app, [])
    |> simulate.message(client.CharacterSelected(c))
    |> simulate.model

  assert result.selected_character == option.Some(c)
}

pub fn view_no_selection_test() {
  let app =
    simulate.application(
      init: client.init,
      update: client.update,
      view: client.view,
    )
  let p_text =
    query.element(matching: query.text(
      "Select a character to view their entries.",
    ))

  let html = simulate.start(app, []) |> simulate.view

  let assert Ok(_) = query.find(in: html, matching: p_text)
}

pub fn view_with_selection_test() {
  let app =
    simulate.application(
      init: client.init,
      update: client.update,
      view: client.view,
    )
  let c = character.Character(id: uuid.nil, name: "Aragorn")
  let entry_list_el = query.element(matching: query.tag("entry-list"))

  let html =
    simulate.start(app, [])
    |> simulate.message(client.CharacterSelected(c))
    |> simulate.view

  let assert Ok(_) = query.find(in: html, matching: entry_list_el)
}
