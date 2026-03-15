import db/character as character_db
import db/entry as entry_db
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/list
import router
import shared/entry.{type Entry}
import test_helpers.{create_test_context, refresh_database}
import wisp/simulate
import youid/uuid

pub fn list_entries_empty_test() {
  let ctx = create_test_context()
  refresh_database(ctx.db)

  let assert Ok(char) = character_db.insert(ctx.db, "Test Character")

  let response =
    simulate.browser_request(
      http.Get,
      "/api/character/" <> uuid.to_string(char.id) <> "/entries",
    )
    |> router.handle_request(fn() { ctx })

  assert response.status == 200

  let assert Ok(entries) =
    response
    |> simulate.read_body()
    |> json.parse(decode.list(entry.entry_decoder()))

  assert entries == []
}

pub fn list_entries_test() {
  let ctx = create_test_context()
  refresh_database(ctx.db)

  let assert Ok(char) = character_db.insert(ctx.db, "Test Character")
  let assert Ok(_) = entry_db.insert(ctx.db, char.id, "First entry")
  let assert Ok(_) = entry_db.insert(ctx.db, char.id, "Second entry")

  let response =
    simulate.browser_request(
      http.Get,
      "/api/character/" <> uuid.to_string(char.id) <> "/entries",
    )
    |> router.handle_request(fn() { ctx })

  assert response.status == 200

  let assert Ok(entries) =
    response
    |> simulate.read_body()
    |> json.parse(decode.list(entry.entry_decoder()))

  assert list.length(entries) == 2
  assert list.any(entries, fn(e: Entry) { e.text == "First entry" })
  assert list.any(entries, fn(e: Entry) { e.text == "Second entry" })
}

pub fn list_entries_invalid_id_test() {
  let ctx = create_test_context()

  let response =
    simulate.browser_request(http.Get, "/api/character/not-a-uuid/entries")
    |> router.handle_request(fn() { ctx })

  assert response.status == 400
}

pub fn save_entry_test() {
  let ctx = create_test_context()
  refresh_database(ctx.db)

  let assert Ok(char) = character_db.insert(ctx.db, "Test Character")

  let payload =
    json.object([
      #("character_id", json.string(uuid.to_string(char.id))),
      #("text", json.string("My journal entry")),
    ])

  let response =
    simulate.browser_request(http.Post, "/api/entry")
    |> simulate.json_body(payload)
    |> router.handle_request(fn() { ctx })

  assert response.status == 201

  let assert Ok(resp_entry) =
    response
    |> simulate.read_body()
    |> json.parse(entry.entry_decoder())

  assert resp_entry.character_id == char.id
  assert resp_entry.text == "My journal entry"

  let assert Ok(db_entries) = entry_db.list_by_character(ctx.db, char.id)
  assert list.length(db_entries) == 1
  let assert [db_entry] = db_entries
  assert db_entry.id == resp_entry.id
}

pub fn save_entry_empty_text_test() {
  let ctx = create_test_context()
  refresh_database(ctx.db)

  let assert Ok(char) = character_db.insert(ctx.db, "Test Character")

  let payload =
    json.object([
      #("character_id", json.string(uuid.to_string(char.id))),
      #("text", json.string("")),
    ])

  let response =
    simulate.browser_request(http.Post, "/api/entry")
    |> simulate.json_body(payload)
    |> router.handle_request(fn() { ctx })

  assert response.status == 400
}

pub fn save_entry_invalid_character_id_test() {
  let ctx = create_test_context()

  let payload =
    json.object([
      #("character_id", json.string("bad-uuid")),
      #("text", json.string("x")),
    ])

  let response =
    simulate.browser_request(http.Post, "/api/entry")
    |> simulate.json_body(payload)
    |> router.handle_request(fn() { ctx })

  assert response.status == 400
}

pub fn delete_entry_test() {
  let ctx = create_test_context()
  refresh_database(ctx.db)

  let assert Ok(char) = character_db.insert(ctx.db, "Test Character")
  let assert Ok(e) = entry_db.insert(ctx.db, char.id, "To be deleted")

  let response =
    simulate.browser_request(http.Delete, "/api/entry/" <> uuid.to_string(e.id))
    |> router.handle_request(fn() { ctx })

  assert response.status == 200

  let assert Ok(db_entries) = entry_db.list_by_character(ctx.db, char.id)
  assert db_entries == []
}

pub fn delete_entry_not_found_test() {
  let ctx = create_test_context()
  let random_id = uuid.v7()

  let response =
    simulate.browser_request(
      http.Delete,
      "/api/entry/" <> uuid.to_string(random_id),
    )
    |> router.handle_request(fn() { ctx })

  assert response.status == 404
}
