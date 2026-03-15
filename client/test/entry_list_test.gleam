import components/entry_list
import gleam/http/response
import gleam/json
import lustre/dev/query
import lustre/dev/simulate
import shared/character
import shared/entry
import youid/uuid

pub fn set_character_test() {
  let app =
    simulate.application(
      init: entry_list.init,
      update: entry_list.update,
      view: entry_list.view,
    )
  let c = character.Character(id: uuid.nil, name: "Gandalf")

  let result =
    simulate.start(app, Nil)
    |> simulate.message(entry_list.SetCharacter(c))
    |> simulate.model

  assert result.character == c
  assert result.entries == []
}

pub fn entries_loaded_test() {
  let app =
    simulate.application(
      init: entry_list.init,
      update: entry_list.update,
      view: entry_list.view,
    )
  let c = character.Character(id: uuid.nil, name: "Gandalf")
  let e =
    entry.Entry(id: uuid.nil, character_id: uuid.nil, text: "A journal entry")
  let body = entry.entry_list_to_json([e]) |> json.to_string
  let resp = response.Response(200, [], body)

  let sim =
    simulate.start(app, Nil)
    |> simulate.message(entry_list.SetCharacter(c))
    |> simulate.message(entry_list.EntriesLoaded(Ok(resp)))

  assert simulate.model(sim).entries == [e]

  let assert Ok(_) =
    query.find(
      in: simulate.view(sim),
      matching: query.element(matching: query.text("A journal entry")),
    )
}

pub fn typing_updates_model_test() {
  let app =
    simulate.application(
      init: entry_list.init,
      update: entry_list.update,
      view: entry_list.view,
    )
  let textarea_q = query.element(matching: query.tag("textarea"))

  let result =
    simulate.start(app, Nil)
    |> simulate.input(on: textarea_q, value: "My new entry")
    |> simulate.model

  assert result.new_text == "My new entry"
}

pub fn empty_submit_does_nothing_test() {
  let app =
    simulate.application(
      init: entry_list.init,
      update: entry_list.update,
      view: entry_list.view,
    )
  let add_button = query.element(matching: query.tag("button"))

  let result =
    simulate.start(app, Nil)
    |> simulate.click(on: add_button)
    |> simulate.model

  assert result.new_text == ""
  assert result.entries == []
}

pub fn submit_adds_entry_test() {
  let app =
    simulate.application(
      init: entry_list.init,
      update: entry_list.update,
      view: entry_list.view,
    )
  let textarea_q = query.element(matching: query.tag("textarea"))
  let add_button = query.element(matching: query.tag("button"))
  let c = character.Character(id: uuid.nil, name: "Gandalf")
  let new_entry =
    entry.Entry(id: uuid.nil, character_id: uuid.nil, text: "A new entry")
  let body = entry.entry_to_json(new_entry) |> json.to_string
  let resp = response.Response(200, [], body)

  let result =
    simulate.start(app, Nil)
    |> simulate.message(entry_list.SetCharacter(c))
    |> simulate.input(on: textarea_q, value: "A new entry")
    |> simulate.click(on: add_button)
    |> simulate.message(entry_list.SubmitResponse(Ok(resp)))
    |> simulate.model

  assert result.new_text == ""
  assert result.entries == [new_entry]
}

pub fn delete_entry_test() {
  let app =
    simulate.application(
      init: entry_list.init,
      update: entry_list.update,
      view: entry_list.view,
    )
  let c = character.Character(id: uuid.nil, name: "Gandalf")
  let e =
    entry.Entry(id: uuid.nil, character_id: uuid.nil, text: "To be deleted")
  let entries_body = entry.entry_list_to_json([e]) |> json.to_string
  let entries_resp = response.Response(200, [], entries_body)
  let delete_resp = response.Response(200, [], "")

  let result =
    simulate.start(app, Nil)
    |> simulate.message(entry_list.SetCharacter(c))
    |> simulate.message(entry_list.EntriesLoaded(Ok(entries_resp)))
    |> simulate.message(entry_list.DeleteResponse(e.id, Ok(delete_resp)))
    |> simulate.model

  assert result.entries == []
}
