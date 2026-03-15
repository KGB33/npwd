import gleam/http
import gleam/json
import pog
import router
import shared/character
import sql
import test_helpers.{create_test_context, refresh_database}
import wisp/simulate
import youid/uuid

pub fn save_character_test() {
  let ctx = create_test_context()

  let test_name = "A Test Name"
  let payload =
    json.object([
      #("name", json.string(test_name)),
      #("id", json.string(uuid.to_string(uuid.nil))),
    ])
  let response =
    simulate.browser_request(http.Post, "/api/character")
    |> simulate.json_body(payload)
    |> router.handle_request(fn() { ctx })

  assert response.status == 201
  let assert Ok(resp_chara) =
    response
    |> simulate.read_body()
    |> json.parse(character.character_decoder())
  assert resp_chara.name == test_name

  let assert Ok(characters) = sql.get_characters_by_id(ctx.db, resp_chara.id)
  assert characters.count == 1
  assert characters.rows == [sql.GetCharactersByIdRow(resp_chara.id, test_name)]
}

pub fn save_character_empty_name_test() {
  let ctx = create_test_context()
  let payload =
    json.object([
      #("name", json.string("")),
      #("id", json.string(uuid.to_string(uuid.nil))),
    ])
  let response =
    simulate.browser_request(http.Post, "/api/character")
    |> simulate.json_body(payload)
    |> router.handle_request(fn() { ctx })

  assert response.status == 400
}

pub fn update_character_test() {
  let ctx = create_test_context()
  refresh_database(ctx.db)

  let assert Ok(pog.Returned(1, [sql.InsertCharacterRow(id, _name)])) =
    sql.insert_character(ctx.db, "test name")

  let payload =
    json.object([
      #("name", json.string("new test name")),
      #("id", json.string(uuid.to_string(id))),
    ])

  let response =
    simulate.browser_request(
      http.Patch,
      "/api/character/" <> uuid.to_string(id),
    )
    |> simulate.json_body(payload)
    |> router.handle_request(fn() { ctx })

  assert response.status == 200

  let assert Ok(resp_chara) =
    response
    |> simulate.read_body()
    |> json.parse(character.character_decoder())

  assert resp_chara.name == "new test name"
  assert resp_chara.id == id

  let assert Ok(pog.Returned(1, [db_chara])) =
    sql.get_characters_by_id(ctx.db, id)

  assert db_chara.id == id
  assert db_chara.name == "new test name"
}

pub fn delete_character_test() {
  let ctx = create_test_context()
  refresh_database(ctx.db)

  let assert Ok(pog.Returned(1, [sql.InsertCharacterRow(id, _name)])) =
    sql.insert_character(ctx.db, "test name")

  let response =
    simulate.browser_request(
      http.Delete,
      "/api/character/" <> uuid.to_string(id),
    )
    |> router.handle_request(fn() { ctx })

  assert response.status == 200

  let assert Ok(pog.Returned(0, [])) = sql.get_characters_by_id(ctx.db, id)
}
