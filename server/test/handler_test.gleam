import context
import gleam/erlang/process
import gleam/http
import gleam/json
import pog
import router
import shared/character
import sql
import wisp
import wisp/simulate
import youid/uuid

fn create_test_context() {
  let name = process.new_name("db-pool")
  let assert Ok(actor) =
    pog.default_config(name)
    |> pog.host("localhost")
    |> pog.database("test")
    |> pog.user("kgb33")
    |> pog.pool_size(15)
    |> pog.start

  let assert Ok(priv_dir) = wisp.priv_directory("server")
  let static_dir = priv_dir <> "/static"

  context.Context(db: actor.data, static_dir: static_dir)
}

fn refresh_database(db: pog.Connection) {
  let assert Ok(_) =
    pog.query(
      // sql
      "
      DELETE FROM characters;
    ",
    )
    |> pog.execute(db)
  Nil
}

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
    |> router.handle_request(create_test_context)

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
    |> router.handle_request(create_test_context)

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
    |> router.handle_request(create_test_context)

  assert response.status == 200

  let assert Ok(pog.Returned(0, [])) = sql.get_characters_by_id(ctx.db, id)
}
